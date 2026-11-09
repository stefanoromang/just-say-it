// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation

/// The CollectivIQ sending rule (kept separate so it can be tested).
enum CiqRoute {
    /// Where a message goes: a new CIQ chat, a DDR's direct-message chat, or decided by the
    /// sending rule once CollectivIQ is open (see `route`).
    enum Destination: Equatable { case chat, ddr(String), auto }

    /// Models that answer in CIQ Chat when the notes go there.
    static let chatModels = ["Gemini", "Nemotron"]

    /// Where the notes end up, decided from the DDRs this person has in CollectivIQ:
    /// - a DDR called Notetaker → the raw transcript goes there;
    /// - no Notetaker but another DDR (their assistant) → the AI version goes to the first one;
    /// - no DDR at all → the AI version goes to CIQ Chat, answered by Gemini and Nemotron.
    enum Route: Equatable {
        case notetaker(String), assistant(String), chat

        /// Reads the result of the `routeScript` check ("route:notetaker:<name>", "route:assistant:<name>", "route:none").
        static func parse(_ r: String) -> Route? {
            if r == "route:none" { return .chat }
            if r.hasPrefix("route:notetaker:") { return .notetaker(String(r.dropFirst("route:notetaker:".count))) }
            if r.hasPrefix("route:assistant:") { return .assistant(String(r.dropFirst("route:assistant:".count))) }
            return nil
        }

        var destination: Destination {
            switch self {
            case .notetaker(let n), .assistant(let n): .ddr(n)
            case .chat: .chat
            }
        }

        /// Which version is sent on this route.
        var sendsRaw: Bool { if case .notetaker = self { return true }; return false }

        var label: String {
            switch self {
            case .notetaker(let n): "the raw transcript to your \(n) DDR"
            case .assistant(let n): "the AI version to your assistant (\(n))"
            case .chat: "the AI version to CIQ Chat (Gemini + Nemotron)"
            }
        }
    }

}
