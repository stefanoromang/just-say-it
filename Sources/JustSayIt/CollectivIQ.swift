// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation

/// After a Note Taker recording: opens CollectivIQ in the browser with the
/// user's prompt + the full transcript copied, ready to paste into the chat.
/// People sign in on the website themselves; the browser remembers them.
@MainActor
enum CollectivIQ {
    static let chatURL = URL(string: "https://collectiviq.ai/chat")!

    static let defaultPrompt = "Summarize this meeting: key points, decisions, action items with owners and dates, and open questions."

    /// The text placed on the clipboard: the prompt, then the transcript.
    static func message(prompt: String, title: String?, transcript: String) -> String {
        var s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultPrompt }
        if let title, !title.isEmpty { s += "\n\nMeeting: \(title)" }
        s += "\n\nTranscript:\n\(transcript)"
        return s
    }

    static func send(title: String?, transcript: String) {
        let p = Store.shared.prefs
        guard p.ciqEnabled, !transcript.isEmpty else { return }
        let text = message(prompt: p.ciqPrompt, title: title, transcript: transcript)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSWorkspace.shared.open(chatURL)
        Controller.shared.overlay.show(.error("CollectivIQ is open – press ⌘V then Return to send the transcript"))
    }
}
