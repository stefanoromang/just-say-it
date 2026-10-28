// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.IO;
using System.Net.Http;
using NAudio.Wave;
using Whisper.net;

namespace JustSayIt;

/// Records the microphone and transcribes on-device with Whisper (whisper.cpp).
/// Free, offline, unlimited.
public sealed class Transcriber : IDisposable
{
    public event Action<float>? Level;

    WaveIn? wave;
    readonly MemoryStream pcm = new();
    readonly object gate = new();
    WhisperFactory? factory;
    string? loadedPath;
    public bool IsRecording { get; private set; }

    static string ModelFile(ModelSize m) => m switch
    {
        ModelSize.Base => "ggml-base.bin",
        ModelSize.Small => "ggml-small.bin",
        _ => "ggml-large-v3-turbo-q5_0.bin",
    };

    public static string ModelPath(ModelSize m) => Path.Combine(Store.Dir, "models", ModelFile(m));

    public static bool ModelExists(ModelSize m) => File.Exists(ModelPath(m));

    /// Downloads the speech model the first time (from Hugging Face, the official whisper.cpp models).
    public static async Task EnsureModel(ModelSize m, IProgress<double>? progress = null, CancellationToken ct = default)
    {
        var path = ModelPath(m);
        if (File.Exists(path)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var url = $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{ModelFile(m)}";
        using var http = new HttpClient { Timeout = TimeSpan.FromHours(1) };
        using var resp = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct);
        resp.EnsureSuccessStatusCode();
        var total = resp.Content.Headers.ContentLength ?? 0;
        var tmp = path + ".part";
        await using (var src = await resp.Content.ReadAsStreamAsync(ct))
        await using (var dst = File.Create(tmp))
        {
            var buf = new byte[1 << 16];
            long done = 0;
            int n;
            while ((n = await src.ReadAsync(buf, ct)) > 0)
            {
                await dst.WriteAsync(buf.AsMemory(0, n), ct);
                done += n;
                if (total > 0) progress?.Report((double)done / total);
            }
        }
        File.Move(tmp, path, true);
    }

    void EnsureFactory(ModelSize m)
    {
        var path = ModelPath(m);
        if (factory != null && loadedPath == path) return;
        factory?.Dispose();
        factory = WhisperFactory.FromPath(path);
        loadedPath = path;
    }

    public void Start()
    {
        if (IsRecording) return;
        lock (gate) { pcm.SetLength(0); }
        wave = new WaveIn { WaveFormat = new WaveFormat(16000, 16, 1), BufferMilliseconds = 50 };
        wave.DataAvailable += (_, e) =>
        {
            lock (gate) { pcm.Write(e.Buffer, 0, e.BytesRecorded); }
            float sum = 0;
            int samples = e.BytesRecorded / 2;
            for (int i = 0; i < samples; i++)
            {
                float s = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;
                sum += s * s;
            }
            float rms = (float)Math.Sqrt(sum / Math.Max(samples, 1));
            Level?.Invoke(Math.Min(1f, rms * 12f));
        };
        wave.StartRecording();
        IsRecording = true;
    }

    public void Cancel()
    {
        if (!IsRecording) return;
        IsRecording = false;
        wave?.StopRecording();
        wave?.Dispose();
        wave = null;
    }

    /// Stops recording and returns the transcript.
    public async Task<string> StopAndTranscribe(ModelSize model, string language, IEnumerable<string> vocabulary)
    {
        if (!IsRecording) return "";
        IsRecording = false;
        wave?.StopRecording();
        await Task.Delay(80);
        wave?.Dispose();
        wave = null;

        float[] samples;
        lock (gate)
        {
            var bytes = pcm.ToArray();
            samples = new float[bytes.Length / 2];
            for (int i = 0; i < samples.Length; i++) samples[i] = BitConverter.ToInt16(bytes, i * 2) / 32768f;
        }
        return await TranscribeSamples(samples, model, language, vocabulary);
    }

    /// Transcribes 16 kHz mono samples (also used by the self-test).
    public async Task<string> TranscribeSamples(float[] samples, ModelSize model, string language, IEnumerable<string> vocabulary)
    {
        if (samples.Length < 16000 / 4) return "";

        return await Task.Run(async () =>
        {
            EnsureFactory(model);
            var builder = factory!.CreateBuilder()
                .WithLanguage(string.IsNullOrWhiteSpace(language) ? "auto" : language)
                .WithThreads(Math.Max(2, Environment.ProcessorCount - 1))
                .WithNoContext()
                .WithSingleSegment();
            var vocab = string.Join(", ", vocabulary.Where(v => !string.IsNullOrWhiteSpace(v)).Take(60));
            if (vocab.Length > 0) builder = builder.WithPrompt("Vocabulary: " + vocab + ".");
            await using var processor = builder.Build();
            var sb = new System.Text.StringBuilder();
            await foreach (var seg in processor.ProcessAsync(samples))
                sb.Append(seg.Text);
            return CleanWhisperArtifacts(sb.ToString());
        });
    }

    static string CleanWhisperArtifacts(string s)
    {
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE|inaudible)[^\]]*\]|\((music|silence|noise)\)", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        s = s.Trim();
        // Common hallucinations on silence.
        string[] junk = { "Thank you.", "Thanks for watching!", "Thank you for watching.", "you" };
        return junk.Contains(s) ? "" : s;
    }

    public void Dispose()
    {
        Cancel();
        factory?.Dispose();
    }
}
