// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

namespace JustSayIt;

/// Shows the finished text after dictation: edit it, Insert, Copy, Rewrite or use the raw words.
public sealed class ResultCard : Form
{
    public event Action? InsertClicked;
    public event Action<RewriteStyle>? RewriteClicked;
    public event Action? RawClicked;

    readonly TextBox box = new();
    readonly Label context = new();
    readonly Label note = new();
    readonly Label mode = new();
    readonly Button insert = new();
    readonly Button copy = new();
    readonly Button rewrite = new();
    readonly Button raw = new();
    readonly Label busy = new();

    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public string Text2 { get => box.Text; set { box.Text = value; box.SelectionStart = box.TextLength; } }

    public ResultCard()
    {
        Text = "Just Say It";
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(520, 300);
        Font = new Font("Segoe UI", 9.5f);
        BackColor = Color.White;
        KeyPreview = true;
        Icon = Program.AppIcon;

        mode.SetBounds(14, 10, 300, 22);
        mode.Font = new Font("Segoe UI Semibold", 10f);
        mode.ForeColor = Color.FromArgb(110, 70, 220);
        busy.SetBounds(400, 10, 106, 22);
        busy.TextAlign = ContentAlignment.MiddleRight;
        busy.ForeColor = Color.Gray;
        context.SetBounds(14, 34, 492, 34);
        context.ForeColor = Color.DimGray;
        context.Font = new Font("Segoe UI", 8.5f);

        box.Multiline = true;
        box.ScrollBars = ScrollBars.Vertical;
        box.Font = new Font("Segoe UI", 11f);
        box.SetBounds(14, 70, 492, 140);
        box.BorderStyle = BorderStyle.FixedSingle;

        note.SetBounds(14, 214, 492, 20);
        note.Font = new Font("Segoe UI", 8.5f);

        insert.Text = "Insert  (Enter)";
        insert.SetBounds(14, 240, 120, 32);
        insert.BackColor = Color.FromArgb(110, 70, 220);
        insert.ForeColor = Color.White;
        insert.FlatStyle = FlatStyle.Flat;
        insert.FlatAppearance.BorderSize = 0;
        insert.Click += (_, _) => InsertClicked?.Invoke();

        copy.Text = "Copy";
        copy.SetBounds(142, 240, 80, 32);
        copy.Click += (_, _) => { Inserter.SetClipboard(box.Text); SetNote("✓ Copied to clipboard", true); };

        rewrite.Text = "Rewrite ▾";
        rewrite.SetBounds(230, 240, 100, 32);
        var menu = new ContextMenuStrip();
        foreach (RewriteStyle s in Enum.GetValues<RewriteStyle>())
        {
            var style = s;
            menu.Items.Add(Labels.Of(s), null, (_, _) => RewriteClicked?.Invoke(style));
        }
        rewrite.Click += (_, _) => menu.Show(rewrite, new Point(0, rewrite.Height));

        raw.Text = "Raw";
        raw.SetBounds(338, 240, 70, 32);
        raw.Click += (_, _) => RawClicked?.Invoke();

        var hint = new Label { Text = "Ctrl+Enter Insert · Esc Close", ForeColor = Color.Silver, Font = new Font("Segoe UI", 8f) };
        hint.SetBounds(14, 278, 300, 18);

        Controls.AddRange(new Control[] { mode, busy, context, box, note, insert, copy, rewrite, raw, hint });
        AcceptButton = null;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape) { Hide(); e.Handled = true; }
        else if (e.KeyCode == Keys.Enter && (e.Control || !box.Focused)) { InsertClicked?.Invoke(); e.Handled = true; e.SuppressKeyPress = true; }
        base.OnKeyDown(e);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }

    public void SetBusy(bool b) { busy.Text = b ? "Working…" : ""; insert.Enabled = copy.Enabled = rewrite.Enabled = raw.Enabled = !b; }

    public void SetNote(string text, bool good)
    {
        note.Text = text;
        note.ForeColor = good ? Color.SeaGreen : Color.DarkOrange;
    }

    public void Present(string text, string modeText, string contextLine, string noteText, bool good, bool focus)
    {
        mode.Text = "Just Say It · " + modeText;
        context.Text = contextLine;
        Text2 = text;
        SetNote(noteText, good);
        SetBusy(false);
        var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Bottom - Height - 90);
        if (focus)
        {
            Show();
            Activate();
            box.Focus();
        }
        else
        {
            ShowNoActivate();
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    void ShowNoActivate()
    {
        ShowWindow(Handle, 4); // SW_SHOWNOACTIVATE
        SetWindowPos(Handle, new IntPtr(-1), Left, Top, Width, Height, 0x0010 | 0x0040); // TOPMOST, NOACTIVATE|SHOWWINDOW
        Visible = true;
    }
}
