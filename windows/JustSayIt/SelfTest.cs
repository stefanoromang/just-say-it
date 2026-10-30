// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it
//
// End-to-end self-test on a real Windows machine:  JustSayIt.exe --selftest <report.txt>
// Runs the real speech engine, context reader, OCR, hotkey hook and paste path.

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Speech.Synthesis;
using System.Windows.Automation;

namespace JustSayIt;

public static class SelfTest
{
    static readonly List<(string name, bool ok, string detail)> results = new();
    static string report = "selftest-report.txt";

    static void Record(string name, bool ok, string detail = "")
    {
        results.Add((name, ok, detail));
        var line = $"{(ok ? "PASS" : "FAIL")}  {name}  {detail}";
        Console.WriteLine(line);
        File.AppendAllText(report, line + Environment.NewLine);
    }

    static void Log(string msg) => File.AppendAllText(report, $"  … {DateTime.Now:HH:mm:ss} {msg}{Environment.NewLine}");

    public static async Task<int> Run(string reportPath)
    {
        report = reportPath;
        File.WriteAllText(report, $"Just Say It self-test · {DateTime.Now:u} · {Environment.OSVersion}{Environment.NewLine}{Environment.NewLine}");
        var sw = Stopwatch.StartNew();
        await Step("Settings load/save", () =>
        {
            Store.Shared.Save();
            return Task.FromResult((File.Exists(Path.Combine(Store.Dir, "prefs.json")), Store.Dir));
        });

        // 1. Speech engine: synthesize a sentence with Windows' voice, transcribe with Whisper.
        await Step("Speech model download (base)", async () =>
        {
            await Transcriber.EnsureModel(ModelSize.Base);
            return (Transcriber.ModelExists(ModelSize.Base), new FileInfo(Transcriber.ModelPath(ModelSize.Base)).Length / 1_048_576 + " MB");
        }, 400);
        await Step("Whisper transcribes synthesized speech", async () =>
        {
            const string sentence = "Please send the quarterly report to the marketing team by Friday.";
            var samples = await Task.Run(() => Synthesize(sentence));
            Log($"synthesized {samples.Length / 16000.0:F1}s of audio");
            using var t = new Transcriber();
            var timer = Stopwatch.StartNew();
            var text = await t.TranscribeSamples(samples, ModelSize.Base, "en", Array.Empty<string>());
            var heard = text.ToLowerInvariant();
            bool ok = heard.Contains("report") && heard.Contains("marketing") && heard.Contains("friday");
            return (ok, $"\"{text}\" ({timer.ElapsedMilliseconds} ms)");
        }, 240);

        // 2. Text cleanup rules (same code the app uses).
        await Step("Cleanup rules", () =>
        {
            var o = TextBrain.RuleClean("um so send it friday. scratch that. send it monday comma please");
            return Task.FromResult((o == "Send it monday, please", o));
        });

        // 3. Context + insertion against a real text box in a separate UI thread
        //    (in real use the target app is another process, never our own thread).
        ContextReader.WarmUp();
        var target = Target.Start();
        Log("target window ready");
        await Pump(500);
        ForceForeground(target.Handle);
        await Pump(400);

        await Step("Context: app, window, text box", () =>
        {
            var c = ContextReader.Capture();
            bool ok = c.Window == target.Handle && c.FieldIsEditable == true && (c.TextBeforeCursor ?? "").Contains("Maria Rossi");
            return Task.FromResult((ok, $"app={c.AppName} title={c.WindowTitle} editable={c.FieldIsEditable} before=\"{c.TextBeforeCursor}\""));
        });

        await Step("Context: selected text", async () =>
        {
            target.Do(b => b.Select(6, 11)); // "Maria Rossi"
            await Pump(250);
            var c = ContextReader.Capture();
            target.Do(b => { b.SelectionStart = b.TextLength; b.SelectionLength = 0; });
            return (c.SelectedText == "Maria Rossi", $"selected=\"{c.SelectedText}\"");
        });

        await Step("Screen reading (Windows OCR)", async () =>
        {
            var text = await ScreenReader.Read(target.Handle);
            bool ok = text != null && text.Contains("Maria", StringComparison.OrdinalIgnoreCase);
            return (ok, text == null ? "no text (OCR language pack missing?)" : $"\"{text.Replace('\n', ' ')}\"");
        });

        await Step("Paste into focused text box", async () =>
        {
            ForceForeground(target.Handle);
            target.Do(b => { b.Focus(); b.SelectionStart = b.TextLength; });
            await Pump(250);
            await Inserter.Insert("I'll pay it today.", target.Handle, restoreClipboard: true);
            await Pump(800);
            var text = target.Get(b => b.Text);
            return (text.EndsWith("I'll pay it today."), $"box=\"{text}\"");
        });

        await Step("Clipboard restored after paste", async () =>
        {
            Inserter.SetClipboard("user clipboard");
            await Inserter.Insert("x", target.Handle, restoreClipboard: true);
            await Pump(800);
            var clip = Clipboard.ContainsText() ? Clipboard.GetText() : "";
            return (clip == "user clipboard", $"clipboard=\"{clip}\"");
        });

        // 4. Global keyboard hook sees the hotkey and fires Start/Stop.
        await Step("Global hotkey hook (hold Right Ctrl)", async () =>
        {
            using var hk = new Hotkeys { Hotkey = HotkeyChoice.RightCtrl };
            int starts = 0, stops = 0;
            hk.Start += (_, _) => starts++;
            hk.Stop += () => stops++;
            hk.Install();
            await Pump(200);
            SendKey(0xA3, false);
            await Pump(450);
            SendKey(0xA3, true);
            await Pump(400);
            return (starts == 1 && stops == 1, $"start={starts} stop={stops}");
        });

        await Step("Note Taker: Right Shift ×3 toggles it", async () =>
        {
            using var hk = new Hotkeys();
            int fired = 0;
            hk.TripleShift += () => fired++;
            hk.Install();
            await Pump(200);
            for (int i = 0; i < 3; i++) { SendKey(0xA1, false, extended: false); await Pump(60); SendKey(0xA1, true, extended: false); await Pump(120); }
            await Pump(300);
            int afterTriple = fired;
            // Slow taps must not trigger it.
            for (int i = 0; i < 3; i++) { SendKey(0xA1, false, extended: false); await Pump(60); SendKey(0xA1, true, extended: false); await Pump(700); }
            await Pump(200);
            return (afterTriple == 1 && fired == 1, $"triple={afterTriple} afterSlow={fired}");
        });

        await Step("Note Taker: transcribes a conversation", async () =>
        {
            var samples = await Task.Run(() => Synthesize("Today we decided to launch on March third. Maria will prepare the press release by Friday."));
            using var t = new Transcriber();
            var text = (await t.TranscribeSamples(samples, ModelSize.Base, "en", Array.Empty<string>())).ToLowerInvariant();
            bool ok = text.Contains("march") && text.Contains("press release") && text.Contains("friday");
            return (ok, $"\"{text}\"");
        }, 240);

        await Step("Meetings: reads calendar and finds Zoom/Meet/Teams", () =>
        {
            var now = DateTime.Now;
            string Ev(string uid, string title, DateTime s, string body) =>
                $"BEGIN:VEVENT\r\nUID:{uid}\r\nSUMMARY:{title}\r\nDTSTART:{s.ToUniversalTime():yyyyMMdd'T'HHmmss'Z'}\r\nDTEND:{s.AddHours(1).ToUniversalTime():yyyyMMdd'T'HHmmss'Z'}\r\nDESCRIPTION:{body}\r\nEND:VEVENT\r\n";
            var ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//JustSayIt//SelfTest//EN\r\n"
                + Ev("a", "Zoom call", now.AddHours(1), "Join https://zoom.us/j/123?pwd=x")
                + Ev("b", "Meet call", now.AddHours(2), "https://meet.google.com/abc-defg-hij")
                + Ev("c", "Teams call", now.AddHours(3), "https://teams.microsoft.com/l/meetup-join/19%3ameeting_X%40thread.v2/0")
                + Ev("d", "Lunch", now.AddHours(4), "no link")
                + "END:VCALENDAR\r\n";
            var found = AutoJoin.Parse(ics, "Test", now);
            var names = string.Join(", ", found.Select(m => $"{m.Title}={MeetingLinks.Name(m.Link.Platform)}"));
            return Task.FromResult((found.Count == 3 && found.All(m => m.Title != "Lunch"), names));
        });

        await Step("Updates: version check against GitHub", async () =>
        {
            bool cmp = Updater.IsNewer("1.10", "1.9") && !Updater.IsNewer("1.5.0", "1.5") && !Updater.IsNewer("1.4", "1.5");
            await Updater.Shared.Check(true);
            var u = Updater.Shared;
            return (cmp && u.Latest != null, $"current={Updater.Current} latest={u.Latest} status=\"{u.Status}\"");
        }, 60);

        await Step("Live calls: detects Teams, Zoom and Meet; reads the microphone list", () =>
        {
            bool apps = CallApps.Kind(@"C:\Users\a\AppData\Local\Microsoft\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe") == MeetingPlatform.Teams
                && CallApps.Kind(@"C:\Users\a\AppData\Roaming\Zoom\bin\Zoom.exe") == MeetingPlatform.Zoom
                && CallApps.IsBrowser(@"C:\Program Files\Google\Chrome\Application\chrome.exe")
                && CallApps.PlatformForTitle("Meet - abc-defg-hij - Google Chrome") == MeetingPlatform.Meet
                && CallApps.PlatformForTitle("Inbox - Gmail - Google Chrome") == null;
            var users = CallWatcher.MicUsers();   // must not throw without admin rights
            return Task.FromResult((apps, $"micInUse={users.Count}"));
        });

        await Step("Overlay and result card render", async () =>
        {
            var c = Controller.Shared;
            c.Overlay.ShowState(OverlayState.Listening, "SelfTest · Professional");
            for (int i = 0; i < 22; i++) c.Overlay.PushLevel(i / 22f);
            await Pump(300);
            c.Card.Present("Test text", "Dictation", "SelfTest", "ok", true, false);
            await Pump(300);
            bool ok = c.Overlay.Visible && c.Card.Visible;
            c.Overlay.ShowState(OverlayState.Hidden);
            c.Card.Hide();
            return (ok, "");
        });

        target.Close();
        var passed = results.Count(r => r.ok);
        File.AppendAllText(report, $"{Environment.NewLine}{passed}/{results.Count} passed in {sw.Elapsed.TotalSeconds:F1}s{Environment.NewLine}");
        return passed == results.Count ? 0 : 1;
    }

    static async Task Step(string name, Func<Task<(bool ok, string detail)>> body, int timeoutSeconds = 90)
    {
        Log("start: " + name);
        try
        {
            var work = body();
            var done = await Task.WhenAny(work, Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)));
            if (done != work) { Record(name, false, $"timed out after {timeoutSeconds}s"); return; }
            var (ok, detail) = await work;
            Record(name, ok, detail);
        }
        catch (Exception e) { Record(name, false, e.GetType().Name + ": " + e.Message); }
    }

    static async Task Pump(int ms)
    {
        var end = DateTime.Now.AddMilliseconds(ms);
        while (DateTime.Now < end) { Application.DoEvents(); await Task.Delay(20); }
    }

    static float[] Synthesize(string text)
    {
        using var synth = new SpeechSynthesizer();
        using var ms = new MemoryStream();
        synth.SetOutputToAudioStream(ms, new System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, System.Speech.AudioFormat.AudioBitsPerSample.Sixteen, System.Speech.AudioFormat.AudioChannel.Mono));
        synth.Rate = -1;
        synth.Speak(text);
        var bytes = ms.ToArray();
        var samples = new float[bytes.Length / 2 + 16000];
        for (int i = 0; i < bytes.Length / 2; i++) samples[i] = BitConverter.ToInt16(bytes, i * 2) / 32768f;
        return samples;
    }

    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    static void ForceForeground(IntPtr h)
    {
        keybd_event(0x12, 0, 0, UIntPtr.Zero);
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
        SetForegroundWindow(h);
    }

    static void SendKey(byte vk, bool up, bool extended = true) =>
        keybd_event(vk, 0, (up ? 2u : 0u) | (extended ? 1u : 0u), UIntPtr.Zero);

    /// A text-box window running on its own STA thread with its own message loop.
    sealed class Target
    {
        public Form Form = null!;
        public TextBox Box = null!;
        public IntPtr Handle;

        public static Target Start()
        {
            var t = new Target();
            var ready = new ManualResetEventSlim();
            var th = new Thread(() =>
            {
                t.Form = new Form { Text = "JustSayIt SelfTest Target", Width = 700, Height = 300, StartPosition = FormStartPosition.CenterScreen, TopMost = true };
                t.Box = new TextBox { Multiline = true, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 14f) };
                t.Form.Controls.Add(t.Box);
                t.Form.Shown += (_, _) =>
                {
                    t.Box.Text = "Hello Maria Rossi, thanks for the invoice. ";
                    t.Box.Focus();
                    t.Box.SelectionStart = t.Box.TextLength;
                    t.Handle = t.Form.Handle;
                    ready.Set();
                };
                Application.Run(t.Form);
            });
            th.SetApartmentState(ApartmentState.STA);
            th.IsBackground = true;
            th.Start();
            ready.Wait(TimeSpan.FromSeconds(20));
            return t;
        }

        public void Do(Action<TextBox> a) => Form.Invoke(() => a(Box));
        public T Get<T>(Func<TextBox, T> f) => (T)Form.Invoke(() => f(Box))!;
        public void Close() { try { Form.Invoke(() => Form.Close()); } catch { } }
    }
}
