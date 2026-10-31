// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation
import WebKit

/// Hidden CollectivIQ web view. Messages are sent one after another without showing
/// anything; the window appears only when the person must sign in.
@MainActor
final class CIQSender: NSObject, WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in _ = try? await webView.evaluateJavaScript(CollectivIQ.reset) }
    }
    static let shared = CIQSender()

    private var window: NSWindow?
    private var web: WKWebView?
    private var queue: [String] = []
    private var timer: Timer?
    private var startedAt = Date()
    private var sentCount = 0
    private var shownForLogin = false
    private var settleUntil: Date?

    private func ensure() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()   // persistent: stays signed in
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 780), configuration: cfg)
        w.navigationDelegate = self
        let win = NSWindow(contentRect: w.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "Sign in to CollectivIQ – Just Say It"
        win.isReleasedWhenClosed = false
        win.contentView = w
        win.center()
        window = win
        web = w
        return w
    }

    /// Shows the window (sign-in or browsing on request).
    func show(url: URL) {
        let w = ensure()
        window?.alphaValue = 1
        window?.ignoresMouseEvents = false
        window?.collectionBehavior = []
        w.load(URLRequest(url: url))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Queues messages and sends them in the background, in order.
    func send(_ msgs: [String]) {
        guard !msgs.isEmpty else { return }
        queue.append(contentsOf: msgs)
        sentCount = 0
        startedAt = Date()
        shownForLogin = false
        settleUntil = nil
        let w = ensure()
        if Store.shared.prefs.ciqShowPreview {
            window?.alphaValue = 1
            window?.ignoresMouseEvents = false
            window?.collectionBehavior = []
            window?.title = "CollectivIQ – Just Say It (preview)"
            window?.makeKeyAndOrderFront(nil)
            w.load(URLRequest(url: CollectivIQ.chatURL))
        } else if window?.isVisible != true {
            // Invisible but "on screen", so the page keeps running timers and scripts.
            window?.alphaValue = 0
            window?.ignoresMouseEvents = true
            window?.collectionBehavior = [.transient, .ignoresCycle]
            window?.orderFrontRegardless()
            window?.orderBack(nil)
            w.load(URLRequest(url: CollectivIQ.chatURL))
        }
        CollectivIQ.notify("JustSayIt – syncing with CollectivIQ",
                           "Your notes are being synced and processed inside CollectivIQ.")
        Controller.shared.overlay.show(.error("Syncing with CollectivIQ…"))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { CIQSender.shared.tick() }
        }
    }

    private func tick() {
        guard let web else { return }
        if let until = settleUntil {
            // Let CollectivIQ register the last message before reporting completion.
            if Date() >= until { finish() }
            return
        }
        guard let msg = queue.first else {
            settleUntil = Date().addingTimeInterval(10)
            return
        }
        if Date().timeIntervalSince(startedAt) > 900 {
            fail("CollectivIQ didn't respond. Your notes are saved on this Mac.")
            return
        }
        web.evaluateJavaScript(CollectivIQ.script(for: msg)) { result, _ in
            MainActor.assumeIsolated { self.handle(result as? String) }
        }
    }

    private func handle(_ r: String?) {
        switch r {
        case "sent":
            queue.removeFirst()
            sentCount += 1
            if shownForLogin && !Store.shared.prefs.ciqShowPreview { hideAgain() }
            shownForLogin = false
            // Each message goes to its own new chat.
            if !queue.isEmpty {
                web?.load(URLRequest(url: CollectivIQ.chatURL))
                startedAt = Date()
            }
        case "login":
            if !shownForLogin {
                shownForLogin = true
                window?.alphaValue = 1
                window?.ignoresMouseEvents = false
                window?.collectionBehavior = []
                NSApp.activate(ignoringOtherApps: true)
                window?.makeKeyAndOrderFront(nil)
                CollectivIQ.notify("Sign in to CollectivIQ",
                                   "Your session expired. Sign in once and your notes are sent automatically.")
            }
        default:
            break
        }
    }

    private func hideAgain() {
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        window?.orderBack(nil)
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        if !shownForLogin, window?.alphaValue == 0 { window?.orderOut(nil) }
        window?.title = "Sign in to CollectivIQ – Just Say It"
        settleUntil = nil
        let n = sentCount
        Controller.shared.overlay.show(.done)
        CollectivIQ.notify("JustSayIt – sent to CollectivIQ",
                           n > 1 ? "\(n) transcripts were sent. CollectivIQ is processing your notes."
                                 : "Your transcript was sent. CollectivIQ is processing your notes.")
    }

    private func fail(_ text: String) {
        timer?.invalidate(); timer = nil
        queue.removeAll()
        Controller.shared.overlay.show(.error(text))
        CollectivIQ.notify("JustSayIt – CollectivIQ", text)
    }
}
