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
        Task { @MainActor in
            _ = try? await webView.evaluateJavaScript(CollectivIQ.reset)
            CIQSender.shared.loading = false
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in CIQSender.shared.loading = false }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in CIQSender.shared.loading = false }
    }
    static let shared = CIQSender()

    private var window: NSWindow?
    private var web: WKWebView?
    private struct Item { let text: String; var destination: CollectivIQ.Destination; let id = UUID() }
    private var queue: [Item] = []
    /// The page shown is ready for the message at the front of the queue.
    private var pageReadyFor: UUID?
    private var inFlight = false
    fileprivate var loading = false
    /// Sending or waiting to send.
    var isBusy: Bool { timer != nil }
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
    func send(_ msgs: [String], to dest: CollectivIQ.Destination = .chat) {
        guard !msgs.isEmpty else { return }
        let wasIdle = timer == nil
        queue.append(contentsOf: msgs.map { Item(text: $0, destination: dest) })
        settleUntil = nil
        let w = ensure()
        guard wasIdle else { return }   // already sending: the new messages wait their turn
        sentCount = 0
        startedAt = Date()
        shownForLogin = false
        pageReadyFor = nil
        if Store.shared.prefs.ciqShowPreview {
            window?.alphaValue = 1
            window?.ignoresMouseEvents = false
            window?.collectionBehavior = []
            window?.title = "CollectivIQ – Just Say It (preview)"
            window?.makeKeyAndOrderFront(nil)
        } else if window?.isVisible != true {
            // Invisible but "on screen", so the page keeps running timers and scripts.
            window?.alphaValue = 0
            window?.ignoresMouseEvents = true
            window?.collectionBehavior = [.transient, .ignoresCycle]
            window?.orderFrontRegardless()
            window?.orderBack(nil)
        }
        _ = w
        CollectivIQ.notify("JustSayIt – syncing with CollectivIQ",
                           "Your notes are being synced and processed inside CollectivIQ.")
        Controller.shared.overlay.show(.error("Syncing with CollectivIQ…"))
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { CIQSender.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keeps sending while a dialog or menu is open
        timer = t
    }

    /// Loads a fresh CollectivIQ chat page for the message at the front of the queue.
    private func loadFresh(for item: Item) {
        pageReadyFor = item.id
        loading = true
        web?.load(URLRequest(url: CollectivIQ.chatURL))
    }

    private func tick() {
        guard let web else { return }
        if let until = settleUntil {
            // Let CollectivIQ register the last message before reporting completion.
            if Date() >= until { finish() }
            return
        }
        guard let item = queue.first else {
            settleUntil = Date().addingTimeInterval(10)
            return
        }
        if Date().timeIntervalSince(startedAt) > 900 {
            fail("CollectivIQ didn't respond. Your notes are saved on this Mac.")
            return
        }
        // Each message starts on its own freshly loaded page, and only one script runs at a time.
        if pageReadyFor != item.id { loadFresh(for: item); return }
        guard !loading, !inFlight else { return }
        let js: String
        switch item.destination {
        case .chat: js = CollectivIQ.script(for: item.text)
        case .ddr(let name): js = CollectivIQ.ddrScript(for: item.text, ddr: name)
        }
        inFlight = true
        web.evaluateJavaScript(js) { result, _ in
            MainActor.assumeIsolated {
                CIQSender.shared.inFlight = false
                CIQSender.shared.handle(result as? String, for: item.id)
            }
        }
    }

    private func handle(_ r: String?, for id: UUID) {
        guard let first = queue.first, first.id == id else { return }
        switch r {
        case "sent":
            queue.removeFirst()
            sentCount += 1
            if shownForLogin && !Store.shared.prefs.ciqShowPreview { hideAgain() }
            shownForLogin = false
            startedAt = Date()
        case "ddr:missing":
            if case .ddr(let name) = first.destination {
                CollectivIQ.notify("JustSayIt – DDR not found", "No DDR called \(name) was found, so the notes go to a new CIQ chat instead.")
                queue[0].destination = .chat
                loadFresh(for: queue[0])
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
        pageReadyFor = nil
        if !shownForLogin, window?.alphaValue == 0 { window?.orderOut(nil) }
        window?.title = "Sign in to CollectivIQ – Just Say It"
        settleUntil = nil
        let n = sentCount
        Controller.shared.overlay.show(.sent)
        CollectivIQ.notify("JustSayIt – sent to CollectivIQ",
                           n > 1 ? "\(n) transcripts were sent. CollectivIQ is processing your notes."
                                 : "Your transcript was sent. CollectivIQ is processing your notes.")
    }

    private func fail(_ text: String) {
        timer?.invalidate(); timer = nil
        queue.removeAll()
        pageReadyFor = nil; inFlight = false
        Controller.shared.overlay.show(.error(text))
        CollectivIQ.notify("JustSayIt – CollectivIQ", text)
    }
}
