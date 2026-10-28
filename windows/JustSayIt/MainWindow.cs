// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;

namespace JustSayIt;

public sealed class MainWindow : Form
{
    readonly Store store = Store.Shared;
    readonly Controller c = Controller.Shared;
    readonly TabControl tabs = new() { Dock = DockStyle.Fill, Padding = new Point(14, 6) };
    Label? modelLabel, aiLabel, statsLabel, lastLabel;
    readonly System.Windows.Forms.Timer refresh = new() { Interval = 1500 };

    static readonly Font H1 = new("Segoe UI Semibold", 20f);
    static readonly Font H2 = new("Segoe UI Semibold", 11f);
    static readonly Font Small = new("Segoe UI", 8.5f);

    public MainWindow()
    {
        Text = "Just Say It";
        Icon = Program.AppIcon;
        Font = new Font("Segoe UI", 9.5f);
        ClientSize = new Size(880, 640);
        MinimumSize = new Size(760, 560);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;

        tabs.TabPages.Add(HomeTab());
        tabs.TabPages.Add(NotesTab());
        tabs.TabPages.Add(StyleTab());
        tabs.TabPages.Add(DictionaryTab());
        tabs.TabPages.Add(SnippetsTab());
        tabs.TabPages.Add(RewriteTab());
        tabs.TabPages.Add(HistoryTab());
        tabs.TabPages.Add(SettingsTab());
        Controls.Add(tabs);

        c.StatusChanged += OnStatus;
        refresh.Tick += async (_, _) => await UpdateStatus();
        refresh.Start();
        Shown += async (_, _) => await UpdateStatus();
        FormClosed += (_, _) => { c.StatusChanged -= OnStatus; refresh.Stop(); };
    }

    void OnStatus() => Ui.Run(() => { _ = UpdateStatus(); });

    static FlowLayoutPanel Flow() => new()
    {
        Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
        AutoScroll = true, Padding = new Padding(22, 18, 22, 18), BackColor = Color.White,
    };

    static Label L(string text, Font? f = null, Color? color = null, int width = 780) => new()
    {
        Text = text, Font = f ?? new Font("Segoe UI", 9.5f), ForeColor = color ?? Color.Black,
        AutoSize = true, MaximumSize = new Size(width, 0), Margin = new Padding(0, 4, 0, 4),
    };

    static GroupBox Group(string title, Control content)
    {
        var g = new GroupBox { Text = title, Font = H2, AutoSize = true, Padding = new Padding(12), Margin = new Padding(0, 10, 0, 6), MinimumSize = new Size(800, 0) };
        content.Font = new Font("Segoe UI", 9.5f);
        content.Dock = DockStyle.Fill;
        g.Controls.Add(content);
        return g;
    }

    // MARK: Home

    TabPage HomeTab()
    {
        var page = new TabPage("Home");
        var f = Flow();
        f.Controls.Add(L("Just Say It", H1));
        f.Controls.Add(L("Free, unlimited, private voice typing. Speech recognition runs on your PC.", null, Color.DimGray));
        f.Controls.Add(L("Created by Stefano Roman Gunness", Small, Color.Gray));

        var setup = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        modelLabel = L("", null, null, 760);
        aiLabel = L("", null, null, 760);
        var aiBtn = new Button { Text = "Get the free local AI (Ollama)", AutoSize = true };
        aiBtn.Click += (_, _) => Open("https://ollama.com/download/windows");
        setup.Controls.Add(modelLabel);
        setup.Controls.Add(aiLabel);
        setup.Controls.Add(aiBtn);
        f.Controls.Add(Group("Setup", setup));

        var hk = Labels.Of(store.Prefs.Hotkey);
        var how = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        foreach (var line in new[]
        {
            $"🎙  Hold {hk}, speak, release. Text appears where your cursor is.",
            $"✋  Double-tap {hk} for hands-free. Tap once more to finish. Esc cancels.",
            $"✨  Hold Shift + {hk} for Scribe: say what you want, get a polished message.",
            "↩  Say \"scratch that\" to drop the last sentence; \"new line\" / \"new paragraph\" for layout.",
            "✂  Select text and hold the key to give an instruction (\"make this shorter\").",
            "🪄  Select text and press Ctrl+Alt+R to make it concise (more styles in the tray menu).",
            "📝  Press Right Shift three times to start the Note Taker; three times again to stop.",
        }) how.Controls.Add(L(line, null, null, 760));
        f.Controls.Add(Group("How to use", how));

        statsLabel = L("", H2);
        f.Controls.Add(statsLabel);
        lastLabel = L("", null, Color.DimGray);
        f.Controls.Add(lastLabel);
        page.Controls.Add(f);
        return page;
    }

    async Task UpdateStatus()
    {
        if (IsDisposed) return;
        if (modelLabel != null) modelLabel.Text = (c.ModelReady ? "✅ " : "⏳ ") + c.ModelStatus;
        var ai = await TextBrain.AiAvailable();
        if (aiLabel != null)
            aiLabel.Text = ai
                ? $"✅ Smart AI cleanup, Scribe and Rewrite ready (Ollama · {store.Prefs.OllamaModel})"
                : $"⚠️ Smart AI is optional. Install Ollama, then run:  ollama pull {store.Prefs.OllamaModel}   (basic cleanup works without it)";
        var p = store.Prefs;
        int wpm = p.TotalSeconds > 5 ? (int)(p.TotalWords / (p.TotalSeconds / 60)) : 0;
        if (statsLabel != null) statsLabel.Text = $"{p.TotalWords} words dictated   ·   {(wpm > 0 ? wpm.ToString() : "–")} words/min   ·   {p.TotalWords / 40} min saved vs typing";
        if (lastLabel != null) lastLabel.Text = string.IsNullOrEmpty(c.LastResult) ? "" : $"Last dictation ({c.LastContext}):\n{c.LastResult}";
    }

    // MARK: Note Taker

    TabPage NotesTab()
    {
        var page = new TabPage("Note Taker");
        var f = Flow();
        f.Controls.Add(L("Press Right Shift three times to record a conversation, and three times again to stop. You get a live transcript, then a summary with key points, decisions and action items.", null, Color.DimGray));
        var row = new FlowLayoutPanel { AutoSize = true };
        var toggle = new Button { Text = "Start / Stop Note Taker", AutoSize = true };
        toggle.Click += (_, _) => c.ToggleNotes();
        var show = new Button { Text = "Show live window", AutoSize = true };
        show.Click += (_, _) => NoteWindow.ShowShared();
        var folder = new Button { Text = "Open notes folder", AutoSize = true };
        folder.Click += (_, _) => Open(NoteTaker.NotesDir);
        row.Controls.AddRange(new Control[] { toggle, show, folder });
        f.Controls.Add(row);
        f.Controls.Add(L("Me: your microphone · Others: computer audio (Zoom, Meet, Teams…). Transcribed on this PC; notes are saved as Markdown in Documents › Just Say It Notes. Always tell people when you're recording them.", Small, Color.Gray));
        var list = new ListBox { Width = 800, Height = 300 };
        void Reload()
        {
            list.Items.Clear();
            foreach (var file in Directory.GetFiles(NoteTaker.NotesDir, "*.md").OrderByDescending(File.GetLastWriteTime))
                list.Items.Add(Path.GetFileName(file));
        }
        page.Enter += (_, _) => Reload();
        list.DoubleClick += (_, _) => { if (list.SelectedItem is string n) Open(Path.Combine(NoteTaker.NotesDir, n)); };
        f.Controls.Add(L("Saved notes (double-click to open)", H2));
        f.Controls.Add(list);
        page.Controls.Add(f);
        return page;
    }

    // MARK: Tone & Style

    TabPage StyleTab()
    {
        var page = new TabPage("Tone & Style");
        var f = Flow();
        f.Controls.Add(L("Just Say It detects the app or website you're typing in and adjusts the tone automatically.", null, Color.DimGray));
        foreach (AppCategory cat in Enum.GetValues<AppCategory>())
        {
            var cc = cat;
            var panel = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Width = 770 };
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
            panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 640));
            var combo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
            foreach (Tone t in Enum.GetValues<Tone>()) combo.Items.Add(Labels.Of(t));
            combo.SelectedIndex = (int)store.ToneFor(cc);
            combo.SelectedIndexChanged += (_, _) => { store.Prefs.Tones[cc] = (Tone)combo.SelectedIndex; store.Save(); };
            var custom = new TextBox { Width = 620, PlaceholderText = "Personal style, e.g. \"Sign emails with – Stefano\" or \"Never use emojis\"" };
            custom.Text = store.Prefs.CustomInstructions.TryGetValue(cc, out var ci) ? ci : "";
            custom.Leave += (_, _) => { store.Prefs.CustomInstructions[cc] = custom.Text; store.Save(); };
            panel.Controls.Add(new Label { Text = "Tone", AutoSize = true, Margin = new Padding(0, 6, 0, 0) }, 0, 0);
            panel.Controls.Add(combo, 1, 0);
            panel.Controls.Add(new Label { Text = "Style", AutoSize = true, Margin = new Padding(0, 6, 0, 0) }, 0, 1);
            panel.Controls.Add(custom, 1, 1);
            f.Controls.Add(Group(Labels.Of(cc), panel));
        }
        page.Controls.Add(f);
        return page;
    }

    // MARK: Dictionary

    TabPage DictionaryTab()
    {
        var page = new TabPage("Dictionary");
        var f = Flow();

        var words = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        words.Controls.Add(L("Names, brands, acronyms and jargon. Fed to the speech engine and always spelled exactly like this.", Small, Color.DimGray));
        var row = new FlowLayoutPanel { AutoSize = true };
        var input = new TextBox { Width = 400, PlaceholderText = "e.g. Kubernetes, metoprolol, OpenCode" };
        var add = new Button { Text = "Add", AutoSize = true };
        row.Controls.Add(input); row.Controls.Add(add);
        var list = new ListBox { Width = 500, Height = 160 };
        var remove = new Button { Text = "Remove selected", AutoSize = true };
        void Reload() { list.Items.Clear(); foreach (var w in store.Prefs.Vocabulary) list.Items.Add(w); }
        Reload();
        void AddWord()
        {
            var w = input.Text.Trim();
            if (w.Length == 0 || store.Prefs.Vocabulary.Contains(w)) return;
            store.Prefs.Vocabulary.Add(w); store.Save(); input.Clear(); Reload();
        }
        add.Click += (_, _) => AddWord();
        input.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) { AddWord(); e.SuppressKeyPress = true; } };
        remove.Click += (_, _) => { if (list.SelectedItem is string w) { store.Prefs.Vocabulary.Remove(w); store.Save(); Reload(); } };
        words.Controls.Add(row); words.Controls.Add(list); words.Controls.Add(remove);
        f.Controls.Add(Group("My words", words));

        var reps = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        reps.Controls.Add(L("Fix words that are always misheard.", Small, Color.DimGray));
        var row2 = new FlowLayoutPanel { AutoSize = true };
        var heard = new TextBox { Width = 250, PlaceholderText = "When I say…" };
        var write = new TextBox { Width = 250, PlaceholderText = "Write…" };
        var add2 = new Button { Text = "Add", AutoSize = true };
        row2.Controls.Add(heard); row2.Controls.Add(new Label { Text = "→", AutoSize = true, Margin = new Padding(4, 6, 4, 0) }); row2.Controls.Add(write); row2.Controls.Add(add2);
        var list2 = new ListBox { Width = 500, Height = 140 };
        var remove2 = new Button { Text = "Remove selected", AutoSize = true };
        void Reload2() { list2.Items.Clear(); foreach (var r in store.Prefs.Replacements) list2.Items.Add($"{r.Heard}  →  {r.Write}"); }
        Reload2();
        add2.Click += (_, _) =>
        {
            if (heard.Text.Trim().Length == 0 || write.Text.Trim().Length == 0) return;
            store.Prefs.Replacements.Add(new Replacement { Heard = heard.Text.Trim(), Write = write.Text.Trim() });
            store.Save(); heard.Clear(); write.Clear(); Reload2();
        };
        remove2.Click += (_, _) => { if (list2.SelectedIndex >= 0) { store.Prefs.Replacements.RemoveAt(list2.SelectedIndex); store.Save(); Reload2(); } };
        reps.Controls.Add(row2); reps.Controls.Add(list2); reps.Controls.Add(remove2);
        f.Controls.Add(Group("Auto-replace", reps));
        page.Controls.Add(f);
        return page;
    }

    // MARK: Snippets

    TabPage SnippetsTab()
    {
        var page = new TabPage("Snippets");
        var f = Flow();
        f.Controls.Add(L("Say the trigger on its own (or \"insert <trigger>\" mid-sentence) to paste the full text.", null, Color.DimGray));
        var panel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        var trigger = new TextBox { Width = 400, PlaceholderText = "Trigger phrase, e.g. \"my address\"" };
        var text = new TextBox { Width = 760, Height = 90, Multiline = true, ScrollBars = ScrollBars.Vertical, PlaceholderText = "Full text to insert" };
        var add = new Button { Text = "Add snippet", AutoSize = true };
        var list = new ListBox { Width = 760, Height = 200 };
        var remove = new Button { Text = "Remove selected", AutoSize = true };
        void Reload() { list.Items.Clear(); foreach (var s in store.Prefs.Snippets) list.Items.Add($"“{s.Trigger}”  →  {s.Text.Replace("\r", "").Replace("\n", " ⏎ ")}"); }
        Reload();
        add.Click += (_, _) =>
        {
            if (trigger.Text.Trim().Length == 0 || text.Text.Length == 0) return;
            store.Prefs.Snippets.Add(new Snippet { Trigger = trigger.Text.Trim(), Text = text.Text.Replace("\r\n", "\n") });
            store.Save(); trigger.Clear(); text.Clear(); Reload();
        };
        remove.Click += (_, _) => { if (list.SelectedIndex >= 0) { store.Prefs.Snippets.RemoveAt(list.SelectedIndex); store.Save(); Reload(); } };
        panel.Controls.AddRange(new Control[] { trigger, text, add });
        f.Controls.Add(Group("New snippet", panel));
        f.Controls.Add(list);
        f.Controls.Add(remove);
        page.Controls.Add(f);
        return page;
    }

    // MARK: Rewrite

    TabPage RewriteTab()
    {
        var page = new TabPage("AI Rewrite");
        var f = Flow();
        f.Controls.Add(L("Select text in any app and press Ctrl+Alt+R, or use the tray menu › Rewrite. You can also paste text here.", null, Color.DimGray));
        var input = new TextBox { Width = 800, Height = 130, Multiline = true, ScrollBars = ScrollBars.Vertical };
        var output = new TextBox { Width = 800, Height = 150, Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true, BackColor = Color.FromArgb(248, 248, 252) };
        var buttons = new FlowLayoutPanel { AutoSize = true, Width = 800 };
        foreach (RewriteStyle s in Enum.GetValues<RewriteStyle>())
        {
            var style = s;
            var b = new Button { Text = Labels.Of(s), AutoSize = true };
            b.Click += async (_, _) =>
            {
                var src = input.Text.Length > 0 ? input.Text : c.LastResult;
                if (src.Length == 0) return;
                buttons.Enabled = false;
                output.Text = "Working…";
                output.Text = await TextBrain.Rewrite(src, style) ?? "Rewrite needs the free local AI. Install Ollama (see Home).";
                buttons.Enabled = true;
            };
            buttons.Controls.Add(b);
        }
        var copy = new Button { Text = "Copy result", AutoSize = true };
        copy.Click += (_, _) => { if (output.Text.Length > 0) Inserter.SetClipboard(output.Text); };
        f.Controls.AddRange(new Control[] { input, buttons, output, copy });
        page.Controls.Add(f);
        return page;
    }

    // MARK: History

    TabPage HistoryTab()
    {
        var page = new TabPage("History");
        var f = Flow();
        f.Controls.Add(L("Recent dictations (stored only on this PC). Double-click to copy.", null, Color.DimGray));
        var list = new ListView { View = View.Details, FullRowSelect = true, Width = 810, Height = 420 };
        list.Columns.Add("When", 130); list.Columns.Add("App", 140); list.Columns.Add("Text", 520);
        void Reload()
        {
            list.Items.Clear();
            foreach (var h in store.History)
                list.Items.Add(new ListViewItem(new[] { h.Date.ToString("g"), h.App, h.Final.Replace("\n", " ") }) { Tag = h });
        }
        Reload();
        page.Enter += (_, _) => Reload();
        list.DoubleClick += (_, _) => { if (list.SelectedItems.Count > 0 && list.SelectedItems[0].Tag is HistoryItem h) Inserter.SetClipboard(h.Final); };
        var clear = new Button { Text = "Clear history", AutoSize = true };
        clear.Click += (_, _) => { store.ClearHistory(); Reload(); };
        f.Controls.Add(list); f.Controls.Add(clear);
        page.Controls.Add(f);
        return page;
    }

    // MARK: Settings

    TabPage SettingsTab()
    {
        var page = new TabPage("Settings");
        var f = Flow();
        var p = store.Prefs;
        var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Width = 800 };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 230));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 560));
        int r = 0;
        void Row(string label, Control ctl) { grid.Controls.Add(new Label { Text = label, AutoSize = true, Margin = new Padding(0, 8, 0, 0) }, 0, r); grid.Controls.Add(ctl, 1, r); r++; }

        var hotkey = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
        foreach (HotkeyChoice h in Enum.GetValues<HotkeyChoice>()) hotkey.Items.Add(Labels.Of(h));
        hotkey.SelectedIndex = (int)p.Hotkey;
        hotkey.SelectedIndexChanged += (_, _) => c.SetHotkey((HotkeyChoice)hotkey.SelectedIndex);
        Row("Dictation hotkey", hotkey);

        var model = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 360 };
        foreach (ModelSize m in Enum.GetValues<ModelSize>()) model.Items.Add(Labels.Of(m));
        model.SelectedIndex = (int)p.Model;
        model.SelectedIndexChanged += async (_, _) => { p.Model = (ModelSize)model.SelectedIndex; store.Save(); await c.PrepareModel(); };
        Row("Speech model", model);

        var langs = new (string code, string name)[]
        {
            ("auto", "Auto-detect (100 languages)"), ("en", "English"), ("es", "Spanish"), ("pt", "Portuguese"), ("fr", "French"),
            ("de", "German"), ("it", "Italian"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"), ("uk", "Ukrainian"),
            ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"), ("zh", "Chinese"), ("ja", "Japanese"), ("ko", "Korean"),
            ("vi", "Vietnamese"), ("th", "Thai"), ("id", "Indonesian"), ("sv", "Swedish"), ("el", "Greek"), ("ro", "Romanian"),
        };
        var lang = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
        foreach (var l in langs) lang.Items.Add(l.name);
        lang.SelectedIndex = Math.Max(0, Array.FindIndex(langs, l => l.code == p.Language));
        lang.SelectedIndexChanged += (_, _) => { p.Language = langs[lang.SelectedIndex].code; store.Save(); };
        Row("Language", lang);

        var url = new TextBox { Width = 300, Text = p.OllamaUrl };
        url.Leave += (_, _) => { p.OllamaUrl = url.Text.Trim(); store.Save(); TextBrain.ResetAiCheck(); };
        Row("Local AI address (Ollama)", url);
        var llm = new TextBox { Width = 300, Text = p.OllamaModel };
        llm.Leave += (_, _) => { p.OllamaModel = llm.Text.Trim(); store.Save(); TextBrain.ResetAiCheck(); _ = TextBrain.Prewarm(); };
        Row("Local AI model", llm);

        CheckBox Check(string text, bool value, Action<bool> set)
        {
            var cb = new CheckBox { Text = text, Checked = value, AutoSize = true };
            cb.CheckedChanged += (_, _) => { set(cb.Checked); store.Save(); };
            return cb;
        }
        Row("", Check("Smart AI cleanup (fillers, corrections, lists, tone)", p.AiCleanup, v => p.AiCleanup = v));
        Row("", Check("Use what's on screen as context (offline Windows OCR)", p.UseScreenContext, v => p.UseScreenContext = v));
        Row("", Check("Note Taker: Right Shift × 3 starts/stops it", p.NoteTakerEnabled, v => p.NoteTakerEnabled = v));
        Row("", Check("Note Taker: also record computer audio (the other people on a call)", p.NoteCaptureSystemAudio, v => p.NoteCaptureSystemAudio = v));
        Row("", Check("Insert automatically into the selected text box", p.AutoInsert, v => p.AutoInsert = v));
        Row("", Check("Always show the result card (edit, copy, rewrite)", p.ShowResultCard, v => p.ShowResultCard = v));
        Row("", Check("Play start/stop sounds", p.PlaySounds, v => p.PlaySounds = v));
        Row("", Check("Restore my clipboard after inserting", p.RestoreClipboard, v => p.RestoreClipboard = v));
        Row("", Check("Start Just Say It with Windows", p.StartWithWindows, v => { p.StartWithWindows = v; Program.SetStartWithWindows(v); }));
        f.Controls.Add(grid);
        var link = new LinkLabel { Text = "github.com/stefanoromang/just-say-it", AutoSize = true, Margin = new Padding(0, 20, 0, 0) };
        link.LinkClicked += (_, _) => Open("https://github.com/stefanoromang/just-say-it");
        f.Controls.Add(L("Just Say It 1.4 · © 2026 Stefano Roman Gunness · MIT License", Small, Color.Gray));
        f.Controls.Add(link);
        page.Controls.Add(f);
        return page;
    }

    static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Closing the window keeps the app running in the tray.
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
