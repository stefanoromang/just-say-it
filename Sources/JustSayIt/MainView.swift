import AppKit
import Speech
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case home = "Home", collectiviq = "CollectivIQ", meetings = "Meetings", notes = "Note Taker", style = "Tone & Style", dictionary = "Dictionary", snippets = "Snippets", rewrite = "AI Rewrite", history = "History", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .notes: "note.text"
        case .meetings: "video"
        case .collectiviq: "bubble.left.and.text.bubble.right"
        case .style: "theatermasks"
        case .dictionary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .rewrite: "wand.and.stars"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store
    @StateObject private var ui = UIState()

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $ui.pane) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                Group {
                    switch ui.pane {
                    case .home: HomePane(c: c, store: store)
                    case .notes: NotesPane(store: store)
                    case .meetings: MeetingsPane(store: store)
                    case .collectiviq: CollectivIQPane(store: store)
                    case .style: StylePane(store: store)
                    case .dictionary: DictionaryPane(store: store)
                    case .snippets: SnippetsPane(store: store)
                    case .rewrite: RewritePane(c: c)
                    case .history: HistoryPane(store: store)
                    case .settings: SettingsPane(c: c, store: store)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(ui.pane.rawValue)
        }
        .onAppear { c.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: .openPane)) { note in
            if let raw = note.object as? String, let p = Pane(rawValue: raw) { ui.pane = p }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in c.refreshPermissions() }
    }
}

// MARK: Home

struct HomePane: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store

    var wpm: Int {
        guard store.prefs.totalSeconds > 5 else { return 0 }
        return Int(Double(store.prefs.totalWords) / (store.prefs.totalSeconds / 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Just Say It").font(.largeTitle.bold())
            Text("Free, unlimited, private voice typing. Everything runs on your Mac.")
                .foregroundStyle(.secondary)
            Text("Created by Stefano Roman Gunness").font(.caption).foregroundStyle(.tertiary)

            GroupBox("Setup") {
                VStack(alignment: .leading, spacing: 10) {
                    PermRow(ok: c.micGranted, title: "Microphone", detail: "To hear you") { c.requestMic() }
                    PermRow(ok: c.axGranted, title: "Accessibility", detail: "To type into other apps and use the hotkey") {
                        Inserter.requestAccessibility()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    PermRow(ok: c.screenGranted, title: "Screen Recording (optional, for context)",
                            detail: "Reads the visible email/chat so names and replies are right. Stays on your Mac.") {
                        ContextReader.requestScreenAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                    PermRow(ok: c.modelReady, title: "Speech model", detail: c.modelStatus) { Task { await c.prepareModel() } }
                    PermRow(ok: TextBrain.aiAvailable, title: "Apple Intelligence (smart cleanup, Scribe, Rewrite)",
                            detail: TextBrain.aiAvailable ? "On-device model available" : "Turn on in System Settings › Apple Intelligence") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }
                }
                .padding(6)
            }

            GroupBox("How to use") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Hold **\(store.prefs.hotkey.label)**, speak, release. Text appears where your cursor is.", systemImage: "mic")
                    Label("**Double-tap** it for hands-free. Tap once more to finish. **Esc** cancels.", systemImage: "hand.raised.slash")
                    Label("Hold **⇧ Shift + \(store.prefs.hotkey.label)** for **Scribe**: say what you want, get a polished message.", systemImage: "wand.and.stars")
                    Label("Say **\"scratch that\"** to drop the last sentence, **\"new line\"** / **\"new paragraph\"** for layout.", systemImage: "arrow.uturn.backward")
                    Label("Select text and press **⌃⌥R** to make it concise (more styles in the menu bar).", systemImage: "text.redaction")
                    Label("Press **Right ⇧ Shift three times** to start the **Note Taker**; press it three times again to stop.", systemImage: "note.text")
                }
                .padding(6)
            }

            HStack(spacing: 16) {
                Stat(value: "\(store.prefs.totalWords)", label: "words dictated")
                Stat(value: wpm > 0 ? "\(wpm)" : "–", label: "words per minute")
                Stat(value: "\(Int(Double(store.prefs.totalWords) / 40.0)) min", label: "saved vs. typing")
            }

            if !c.lastResult.isEmpty {
                GroupBox("Last dictation") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !c.lastContext.isEmpty {
                            Label(c.lastContext, systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(c.lastResult).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(c.lastResult, forType: .string)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
        }
    }
}

struct PermRow: View {
    let ok: Bool
    let title: String
    let detail: String
    let fix: () -> Void
    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok { Button("Fix", action: fix) }
        }
    }
}

struct Stat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
    }
}

// MARK: Tone & Style

struct StylePane: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Just Say It detects the app you're typing in and adjusts the tone automatically.")
                .foregroundStyle(.secondary)
            ForEach(AppCategory.allCases) { cat in
                GroupBox(cat.label) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Tone", selection: Binding(
                            get: { store.tone(for: cat) },
                            set: { store.prefs.tones[cat] = $0 })) {
                            ForEach(Tone.allCases) { Text($0.label).tag($0) }
                        }
                        TextField("Personal style, e.g. \"Sign emails with – Stefano\" or \"Never use emojis\"",
                                  text: Binding(get: { store.prefs.customInstructions[cat] ?? "" },
                                                set: { store.prefs.customInstructions[cat] = $0 }))
                    }
                    .padding(6)
                }
            }
        }
    }
}

// MARK: Dictionary

struct DictionaryPane: View {
    @ObservedObject var store: Store
    @StateObject private var f = UIState()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("My words") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Names, brands, acronyms and jargon. They're fed to the speech engine and always spelled exactly like this.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. Kubernetes, metoprolol, OpenCode", text: $f.word).onSubmit(addWord)
                        Button("Add", action: addWord)
                    }
                    FlowList(items: store.prefs.vocabulary) { w in store.prefs.vocabulary.removeAll { $0 == w } }
                }
                .padding(6)
            }
            GroupBox("Auto-replace") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fix words that are always misheard.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("When I say…", text: $f.heard)
                        Image(systemName: "arrow.right")
                        TextField("Write…", text: $f.write).onSubmit(addRep)
                        Button("Add", action: addRep)
                    }
                    ForEach(store.prefs.replacements) { r in
                        HStack {
                            Text(r.heard)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(r.write).bold()
                            Spacer()
                            Button(role: .destructive) { store.prefs.replacements.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    func addWord() {
        let w = f.word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !store.prefs.vocabulary.contains(w) else { return }
        store.prefs.vocabulary.append(w)
        f.word = ""
    }

    func addRep() {
        let h = f.heard.trimmingCharacters(in: .whitespaces), w = f.write.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !w.isEmpty else { return }
        store.prefs.replacements.append(Replacement(heard: h, write: w))
        f.heard = ""; f.write = ""
    }
}

struct FlowList: View {
    let items: [String]
    let remove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { w in
                HStack(spacing: 4) {
                    Text(w).lineLimit(1)
                    Button { remove(w) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
        }
    }
}

// MARK: Snippets

struct SnippetsPane: View {
    @ObservedObject var store: Store
    @StateObject private var f = UIState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say the trigger on its own (or \"insert <trigger>\" mid-sentence) to paste the full text.")
                .foregroundStyle(.secondary)
            GroupBox("New snippet") {
                VStack(alignment: .leading) {
                    TextField("Trigger phrase, e.g. \"my address\"", text: $f.trigger)
                    TextEditor(text: $f.text).frame(height: 80).font(.body)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    Button("Add snippet") {
                        let t = f.trigger.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !f.text.isEmpty else { return }
                        store.prefs.snippets.append(Snippet(trigger: t, text: f.text))
                        f.trigger = ""; f.text = ""
                    }
                }
                .padding(6)
            }
            ForEach(store.prefs.snippets) { s in
                GroupBox {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text("“\(s.trigger)”").bold()
                            Text(s.text).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                        }
                        Spacer()
                        Button(role: .destructive) { store.prefs.snippets.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .padding(4)
                }
            }
        }
    }
}

// MARK: Rewrite

struct RewritePane: View {
    @ObservedObject var c: Controller
    @StateObject private var f = UIState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select text in any app and press ⌃⌥R, or use the menu bar › Rewrite. You can also paste text here.")
                .foregroundStyle(.secondary)
            TextEditor(text: $f.input).frame(height: 120).font(.body)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                ForEach(RewriteStyle.allCases) { s in
                    Button(s.label) {
                        let src = f.input.isEmpty ? c.lastResult : f.input
                        guard !src.isEmpty else { return }
                        f.busy = true
                        Task {
                            f.output = await TextBrain.rewrite(src, style: s) ?? "Rewrite unavailable. Turn on Apple Intelligence."
                            f.busy = false
                        }
                    }
                }
                if f.busy { ProgressView().controlSize(.small) }
            }
            .disabled(f.busy)
            if !f.output.isEmpty {
                GroupBox {
                    VStack(alignment: .leading) {
                        Text(f.output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(f.output, forType: .string)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }
}

// MARK: History

struct HistoryPane: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(store.history.count) recent dictations (stored only on this Mac)").foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { store.history.removeAll() }
            }
            ForEach(store.history) { h in
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(h.app).font(.caption.bold())
                            Text(h.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(h.final, forType: .string)
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(h.final).textSelection(.enabled)
                        if h.raw != h.final {
                            Text("Heard: " + h.raw).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
        }
    }
}

// MARK: Settings

struct SettingsPane: View {
    @ObservedObject var c: Controller
    @ObservedObject var store: Store
    @StateObject private var f = UIState()

    var body: some View {
        Form {
            Picker("Dictation hotkey", selection: Binding(get: { store.prefs.hotkey }, set: { c.setHotkey($0) })) {
                ForEach(HotkeyChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker("Language", selection: Binding(get: { store.prefs.localeID }, set: { v in
                store.prefs.localeID = v
                Task { await c.prepareModel() }
            })) {
                ForEach(f.locales, id: \.identifier) { l in
                    Text(Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier).tag(l.identifier)
                }
            }
            Toggle("Smart AI cleanup (fillers, self-corrections, lists, tone)", isOn: $store.prefs.aiCleanup)
            Toggle("Insert automatically into the selected text box", isOn: $store.prefs.autoInsert)
            Toggle("Always show the result card (to edit, copy or rewrite)", isOn: $store.prefs.showResultCard)
            Toggle("Use what's on screen as context (needs Screen Recording)", isOn: $store.prefs.useScreenContext)
            Toggle("Note Taker: Right ⇧ Shift × 3 starts/stops it", isOn: $store.prefs.noteTakerEnabled)
            Toggle("Note Taker: also record computer audio (the other people on a call)", isOn: $store.prefs.noteCaptureSystemAudio)
            Toggle("Start Just Say It when I log in to my Mac", isOn: Binding(
                get: { store.prefs.startAtLogin },
                set: { store.prefs.startAtLogin = $0; LoginItem.set($0) }))
            Toggle("Play start/stop sounds", isOn: $store.prefs.playSounds)
            Toggle("Restore my clipboard after inserting", isOn: $store.prefs.restoreClipboard)
            Text(c.modelStatus).font(.caption).foregroundStyle(.secondary)
            UpdatesSection(store: store)
        }
        .formStyle(.grouped)
        .task {
            let all = await DictationTranscriber.supportedLocales
            f.locales = all.sorted { ($0.identifier) < ($1.identifier) }
        }
    }
}

extension Notification.Name {
    static let openPane = Notification.Name("JustSayIt.openPane")
}

@MainActor
final class UIState: ObservableObject {
    @Published var pane: Pane = .home
    @Published var word = ""
    @Published var heard = ""
    @Published var write = ""
    @Published var trigger = ""
    @Published var text = ""
    @Published var input = ""
    @Published var output = ""
    @Published var busy = false
    @Published var locales: [Locale] = []
}

// MARK: Note Taker

struct NotesPane: View {
    @ObservedObject var store: Store
    @ObservedObject var n = NoteTaker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Press **Right ⇧ Shift three times** to start recording a conversation, and three times again to stop. You get a live transcript, then a summary with key points, decisions and action items.")
                .foregroundStyle(.secondary)
            HStack {
                Button { n.toggle() } label: {
                    Label(n.isRecording ? "Stop Note Taker" : "Start Note Taker", systemImage: n.isRecording ? "stop.fill" : "record.circle")
                }
                .buttonStyle(.borderedProminent).tint(n.isRecording ? .red : .purple)
                Button("Show live window") { NoteWindow.shared.show() }
                Button("Open notes folder") { NSWorkspace.shared.open(NoteTaker.notesDir) }
            }
            GroupBox("What gets recorded") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("**Me:** your microphone", systemImage: "mic")
                    Label(store.prefs.noteCaptureSystemAudio
                          ? (ContextReader.hasScreenAccess ? "**Others:** computer audio (Zoom, Meet, Teams…)" : "**Others:** needs Screen Recording permission (Home › Fix)")
                          : "**Others:** off (turn on in Settings)", systemImage: "speaker.wave.2")
                    Text("Everything is transcribed on this Mac. Notes are saved as Markdown in Documents › Just Say It Notes. Always tell people when you're recording them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            Label("Send recordings to CollectivIQ: see **CollectivIQ** in the sidebar.", systemImage: "bubble.left.and.text.bubble.right")
                .font(.caption).foregroundStyle(.secondary)
            Text("Saved notes").font(.headline)
            if n.saved.isEmpty {
                Text("No notes yet.").foregroundStyle(.secondary)
            }
            ForEach(n.saved) { note in
                HStack {
                    Image(systemName: "doc.text")
                    Text(note.title)
                    Spacer()
                    Text(note.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                    Button("Open") { NSWorkspace.shared.open(note.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                }
            }
        }
        .onAppear { n.refreshSaved() }
    }
}

// MARK: Meetings (calendar auto-join)

struct MeetingsPane: View {
    @ObservedObject var store: Store
    @ObservedObject var aj = AutoJoin.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Just Say It reads your Google and Microsoft calendars, joins your **Zoom, Google Meet and Microsoft Teams** calls on time, and takes notes automatically.")
                .foregroundStyle(.secondary)

            GroupBox("1. Connect your calendars") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: aj.hasAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(aj.hasAccess ? .green : .orange)
                        Text(aj.hasAccess ? "Calendar access granted" : "Allow Just Say It to read your calendars")
                        Spacer()
                        if !aj.hasAccess { Button("Allow access") { aj.requestAccess() } }
                    }
                    Text("Add your **Google** and **Microsoft (Outlook/Exchange/Office 365)** accounts in **System Settings › Internet Accounts** and turn on Calendars. They then appear below.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Internet Accounts") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                    }
                    if aj.hasAccess {
                        Divider()
                        Text("Calendars to watch").font(.caption.bold())
                        ForEach(aj.calendars, id: \.calendarIdentifier) { c in
                            Toggle(isOn: Binding(get: { aj.isCalendarIncluded(c) }, set: { aj.setCalendar(c, included: $0) })) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(cgColor: c.cgColor)).frame(width: 8, height: 8)
                                    Text(c.title)
                                    Text(c.source.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("Record every live call automatically") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("When a Teams, Zoom or Google Meet call starts, record and transcribe it", isOn: $store.prefs.autoRecordCalls)
                    HStack(spacing: 18) {
                        Toggle("Microsoft Teams", isOn: $store.prefs.recordTeamsCalls)
                        Toggle("Zoom", isOn: $store.prefs.recordZoomCalls)
                        Toggle("Google Meet", isOn: $store.prefs.recordMeetCalls)
                    }
                    .disabled(!store.prefs.autoRecordCalls)
                    Text("Works for calls you join, answer or start, in the Teams and Zoom apps or in Chrome, Edge, Safari, Brave or Arc. Recording starts a few seconds after the call uses your microphone and stops when the call ends; the transcript is saved (and sent to CollectivIQ if that's on). To record the other people too, allow **Screen Recording** on the Home page.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let c = CallWatcher.shared.activeCall {
                        Label("Recording: \(c.title) (\(c.platform.rawValue))", systemImage: "record.circle").foregroundStyle(.red)
                    } else if !CallWatcher.shared.status.isEmpty {
                        Text(CallWatcher.shared.status).font(.caption).foregroundStyle(.purple)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("2. Automatic joining") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Join my calendar calls automatically", isOn: $store.prefs.autoJoinEnabled)
                    Toggle("Start the Note Taker for each call (stops when the meeting ends)", isOn: $store.prefs.autoJoinStartNotes)
                    Picker("Join", selection: $store.prefs.autoJoinLeadSeconds) {
                        Text("At start time").tag(0)
                        Text("1 minute early").tag(60)
                        Text("2 minutes early").tag(120)
                        Text("5 minutes early").tag(300)
                    }
                    .frame(maxWidth: 320)
                    Text("Zoom opens directly in the Zoom app. Google Meet and Teams open their join screen in your browser or Teams app; the first time, sign in and choose “remember” so later calls connect straight away. Only calls you haven't declined are joined.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !aj.lastAction.isEmpty { Text(aj.lastAction).font(.caption).foregroundStyle(.purple) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            HStack {
                Text("Upcoming calls").font(.headline)
                Spacer()
                Button("Refresh") { aj.refresh() }
            }
            if aj.upcoming.isEmpty {
                Text(aj.hasAccess ? "No Zoom, Meet or Teams calls in the next 36 hours." : "Connect your calendars to see your calls.")
                    .foregroundStyle(.secondary)
            }
            ForEach(aj.upcoming) { m in
                HStack(alignment: .top) {
                    Image(systemName: m.link.platform == .zoom ? "video.fill" : (m.link.platform == .meet ? "person.2.wave.2.fill" : "person.3.fill"))
                        .foregroundStyle(.purple).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).bold()
                        Text("\(m.start.formatted(date: .abbreviated, time: .shortened)) – \(m.end.formatted(date: .omitted, time: .shortened)) · \(m.link.platform.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(m.calendar).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if aj.current?.id == m.id {
                        Text("In call").font(.caption.bold()).foregroundStyle(.red)
                    }
                    Button("Join now") { aj.join(m, automatic: false) }
                }
            }
        }
        .onAppear { aj.refresh() }
    }
}

// MARK: Updates

struct UpdatesSection: View {
    @ObservedObject var store: Store
    @ObservedObject var u = Updater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $store.prefs.checkForUpdates)
            HStack {
                Text("Version \(u.current)")
                Spacer()
                if u.installing { ProgressView().controlSize(.small) }
                if u.updateAvailable, let v = u.latest {
                    Button("Install \(v)") { u.install() }.buttonStyle(.borderedProminent).tint(.purple).disabled(u.installing)
                } else {
                    Button("Check now") { Task { await u.check(userInitiated: true) } }.disabled(u.installing)
                }
            }
            if !u.status.isEmpty { Text(u.status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

// MARK: CollectivIQ

struct CollectivIQPane: View {
    @ObservedObject var store: Store
    @ObservedObject var n = NoteTaker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect Just Say It to **CollectivIQ**. After every Note Taker recording, the transcript is sent to a new CollectivIQ chat **inside Just Say It**, with no browser needed.")
                .foregroundStyle(.secondary)

            GroupBox("1. Sign in to CollectivIQ") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Opens CollectivIQ in a Just Say It window. Sign in once with your own email and password and tick **Remember me**. The window keeps you signed in.")
                        .font(.callout)
                    Button {
                        CollectivIQ.showWindow(signIn: true)
                    } label: { Label("Sign in to CollectivIQ", systemImage: "person.crop.circle.badge.checkmark") }
                    .buttonStyle(.borderedProminent).tint(.purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("2. Turn it on") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("After each Note Taker recording, send my prompt + the transcript to CollectivIQ", isOn: $store.prefs.ciqEnabled)
                    Text(store.prefs.ciqEnabled ? "✓ On: when a recording stops, a new CollectivIQ chat is sent automatically." : "Off: recordings are only saved on this Mac.")
                        .font(.caption).foregroundStyle(store.prefs.ciqEnabled ? .green : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("3. Your prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Placed before every note or transcript sent to CollectivIQ. Change it to anything you like.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $store.prefs.ciqPrompt)
                        .font(.callout).frame(height: 260)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    Button("Reset to the standard meeting prompt") { store.prefs.ciqPrompt = CollectivIQ.defaultPrompt }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            GroupBox("How it works") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Press **Right ⇧ three times** to start the Note Taker, and three times again to stop.", systemImage: "1.circle")
                    Label("The note is saved in Documents › Just Say It Notes.", systemImage: "2.circle")
                    Label("The CollectivIQ window opens a new chat, pastes your prompt + the transcript and presses Send.", systemImage: "3.circle")
                    Label("If you aren't signed in yet, sign in in that window, and the transcript is sent right after.", systemImage: "4.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }

            HStack {
                Button("Open CollectivIQ") { CollectivIQ.showWindow() }
                if let u = n.lastNoteURL ?? n.saved.first?.url, let text = try? String(contentsOf: u, encoding: .utf8) {
                    Button("Send my last note now") {
                        CollectivIQ.send(title: u.deletingPathExtension().lastPathComponent, transcript: text, force: true)
                    }
                }
            }
        }
        .onAppear { n.refreshSaved() }
    }
}
