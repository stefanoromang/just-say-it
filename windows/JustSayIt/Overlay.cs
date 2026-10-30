// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Drawing.Drawing2D;

namespace JustSayIt;

public enum OverlayState { Hidden, Listening, Thinking, Done, Error, NoteTaker }

/// Floating pill at the bottom of the screen while recording. Never steals focus.
public sealed class Overlay : Form
{
    readonly float[] levels = new float[22];
    OverlayState state = OverlayState.Hidden;
    string label = "";
    string message = "";
    bool scribe, handsFree;
    readonly System.Windows.Forms.Timer hideTimer = new();
    readonly System.Windows.Forms.Timer blinkTimer = new() { Interval = 600 };
    bool blink;

    public Overlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        Size = new Size(560, 48);
        DoubleBuffered = true;
        hideTimer.Tick += (_, _) => { hideTimer.Stop(); HideNow(); };
        blinkTimer.Tick += (_, _) => { if (state == OverlayState.NoteTaker) { blink = !blink; Invalidate(); } };
        blinkTimer.Start();
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020; // NOACTIVATE | TOOLWINDOW | TRANSPARENT
            return cp;
        }
    }

    public void PushLevel(float l)
    {
        Array.Copy(levels, 1, levels, 0, levels.Length - 1);
        levels[^1] = l;
        if (state == OverlayState.Listening) Invalidate();
    }

    public void ShowState(OverlayState s, string text = "", bool isScribe = false, bool isHandsFree = false)
    {
        hideTimer.Stop();
        state = s;
        if (s == OverlayState.Listening) { label = text; scribe = isScribe; handsFree = isHandsFree; Array.Clear(levels); }
        else message = text;
        if (s == OverlayState.Hidden) { HideNow(); return; }
        var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Bottom - Height - 28);
        if (!Visible) Show();
        Invalidate();
        if (s == OverlayState.Done) { hideTimer.Interval = 800; hideTimer.Start(); }
        if (s == OverlayState.Error) { hideTimer.Interval = 2800; hideTimer.Start(); }
    }

    void HideNow()
    {
        // While the Note Taker records, fall back to the flashing "active" pill.
        if (NoteTaker.Shared.IsRecording) { state = OverlayState.NoteTaker; Invalidate(); if (!Visible) Show(); return; }
        state = OverlayState.Hidden; Hide();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        using var font = new Font("Segoe UI", 9.5f);
        using var bold = new Font("Segoe UI Semibold", 9.5f);

        string text = state switch
        {
            OverlayState.NoteTaker => "JustSayIt - Note taker is active",
            OverlayState.Thinking => "Polishing…",
            OverlayState.Done => "Inserted",
            OverlayState.Error => message,
            _ => "",
        };
        // Measure to size the pill.
        float contentW = state == OverlayState.Listening
            ? 22 * 5 + 20 + (scribe ? g.MeasureString("Scribe", bold).Width + 8 : 0) + (handsFree ? g.MeasureString("Hands-free", font).Width + 8 : 0) + g.MeasureString(label, font).Width + 8
            : g.MeasureString(text, font).Width + 30;
        int w = (int)Math.Min(Width - 4, contentW + 40);
        var rect = new Rectangle((Width - w) / 2, 4, w, 38);
        using (var path = Rounded(rect, 19))
        using (var bg = new SolidBrush(Color.FromArgb(235, 20, 20, 24)))
            g.FillPath(bg, path);

        int x = rect.Left + 16;
        int cy = rect.Top + rect.Height / 2;
        Color dot = state switch
        {
            OverlayState.Listening => scribe ? Color.MediumPurple : Color.IndianRed,
            OverlayState.Done => Color.MediumSeaGreen,
            OverlayState.NoteTaker => blink ? Color.FromArgb(57, 255, 20) : Color.FromArgb(40, 57, 255, 20),
            OverlayState.Error => Color.Goldenrod,
            _ => Color.LightGray,
        };
        using (var b = new SolidBrush(dot)) g.FillEllipse(b, x, cy - 5, 10, 10);
        x += 18;

        if (state == OverlayState.Listening)
        {
            using var white = new SolidBrush(Color.White);
            foreach (var l in levels)
            {
                int h = Math.Max(3, (int)(l * 22));
                g.FillRectangle(white, x, cy - h / 2, 3, h);
                x += 5;
            }
            x += 6;
            if (scribe)
            {
                using var p = new SolidBrush(Color.MediumPurple);
                g.DrawString("Scribe", bold, p, x, cy - 9);
                x += (int)g.MeasureString("Scribe", bold).Width + 6;
            }
            using var dim = new SolidBrush(Color.FromArgb(170, 255, 255, 255));
            if (handsFree)
            {
                g.DrawString("Hands-free", font, dim, x, cy - 9);
                x += (int)g.MeasureString("Hands-free", font).Width + 6;
            }
            g.DrawString(label, font, dim, x, cy - 9);
        }
        else
        {
            using var fg = new SolidBrush(state == OverlayState.NoteTaker && blink ? Color.FromArgb(57, 255, 20) : Color.White);
            g.DrawString(text, state == OverlayState.NoteTaker ? bold : font, fg, x, cy - 9);
        }
    }

    static GraphicsPath Rounded(Rectangle r, int radius)
    {
        var p = new GraphicsPath();
        int d = radius * 2;
        p.AddArc(r.Left, r.Top, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
