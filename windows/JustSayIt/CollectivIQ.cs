// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace JustSayIt;

/// Sends Note Taker transcripts to CollectivIQ inside Just Say It (no external browser).
/// CollectivIQ runs in an in-app window; each person signs in there once and the
/// window remembers the session. When a recording ends, the app opens a new chat,
/// types the prompt + full transcript into the chat box and presses Send.
public static class CollectivIQ
{
    public const string ChatUrl = "https://collectiviq.ai/chat";
    public const string LoginUrl = "https://collectiviq.ai/login";
    public const string DefaultPrompt = Prompts.CiqStandard;

    public static string Message(string prompt, string? title, string transcript)
    {
        // The prompt ends with "HERE IS THE INFORMATION :" so the note follows right after it.
        var s = (string.IsNullOrWhiteSpace(prompt) ? DefaultPrompt : prompt.Trim()) + "\n\n";
        if (!string.IsNullOrWhiteSpace(title)) s += $"Meeting: {title}\n\n";
        return s + transcript;
    }

    public enum Choice { Raw, Ai, Both }

    /// Where a message goes: a new CIQ chat, or a DDR's direct-message chat (e.g. "Notetaker").
    public record Destination(string? Ddr)
    {
        public static readonly Destination Chat = new((string?)null);
    }

    public static string RawMessage(string? title, string raw) =>
        "RAW TRANSCRIPT (exactly as heard)" + (string.IsNullOrWhiteSpace(title) ? "" : $" – {title}") + "\n\n" + raw;

    public static Choice ParseChoice(string? s) => (s ?? "").ToLowerInvariant() switch
    {
        "raw" => Choice.Raw,
        "ai" => Choice.Ai,
        _ => Choice.Both,
    };

    /// Where automatic sends go: the DDR (when one is named) or a new CIQ chat.
    public static Destination AutoDestination(Prefs p) =>
        p.CiqAutoWhere == "ddr" && !string.IsNullOrWhiteSpace(p.CiqDdrName) ? new Destination(p.CiqDdrName.Trim()) : Destination.Chat;

    /// Called when a recording is saved. With automatic (call ended / End Note Taker) it sends right
    /// away using the saved defaults; otherwise it asks what to send and where.
    public static void Deliver(string? title, string raw, string? smart, bool automatic = false)
    {
        var p = Store.Shared.Prefs;
        if (!p.CiqEnabled || string.IsNullOrWhiteSpace(raw)) return;
        Ui.Run(() =>
        {
            Choice? choice = automatic ? ParseChoice(p.CiqAutoWhat) : AskWhat();
            if (choice == null) return;
            var dest = automatic ? AutoDestination(p) : AskWhere();
            if (dest == null) return;
            var ai = Message(p.CiqPrompt, title, smart ?? raw);
            var text = choice switch
            {
                Choice.Raw => RawMessage(title, raw),
                Choice.Ai => ai,
                _ => RawMessage(title, raw) + "\n\n" + new string('─', 40) + "\n\n" + ai,
            };
            CIQWindow.Shared.SendMessages(new List<string> { text }, dest);
        });
    }

    /// For "Send my last note now" (asks where; no "what" question).
    public static void Send(string? title, string transcript, bool force = false)
    {
        var p = Store.Shared.Prefs;
        if ((!p.CiqEnabled && !force) || string.IsNullOrWhiteSpace(transcript)) return;
        Ui.Run(() =>
        {
            var dest = AskWhere();
            if (dest == null) return;
            CIQWindow.Shared.SendMessages(new List<string> { Message(p.CiqPrompt, title, transcript) }, dest);
        });
    }

    static int? Choose(string title, string info, string[] buttons)
    {
        using var f = new Form
        {
            Text = "Just Say It – CollectivIQ", FormBorderStyle = FormBorderStyle.FixedDialog, StartPosition = FormStartPosition.CenterScreen,
            TopMost = true, MinimizeBox = false, MaximizeBox = false, ClientSize = new Size(500, 180), Font = new Font("Segoe UI", 9.5f), Icon = Program.AppIcon,
        };
        f.Controls.Add(new Label { Text = title, Font = new Font("Segoe UI Semibold", 11f), AutoSize = false, Bounds = new Rectangle(16, 12, 470, 26) });
        f.Controls.Add(new Label { Text = info, AutoSize = false, Bounds = new Rectangle(16, 40, 470, 80) });
        int? result = null;
        int x = 16;
        for (int i = 0; i <= buttons.Length; i++)
        {
            var idx = i;
            var label = i < buttons.Length ? buttons[i] : "Don't send";
            var btn = new Button { Text = label, AutoSize = true, MinimumSize = new Size(100, 32), Location = new Point(x, 132) };
            btn.Click += (_, _) => { result = idx < buttons.Length ? idx : null; f.Close(); };
            f.Controls.Add(btn);
            x += Math.Max(108, TextRenderer.MeasureText(label, f.Font).Width + 30);
        }
        f.ShowDialog();
        return result;
    }

    static Choice? AskWhat() => Choose("Send this recording to CollectivIQ?",
        "Raw: the transcript exactly as heard.\nAI version: your prompt + the transcript with words and logic fixed.\nBoth: raw first, then the AI version, in the same chat.",
        new[] { "AI version", "Raw", "Both" }) switch { 0 => Choice.Ai, 1 => Choice.Raw, 2 => Choice.Both, _ => null };

    static Destination? AskWhere()
    {
        var ddr = (Store.Shared.Prefs.CiqDdrName ?? "").Trim();
        if (ddr.Length == 0) return Destination.Chat;
        var model = string.IsNullOrEmpty(Store.Shared.Prefs.CiqModel) ? "All · Auto" : Store.Shared.Prefs.CiqModel;
        return Choose("Where should it go?",
            $"CIQ Chat: a new CollectivIQ chat (answered by {model}).\nDDR: your {ddr} DDR's chat.",
            new[] { "CIQ Chat", $"DDR: {ddr}" }) switch { 0 => Destination.Chat, 1 => new Destination(ddr), _ => null };
    }

    /// Opens a DDR's direct-message chat, pastes the message and presses Send.
    public static string DdrScript(string msg, string ddr) =>
        "(" + DdrSteps + ")(" + JsonSerializer.Serialize(msg) + ", " + JsonSerializer.Serialize(ddr) + ")";

    const string DdrSteps = """
        (function(msg, ddrName){
          var S = window.__jsiddr || (window.__jsiddr = {});
          if (location.pathname.indexOf('/login') === 0) return 'login';
          function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
          var want = ddrName.toLowerCase().replace(/[^a-z0-9]/g, '');
          // 1. Open the DDR's direct-message chat from the sidebar (or the left rail).
          if (location.pathname.indexOf('/chat/ddr/dm') !== 0) {
            if (S.clicked && Date.now() - S.clicked < 4000) return 'wait';
            var entries = Array.prototype.slice.call(document.querySelectorAll('[data-testid=ddr-dm-entry], [data-testid=chat-rail-persona-button]'));
            if (!entries.length) return 'wait';
            var hit = entries.filter(function(e){
              var name = (txt(e.querySelector('.name')) || e.getAttribute('title') || e.getAttribute('aria-label') || txt(e)).toLowerCase().replace(/[^a-z0-9]/g, '');
              return name.indexOf(want) >= 0;
            })[0];
            if (!hit) return 'ddr:missing';
            S.clicked = Date.now(); hit.click(); return 'ddr:open';
          }
          // 2. Paste into the DDR composer and press Send.
          var ta = document.querySelector('textarea[data-testid=ddr-composer-input]');
          if (!ta || ta.disabled) return 'wait';
          var b = document.querySelector('[data-testid=ddr-send-button]');
          if (ta.value === msg && b && !b.disabled) { b.click(); S.sentAt = Date.now(); return 'sent'; }
          if (ta.value !== msg) {
            var setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
            ta.focus(); setter.call(ta, msg);
            ta.dispatchEvent(new Event('input', {bubbles: true}));
            ta.dispatchEvent(new Event('change', {bubbles: true}));
          }
          return 'filled';
        })
        """;

    public static void Notify(string title, string body) =>
        Ui.Run(() => Program.Tray?.ShowBalloonTip(5000, title, body, ToolTipIcon.Info));

    public static void OpenChat(bool signIn = false) => Ui.Run(() => CIQWindow.Shared.ShowAt(signIn ? LoginUrl : ChatUrl));


    /// Picks the model (All · Auto → All Selected → only <model> → Apply Changes), then fills the
    /// chat box and presses Send. Returns "login", "wait", "model:…", "filled" or "sent".
    public static string Script(string msg) =>
        "(" + Steps + ")(" + JsonSerializer.Serialize(msg) + ", " + JsonSerializer.Serialize(Store.Shared.Prefs.CiqModel ?? "") + ")";

    public const string Reset = "window.__jsi = undefined; window.__jsiddr = undefined; 'ok'";

    const string Steps = """
        (function(msg, model){
          var S = window.__jsi || (window.__jsi = {modelDone: !model});
          if (location.pathname.indexOf('/login') === 0) return 'login';
          function txt(e){ return (e && (e.innerText || e.textContent) || '').trim(); }
          // 1. Pick the model: All · Auto -> All Selected -> only <model> -> Apply Changes
          if (!S.modelDone) {
            var modal = document.querySelector('app-model-config-modal [role=dialog], app-model-config-modal .modal');
            if (!modal) {
              var trig = document.querySelector('[data-testid=model-config-trigger]');
              if (!trig) return 'wait';
              if (S.opened && Date.now() - S.opened < 4000) return 'wait';
              S.opened = Date.now(); trig.click(); return 'model:open';
            }
            var chips = Array.prototype.slice.call(modal.querySelectorAll('button.model-chip'));
            if (!chips.length) return 'wait';
            var want = model.toLowerCase();
            var target = chips.filter(function(c){ return txt(c.querySelector('.provider') || c).toLowerCase().indexOf(want) >= 0; })[0];
            if (!target) { S.modelDone = true; var x = modal.querySelector('.plain-btn, [aria-label="Close modal"]'); if (x) x.click(); return 'model:missing'; }
            var all = modal.querySelector('button.text-btn');
            if (!S.cleared && all && /all selected/i.test(txt(all))) { S.cleared = true; all.click(); return 'model:all-selected'; }
            S.cleared = true;
            if (!target.classList.contains('is-selected')) { target.click(); return 'model:pick'; }
            var others = chips.filter(function(c){ return c !== target && c.classList.contains('is-selected') && !c.disabled; });
            if (others.length) { others[0].click(); return 'model:trim'; }
            var apply = modal.querySelector('button.apply-btn');
            if (apply && !apply.disabled) { S.modelDone = true; apply.click(); return 'model:apply'; }
            S.modelDone = true; var c2 = modal.querySelector('.plain-btn, [aria-label="Close modal"]'); if (c2) c2.click(); return 'model:unchanged';
          }
          if (document.querySelector('app-model-config-modal [role=dialog], app-model-config-modal .modal')) return 'wait';
          // 2. Paste the prompt + transcript and press Send
          var h = document.querySelector('wa-textarea[data-testid=chat-input]');
          if (!h || !h.shadowRoot) return 'wait';
          var ta = h.shadowRoot.querySelector('textarea');
          if (!ta) return 'wait';
          var b = document.querySelector('[data-testid=send-button]');
          if (h.value === msg && b && !b.hasAttribute('disabled')) { b.click(); return 'sent'; }
          if (h.value !== msg) {
            ta.focus(); ta.value = msg;
            ta.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            try { h.value = msg; } catch (e) {}
            h.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            h.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
          }
          return 'filled';
        })
        """;
}

/// The in-app CollectivIQ window (WebView2). Works hidden in the background and is shown
/// only when the person must sign in. Sign-in is kept in the user's profile folder.
public sealed class CIQWindow : Form
{
    static CIQWindow? shared;
    public static CIQWindow Shared => shared == null || shared.IsDisposed ? (shared = new CIQWindow()) : shared;
    /// Sending to CollectivIQ right now (without creating the window).
    public static bool Sending => shared != null && !shared.IsDisposed && shared.IsBusy;

    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    Task? ready;
    sealed class Item(string text, CollectivIQ.Destination dest)
    {
        public readonly string Text = text;
        public CollectivIQ.Destination Destination = dest;
    }
    readonly Queue<Item> queue = new();
    /// The page shown has been loaded fresh for the message at the front of the queue.
    Item? pageReadyFor;
    bool ticking, loading;
    /// Sending or waiting to send.
    public bool IsBusy => timer.Enabled || queue.Count > 0;
    DateTime startedAt;
    DateTime? settleUntil;
    int sent;
    bool shownForLogin, background, resetHooked;

    CIQWindow()
    {
        Text = "Sign in to CollectivIQ – Just Say It";
        Icon = Program.AppIcon;
        ClientSize = new Size(1100, 780);
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;
        Controls.Add(web);
        timer.Tick += async (_, _) =>
        {
            if (ticking) return;   // one step at a time, so nothing is sent twice
            ticking = true;
            try { await Tick(); } catch { }
            finally { ticking = false; }
        };
    }

    // Created with a window handle but never shown unless sign-in is needed.
    protected override void SetVisibleCore(bool value) => base.SetVisibleCore(background ? false : value);

    Task Ready()
    {
        if (ready != null) return ready;
        _ = Handle;
        var dataDir = Path.Combine(Store.Dir, "CollectivIQ");
        ready = CoreWebView2Environment.CreateAsync(null, dataDir).ContinueWith(t => web.EnsureCoreWebView2Async(t.Result),
            TaskScheduler.FromCurrentSynchronizationContext()).Unwrap();
        // If it fails, try again next time instead of failing forever.
        ready.ContinueWith(_ => ready = null, CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.FromCurrentSynchronizationContext());
        return ready;
    }

    /// Shows the window (sign-in, or opened from Settings).
    public async void ShowAt(string url)
    {
        background = false;
        ShowInTaskbar = true;
        Show(); WindowState = FormWindowState.Normal; Activate();
        try { await Ready(); web.CoreWebView2.Navigate(url); }
        catch (Exception e)
        {
            MessageBox.Show("CollectivIQ couldn't open: " + e.Message + "\n\nWindows needs the Microsoft Edge WebView2 Runtime (included in Windows 10/11 updates).",
                "Just Say It", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    /// Sends the messages one after another in the background, each to a new chat.
    public async void SendMessages(List<string> msgs, CollectivIQ.Destination? dest = null)
    {
        if (msgs.Count == 0) return;
        bool wasIdle = !timer.Enabled;
        foreach (var m in msgs) queue.Enqueue(new Item(m, dest ?? CollectivIQ.Destination.Chat));
        settleUntil = null;
        if (!wasIdle) return;   // already sending: the new messages wait their turn
        sent = 0; shownForLogin = false; startedAt = DateTime.Now; pageReadyFor = null;
        if (Store.Shared.Prefs.CiqShowPreview) { background = false; ShowInTaskbar = true; Text = "CollectivIQ – Just Say It (preview)"; Show(); Activate(); }
        else if (!Visible) { background = true; ShowInTaskbar = false; }
        CollectivIQ.Notify("JustSayIt – syncing with CollectivIQ", "Your notes are being synced and processed inside CollectivIQ.");
        try
        {
            await Ready();
            if (!resetHooked)
            {
                resetHooked = true;
                web.CoreWebView2.NavigationCompleted += async (_, _) =>
                {
                    try { await web.CoreWebView2.ExecuteScriptAsync(CollectivIQ.Reset); } catch { }
                    loading = false;
                };
            }
        }
        catch { CollectivIQ.Notify("JustSayIt – CollectivIQ", "CollectivIQ couldn't start (WebView2 Runtime missing?). Your notes are saved on this PC."); queue.Clear(); return; }
        timer.Start();
    }

    async Task Tick()
    {
        if (web.CoreWebView2 == null) return;
        if (settleUntil != null)
        {
            if (DateTime.Now < settleUntil) return;
            timer.Stop(); settleUntil = null;
            Controller.Shared.Overlay.ShowState(OverlayState.Done, "Sent to CollectivIQ");
            CollectivIQ.Notify("JustSayIt – sent to CollectivIQ",
                sent > 1 ? $"{sent} transcripts were sent. CollectivIQ is processing your notes." : "Your transcript was sent. CollectivIQ is processing your notes.");
            return;
        }
        if (queue.Count == 0) { settleUntil = DateTime.Now.AddSeconds(10); return; }
        if ((DateTime.Now - startedAt).TotalMinutes > 15)
        {
            timer.Stop(); queue.Clear();
            CollectivIQ.Notify("JustSayIt – CollectivIQ", "CollectivIQ didn't respond. Your notes are saved on this PC.");
            return;
        }
        var item = queue.Peek();
        // Each message starts on its own freshly loaded page.
        if (!ReferenceEquals(pageReadyFor, item)) { pageReadyFor = item; loading = true; web.CoreWebView2.Navigate(CollectivIQ.ChatUrl); return; }
        if (loading) return;
        string result;
        var dest = item.Destination;
        var js = dest.Ddr == null ? CollectivIQ.Script(item.Text) : CollectivIQ.DdrScript(item.Text, dest.Ddr);
        try { result = JsonSerializer.Deserialize<string>(await web.CoreWebView2.ExecuteScriptAsync(js)) ?? ""; }
        catch { return; }
        if (queue.Count == 0 || !ReferenceEquals(queue.Peek(), item)) return;
        if (result == "sent")
        {
            queue.Dequeue(); sent++;
            if (shownForLogin && !Store.Shared.Prefs.CiqShowPreview) { background = true; Hide(); }
            shownForLogin = false;
            startedAt = DateTime.Now;
        }
        else if (result == "ddr:missing" && dest.Ddr != null)
        {
            CollectivIQ.Notify("JustSayIt – DDR not found", $"No DDR called {dest.Ddr} was found, so the notes go to a new CIQ chat instead.");
            item.Destination = CollectivIQ.Destination.Chat;
            pageReadyFor = null;
        }
        else if (result == "login" && !shownForLogin)
        {
            shownForLogin = true;
            background = false; ShowInTaskbar = true;
            Show(); WindowState = FormWindowState.Normal; Activate();
            CollectivIQ.Notify("Sign in to CollectivIQ", "Your session expired. Sign in once and your notes are sent automatically.");
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
