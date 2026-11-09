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
    /// True while the microphone and speech model are being set up (before isRecording).
    @Published private(set) var isStarting = false
    /// Number of finished recordings still writing their smart transcript / summary.
    @Published private(set) var finishing = 0
    /// Recording, starting, or still saving a finished one.
    var isBusy: Bool { isRecording || isStarting || finishing > 0 }
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
    /// Transcript rewritten for clarity (filled in when a recording stops).
    private(set) var smartTranscript: String?

    /// What started the current recording.
    enum Origin { case manual, calendar, call }
    private(set) var origin: Origin = .manual

    private init() { refreshSaved() }

    func toggle() {
        if isRecording { endByUser() } else { Task { await start() } }
    }

    /// The "End Note Taker" button: the only manual way to finish a call recording.
    func endByUser() {
        if origin == .call { CallWatcher.shared.endByUser() } else { Task { await stop(sendImmediately: true) } }
    }

    // MARK: Start / stop

    /// Starts notes for a calendar meeting (title and attendees go into the note).
    @discardableResult
    func start(meeting m: UpcomingMeeting, origin o: Origin = .calendar) async -> Bool {
        guard !isRecording, !isStarting else { return false }
        meeting = m
        origin = o
        return await start(keepMeeting: true)
    }

    @discardableResult
    func start() async -> Bool {
        guard !isRecording, !isStarting else { return false }
        origin = .manual
        return await start(keepMeeting: false)
    }

    private func start(keepMeeting: Bool) async -> Bool {
        guard !isRecording, !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
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
            // A failure here never stops the recording of your microphone.
            if store.prefs.noteCaptureSystemAudio && ContextReader.hasScreenAccess {
                let sys = TranscriptPipe()
                wire(sys, speaker: "Others")
                do {
                    try await sys.start(locale: locale)
                    let cap = SystemAudioCapture()
                    cap.onBuffer = { sys.feed($0) }
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
            return false
        }

        startedAt = Date()
        isRecording = true
        status = sysCapture != nil ? "Recording you and computer audio" : "Recording your microphone"
        createFile()
        NoteWindow.shared.show()
        Controller.shared.overlay.show(.noteTaker)
        if store.prefs.playSounds { NSSound(named: "Hero")?.play() }
        return true
    }

    /// Finishes the recording. With `sendImmediately` (call ended / End Note Taker) the notes go to
    /// CollectivIQ straight away using the saved defaults, without any questions.
    func stop(sendImmediately: Bool = false) async {
        guard isRecording else { return }
        isRecording = false
        finishing += 1
        defer { finishing -= 1 }
        status = "Finishing transcript…"
        Controller.shared.overlay.show(.hidden)
        await teardown()
        if Store.shared.prefs.playSounds { NSSound(named: "Bottle")?.play() }

        // From here on work on a copy, so a new recording that starts meanwhile can't mix with this one.
        var note = snapshot()
        note.endedAt = Date()
        fileURL = nil
        guard !note.lines.isEmpty else {
            status = "Nothing was heard."
            if let f = note.fileURL {
                let base = f.deletingPathExtension().path
                for path in [f.path, base + " - Raw.txt", base + " - Smart.txt"] { try? FileManager.default.removeItem(atPath: path) }
            }
            return
        }
        Self.write(note, summary: nil)
        setStatus("Writing the smart transcript…")
        note.smart = await TextBrain.smartTranscript(note.plainText)
        smartTranscript = note.smart
        Self.write(note, summary: nil)
        setStatus("Writing summary…")
        let summary = await summarize(note)
        Self.write(note, summary: summary)
        lastNoteURL = note.fileURL
        refreshSaved()
        setStatus("Saved to Documents › Just Say It Notes")
        CollectivIQ.deliver(title: note.meeting?.title,
                            raw: note.plainText,
                            smart: note.smart,
                            automatic: sendImmediately && Store.shared.prefs.ciqAutoSend)
    }

    /// Status of a finishing recording; never overwrites the status of a new one that's running.
    private func setStatus(_ s: String) {
        if !isRecording && !isStarting { status = s }
    }

    /// Everything that goes into a note file.
    struct NoteSnapshot {
        var lines: [NoteLine]
        var meeting: UpcomingMeeting?
        var fileURL: URL?
        var startedAt: Date
        var endedAt: Date?
        var context: String
        var smart: String?

        var plainText: String { lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n") }
        var rawTranscript: String { lines.map { "[\(NoteTaker.stampText($0.time))] \($0.speaker): \($0.text)" }.joined(separator: "\n") }
    }

    private func snapshot() -> NoteSnapshot {
        NoteSnapshot(lines: lines, meeting: meeting, fileURL: fileURL, startedAt: startedAt ?? Date(), endedAt: nil,
                     context: context, smart: smartTranscript)
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

    private func summarize(_ note: NoteSnapshot) async -> String? {
        guard TextBrain.aiAvailable else { return nil }
        let base = note.smart ?? note.plainText
        var header = ""
        if let m = note.meeting { header = "Meeting: \(m.title)\nAttendees: \(m.attendees.joined(separator: ", "))\n\n" }
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
        func ask(_ text: String) async -> String? {
            let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations), instructions: ins)
            return try? await session.respond(to: header + text).content
        }
        if base.count <= 7000 { return await ask(base) }
        // Long call: note each part, then combine, so nothing in the middle is lost.
        var partials: [String] = []
        for part in TextBrain.transcriptChunks(base, limit: 6000) {
            if let n = await ask(part) { partials.append(n) }
        }
        guard !partials.isEmpty else { return nil }
        if partials.count == 1 { return partials[0] }
        let combine = """
        Combine these partial notes from consecutive parts of one meeting into a single set of notes with exactly these sections: ## Summary, ## Key points, ## Decisions, ## Action items. Merge duplicates, keep every distinct decision and action item, and keep them in the order they happened. Do not invent anything.
        """
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations), instructions: combine)
        return (try? await session.respond(to: partials.joined(separator: "\n\n---\n\n")).content) ?? partials.joined(separator: "\n\n")
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
        // Never overwrite an earlier note (two calls with the same name in the same minute).
        var base = "\(f.string(from: Date())) \(title)"
        var n = 2
        while FileManager.default.fileExists(atPath: Self.notesDir.appendingPathComponent(base + ".txt").path) {
            base = "\(f.string(from: Date())) \(title) (\(n))"
            n += 1
        }
        fileURL = Self.notesDir.appendingPathComponent(base + ".txt")
        smartTranscript = nil
        writeFile(summary: nil)
    }

    func transcriptText(timestamps: Bool = true) -> String {
        lines.map { l in
            timestamps ? "**\(stamp(l.time)) \(l.speaker):** \(l.text)" : "\(l.speaker): \(l.text)"
        }.joined(separator: timestamps ? "\n\n" : "\n")
    }

    func stamp(_ t: Double) -> String { Self.stampText(t) }

    nonisolated static func stampText(_ t: Double) -> String {
        let s = Int(t.isFinite ? max(0, t) : 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Plain-text note: header, summary, smart transcript and raw transcript.
    /// Also writes "<name> - Raw.txt" and "<name> - Smart.txt" next to it.
    private func writeFile(summary: String?) {
        guard isRecording || isStarting else { return }
        Self.write(snapshot(), summary: summary)
    }

    private static func write(_ note: NoteSnapshot, summary: String?) {
        guard let url = note.fileURL else { return }
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        let start = note.startedAt
        let duration = (note.endedAt ?? Date()).timeIntervalSince(start)
        let rule = String(repeating: "=", count: 60)
        var header = (note.meeting?.title ?? "Note – \(df.string(from: start))") + "\n"
        header += "Recorded with Just Say It · \(df.string(from: start)) · \(stampText(duration)) · \(note.context)\n"
        if let m = note.meeting, !m.attendees.isEmpty { header += "Attendees: " + m.attendees.joined(separator: ", ") + "\n" }
        let raw = note.rawTranscript

        var txt = header + "\n"
        if let summary { txt += "\(rule)\nSUMMARY\n\(rule)\n" + Self.plain(summary) + "\n\n" }
        if let smart = note.smart { txt += "\(rule)\nSMART TRANSCRIPT (words and logic fixed)\n\(rule)\n" + smart + "\n\n" }
        txt += "\(rule)\nRAW TRANSCRIPT (exactly as heard)\n\(rule)\n" + raw + "\n"
        try? txt.write(to: url, atomically: true, encoding: .utf8)

        let base = url.deletingPathExtension().path
        try? (header + "\nRAW TRANSCRIPT (exactly as heard)\n\n" + raw + "\n")
            .write(toFile: base + " - Raw.txt", atomically: true, encoding: .utf8)
        if let smart = note.smart {
            try? (header + "\nSMART TRANSCRIPT (words and logic fixed)\n\n" + smart + "\n")
                .write(toFile: base + " - Smart.txt", atomically: true, encoding: .utf8)
        }
    }

    /// Timestamped transcript exactly as recognised.
    func rawTranscript() -> String {
        lines.map { "[\(stamp($0.time))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    /// Removes Markdown symbols for the plain-text file.
    nonisolated static func plain(_ md: String) -> String {
        md.components(separatedBy: "\n").map { line -> String in
            var l = line.replacingOccurrences(of: "**", with: "")
            if l.hasPrefix("## ") { l = String(l.dropFirst(3)).uppercased() }
            if l.hasPrefix("- [ ] ") { l = "• " + l.dropFirst(6) }
            else if l.hasPrefix("- ") { l = "• " + l.dropFirst(2) }
            return l
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refreshSaved() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: Self.notesDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        saved = urls.filter {
            ($0.pathExtension == "txt" || $0.pathExtension == "md")
                && !$0.lastPathComponent.hasSuffix(" - Raw.txt") && !$0.lastPathComponent.hasSuffix(" - Smart.txt")
        }.map { u in
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return SavedNote(url: u, title: u.deletingPathExtension().lastPathComponent, date: d)
        }.sorted { $0.date > $1.date }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText(), forType: .string)
    }
}
