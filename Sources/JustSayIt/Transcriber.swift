// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AVFoundation
import Foundation
import Speech

/// Streams microphone audio into Apple's on-device SpeechAnalyzer.
/// Nothing leaves the Mac, and there is no usage limit.
@MainActor
final class Transcriber {
    var onLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var finalText = ""
    private var volatileText = ""
    private(set) var isRunning = false
    private var preparedLocale: String?

    /// Downloads the speech model for a language the first time it is used.
    func ensureModel(localeID: String) async throws {
        let locale = Locale(identifier: localeID)
        let t = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()
        }
    }

    func start(localeID: String, vocabulary: [String]) async throws {
        guard !isRunning else { return }
        finalText = ""
        volatileText = ""

        let locale = Locale(identifier: localeID)
        if preparedLocale != localeID {
            try await ensureModel(localeID: localeID)
            preparedLocale = localeID
        }

        let t = DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm],
            transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: []
        )
        let a = SpeechAnalyzer(modules: [t], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        if !vocabulary.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings[.general] = vocabulary
            try? await a.setContext(ctx)
        }

        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t], considering: micFormat) else {
            throw NSError(domain: "JustSayIt", code: 1, userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"])
        }
        analyzerFormat = fmt
        converter = AVAudioConverter(from: micFormat, to: fmt)
        try await a.prepareToAnalyze(in: fmt)

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        continuation = cont
        transcriber = t
        analyzer = a

        resultsTask = Task { [weak self] in
            do {
                for try await r in t.results {
                    let text = String(r.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        if r.isFinal {
                            self.finalText += text
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                        self.onPartial?(self.finalText + self.volatileText)
                    }
                }
            } catch {}
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

    /// Stops recording and returns the full transcript.
    func stop() async -> String {
        guard isRunning else { return "" }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        let text = (finalText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func cancel() async {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }
}
