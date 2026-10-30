// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AVFoundation
import AppKit
import Foundation
import FoundationModels

struct NoteLine: Identifiable, Hashable {
    let id = UUID()
    let speaker: String   // "Me" or "Others"
    let time: Double      // seconds since start
    let text: String
}

struct SavedNote: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let date: Date
}

/// Records and transcribes a conversation: your microphone ("Me") and,
/// optionally, the computer's sound ("Others", e.g. people on a call).
@MainActor
final class NoteTaker: ObservableObject {
    static let shared = NoteTaker()

    @Published private(set) var isRecording = false
    @Published private(set) var lines: [NoteLine] = []
    @Published private(set) var live: [String: String] = [:]
    @Published private(set) var startedAt: Date?
    @Published var status = ""
    @Published private(set) var lastNoteURL: URL?
    @Published private(set) var saved: [SavedNote] = []

    static var notesDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just Say It Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private let engine = AVAudioEngine()
    private var micPipe: TranscriptPipe?
    private var sysPipe: TranscriptPipe?
    private var sysCapture: SystemAudioCapture?
    private var fileURL: URL?
    private var context = ""
    private(set) var meeting: UpcomingMeeting?

    private init() { refreshSaved() }

    func toggle() {
        if isRecording { Task { await stop() } } else { Task { await start() } }
    }

    // MARK: Start / stop

    /// Starts notes for a calendar meeting (title and attendees go into the note).
    func start(meeting m: UpcomingMeeting) async {
        meeting = m
        await start(keepMeeting: true)
    }

    func start() async { await start(keepMeeting: false) }

    private func start(keepMeeting: Bool) async {
        guard !isRecording else { return }
        if !keepMeeting { meeting = nil }
        let store = Store.shared
        let locale = Locale(identifier: store.prefs.localeID)
        lines = []
        live = [:]
        status = "Starting…"
        let front = Inserter.frontApp()
        context = meeting.map { "\($0.link.platform.rawValue) – \($0.title)" } ?? front.name

        do {
            try await TranscriptPipe.ensureModel(locale: locale)

            // Your microphone.
            let mic = TranscriptPipe()
            wire(mic, speaker: "Me")
            try await mic.start(locale: locale)
            let input = engine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buf, _ in mic.feed(buf) }
            engine.prepare()
            try engine.start()
            micPipe = mic

            // The other side of a call (computer audio). Needs Screen Recording permission.
            if store.prefs.noteCaptureSystemAudio && ContextReader.hasScreenAccess {
                let sys = TranscriptPipe()
                wire(sys, speaker: "Others")
                try await sys.start(locale: locale)
                let cap = SystemAudioCapture()
                cap.onBuffer = { sys.feed($0) }
                do {
                    try await cap.start()
                    sysPipe = sys
                    sysCapture = cap
                } catch {
                    await sys.finish()
                }
            }
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
            await teardown()
            return
        }

        startedAt = Date()
        isRecording = true
        status = sysCapture != nil ? "Recording you and computer audio" : "Recording your microphone"
        createFile()
        NoteWindow.shared.show()
        if store.prefs.playSounds { NSSound(named: "Hero")?.play() }
    }

    func stop() async {
        guard isRecording else { return }
        isRecording = false
        status = "Finishing transcript…"
        await teardown()
        if Store.shared.prefs.playSounds { NSSound(named: "Bottle")?.play() }

        guard !lines.isEmpty else {
            status = "Nothing was heard."
            if let f = fileURL { try? FileManager.default.removeItem(at: f) }
            fileURL = nil
            return
        }
        status = "Writing summary…"
        let summary = await summarize()
        writeFile(summary: summary)
        lastNoteURL = fileURL
        refreshSaved()
        status = "Saved to Documents › Just Say It Notes"
        CollectivIQ.send(title: meeting?.title, transcript: transcriptText(timestamps: false))
    }

    private func teardown() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        await sysCapture?.stop()
        await micPipe?.finish()
        await sysPipe?.finish()
        micPipe = nil
        sysPipe = nil
        sysCapture = nil
        live = [:]
    }

    private func wire(_ pipe: TranscriptPipe, speaker: String) {
        pipe.onFinal = { [weak self] text, t in
            Task { @MainActor in self?.append(speaker: speaker, time: t, text: text) }
        }
        pipe.onVolatile = { [weak self] text in
            Task { @MainActor in self?.live[speaker] = text }
        }
    }

    private func append(speaker: String, time: Double, text: String) {
        // Merge with the previous line when the same person keeps talking.
        if let last = lines.last, last.speaker == speaker, time - last.time < 20, last.text.count < 600 {
            lines[lines.count - 1] = NoteLine(speaker: speaker, time: last.time, text: last.text + " " + text)
        } else {
            lines.append(NoteLine(speaker: speaker, time: time.isFinite ? max(0, time) : 0, text: text))
        }
        writeFile(summary: nil)
    }

    // MARK: Summary (on-device Apple Intelligence)

    private func summarize() async -> String? {
        guard TextBrain.aiAvailable else { return nil }
        var transcript = transcriptText(timestamps: false)
        if let m = meeting { transcript = "Meeting: \(m.title)\nAttendees: \(m.attendees.joined(separator: ", "))\n\n" + transcript }
        if transcript.count > 9000 { transcript = String(transcript.prefix(4500)) + "\n…\n" + String(transcript.suffix(4500)) }
        let ins = """
        You write meeting notes from a transcript. Lines starting with "Me:" are the user; "Others:" is everyone else.
        Write in Markdown with exactly these sections:
        ## Summary
        (3–5 sentences)
        ## Key points
        (bullets)
        ## Decisions
        (bullets, or "None")
        ## Action items
        (bullets as "- [ ] who – what – when", or "None")
        List every task anyone agreed to do as an action item, including tasks for people other than the speaker.
        Use only information from the transcript. Do not invent names, dates or numbers.
        """
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations), instructions: ins)
        return try? await session.respond(to: transcript).content
    }

    // MARK: Files

    private func createFile() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        var title = "Note"
        if let m = meeting {
            let safe = m.title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
            title = String(safe.prefix(60)).trimmingCharacters(in: .whitespaces)
        }
        let name = "\(f.string(from: Date())) \(title).md"
        fileURL = Self.notesDir.appendingPathComponent(name)
        writeFile(summary: nil)
    }

    func transcriptText(timestamps: Bool = true) -> String {
        lines.map { l in
            timestamps ? "**\(stamp(l.time)) \(l.speaker):** \(l.text)" : "\(l.speaker): \(l.text)"
        }.joined(separator: timestamps ? "\n\n" : "\n")
    }

    func stamp(_ t: Double) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func writeFile(summary: String?) {
        guard let url = fileURL else { return }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        let start = startedAt ?? Date()
        let duration = Date().timeIntervalSince(start)
        var md = meeting.map { "# \($0.title)\n\n" } ?? "# Note – \(df.string(from: start))\n\n"
        md += "*Recorded with Just Say It · \(df.string(from: start)) · \(stamp(duration)) · \(context)*\n\n"
        if let m = meeting, !m.attendees.isEmpty { md += "**Attendees:** " + m.attendees.joined(separator: ", ") + "\n\n" }
        if let summary { md += summary.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" }
        md += "## Transcript\n\n" + transcriptText() + "\n"
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    func refreshSaved() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: Self.notesDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        saved = urls.filter { $0.pathExtension == "md" }.map { u in
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SavedNote(url: u, title: u.deletingPathExtension().lastPathComponent, date: d)
        }.sorted { $0.date > $1.date }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText(), forType: .string)
    }
}
