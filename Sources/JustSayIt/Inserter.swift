// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import ApplicationServices

/// Detects the frontmost app and pastes text into its focused text field.
@MainActor
enum Inserter {

    static func frontApp() -> (name: String, bundleID: String) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName ?? "this app", app?.bundleIdentifier ?? "")
    }

    static func category(for c: CaptureContext) -> AppCategory {
        let hay = ((c.host ?? "") + " " + (c.windowTitle ?? "")).lowercased()
        if !hay.trimmingCharacters(in: .whitespaces).isEmpty, ContextReader.browserIDs[c.bundleID.lowercased()] != nil || c.bundleID.lowercased() == "org.mozilla.firefox" {
            let email = ["mail.google", "gmail", "outlook.", "outlook ", "mail.yahoo", "proton.me", "icloud.com/mail", "inbox", "superhuman", "fastmail"]
            let work = ["slack", "teams.microsoft", "teams", "notion", "linear.app", "atlassian", "jira", "asana", "docs.google", "google docs", "monday.com", "clickup", "trello", "figma", "hubspot", "salesforce"]
            let casual = ["whatsapp", "messenger", "discord", "telegram", "instagram", "facebook", "x.com", "twitter", "reddit", "messages"]
            let ai = ["chatgpt", "chat.openai", "claude.ai", "claude", "gemini.google", "gemini", "perplexity", "copilot", "grok"]
            let code = ["github", "gitlab", "stackoverflow", "stack overflow", "codepen", "replit", "vercel"]
            if email.contains(where: hay.contains) { return .email }
            if ai.contains(where: hay.contains) { return .ai }
            if work.contains(where: hay.contains) { return .work }
            if casual.contains(where: hay.contains) { return .casual }
            if code.contains(where: hay.contains) { return .code }
        }
        return category(bundleID: c.bundleID, appName: c.appName)
    }

    static func category(bundleID id: String, appName: String) -> AppCategory {
        let b = id.lowercased()
        let n = appName.lowercased()
        let email = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.superhuman", "com.google.gmail", "io.canarymail", "com.freron.mailmate", "it.bloop.airmail", "com.mimestream"]
        let work = ["com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.microsoft.teams2", "notion.id", "com.linear", "com.atlassian", "com.asana", "us.zoom.xos", "com.google.chat", "com.clickup"]
        let casual = ["com.apple.mobilesms", "com.apple.ichat", "net.whatsapp.whatsapp", "desktop.whatsapp", "ru.keepcoder.telegram", "com.tdesktop.telegram", "com.hnc.discord", "org.whispersystems.signal-desktop", "com.facebook.archon", "com.facebook.messenger"]
        let ai = ["com.openai.chat", "com.openai.codex", "com.anthropic.claudefordesktop", "com.perplexity", "com.google.gemini", "ai.opencode"]
        let code = ["com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.xcode", "com.jetbrains", "dev.zed.zed", "com.sublimetext", "com.googlecode.iterm2", "com.apple.terminal", "dev.warp.warp-stable", "com.mitchellh.ghostty", "com.exafunction.windsurf"]
        func has(_ list: [String]) -> Bool { list.contains { b.hasPrefix($0) } }
        if has(email) { return .email }
        if has(work) { return .work }
        if has(casual) { return .casual }
        if has(ai) || n.contains("chatgpt") || n.contains("claude") { return .ai }
        if has(code) || n.contains("cursor") || n.contains("code") { return .code }
        // Browsers: try the window title (Gmail, Slack, ChatGPT open as tabs).
        let browsers = ["com.apple.safari", "com.google.chrome", "company.thebrowser.browser", "org.mozilla.firefox", "com.brave.browser", "com.microsoft.edgemac", "com.operasoftware", "com.vivaldi", "app.zen-browser"]
        if has(browsers), let title = focusedWindowTitle()?.lowercased() {
            if title.contains("gmail") || title.contains("outlook") || title.contains("inbox") || title.contains("mail") { return .email }
            if title.contains("slack") || title.contains("teams") || title.contains("notion") || title.contains("linear") || title.contains("google docs") { return .work }
            if title.contains("whatsapp") || title.contains("messenger") || title.contains("discord") || title.contains("telegram") || title.contains("instagram") { return .casual }
            if title.contains("chatgpt") || title.contains("claude") || title.contains("gemini") || title.contains("perplexity") { return .ai }
            if title.contains("github") || title.contains("stack overflow") { return .code }
        }
        return .other
    }

    static func focusedWindowTitle() -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    /// Currently selected text in the focused field (for AI Rewrite).
    static func selectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success else { return nil }
        let s = sel as? String
        return (s?.isEmpty == false) ? s : nil
    }

    /// Copies the selection with ⌘C as a fallback for apps without accessibility text.
    static func copySelectionViaKeyboard() async -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let saved = savePasteboard()
        sendKey(8, flags: .maskCommand) // C
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 15_000_000)
            if pb.changeCount != before { break }
        }
        let s = pb.changeCount != before ? pb.string(forType: .string) : nil
        restorePasteboard(saved)
        return s
    }

    static func insert(_ text: String, restoreClipboard: Bool) async {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let saved = restoreClipboard ? savePasteboard() : []
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Hide from clipboard managers.
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        sendKey(9, flags: .maskCommand) // V
        if restoreClipboard {
            try? await Task.sleep(nanoseconds: 350_000_000)
            restorePasteboard(saved)
        }
    }

    static func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func savePasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    private static func restorePasteboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !items.isEmpty else { return }
        let objs: [NSPasteboardItem] = items.map { dict in
            let it = NSPasteboardItem()
            for (t, v) in dict { it.setData(v, forType: t) }
            return it
        }
        pb.writeObjects(objs)
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
