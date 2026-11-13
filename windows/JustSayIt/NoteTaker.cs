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
    /// Setting up the microphone and speech model (before IsRecording), or transcribing the last audio after a stop.
    public bool IsStarting { get; private set; }
    bool flushing;
    int finishing;
    /// Recording, starting, or still saving a finished one.
    public bool IsBusy => IsRecording || IsStarting || flushing || Volatile.Read(ref finishing) > 0;
    public DateTime StartedAt { get; private set; }
    public string Status { get; private set; } = "";
    public string? LastNotePath { get; private set; }
    readonly List<NoteLine> Lines = new();
    DateTime captureStart;

    /// A thread-safe copy of the transcript lines.
    public NoteLine[] Snapshot() { lock (linesGate) return Lines.ToArray(); }
    public int LineCount { get { lock (linesGate) return Lines.Count; } }
    /// Transcript rewritten for clarity (filled in when a recording stops).
    public string? SmartTranscript { get; private set; }
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
        if (IsRecording) EndByUser(); else if (!IsBusyStarting) _ = Start();
    }

    /// The "End Note Taker" button (and Right Shift ×3 while recording): finish now and send right away.
    public void EndByUser()
    {
        if (!IsRecording) return;
        if (CurrentOrigin == Origin.Call) CallWatcher.Shared.EndByUser(); else _ = Stop(sendImmediately: true);
    }

    /// What started the current recording.
    public enum Origin { Manual, Calendar, Call }
    public Origin CurrentOrigin { get; private set; } = Origin.Manual;

    public Task Start() => Start(null, Origin.Manual);

    public Task Start(UpcomingMeeting? m) => Start(m, m == null ? Origin.Manual : Origin.Calendar);

    bool IsBusyStarting => IsStarting || flushing;

    /// Starts a recording. Returns false if one is already running/starting or it couldn't start.
    public Task<bool> Start(UpcomingMeeting? m, Origin origin) => Ui.Context == null || SynchronizationContext.Current == Ui.Context
        ? StartCore(m, origin)
        : RunOnUi(() => StartCore(m, origin));

    static Task<bool> RunOnUi(Func<Task<bool>> f)
    {
        var tcs = new TaskCompletionSource<bool>();
        Ui.Context!.Post(async _ => { try { tcs.SetResult(await f()); } catch (Exception e) { tcs.SetException(e); } }, null);
        return tcs.Task;
    }

    async Task<bool> StartCore(UpcomingMeeting? m, Origin origin)
    {
        if (IsRecording || IsBusyStarting || Updater.Shared.Installing) return false;
        IsStarting = true;
        try { return await StartInner(m, origin); }
        finally { IsStarting = false; Changed?.Invoke(); }
    }

    async Task<bool> StartInner(UpcomingMeeting? m, Origin origin)
    {
        meeting = m;
        CurrentOrigin = origin;
        var p = Store.Shared.Prefs;
        filePath = null;
        SmartTranscript = null;
        CaptionConnector.Shared.Reset();
        lock (linesGate) Lines.Clear();
        Set("Starting…");
        try
        {
            await Transcriber.EnsureModel(p.Model);
            factory ??= WhisperFactory.FromPath(Transcriber.ModelPath(p.Model));
        }
        catch (Exception e) { Set("Couldn't load the speech model: " + e.Message); return false; }

        context = meeting != null ? $"{MeetingLinks.Name(meeting.Link.Platform)} – {meeting.Title}" : ContextReader.Capture().AppName;
        sources.Clear();
        try
        {
            captureStart = DateTime.Now;
            // WaveInEvent works from any thread (WaveIn needs a window message loop).
            AddSource("Me", new WaveInEvent { WaveFormat = new WaveFormat(Rate, 16, 1), BufferMilliseconds = 100 });
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
            return false;
        }

        StartedAt = captureStart;
        IsRecording = true;
        Set(sources.Count > 1 ? "Recording you and computer audio" : "Recording your microphone");
        var title = meeting == null ? "Note" : string.Join("-", meeting.Title.Split(Path.GetInvalidFileNameChars())).Trim();
        if (title.Length > 60) title = title[..60];
        // Never overwrite an earlier note (two calls with the same name in the same minute).
        var name = $"{DateTime.Now:yyyy-MM-dd HH.mm} {title}.txt";
        for (int i = 2; File.Exists(Path.Combine(NotesDir, name)); i++) name = $"{DateTime.Now:yyyy-MM-dd HH.mm} {title} ({i}).txt";
        SmartTranscript = null;
        filePath = Path.Combine(NotesDir, name);
        WriteFile(null);
        CaptionConnector.Shared.Start(CurrentOrigin == Origin.Call ? CallWatcher.Shared.ActiveCall?.Service.Id ?? "" : "");
        cts = new CancellationTokenSource();
        var token = cts.Token;
        worker = Task.Run(() => Loop(token));
        if (p.PlaySounds) System.Media.SystemSounds.Asterisk.Play();
        _ = Ui.Run(() => Controller.Shared.Overlay.ShowState(OverlayState.NoteTaker));
        return true;
    }

    /// Finishes the recording. With sendImmediately (call ended / End Note Taker) the notes go to
    /// CollectivIQ straight away using the saved defaults, without any questions.
    public async Task Stop(bool sendImmediately = false)
    {
        if (!IsRecording) return;
        IsRecording = false;
        flushing = true;
        Interlocked.Increment(ref finishing);
        try
        {
            Set("Finishing transcript…");
            _ = Ui.Run(() => Controller.Shared.Overlay.ShowState(OverlayState.Hidden));
            StopCaptures();
            cts?.Cancel();
            if (worker != null) { try { await worker; } catch { } }
            try { await Flush(force: true); } catch { }
            if (Store.Shared.Prefs.PlaySounds) System.Media.SystemSounds.Exclamation.Play();

            // From here on work on a copy, so a new recording that starts meanwhile can't mix with this one.
            await Ui.Run(() => CaptionConnector.Shared.Stop());
            var note = new Note(Snapshot(), meeting, filePath, StartedAt, DateTime.Now, context) { Captions = CaptionConnector.Shared.Snapshot() };
            flushing = false;
            if (note.Lines.Length == 0 && note.Captions.Length == 0)
            {
                SetIdle("Nothing was heard.");
                if (note.FilePath != null)
                {
                    var b = Path.Combine(Path.GetDirectoryName(note.FilePath)!, Path.GetFileNameWithoutExtension(note.FilePath));
                    foreach (var f in new[] { note.FilePath, b + " - Raw.txt", b + " - Smart.txt" }) try { File.Delete(f); } catch { }
                }
                return;
            }
            string? summary = null;
            try
            {
                SetIdle("Writing the smart transcript…");
                note.Smart = await TextBrain.SmartTranscript(note.PlainText);
                WriteNote(note, null);
                SetIdle("Writing summary…");
                summary = await Summarize(note);
            }
            catch { }
            WriteNote(note, summary);
            LastNotePath = note.FilePath;
            if (!IsRecording && !IsStarting) SmartTranscript = note.Smart;
            SetIdle("Saved to Documents › Just Say It Notes");
            CollectivIQ.Deliver(note.Meeting?.Title, note.PlainText, note.Smart, sendImmediately && Store.Shared.Prefs.CiqAutoSend);
        }
        finally
        {
            flushing = false;
            Interlocked.Decrement(ref finishing);
            Changed?.Invoke();
        }
    }

    /// Everything that goes into a finished note file.
    sealed class Note(NoteLine[] lines, UpcomingMeeting? meeting, string? filePath, DateTime startedAt, DateTime endedAt, string context)
    {
        public NoteLine[] Lines = lines;
        public UpcomingMeeting? Meeting = meeting;
        public string? FilePath = filePath;
        public DateTime StartedAt = startedAt, EndedAt = endedAt;
        public string Context = context;
        public string? Smart;
        public MeetingCaption[] Captions = Array.Empty<MeetingCaption>();
        public string PlainText => MeetingTranscript.Combined(string.Join("\n", Lines.Select(l => $"{l.Speaker}: {l.Text}")), Captions);
        public string Raw => MeetingTranscript.Combined(string.Join("\n", Lines.Select(l => $"[{Stamp(l.Time)}] {l.Speaker}: {l.Text}")), Captions);
    }

    /// Status of a finishing recording; never overwrites the status of a new one.
    void SetIdle(string s) { if (!IsRecording && !IsStarting) Set(s); }

    void AddSource(string speaker, IWaveIn capture)
    {
        var s = new Source { Speaker = speaker, Capture = capture, Format = capture.WaveFormat };
        capture.DataAvailable += (_, e) =>
        {
            var samples = ToMono16k(e.Buffer, e.BytesRecorded, s.Format!);
            lock (s.Gate)
            {
                // Computer audio sends nothing while it's silent: fill the gap so "Others" timestamps stay in sync.
                var expected = (DateTime.Now - captureStart).TotalSeconds * Rate - samples.Length;
                var have = s.Offset * Rate + s.Pending.Count;
                var gap = (int)(expected - have);
                if (gap > Rate / 2) s.Pending.AddRange(new float[Math.Min(gap, Rate * 60)]);
                s.Pending.AddRange(samples);
            }
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
            string text;
            try { text = await Transcribe(chunk); }
            catch { continue; }   // one bad chunk never stops the rest of the meeting
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
        var langs = p.SpokenLanguages();
        // Several languages: each phrase of the chunk is recognised in the language it was spoken in.
        var pieces = langs.Count >= 2
            ? LanguageMix.Tag(samples, langs, (span, cands) =>
              {
                  using var det = factory.CreateBuilder().WithThreads(Math.Max(2, Environment.ProcessorCount - 1)).Build();
                  var r = det.DetectLanguageWithProbability(span, cands);
                  return (r.language, r.probability);
              }, Learner.Shared.LanguagePrior())
            : new List<LanguageMix.Piece> { new(0, samples.Length, langs.Count == 1 ? langs[0] : (string.IsNullOrWhiteSpace(p.Language) ? "auto" : p.Language)) };
        var parts = new List<string>();
        foreach (var piece in pieces)
        {
            await using var proc = factory.CreateBuilder()
                .WithLanguage(piece.Language)
                .WithThreads(Math.Max(2, Environment.ProcessorCount - 1))
                .WithNoContext()
                .Build();
            var sb = new StringBuilder();
            await foreach (var seg in proc.ProcessAsync(samples.AsMemory(piece.Start, piece.Length))) sb.Append(seg.Text);
            parts.Add(System.Text.RegularExpressions.Regex.Replace(sb.ToString().Trim(), @"\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE)[^\]]*\]", "").Trim());
        }
        return LanguageMix.Join(parts);
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

    /// Main note files, newest first (skips the separate Raw / Smart copies).
    public static IEnumerable<string> SavedNotes() =>
        Directory.GetFiles(NotesDir, "*.txt").Concat(Directory.GetFiles(NotesDir, "*.md"))
            .Where(f => !f.EndsWith(" - Raw.txt") && !f.EndsWith(" - Smart.txt"))
            .OrderByDescending(File.GetLastWriteTime);

    public static string Stamp(double t)
    {
        var s = (int)t;
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60:00}:{s % 60:00}";
    }

    public string TranscriptText(bool timestamps = true)
    {
        lock (linesGate)
            return MeetingTranscript.Combined(string.Join(timestamps ? "\n\n" : "\n",
                Lines.Select(l => timestamps ? $"**{Stamp(l.Time)} {l.Speaker}:** {l.Text}" : $"{l.Speaker}: {l.Text}")), CaptionConnector.Shared.Snapshot());
    }

    /// Plain-text note: header, summary, smart transcript and raw transcript.
    /// Also writes "<name> - Raw.txt" and "<name> - Smart.txt" next to it.
    void WriteFile(string? summary)
    {
        if (!IsRecording && !flushing) return;
        WriteNote(new Note(Snapshot(), meeting, filePath, StartedAt, DateTime.Now, context) { Smart = SmartTranscript, Captions = CaptionConnector.Shared.Snapshot() }, summary);
    }

    public void CaptionsChanged() { if (IsRecording) { WriteFile(null); Changed?.Invoke(); } }

    static void WriteNote(Note n, string? summary)
    {
        var filePath = n.FilePath;
        if (filePath == null) return;
        var rule = new string('=', 60);
        var header = new StringBuilder();
        header.AppendLine(n.Meeting != null ? n.Meeting.Title : $"Note – {n.StartedAt:dddd, MMMM d, yyyy h:mm tt}");
        header.AppendLine($"Recorded with Just Say It · {n.StartedAt:f} · {Stamp((n.EndedAt - n.StartedAt).TotalSeconds)} · {n.Context}");
        if (n.Meeting != null && n.Meeting.Attendees.Count > 0) header.AppendLine("Attendees: " + string.Join(", ", n.Meeting.Attendees));
        var raw = n.Raw;

        var txt = new StringBuilder(header.ToString()).AppendLine();
        if (!string.IsNullOrWhiteSpace(summary)) txt.AppendLine(rule).AppendLine("SUMMARY").AppendLine(rule).AppendLine(Plain(summary)).AppendLine();
        if (n.Smart != null) txt.AppendLine(rule).AppendLine("SMART TRANSCRIPT (words and logic fixed)").AppendLine(rule).AppendLine(n.Smart).AppendLine();
        txt.AppendLine(rule).AppendLine("RAW TRANSCRIPT (exactly as heard)").AppendLine(rule).AppendLine(raw);
        try { File.WriteAllText(filePath, txt.ToString()); } catch { }

        var b = Path.Combine(Path.GetDirectoryName(filePath)!, Path.GetFileNameWithoutExtension(filePath));
        try { File.WriteAllText(b + " - Raw.txt", header + "\nRAW TRANSCRIPT (exactly as heard)\n\n" + raw + "\n"); } catch { }
        if (n.Smart != null)
            try { File.WriteAllText(b + " - Smart.txt", header + "\nSMART TRANSCRIPT (words and logic fixed)\n\n" + n.Smart + "\n"); } catch { }
    }

    /// Timestamped transcript exactly as recognised.
    public string RawTranscript()
    {
        lock (linesGate) return string.Join("\n", Lines.Select(l => $"[{Stamp(l.Time)}] {l.Speaker}: {l.Text}"));
    }

    static string Plain(string md) => string.Join("\n", md.Replace("**", "").Split('\n').Select(l =>
        l.StartsWith("## ") ? l[3..].ToUpperInvariant() : l.StartsWith("- [ ] ") ? "• " + l[6..] : l.StartsWith("- ") ? "• " + l[2..] : l)).Trim();

    static async Task<string?> Summarize(Note note)
    {
        var body = note.Smart ?? note.PlainText;
        var m = note.Meeting;
        var header = m != null ? $"Meeting: {m.Title}\nAttendees: {string.Join(", ", m.Attendees)}\n\n" : "";
        if (body.Length <= 7000) return await TextBrain.SummarizeMeeting(header + body);
        // Long call: note each part, then combine, so nothing in the middle is lost.
        var partials = new List<string>();
        foreach (var part in TextBrain.TranscriptChunks(body, 6000))
            if (await TextBrain.SummarizeMeeting(header + part) is { } n) partials.Add(n);
        if (partials.Count == 0) return null;
        if (partials.Count == 1) return partials[0];
        return await TextBrain.CombineNotes(partials) ?? string.Join("\n\n", partials);
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
