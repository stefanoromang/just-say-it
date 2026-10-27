// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import SwiftUI

@MainActor
final class ResultModel: ObservableObject {
    @Published var text = ""
    @Published var raw = ""
    @Published var contextLine = ""
    @Published var busy = false
    @Published var note = ""
    @Published var autoInserted = false
    @Published var mode = "Dictation"
}

struct ResultView: View {
    @ObservedObject var m: ResultModel
    var onInsert: () -> Void
    var onCopy: () -> Void
    var onRewrite: (RewriteStyle) -> Void
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill").foregroundStyle(.purple).font(.title3)
                Text("Just Say It").font(.headline)
                Text(m.mode).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.purple.opacity(0.2)))
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }
            if !m.contextLine.isEmpty {
                Label(m.contextLine, systemImage: "scope").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            TextEditor(text: $m.text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 90, maxHeight: 260)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            if !m.note.isEmpty {
                Text(m.note).font(.caption).foregroundStyle(m.autoInserted ? .green : .orange)
            }
            HStack(spacing: 8) {
                Button(action: onInsert) { Label(m.autoInserted ? "Insert again" : "Insert", systemImage: "text.insert") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(.purple)
                Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Menu {
                    ForEach(RewriteStyle.allCases) { s in Button(s.label) { onRewrite(s) } }
                } label: { Label("Rewrite", systemImage: "wand.and.stars") }
                    .fixedSize()
                Button(action: onRetry) { Label("Raw", systemImage: "arrow.uturn.backward") }
                    .help("Use the exact words I said")
                Spacer()
            }
            .disabled(m.busy)
            Text("↩ Insert · ⇧⌘C Copy · Esc Close").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ResultPanelController {
    let model = ResultModel()
    private var panel: KeyPanel?
    var onInsert: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRewrite: ((RewriteStyle) -> Void)?
    var onRetry: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(focus: Bool) {
        if panel == nil {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .closable],
                             backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.backgroundColor = .clear
            p.contentView = NSHostingView(rootView: ResultView(
                m: model,
                onInsert: { [weak self] in self?.onInsert?() },
                onCopy: { [weak self] in self?.onCopy?() },
                onRewrite: { [weak self] s in self?.onRewrite?(s) },
                onRetry: { [weak self] in self?.onRetry?() },
                onClose: { [weak self] in self?.hide() }))
            panel = p
        }
        guard let p = panel else { return }
        p.setContentSize(p.contentView?.fittingSize ?? NSSize(width: 480, height: 300))
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY + 80))
        }
        if focus { p.makeKeyAndOrderFront(nil) } else { p.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }
}
