// Just Say It – created by Stefano Roman Gunness · MIT License
import AppKit
import Foundation

@MainActor
final class CaptionConnector: ObservableObject {
    static let shared = CaptionConnector()
    @Published private(set) var status = "Meeting captions are off"
    @Published private(set) var lines: [MeetingCaption] = []
    private var token = "", session: String?
    private var timer: Timer?
    private var offset: UInt64 = 0
    private var pending = Data()
    private var service = ""
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JustSayIt")
    }
    private var file: URL { Self.directory.appendingPathComponent("captions-\(token).jsonl") }

    func start(service: String) {
        stop()
        lines = []; session = nil; offset = 0; pending = Data()
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        self.service = ["teams", "meet"].contains(service) ? service : ""
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { Self.shared.tick() } }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    private func tick() {
        let enabled = Store.shared.prefs.captureMeetingCaptions && NoteTaker.shared.isRecording
        let state: [String: Any] = ["token": token, "enabled": enabled, "service": service, "updated": Date().timeIntervalSince1970]
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: state).write(to: Self.directory.appendingPathComponent("caption-state.json"), options: .atomic)
            if let h = try? FileHandle(forReadingFrom: file) {
                defer { try? h.close() }
                try h.seek(toOffset: offset)
                let data = try h.read(upToCount: 262144) ?? Data(); offset += UInt64(data.count); pending.append(data)
                while let end = pending.firstIndex(of: 10) {
                    let data = Data(pending[..<end]); pending.removeSubrange(...end)
                    if let row = try? JSONDecoder().decode(MeetingCaption.self, from: data),
                       Store.shared.prefs.captureMeetingCaptions, enabled || timer == nil {
                        let before = lines
                        MeetingTranscript.merge([row], into: &lines, session: &session)
                        if before != lines { NoteTaker.shared.captionsChanged() }
                    }
                }
            }
            status = !enabled ? "Meeting captions are off" : lines.isEmpty ? "Waiting for Teams web / Meet captions · audio backup is active" : "Connected · \(lines.count) speaker-labelled captions"
        } catch { status = "Caption connector unavailable · audio backup is active" }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if !token.isEmpty { tick(); try? FileManager.default.removeItem(at: file) }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent("caption-state.json"))
        token = ""
    }

    func reset() { lines = []; session = nil }

    func importTranscript() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.title = "Add a Teams or Google Meet transcript (.vtt, .srt, .txt)"
        guard NoteTaker.shared.isRecording, panel.runModal() == .OK, NoteTaker.shared.isRecording, let url = panel.url else { return }
        do {
            let info = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (info.fileSize ?? 0) <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let rows = MeetingTranscript.parse(try String(contentsOf: url, encoding: .utf8))
            guard !rows.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            // Imports may contain the complete history: retain it as a separate session, without mixing live streams.
            lines.append(contentsOf: rows)
            status = "Imported \(rows.count) transcript lines"
            NoteTaker.shared.captionsChanged()
        } catch { status = "Could not import transcript: \(error.localizedDescription)" }
    }

    func openSetup() {
        guard let resources = Bundle.main.resourceURL else { return }
        NSWorkspace.shared.open(resources.appendingPathComponent("captions"))
    }
}
