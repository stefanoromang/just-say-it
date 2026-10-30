// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace JustSayIt;

public record LiveCall(MeetingPlatform Platform, string Title);

/// Watches which apps are using the microphone (Windows' privacy "in use" list, per user).
/// When Microsoft Teams, Zoom or a Google Meet / Teams / Zoom browser tab starts a live call,
/// the Note Taker starts automatically; when the call ends, it stops and saves the transcript.
public sealed class CallWatcher
{
    public static CallWatcher Shared { get; } = new();

    public LiveCall? ActiveCall { get; private set; }
    public string Status { get; private set; } = "";
    public event Action? Changed;

    readonly System.Windows.Forms.Timer timer = new() { Interval = 2000 };
    LiveCall? candidate;
    DateTime? candidateSince, lastSeen;
    bool startedRecording;

    const double StartDelay = 3, EndDelay = 10;

    public void Boot()
    {
        timer.Tick += (_, _) => Tick();
        timer.Start();
    }

    void Tick()
    {
        var p = Store.Shared.Prefs;
        var now = DateTime.Now;
        LiveCall? call = null;
        try { call = p.AutoRecordCalls ? Detect() : null; } catch { }

        if (call != null)
        {
            lastSeen = now;
            if (ActiveCall == null)
            {
                if (candidate != call) { candidate = call; candidateSince = now; }
                if (candidateSince != null && (now - candidateSince.Value).TotalSeconds >= StartDelay) Begin(call);
            }
        }
        else
        {
            candidate = null; candidateSince = null;
            if (ActiveCall != null && (now - (lastSeen ?? now)).TotalSeconds >= EndDelay) End();
        }
    }

    void Begin(LiveCall call)
    {
        ActiveCall = call;
        Status = $"Live {MeetingLinks.Name(call.Platform)} call detected";
        Changed?.Invoke();
        var notes = NoteTaker.Shared;
        if (notes.IsRecording || Controller.Shared.Transcriber.IsRecording) return;
        startedRecording = true;
        var m = new UpcomingMeeting($"call-{DateTime.Now.Ticks}", call.Title, DateTime.Now, DateTime.Now.AddHours(8),
            new MeetingLink(call.Platform, "about:blank"), "Live call", new List<string>());
        Controller.Shared.Overlay.ShowState(OverlayState.Error, $"Recording your {MeetingLinks.Name(call.Platform)} call – notes save when it ends");
        NoteWindow.ShowShared();
        _ = notes.Start(m, NoteTaker.Origin.Call);
    }

    void End()
    {
        var notes = NoteTaker.Shared;
        if (startedRecording && notes.IsRecording && notes.CurrentOrigin == NoteTaker.Origin.Call) _ = notes.Stop();
        Status = ActiveCall != null ? $"{MeetingLinks.Name(ActiveCall.Platform)} call ended – transcript saved" : "";
        ActiveCall = null;
        startedRecording = false;
        Changed?.Invoke();
    }

    // MARK: Detection

    LiveCall? Detect()
    {
        var p = Store.Shared.Prefs;
        var browsers = new List<string>();
        foreach (var exe in MicUsers())
        {
            var kind = CallApps.Kind(exe);
            if (kind is MeetingPlatform platform && Enabled(platform, p)) return new LiveCall(platform, NativeTitle(platform));
            if (kind == null && CallApps.IsBrowser(exe)) browsers.Add(Path.GetFileNameWithoutExtension(exe).ToLowerInvariant());
        }
        if (browsers.Count == 0) return null;
        // A browser has the microphone: look at its window titles for a Meet / Teams / Zoom call.
        foreach (var w in TopWindows())
        {
            if (!browsers.Contains(w.process)) continue;
            var platform = CallApps.PlatformForTitle(w.title);
            if (platform != null && Enabled(platform.Value, p)) return new LiveCall(platform.Value, CallApps.CleanTitle(w.title, platform.Value));
        }
        return null;
    }

    static bool Enabled(MeetingPlatform platform, Prefs p) => platform switch
    {
        MeetingPlatform.Teams => p.RecordTeamsCalls,
        MeetingPlatform.Zoom => p.RecordZoomCalls,
        _ => p.RecordMeetCalls,
    };

    /// Executables currently using the microphone, from the per-user CapabilityAccessManager store
    /// (the same data behind the "app is using your microphone" indicator). No admin rights needed.
    public static List<string> MicUsers()
    {
        var result = new List<string>();
        const string root = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
        using var mic = Registry.CurrentUser.OpenSubKey(root);
        if (mic == null) return result;
        void Scan(RegistryKey parent, bool decodePath)
        {
            foreach (var name in parent.GetSubKeyNames())
            {
                if (name == "NonPackaged") continue;
                using var k = parent.OpenSubKey(name);
                if (k == null) continue;
                var start = k.GetValue("LastUsedTimeStart") is long s ? s : 0;
                var stop = k.GetValue("LastUsedTimeStop") is long e ? e : 0;
                if (start > 0 && stop == 0) result.Add(decodePath ? name.Replace('#', '\\') : name);
            }
        }
        Scan(mic, false);
        using (var np = mic.OpenSubKey("NonPackaged")) if (np != null) Scan(np, true);
        return result;
    }

    string NativeTitle(MeetingPlatform platform)
    {
        var names = platform == MeetingPlatform.Teams ? new[] { "ms-teams", "teams" } : new[] { "zoom" };
        foreach (var w in TopWindows())
        {
            if (!names.Contains(w.process)) continue;
            var t = w.title.Replace(" | Microsoft Teams", "").Replace(" - Microsoft Teams", "").Trim();
            var low = t.ToLowerInvariant();
            if (t.Length == 0 || low is "microsoft teams" or "zoom" or "zoom workplace" or "chat" or "calendar" or "activity") continue;
            return t.Length > 80 ? t[..80] : t;
        }
        return $"{MeetingLinks.Name(platform)} call";
    }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    static List<(string process, string title)> TopWindows()
    {
        var list = new List<(string, string)>();
        var names = new Dictionary<uint, string>();
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(512);
            if (GetWindowText(h, sb, sb.Capacity) == 0) return true;
            GetWindowThreadProcessId(h, out var pid);
            if (!names.TryGetValue(pid, out var name))
            {
                try { name = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant(); } catch { name = ""; }
                names[pid] = name;
            }
            list.Add((name, sb.ToString()));
            return true;
        }, IntPtr.Zero);
        return list;
    }
}

/// Recognises call apps from executable paths and browser window titles.
public static class CallApps
{
    public static MeetingPlatform? Kind(string exePathOrPackage)
    {
        var e = exePathOrPackage.ToLowerInvariant();
        if (e.Contains("msteams") || e.EndsWith("\\ms-teams.exe") || e.EndsWith("\\teams.exe") || e.Contains("microsoftteams")) return MeetingPlatform.Teams;
        if (e.EndsWith("\\zoom.exe") || e.Contains("zoom.us") || e.Contains("\\zoom\\bin\\")) return MeetingPlatform.Zoom;
        return null;
    }

    public static bool IsBrowser(string exePath)
    {
        var name = Path.GetFileName(exePath.ToLowerInvariant());
        return name is "chrome.exe" or "msedge.exe" or "brave.exe" or "firefox.exe" or "opera.exe" or "vivaldi.exe" or "arc.exe";
    }

    public static MeetingPlatform? PlatformForTitle(string title)
    {
        var t = title.ToLowerInvariant();
        if (t.StartsWith("meet - ") || t.StartsWith("meet – ") || t.Contains("google meet") || t.Contains("meet.google.com")) return MeetingPlatform.Meet;
        if (t.Contains("microsoft teams")) return MeetingPlatform.Teams;
        if (t.Contains("zoom meeting") || t.Contains("zoom workplace") || t.Contains("zoom webinar")) return MeetingPlatform.Zoom;
        return null;
    }

    public static string CleanTitle(string raw, MeetingPlatform platform)
    {
        var t = raw;
        foreach (var cut in new[] { " - Google Chrome", " – Google Chrome", " - Microsoft​ Edge", " - Microsoft Edge", " - Brave", " — Mozilla Firefox", " - Mozilla Firefox", " | Microsoft Teams", " - Work", " - Personal" })
            t = t.Replace(cut, "");
        t = t.Trim();
        if (t.StartsWith("Meet - ") || t.StartsWith("Meet – ")) t = t[7..];
        var low = t.ToLowerInvariant();
        if (t.Length == 0 || low is "meet" or "microsoft teams" or "google meet") return $"{MeetingLinks.Name(platform)} call";
        return t.Length > 80 ? t[..80] : t;
    }
}
