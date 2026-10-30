// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation

enum AppCategory: String, CaseIterable, Codable, Identifiable {
    case email, work, casual, ai, code, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .email: "Email"
        case .work: "Work chat"
        case .casual: "Personal messages"
        case .ai: "AI chats & prompts"
        case .code: "Code editors"
        case .other: "Everything else"
        }
    }
}

enum Tone: String, CaseIterable, Codable, Identifiable {
    case formal, professional, casual, veryCasual, verbatim
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formal: "Formal"
        case .professional: "Professional"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .verbatim: "Exact words (only clean up)"
        }
    }
    var guidance: String {
        switch self {
        case .formal: "Use a formal, polished register with complete sentences and proper capitalization."
        case .professional: "Use a clear, friendly, professional register with complete sentences."
        case .casual: "Use a relaxed conversational register. Contractions are fine. Keep it short."
        case .veryCasual: "Use a very casual chat register: lowercase is fine, minimal punctuation, no trailing period on single sentences."
        case .verbatim: "Keep the speaker's exact wording; only fix punctuation, capitalization, fillers and self-corrections."
        }
    }
}

enum HotkeyChoice: String, CaseIterable, Codable, Identifiable {
    case rightOption, rightCommand, rightControl, fn
    var id: String { rawValue }
    var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: .function
        case .rightOption: .option
        case .rightCommand: .command
        case .rightControl: .control
        }
    }
    var label: String {
        switch self {
        case .fn: "fn / 🌐 Globe"
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        }
    }
}

enum RewriteStyle: String, CaseIterable, Identifiable {
    case formal, casual, concise, enthusiastic, longer, summarize, grammar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .formal: "More formal"
        case .casual: "More casual"
        case .concise: "Shorter & concise"
        case .enthusiastic: "Enthusiastic"
        case .longer: "Make it longer"
        case .summarize: "Summarize"
        case .grammar: "Fix grammar only"
        }
    }
    var instruction: String {
        switch self {
        case .formal: "Rewrite the text in a more formal, polished tone."
        case .casual: "Rewrite the text in a relaxed, casual tone."
        case .concise: "Rewrite the text to be as short and clear as possible while keeping every key point."
        case .enthusiastic: "Rewrite the text with a warm, enthusiastic, upbeat tone."
        case .longer: "Expand the text with more detail and complete sentences, without inventing facts."
        case .summarize: "Summarize the text in one to three sentences."
        case .grammar: "Fix only grammar, spelling and punctuation. Do not change wording otherwise."
        }
    }
}

struct Replacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var heard: String
    var write: String
}

struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: String
    var text: String
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var raw: String
    var final: String
    var app: String
    var seconds: Double
    var words: Int
}

struct Prefs: Codable {
    var hotkey: HotkeyChoice = .rightOption
    var localeID: String = "en_US"
    var aiCleanup = true
    var playSounds = true
    var restoreClipboard = true
    var tones: [AppCategory: Tone] = [
        .email: .professional, .work: .professional, .casual: .casual,
        .ai: .verbatim, .code: .verbatim, .other: .professional,
    ]
    var customInstructions: [AppCategory: String] = [:]
    var vocabulary: [String] = []
    var replacements: [Replacement] = []
    var snippets: [Snippet] = []
    var totalWords = 0
    var totalSeconds = 0.0
    var autoInsert = true
    var showResultCard = true
    var useScreenContext = true
    var noteTakerEnabled = true
    var noteCaptureSystemAudio = true
    var autoJoinEnabled = false
    var autoJoinStartNotes = true
    var autoJoinLeadSeconds = 60
    var autoJoinStopGraceSeconds = 120
    var autoJoinExcludedCalendars: [String] = []
    var checkForUpdates = true
    var skippedVersion: String?
    var startAtLogin = true
    var autoRecordCalls = true
    var recordTeamsCalls = true
    var recordZoomCalls = true
    var recordMeetCalls = true
    var ciqEnabled = false
    var ciqPrompt = ciqStandardPrompt

    init() {}

    // Tolerant decoding so older prefs files keep working when new settings are added.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = Prefs()
        hotkey = (try? c.decode(HotkeyChoice.self, forKey: .hotkey)) ?? def.hotkey
        localeID = (try? c.decode(String.self, forKey: .localeID)) ?? def.localeID
        aiCleanup = (try? c.decode(Bool.self, forKey: .aiCleanup)) ?? def.aiCleanup
        playSounds = (try? c.decode(Bool.self, forKey: .playSounds)) ?? def.playSounds
        restoreClipboard = (try? c.decode(Bool.self, forKey: .restoreClipboard)) ?? def.restoreClipboard
        tones = (try? c.decode([AppCategory: Tone].self, forKey: .tones)) ?? def.tones
        customInstructions = (try? c.decode([AppCategory: String].self, forKey: .customInstructions)) ?? [:]
        vocabulary = (try? c.decode([String].self, forKey: .vocabulary)) ?? []
        replacements = (try? c.decode([Replacement].self, forKey: .replacements)) ?? []
        snippets = (try? c.decode([Snippet].self, forKey: .snippets)) ?? []
        totalWords = (try? c.decode(Int.self, forKey: .totalWords)) ?? 0
        totalSeconds = (try? c.decode(Double.self, forKey: .totalSeconds)) ?? 0
        autoInsert = (try? c.decode(Bool.self, forKey: .autoInsert)) ?? def.autoInsert
        showResultCard = (try? c.decode(Bool.self, forKey: .showResultCard)) ?? def.showResultCard
        useScreenContext = (try? c.decode(Bool.self, forKey: .useScreenContext)) ?? def.useScreenContext
        noteTakerEnabled = (try? c.decode(Bool.self, forKey: .noteTakerEnabled)) ?? def.noteTakerEnabled
        noteCaptureSystemAudio = (try? c.decode(Bool.self, forKey: .noteCaptureSystemAudio)) ?? def.noteCaptureSystemAudio
        autoJoinEnabled = (try? c.decode(Bool.self, forKey: .autoJoinEnabled)) ?? def.autoJoinEnabled
        autoJoinStartNotes = (try? c.decode(Bool.self, forKey: .autoJoinStartNotes)) ?? def.autoJoinStartNotes
        autoJoinLeadSeconds = (try? c.decode(Int.self, forKey: .autoJoinLeadSeconds)) ?? def.autoJoinLeadSeconds
        autoJoinStopGraceSeconds = (try? c.decode(Int.self, forKey: .autoJoinStopGraceSeconds)) ?? def.autoJoinStopGraceSeconds
        autoJoinExcludedCalendars = (try? c.decode([String].self, forKey: .autoJoinExcludedCalendars)) ?? []
        checkForUpdates = (try? c.decode(Bool.self, forKey: .checkForUpdates)) ?? def.checkForUpdates
        skippedVersion = try? c.decode(String.self, forKey: .skippedVersion)
        startAtLogin = (try? c.decode(Bool.self, forKey: .startAtLogin)) ?? def.startAtLogin
        autoRecordCalls = (try? c.decode(Bool.self, forKey: .autoRecordCalls)) ?? def.autoRecordCalls
        recordTeamsCalls = (try? c.decode(Bool.self, forKey: .recordTeamsCalls)) ?? def.recordTeamsCalls
        recordZoomCalls = (try? c.decode(Bool.self, forKey: .recordZoomCalls)) ?? def.recordZoomCalls
        recordMeetCalls = (try? c.decode(Bool.self, forKey: .recordMeetCalls)) ?? def.recordMeetCalls
        ciqEnabled = (try? c.decode(Bool.self, forKey: .ciqEnabled)) ?? def.ciqEnabled
        ciqPrompt = (try? c.decode(String.self, forKey: .ciqPrompt)) ?? def.ciqPrompt
        // Upgrade people still on the old short default to the standard meeting prompt.
        let trimmed = ciqPrompt.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if trimmed.isEmpty || trimmed == ciqOldDefaultPrompt.trimmingCharacters(in: CharacterSet(charactersIn: ".")) { ciqPrompt = ciqStandardPrompt }
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var prefs: Prefs { didSet { save() } }
    @Published var history: [HistoryItem] { didSet { saveHistory() } }

    private let dir: URL
    private var prefsURL: URL { dir.appendingPathComponent("prefs.json") }
    private var historyURL: URL { dir.appendingPathComponent("history.json") }

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JustSayIt", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        prefs = (try? dec.decode(Prefs.self, from: Data(contentsOf: dir.appendingPathComponent("prefs.json")))) ?? Prefs()
        history = (try? dec.decode([HistoryItem].self, from: Data(contentsOf: dir.appendingPathComponent("history.json")))) ?? []
        save() // write back any upgraded settings (e.g. the new CollectivIQ prompt)
    }

    func tone(for c: AppCategory) -> Tone { prefs.tones[c] ?? .professional }

    func record(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        prefs.totalWords += item.words
        prefs.totalSeconds += item.seconds
    }

    private func save() {
        if let d = try? JSONEncoder().encode(prefs) { try? d.write(to: prefsURL, options: .atomic) }
    }

    private func saveHistory() {
        if let d = try? JSONEncoder().encode(history) { try? d.write(to: historyURL, options: .atomic) }
    }
}

/// Placed before every note or transcript sent to CollectivIQ.
let ciqStandardPrompt = """
Instructions:

Analyze the provided meeting transcript/recording/notes in full detail and produce a professional, structured summary using the exact format below. Preserve chronological flow (beginning → middle → end) and use direct quotes where impactful. Use bullet points throughout. Do not omit minor details — capture the full arc of the conversation.

1. Meeting Metadata
Date:
Time (start–end):
Duration:
Location / Platform (in-person, Zoom, Teams, etc.):
Meeting Purpose / Objective:

2. Participants
Attendees (full list, with roles/titles if known):
Who called/organized the meeting:
Who joined late or left early (if noted):
Absent/expected-but-missing participants:

3. Opening — How the Meeting Started
Context or agenda set at the outset
Any recap of previous meeting/action items referenced early on
Initial tone/framing of the discussion

4. Chronological Flow of Discussion (Beginning → Middle → End)
Bullet-by-bullet walkthrough of how topics progressed
Note transitions between subjects
Flag any tense moments, disagreements, or pivots in direction

5. Key Discussion Points
Bullet list of each major topic raised
Who raised each point
Supporting context/data mentioned

6. Decisions Made
Bullet list of every concrete decision
Who made/approved the decision
Rationale given (if any)

7. Open Questions / Unresolved Items
Bullet list of questions raised but not answered
Who owns finding the answer (if assigned)

8. Risks Identified
Bullet list of risks discussed
Severity/impact if mentioned
Who flagged the risk

9. Blockers
Bullet list of current blockers
What/who is causing the blocker
Dependencies involved

10. Solutions Proposed
Bullet list of solutions/ideas brought to the table
Who proposed each
Whether it was accepted, rejected, or left pending

11. Issues Resolved During the Meeting
Bullet list of problems that were actually solved/closed out in real time

12. Timelines & Deadlines
Bullet list of all dates, milestones, or deadlines mentioned
Owner responsible for each

13. Next Steps / Action Items
Bullet list format: Action → Owner → Due Date

14. Key Quotes
Pull 3–6 of the most important or revealing direct quotes
Attribute each to the speaker
Note why the quote matters (decision-defining, risk-flagging, conflict, resolution, etc.)

15. Closing — How the Meeting Ended
Final summary/recap given (if any)
Any last-minute decisions or action items added at the end
Sentiment/tone at close (agreement, unresolved tension, enthusiasm, etc.)

16. Overall Meeting Assessment
Was the stated purpose achieved?
What progress was made vs. what remains outstanding?
Any recommendations for the next meeting's agenda?

Formatting rules:
Use nested bullet points, not paragraphs
Bold key terms (decisions, owners, dates)
Keep quotes exact and short, with speaker attribution
Flag anything ambiguous as "unclear/unconfirmed" rather than guessing
Paste your transcript or notes right after this prompt whenever you're ready, and I'll run the full breakdown for you IN PLAIN TEXT
- HERE IS THE INFORMATION :
"""

let ciqOldDefaultPrompt = "Summarize this meeting: key points, decisions, action items with owners and dates, and open questions."
