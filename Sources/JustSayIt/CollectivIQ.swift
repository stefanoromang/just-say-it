// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation
import UserNotifications
import WebKit

/// Sends Note Taker transcripts to CollectivIQ in the background.
/// CollectivIQ runs in a hidden in-app web view; the window is shown only when
/// the person has to sign in. Each person signs in once; the session is remembered.
@MainActor
enum CollectivIQ {
    static let chatURL = URL(string: "https://collectiviq.ai/chat")!
    static let loginURL = URL(string: "https://collectiviq.ai/login")!
    static let defaultPrompt = ciqStandardPrompt

    enum Choice { case raw, smart, both }

    static func message(prompt: String, title: String?, transcript: String) -> String {
        var s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultPrompt }
        s += "\n\n"
        if let title, !title.isEmpty { s += "Meeting: \(title)\n\n" }
        s += transcript
        return s
    }

    /// Called when a recording is saved: asks Raw / Smart / Both, then sends in the background.
    static func deliver(title: String?, raw: String, smart: String?) {
        guard Store.shared.prefs.ciqEnabled, !raw.isEmpty else { return }
        let choice = smart == nil ? .raw : ask()
        guard let choice else { return }
        let prompt = Store.shared.prefs.ciqPrompt
        var msgs: [String] = []
        if choice == .raw || choice == .both {
            msgs.append(message(prompt: prompt, title: title.map { $0 + " (raw transcript)" }, transcript: raw))
        }
        if let smart, choice == .smart || choice == .both {
            msgs.append(message(prompt: prompt, title: title.map { $0 + " (smart transcript)" }, transcript: smart))
        }
        CIQSender.shared.send(msgs)
    }

    /// For "Send my last note now" and other one-off sends (no question asked).
    static func send(title: String?, transcript: String, force: Bool = false) {
        let p = Store.shared.prefs
        guard (p.ciqEnabled || force), !transcript.isEmpty else { return }
        CIQSender.shared.send([message(prompt: p.ciqPrompt, title: title, transcript: transcript)])
    }

    static func showWindow(signIn: Bool = false) {
        CIQSender.shared.show(url: signIn ? loginURL : chatURL)
    }

    private static func ask() -> Choice? {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }
        let a = NSAlert()
        a.messageText = "Send this recording to CollectivIQ?"
        a.informativeText = "Raw: exactly as heard.\nSmart: words and logic fixed so it reads clearly.\nBoth: the raw transcript first, then the smart one."
        a.addButton(withTitle: "Smart")
        a.addButton(withTitle: "Raw")
        a.addButton(withTitle: "Both")
        let skip = a.addButton(withTitle: "Don't send")
        skip.keyEquivalent = "\u{1b}"
        a.window.level = .floating
        switch a.runModal() {
        case .alertFirstButtonReturn: return .smart
        case .alertSecondButtonReturn: return .raw
        case .alertThirdButtonReturn: return .both
        default: return nil
        }
    }

    /// Fills the chat box and presses Send. Returns "login", "wait", "filled" or "sent".
    static func script(for msg: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [msg])) ?? Data("[\"\"]".utf8)
        let arg = String(decoding: data, as: UTF8.self)
        return """
        (function(msg){
          if (location.pathname.indexOf('/login') === 0) return 'login';
          var h = document.querySelector('wa-textarea[data-testid=chat-input]');
          if (!h || !h.shadowRoot) return 'wait';
          var ta = h.shadowRoot.querySelector('textarea');
          if (!ta) return 'wait';
          var b = document.querySelector('[data-testid=send-button]');
          if (h.value === msg && b && !b.hasAttribute('disabled')) { b.click(); return 'sent'; }
          if (h.value !== msg) {
            ta.focus(); ta.value = msg;
            ta.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            try { h.value = msg; } catch (e) {}
            h.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            h.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
          }
          return 'filled';
        })(\(arg)[0])
        """
    }

    static func notify(_ title: String, _ body: String) {
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = title
            n.body = body
            n.sound = .default
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
        }
    }
}
