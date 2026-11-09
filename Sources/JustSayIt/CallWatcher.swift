// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import ApplicationServices
import CoreAudio
import Foundation

struct LiveCall: Equatable {
    let service: CallService
    let title: String
    /// Process that owns the call (native app bundle ID), or the browser's name for web calls.
    let owner: String
    let pid: pid_t
    var inBrowser = false
}

/// Detects live calls in any supported app (Teams, Meet, Zoom, FaceTime, Webex, Slack huddles,
/// Discord, Skype, Whereby, Jitsi, RingCentral, GoTo, Zoho, Signal, WhatsApp, Telegram).
///
/// Rules:
/// - A call starts when its app (or browser tab) uses the microphone for a few seconds.
/// - The recording is tied to that call. Nothing else (another meeting, calendar events, muting)
///   stops it. It ends only when the call itself ends (its app stops using the mic *and* speakers,
///   or the app quits) or when the user presses **End Note Taker**.
/// - When a call ends, notes are saved and sent to CollectivIQ straight away.
@MainActor
final class CallWatcher: ObservableObject {
    static let shared = CallWatcher()

    @Published private(set) var activeCall: LiveCall?
    @Published private(set) var status = ""

    private var timer: Timer?
    private var candidate: LiveCall?
    private var candidateSince: Date?
    private var lastAlive: Date?
    /// The Note Taker is still setting up for the active call.
    private var starting = false
    /// Last browser-tab check for a web call (AppleScript is slow, so it's cached briefly).
    private var tabCheck: (call: LiveCall, at: Date, open: Bool)?
    private var startedRecording = false
    /// A call the user ended with "End Note Taker": not recorded again until it really ends.
    private var dismissed: LiveCall?
    private var dismissedLastSeen: Date?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// A call must hold the microphone this long before recording starts (ignores quick mic tests).
    let startDelay: TimeInterval = 3
    /// The call must be gone (no mic, no speaker audio) this long before it counts as ended.
    /// Generous so muting yourself or a quiet moment never ends the recording.
    let endDelay: TimeInterval = 45

    func boot() {
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { CallWatcher.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keeps watching while a dialog or menu is open
        timer = t
    }

    /// The user pressed "End Note Taker": finish now and send immediately.
    func endByUser() {
        let notes = NoteTaker.shared
        guard notes.isRecording else { return }
        if let c = activeCall { dismissed = c; dismissedLastSeen = Date() }
        activeCall = nil
        startedRecording = false
        status = "Ended by you – notes saved"
        Task { await notes.stop(sendImmediately: true) }
    }

    private func tick() {
        let p = Store.shared.prefs
        let now = Date()

        // While recording a call: only that call can end it.
        if let call = activeCall {
            let notes = NoteTaker.shared
            if starting {
                if isAlive(call) { lastAlive = now }
                return
            }
            if !notes.isRecording || notes.origin != .call {
                // The recording finished another way: don't record this call again until it's over.
                dismissed = call; dismissedLastSeen = now
                activeCall = nil; startedRecording = false
                return
            }
            if isAlive(call) { lastAlive = now; return }
            if now.timeIntervalSince(lastAlive ?? now) >= endDelay { end(call) }
            return
        }

        // A call the user already ended stays ignored until it's really over (checked even while busy).
        if let d = dismissed {
            if isAlive(d) { dismissedLastSeen = now }
            if now.timeIntervalSince(dismissedLastSeen ?? now) >= endDelay { dismissed = nil }
        }
        guard p.autoRecordCalls, p.noteTakerEnabled, !NoteTaker.shared.isRecording, !NoteTaker.shared.isStarting,
              !Controller.shared.transcriber.isRunning else {
            candidate = nil; candidateSince = nil
            return
        }
        var call = detect()
        if let d = dismissed, let c = call, c.service == d.service, c.inBrowser == d.inBrowser, (!c.inBrowser || c.owner == d.owner) { call = nil }
        if let call {
            if candidate?.service != call.service || candidate?.inBrowser != call.inBrowser { candidate = call; candidateSince = now }
            if let since = candidateSince, now.timeIntervalSince(since) >= startDelay { begin(call) }
        } else {
            candidate = nil; candidateSince = nil
        }
    }

    private func begin(_ call: LiveCall) {
        activeCall = call
        lastAlive = Date()
        candidate = nil; candidateSince = nil
        startedRecording = true
        starting = true
        status = "Recording your \(call.service.name) call"
        let m = UpcomingMeeting(id: "call-\(Int(Date().timeIntervalSince1970))", title: call.title,
                                start: Date(), end: .distantFuture,
                                link: MeetingLink(platform: platform(call.service), url: URL(string: "about:blank")!),
                                calendar: call.service.name, attendees: [])
        Controller.shared.overlay.show(.error("Recording your \(call.service.name) call – it keeps going until the call ends"))
        Task {
            let ok = await NoteTaker.shared.start(meeting: m, origin: .call)
            starting = false
            if !ok, activeCall == call {
                // Couldn't start (e.g. microphone blocked): don't keep retrying this call.
                status = "Couldn't record your \(call.service.name) call: \(NoteTaker.shared.status)"
                dismissed = call; dismissedLastSeen = Date()
                activeCall = nil; startedRecording = false
            }
        }
    }

    private func end(_ call: LiveCall) {
        let notes = NoteTaker.shared
        if startedRecording, notes.isRecording, notes.origin == .call {
            Task { await notes.stop(sendImmediately: true) }
        }
        status = "\(call.service.name) call ended – notes saved and sent"
        activeCall = nil
        startedRecording = false
    }

    private func platform(_ s: CallService) -> MeetingPlatform {
        switch s.id { case "meet": .meet; case "zoom": .zoom; default: .teams }
    }

    // MARK: Detection

    private func detect() -> LiveCall? {
        let p = Store.shared.prefs
        var browsers: [(name: String, pid: pid_t)] = []
        for user in Self.audioProcesses() where user.pid != ownPID && user.input {
            switch CallApps.kind(bundleID: user.bundleID) {
            case .native(let s)? where p.isCallServiceEnabled(s.id):
                return LiveCall(service: s, title: nativeTitle(s, pid: user.pid), owner: user.bundleID, pid: user.pid)
            case .browser(let name)?:
                browsers.append((name, user.pid))
            default:
                break
            }
        }
        for b in browsers {
            if let call = browserCall(appName: b.name, pid: b.pid), p.isCallServiceEnabled(call.service.id) { return call }
        }
        return nil
    }

    /// Is this call still going? True while its app uses the mic or plays sound, so muting yourself
    /// keeps it alive through the other people's audio. For web calls, sound alone only counts while
    /// the browser still shows the call (a YouTube video afterwards doesn't keep it going).
    private func isAlive(_ call: LiveCall) -> Bool {
        let procs = Self.audioProcesses().filter { $0.pid != ownPID }
        if call.inBrowser {
            let mine = procs.filter { CallApps.kind(bundleID: $0.bundleID) == .browser(call.owner) || $0.pid == call.pid }
            if mine.contains(where: \.input) { return true }
            guard mine.contains(where: \.output) else { return false }
            if let c = tabCheck, c.call == call, Date().timeIntervalSince(c.at) < 15 { return c.open }
            let open = browserCall(appName: call.owner, pid: call.pid)?.service == call.service
            tabCheck = (call, Date(), open)
            return open
        }
        let prefixes = call.service.bundlePrefixes
        let owner = call.owner.lowercased()
        return procs.contains { p in
            let b = p.bundleID.lowercased()
            return (prefixes.contains(where: { b.hasPrefix($0) }) || b == owner || p.pid == call.pid) && (p.input || p.output)
        }
    }

    struct AudioProc { let pid: pid_t; let bundleID: String; let input: Bool; let output: Bool }

    /// Processes using audio input or output, from Core Audio's process list.
    nonisolated static func audioProcesses() -> [AudioProc] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        func u32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var v: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr ? v : 0
        }
        return ids.compactMap { id in
            let input = u32(id, kAudioProcessPropertyIsRunningInput) != 0
            let output = u32(id, kAudioProcessPropertyIsRunningOutput) != 0
            guard input || output else { return nil }
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var s = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &pid)
            var cf: Unmanaged<CFString>?
            s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            a.mSelector = kAudioProcessPropertyBundleID
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &cf)
            let bundle = cf?.takeRetainedValue() as String? ?? ""
            return AudioProc(pid: pid, bundleID: bundle, input: input, output: output)
        }
    }

    /// Kept for the self-checks and older callers.
    nonisolated static func micUsers() -> [AudioProc] { audioProcesses().filter(\.input) }

    // MARK: Titles

    private func nativeTitle(_ s: CallService, pid: pid_t) -> String {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let b = (app.bundleIdentifier ?? "").lowercased()
            return s.bundlePrefixes.contains(where: { b.hasPrefix($0) })
        }
        let skip: Set<String> = ["", "microsoft teams", "zoom", "zoom workplace", "chat", "calendar", "activity",
                                 "slack", "discord", "skype", "webex", "facetime", "signal", "whatsapp", "telegram", "ringcentral"]
        for app in apps {
            for t in windowTitles(pid: app.processIdentifier) {
                var name = t
                for cut in [" | Microsoft Teams", " - Microsoft Teams", " - Slack", " | Slack", " - Discord", " - Webex"] {
                    name = name.replacingOccurrences(of: cut, with: "")
                }
                name = name.trimmingCharacters(in: .whitespaces)
                if !skip.contains(name.lowercased()) { return String(name.prefix(80)) }
            }
        }
        return "\(s.name) call"
    }

    private func windowTitles(pid: pid_t) -> [String] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success, let wins = v as? [AXUIElement] else { return [] }
        return wins.compactMap { w in
            var t: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success ? t as? String : nil
        }
    }

    /// A browser is using the microphone: find the tab with a supported web call.
    private func browserCall(appName: String, pid: pid_t) -> LiveCall? {
        let scriptable = ["Google Chrome", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera", "Safari"]
        if scriptable.contains(appName), NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == appName }) {
            let src = appName == "Safari"
                ? "tell application \"Safari\" to get {URL, name} of every tab of every window"
                : "tell application \"\(appName)\" to get {URL, title} of every tab of every window"
            var err: NSDictionary?
            if let r = NSAppleScript(source: src)?.executeAndReturnError(&err), r.numberOfItems >= 2,
               let urls = r.atIndex(1), let names = r.atIndex(2), urls.numberOfItems > 0 {
                for w in 1...urls.numberOfItems {
                    guard let wu = urls.atIndex(w), let wn = names.atIndex(w), wu.numberOfItems > 0 else { continue }
                    for t in 1...wu.numberOfItems {
                        let url = wu.atIndex(t)?.stringValue ?? ""
                        if let s = CallApps.service(forURL: url) {
                            return LiveCall(service: s, title: cleanTitle(wn.atIndex(t)?.stringValue, s), owner: appName, pid: pid, inBrowser: true)
                        }
                    }
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.localizedName == appName || (appName == "Safari" && app.bundleIdentifier == "com.apple.Safari") {
            for t in windowTitles(pid: app.processIdentifier) {
                if let s = CallApps.service(forTitle: t) { return LiveCall(service: s, title: cleanTitle(t, s), owner: appName, pid: pid, inBrowser: true) }
            }
        }
        return nil
    }

    private func cleanTitle(_ raw: String?, _ s: CallService) -> String {
        var t = (raw ?? "").trimmingCharacters(in: .whitespaces)
        for cut in [" - Google Chrome", " – Google Chrome", " - Microsoft Edge", " | Microsoft Teams", " - Brave", " — Mozilla Firefox", " - Safari"] {
            t = t.replacingOccurrences(of: cut, with: "")
        }
        if t.lowercased().hasPrefix("meet - ") || t.lowercased().hasPrefix("meet – ") { t = String(t.dropFirst(7)) }
        if t.isEmpty || t.lowercased() == "meet" || t.lowercased() == s.name.lowercased() { return "\(s.name) call" }
        return String(t.prefix(80))
    }
}
