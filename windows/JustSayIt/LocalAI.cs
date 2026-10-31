// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Security.Cryptography;
using System.Text;
using LLama;
using LLama.Common;
using LLama.Sampling;

namespace JustSayIt;

public enum LocalModel { Fast, Quality }

/// Built-in local AI: a small open model (GGUF) run on the PC with llama.cpp via LLamaSharp.
/// No separate program, no admin rights, works offline after the one-time download.
public static class LocalAI
{
    public record ModelInfo(string File, string Url, string Sha256, long Bytes, string Label);

    public static ModelInfo Info(LocalModel m) => m switch
    {
        LocalModel.Quality => new("Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            "6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff", 2019377696, "Better quality (Llama 3.2 3B, 2 GB)"),
        _ => new("qwen2.5-1.5b-instruct-q4_k_m.gguf",
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e", 1117320736, "Fast (Qwen 2.5 1.5B, 1.1 GB)"),
    };

    public static string ModelPath(LocalModel m) => Path.Combine(Store.Dir, "models", Info(m).File);
    public static bool ModelExists(LocalModel m) => File.Exists(ModelPath(m));

    public static string Status { get; private set; } = "";
    public static event Action? Changed;
    static void Set(string s) { Status = s; Changed?.Invoke(); }

    static readonly SemaphoreSlim gate = new(1, 1);
    static LLamaWeights? weights;
    static ModelParams? parameters;
    static LocalModel? loaded;
    static Task? downloading;

    /// Downloads the model once (resumable, SHA-256 verified).
    public static Task EnsureModel(LocalModel m)
    {
        if (ModelExists(m)) return Task.CompletedTask;
        return downloading ??= Download(m).ContinueWith(t => { downloading = null; if (t.IsFaulted) throw t.Exception!.InnerException!; });
    }

    static async Task Download(LocalModel m)
    {
        var info = Info(m);
        var path = ModelPath(m);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var part = path + ".part";
        using var http = new HttpClient { Timeout = TimeSpan.FromHours(2) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("JustSayIt");
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                long have = File.Exists(part) ? new FileInfo(part).Length : 0;
                using var req = new HttpRequestMessage(HttpMethod.Get, info.Url);
                if (have > 0) req.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(have, null);
                using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
                resp.EnsureSuccessStatusCode();
                if (have > 0 && resp.StatusCode != System.Net.HttpStatusCode.PartialContent) have = 0;
                await using (var src = await resp.Content.ReadAsStreamAsync())
                await using (var dst = new FileStream(part, have > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write))
                {
                    var buf = new byte[1 << 16];
                    long done = have; int n; var last = DateTime.MinValue;
                    while ((n = await src.ReadAsync(buf)) > 0)
                    {
                        await dst.WriteAsync(buf.AsMemory(0, n));
                        done += n;
                        if ((DateTime.Now - last).TotalSeconds > 1) { last = DateTime.Now; Set($"Downloading the local AI model… {done * 100 / info.Bytes}%"); }
                    }
                }
                Set("Checking the local AI model…");
                if (!await VerifyAsync(part, info.Sha256)) { File.Delete(part); throw new IOException("Downloaded model failed its checksum"); }
                File.Move(part, path, true);
                Set("Local AI ready");
                return;
            }
            catch when (attempt < 4) { await Task.Delay(3000 * (attempt + 1)); }
        }
    }

    static async Task<bool> VerifyAsync(string file, string sha) => await Task.Run(() =>
    {
        using var f = File.OpenRead(file);
        return Convert.ToHexString(SHA256.HashData(f)).Equals(sha, StringComparison.OrdinalIgnoreCase);
    });

    static void Load(LocalModel m)
    {
        if (loaded == m && weights != null) return;
        weights?.Dispose();
        parameters = new ModelParams(ModelPath(m))
        {
            ContextSize = 4096,
            GpuLayerCount = 0,
            Threads = Math.Max(2, Environment.ProcessorCount - 1),
        };
        weights = LLamaWeights.LoadFromFile(parameters);
        loaded = m;
    }

    public static bool Ready => ModelExists(Store.Shared.Prefs.LocalModel);

    /// Loads the model into memory so the first request is fast.
    public static async Task Prewarm()
    {
        var m = Store.Shared.Prefs.LocalModel;
        if (!ModelExists(m)) return;
        await gate.WaitAsync();
        try { await Task.Run(() => Load(m)); Set("Local AI ready"); }
        catch (Exception e) { Set("Local AI couldn't start: " + e.Message); }
        finally { gate.Release(); }
    }

    /// One instruction + text → answer. Returns null if the model isn't available.
    public static async Task<string?> Run(string instructions, string prompt, int maxTokens = 1500)
    {
        var m = Store.Shared.Prefs.LocalModel;
        if (!ModelExists(m)) return null;
        await gate.WaitAsync();
        try
        {
            return await Task.Run(async () =>
            {
                Load(m);
                using var ctx = weights!.CreateContext(parameters!);
                var executor = new StatelessExecutor(weights!, parameters!);
                var history = new ChatHistory();
                history.AddMessage(AuthorRole.System, instructions);
                history.AddMessage(AuthorRole.User, prompt);
                var text = weights!.NativeHandle.Vocab != null ? ApplyTemplate(history) : prompt;
                var inference = new InferenceParams
                {
                    MaxTokens = maxTokens,
                    AntiPrompts = new[] { "<|im_end|>", "<|eot_id|>", "<|end_of_text|>" },
                    SamplingPipeline = new DefaultSamplingPipeline { Temperature = 0f },
                };
                var sb = new StringBuilder();
                await foreach (var piece in executor.InferAsync(text, inference)) sb.Append(piece);
                var outp = sb.ToString();
                foreach (var stop in inference.AntiPrompts) outp = outp.Replace(stop, "");
                outp = outp.Trim();
                return outp.Length == 0 ? null : outp;
            });
        }
        catch (Exception e) { Set("Local AI error: " + e.Message); return null; }
        finally { gate.Release(); }
    }

    static string ApplyTemplate(ChatHistory history)
    {
        var template = new LLamaTemplate(weights!) { AddAssistant = true };
        foreach (var msg in history.Messages) template.Add(msg.AuthorRole.ToString().ToLowerInvariant(), msg.Content);
        return Encoding.UTF8.GetString(template.Apply());
    }
}
