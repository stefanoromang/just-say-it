// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Speech

/// One audio source → Apple's on-device long-form SpeechTranscriber.
final class TranscriptPipe: @unchecked Sendable {
    var onFinal: ((String, Double) -> Void)?    // text, start time in seconds
    var onVolatile: ((String) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private let lock = NSLock()

    static func ensureModel(locale: Locale) async throws {
        let t = SpeechTranscriber(locale: locale, preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await req.downloadAndInstall()
        }
    }

    func start(locale: Locale) async throws {
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                  reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        let a = SpeechAnalyzer(modules: [t], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else {
            throw NSError(domain: "JustSayIt", code: 2, userInfo: [NSLocalizedDescriptionKey: "No compatible audio format for notes"])
        }
        analyzerFormat = fmt
        try await a.prepareToAnalyze(in: fmt)
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        continuation = cont
        analyzer = a
        resultsTask = Task { [weak self] in
            do {
                for try await r in t.results {
                    let text = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if r.isFinal {
                        if !text.isEmpty { self?.onFinal?(text, r.range.start.seconds) }
                        self?.onVolatile?("")
                    } else {
                        self?.onVolatile?(text)
                    }
                }
            } catch {}
        }
        try await a.start(inputSequence: stream)
    }

    /// Called from audio threads.
    func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let fmt = analyzerFormat, let cont = continuation, buffer.frameLength > 0 else { return }
        if converter == nil || converterInput != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: fmt)
            converterInput = buffer.format
        }
        guard let conv = converter else { return }
        let ratio = fmt.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
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

    func finish() async {
        let cont = lock.withLock { () -> AsyncStream<AnalyzerInput>.Continuation? in
            let c = continuation
            continuation = nil
            return c
        }
        cont?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        _ = await resultsTask?.value
        analyzer = nil
        resultsTask = nil
    }
}

/// Captures the computer's sound output (other people on a call) with ScreenCaptureKit.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "justsayit.system-audio")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "JustSayIt", code: 3, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 1
        // Video is required by the API but unused: keep it tiny and slow.
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        cfg.showsCursor = false
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid, let desc = sb.formatDescription else { return }
        let fmt = AVAudioFormat(cmAudioFormatDescription: desc)
        try? sb.withAudioBufferList { abl, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: abl.unsafePointer) else { return }
            onBuffer?(pcm)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {}
}
