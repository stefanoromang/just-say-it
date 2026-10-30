// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;

namespace JustSayIt;

/// After a Note Taker recording: opens CollectivIQ in the browser with the
/// user's prompt + the full transcript copied, ready to paste into the chat.
/// People sign in on the website themselves; the browser remembers them.
public static class CollectivIQ
{
    public const string ChatUrl = "https://collectiviq.ai/chat";
    public const string DefaultPrompt = "Summarize this meeting: key points, decisions, action items with owners and dates, and open questions.";

    public static string Message(string prompt, string? title, string transcript)
    {
        var s = string.IsNullOrWhiteSpace(prompt) ? DefaultPrompt : prompt.Trim();
        if (!string.IsNullOrWhiteSpace(title)) s += $"\n\nMeeting: {title}";
        return s + $"\n\nTranscript:\n{transcript}";
    }

    public static void Send(string? title, string transcript)
    {
        var p = Store.Shared.Prefs;
        if (!p.CiqEnabled || string.IsNullOrWhiteSpace(transcript)) return;
        var text = Message(p.CiqPrompt, title, transcript);
        Ui.Run(() =>
        {
            Inserter.SetClipboard(text);
            OpenChat();
            Controller.Shared.Overlay.ShowState(OverlayState.Error, "CollectivIQ is open – press Ctrl+V then Enter to send the transcript");
        });
    }

    public static void OpenChat()
    {
        try { Process.Start(new ProcessStartInfo(ChatUrl) { UseShellExecute = true }); } catch { }
    }
}
