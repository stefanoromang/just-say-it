// Just Say It – created by Stefano Roman Gunness · MIT License
// Minimal stand-in for the context type so TextBrain compiles in the rule tests.
import Foundation

struct CaptureContext {
    var appName = "Test"
    var category: AppCategory = .other
    var screenText: String?
    var windowTitle: String?
    func promptBlock(maxScreen: Int = 1200) -> String { "App: Test" }
}

/// Same comparison as Updater.isNewer (the real Updater depends on AppKit UI).
enum Updater {
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

/// Same text layout as CollectivIQ.message (the real type opens the browser).
enum CollectivIQ {
    static let defaultPrompt = ciqStandardPrompt
    static func message(prompt: String, title: String?, transcript: String) -> String {
        var s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultPrompt }
        s += "\n\n"
        if let title, !title.isEmpty { s += "Meeting: \(title)\n\n" }
        s += transcript
        return s
    }
}
