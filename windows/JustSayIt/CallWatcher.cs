// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;
using NAudio.CoreAudioApi;

namespace JustSayIt;

/// A live call. <see cref="Owner"/> is the app's process name (or the browser's for web calls).
public sealed record LiveCall(CallService Service, string Title, string Owner, bool InBrowser)
{
    public MeetingPlatform Platform => CallApps.ToPlatform(Service) ?? MeetingPlatform.Teams;
}

/// Detects live calls in every supported app (Teams, Meet, Zoom, Webex, Slack huddles, Discord,
/// Skype, Whereby, Jitsi, RingCentral, GoTo, Zoho, Signal, WhatsApp, Telegram, FaceTime on the web).
///
/// Rules:
/// - A call starts when its app (or a browser showing the call) uses the microphone for a few seconds.
/// - The recording belongs to that call. Nothing else (another meeting, calendar end times, muting)
///   stops it. It ends only when the call itself ends (its app has neither microphone nor speaker
///   audio for 45 seconds) or when the user presses End Note Taker.
/// - When it ends the notes are saved and sent to CollectivIQ straight away.
public sealed class CallWatcher
{
    public static CallWatcher Shared { get; } = new();

    public LiveCall? ActiveCall { get; private set; }
    public string Status { get; private set; } = "";
    public event Action? Changed;

    readonly System.Windows.Forms.Timer timer = new() { Interval = 2000 };
    LiveCall? candidate, dismissed;
    DateTime? candidateSince, lastAlive, dismissedLastSeen;
    bool startedRecording, starting, busy;

    /// The call must hold the microphone this long before recording starts (ignores quick mic tests).
    public const double StartDelay = 3;
    /// No microphone and no speaker audio from the call's app for this long = the call is over.
    public const double EndDelay = 45;

    public void Boot()
    {
        timer.Tick += async (_, _) =>
        {
            if (busy) return;
            busy = true;
            try { await Tick(); } catch { }
            finally { busy = false; }
        };
        timer.Start();
    }

    /// "End Note Taker": finish now and send immediately. The same call isn't recorded again.
    public void EndByUser()
    {
        var notes = NoteTaker.Shared;
        if (!notes.IsRecording) return;
        if (ActiveCall != null) { dismissed = ActiveCall; dismissedLastSeen = DateTime.Now; }
        ActiveCall = null;
        startedRecording = false;
        Status = "Ended by you – notes saved and sent";
        Changed?.Invoke();
        _ = notes.Stop(sendImmediately: true);
    }

    async Task Tick()
    {
        var p = Store.Shared.Prefs;
        var now = DateTime.Now;
        var notes = NoteTaker.Shared;
        bool watching = ActiveCall != null || dismissed != null
            || (p.AutoRecordCalls && p.NoteTakerEnabled && !notes.IsBusy && !Controller.Shared.Transcriber.IsRecording);
        if (!watching) { candidate = null; candidateSince = null; return; }

        // Reading audio sessions, processes and windows is slow: do it off the UI thread.
        var audio = await Task.Run(AudioSnapshot.Take);
        now = DateTime.Now;

        // While recording a call, only that call can end it.
        if (ActiveCall is { } active)
        {
            if (starting) { if (IsAlive(active, audio)) lastAlive = now; return; }
            if (!notes.IsRecording || notes.CurrentOrigin != NoteTaker.Origin.Call)
            {
                // The recording finished another way: don't record this call again until it's over.
                dismissed = active; dismissedLastSeen = now;
                ActiveCall = null; startedRecording = false; Changed?.Invoke();
                return;
            }
            if (IsAlive(active, audio)) { lastAlive = now; return; }
            if ((now - (lastAlive ?? now)).TotalSeconds >= EndDelay) End(active);
            return;
        }

        // A call the user already ended stays ignored until it's really over (checked even while busy).
        if (dismissed is { } d)
        {
            if (IsAlive(d, audio)) dismissedLastSeen = now;
            if ((now - (dismissedLastSeen ?? now)).TotalSeconds >= EndDelay) dismissed = null;
        }
        if (!p.AutoRecordCalls || !p.NoteTakerEnabled || notes.IsBusy || Controller.Shared.Transcriber.IsRecording)
        {
            candidate = null; candidateSince = null;
            return;
        }
        var call = Detect(audio, p);
        if (dismissed is { } dd && call != null && call.Service == dd.Service && call.InBrowser == dd.InBrowser && (!call.InBrowser || call.Owner == dd.Owner))
            call = null;
        if (call != null)
        {
            if (candidate == null || candidate.Service != call.Service || candidate.InBrowser != call.InBrowser) { candidate = call; candidateSince = now; }
            if (candidateSince != null && (now - candidateSince.Value).TotalSeconds >= StartDelay) Begin(call);
        }
        else { candidate = null; candidateSince = null; }
    }

    void Begin(LiveCall call)
    {
        ActiveCall = call;
        lastAlive = DateTime.Now;
        candidate = null; candidateSince = null;
        startedRecording = true;
        starting = true;
        Status = $"Recording your {call.Service.Name} call";
        Changed?.Invoke();
        var m = new UpcomingMeeting($"call-{DateTime.Now.Ticks}", call.Title, DateTime.Now, DateTime.MaxValue,
            new MeetingLink(call.Platform, "about:blank"), call.Service.Name, new List<string>());
        Controller.Shared.Overlay.ShowState(OverlayState.Error, $"Recording your {call.Service.Name} call – it keeps going until the call ends");
        NoteWindow.ShowShared();
        _ = StartFor(call, m);
    }

    async Task StartFor(LiveCall call, UpcomingMeeting m)
    {
        bool ok = false;
        try { ok = await NoteTaker.Shared.Start(m, NoteTaker.Origin.Call); } catch { }
        starting = false;
        if (!ok && ActiveCall == call)
        {
            // Couldn't start (e.g. microphone blocked): don't keep retrying this call.
            Status = $"Couldn't record your {call.Service.Name} call: {NoteTaker.Shared.Status}";
            dismissed = call; dismissedLastSeen = DateTime.Now;
            ActiveCall = null; startedRecording = false;
            Changed?.Invoke();
        }
    }

    void End(LiveCall call)
    {
        var notes = NoteTaker.Shared;
        if (startedRecording && notes.IsRecording && notes.CurrentOrigin == NoteTaker.Origin.Call) _ = notes.Stop(sendImmediately: true);
        Status = $"{call.Service.Name} call ended – notes saved and sent";
        ActiveCall = null;
        startedRecording = false;
        Changed?.Invoke();
    }

    // MARK: Detection

    static LiveCall? Detect(AudioSnapshot audio, Prefs p)
    {
        var browsers = new HashSet<string>();
        foreach (var user in audio.MicUsers)
        {
            var svc = CallApps.Service(user);
            if (svc != null)
            {
                if (p.IsCallServiceEnabled(svc.Id)) return new LiveCall(svc, NativeTitle(svc, audio.Windows), ProcessName(user), false);
                continue;
            }
            if (CallApps.IsBrowser(user)) browsers.Add(ProcessName(user));
        }
        if (browsers.Count == 0) return null;
        // A browser has the microphone: find its window showing a supported web call.
        foreach (var w in audio.Windows)
        {
            if (!browsers.Contains(w.process)) continue;
            var svc = CallApps.ServiceForTitle(w.title);
            if (svc != null && p.IsCallServiceEnabled(svc.Id)) return new LiveCall(svc, CallApps.CleanTitle(w.title, svc), w.process, true);
        }
        return null;
    }

    static string ProcessName(string exePathOrPackage)
    {
        var e = exePathOrPackage.ToLowerInvariant().Replace('/', '\\');
        return Path.GetFileNameWithoutExtension(e.Contains('\\') ? e[(e.LastIndexOf('\\') + 1)..] : e);
    }

    /// Is the call still going? True while its app uses the microphone or plays sound. Muting
    /// yourself keeps it alive through the other people's audio. For web calls the browser must
    /// also still show the call window when only sound is playing (so a YouTube video afterwards
    /// doesn't keep it going).
    static bool IsAlive(LiveCall call, AudioSnapshot audio)
    {
        bool Related(string name) => call.InBrowser
            ? name == call.Owner
            : name == call.Owner || call.Service.ExeNames.Contains(name);
        if (audio.MicUsers.Any(u => Related(ProcessName(u)) || (!call.InBrowser && CallApps.Service(u) == call.Service))) return true;
        if (!audio.PlayingProcesses.Any(Related)) return false;
        if (!call.InBrowser) return true;
        return audio.Windows.Any(w => w.process == call.Owner && CallApps.ServiceForTitle(w.title) == call.Service);
    }

    /// Microphone users and processes playing sound, read once per tick.
    sealed class AudioSnapshot
    {
        public List<string> MicUsers = new();
        public HashSet<string> PlayingProcesses = new();
        public List<(string process, string title)> Windows = new();

        public static AudioSnapshot Take()
        {
            var s = new AudioSnapshot();
            var names = ProcessNames();
            var running = new HashSet<string>(names.Values);
            try
            {
                // A crashed app can leave its "in use" entry behind: only count apps that are still running.
                s.MicUsers = CallWatcher.MicUsers().Where(u => !u.Contains('\\') || running.Contains(ProcessName(u))).ToList();
            }
            catch { }
            try { s.PlayingProcesses = ActiveSessions(DataFlow.Render, names); } catch { }
            try { foreach (var n in ActiveSessions(DataFlow.Capture, names)) s.MicUsers.Add(n + ".exe"); } catch { }
            try { s.Windows = TopWindows(names); } catch { }
            return s;
        }
    }

    /// pid → lowercase process name for every running process (read once per check).
    static Dictionary<int, string> ProcessNames()
    {
        var d = new Dictionary<int, string>();
        foreach (var pr in Process.GetProcesses())
        {
            try { d[pr.Id] = pr.ProcessName.ToLowerInvariant(); } catch { }
            finally { pr.Dispose(); }
        }
        return d;
    }

    /// Process names with an active audio session (playing sound, or recording) on any device.
    public static HashSet<string> ActiveSessions(DataFlow flow) => ActiveSessions(flow, ProcessNames());

    static HashSet<string> ActiveSessions(DataFlow flow, Dictionary<int, string> procNames)
    {
        var names = new HashSet<string>();
        using var en = new MMDeviceEnumerator();
        foreach (var dev in en.EnumerateAudioEndPoints(flow, DeviceState.Active))
        {
            using (dev)
            {
                var sessions = dev.AudioSessionManager.Sessions;
                for (int i = 0; i < sessions.Count; i++)
                {
                    using var ses = sessions[i];
                    if (ses.State != NAudio.CoreAudioApi.Interfaces.AudioSessionState.AudioSessionStateActive) continue;
                    var pid = (int)ses.GetProcessID;
                    if (pid == 0 || pid == Environment.ProcessId) continue;
                    if (procNames.TryGetValue(pid, out var nm)) names.Add(nm);
                }
            }
        }
        return names;
    }

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
        var self = Environment.ProcessPath ?? "";
        result.RemoveAll(r => r.Equals(self, StringComparison.OrdinalIgnoreCase) || r.EndsWith("\\justsayit.exe", StringComparison.OrdinalIgnoreCase));
        return result;
    }

    static string NativeTitle(CallService svc, List<(string process, string title)> windows)
    {
        var skip = new HashSet<string> { "", "microsoft teams", "zoom", "zoom workplace", "chat", "calendar", "activity", "slack", "discord",
                                         "skype", "webex", "signal", "whatsapp", "telegram", "ringcentral", "goto", "zoho meeting" };
        foreach (var w in windows)
        {
            if (!svc.ExeNames.Contains(w.process)) continue;
            var t = CallApps.CleanTitle(w.title, svc);
            if (skip.Contains(t.ToLowerInvariant()) || t == $"{svc.Name} call") continue;
            return t;
        }
        return $"{svc.Name} call";
    }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    static List<(string process, string title)> TopWindows(Dictionary<int, string> procNames)
    {
        var list = new List<(string, string)>();
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(512);
            if (GetWindowText(h, sb, sb.Capacity) == 0) return true;
            GetWindowThreadProcessId(h, out var pid);
            list.Add((procNames.TryGetValue((int)pid, out var name) ? name : "", sb.ToString()));
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
