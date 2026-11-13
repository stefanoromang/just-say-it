// Just Say It – created by Stefano Roman Gunness · MIT License
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace JustSayIt;

public sealed class CaptionConnector
{
    public static CaptionConnector Shared { get; } = new();
    readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    readonly List<MeetingCaption> lines = new();
    readonly object gate = new();
    public MeetingCaption[] Snapshot() { lock (gate) return lines.ToArray(); }
    public string Status { get; private set; } = "Meeting captions are off";
    string token = "", service = "";
    string? session;
    long offset;
    string pending = "";
    string FilePath => Path.Combine(Store.Dir, $"captions-{token}.jsonl");

    CaptionConnector() { timer.Tick += (_, _) => Tick(); }
    public void Start(string source)
    {
        Stop(); lock (gate) lines.Clear(); session = null; offset = 0; pending = "";
        token = Guid.NewGuid().ToString("N"); service = source is "teams" or "meet" ? source : "";
        Tick(); timer.Start();
    }

    void Tick()
    {
        bool enabled = Store.Shared.Prefs.CaptureMeetingCaptions && NoteTaker.Shared.IsRecording;
        try
        {
            File.WriteAllText(Path.Combine(Store.Dir, "caption-state.json"), JsonSerializer.Serialize(new { token, enabled, service, updated = DateTimeOffset.UtcNow.ToUnixTimeSeconds() }));
            if (File.Exists(FilePath))
            {
                using var f = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                f.Position = offset;
                using var reader = new StreamReader(f, Encoding.UTF8);
                pending += reader.ReadToEnd(); offset = f.Position;
                int end;
                bool changed = false;
                while ((end = pending.IndexOf('\n')) >= 0)
                {
                    var line = pending[..end]; pending = pending[(end + 1)..];
                    try
                    {
                        if (Store.Shared.Prefs.CaptureMeetingCaptions && (enabled || !timer.Enabled) && JsonSerializer.Deserialize<MeetingCaption>(line) is { Valid: true } row)
                        {
                            lock (gate)
                            {
                                var before = lines.ToArray();
                                MeetingTranscript.Merge(new[] { row }, lines, ref session);
                                changed |= !before.SequenceEqual(lines);
                            }
                        }
                    }
                    catch (JsonException) { }
                }
                if (changed) NoteTaker.Shared.CaptionsChanged();
            }
            int count = Snapshot().Length;
            Status = !enabled ? "Meeting captions are off" : count == 0 ? "Waiting for Teams web / Meet captions · audio backup is active" : $"Connected · {count} speaker-labelled captions";
        }
        catch { Status = "Caption connector unavailable · audio backup is active"; }
    }

    public void Stop()
    {
        timer.Stop();
        if (token.Length > 0) { Tick(); try { File.Delete(FilePath); } catch { } }
        try { File.Delete(Path.Combine(Store.Dir, "caption-state.json")); } catch { }
        token = "";
    }

    public void Reset() { lock (gate) lines.Clear(); session = null; }

    public void Import()
    {
        if (!NoteTaker.Shared.IsRecording) return;
        using var dialog = new OpenFileDialog { Title = "Add a meeting transcript", Filter = "Transcripts|*.vtt;*.srt;*.txt" };
        if (dialog.ShowDialog() != DialogResult.OK || !NoteTaker.Shared.IsRecording) return;
        try
        {
            if (new FileInfo(dialog.FileName).Length > 10_000_000) throw new IOException("Transcript is too large (maximum 10 MB).");
            var rows = MeetingTranscript.Parse(File.ReadAllText(dialog.FileName));
            if (rows.Count == 0) throw new IOException("No transcript text found.");
            lock (gate) lines.AddRange(rows); Status = $"Imported {rows.Count} transcript lines"; NoteTaker.Shared.CaptionsChanged();
        }
        catch (Exception e) { MessageBox.Show(e.Message, "Transcript import", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
    }

    public static void OpenSetup() => Process.Start(new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "captions")) { UseShellExecute = true });

    /// Browser launches this before the normal app entry point; no UI and no listening TCP port.
    public static void NativeHost()
    {
        try
        {
            using var input = Console.OpenStandardInput(); using var output = Console.OpenStandardOutput();
            var header = new byte[4]; input.ReadExactly(header);
            int size = BitConverter.ToInt32(header); if (size <= 0 || size > 65536) return;
            var bytes = new byte[size]; input.ReadExactly(bytes);
            var row = JsonSerializer.Deserialize<MeetingCaption>(bytes);
            using var message = JsonDocument.Parse(bytes);
            using var state = JsonDocument.Parse(File.ReadAllText(Path.Combine(Store.Dir, "caption-state.json")));
            var root = state.RootElement;
            string activeToken = root.GetProperty("token").GetString() ?? "";
            string activeService = root.GetProperty("service").GetString() ?? "";
            bool ok = row is { Valid: true } && root.GetProperty("enabled").GetBoolean()
                && DateTimeOffset.UtcNow.ToUnixTimeSeconds() - root.GetProperty("updated").GetDouble() < 15
                && System.Text.RegularExpressions.Regex.IsMatch(activeToken, "^[a-f0-9]{32}$");
            var url = new Uri(message.RootElement.GetProperty("url").GetString() ?? "");
            var expected = url.Host == "meet.google.com" ? "meet" : new[] { "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft" }.Contains(url.Host) ? "teams" : "";
            ok &= url.Scheme == "https" && expected.Length > 0 && row?.Service == expected && (activeService.Length == 0 || activeService == expected);
            if (ok)
            {
                string path = Path.Combine(Store.Dir, $"captions-{activeToken}.jsonl");
                if (File.Exists(path) && new FileInfo(path).Length > 64 * 1024 * 1024) ok = false;
                else
                {
                    using var f = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
                    var payload = JsonSerializer.SerializeToUtf8Bytes(row! with { Received = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0 });
                    f.Write(payload); f.WriteByte(10);
                }
            }
            var result = JsonSerializer.SerializeToUtf8Bytes(new { ok, status = ok ? "Capturing speaker-labelled captions into your notes." : "Enable meeting captions and start the Note Taker in Just Say It." });
            output.Write(BitConverter.GetBytes(result.Length)); output.Write(result); output.Flush();
        }
        catch { /* Browser reports an unavailable connector; never launch the normal app on malformed input. */ }
    }
}
