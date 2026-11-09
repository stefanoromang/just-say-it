// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AVFoundation
import Foundation
import Speech

/// Streams microphone audio into Apple's on-device SpeechAnalyzer.
/// With several languages, the same audio is recognised in all of them at once and each phrase
/// keeps the language that heard it best, so you can switch languages mid-sentence without saying so.
/// Nothing leaves the Mac, and there is no usage limit.
@MainActor
final class Transcriber {
    var onLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTasks: [Task<Void, Never>] = []
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var languages: [String] = []
    /// Finalised words per language, plus the latest not-yet-final words.
    private var finalWords: [String: [SpokenWord]] = [:]
    private var volatileWords: [String: [SpokenWord]] = [:]
    private(set) var isRunning = false
    /// The language chosen for each phrase of the last recording (used to learn which languages you use).
    private(set) var lastPieces: [LanguageMix.Piece] = []
    private var prepared: Set<String> = []

    /// Downloads the speech model for a language the first time it is used.
    func ensureModel(localeID: String) async throws {
        let t = DictationTranscriber(locale: Locale(identifier: localeID), preset: .progressiveShortDictation)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()
        }
        prepared.insert(localeID)
    }

    func start(localeIDs: [String], vocabulary: [String]) async throws {
        guard !isRunning else { return }
        let ids = localeIDs.isEmpty ? ["en_US"] : localeIDs
        languages = ids
        finalWords = [:]
        volatileWords = [:]
        lastPieces = []
        for id in ids where !prepared.contains(id) { try await ensureModel(localeID: id) }

        var modules: [(String, DictationTranscriber)] = []
        for id in ids {
            modules.append((id, DictationTranscriber(
                locale: Locale(identifier: id),
                contentHints: [.shortForm],
                transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: ids.count > 1 ? [.transcriptionConfidence, .audioTimeRange] : [.audioTimeRange]
            )))
        }
        let a = SpeechAnalyzer(modules: modules.map(\.1), options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        if !vocabulary.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = vocabulary
            try? await a.setContext(ctx)
        }

        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules.map(\.1), considering: micFormat) else {
            throw NSError(domain: "JustSayIt", code: 1, userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"])
        }
        analyzerFormat = fmt
        converter = AVAudioConverter(from: micFormat, to: fmt)
        try await a.prepareToAnalyze(in: fmt)

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        continuation = cont
        analyzer = a

        resultsTasks = modules.map { (id, t) in
            Task { [weak self] in
                do {
                    for try await r in t.results {
                        let words = Self.words(r.text)
                        let isFinal = r.isFinal
                        await MainActor.run {
                            guard let self else { return }
                            if isFinal {
                                self.finalWords[id, default: []].append(contentsOf: words)
                                self.volatileWords[id] = []
                            } else {
                                self.volatileWords[id] = words
                            }
                            self.onPartial?(self.currentText())
                        }
                    }
                } catch {}
            }
        }

        try await a.start(inputSequence: stream)

        let conv = converter
        let level = onLevel
        input.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, _ in
            if let ch = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                let lvl = min(1, rms * 12)
                Task { @MainActor in level?(lvl) }
            }
            guard let conv else { return }
            let ratio = fmt.sampleRate / micFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Words with timing and confidence from a recognised attributed string.
    nonisolated static func words(_ s: AttributedString) -> [SpokenWord] {
        s.runs.map { run in
            let r = run.audioTimeRange
            return SpokenWord(text: String(s[run.range].characters),
                              start: r?.start.seconds ?? 0, end: r?.end.seconds ?? 0,
                              confidence: run.transcriptionConfidence ?? 0.5)
        }
    }

    private func currentText() -> String {
        var all: [String: [SpokenWord]] = [:]
        for id in languages { all[id] = (finalWords[id] ?? []) + (volatileWords[id] ?? []) }
        if languages.count == 1 { return (all[languages[0]] ?? []).map(\.text).joined() }
        return LanguageMix.text(all, languages: languages, prior: Learner.languagePrior())
    }

    /// Stops recording and returns the full transcript.
    func stop() async -> String {
        guard isRunning else { return "" }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        for t in resultsTasks { _ = await t.value }
        resultsTasks = []
        analyzer = nil
        var all: [String: [SpokenWord]] = [:]
        for id in languages { all[id] = (finalWords[id] ?? []) + (volatileWords[id] ?? []) }
        if languages.count > 1 {
            lastPieces = LanguageMix.merge(all, languages: languages, prior: Learner.languagePrior())
            return LanguageMix.join(lastPieces.map(\.text))
        }
        return (all[languages.first ?? ""] ?? []).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        for t in resultsTasks { t.cancel() }
        resultsTasks = []
        analyzer = nil
    }
}
