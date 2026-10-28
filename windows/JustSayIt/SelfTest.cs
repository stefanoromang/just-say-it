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

    static void Record(string name, bool ok, string detail = "")
    {
        results.Add((name, ok, detail));
        Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name}  {detail}");
    }

    public static async Task<int> Run(string reportPath)
    {
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
        });
        await Step("Whisper transcribes synthesized speech", async () =>
        {
            const string sentence = "Please send the quarterly report to the marketing team by Friday.";
            var samples = Synthesize(sentence);
            using var t = new Transcriber();
            var timer = Stopwatch.StartNew();
            var text = await t.TranscribeSamples(samples, ModelSize.Base, "en", Array.Empty<string>());
            var heard = text.ToLowerInvariant();
            bool ok = heard.Contains("report") && heard.Contains("marketing") && heard.Contains("friday");
            return (ok, $"\"{text}\" ({timer.ElapsedMilliseconds} ms)");
        });

        // 2. Text cleanup rules (same code the app uses).
        await Step("Cleanup rules", () =>
        {
            var o = TextBrain.RuleClean("um so send it friday. scratch that. send it monday comma please");
            return Task.FromResult((o == "Send it monday, please", o));
        });

        // 3. Context + insertion against a real text box in a real window.
        using var form = new Form { Text = "JustSayIt SelfTest Target", Width = 700, Height = 300, StartPosition = FormStartPosition.CenterScreen, TopMost = true };
        var box = new TextBox { Multiline = true, Dock = DockStyle.Fill, Font = new Font("Segoe UI", 14f) };
        form.Controls.Add(box);
        form.Show();
        form.Activate();
        box.Focus();
        box.Text = "Hello Maria Rossi, thanks for the invoice. ";
        box.SelectionStart = box.TextLength;
        await Pump(600);
        ForceForeground(form.Handle);
        await Pump(300);

        await Step("Context: app, window, text box", () =>
        {
            var c = ContextReader.Capture();
            bool ok = c.Window == form.Handle && c.FieldIsEditable == true && (c.TextBeforeCursor ?? "").Contains("Maria Rossi");
            return Task.FromResult((ok, $"app={c.AppName} title={c.WindowTitle} editable={c.FieldIsEditable} before=\"{c.TextBeforeCursor}\""));
        });

        await Step("Context: selected text", async () =>
        {
            box.Select(6, 11); // "Maria Rossi"
            await Pump(200);
            var c = ContextReader.Capture();
            box.SelectionStart = box.TextLength;
            box.SelectionLength = 0;
            return (c.SelectedText == "Maria Rossi", $"selected=\"{c.SelectedText}\"");
        });

        await Step("Screen reading (Windows OCR)", async () =>
        {
            var text = await ScreenReader.Read(form.Handle);
            bool ok = text != null && text.Contains("Maria", StringComparison.OrdinalIgnoreCase);
            return (ok, text == null ? "no text (OCR language pack missing?)" : $"\"{text.Replace('\n', ' ')}\"");
        });

        await Step("Paste into focused text box", async () =>
        {
            ForceForeground(form.Handle);
            box.Focus();
            box.SelectionStart = box.TextLength;
            await Pump(200);
            await Inserter.Insert("I'll pay it today.", form.Handle, restoreClipboard: true);
            await Pump(700);
            return (box.Text.EndsWith("I'll pay it today."), $"box=\"{box.Text}\"");
        });

        await Step("Clipboard restored after paste", async () =>
        {
            Inserter.SetClipboard("user clipboard");
            await Inserter.Insert("x", form.Handle, restoreClipboard: true);
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

        form.Close();
        var passed = results.Count(r => r.ok);
        var lines = new List<string> { $"Just Say It self-test · {DateTime.Now:u} · {Environment.OSVersion} · {sw.Elapsed.TotalSeconds:F1}s", "" };
        lines.AddRange(results.Select(r => $"{(r.ok ? "PASS" : "FAIL")}  {r.name}  {r.detail}"));
        lines.Add("");
        lines.Add($"{passed}/{results.Count} passed");
        File.WriteAllLines(reportPath, lines);
        return passed == results.Count ? 0 : 1;
    }

    static async Task Step(string name, Func<Task<(bool ok, string detail)>> body)
    {
        try
        {
            var (ok, detail) = await body();
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

    static void SendKey(byte vk, bool up) => keybd_event(vk, 0, (up ? 2u : 0u) | 1u /*EXTENDED*/, UIntPtr.Zero);
}
