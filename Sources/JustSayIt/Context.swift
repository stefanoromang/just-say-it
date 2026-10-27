// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// Everything we know about where the user is dictating, captured when the hotkey is pressed.
struct CaptureContext {
    var appName = ""
    var bundleID = ""
    var pid: pid_t = 0
    var windowTitle: String?
    var url: String?
    var selectedText: String?
    var fieldTextBeforeCursor: String?
    var fieldRole: String?
    var fieldIsEditable: Bool?
    var screenText: String?
    var category: AppCategory = .other

    var host: String? { url.flatMap { URL(string: $0)?.host?.lowercased() } }

    /// Short description for the AI prompt.
    func promptBlock(maxScreen: Int = 1200) -> String {
        var lines: [String] = []
        lines.append("App: \(appName) (\(category.label))")
        if let t = windowTitle, !t.isEmpty { lines.append("Window title: \(t.prefix(160))") }
        if let h = host { lines.append("Website: \(h)") }
        if let f = fieldTextBeforeCursor?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            lines.append("Text already in the box before the cursor:\n\"\"\"\n\(f.suffix(600))\n\"\"\"")
        }
        if let s = selectedText, !s.isEmpty {
            lines.append("Text the user selected:\n\"\"\"\n\(s.prefix(1500))\n\"\"\"")
        }
        if let sc = screenText, !sc.isEmpty {
            lines.append("Visible on screen (OCR, may be noisy):\n\"\"\"\n\(sc.prefix(maxScreen))\n\"\"\"")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
enum ContextReader {

    static let browserIDs: [String: String] = [
        "com.google.chrome": "Google Chrome", "com.google.chrome.beta": "Google Chrome Beta",
        "com.google.chrome.canary": "Google Chrome Canary", "company.thebrowser.browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge", "com.brave.browser": "Brave Browser",
        "com.vivaldi.vivaldi": "Vivaldi", "com.apple.safari": "Safari",
        "com.operasoftware.opera": "Opera",
    ]

    /// Fast part (accessibility + browser URL). Runs synchronously at hotkey press.
    static func captureFast() -> CaptureContext {
        var c = CaptureContext()
        let app = NSWorkspace.shared.frontmostApplication
        c.appName = app?.localizedName ?? "this app"
        c.bundleID = app?.bundleIdentifier ?? ""
        c.pid = app?.processIdentifier ?? 0

        if AXIsProcessTrusted(), c.pid != 0 {
            let axApp = AXUIElementCreateApplication(c.pid)
            // Ask Chromium/Electron apps to expose their web content to accessibility.
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            c.windowTitle = windowTitle(axApp)
            if let focused = focusedElement(axApp) {
                c.fieldRole = string(focused, kAXRoleAttribute)
                c.fieldIsEditable = isEditable(focused, role: c.fieldRole)
                c.selectedText = string(focused, kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 }
                c.fieldTextBeforeCursor = textBeforeCursor(focused)
            }
        }
        if let name = browserIDs[c.bundleID.lowercased()] {
            c.url = browserURL(appName: name, safari: c.bundleID.lowercased() == "com.apple.safari")
        }
        c.category = Inserter.category(for: c)
        return c
    }

    // MARK: Accessibility helpers

    static func focusedElement(_ axApp: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &v) == .success, let v {
            return (v as! AXUIElement)
        }
        let sys = AXUIElementCreateSystemWide()
        if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &v) == .success, let v {
            return (v as! AXUIElement)
        }
        return nil
    }

    static func windowTitle(_ axApp: AXUIElement) -> String? {
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &w) == .success, let w else { return nil }
        return string(w as! AXUIElement, kAXTitleAttribute)
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    static func isEditable(_ el: AXUIElement, role: String?) -> Bool? {
        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        if let role, editableRoles.contains(role) { return true }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue { return true }
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &v) == .success, let b = v as? Bool { return b }
        return role == nil ? nil : false
    }

    static func textBeforeCursor(_ el: AXUIElement) -> String? {
        guard let value = string(el, kAXValueAttribute), !value.isEmpty else { return nil }
        var r: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &r) == .success, let r,
           CFGetTypeID(r) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(r as! AXValue, .cfRange, &range) {
                let ns = value as NSString
                let loc = min(max(range.location, 0), ns.length)
                let start = max(0, loc - 1500)
                return ns.substring(with: NSRange(location: start, length: loc - start))
            }
        }
        return String(value.suffix(1500))
    }

    // MARK: Browser URL

    static func browserURL(appName: String, safari: Bool) -> String? {
        let src = safari
            ? "tell application \"\(appName)\" to if (count of windows) > 0 then return URL of front document"
            : "tell application \"\(appName)\" to if (count of windows) > 0 then return URL of active tab of front window"
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return r?.stringValue
    }

    // MARK: Screen OCR (needs Screen Recording permission)

    static var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenAccess() { _ = CGRequestScreenCaptureAccess() }

    /// Reads the visible text of the user's window. Runs in the background while they talk.
    static func readScreen(pid: pid_t) async -> String? {
        guard hasScreenAccess, pid != 0 else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 150
            }
            guard let win = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = SCStreamConfiguration()
            let scale = 2.0
            cfg.width = Int(win.frame.width * scale)
            cfg.height = Int(win.frame.height * scale)
            cfg.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            return await Task.detached(priority: .userInitiated) { ocr(image) }.value
        } catch {
            return nil
        }
    }

    nonisolated static func ocr(_ image: CGImage) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try? handler.perform([req])
        let lines = (req.results ?? [])
            .sorted { ($0.boundingBox.minY, -$0.boundingBox.minX) > ($1.boundingBox.minY, -$1.boundingBox.minX) }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.count > 2 }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : String(text.prefix(4000))
    }

    /// Proper nouns and technical words on screen, to help the speech engine spell names.
    nonisolated static func glossary(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0.isWhitespace || ",.;:()[]\"!?".contains($0) }) {
            let w = String(raw)
            guard w.count >= 3, w.count <= 30, let f = w.first, f.isUppercase || w.contains(where: \.isNumber) == false && w.dropFirst().contains(where: \.isUppercase) else { continue }
            guard w.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "'" }) else { continue }
            if seen.insert(w.lowercased()).inserted { out.append(w) }
            if out.count >= 60 { break }
        }
        return out
    }
}
