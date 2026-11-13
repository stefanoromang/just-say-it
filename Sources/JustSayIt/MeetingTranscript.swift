// Just Say It – created by Stefano Roman Gunness · MIT License
import Foundation

struct MeetingCaption: Codable, Equatable {
    let service: String
    let session: String
    let segment: String
    let speaker: String
    let text: String
    let received: Double

    var valid: Bool {
        ["teams", "meet", "import"].contains(service) && !session.isEmpty && session.count <= 64
            && !segment.isEmpty && segment.count <= 100 && !speaker.isEmpty && speaker.count <= 200
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 12000
            && received.isFinite && received >= 0
    }
}

enum MeetingTranscript {
    /// Repeated snapshots update the same caption, rather than adding the sentence each second.
    static func merge(_ items: [MeetingCaption], into lines: inout [MeetingCaption], session: inout String?) {
        for item in items where item.valid {
            if session == nil { session = item.session }
            guard session == item.session else { continue } // never mix two meeting tabs
            if let i = lines.firstIndex(where: { $0.segment == item.segment && $0.session == item.session }) {
                lines[i] = item
            } else { lines.append(item) }
        }
    }

    static func text(_ lines: [MeetingCaption]) -> String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    /// VTT/SRT export, or plain text with "Speaker: words" lines. Never guess speaker identities.
    static func parse(_ input: String, now: Double = Date().timeIntervalSince1970) -> [MeetingCaption] {
        let input = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let session = UUID().uuidString
        var out: [MeetingCaption] = []
        let blocks = input.components(separatedBy: "\n\n")
        for block in blocks {
            var lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.first?.hasPrefix("WEBVTT") == true || lines.first?.hasPrefix("NOTE") == true { continue }
            if let timing = lines.firstIndex(where: { $0.contains("-->") }) { lines = Array(lines.dropFirst(timing + 1)) }
            else { lines.removeAll { $0.range(of: #"^\d+$"#, options: .regularExpression) != nil } }
            var cueSpeaker = "Speaker"
            for line in lines where !line.isEmpty {
                var speaker = "Speaker", text = line
                if let r = line.range(of: #"^<v(?:\.[^ >]+)?\s+([^>]+)>"#, options: .regularExpression) {
                    let tag = String(line[r]); speaker = tag.replacingOccurrences(of: #"^<v(?:\.[^ >]+)?\s+|>$"#, with: "", options: .regularExpression)
                    text = String(line[r.upperBound...]).replacingOccurrences(of: "</v>", with: "")
                } else if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) <= 100,
                          !line[..<colon].contains(where: { $0.isNumber }), !line[..<colon].isEmpty {
                    speaker = String(line[..<colon]); text = String(line[line.index(after: colon)...])
                } else if block.contains("-->") { speaker = cueSpeaker }
                cueSpeaker = speaker
                text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let item = MeetingCaption(service: "import", session: session, segment: String(out.count), speaker: speaker, text: text, received: now)
                if item.valid { out.append(item) }
            }
        }
        return out
    }

    static func combined(local: String, captions: [MeetingCaption]) -> String {
        guard !captions.isEmpty else { return local }
        return "MEETING PLATFORM TRANSCRIPT (speaker names supplied by the platform)\n" + text(captions)
            + "\n\nLOCAL AUDIO BACKUP (may overlap the platform transcript; do not count repeated statements twice)\n" + local
    }
}
