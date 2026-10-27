// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using Microsoft.Win32;

namespace JustSayIt;

static class Program
{
    public static Icon AppIcon = SystemIcons.Application;
    static Mutex? single;

    [STAThread]
    static void Main(string[] args)
    {
        single = new Mutex(true, "JustSayIt.SingleInstance", out bool first);
        if (!first) return;

        ApplicationConfiguration.Initialize();
        try
        {
            using var s = typeof(Program).Assembly.GetManifestResourceStream("JustSayIt.AppIcon.ico");
            if (s != null) AppIcon = new Icon(s);
        }
        catch { }

        using var ctx = new TrayApp(showWindow: !args.Contains("--background"));
        Application.Run(ctx);
    }

    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static void SetStartWithWindows(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
            if (key == null) return;
            if (on) key.SetValue("JustSayIt", $"\"{Application.ExecutablePath}\" --background");
            else key.DeleteValue("JustSayIt", false);
        }
        catch { }
    }
}

/// System-tray app: owns the tray icon, controller and main window.
sealed class TrayApp : ApplicationContext
{
    readonly NotifyIcon tray = new();
    MainWindow? window;
    readonly Controller c = Controller.Shared;

    public TrayApp(bool showWindow)
    {
        Ui.Context = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        // Force handle creation on the UI thread.
        _ = c.Overlay.Handle;
        _ = c.Card.Handle;
        c.Boot();
        Program.SetStartWithWindows(Store.Shared.Prefs.StartWithWindows);

        tray.Icon = Program.AppIcon;
        tray.Text = "Just Say It";
        tray.Visible = true;
        var menu = new ContextMenuStrip();
        menu.Opening += (_, _) => BuildMenu(menu);
        BuildMenu(menu);
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ShowWindow();

        if (showWindow || !c.ModelReady) ShowWindow();
        else tray.ShowBalloonTip(3000, "Just Say It is running",
            $"Hold {Labels.Of(Store.Shared.Prefs.Hotkey)} to talk.", ToolTipIcon.Info);
    }

    void BuildMenu(ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var hk = Labels.Of(Store.Shared.Prefs.Hotkey);
        menu.Items.Add(new ToolStripMenuItem($"Hold {hk} to talk") { Enabled = false });
        menu.Items.Add(new ToolStripMenuItem("Double-tap for hands-free · add Shift for Scribe") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Start / Stop Dictation", null, (_, _) => c.ToggleFromMenu());
        var rw = new ToolStripMenuItem("Rewrite Selected Text");
        foreach (RewriteStyle s in Enum.GetValues<RewriteStyle>())
        {
            var style = s;
            rw.DropDownItems.Add(Labels.Of(s), null, (_, _) => _ = c.RewriteSelection(style));
        }
        menu.Items.Add(rw);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open Just Say It…", null, (_, _) => ShowWindow());
        menu.Items.Add("About Just Say It", null, (_, _) =>
            MessageBox.Show("Just Say It 1.1\n\nCreated by Stefano Roman Gunness\nFree, private voice typing.\n\n© 2026 Stefano Roman Gunness · MIT License\nhttps://github.com/stefanoromang/just-say-it",
                "About Just Say It", MessageBoxButtons.OK, MessageBoxIcon.Information));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());
    }

    void ShowWindow()
    {
        if (window == null || window.IsDisposed) window = new MainWindow();
        window.Show();
        window.WindowState = FormWindowState.Normal;
        window.Activate();
    }

    protected override void ExitThreadCore()
    {
        tray.Visible = false;
        tray.Dispose();
        c.Dispose();
        base.ExitThreadCore();
    }
}
