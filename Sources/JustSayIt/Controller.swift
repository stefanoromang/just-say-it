// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AVFoundation
import AppKit
import Speech

@MainActor
final class Controller: ObservableObject {
    static let shared = Controller()

    let store = Store.shared
    let transcriber = Transcriber()
    let hotkeys = Hotkeys()
    let overlay = OverlayController()
    let result = ResultPanelController()

    @Published var micGranted = false
    @Published var axGranted = false
    @Published var screenGranted = false
    @Published var modelReady = false
    @Published var modelStatus = "Checking speech model…"
    @Published var lastResult = ""
    @Published var lastContext = ""

    private var startedAt = Date()
    private var scribe = false
    private var ctx = CaptureContext()
    private var screenTask: Task<String?, Never>?
    private var startTask: Task<Void, Never>?
    private var lastRaw = ""

    func boot() {
        transcriber.onLevel = { [weak self] l in self?.overlay.model.push(l) }
        transcriber.onPartial = { [weak self] t in self?.overlay.model.preview = t }
        hotkeys.hotkey = store.prefs.hotkey
        hotkeys.onStart = { [weak self] s, hf in self?.begin(scribe: s, handsFree: hf) }
        hotkeys.onStop = { [weak self] in self?.finish() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.onRewrite = { [weak self] in self?.rewriteSelection(.concise) }
        hotkeys.onTripleShift = { [weak self] in self?.toggleNotes() }
        hotkeys.install()

        result.onInsert = { [weak self] in self?.insertFromPanel() }
        result.onCopy = { [weak self] in self?.copyFromPanel() }
        result.onRewrite = { [weak self] s in self?.rewritePanel(s) }
        result.onRetry = { [weak self] in self?.useRaw() }

        refreshPermissions()
        TextBrain.prewarm()
        AutoJoin.shared.boot()
        Updater.shared.boot()
        Task { await prepareModel() }
        // Re-check permissions periodically so the hotkey starts working as soon as they're granted.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasAX = self.axGranted
                self.refreshPermissions()
                if !wasAX && self.axGranted { self.hotkeys.install() }
            }
        }
    }

    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = Inserter.hasAccessibility
        screenGranted = ContextReader.hasScreenAccess
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Task { @MainActor in self.micGranted = ok }
        }
    }

    func prepareModel() async {
        modelStatus = "Downloading speech model (first run only)…"
        do {
            try await transcriber.ensureModel(localeID: store.prefs.localeID)
            modelReady = true
            modelStatus = "Speech model ready (on-device)"
        } catch {
            modelReady = false
            modelStatus = "Speech model error: \(error.localizedDescription)"
        }
    }

    func setHotkey(_ h: HotkeyChoice) {
        store.prefs.hotkey = h
        hotkeys.hotkey = h
    }

    // MARK: Note Taker

    func toggleNotes() {
        guard store.prefs.noteTakerEnabled else { return }
        guard micGranted else { requestMic(); overlay.show(.error("Allow microphone access")); return }
        if transcriber.isRunning { return }
        NoteTaker.shared.toggle()
    }

    // MARK: Dictation flow

    func toggleFromMenu() {
        if transcriber.isRunning || startTask != nil { finish() } else {
            hotkeys.reset()
            // Give focus back to the previous app before reading context.
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.begin(scribe: false, handsFree: true) }
        }
    }

    private func begin(scribe: Bool, handsFree: Bool) {
        guard micGranted else { requestMic(); overlay.show(.error("Allow microphone access")); hotkeys.reset(); return }
        if NoteTaker.shared.isRecording { overlay.show(.error("Note Taker is recording – press Right ⇧ ×3 to stop")); hotkeys.reset(); return }
        if result.isVisible { result.hide() }
        self.scribe = scribe
        startedAt = Date()

        // 1. Capture context NOW, while the user's app and text box still have focus.
        ctx = ContextReader.captureFast()
        lastContext = describe(ctx)
        // 2. Read the screen in the background while the user talks.
        let pid = ctx.pid
        screenTask = store.prefs.useScreenContext ? Task { await ContextReader.readScreen(pid: pid) } : nil

        overlay.show(.listening(scribe: scribe, handsFree: handsFree))
        overlay.model.contextLabel = "\(ctx.appName) · \(store.tone(for: ctx.category).label)"
        if store.prefs.playSounds { NSSound(named: "Tink")?.play() }

        var vocab = store.prefs.vocabulary + store.prefs.replacements.map(\.write)
        if let sel = ctx.selectedText { vocab += ContextReader.glossary(from: sel) }
        if let t = ctx.windowTitle { vocab += ContextReader.glossary(from: t) }
        let vocabulary = Array(vocab.prefix(100))
        startTask = Task {
            do {
                try await transcriber.start(localeID: store.prefs.localeID, vocabulary: vocabulary)
            } catch {
                overlay.show(.error("Mic/speech error: \(error.localizedDescription)"))
                hotkeys.reset()
            }
            startTask = nil
        }
    }

    private func cancel() {
        Task {
            await startTask?.value
            await transcriber.cancel()
            screenTask?.cancel()
            overlay.show(.hidden)
        }
    }

    private func finish() {
        Task {
            await startTask?.value
            let duration = Date().timeIntervalSince(startedAt)
            let raw = await transcriber.stop()
            if store.prefs.playSounds { NSSound(named: "Pop")?.play() }
            guard !raw.isEmpty else {
                overlay.show(.error("Didn't hear anything – try again"))
                return
            }
            lastRaw = raw
            overlay.show(.thinking)
            if let screen = await screenTask?.value { ctx.screenText = screen }
            screenTask = nil
            let text = await process(raw)
            guard !text.isEmpty else { overlay.show(.hidden); return }
            lastResult = text
            store.record(HistoryItem(date: Date(), raw: raw, final: text, app: ctx.appName,
                                     seconds: duration, words: text.split { $0.isWhitespace }.count))
            await deliver(text)
        }
    }

    /// Insert automatically when there's a text box; always show the result card so it can be copied/edited.
    private func deliver(_ text: String) async {
        result.model.text = text
        result.model.raw = lastRaw
        result.model.mode = scribe ? "Scribe" : (ctx.selectedText != nil ? "Edit selection" : "Dictation")
        result.model.contextLine = lastContext
        result.model.busy = false

        let canType = axGranted && ctx.fieldIsEditable != false
        if store.prefs.autoInsert && canType {
            await reactivateTarget()
            await Inserter.insert(text, restoreClipboard: store.prefs.restoreClipboard)
            result.model.autoInserted = true
            result.model.note = "✓ Inserted into \(ctx.appName). Edit below and press Insert again, or Copy."
            overlay.show(.done)
        } else {
            result.model.autoInserted = false
            result.model.note = !axGranted
                ? "Turn on Accessibility for Just Say It to insert automatically. You can Copy for now."
                : "No text box was selected. Click into a text box, then press Insert, or Copy."
            overlay.show(.hidden)
        }
        if store.prefs.showResultCard || !result.model.autoInserted {
            result.show(focus: !result.model.autoInserted)
        }
    }

    private func reactivateTarget() async {
        guard ctx.pid != 0, let app = NSRunningApplication(processIdentifier: ctx.pid) else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ctx.pid {
            app.activate()
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func process(_ raw: String) async -> String {
        let p = store.prefs
        let (expanded, wholeSnippet) = TextBrain.expandSnippets(raw, p.snippets)
        if wholeSnippet { return expanded }

        let tone = store.tone(for: ctx.category)
        let custom = p.customInstructions[ctx.category]
        let ruled = TextBrain.ruleClean(expanded)
        var out = ruled

        if let sel = ctx.selectedText, !scribe, TextBrain.looksLikeEditCommand(ruled) {
            // Spoken instruction applied to selected text ("make this shorter", "translate to Spanish").
            if let s = await TextBrain.editSelection(sel, instruction: ruled, ctx: ctx, tone: tone) { out = s }
        } else if scribe {
            if let s = await TextBrain.scribe(ruled, ctx: ctx, tone: tone, custom: custom) { out = s }
        } else if p.aiCleanup, ruled.split(separator: " ").count >= 3 || ruled.contains("\n") {
            if let s = await TextBrain.polish(ruled, ctx: ctx, tone: tone, custom: custom, vocabulary: p.vocabulary),
               plausible(s, against: ruled) {
                out = s
            }
        }
        out = TextBrain.applyReplacements(out, p.replacements, vocabulary: p.vocabulary)
        if tone == .veryCasual, !scribe {
            out = out.trimmingCharacters(in: .whitespaces)
            if out.hasSuffix("."), !out.dropLast().contains(".") { out.removeLast() }
        }
        return TextBrain.fitToCursor(out, before: ctx.fieldTextBeforeCursor)
    }

    private func plausible(_ out: String, against input: String) -> Bool {
        let a = Double(out.count), b = Double(max(input.count, 1))
        if a > b * 1.8 + 40 { return false }
        if a < b * 0.25 { return false }
        return true
    }

    private func describe(_ c: CaptureContext) -> String {
        var parts = [c.appName]
        if let h = c.host { parts.append(h) } else if let t = c.windowTitle, !t.isEmpty { parts.append("“\(t.prefix(50))”") }
        parts.append(c.category.label)
        parts.append("tone: " + store.tone(for: c.category).label)
        if c.selectedText != nil { parts.append("selection captured") }
        if c.fieldIsEditable == true { parts.append("text box ✓") } else if c.fieldIsEditable == false { parts.append("no text box") }
        if store.prefs.useScreenContext && screenGranted { parts.append("screen read") }
        return parts.joined(separator: " · ")
    }

    // MARK: Result card actions

    private func insertFromPanel() {
        let text = result.model.text
        result.hide()
        Task {
            await reactivateTarget()
            await Inserter.insert(text, restoreClipboard: store.prefs.restoreClipboard)
            overlay.show(.done)
        }
    }

    private func copyFromPanel() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.model.text, forType: .string)
        result.model.note = "✓ Copied to clipboard"
        result.model.autoInserted = true
    }

    private func rewritePanel(_ style: RewriteStyle) {
        let src = result.model.text
        result.model.busy = true
        Task {
            if let out = await TextBrain.rewrite(src, style: style) { result.model.text = out; lastResult = out }
            result.model.busy = false
            result.model.autoInserted = false
            result.model.note = "Rewritten (\(style.label)). Press Insert to replace, or Copy."
        }
    }

    private func useRaw() {
        result.model.text = TextBrain.ruleClean(lastRaw)
        result.model.autoInserted = false
        result.model.note = "Showing your exact words (basic cleanup only)."
    }

    // MARK: Rewrite selection hotkey

    func rewriteSelection(_ style: RewriteStyle) {
        Task {
            ctx = ContextReader.captureFast()
            var text = ctx.selectedText
            if text == nil { text = await Inserter.copySelectionViaKeyboard() }
            guard let text, !text.isEmpty else { overlay.show(.error("Select some text first")); return }
            overlay.show(.thinking)
            guard let out = await TextBrain.rewrite(text, style: style) else {
                overlay.show(.error(TextBrain.aiAvailable ? "Rewrite failed" : "Turn on Apple Intelligence"))
                return
            }
            lastRaw = text
            lastContext = describe(ctx)
            scribe = false
            lastResult = out
            await deliver(out)
        }
    }
}
