// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit

/// Global hotkeys:
/// - Hold the dictation key to talk, release to insert.
/// - Double-tap it for hands-free; tap again to finish.
/// - Hold the dictation key + Shift for Scribe mode.
/// - Esc while recording cancels.
@MainActor
final class Hotkeys {
    var onStart: ((_ scribe: Bool, _ handsFree: Bool) -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRewrite: (() -> Void)?

    var hotkey: HotkeyChoice = .rightOption
    private(set) var recording = false
    private var handsFree = false
    private var keyDownAt: Date?
    private var lastTapUp: Date?
    private var monitors: [Any] = []

    func install() {
        uninstall()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { _ = self?.handle(e) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated {
                if self?.handle(e) == true { return nil }
                return e
            }
        }) { monitors.append(l) }
    }

    func uninstall() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    func reset() {
        recording = false
        handsFree = false
        keyDownAt = nil
    }

    /// Returns true when the event was consumed (local monitor only).
    private func handle(_ e: NSEvent) -> Bool {
        if e.type == .keyDown {
            if recording && e.keyCode == 53 { // Esc
                reset()
                onCancel?()
                return true
            }
            // ⌃⌥R = rewrite selection
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 15, f.contains(.control), f.contains(.option), !f.contains(.command) {
                onRewrite?()
                return true
            }
            return false
        }
        guard e.type == .flagsChanged, e.keyCode == hotkey.keyCode else { return false }
        let down = e.modifierFlags.contains(hotkey.flag)
        let now = Date()

        if down {
            keyDownAt = now
            if recording && handsFree {
                // Tap while hands-free → finish.
                reset()
                onStop?()
                return false
            }
            if !recording {
                let scribe = e.modifierFlags.contains(.shift)
                let isDoubleTap = lastTapUp.map { now.timeIntervalSince($0) < 0.35 } ?? false
                recording = true
                handsFree = isDoubleTap
                onStart?(scribe, isDoubleTap)
            }
        } else {
            let held = keyDownAt.map { now.timeIntervalSince($0) } ?? 0
            keyDownAt = nil
            guard recording, !handsFree else { return false }
            if held < 0.25 {
                // Quick tap: discard it; a second tap soon after starts hands-free.
                lastTapUp = now
                reset()
                onCancel?()
                return false
            }
            lastTapUp = nil
            reset()
            onStop?()
        }
        return false
    }
}
