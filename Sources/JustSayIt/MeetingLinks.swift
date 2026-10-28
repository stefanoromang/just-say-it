// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation

enum MeetingPlatform: String, Codable, CaseIterable {
    case zoom = "Zoom", meet = "Google Meet", teams = "Microsoft Teams"
}

struct MeetingLink: Equatable {
    let platform: MeetingPlatform
    let url: URL
}

/// Finds Zoom / Google Meet / Microsoft Teams join links in calendar text.
enum MeetingLinks {
    static let patterns: [(MeetingPlatform, String)] = [
        (.zoom, #"https://(?:[\w-]+\.)?zoom\.us/(?:j|my|w|s)/[\w?=.&%-]+"#),
        (.zoom, #"https://(?:[\w-]+\.)?zoomgov\.com/j/[\w?=.&%-]+"#),
        (.meet, #"https://meet\.google\.com/[a-z]{3,4}-[a-z]{3,4}-[a-z]{3,4}(?:\?[\w=&%.-]*)?"#),
        (.teams, #"https://teams\.microsoft\.com/l/meetup-join/[^\s"<>]+"#),
        (.teams, #"https://teams\.live\.com/meet/[\w?=&%-]+"#),
        (.teams, #"https://teams\.microsoft\.com/meet/[\w?=&%-]+"#),
    ]

    static func find(in texts: [String?]) -> MeetingLink? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for (platform, pattern) in patterns {
                if let r = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    var s = String(text[r])
                    while let last = s.last, ".,;)>]".contains(last) { s.removeLast() }
                    if let url = URL(string: s) { return MeetingLink(platform: platform, url: url) }
                }
            }
        }
        return nil
    }

    /// Opens Zoom meetings directly in the Zoom app when it is installed (skips the browser page).
    static func appURL(for link: MeetingLink) -> URL {
        guard link.platform == .zoom,
              let comps = URLComponents(url: link.url, resolvingAgainstBaseURL: false),
              let host = comps.host else { return link.url }
        let parts = comps.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "j" else { return link.url }
        var q = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(parts[1]))]
        if let pwd = comps.queryItems?.first(where: { $0.name == "pwd" })?.value { q.append(URLQueryItem(name: "pwd", value: pwd)) }
        var z = URLComponents()
        z.scheme = "zoommtg"
        z.host = host
        z.path = "/join"
        z.queryItems = q
        return z.url ?? link.url
    }
}
