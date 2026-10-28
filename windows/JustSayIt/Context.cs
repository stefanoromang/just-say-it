// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using System.Windows.Automation.Text;

namespace JustSayIt;

/// Everything we know about where the user is dictating, captured at hotkey press.
public class CaptureContext
{
    public string AppName = "";
    public string ProcessName = "";
    public IntPtr Window;
    public string? WindowTitle;
    public string? Url;
    public string? SelectedText;
    public string? TextBeforeCursor;
    public bool? FieldIsEditable;
    public string? ScreenText;
    public AppCategory Category = AppCategory.Other;

    public string? Host
    {
        get
        {
            if (string.IsNullOrEmpty(Url)) return null;
            var u = Url.Contains("://") ? Url : "https://" + Url;
            return Uri.TryCreate(u, UriKind.Absolute, out var uri) ? uri.Host.ToLowerInvariant() : null;
        }
    }

    public string PromptBlock()
    {
        var sb = new StringBuilder();
        sb.AppendLine($"App: {AppName} ({Labels.Of(Category)})");
        if (!string.IsNullOrEmpty(WindowTitle)) sb.AppendLine("Window title: " + Trunc(WindowTitle, 160));
        if (Host != null) sb.AppendLine("Website: " + Host);
        if (!string.IsNullOrWhiteSpace(TextBeforeCursor))
            sb.AppendLine("Text already in the box before the cursor:\n\"\"\"\n" + Tail(TextBeforeCursor.Trim(), 600) + "\n\"\"\"");
        if (!string.IsNullOrEmpty(SelectedText))
            sb.AppendLine("Text the user selected:\n\"\"\"\n" + Trunc(SelectedText, 1500) + "\n\"\"\"");
        if (!string.IsNullOrWhiteSpace(ScreenText))
            sb.AppendLine("Visible on screen (OCR, may be noisy):\n\"\"\"\n" + Trunc(ScreenText, 1200) + "\n\"\"\"");
        return sb.ToString().TrimEnd();
    }

    static string Trunc(string s, int n) => s.Length > n ? s[..n] : s;
    static string Tail(string s, int n) => s.Length > n ? s[^n..] : s;
}

public static class ContextReader
{
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int max);

    static readonly HashSet<string> Browsers = new(StringComparer.OrdinalIgnoreCase)
        { "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc", "zen" };

    public static bool IsBrowser(string process) => Browsers.Contains(process);

    public static CaptureContext Capture()
    {
        var c = new CaptureContext { Window = GetForegroundWindow() };
        try
        {
            GetWindowThreadProcessId(c.Window, out var pid);
            var proc = Process.GetProcessById((int)pid);
            c.ProcessName = proc.ProcessName;
            c.AppName = FriendlyName(proc);
        }
        catch { c.AppName = "this app"; }
        var sb = new StringBuilder(512);
        GetWindowText(c.Window, sb, sb.Capacity);
        c.WindowTitle = sb.ToString();

        // UI Automation can be slow on some apps; read into a copy on a background
        // thread and cap the wait so the hotkey always feels instant.
        // Classic Windows text boxes answer directly in a few milliseconds, so read them first:
        // this still works when UI Automation is slow (for example on its first use).
        var hwndFocus = FocusedControl(c.Window);
        if (hwndFocus != IntPtr.Zero) ReadNativeEdit(hwndFocus, c);

        var probe = new CaptureContext { Window = c.Window, ProcessName = c.ProcessName };
        var task = Task.Run(() => ReadAutomation(probe));
        if (task.Wait(TimeSpan.FromMilliseconds(600)))
        {
            c.SelectedText ??= probe.SelectedText;
            if (string.IsNullOrEmpty(c.TextBeforeCursor)) c.TextBeforeCursor = probe.TextBeforeCursor;
            c.FieldIsEditable ??= probe.FieldIsEditable;
            c.Url = probe.Url;
        }
        c.Category = Classify(c);
        return c;
    }

    /// UI Automation is slow the first time it is used; call this once at startup.
    public static void WarmUp() => Task.Run(() =>
    {
        try { _ = AutomationElement.FocusedElement?.Current.ControlType; } catch { }
    });

    static string FriendlyName(Process p)
    {
        try
        {
            var desc = p.MainModule?.FileVersionInfo.FileDescription;
            if (!string.IsNullOrWhiteSpace(desc)) return desc!;
        }
        catch { }
        return p.ProcessName;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct GUITHREADINFO
    {
        public int cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, StringBuilder l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);

    /// The window that has keyboard focus inside the foreground app (works across processes).
    static IntPtr FocusedControl(IntPtr top)
    {
        var info = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        uint thread = GetWindowThreadProcessId(top, IntPtr.Zero);
        return GetGUIThreadInfo(thread, ref info) ? info.hwndFocus : IntPtr.Zero;
    }

    static void ReadAutomation(CaptureContext c)
    {
        var hwndFocus = FocusedControl(c.Window);
        try
        {
            AutomationElement? focused = null;
            try { focused = AutomationElement.FocusedElement; } catch { }
            // Prefer the element for the focused native control when UIA's global focus is stale.
            if (hwndFocus != IntPtr.Zero && (focused == null || focused.Current.NativeWindowHandle == 0 || focused.Current.ProcessId != ProcessOf(c.Window)))
            {
                try { focused = AutomationElement.FromHandle(hwndFocus); } catch { }
            }
            if (focused != null)
            {
                var ct = focused.Current.ControlType;
                bool editable = ct == ControlType.Edit || ct == ControlType.Document || ct == ControlType.ComboBox;
                if (focused.TryGetCurrentPattern(ValuePattern.Pattern, out var vp))
                {
                    var v = (ValuePattern)vp;
                    if (!v.Current.IsReadOnly) editable = true;
                    var val = v.Current.Value;
                    if (!string.IsNullOrEmpty(val)) c.TextBeforeCursor = Tail(val);
                }
                if (focused.TryGetCurrentPattern(TextPattern.Pattern, out var tp))
                {
                    var t = (TextPattern)tp;
                    var sel = t.GetSelection();
                    if (sel.Length > 0)
                    {
                        var s = sel[0].GetText(4000);
                        if (!string.IsNullOrWhiteSpace(s)) c.SelectedText = s;
                        var before = t.DocumentRange.Clone();
                        before.MoveEndpointByRange(TextPatternRangeEndpoint.End, sel[0], TextPatternRangeEndpoint.Start);
                        var b = before.GetText(-1);
                        if (!string.IsNullOrEmpty(b)) c.TextBeforeCursor = Tail(b);
                    }
                    editable = editable || ct == ControlType.Edit;
                }
                c.FieldIsEditable = editable;
            }
        }
        catch { }

        try { if (IsBrowser(c.ProcessName)) c.Url = BrowserUrl(c.Window); } catch { }
    }

    static int ProcessOf(IntPtr h) { GetWindowThreadProcessId(h, out var pid); return (int)pid; }

    static void ReadNativeEdit(IntPtr h, CaptureContext c)
    {
        var cls = new StringBuilder(128);
        GetClassName(h, cls, cls.Capacity);
        var name = cls.ToString();
        bool isEdit = name.Equals("Edit", StringComparison.OrdinalIgnoreCase) || name.Contains("EDIT", StringComparison.OrdinalIgnoreCase)
                      || name.StartsWith("RichEdit", StringComparison.OrdinalIgnoreCase);
        if (!isEdit) return;
        const uint WM_GETTEXTLENGTH = 0x000E, WM_GETTEXT = 0x000D, EM_GETSEL = 0x00B0, SMTO_ABORTIFHUNG = 0x0002;
        SendMessageTimeout(h, WM_GETTEXTLENGTH, IntPtr.Zero, IntPtr.Zero, SMTO_ABORTIFHUNG, 200, out var lenPtr);
        int len = (int)lenPtr;
        if (len <= 0) { c.FieldIsEditable = true; return; }
        var buf = new StringBuilder(len + 1);
        SendMessageTimeout(h, WM_GETTEXT, (IntPtr)(len + 1), buf, SMTO_ABORTIFHUNG, 200, out _);
        var text = buf.ToString();
        // EM_GETSEL packs start/end into the return value (works across processes).
        SendMessageTimeout(h, EM_GETSEL, IntPtr.Zero, IntPtr.Zero, SMTO_ABORTIFHUNG, 200, out var sel);
        long packed = sel.ToInt64();
        int start = (int)(packed & 0xFFFF), end = (int)((packed >> 16) & 0xFFFF);
        if (text.Length > 0xFFFF && start == 0xFFFF) { start = end = text.Length; }
        start = Math.Clamp(start, 0, text.Length);
        end = Math.Clamp(end, start, text.Length);
        c.FieldIsEditable = true;
        if (string.IsNullOrEmpty(c.TextBeforeCursor) || c.TextBeforeCursor.Length < start) c.TextBeforeCursor = Tail(text[..start]);
        if (c.SelectedText == null && end > start) c.SelectedText = text[start..end];
    }

    static string Tail(string s) => s.Length > 1500 ? s[^1500..] : s;

    /// Reads the address bar of Chromium browsers and Firefox via UI Automation.
    static string? BrowserUrl(IntPtr hwnd)
    {
        try
        {
            var root = AutomationElement.FromHandle(hwnd);
            var cond = new AndCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
                new PropertyCondition(AutomationElement.IsKeyboardFocusableProperty, true));
            foreach (AutomationElement el in root.FindAll(TreeScope.Descendants, cond))
            {
                var name = el.Current.Name ?? "";
                if (!name.Contains("Address", StringComparison.OrdinalIgnoreCase) && !name.Contains("Search", StringComparison.OrdinalIgnoreCase)
                    && !name.Contains("URL", StringComparison.OrdinalIgnoreCase)) continue;
                if (el.TryGetCurrentPattern(ValuePattern.Pattern, out var vp))
                {
                    var v = ((ValuePattern)vp).Current.Value;
                    if (!string.IsNullOrWhiteSpace(v) && (v.Contains('.') || v.Contains("://"))) return v;
                }
            }
        }
        catch { }
        return null;
    }

    public static AppCategory Classify(CaptureContext c)
    {
        var p = c.ProcessName.ToLowerInvariant();
        var hay = ((c.Host ?? "") + " " + (c.WindowTitle ?? "")).ToLowerInvariant();
        if (IsBrowser(p) && hay.Trim().Length > 0)
        {
            if (Has(hay, "mail.google", "gmail", "outlook.", "outlook ", "mail.yahoo", "proton.me", "inbox", "superhuman", "fastmail")) return AppCategory.Email;
            if (Has(hay, "chatgpt", "chat.openai", "claude", "gemini", "perplexity", "copilot", "grok")) return AppCategory.Ai;
            if (Has(hay, "slack", "teams", "notion", "linear.app", "atlassian", "jira", "asana", "docs.google", "google docs", "monday.com", "clickup", "trello", "figma", "hubspot", "salesforce")) return AppCategory.Work;
            if (Has(hay, "whatsapp", "messenger", "discord", "telegram", "instagram", "facebook", "x.com", "twitter", "reddit")) return AppCategory.Casual;
            if (Has(hay, "github", "gitlab", "stackoverflow", "stack overflow", "replit", "vercel")) return AppCategory.Code;
        }
        if (Has(p, "outlook", "olk", "thunderbird", "hxoutlook", "mailspring", "em client")) return AppCategory.Email;
        if (Has(p, "slack", "teams", "ms-teams", "notion", "zoom", "linear", "clickup")) return AppCategory.Work;
        if (Has(p, "whatsapp", "telegram", "discord", "signal", "messenger")) return AppCategory.Casual;
        if (Has(p, "chatgpt", "claude", "perplexity", "opencode")) return AppCategory.Ai;
        if (Has(p, "code", "cursor", "devenv", "rider", "idea", "pycharm", "windsurf", "zed", "sublime", "notepad++", "windowsterminal", "powershell", "cmd", "wt")) return AppCategory.Code;
        return AppCategory.Other;
    }

    static bool Has(string hay, params string[] needles) => needles.Any(hay.Contains);
}
