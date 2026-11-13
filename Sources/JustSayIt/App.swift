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
            StatusIconView()
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

    /// Never lose a recording on quit: finish it, save it and send it first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let notes = NoteTaker.shared
            guard notes.isBusy || CIQSender.shared.isBusy else { return .terminateNow }
            Controller.shared.overlay.show(.error("Saving your notes before quitting…"))
            Task { @MainActor in
                if notes.isRecording { await notes.stop(sendImmediately: true) }
                // Wait (up to 5 minutes) for the notes to be written and sent.
                for _ in 0..<300 where notes.isBusy || CIQSender.shared.isBusy {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}

struct MenuContent: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store
    @ObservedObject var notes = NoteTaker.shared
    @ObservedObject var autoJoin = AutoJoin.shared
    @ObservedObject var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Hold \(store.prefs.hotkey.label) to talk")
        Text("Double-tap for hands-free · add ⇧ for Scribe")
        Text("Press Right ⇧ three times for the Note Taker")
        Divider()
        Text("Icon colors: cyan ready · pink dictating · purple Scribe · green Note Taker · orange working")
        Divider()
        Button("Start / Stop Dictation") { c.toggleFromMenu() }
        if NoteTaker.shared.isRecording {
            Button("⏹ End Note Taker and send") { NoteTaker.shared.endByUser() }
        } else {
            Button("Start Note Taker (Right ⇧ ×3)") { c.toggleNotes() }
        }
        Button("Show Note Taker") { NoteWindow.shared.show() }
        Toggle("Add Teams / Meet captions", isOn: $store.prefs.captureMeetingCaptions)
        Button("Import meeting transcript…") { CaptionConnector.shared.importTranscript() }.disabled(!notes.isRecording)
        Button("Set up caption connector…") { CaptionConnector.shared.openSetup() }
        Button("CollectivIQ…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
            NotificationCenter.default.post(name: .openPane, object: "CollectivIQ")
        }
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
        if Updater.shared.updateAvailable, let v = Updater.shared.latest {
            Button("⬆︎ Install update \(v)") { Updater.shared.install() }
        } else {
            Button("Check for Updates…") { Task { await Updater.shared.check(userInitiated: true) } }
        }
        Button("About Just Say It") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Just Say It",
                .credits: NSAttributedString(string: "An original app designed and built by Stefano Roman Gunness.\nFree, private voice typing and meeting notes for Mac and Windows.\nTriple-tap Right Shift to start the Note Taker."),
            ])
        }
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
