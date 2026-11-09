// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation

/// Persists and applies what was learned.
@MainActor
final class Learner: ObservableObject {
    static let shared = Learner()

    @Published private(set) var data = Learning()
    private let url: URL

    private init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JustSayIt/learning.json")
        if let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode(Learning.self, from: d) { data = l }
    }

    private var enabled: Bool { Store.shared.prefs.learningEnabled }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    /// After each dictation: count languages and remember the style.
    func dictated(final text: String, languages: [String], category: AppCategory) {
        guard enabled else { return }
        data.dictations += 1
        for l in languages { data.languageCounts[l, default: 0] += 1 }
        LearnCore.remember(&data, example: text, category: category.rawValue)
        save()
    }

    /// You changed the text before inserting it: learn the corrections.
    func corrected(original: String, edited: String, category: AppCategory) {
        guard enabled, original != edited else { return }
        LearnCore.learn(&data, original: original, edited: edited)
        LearnCore.remember(&data, example: edited, category: category.rawValue)
        save()
    }

    static func languagePrior() -> [String: Double] {
        shared.enabled ? LearnCore.languagePrior(shared.data) : [:]
    }

    var fixes: [Replacement] {
        guard enabled else { return [] }
        return LearnCore.learnedFixes(data).map { Replacement(heard: $0.heard, write: $0.write) }
    }

    var terms: [String] { enabled ? LearnCore.learnedTerms(data) : [] }

    func style(for c: AppCategory) -> String? { enabled ? LearnCore.styleBlock(data, category: c.rawValue) : nil }

    func forget(correction heard: String) { data.corrections[heard] = nil; save() }
    func forget(term: String) { data.terms[term] = nil; save() }

    func forgetAll() { data = Learning(); save() }
}
