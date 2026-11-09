// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation
import NaturalLanguage

/// One recognised word (or punctuation) with its timing and how sure the recogniser was.
struct SpokenWord: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
}

/// Mixed-language speech: the audio is recognised in every language the user speaks at the same
/// time; this picks, phrase by phrase, the language that heard it best. You never have to say or
/// switch which language you're speaking.
enum LanguageMix {
    /// A phrase in one language.
    struct Piece: Equatable { let language: String; let text: String; let start: Double; let end: Double }

    /// Punctuation and spaces come back as separate pieces with no length of their own: attach them
    /// to the word before, so every piece is a real timed word.
    static func attachPunctuation(_ ws: [SpokenWord]) -> [SpokenWord] {
        var out: [SpokenWord] = []
        var pending = ""
        for w in ws {
            let isWord = w.end > w.start && w.text.contains(where: { $0.isLetter || $0.isNumber })
            if isWord {
                out.append(SpokenWord(text: pending + w.text, start: w.start, end: w.end, confidence: w.confidence))
                pending = ""
            } else if let last = out.last {
                out[out.count - 1] = SpokenWord(text: last.text + w.text, start: last.start, end: last.end, confidence: last.confidence)
            } else {
                pending += w.text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : w.text
            }
        }
        return out
    }

    /// Splits the timeline into phrases at pauses where no language heard a word.
    static func phrases(_ all: [String: [SpokenWord]], pause: Double = 0.2) -> [(start: Double, end: Double)] {
        let spoken = all.values.flatMap { $0 }.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard let first = spoken.first else { return [] }
        var out: [(Double, Double)] = []
        var start = first.start, reach = first.end
        for w in spoken.dropFirst() {
            if w.start - reach >= pause { out.append((start, reach)); start = w.start }
            reach = max(reach, w.end)
        }
        out.append((start, reach))
        return out
    }

    /// How well a language heard a phrase: its confidence, weighted by whether the words it wrote
    /// actually read as that language (a Spanish recogniser hearing English writes English-looking words).
    static func score(language: String, words: [SpokenWord]) -> Double {
        let timed = words.filter { $0.end > $0.start }
        let duration = timed.map { $0.end - $0.start }.reduce(0, +)
        guard duration > 0 else { return 0 }
        let confidence = timed.map { ($0.end - $0.start) * $0.confidence }.reduce(0, +) / duration
        let text = words.map(\.text).joined()
        let count = text.split(whereSeparator: \.isWhitespace).count
        let own = readsAs(text, language: language)
        return confidence * (count >= 3 ? 0.4 + 0.6 * own : 0.8 + 0.2 * own)
    }

    /// Probability (0–1) that the text is written in this language ("en_US", "pt-BR", "es"…).
    static func readsAs(_ text: String, language: String) -> Double {
        let code = String(language.prefix(2)).lowercased()
        let r = NLLanguageRecognizer()
        r.processString(text)
        return r.languageHypotheses(withMaximum: 12).filter { $0.key.rawValue.lowercased().hasPrefix(code) }.map(\.value).reduce(0, +)
    }

    /// The best language for each phrase, in order. Neighbouring phrases in the same language are joined.
    /// `prior`: share of past phrases per language (learned); a gentle tie-breaker for close calls.
    static func merge(_ all: [String: [SpokenWord]], languages: [String]? = nil, prior: [String: Double] = [:]) -> [Piece] {
        let order = languages ?? all.keys.sorted()
        let all = all.mapValues(attachPunctuation)
        var pieces: [Piece] = []
        for p in phrases(all) {
            var best: (lang: String, score: Double, text: String)?
            for lang in order {
                var inside = (all[lang] ?? []).filter { let mid = ($0.start + $0.end) / 2; return mid >= p.start - 0.001 && mid <= p.end + 0.001 }
                // Drop barely-heard words at the start (guesses at a language switch, e.g. "this week" / "Please").
                if !pieces.isEmpty { while inside.count >= 4, let f = inside.first, f.confidence < 0.3 { inside.removeFirst() } }
                var text = inside.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                while let f = text.first, ".,;:!?".contains(f) { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
                guard !text.isEmpty else { continue }
                var s = score(language: lang, words: inside)
                if let share = prior[lang] { s *= 0.9 + 0.2 * share }
                if best == nil || s > best!.score { best = (lang, s, text) }
            }
            guard var b = best else { continue }
            // A few words in another language with no pause around them ("…the report antes del viernes
            // because…"): swap in that language's words where it clearly heard them better.
            if order.count > 1 {
                b.text = patchSwitches(winner: b.lang, all: all, order: order, range: p, first: pieces.isEmpty)
            }
            if let last = pieces.last, last.language == b.lang {
                pieces[pieces.count - 1] = Piece(language: b.lang, text: join([last.text, b.text]), start: last.start, end: p.end)
            } else {
                pieces.append(Piece(language: b.lang, text: b.text, start: p.start, end: p.end))
            }
        }
        return pieces
    }

    /// Inside a phrase, replaces runs of barely-heard words with another language's version of the
    /// same moment when that language heard them clearly and they read as that language.
    static func patchSwitches(winner: String, all: [String: [SpokenWord]], order: [String], range p: (start: Double, end: Double), first: Bool = false) -> String {
        func within(_ ws: [SpokenWord], _ a: Double, _ b: Double) -> [SpokenWord] {
            ws.filter { let mid = ($0.start + $0.end) / 2; return mid >= a - 0.001 && mid <= b + 0.001 }
        }
        var words = within(all[winner] ?? [], p.start, p.end)
        if !first { while words.count >= 4, let f = words.first, f.confidence < 0.3 { words.removeFirst() } }
        var out: [String] = []
        var i = 0
        while i < words.count {
            guard words[i].confidence < 0.45 else { out.append(words[i].text); i += 1; continue }
            var j = i
            while j < words.count, words[j].confidence < 0.45 { j += 1 }
            let run = Array(words[i..<j])
            let a = run.first!.start, b = run.last!.end
            let mine = run.map(\.confidence).reduce(0, +) / Double(run.count)
            var replacement: [SpokenWord]?
            for other in order where other != winner {
                let theirs = within(all[other] ?? [], a, b).filter { $0.confidence >= 0.3 }
                guard !theirs.isEmpty else { continue }
                let conf = theirs.map(\.confidence).reduce(0, +) / Double(theirs.count)
                let text = theirs.map(\.text).joined()
                if conf >= max(0.5, mine + 0.2),
                   readsAs(text, language: other) > readsAs(text, language: winner) {
                    replacement = theirs
                    break
                }
            }
            if let r = replacement {
                var t = r.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                // Keep the winner's punctuation at the end of the run.
                if let last = run.last?.text.trimmingCharacters(in: .whitespaces).last, ".,;:!?".contains(last),
                   !(t.last.map { ".,;:!?".contains($0) } ?? false) { t.append(last) }
                out.append(t + " ")
            } else {
                out.append(contentsOf: run.map(\.text))
            }
            i = j
        }
        var text = out.joined().replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while let f = text.first, ".,;:!?".contains(f) { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return text
    }

    /// Joins phrases into one text, adding a sentence break when a phrase ends without punctuation
    /// and the next one starts a new sentence.
    static func join(_ parts: [String]) -> String {
        var out = ""
        for raw in parts {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if out.isEmpty { out = t; continue }
            let ended = out.last.map { ".!?…:;".contains($0) } ?? true
            if !ended, t.first?.isUppercase == true { out += "." }
            out += " " + t
        }
        return out
    }

    /// Text for a set of recognitions: one language → as heard; several → the best per phrase.
    static func text(_ all: [String: [SpokenWord]], languages: [String], prior: [String: Double] = [:]) -> String {
        if languages.count == 1, let only = all[languages[0]] {
            return only.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return join(merge(all, languages: languages, prior: prior).map(\.text))
    }

    /// Live merging for long recordings (Note Taker): words arrive from each language as they are
    /// finalised; phrases are released once every language has finished with that stretch of audio.
    final class Stream: @unchecked Sendable {
        private let languages: [String]
        var prior: [String: Double] = [:]
        private var words: [String: [SpokenWord]] = [:]
        private var finalized: [String: Double] = [:]
        private let lock = NSLock()

        init(languages: [String]) { self.languages = languages }

        /// Adds finalised words from one language; `through` is how far that language has finalised.
        func add(_ lang: String, _ new: [SpokenWord], through: Double) {
            lock.withLock {
                words[lang, default: []].append(contentsOf: new)
                finalized[lang] = max(finalized[lang] ?? 0, through)
            }
        }

        /// Phrases that every language has finished with (ending before a pause), removed from the buffer.
        func drain(final: Bool = false) -> [Piece] {
            lock.withLock {
                let done = final ? Double.infinity : languages.map { finalized[$0] ?? 0 }.min() ?? 0
                let ranges = LanguageMix.phrases(words)
                // Keep the last phrase open unless everything is finished (more words may join it).
                let ready = ranges.filter { $0.end < done - 0.3 || final }
                guard let cut = ready.last?.end else { return [] }
                var taken: [String: [SpokenWord]] = [:]
                for (lang, ws) in words {
                    taken[lang] = ws.filter { ($0.start + $0.end) / 2 <= cut + 0.001 }
                    words[lang] = ws.filter { ($0.start + $0.end) / 2 > cut + 0.001 }
                }
                return LanguageMix.merge(taken, languages: languages, prior: prior)
            }
        }
    }
}
