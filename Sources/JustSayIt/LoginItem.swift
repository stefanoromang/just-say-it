// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation
import ServiceManagement

/// Starts Just Say It automatically when you log in to your Mac.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func apply() {
        set(Store.shared.prefs.startAtLogin)
    }

    static func set(_ on: Bool) {
        do {
            if on, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !on, SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("JustSayIt login item: \(error.localizedDescription)")
        }
    }
}
