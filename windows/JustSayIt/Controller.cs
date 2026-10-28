// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Media;

namespace JustSayIt;

public sealed class Controller : IDisposable
{
    public static Controller Shared { get; } = new();

    readonly Store store = Store.Shared;
    public readonly Transcriber Transcriber = new();
    public readonly Hotkeys Hotkeys = new();
    public readonly Overlay Overlay = new();
    public readonly ResultCard Card = new();

    public string LastResult { get; private set; } = "";
    public string LastContext { get; private set; } = "";
    public string ModelStatus { get; private set; } = "Checking speech model…";
    public bool ModelReady => Transcriber.ModelExists(store.Prefs.Model);
    public event Action? StatusChanged;

    CaptureContext ctx = new();
    bool scribe;
    DateTime startedAt;
    string lastRaw = "";
    bool busy;
    Task<string?>? screenTask;

    public void Boot()
    {
        Transcriber.Level += l => Ui.Run(() => Overlay.PushLevel(l));
        Hotkeys.Hotkey = store.Prefs.Hotkey;
        Hotkeys.Start += (s, hf) => Begin(s, hf);
        Hotkeys.Stop += () => _ = Finish();
        Hotkeys.CancelRecording += Cancel;
        Hotkeys.Rewrite += () => _ = RewriteSelection(RewriteStyle.Concise);
        Hotkeys.TripleShift += ToggleNotes;
        Hotkeys.Install();

        Card.InsertClicked += () => _ = InsertFromCard();
        Card.RewriteClicked += s => _ = RewriteCard(s);
        Card.RawClicked += () =>
        {
            Card.Text2 = TextBrain.RuleClean(lastRaw);
            Card.SetNote("Showing your exact words (basic cleanup only).", false);
        };

        _ = PrepareModel();
        _ = TextBrain.Prewarm();
        AutoJoin.Shared.Boot();
        ContextReader.WarmUp();
    }

    public async Task PrepareModel()
    {
        var m = store.Prefs.Model;
        if (Transcriber.ModelExists(m)) { ModelStatus = "Speech model ready (on-device)"; StatusChanged?.Invoke(); return; }
        try
        {
            var progress = new Progress<double>(p => { ModelStatus = $"Downloading speech model… {p:P0} (first run only)"; StatusChanged?.Invoke(); });
            await Transcriber.EnsureModel(m, progress);
            ModelStatus = "Speech model ready (on-device)";
        }
        catch (Exception e)
        {
            ModelStatus = "Speech model download failed: " + e.Message;
        }
        StatusChanged?.Invoke();
    }

    public void SetHotkey(HotkeyChoice h)
    {
        store.Prefs.Hotkey = h;
        Hotkeys.Hotkey = h;
        store.Save();
    }

    void Sound(bool start)
    {
        if (!store.Prefs.PlaySounds) return;
        try { (start ? SystemSounds.Asterisk : SystemSounds.Exclamation).Play(); } catch { }
    }

    // MARK: Note Taker

    public void ToggleNotes()
    {
        if (!store.Prefs.NoteTakerEnabled || Transcriber.IsRecording) return;
        if (!NoteTaker.Shared.IsRecording) NoteWindow.ShowShared();
        NoteTaker.Shared.Toggle();
    }

    // MARK: Dictation flow

    public void ToggleFromMenu()
    {
        if (Transcriber.IsRecording) { Hotkeys.Reset(); _ = Finish(); }
        else { Hotkeys.Reset(); Begin(false, true); }
    }

    void Begin(bool isScribe, bool handsFree)
    {
        Ui.Run(() =>
        {
            if (busy) { Hotkeys.Reset(); return; }
            if (NoteTaker.Shared.IsRecording)
            {
                Overlay.ShowState(OverlayState.Error, "Note Taker is recording – press Right Shift ×3 to stop");
                Hotkeys.Reset();
                return;
            }
            if (!ModelReady)
            {
                Overlay.ShowState(OverlayState.Error, "Speech model still downloading – see the Just Say It window");
                Hotkeys.Reset();
                return;
            }
            if (Card.Visible) Card.Hide();
            scribe = isScribe;
            startedAt = DateTime.Now;
            ctx = ContextReader.Capture();
            LastContext = Describe(ctx);
            var hwnd = ctx.Window;
            screenTask = store.Prefs.UseScreenContext ? Task.Run(() => ScreenReader.Read(hwnd)) : null;
            try { Transcriber.Start(); }
            catch (Exception e)
            {
                Overlay.ShowState(OverlayState.Error, "Microphone error: " + e.Message);
                Hotkeys.Reset();
                return;
            }
            Sound(true);
            Overlay.ShowState(OverlayState.Listening, $"{ctx.AppName} · {Labels.Of(store.ToneFor(ctx.Category))}", isScribe, handsFree);
        });
    }

    void Cancel()
    {
        Ui.Run(() =>
        {
            Transcriber.Cancel();
            Overlay.ShowState(OverlayState.Hidden);
        });
    }

    async Task Finish()
    {
        if (!Transcriber.IsRecording || busy) return;
        busy = true;
        try
        {
            var duration = (DateTime.Now - startedAt).TotalSeconds;
            await Ui.Run(() => Overlay.ShowState(OverlayState.Thinking));
            Sound(false);
            var p = store.Prefs;
            var vocab = p.Vocabulary.Concat(p.Replacements.Select(r => r.Write)).ToList();
            var raw = await Transcriber.StopAndTranscribe(p.Model, p.Language, vocab);
            if (string.IsNullOrWhiteSpace(raw))
            {
                await Ui.Run(() => Overlay.ShowState(OverlayState.Error, "Didn't hear anything – try again"));
                return;
            }
            lastRaw = raw;
            if (screenTask != null)
            {
                var done = await Task.WhenAny(screenTask, Task.Delay(1500));
                if (done == screenTask) ctx.ScreenText = await screenTask;
                screenTask = null;
            }
            var text = await Process(raw);
            if (string.IsNullOrWhiteSpace(text)) { await Ui.Run(() => Overlay.ShowState(OverlayState.Hidden)); return; }
            LastResult = text;
            store.Record(new HistoryItem
            {
                Date = DateTime.Now, Raw = raw, Final = text, App = ctx.AppName,
                Seconds = duration, Words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length,
            });
            await Deliver(text);
        }
        catch (Exception e)
        {
            await Ui.Run(() => Overlay.ShowState(OverlayState.Error, "Error: " + e.Message));
        }
        finally { busy = false; StatusChanged?.Invoke(); }
    }

    async Task Deliver(string text)
    {
        var p = store.Prefs;
        var modeText = scribe ? "Scribe" : (ctx.SelectedText != null ? "Edit selection" : "Dictation");
        bool canType = ctx.FieldIsEditable != false;
        if (p.AutoInsert && canType)
        {
            await Inserter.Insert(text, ctx.Window, p.RestoreClipboard);
            await Ui.Run(() =>
            {
                Overlay.ShowState(OverlayState.Done);
                if (p.ShowResultCard)
                    Card.Present(text, modeText, LastContext, $"✓ Inserted into {ctx.AppName}. Edit and press Insert again, or Copy.", true, false);
            });
        }
        else
        {
            await Ui.Run(() =>
            {
                Overlay.ShowState(OverlayState.Hidden);
                Card.Present(text, modeText, LastContext,
                    "No text box was selected. Click into a text box and press Insert, or Copy.", false, true);
            });
        }
    }

    async Task<string> Process(string raw)
    {
        var p = store.Prefs;
        var (expanded, whole) = TextBrain.ExpandSnippets(raw, p.Snippets);
        if (whole) return expanded;
        var tone = store.ToneFor(ctx.Category);
        p.CustomInstructions.TryGetValue(ctx.Category, out var custom);
        var ruled = TextBrain.RuleClean(expanded);
        var output = ruled;

        if (ctx.SelectedText != null && !scribe && TextBrain.LooksLikeEditCommand(ruled))
            output = await TextBrain.EditSelection(ctx.SelectedText, ruled, ctx, tone) ?? ruled;
        else if (scribe)
            output = await TextBrain.Scribe(ruled, ctx, tone, custom) ?? ruled;
        else if (p.AiCleanup && (ruled.Split(' ').Length >= 3 || ruled.Contains('\n')))
        {
            var s = await TextBrain.Polish(ruled, ctx, tone, custom, p.Vocabulary);
            if (s != null && Plausible(s, ruled)) output = s;
        }
        output = TextBrain.ApplyReplacements(output, p.Replacements, p.Vocabulary);
        if (tone == Tone.VeryCasual && !scribe)
        {
            output = output.Trim();
            if (output.EndsWith('.') && !output[..^1].Contains('.')) output = output[..^1];
        }
        return TextBrain.FitToCursor(output, ctx.TextBeforeCursor);
    }

    static bool Plausible(string output, string input)
    {
        double a = output.Length, b = Math.Max(input.Length, 1);
        return a <= b * 1.8 + 40 && a >= b * 0.25;
    }

    string Describe(CaptureContext c)
    {
        var parts = new List<string> { c.AppName };
        if (c.Host != null) parts.Add(c.Host);
        else if (!string.IsNullOrEmpty(c.WindowTitle)) parts.Add("“" + (c.WindowTitle.Length > 50 ? c.WindowTitle[..50] : c.WindowTitle) + "”");
        parts.Add(Labels.Of(c.Category));
        parts.Add("tone: " + Labels.Of(store.ToneFor(c.Category)));
        if (c.SelectedText != null) parts.Add("selection captured");
        if (c.FieldIsEditable == true) parts.Add("text box ✓");
        else if (c.FieldIsEditable == false) parts.Add("no text box");
        if (store.Prefs.UseScreenContext) parts.Add("screen read");
        return string.Join(" · ", parts);
    }

    // MARK: Card actions

    async Task InsertFromCard()
    {
        var text = Card.Text2;
        Card.Hide();
        await Inserter.Insert(text, ctx.Window, store.Prefs.RestoreClipboard);
        Overlay.ShowState(OverlayState.Done);
    }

    async Task RewriteCard(RewriteStyle s)
    {
        Card.SetBusy(true);
        var output = await TextBrain.Rewrite(Card.Text2, s);
        Card.SetBusy(false);
        if (output == null) { Card.SetNote("Rewrite needs the local AI (Ollama). See Settings.", false); return; }
        Card.Text2 = output;
        LastResult = output;
        Card.SetNote($"Rewritten ({Labels.Of(s)}). Press Insert to replace, or Copy.", true);
    }

    public async Task RewriteSelection(RewriteStyle style)
    {
        await Ui.Run(() => { ctx = ContextReader.Capture(); });
        var text = ctx.SelectedText ?? await Inserter.CopySelection();
        if (string.IsNullOrWhiteSpace(text)) { Overlay.ShowState(OverlayState.Error, "Select some text first"); return; }
        Overlay.ShowState(OverlayState.Thinking);
        var output = await TextBrain.Rewrite(text, style);
        if (output == null) { Overlay.ShowState(OverlayState.Error, "Rewrite needs the local AI (Ollama) – see Settings"); return; }
        lastRaw = text;
        LastContext = Describe(ctx);
        scribe = false;
        LastResult = output;
        await Deliver(output);
    }

    public void Dispose()
    {
        Hotkeys.Dispose();
        Transcriber.Dispose();
    }
}
