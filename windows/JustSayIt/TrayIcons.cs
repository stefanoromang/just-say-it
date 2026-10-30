// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace JustSayIt;

/// What the app is doing; each mode has its own neon tray-icon color.
public enum IconMode { Idle, Dictating, Scribe, NoteTaker, Working }

/// Draws bright neon tray icons that look good on light and dark taskbars, and pulses
/// the active one. Cyan = ready, pink = dictating, purple = Scribe, green = Note Taker, orange = working.
public sealed class TrayIcons
{
    public static Color ColorOf(IconMode m) => m switch
    {
        IconMode.Dictating => Color.FromArgb(255, 41, 158),
        IconMode.Scribe => Color.FromArgb(168, 84, 255),
        IconMode.NoteTaker => Color.FromArgb(57, 255, 20),
        IconMode.Working => Color.FromArgb(255, 148, 0),
        _ => Color.FromArgb(0, 230, 255),
    };

    public static string LabelOf(IconMode m) => m switch
    {
        IconMode.Dictating => "Just Say It – dictating",
        IconMode.Scribe => "Just Say It – Scribe",
        IconMode.NoteTaker => "Just Say It – Note Taker recording",
        IconMode.Working => "Just Say It – working…",
        _ => "Just Say It – ready",
    };

    readonly NotifyIcon tray;
    readonly System.Windows.Forms.Timer timer = new() { Interval = 600 };
    readonly Dictionary<(IconMode, bool), Icon> cache = new();
    IconMode mode = (IconMode)(-1);
    bool pulse;

    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

    public TrayIcons(NotifyIcon tray)
    {
        this.tray = tray;
        timer.Tick += (_, _) => Tick();
        timer.Start();
        Tick();
    }

    void Tick()
    {
        var c = Controller.Shared;
        var m = NoteTaker.Shared.IsRecording ? IconMode.NoteTaker
            : c.Transcriber.IsRecording ? (c.IsScribe ? IconMode.Scribe : IconMode.Dictating)
            : c.IsBusy ? IconMode.Working
            : IconMode.Idle;
        if (m != mode) { mode = m; pulse = true; tray.Text = LabelOf(m); }
        else if (m != IconMode.Idle) pulse = !pulse;
        else pulse = true;
        tray.Icon = Get(m, pulse);
    }

    Icon Get(IconMode m, bool bright)
    {
        if (cache.TryGetValue((m, bright), out var ic)) return ic;
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var col = ColorOf(m);
            var glow = bright ? 1f : 0.45f;
            var r = new Rectangle(1, 1, 30, 30);
            using var path = new GraphicsPath();
            int d = 12;
            path.AddArc(r.Left, r.Top, d, d, 180, 90); path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            using (var bg = new SolidBrush(Color.FromArgb(255, 14, 8, 38))) g.FillPath(bg, path);
            using (var halo = new SolidBrush(Color.FromArgb((int)(90 * glow), col))) g.FillPath(halo, path);
            using (var pen = new Pen(col, 2.4f)) g.DrawPath(pen, path);
            float[] bars = { 0.35f, 0.7f, 1f, 0.6f, 0.85f };
            float bw = 3f, gap = 2f, total = bars.Length * bw + (bars.Length - 1) * gap, x = 16 - total / 2;
            using var white = new SolidBrush(Color.White);
            foreach (var b in bars)
            {
                var h = 18 * b;
                g.FillRectangle(white, x, 16 - h / 2, bw, h);
                x += bw + gap;
            }
        }
        var hicon = bmp.GetHicon();
        ic = (Icon)Icon.FromHandle(hicon).Clone();
        DestroyIcon(hicon);
        cache[(m, bright)] = ic;
        return ic;
    }
}
