// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using Whisper.net;

namespace JustSayIt;

public record NoteLine(string Speaker, double Time, string Text);

/// Records a conversation: your microphone ("Me") and, optionally, the computer's
/// sound ("Others", e.g. people on a call). Transcribes on-device with Whisper in
/// short chunks while you talk, then writes a Markdown note with an optional summary.
public sealed class NoteTaker
{
    public static NoteTaker Shared { get; } = new();

    public bool IsRecording { get; private set; }
    public DateTime StartedAt { get; private set; }
    public string Status { get; private set; } = "";
    public string? LastNotePath { get; private set; }
    public readonly List<NoteLine> Lines = new();
    public event Action? Changed;

    public static string NotesDir
    {
        get
        {
            var d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Just Say It Notes");
            Directory.CreateDirectory(d);
            return d;
        }
    }

    sealed class Source
    {
        public string Speaker = "";
        public IWaveIn? Capture;
        public WaveFormat? Format;
        public readonly List<float> Pending = new();
        public double Offset;        // seconds already transcribed
        public readonly object Gate = new();
    }

    readonly List<Source> sources = new();
    WhisperFactory? factory;
    CancellationTokenSource? cts;
    Task? worker;
    string? filePath;
    string context = "";
    UpcomingMeeting? meeting;
    readonly object linesGate = new();

    const int Rate = 16000;
    const double ChunkSeconds = 12;

    public void Toggle()
    {
        if (IsRecording) _ = Stop(); else _ = Start();
    }

    /// What started the current recording.
    public enum Origin { Manual, Calendar, Call }
    public Origin CurrentOrigin { get; private set; } = Origin.Manual;

    public Task Start() => Start(null, Origin.Manual);

    public Task Start(UpcomingMeeting? m) => Start(m, m == null ? Origin.Manual : Origin.Calendar);

    public async Task Start(UpcomingMeeting? m, Origin origin)
    {
        if (IsRecording) return;
        meeting = m;
        CurrentOrigin = origin;
        var p = Store.Shared.Prefs;
        Lines.Clear();
        Set("Starting…");
        try
        {
            await Transcriber.EnsureModel(p.Model);
            factory ??= WhisperFactory.FromPath(Transcriber.ModelPath(p.Model));
        }
        catch (Exception e) { Set("Couldn't load the speech model: " + e.Message); return; }

        context = meeting != null ? $"{MeetingLinks.Name(meeting.Link.Platform)} – {meeting.Title}" : ContextReader.Capture().AppName;
        sources.Clear();
        try
        {
            AddSource("Me", new WaveIn { WaveFormat = new WaveFormat(Rate, 16, 1), BufferMilliseconds = 100 });
            if (p.NoteCaptureSystemAudio)
            {
#pragma warning disable CS0618 // system-wide loopback; the replacement API is process-specific
                try { AddSource("Others", new WasapiLoopbackCapture()); } catch { }
#pragma warning restore CS0618
            }
            foreach (var s in sources) s.Capture!.StartRecording();
        }
        catch (Exception e)
        {
            Set("Microphone error: " + e.Message);
            StopCaptures();
            return;
        }

        StartedAt = DateTime.Now;
        IsRecording = true;
        Set(sources.Count > 1 ? "Recording you and computer audio" : "Recording your microphone");
        var title = meeting == null ? "Note" : string.Join("-", meeting.Title.Split(Path.GetInvalidFileNameChars())).Trim();
        if (title.Length > 60) title = title[..60];
        var name = $"{DateTime.Now:yyyy-MM-dd HH.mm} {title}.md";
        filePath = Path.Combine(NotesDir, name);
        WriteFile(null);
        cts = new CancellationTokenSource();
        var token = cts.Token;
        worker = Task.Run(() => Loop(token));
        if (p.PlaySounds) System.Media.SystemSounds.Asterisk.Play();
    }

    public async Task Stop()
    {
        if (!IsRecording) return;
        IsRecording = false;
        Set("Finishing transcript…");
        StopCaptures();
        cts?.Cancel();
        if (worker != null) { try { await worker; } catch { } }
        await Flush(force: true);
        if (Store.Shared.Prefs.PlaySounds) System.Media.SystemSounds.Exclamation.Play();

        if (Lines.Count == 0)
        {
            Set("Nothing was heard.");
            if (filePath != null) try { File.Delete(filePath); } catch { }
            return;
        }
        Set("Writing summary…");
        var summary = await Summarize();
        WriteFile(summary);
        LastNotePath = filePath;
        Set("Saved to Documents › Just Say It Notes");
        CollectivIQ.Send(meeting?.Title, TranscriptText(false));
    }

    void AddSource(string speaker, IWaveIn capture)
    {
        var s = new Source { Speaker = speaker, Capture = capture, Format = capture.WaveFormat };
        capture.DataAvailable += (_, e) =>
        {
            var samples = ToMono16k(e.Buffer, e.BytesRecorded, s.Format!);
            lock (s.Gate) s.Pending.AddRange(samples);
        };
        sources.Add(s);
    }

    void StopCaptures()
    {
        foreach (var s in sources)
        {
            try { s.Capture?.StopRecording(); } catch { }
            try { s.Capture?.Dispose(); } catch { }
        }
    }

    async Task Loop(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            try { await Task.Delay(1000, token); } catch { break; }
            await Flush(force: false);
        }
    }

    async Task Flush(bool force)
    {
        foreach (var s in sources)
        {
            float[] chunk;
            double start;
            lock (s.Gate)
            {
                int n = s.Pending.Count;
                if (n == 0 || (!force && n < Rate * ChunkSeconds)) continue;
                // Cut at the quietest point in the last 2 seconds so words aren't split.
                int cut = force ? n : QuietCut(s.Pending, n);
                chunk = s.Pending.GetRange(0, cut).ToArray();
                s.Pending.RemoveRange(0, cut);
                start = s.Offset;
                s.Offset += cut / (double)Rate;
            }
            if (Rms(chunk) < 0.004) continue; // silence
            var text = await Transcribe(chunk);
            if (string.IsNullOrWhiteSpace(text)) continue;
            Append(s.Speaker, start, text);
        }
    }

    static int QuietCut(List<float> buf, int n)
    {
        int window = Rate / 10, searchFrom = Math.Max(window, n - Rate * 2), best = n;
        double bestE = double.MaxValue;
        for (int i = searchFrom; i + window <= n; i += window / 2)
        {
            double e = 0;
            for (int j = i; j < i + window; j++) e += buf[j] * buf[j];
            if (e < bestE) { bestE = e; best = i + window / 2; }
        }
        return best;
    }

    static double Rms(float[] a)
    {
        double s = 0;
        foreach (var v in a) s += v * v;
        return Math.Sqrt(s / Math.Max(a.Length, 1));
    }

    async Task<string> Transcribe(float[] samples)
    {
        if (factory == null) return "";
        var p = Store.Shared.Prefs;
        await using var proc = factory.CreateBuilder()
            .WithLanguage(string.IsNullOrWhiteSpace(p.Language) ? "auto" : p.Language)
            .WithThreads(Math.Max(2, Environment.ProcessorCount - 1))
            .WithNoContext()
            .Build();
        var sb = new StringBuilder();
        await foreach (var seg in proc.ProcessAsync(samples)) sb.Append(seg.Text);
        var t = sb.ToString().Trim();
        t = System.Text.RegularExpressions.Regex.Replace(t, @"\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE)[^\]]*\]", "").Trim();
        return t;
    }

    void Append(string speaker, double time, string text)
    {
        lock (linesGate)
        {
            Lines.Add(new NoteLine(speaker, time, text));
            Lines.Sort((a, b) => a.Time.CompareTo(b.Time));
        }
        WriteFile(null);
        Changed?.Invoke();
    }

    public static string Stamp(double t)
    {
        var s = (int)t;
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60:00}:{s % 60:00}";
    }

    public string TranscriptText(bool timestamps = true)
    {
        lock (linesGate)
            return string.Join(timestamps ? "\n\n" : "\n",
                Lines.Select(l => timestamps ? $"**{Stamp(l.Time)} {l.Speaker}:** {l.Text}" : $"{l.Speaker}: {l.Text}"));
    }

    void WriteFile(string? summary)
    {
        if (filePath == null) return;
        var md = new StringBuilder();
        md.AppendLine(meeting != null ? $"# {meeting.Title}\n" : $"# Note – {StartedAt:dddd, MMMM d, yyyy h:mm tt}\n");
        md.AppendLine($"*Recorded with Just Say It · {StartedAt:f} · {Stamp((DateTime.Now - StartedAt).TotalSeconds)} · {context}*\n");
        if (meeting != null && meeting.Attendees.Count > 0) md.AppendLine("**Attendees:** " + string.Join(", ", meeting.Attendees) + "\n");
        if (!string.IsNullOrWhiteSpace(summary)) md.AppendLine(summary.Trim() + "\n");
        md.AppendLine("## Transcript\n");
        md.AppendLine(TranscriptText());
        try { File.WriteAllText(filePath, md.ToString()); } catch { }
    }

    async Task<string?> Summarize()
    {
        var transcript = TranscriptText(false);
        if (meeting != null) transcript = $"Meeting: {meeting.Title}\nAttendees: {string.Join(", ", meeting.Attendees)}\n\n" + transcript;
        if (transcript.Length > 9000) transcript = transcript[..4500] + "\n…\n" + transcript[^4500..];
        return await TextBrain.SummarizeMeeting(transcript);
    }

    void Set(string s) { Status = s; Changed?.Invoke(); }

    /// Converts any capture format (16-bit or 32-bit float, any rate, any channels) to 16 kHz mono floats.
    static float[] ToMono16k(byte[] buf, int bytes, WaveFormat f)
    {
        int ch = f.Channels;
        bool isFloat = f.Encoding == WaveFormatEncoding.IeeeFloat || (f.Encoding == WaveFormatEncoding.Extensible && f.BitsPerSample == 32);
        int bps = f.BitsPerSample / 8;
        int frames = bytes / (bps * ch);
        var mono = new float[frames];
        for (int i = 0; i < frames; i++)
        {
            float sum = 0;
            for (int c = 0; c < ch; c++)
            {
                int o = (i * ch + c) * bps;
                sum += isFloat ? BitConverter.ToSingle(buf, o) : BitConverter.ToInt16(buf, o) / 32768f;
            }
            mono[i] = sum / ch;
        }
        if (f.SampleRate == Rate) return mono;
        double ratio = (double)f.SampleRate / Rate;
        int outLen = (int)(frames / ratio);
        var res = new float[outLen];
        for (int i = 0; i < outLen; i++)
        {
            double pos = i * ratio;
            int a = (int)pos;
            int b = Math.Min(a + 1, frames - 1);
            float frac = (float)(pos - a);
            res[i] = mono[a] * (1 - frac) + mono[b] * frac;
        }
        return res;
    }
}
