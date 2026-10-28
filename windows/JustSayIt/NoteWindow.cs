// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;

namespace JustSayIt;

/// Floating window with the live transcript, a timer and Stop / Copy / Open buttons.
public sealed class NoteWindow : Form
{
    static NoteWindow? shared;

    public static void ShowShared()
    {
        if (shared == null || shared.IsDisposed) shared = new NoteWindow();
        shared.Show();
        shared.Activate();
    }

    readonly NoteTaker n = NoteTaker.Shared;
    readonly Label title = new() { Font = new Font("Segoe UI Semibold", 11f), AutoSize = true };
    readonly Label status = new() { ForeColor = Color.DimGray, AutoSize = true, Font = new Font("Segoe UI", 8.5f) };
    readonly RichTextBox transcript = new() { ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Color.White, Font = new Font("Segoe UI", 10f) };
    readonly Button toggle = new() { AutoSize = true };
    readonly Button copy = new() { Text = "Copy transcript", AutoSize = true };
    readonly Button open = new() { Text = "Open note", AutoSize = true, Visible = false };
    readonly Button folder = new() { Text = "Notes folder", AutoSize = true };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 500 };
    int shownLines = -1;

    NoteWindow()
    {
        Text = "Just Say It – Note Taker";
        Icon = Program.AppIcon;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(560, 460);
        MinimumSize = new Size(420, 300);
        Font = new Font("Segoe UI", 9.5f);
        BackColor = Color.FromArgb(248, 248, 252);
        var wa = Screen.PrimaryScreen!.WorkingArea;
        Location = new Point(wa.Right - Width - 20, wa.Top + 20);

        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 64, Padding = new Padding(12, 10, 12, 0), FlowDirection = FlowDirection.TopDown };
        top.Controls.Add(title);
        top.Controls.Add(status);
        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 46, Padding = new Padding(10, 8, 10, 6) };
        bottom.Controls.AddRange(new Control[] { toggle, copy, open, folder });
        var mid = new Panel { Dock = DockStyle.Fill, Padding = new Padding(12, 4, 12, 4) };
        transcript.Dock = DockStyle.Fill;
        mid.Controls.Add(transcript);
        Controls.Add(mid);
        Controls.Add(top);
        Controls.Add(bottom);

        toggle.Click += (_, _) => Controller.Shared.ToggleNotes();
        copy.Click += (_, _) => { var t = n.TranscriptText(); if (t.Length > 0) Inserter.SetClipboard(t); };
        open.Click += (_, _) => { if (n.LastNotePath != null) Launch(n.LastNotePath); };
        folder.Click += (_, _) => Launch(NoteTaker.NotesDir);
        n.Changed += OnChanged;
        timer.Tick += (_, _) => Render();
        timer.Start();
        FormClosed += (_, _) => { n.Changed -= OnChanged; timer.Stop(); };
        Render();
    }

    void OnChanged() => Ui.Run(Render);

    void Render()
    {
        if (IsDisposed) return;
        var elapsed = n.IsRecording ? "  " + NoteTaker.Stamp((DateTime.Now - n.StartedAt).TotalSeconds) : "";
        title.Text = (n.IsRecording ? "● Recording" : "Note Taker") + elapsed;
        title.ForeColor = n.IsRecording ? Color.Firebrick : Color.Black;
        status.Text = n.Status + (n.IsRecording ? " · press Right Shift three times to stop" : "");
        toggle.Text = n.IsRecording ? "■ Stop" : "● New note";
        open.Visible = !n.IsRecording && n.LastNotePath != null;
        if (n.Lines.Count != shownLines)
        {
            shownLines = n.Lines.Count;
            transcript.Clear();
            foreach (var l in n.Lines.ToArray())
            {
                transcript.SelectionColor = Color.Gray;
                transcript.AppendText(NoteTaker.Stamp(l.Time) + "  ");
                transcript.SelectionColor = l.Speaker == "Me" ? Color.FromArgb(110, 70, 220) : Color.SteelBlue;
                transcript.SelectionFont = new Font("Segoe UI Semibold", 10f);
                transcript.AppendText(l.Speaker + ": ");
                transcript.SelectionColor = Color.Black;
                transcript.SelectionFont = transcript.Font;
                transcript.AppendText(l.Text + "\n\n");
            }
            transcript.SelectionStart = transcript.TextLength;
            transcript.ScrollToCaret();
        }
    }

    static void Launch(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        base.OnFormClosing(e);
    }
}
