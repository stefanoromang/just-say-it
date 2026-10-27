// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using System.Runtime.InteropServices;

namespace JustSayIt;

/// Global low-level keyboard hook:
/// - Hold the dictation key to talk, release to finish.
/// - Double-tap it for hands-free; tap again to finish.
/// - Hold Shift + dictation key for Scribe.
/// - Esc while recording cancels.  Ctrl+Alt+R rewrites the selection.
public sealed class Hotkeys : IDisposable
{
    public event Action<bool, bool>? Start;   // scribe, handsFree
    public event Action? Stop;
    public event Action? CancelRecording;
    public event Action? Rewrite;

    public HotkeyChoice Hotkey = HotkeyChoice.RightAlt;
    public bool Recording { get; private set; }
    bool handsFree;
    bool keyIsDown;
    DateTime downAt;
    DateTime lastTapUp = DateTime.MinValue;

    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    readonly HookProc proc;
    IntPtr hook;

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr dwExtraInfo; }

    const int WH_KEYBOARD_LL = 13, WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_SYSKEYDOWN = 0x104, WM_SYSKEYUP = 0x105;

    public Hotkeys() { proc = Callback; }

    // Windows removes a low-level hook that takes too long, so events are handed
    // to the UI thread and the hook returns immediately.
    static void Later(Action? a)
    {
        if (a == null) return;
        if (Ui.Context != null) Ui.Context.Post(_ => a(), null);
        else ThreadPool.QueueUserWorkItem(_ => a());
    }

    public void Install()
    {
        if (hook != IntPtr.Zero) return;
        using var mod = Process.GetCurrentProcess().MainModule;
        hook = SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(mod?.ModuleName), 0);
    }

    public void Reset() { Recording = false; handsFree = false; }

    static bool Down(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code < 0) return CallNextHookEx(hook, code, wParam, lParam);
        var k = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        if (k.dwExtraInfo == Inserter.Marker) return CallNextHookEx(hook, code, wParam, lParam);
        int msg = (int)wParam;
        bool isDown = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
        bool isUp = msg is WM_KEYUP or WM_SYSKEYUP;
        int vk = (int)k.vkCode;
        int hot = Labels.VirtualKey(Hotkey);

        if (isDown && vk == 0x1B && Recording) // Esc
        {
            Reset();
            Later(CancelRecording);
            return 1;
        }
        if (isDown && vk == 'R' && Down(0x11) && Down(0x12) && !Down(0x5B)) // Ctrl+Alt+R
        {
            Later(Rewrite);
            return 1;
        }
        if (vk != hot) return CallNextHookEx(hook, code, wParam, lParam);

        var now = DateTime.Now;
        if (isDown)
        {
            if (keyIsDown) return 1; // auto-repeat
            keyIsDown = true;
            downAt = now;
            if (Recording && handsFree)
            {
                Reset();
                Later(Stop);
                return 1;
            }
            if (!Recording)
            {
                bool scribe = Down(0x10);
                bool doubleTap = (now - lastTapUp).TotalMilliseconds < 350;
                Recording = true;
                handsFree = doubleTap;
                var st = Start; Later(() => st?.Invoke(scribe, doubleTap));
            }
            return 1; // swallow so Right Alt doesn't open menus
        }
        if (isUp)
        {
            keyIsDown = false;
            var held = (now - downAt).TotalMilliseconds;
            if (!Recording || handsFree) return 1;
            if (held < 250)
            {
                lastTapUp = now;
                Reset();
                Later(CancelRecording);
                return 1;
            }
            lastTapUp = DateTime.MinValue;
            Reset();
            Later(Stop);
            return 1;
        }
        return CallNextHookEx(hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        hook = IntPtr.Zero;
    }
}
