// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case hidden, listening(scribe: Bool, handsFree: Bool), thinking, done, error(String), noteTaker
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var level: Float = 0
    @Published var preview = ""
    @Published var contextLabel = ""
    var levels: [Float] = Array(repeating: 0, count: 22)

    func push(_ l: Float) {
        levels.removeFirst()
        levels.append(l)
        level = l
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var tick = Ticker.shared

    var body: some View {
        VStack(spacing: 6) {
            if !model.preview.isEmpty, case .listening = model.state {
                Text(model.preview.suffix(90))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: 340)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                icon
                content
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(.black.opacity(0.88)))
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.15), value: model.state)
    }

    @ViewBuilder var icon: some View {
        switch model.state {
        case .listening(let scribe, _):
            Image(systemName: scribe ? "wand.and.stars" : "mic.fill")
                .foregroundStyle(scribe ? .purple : .red)
        case .thinking:
            ProgressView().controlSize(.small).tint(.white)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .noteTaker:
            Circle().fill(Color(red: 1, green: 0.16, blue: 0.47)).frame(width: 10, height: 10)
                .opacity(Ticker.shared.blink ? 1 : 0.25)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder var content: some View {
        switch model.state {
        case .listening(let scribe, let hf):
            HStack(spacing: 2) {
                ForEach(0..<model.levels.count, id: \.self) { i in
                    Capsule().fill(.white)
                        .frame(width: 3, height: max(3, CGFloat(model.levels[i]) * 22))
                }
            }
            .frame(height: 24)
            if scribe { Text("Scribe").font(.caption.bold()).foregroundStyle(.purple) }
            if hf { Text("Hands-free").font(.caption).foregroundStyle(.white.opacity(0.7)) }
            if !model.contextLabel.isEmpty {
                Text(model.contextLabel).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        case .thinking:
            Text("Polishing…").font(.caption).foregroundStyle(.white)
        case .done:
            Text("Inserted").font(.caption).foregroundStyle(.white)
        case .noteTaker:
            Text("JustSayIt - Note taker is active").font(.caption.bold())
                .foregroundStyle(Ticker.shared.blink ? Color(red: 1, green: 0.16, blue: 0.47) : .white)
        case .error(let m):
            Text(m).font(.caption).foregroundStyle(.white).lineLimit(1)
        case .hidden:
            EmptyView()
        }
    }
}

@MainActor
final class OverlayController {
    let model = OverlayModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 110),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    }

    func show(_ s: OverlayState) {
        hideWork?.cancel()
        model.state = s
        if case .listening = s { model.preview = "" }
        position()
        panel.orderFrontRegardless()
        switch s {
        case .done: hide(after: 0.7)
        case .error: hide(after: 2.5)
        case .hidden:
            if NoteTaker.shared.isRecording { model.state = .noteTaker } else { panel.orderOut(nil) }
        default: break
        }
    }

    func hide(after: Double = 0) {
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // While the Note Taker records, fall back to the flashing "active" pill.
                if NoteTaker.shared.isRecording {
                    self.model.state = .noteTaker
                    self.position()
                    self.panel.orderFrontRegardless()
                } else {
                    self.model.state = .hidden
                    self.panel.orderOut(nil)
                }
            }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: w)
    }

    private func position() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: f.midX - 260, y: f.minY + 24))
    }
}
