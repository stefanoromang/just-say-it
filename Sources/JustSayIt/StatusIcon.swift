// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import SwiftUI

/// What the app is doing; each mode has its own neon color in the menu bar.
enum IconMode: Equatable {
    case idle, dictating, scribe, noteTaker, working

    /// Neon colors, bright enough for both dark and light menu bars.
    var color: NSColor {
        switch self {
        case .idle:      NSColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1)   // neon cyan
        case .dictating: NSColor(red: 1.00, green: 0.16, blue: 0.62, alpha: 1)   // neon pink
        case .scribe:    NSColor(red: 0.66, green: 0.33, blue: 1.00, alpha: 1)   // neon purple
        case .noteTaker: NSColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1)   // neon green
        case .working:   NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1)   // neon orange
        }
    }

    var label: String {
        switch self {
        case .idle: "Ready"
        case .dictating: "Dictating (1 key)"
        case .scribe: "Scribe (2 keys)"
        case .noteTaker: "Note Taker recording (Right Shift ×3)"
        case .working: "Working…"
        }
    }
}

@MainActor
final class StatusIcon: ObservableObject {
    static let shared = StatusIcon()

    @Published private(set) var mode: IconMode = .idle
    @Published private(set) var image: NSImage = StatusIcon.render(.idle, glow: 1)
    private var pulse = false
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            MainActor.assumeIsolated { StatusIcon.shared.tick() }
        }
    }

    func set(_ m: IconMode) {
        guard m != mode else { return }
        mode = m
        image = Self.render(m, glow: 1)
    }

    /// Picks the mode from what's running now.
    func refresh() {
        let c = Controller.shared
        if NoteTaker.shared.isRecording { set(.noteTaker) }
        else if c.isDictating { set(c.isScribe ? .scribe : .dictating) }
        else if c.isWorking { set(.working) }
        else { set(.idle) }
    }

    private func tick() {
        refresh()
        // Active modes pulse; idle stays steady.
        guard mode != .idle else { return }
        pulse.toggle()
        image = Self.render(mode, glow: pulse ? 1 : 0.45)
    }

    /// A bright, glowing waveform badge drawn in the mode's neon color.
    static func render(_ mode: IconMode, glow: CGFloat) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let c = mode.color
            let badge = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1), xRadius: 5, yRadius: 5)
            // Glow
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = c.withAlphaComponent(0.9 * glow)
            shadow.shadowBlurRadius = 3.5 * glow
            shadow.set()
            c.withAlphaComponent(0.25 + 0.2 * glow).setFill()
            badge.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            // Neon outline
            c.setStroke()
            badge.lineWidth = 1.4
            badge.stroke()
            // Waveform bars
            let bars: [CGFloat] = [0.35, 0.7, 1.0, 0.6, 0.85, 0.45]
            let bw: CGFloat = 1.8, gap: CGFloat = 1.2
            let total = CGFloat(bars.count) * bw + CGFloat(bars.count - 1) * gap
            var x = rect.midX - total / 2
            NSColor.white.setFill()
            for b in bars {
                let h = (rect.height - 7) * b
                NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - h / 2, width: bw, height: h), xRadius: 0.9, yRadius: 0.9).fill()
                x += bw + gap
            }
            return true
        }
        img.isTemplate = false   // keep the neon colors in light and dark menu bars
        return img
    }
}

/// The menu-bar label: the neon icon, redrawn as the mode changes.
struct StatusIconView: View {
    @ObservedObject var icon = StatusIcon.shared
    var body: some View {
        Image(nsImage: icon.image)
            .help(icon.mode.label)
    }
}
