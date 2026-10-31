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

    public enum Choice { Raw, Smart, Both }

    /// Called when a recording is saved: asks Raw / Smart / Both, then sends in the background.
    public static void Deliver(string? title, string raw, string? smart)
    {
        var p = Store.Shared.Prefs;
        if (!p.CiqEnabled || string.IsNullOrWhiteSpace(raw)) return;
        Ui.Run(() =>
        {
            Choice? choice = smart == null ? Choice.Raw : Ask();
            if (choice == null) return;
            var msgs = new List<string>();
            if (choice is Choice.Raw or Choice.Both) msgs.Add(Message(p.CiqPrompt, title == null ? null : title + " (raw transcript)", raw));
            if (smart != null && choice is Choice.Smart or Choice.Both) msgs.Add(Message(p.CiqPrompt, title == null ? null : title + " (smart transcript)", smart));
            CIQWindow.Shared.SendMessages(msgs);
        });
    }

    /// For "Send my last note now" (no question asked).
    public static void Send(string? title, string transcript, bool force = false)
    {
        var p = Store.Shared.Prefs;
        if ((!p.CiqEnabled && !force) || string.IsNullOrWhiteSpace(transcript)) return;
        var text = Message(p.CiqPrompt, title, transcript);
        Ui.Run(() => CIQWindow.Shared.SendMessages(new List<string> { text }));
    }

    static Choice? Ask()
    {
        using var f = new Form
        {
            Text = "Just Say It – CollectivIQ", FormBorderStyle = FormBorderStyle.FixedDialog, StartPosition = FormStartPosition.CenterScreen,
            TopMost = true, MinimizeBox = false, MaximizeBox = false, ClientSize = new Size(460, 170), Font = new Font("Segoe UI", 9.5f), Icon = Program.AppIcon,
        };
        var lbl = new Label
        {
            Text = "Send this recording to CollectivIQ?\n\nRaw: exactly as heard.\nSmart: words and logic fixed so it reads clearly.\nBoth: the raw transcript first, then the smart one.",
            AutoSize = false, Bounds = new Rectangle(16, 12, 430, 100),
        };
        Choice? result = null;
        Button B(string text, int x, Choice? c) { var b = new Button { Text = text, Bounds = new Rectangle(x, 120, 100, 32) }; b.Click += (_, _) => { result = c; f.Close(); }; return b; }
        f.Controls.AddRange(new Control[] { lbl, B("Smart", 16, Choice.Smart), B("Raw", 124, Choice.Raw), B("Both", 232, Choice.Both), B("Don't send", 340, null) });
        f.ShowDialog();
        return result;
    }

    public static void Notify(string title, string body) =>
        Ui.Run(() => Program.Tray?.ShowBalloonTip(5000, title, body, ToolTipIcon.Info));

    public static void OpenChat(bool signIn = false) => Ui.Run(() => CIQWindow.Shared.ShowAt(signIn ? LoginUrl : ChatUrl));


    /// Picks the model (All · Auto → All Selected → only <model> → Apply Changes), then fills the
    /// chat box and presses Send. Returns "login", "wait", "model:…", "filled" or "sent".
    public static string Script(string msg) =>
        "(" + Steps + ")(" + JsonSerializer.Serialize(msg) + ", " + JsonSerializer.Serialize(Store.Shared.Prefs.CiqModel ?? "") + ")";

    public const string Reset = "window.__jsi = undefined; 'ok'";

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

    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    Task? ready;
    readonly Queue<string> queue = new();
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
        timer.Tick += async (_, _) => await Tick();
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
    public async void SendMessages(List<string> msgs)
    {
        if (msgs.Count == 0) return;
        foreach (var m in msgs) queue.Enqueue(m);
        sent = 0; settleUntil = null; shownForLogin = false; startedAt = DateTime.Now;
        if (Store.Shared.Prefs.CiqShowPreview) { background = false; ShowInTaskbar = true; Text = "CollectivIQ – Just Say It (preview)"; Show(); Activate(); }
        else if (!Visible) { background = true; ShowInTaskbar = false; }
        CollectivIQ.Notify("JustSayIt – syncing with CollectivIQ", "Your notes are being synced and processed inside CollectivIQ.");
        try
        {
            await Ready();
            if (!resetHooked) { resetHooked = true; web.CoreWebView2.NavigationCompleted += async (_, _) => { try { await web.CoreWebView2.ExecuteScriptAsync(CollectivIQ.Reset); } catch { } }; }
            web.CoreWebView2.Navigate(CollectivIQ.ChatUrl);
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
            Controller.Shared.Overlay.ShowState(OverlayState.Done);
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
        string result;
        try { result = JsonSerializer.Deserialize<string>(await web.CoreWebView2.ExecuteScriptAsync(CollectivIQ.Script(queue.Peek()))) ?? ""; }
        catch { return; }
        if (result == "sent")
        {
            queue.Dequeue(); sent++;
            if (shownForLogin && !Store.Shared.Prefs.CiqShowPreview) { background = true; Hide(); }
            shownForLogin = false;
            if (queue.Count > 0) { web.CoreWebView2.Navigate(CollectivIQ.ChatUrl); startedAt = DateTime.Now; }
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
