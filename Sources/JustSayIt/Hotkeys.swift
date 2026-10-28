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
    var onTripleShift: (() -> Void)?

    private var rightShiftTaps: [Date] = []
    private var rightShiftDownAt: Date?

    /// Right Shift pressed three times within ~0.9 s (each a quick tap) → Note Taker.
    private func handleRightShift(_ e: NSEvent) {
        let now = Date()
        // Right Shift sets the device-dependent bit 0x04 while held.
        let down = (e.modifierFlags.rawValue & 0x04) != 0
        if down {
            rightShiftDownAt = now
            return
        }
        if rightShiftDownAt == nil { return }
        // A long press (normal Shift use) resets the count.
        guard let d = rightShiftDownAt, now.timeIntervalSince(d) < 0.35 else {
            rightShiftDownAt = nil
            rightShiftTaps.removeAll()
            return
        }
        rightShiftDownAt = nil
        let others = e.modifierFlags.intersection([.command, .control, .option])
        guard others.isEmpty else { rightShiftTaps.removeAll(); return }
        rightShiftTaps = rightShiftTaps.filter { now.timeIntervalSince($0) < 0.9 } + [now]
        if rightShiftTaps.count >= 3 {
            rightShiftTaps.removeAll()
            onTripleShift?()
        }
    }

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
            // Any other key between Shift taps breaks the sequence (normal typing).
            rightShiftTaps.removeAll()
            return false
        }
        if e.type == .flagsChanged, e.keyCode == 60 { // Right Shift
            handleRightShift(e)
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
