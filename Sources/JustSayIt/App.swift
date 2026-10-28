import AppKit
import SwiftUI

@main
struct JustSayItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var c = Controller.shared
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(c: c, store: store)
        } label: {
            Image(systemName: "waveform.circle.fill")
        }
        Window("Just Say It", id: "main") {
            MainView(c: c, store: store)
                .frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 860, height: 600)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated { Controller.shared.boot() }
    }
}

struct MenuContent: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Hold \(store.prefs.hotkey.label) to talk")
        Text("Double-tap for hands-free · add ⇧ for Scribe")
        Text("Press Right ⇧ three times for the Note Taker")
        Divider()
        Button("Start / Stop Dictation") { c.toggleFromMenu() }
        Button(NoteTaker.shared.isRecording ? "Stop Note Taker" : "Start Note Taker (Right ⇧ ×3)") { c.toggleNotes() }
        Button("Show Note Taker") { NoteWindow.shared.show() }
        if let next = AutoJoin.shared.upcoming.first(where: { $0.end > Date() }) {
            Button("Join now: \(next.title) (\(next.start.formatted(date: .omitted, time: .shortened)))") { AutoJoin.shared.join(next, automatic: false) }
        }
        Menu("Rewrite Selected Text") {
            ForEach(RewriteStyle.allCases) { s in
                Button(s.label) { c.rewriteSelection(s) }
            }
        }
        Divider()
        if !c.micGranted || !c.axGranted {
            Text("⚠️ Permissions needed – open Just Say It")
        }
        Button("Open Just Say It…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut(",")
        Divider()
        Button("About Just Say It") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Just Say It",
                .credits: NSAttributedString(string: "Created by Stefano Roman Gunness\nFree, private voice typing for Mac and Windows."),
            ])
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
