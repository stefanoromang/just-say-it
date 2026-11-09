// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation

/// Every call app Just Say It recognises, with its Mac bundle IDs, web addresses and window titles.
struct CallService: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    /// Mac bundle-ID prefixes (helper processes share the app's prefix).
    let bundlePrefixes: [String]
    /// Windows executable names (lowercase, without .exe).
    let exeNames: [String]
    /// Regular expressions that match the URL of an active call in a browser tab.
    let urlPatterns: [String]
    /// Lowercase fragments of window/tab titles that mean a call is open.
    let titleHints: [String]
}

enum CallApps {
    static let services: [CallService] = [
        CallService(id: "teams", name: "Microsoft Teams",
                    bundlePrefixes: ["com.microsoft.teams"], exeNames: ["ms-teams", "teams", "msteams"],
                    urlPatterns: [#"teams\.microsoft\.com"#, #"teams\.live\.com"#, #"teams\.cloud\.microsoft"#],
                    titleHints: ["microsoft teams"]),
        CallService(id: "meet", name: "Google Meet",
                    bundlePrefixes: [], exeNames: [],
                    urlPatterns: [#"meet\.google\.com/[a-z]{3,4}-[a-z]{3,4}-[a-z]{3,4}"#],
                    titleHints: ["google meet", "meet.google.com"]),
        CallService(id: "zoom", name: "Zoom",
                    bundlePrefixes: ["us.zoom."], exeNames: ["zoom", "cpthost"],
                    urlPatterns: [#"zoom\.us/wc/"#, #"app\.zoom\.us/wc"#, #"zoomgov\.com/wc/"#],
                    titleHints: ["zoom meeting", "zoom workplace", "zoom webinar"]),
        CallService(id: "facetime", name: "FaceTime",
                    bundlePrefixes: ["com.apple.facetime", "com.apple.avconferenced"], exeNames: [],
                    urlPatterns: [#"facetime\.apple\.com/join"#],
                    titleHints: ["facetime"]),
        CallService(id: "webex", name: "Cisco Webex",
                    bundlePrefixes: ["com.cisco.webex", "com.webex."], exeNames: ["webex", "ciscocollabhost", "atmgr", "webexmta"],
                    urlPatterns: [#"\.webex\.com/(meet|wbxmjs|webappng)"#],
                    titleHints: ["webex"]),
        CallService(id: "slack", name: "Slack (Huddles)",
                    bundlePrefixes: ["com.tinyspeck.slackmacgap"], exeNames: ["slack"],
                    urlPatterns: [#"app\.slack\.com/huddle"#],
                    titleHints: ["huddle"]),
        CallService(id: "discord", name: "Discord",
                    bundlePrefixes: ["com.hnc.discord"], exeNames: ["discord", "discordptb", "discordcanary"],
                    urlPatterns: [#"discord\.com/channels/"#],
                    titleHints: ["discord"]),
        CallService(id: "skype", name: "Skype",
                    bundlePrefixes: ["com.skype."], exeNames: ["skype"],
                    urlPatterns: [#"web\.skype\.com"#, #"join\.skype\.com"#],
                    titleHints: ["skype"]),
        CallService(id: "whereby", name: "Whereby",
                    bundlePrefixes: ["com.whereby"], exeNames: ["whereby"],
                    urlPatterns: [#"whereby\.com/[a-z0-9_-]+"#],
                    titleHints: ["whereby"]),
        CallService(id: "jitsi", name: "Jitsi Meet",
                    bundlePrefixes: ["org.jitsi."], exeNames: ["jitsi meet"],
                    urlPatterns: [#"meet\.jit\.si/[A-Za-z0-9_-]+"#, #"8x8\.vc/"#],
                    titleHints: ["jitsi meet"]),
        CallService(id: "ringcentral", name: "RingCentral",
                    bundlePrefixes: ["com.ringcentral.", "com.glip."], exeNames: ["ringcentral", "ringcentralvideo", "rcvideo"],
                    urlPatterns: [#"app\.ringcentral\.com"#, #"v\.ringcentral\.com"#, #"video\.ringcentral\.com"#],
                    titleHints: ["ringcentral"]),
        CallService(id: "goto", name: "GoTo Meeting",
                    bundlePrefixes: ["com.logmein.", "com.goto."], exeNames: ["g2mcomm", "g2mstart", "goto", "gotomeeting"],
                    urlPatterns: [#"app\.goto\.com/meeting"#, #"meet\.goto\.com"#, #"global\.gotomeeting\.com"#],
                    titleHints: ["goto meeting", "gotomeeting"]),
        CallService(id: "zoho", name: "Zoho Meeting",
                    bundlePrefixes: ["com.zoho.meeting", "com.zoho."], exeNames: ["zohomeeting", "zoho meeting"],
                    urlPatterns: [#"meeting\.zoho\.[a-z.]+/"#],
                    titleHints: ["zoho meeting"]),
        CallService(id: "signal", name: "Signal",
                    bundlePrefixes: ["org.whispersystems.signal-desktop"], exeNames: ["signal"],
                    urlPatterns: [],
                    titleHints: ["signal"]),
        CallService(id: "whatsapp", name: "WhatsApp",
                    bundlePrefixes: ["net.whatsapp.whatsapp", "desktop.whatsapp"], exeNames: ["whatsapp"],
                    urlPatterns: [],
                    titleHints: []),
        CallService(id: "telegram", name: "Telegram",
                    bundlePrefixes: ["ru.keepcoder.telegram", "org.telegram.desktop"], exeNames: ["telegram"],
                    urlPatterns: [],
                    titleHints: []),
    ]

    static func service(id: String) -> CallService? { services.first { $0.id == id } }

    /// Browsers whose tabs are checked for web calls.
    static let browsers: [(prefix: String, name: String)] = [
        ("com.google.chrome", "Google Chrome"), ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.browser", "Brave Browser"), ("company.thebrowser.browser", "Arc"),
        ("com.vivaldi.vivaldi", "Vivaldi"), ("com.operasoftware.opera", "Opera"),
        ("org.mozilla.firefox", "Firefox"), ("com.apple.safari", "Safari"), ("com.apple.webkit", "Safari"),
    ]

    enum Kind: Equatable { case native(CallService), browser(String) }

    static func kind(bundleID raw: String) -> Kind? {
        let b = raw.lowercased()
        for s in services where s.bundlePrefixes.contains(where: { b.hasPrefix($0) }) { return .native(s) }
        for (prefix, name) in browsers where b.hasPrefix(prefix) { return .browser(name) }
        return nil
    }

    static func service(forURL url: String) -> CallService? {
        let u = url.lowercased()
        return services.first { s in s.urlPatterns.contains { u.range(of: $0, options: .regularExpression) != nil } }
    }

    static func service(forTitle title: String) -> CallService? {
        let t = title.lowercased()
        // A Meet tab is titled "Meet - abc-defg-hij" or "Meet – <meeting name>".
        if t.hasPrefix("meet - ") || t.hasPrefix("meet – ") { return service(id: "meet") }
        return services.first { s in !s.urlPatterns.isEmpty && s.titleHints.contains { t.contains($0) } }
    }

    // Legacy helpers used by tests and calendar auto-join.
    static func platform(forURL url: String) -> MeetingPlatform? {
        switch service(forURL: url)?.id {
        case "meet": .meet
        case "teams": .teams
        case "zoom": .zoom
        default: nil
        }
    }

    static func platform(forTitle title: String) -> MeetingPlatform? {
        switch service(forTitle: title)?.id {
        case "meet": .meet
        case "teams": .teams
        case "zoom": .zoom
        default: nil
        }
    }
}
