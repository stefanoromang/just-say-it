// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation
import WebKit

/// Sends Note Taker transcripts to CollectivIQ inside Just Say It (no external browser).
/// CollectivIQ runs in an in-app window; each person signs in there once and the
/// window remembers the session. When a recording ends, the app opens a new chat,
/// types the prompt + full transcript into the chat box and presses Send.
@MainActor
enum CollectivIQ {
    static let chatURL = URL(string: "https://collectiviq.ai/chat")!
    static let loginURL = URL(string: "https://collectiviq.ai/login")!

    static let defaultPrompt = "Summarize this meeting: key points, decisions, action items with owners and dates, and open questions."

    /// The text sent to the chat: the prompt, then the transcript.
    static func message(prompt: String, title: String?, transcript: String) -> String {
        var s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultPrompt }
        if let title, !title.isEmpty { s += "\n\nMeeting: \(title)" }
        s += "\n\nTranscript:\n\(transcript)"
        return s
    }

    static func send(title: String?, transcript: String, force: Bool = false) {
        let p = Store.shared.prefs
        guard (p.ciqEnabled || force), !transcript.isEmpty else { return }
        CIQWindow.shared.send(message(prompt: p.ciqPrompt, title: title, transcript: transcript))
    }

    static func showWindow(signIn: Bool = false) {
        CIQWindow.shared.show(url: signIn ? loginURL : chatURL)
    }

    /// Fills CollectivIQ's chat box and presses Send. Returns "login", "wait", "filled" or "sent".
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
            ta.focus();
            ta.value = msg;
            ta.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            try { h.value = msg; } catch (e) {}
            h.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
            h.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
          }
          return 'filled';
        })(\(arg)[0])
        """
    }
}

/// The in-app CollectivIQ window. Cookies and sign-in are kept by WebKit between launches.
@MainActor
final class CIQWindow: NSObject, WKNavigationDelegate {
    static let shared = CIQWindow()

    private var window: NSWindow?
    private var web: WKWebView?
    private var pending: String?
    private var timer: Timer?
    private var startedAt = Date()
    private var signInNoticeShown = false

    private func ensure() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // persistent: stay signed in
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = self
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "CollectivIQ – Just Say It"
        win.isReleasedWhenClosed = false
        win.contentView = w
        win.center()
        window = win
        web = w
        return w
    }

    func show(url: URL? = nil) {
        let w = ensure()
        if let url { w.load(URLRequest(url: url)) }
        else if w.url == nil { w.load(URLRequest(url: CollectivIQ.chatURL)) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Opens a new chat and sends the message once the chat box is ready (waits for sign-in if needed).
    func send(_ msg: String) {
        pending = msg
        startedAt = Date()
        signInNoticeShown = false
        show(url: CollectivIQ.chatURL)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { CIQWindow.shared.tick() }
        }
    }

    private func tick() {
        guard let msg = pending, let web else { stop(); return }
        if Date().timeIntervalSince(startedAt) > 600 {
            stop()
            Controller.shared.overlay.show(.error("CollectivIQ: timed out – transcript is saved in your note"))
            return
        }
        web.evaluateJavaScript(CollectivIQ.script(for: msg)) { result, _ in
            MainActor.assumeIsolated {
                switch result as? String {
                case "sent":
                    self.stop()
                    Controller.shared.overlay.show(.done)
                case "login":
                    if !self.signInNoticeShown {
                        self.signInNoticeShown = true
                        Controller.shared.overlay.show(.error("Sign in to CollectivIQ in the window – the transcript is sent right after"))
                    }
                    // After signing in, CollectivIQ goes to its chat page and the next tick sends.
                default:
                    break
                }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }
}
