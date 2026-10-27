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
