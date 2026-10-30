// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import ApplicationServices
import CoreAudio
import Foundation

struct LiveCall: Equatable {
    let platform: MeetingPlatform
    let title: String
}

/// Watches which apps are using the microphone. When Microsoft Teams, Zoom or a
/// Google Meet / Teams / Zoom browser tab starts a live call, the Note Taker
/// starts automatically; when the call ends, it stops and saves the transcript.
@MainActor
final class CallWatcher: ObservableObject {
    static let shared = CallWatcher()

    @Published private(set) var activeCall: LiveCall?
    @Published private(set) var status = ""

    private var timer: Timer?
    private var candidate: LiveCall?
    private var candidateSince: Date?
    private var lastSeen: Date?
    private var startedRecording = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// A call must hold the microphone this long before recording starts (ignores quick mic tests).
    private let startDelay: TimeInterval = 3
    /// The microphone must be released this long before the call counts as ended.
    private let endDelay: TimeInterval = 10

    func boot() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { CallWatcher.shared.tick() }
        }
    }

    private func tick() {
        let p = Store.shared.prefs
        let now = Date()
        let call = p.autoRecordCalls ? detect() : nil

        if let call {
            lastSeen = now
            if activeCall == nil {
                if candidate != call { candidate = call; candidateSince = now }
                if let since = candidateSince, now.timeIntervalSince(since) >= startDelay { begin(call) }
            }
        } else {
            candidate = nil
            candidateSince = nil
            if activeCall != nil, now.timeIntervalSince(lastSeen ?? now) >= endDelay { end() }
        }
    }

    private func begin(_ call: LiveCall) {
        activeCall = call
        status = "Live \(call.platform.rawValue) call detected"
        let notes = NoteTaker.shared
        guard !notes.isRecording else { return }          // manual or calendar recording already running
        guard !Controller.shared.transcriber.isRunning else { return }
        startedRecording = true
        let m = UpcomingMeeting(id: "call-\(Int(Date().timeIntervalSince1970))", title: call.title,
                                start: Date(), end: Date().addingTimeInterval(8 * 3600),
                                link: MeetingLink(platform: call.platform, url: URL(string: "about:blank")!),
                                calendar: "Live call", attendees: [])
        Controller.shared.overlay.show(.error("Recording your \(call.platform.rawValue) call – notes save when it ends"))
        Task { await notes.start(meeting: m, origin: .call) }
    }

    private func end() {
        let notes = NoteTaker.shared
        if startedRecording, notes.isRecording, notes.origin == .call {
            Task { await notes.stop() }
        }
        status = activeCall.map { "\($0.platform.rawValue) call ended – transcript saved" } ?? ""
        activeCall = nil
        startedRecording = false
    }

    // MARK: Detection

    private func detect() -> LiveCall? {
        let p = Store.shared.prefs
        var browsers = Set<String>()
        for user in Self.micUsers() where user.pid != ownPID {
            switch CallApps.kind(bundleID: user.bundleID) {
            case .native(let platform)? where enabled(platform, p):
                return LiveCall(platform: platform, title: nativeTitle(platform))
            case .browser(let name)?:
                browsers.insert(name)
            default:
                break
            }
        }
        for name in browsers {
            if let call = browserCall(appName: name), enabled(call.platform, p) { return call }
        }
        return nil
    }

    private func enabled(_ platform: MeetingPlatform, _ p: Prefs) -> Bool {
        switch platform {
        case .teams: p.recordTeamsCalls
        case .zoom: p.recordZoomCalls
        case .meet: p.recordMeetCalls
        }
    }

    struct MicUser { let pid: pid_t; let bundleID: String }

    /// Processes currently capturing audio input, from Core Audio's process list.
    nonisolated static func micUsers() -> [MicUser] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var input: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &input) == noErr, input != 0 else { return nil }
            var pid: pid_t = 0
            s = UInt32(MemoryLayout<pid_t>.size)
            a.mSelector = kAudioProcessPropertyPID
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &pid)
            var cf: Unmanaged<CFString>?
            s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            a.mSelector = kAudioProcessPropertyBundleID
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &cf)
            let bundle = cf?.takeRetainedValue() as String? ?? ""
            return MicUser(pid: pid, bundleID: bundle)
        }
    }

    /// Meeting name from the app's window title, e.g. "Weekly sync | Microsoft Teams".
    private func nativeTitle(_ platform: MeetingPlatform) -> String {
        let prefix = platform == .teams ? "com.microsoft.teams" : "us.zoom.xos"
        let titles = NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").lowercased().hasPrefix(prefix) }
            .flatMap { windowTitles(pid: $0.processIdentifier) }
        let skip = ["microsoft teams", "zoom", "zoom workplace", "chat", "calendar", "activity", ""]
        for t in titles {
            var name = t.replacingOccurrences(of: " | Microsoft Teams", with: "")
                .replacingOccurrences(of: " - Microsoft Teams", with: "")
                .trimmingCharacters(in: .whitespaces)
            if name.lowercased().hasPrefix("meeting with ") || name.lowercased().contains("call") || !skip.contains(name.lowercased()) {
                if name.count > 80 { name = String(name.prefix(80)) }
                if !skip.contains(name.lowercased()) { return name }
            }
        }
        return "\(platform.rawValue) call"
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

    /// A browser is using the microphone: check its tabs for a Meet / Teams / Zoom call.
    private func browserCall(appName: String) -> LiveCall? {
        let scriptable = ["Google Chrome", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera", "Safari"]
        if scriptable.contains(appName), NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == appName }) {
            let src = appName == "Safari"
                ? "tell application \"Safari\" to get {URL, name} of every tab of every window"
                : "tell application \"\(appName)\" to get {URL, title} of every tab of every window"
            var err: NSDictionary?
            if let r = NSAppleScript(source: src)?.executeAndReturnError(&err), r.numberOfItems >= 2,
               let urls = r.atIndex(1), let names = r.atIndex(2) {
                for w in 1...max(urls.numberOfItems, 1) {
                    guard let wu = urls.atIndex(w), let wn = names.atIndex(w) else { continue }
                    for t in 1...max(wu.numberOfItems, 1) {
                        let url = wu.atIndex(t)?.stringValue ?? ""
                        if let platform = CallApps.platform(forURL: url) {
                            return LiveCall(platform: platform, title: cleanTabTitle(wn.atIndex(t)?.stringValue, platform))
                        }
                    }
                }
            }
        }
        // Firefox and fallback: window titles.
        for app in NSWorkspace.shared.runningApplications where app.localizedName == appName || (appName == "Safari" && app.bundleIdentifier == "com.apple.Safari") {
            for t in windowTitles(pid: app.processIdentifier) {
                if let platform = CallApps.platform(forTitle: t) { return LiveCall(platform: platform, title: cleanTabTitle(t, platform)) }
            }
        }
        return nil
    }

    private func cleanTabTitle(_ raw: String?, _ platform: MeetingPlatform) -> String {
        var t = (raw ?? "").trimmingCharacters(in: .whitespaces)
        for cut in [" - Google Chrome", " – Google Chrome", " - Microsoft Edge", " | Microsoft Teams", " - Brave", " — Mozilla Firefox"] {
            t = t.replacingOccurrences(of: cut, with: "")
        }
        if t.lowercased().hasPrefix("meet - ") || t.lowercased().hasPrefix("meet – ") { t = String(t.dropFirst(7)) }
        if t.isEmpty || t.lowercased() == "meet" || t.lowercased() == "microsoft teams" { return "\(platform.rawValue) call" }
        return String(t.prefix(80))
    }
}
