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

    public static void Send(string? title, string transcript, bool force = false)
    {
        var p = Store.Shared.Prefs;
        if ((!p.CiqEnabled && !force) || string.IsNullOrWhiteSpace(transcript)) return;
        var text = Message(p.CiqPrompt, title, transcript);
        Ui.Run(() => CIQWindow.Shared.SendMessage(text));
    }

    public static void OpenChat(bool signIn = false) => Ui.Run(() => CIQWindow.Shared.ShowAt(signIn ? LoginUrl : ChatUrl));

    /// Fills CollectivIQ's chat box and presses Send. Returns "login", "wait", "filled" or "sent".
    public static string Script(string msg) => """
        (function(msg){
          if (location.pathname.indexOf('/login') === 0) return 'login';
          var h = document.querySelector('wa-textarea[data-testid=chat-input]');
          if (!h || !h.shadowRoot) return 'wait';
          var ta = h.shadowRoot.querySelector('textarea');
          if (!ta) return 'wait';
          var b = document.querySelector('[data-testid=send-button]');
          if (h.value === msg && b && !b.hasAttribute('disabled')) { b.click(); return 'sent'; }
          if (h.value !== msg) {
            ta.focus();
            ta.value = msg;
            ta.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            try { h.value = msg; } catch (e) {}
            h.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            h.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
          }
          return 'filled';
        })(
        """ + JsonSerializer.Serialize(msg) + ")";
}

/// The in-app CollectivIQ window (WebView2). Sign-in is kept in the user's profile folder.
public sealed class CIQWindow : Form
{
    static CIQWindow? shared;
    public static CIQWindow Shared => shared == null || shared.IsDisposed ? (shared = new CIQWindow()) : shared;

    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    Task? ready;
    string? pending;
    DateTime startedAt;
    bool noticeShown;

    CIQWindow()
    {
        Text = "CollectivIQ – Just Say It";
        Icon = Program.AppIcon;
        ClientSize = new Size(1100, 780);
        StartPosition = FormStartPosition.CenterScreen;
        Controls.Add(web);
        timer.Tick += async (_, _) => await Tick();
    }

    Task Ready()
    {
        if (ready != null) return ready;
        var dataDir = Path.Combine(Store.Dir, "CollectivIQ");
        ready = Task.Run(async () =>
        {
            var env = await CoreWebView2Environment.CreateAsync(null, dataDir);
            await Ui.Run(() => { });
            return env;
        }).ContinueWith(t => web.EnsureCoreWebView2Async(t.Result), TaskScheduler.FromCurrentSynchronizationContext()).Unwrap();
        return ready;
    }

    public async void ShowAt(string url)
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        try
        {
            await Ready();
            web.CoreWebView2.Navigate(url);
        }
        catch (Exception e)
        {
            MessageBox.Show("CollectivIQ couldn't open: " + e.Message + "\n\nWindows needs the Microsoft Edge WebView2 Runtime (already included in Windows 10/11 updates).",
                "Just Say It", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    public void SendMessage(string msg)
    {
        pending = msg;
        startedAt = DateTime.Now;
        noticeShown = false;
        ShowAt(CollectivIQ.ChatUrl);
        timer.Start();
    }

    async Task Tick()
    {
        if (pending == null || web.CoreWebView2 == null) { if (pending == null) timer.Stop(); return; }
        if ((DateTime.Now - startedAt).TotalMinutes > 10)
        {
            timer.Stop(); pending = null;
            Controller.Shared.Overlay.ShowState(OverlayState.Error, "CollectivIQ: timed out – the transcript is saved in your note");
            return;
        }
        string result;
        try { result = JsonSerializer.Deserialize<string>(await web.CoreWebView2.ExecuteScriptAsync(CollectivIQ.Script(pending))) ?? ""; }
        catch { return; }
        if (result == "sent")
        {
            timer.Stop(); pending = null;
            Controller.Shared.Overlay.ShowState(OverlayState.Done);
        }
        else if (result == "login" && !noticeShown)
        {
            noticeShown = true;
            Controller.Shared.Overlay.ShowState(OverlayState.Error, "Sign in to CollectivIQ in the window – the transcript is sent right after");
        }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
