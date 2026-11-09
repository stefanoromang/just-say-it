// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation

/// What Just Say It has learned about how you speak and write. Stays on this Mac.
struct Learning: Codable, Equatable {
    /// How often each language was used (phrases), so close calls go to the languages you speak most.
    var languageCounts: [String: Int] = [:]
    /// Corrections you made: what was written → what you changed it to, with how many times.
    var corrections: [String: [String: Int]] = [:]
    /// Names and terms you corrected or typed in, so they're recognised and spelled right next time.
    var terms: [String: Int] = [:]
    /// Recent finished texts you kept, per kind of app, to match your style.
    var examples: [String: [String]] = [:]
    var dictations = 0
    var edits = 0
}

/// Learns from every dictation and every correction:
/// - the languages you use most (helps pick the right language for short phrases),
/// - words you correct (fixed automatically after you correct them twice),
/// - names and terms (recognised and spelled correctly),
/// - your writing style per app (recent examples guide the AI).
enum LearnCore {
    /// Word-level substitutions between the text Just Say It wrote and the version you fixed.
    /// Only short replacements (1–3 words) count; rewrites of whole sentences are ignored.
    static func substitutions(from original: String, to edited: String) -> [(String, String)] {
        let a = tokens(original), b = tokens(edited)
        guard !a.isEmpty, !b.isEmpty, a.count < 400, b.count < 400 else { return [] }
        // Longest common subsequence on lowercased words.
        let la = a.map { $0.lowercased() }, lb = b.map { $0.lowercased() }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = la[i] == lb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [(String, String)] = []
        var i = 0, j = 0
        var gapA: [String] = [], gapB: [String] = []
        func flush() {
            if !gapA.isEmpty, !gapB.isEmpty, gapA.count <= 3, gapB.count <= 3 {
                let from = gapA.joined(separator: " "), to = gapB.joined(separator: " ")
                if from.lowercased() != to.lowercased() || from != to { out.append((from, to)) }
            }
            gapA = []; gapB = []
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, la[i] == lb[j] {
                flush()
                // Same word, different capitalisation (a name): counts as a correction too.
                if a[i] != b[j], b[j].first?.isUppercase == true { out.append((a[i], b[j])) }
                i += 1; j += 1
            } else if j < b.count, i == a.count || dp[i][j + 1] >= dp[i + 1][j] {
                gapB.append(b[j]); j += 1
            } else {
                gapA.append(a[i]); i += 1
            }
        }
        flush()
        // A big rewrite isn't a word correction.
        let changed = out.reduce(0) { $0 + $1.0.split(separator: " ").count }
        return changed > max(4, a.count / 3) ? [] : out
    }

    static func tokens(_ s: String) -> [String] {
        s.split { $0.isWhitespace }.map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
    }

    /// Corrections seen at least twice become automatic fixes.
    static func learnedFixes(_ l: Learning, minimum: Int = 2) -> [(heard: String, write: String)] {
        l.corrections.compactMap { heard, targets in
            guard let best = targets.max(by: { $0.value < $1.value }), best.value >= minimum else { return nil }
            return (heard, best.key)
        }.sorted { $0.heard < $1.heard }
    }

    /// Terms to recognise and spell exactly (most used first).
    static func learnedTerms(_ l: Learning, limit: Int = 60) -> [String] {
        l.terms.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }

    /// Share of phrases per language (0–1).
    static func languagePrior(_ l: Learning) -> [String: Double] {
        let total = Double(l.languageCounts.values.reduce(0, +))
        guard total >= 5 else { return [:] }
        return l.languageCounts.mapValues { Double($0) / total }
    }

    /// Records a correction in the learning data.
    static func learn(_ l: inout Learning, original: String, edited: String) {
        let subs = substitutions(from: original, to: edited)
        guard !subs.isEmpty else { return }
        l.edits += 1
        for (from, to) in subs {
            let key = from.lowercased()
            l.corrections[key, default: [:]][to, default: 0] += 1
            // Names / terms: capitalised or containing a capital, digit or symbol.
            for w in to.split(separator: " ").map(String.init)
            where w.count > 1 && (w.first?.isUppercase == true || w.contains(where: { $0.isNumber })) && !commonWords.contains(w.lowercased()) {
                l.terms[w, default: 0] += 1
            }
        }
        if l.corrections.count > 400 {
            // Keep the most used ones.
            let keep = l.corrections.sorted { ($0.value.values.max() ?? 0) > ($1.value.values.max() ?? 0) }.prefix(300)
            l.corrections = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    static func remember(_ l: inout Learning, example: String, category: String) {
        let t = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 25, t.count <= 600 else { return }
        var list = l.examples[category] ?? []
        list.removeAll { $0 == t }
        list.insert(t, at: 0)
        l.examples[category] = Array(list.prefix(5))
    }

    /// A short block for the AI: how this user writes in this kind of app.
    static func styleBlock(_ l: Learning, category: String, maxChars: Int = 700) -> String? {
        guard let ex = l.examples[category], !ex.isEmpty else { return nil }
        var out = "", used = 0
        for e in ex where used + e.count <= maxChars { out += "- \(e)\n"; used += e.count }
        return out.isEmpty ? nil : out
    }

    static let commonWords: Set<String> = ["i", "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "is", "it",
                                           "el", "la", "los", "las", "de", "y", "o", "que", "en", "un", "una", "o", "e", "il", "lo", "di", "da"]
}

