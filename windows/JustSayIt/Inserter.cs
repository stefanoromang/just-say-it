// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Runtime.InteropServices;

namespace JustSayIt;

/// Pastes text into the focused text box of the target window.
public static class Inserter
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 2;
    const ushort VK_CONTROL = 0x11, VK_SHIFT = 0x10, VK_MENU = 0x12, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    public static readonly IntPtr Marker = new(0x4A535349); // "JSSI" – ignored by our own keyboard hook

    static INPUT Key(ushort vk, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0, dwExtraInfo = Marker } },
    };

    static void ReleaseModifiers()
    {
        var list = new List<INPUT>();
        foreach (var vk in new ushort[] { VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN, 0xA5, 0xA3 })
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) list.Add(Key(vk, true));
        if (list.Count > 0) SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf<INPUT>());
    }

    public static void Chord(ushort modifier, ushort key)
    {
        ReleaseModifiers();
        var inputs = new[] { Key(modifier, false), Key(key, false), Key(key, true), Key(modifier, true) };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    public static async Task Focus(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || GetForegroundWindow() == hwnd) return;
        // Tapping Alt lets us take foreground rights back from the result card.
        var alt = new[] { Key(VK_MENU, false), Key(VK_MENU, true) };
        SendInput(2, alt, Marshal.SizeOf<INPUT>());
        SetForegroundWindow(hwnd);
        await Task.Delay(150);
    }

    public static async Task Insert(string text, IntPtr target, bool restoreClipboard)
    {
        if (string.IsNullOrEmpty(text)) return;
        await Focus(target);
        IDataObject? saved = null;
        await Ui.Run(() =>
        {
            if (restoreClipboard) { try { saved = Clipboard.GetDataObject(); } catch { } }
            SetClipboard(text);
        });
        await Task.Delay(40);
        Chord(VK_CONTROL, (ushort)'V');
        if (restoreClipboard && saved != null)
        {
            await Task.Delay(400);
            await Ui.Run(() =>
            {
                try
                {
                    var copy = new DataObject();
                    foreach (var f in saved.GetFormats()) { try { copy.SetData(f, saved.GetData(f)); } catch { } }
                    Clipboard.SetDataObject(copy, true);
                }
                catch { }
            });
        }
    }

    public static void SetClipboard(string text)
    {
        for (int i = 0; i < 5; i++)
        {
            try { Clipboard.SetText(text); return; } catch { Thread.Sleep(30); }
        }
    }

    /// Copies the current selection with Ctrl+C (fallback when UI Automation can't read it).
    public static async Task<string?> CopySelection()
    {
        string? before = null;
        await Ui.Run(() => { try { before = Clipboard.ContainsText() ? Clipboard.GetText() : null; Clipboard.Clear(); } catch { } });
        Chord(VK_CONTROL, (ushort)'C');
        string? got = null;
        for (int i = 0; i < 15 && got == null; i++)
        {
            await Task.Delay(30);
            await Ui.Run(() => { try { if (Clipboard.ContainsText()) got = Clipboard.GetText(); } catch { } });
        }
        if (before != null) await Ui.Run(() => SetClipboard(before));
        return string.IsNullOrEmpty(got) ? null : got;
    }
}

/// Runs work on the UI thread (the clipboard requires an STA thread).
public static class Ui
{
    public static SynchronizationContext? Context;

    public static Task Run(Action a)
    {
        var tcs = new TaskCompletionSource();
        if (Context == null || SynchronizationContext.Current == Context) { a(); tcs.SetResult(); return tcs.Task; }
        Context.Post(_ => { try { a(); tcs.SetResult(); } catch (Exception e) { tcs.SetException(e); } }, null);
        return tcs.Task;
    }
}
