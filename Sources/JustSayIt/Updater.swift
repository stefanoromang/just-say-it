// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit
import Foundation

/// Checks GitHub Releases for a newer version and installs it.
/// On Mac the app is built from source on the user's computer, so "install"
/// runs the official installer script (no Gatekeeper warnings, permissions kept).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "stefanoromang/just-say-it"

    @Published private(set) var latest: String?
    @Published private(set) var notes = ""
    @Published private(set) var status = ""
    @Published private(set) var installing = false
    @Published private(set) var lastChecked: Date?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var updateAvailable: Bool { latest.map { Self.isNewer($0, than: current) } ?? false }

    private var timer: Timer?

    func boot() {
        // Wait until the menu-bar app has finished launching before showing any alert.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await Updater.shared.check(userInitiated: false) } }
        }
    }

    static func log(_ s: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/JustSayIt/updates.log")
        let line = "\(Date()) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// "1.10" > "1.9", "2.0" > "1.12.3".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
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

    func check(userInitiated: Bool) async {
        guard Store.shared.prefs.checkForUpdates || userInitiated else { return }
        status = "Checking for updates…"
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("JustSayIt/\(current)", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw URLError(.cannotParseResponse) }
            latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            notes = (json["body"] as? String) ?? ""
            lastChecked = Date()
            Self.log("checked: current=\(current) latest=\(latest ?? "nil") available=\(updateAvailable)")
            if updateAvailable {
                status = "Version \(latest!) is available (you have \(current))."
                if !userInitiated && Store.shared.prefs.skippedVersion != latest { prompt() }
            } else {
                status = "You're up to date (\(current))."
            }
        } catch {
            Self.log("check failed: \(error.localizedDescription)")
            status = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    private func prompt() {
        guard let v = latest else { return }
        Self.log("showing update prompt for \(v)")
        // Menu-bar apps have no Dock icon; become a regular app briefly so the alert comes to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }
        let a = NSAlert()
        a.messageText = "Just Say It \(v) is available"
        a.informativeText = "You have \(current). Install the update now? It takes about a minute, and Just Say It restarts when it's done.\n\n" + String(Self.summary(notes).prefix(600))
        a.addButton(withTitle: "Install update")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip this version")
        a.window.level = .floating
        switch a.runModal() {
        case .alertFirstButtonReturn: install()
        case .alertThirdButtonReturn: Store.shared.prefs.skippedVersion = v
        default: break
        }
    }

    /// First paragraphs of the release notes, without Markdown symbols.
    nonisolated static func summary(_ md: String) -> String {
        md.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "### ", with: "") }
            .filter { !$0.hasPrefix("```") && !$0.contains("curl ") && !$0.contains("irm ") }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the official installer in the background, then relaunches the app.
    func install() {
        guard !installing else { return }
        installing = true
        status = "Downloading and building the update… (about a minute)"
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("just-say-it-update.log")
        let script = """
        set -o pipefail
        curl -fsSL https://raw.githubusercontent.com/\(Self.repo)/main/install-mac.sh \
          | sed 's|^open "$HOME/Applications/Just Say It.app"|# relaunch handled by updater|' \
          | /bin/zsh > '\(log.path)' 2>&1
        """
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", script]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
            env["JUSTSAYIT_UPDATER"] = "1"
            p.environment = env
            do { try p.run() } catch {}
            p.waitUntilExit()
            let ok = p.terminationStatus == 0
            await MainActor.run {
                Updater.shared.installing = false
                if ok {
                    Updater.shared.status = "Update installed. Restarting…"
                    Updater.relaunch()
                } else {
                    Updater.shared.status = "Update failed. See \(log.path)"
                    NSWorkspace.shared.open(log)
                }
            }
        }
    }

    /// Quit, then open the freshly installed copy.
    static func relaunch() {
        let app = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Just Say It.app")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while pgrep -x JustSayIt >/dev/null; do sleep 0.3; done; open \"\(app.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}
