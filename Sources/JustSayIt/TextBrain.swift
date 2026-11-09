// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import Foundation
import FoundationModels

/// Turns a raw transcript into finished text. Fast rules run first; Apple's
/// on-device language model then polishes when it is available.
@MainActor
enum TextBrain {

    // MARK: Fast local rules (always run)

    static let fillers = ["um", "umm", "uh", "uhh", "uh huh", "er", "erm", "ah", "hmm", "mm", "you know", "i mean", "sort of", "kind of like"]

    static func ruleClean(_ input: String) -> String {
        var s = " " + input + " "
        // Self-correction commands: drop the preceding sentence.
        let scratch = ["scratch that", "delete that", "strike that", "never mind that"]
        for cmd in scratch {
            while let r = s.range(of: cmd, options: .caseInsensitive) {
                let before = s[..<r.lowerBound]
                var cut = before.startIndex
                let trimmed = before.trimmingCharacters(in: .whitespaces)
                let t2 = trimmed.dropLast(trimmed.last.map { ".!?,".contains($0) } == true ? 1 : 0)
                if let end = t2.lastIndex(where: { ".!?\n".contains($0) }) {
                    cut = s.index(after: end)
                }
                var after = s[r.upperBound...]
                while let f = after.first, ".,!? ".contains(f) { after = after.dropFirst() }
                s = String(s[..<cut]) + " " + after
            }
        }
        // Filler words.
        for f in fillers {
            let pattern = "(?i)(?<![\\p{L}'])" + NSRegularExpression.escapedPattern(for: f) + "(?![\\p{L}'])[,.]?"
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Stand-alone "like," used as filler.
        s = s.replacingOccurrences(of: "(?i)(?<=[,.]|^|\\s)like,\\s", with: " ", options: .regularExpression)
        // Spoken punctuation & layout.
        let spoken: [(String, String)] = [
            ("new paragraph", "\n\n"), ("new line", "\n"), ("next line", "\n"),
            ("question mark", "?"), ("exclamation point", "!"), ("exclamation mark", "!"),
            ("full stop", "."), ("comma", ","), ("colon", ":"), ("semicolon", ";"),
        ]
        for (k, v) in spoken {
            s = s.replacingOccurrences(of: "(?i)\\s*\\b" + k + "\\b[,.]?\\s*", with: v == "\n" || v == "\n\n" ? v : v + " ", options: .regularExpression)
        }
        // Repeated words ("the the").
        s = s.replacingOccurrences(of: "(?i)\\b(\\w+)(\\s+\\1\\b)+", with: "$1", options: .regularExpression)
        // Whitespace & punctuation tidy.
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "([,.!?;:])(?=[A-Za-z])", with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: ",+", with: ",", options: .regularExpression)
        s = s.replacingOccurrences(of: "^[\\s,.]+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return capitalizeSentences(s)
    }

    static func capitalizeSentences(_ s: String) -> String {
        var out = ""
        var capNext = true
        for ch in s {
            if capNext, ch.isLetter { out.append(contentsOf: ch.uppercased()); capNext = false; continue }
            out.append(ch)
            if ".!?\n".contains(ch) { capNext = true } else if !ch.isWhitespace { capNext = false }
        }
        return out
    }

    static func applyReplacements(_ s: String, _ reps: [Replacement], vocabulary: [String]) -> String {
        var out = s
        for r in reps where !r.heard.isEmpty {
            out = out.replacingOccurrences(of: "(?i)\\b" + NSRegularExpression.escapedPattern(for: r.heard) + "\\b", with: NSRegularExpression.escapedTemplate(for: r.write), options: .regularExpression)
        }
        // Enforce exact spelling/casing of dictionary words.
        for w in vocabulary where !w.isEmpty {
            out = out.replacingOccurrences(of: "(?i)\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b", with: NSRegularExpression.escapedTemplate(for: w), options: .regularExpression)
        }
        return out
    }

    /// If the whole utterance is a snippet trigger, or contains "insert <trigger>", expand it.
    static func expandSnippets(_ s: String, _ snippets: [Snippet]) -> (String, Bool) {
        let norm = s.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        for sn in snippets where !sn.trigger.isEmpty {
            let trig = sn.trigger.lowercased()
            if norm == trig || norm == "insert " + trig { return (sn.text, true) }
        }
        var out = s
        for sn in snippets where !sn.trigger.isEmpty {
            out = out.replacingOccurrences(of: "(?i)\\binsert\\s+" + NSRegularExpression.escapedPattern(for: sn.trigger) + "\\b[.,]?", with: NSRegularExpression.escapedTemplate(for: sn.text), options: .regularExpression)
        }
        return (out, false)
    }

    // MARK: On-device AI

    static var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static var warm: LanguageModelSession?

    static func prewarm() {
        guard aiAvailable else { return }
        let s = LanguageModelSession(instructions: "You format dictated text.")
        s.prewarm()
        warm = s
    }

    /// Deterministic output. The initializer label changed between Apple SDKs (Swift 6.2 vs 6.4).
    private static func greedyOptions() -> GenerationOptions {
        #if compiler(>=6.4)
        return GenerationOptions(samplingMode: .greedy, temperature: 0)
        #else
        return GenerationOptions(sampling: .greedy, temperature: 0)
        #endif
    }

    private static func run(_ instructions: String, _ prompt: String) async -> String? {
        guard aiAvailable else { return nil }
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations), instructions: instructions)
        do {
            let r = try await session.respond(to: prompt, options: greedyOptions())
            let t = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : stripWrapping(t)
        } catch {
            return nil
        }
    }

    static func stripWrapping(_ t: String) -> String {
        var s = t
        for p in ["Here is the cleaned text:", "Here's the cleaned text:", "Cleaned text:", "Output:", "Here is the rewritten text:"] {
            if s.lowercased().hasPrefix(p.lowercased()) { s = String(s.dropFirst(p.count)) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 2, s.hasPrefix("\""), s.hasSuffix("\""), s.dropFirst().dropLast().contains("\"") == false {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }

    /// Words that must survive formatting; if the model drops most of them it answered instead of formatting.
    static func keepsMeaning(_ out: String, _ input: String) -> Bool {
        let stop: Set<String> = ["the", "a", "an", "and", "or", "to", "of", "is", "it", "i", "you", "so", "like", "um", "uh", "that", "this", "in", "on", "at", "for", "be", "we", "my"]
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init).filter { $0.count > 1 && !stop.contains($0) })
        }
        let src = words(input), dst = words(out)
        guard src.count >= 2 else { return true }
        let kept = Double(src.intersection(dst).count) / Double(src.count)
        return kept >= 0.5
    }

    /// Language guidance for speech that may mix languages.
    static let mixedLanguageRule = """
    - The speaker may switch between languages (for example English, Spanish, Portuguese and Italian) in the same sentence. Keep each part in the language it was spoken in. Never translate unless asked. A word that looks wrong may have been heard in the wrong language: fix it using the language of the words around it.
    """

    static func polish(_ text: String, ctx: CaptureContext, tone: Tone, custom: String?, vocabulary: [String], style: String? = nil) async -> String? {
        let category = ctx.category
        var ins = """
        You are a dictation formatter. The user spoke the text below and it was transcribed by speech recognition. Rewrite it as the finished text the user intended to type.
        Rules:
        - Remove filler words (um, uh, like, you know, I mean, eh, este, tipo, cioè, né), stutters, and false starts.
        - When the speaker corrects themselves ("no wait", "actually", "I mean", "sorry", "or rather", "no espera", "mejor dicho", "anzi"), delete the wrong part and the correction phrase, keeping only the corrected version. Example: "meet on Tuesday no wait Wednesday" → "meet on Wednesday". Example: "send it to Mark sorry Mike" → "send it to Mike".
        - Remove casual filler like "like", "so" at the start, and "you know"; "at like 3pm" → "at 3 PM".
        - Fix punctuation, capitalization, grammar and obvious recognition errors (words that sound alike but make no sense in the sentence). Use the CONTEXT below to spell names, people, companies and terms correctly (for example, the name of the person in the email being replied to).
        - When the speaker lists several items, format them as a list with "- " bullets, or numbers if they said first/second/third or counted.
        - Keep the speaker's meaning and their own words, including hedges like "I think". Never add facts, greetings, or sign-offs they did not say.
        - The text is something the user is typing to someone else. If it contains a question or request, output the question itself, nicely formatted. Never answer it.
        - If the box already contains text, continue naturally from it (do not repeat it).
        - Output ONLY the final text, with no quotes or commentary.
        \(mixedLanguageRule)
        Tone: \(tone.guidance)
        """
        if category == .code || category == .ai {
            ins += "\nPreserve technical terms, code identifiers, file names and commands exactly."
        }
        if !vocabulary.isEmpty {
            ins += "\nAlways spell these terms exactly like this: " + vocabulary.joined(separator: ", ") + "."
        }
        if let custom, !custom.isEmpty { ins += "\nUser style preference: " + custom }
        if let style { ins += "\nHow this user writes here (recent messages; match the style, never copy the content):\n" + style }
        ins += "\n\nCONTEXT (for spelling and tone only; never copy it into the output):\n" + ctx.promptBlock(maxScreen: 900)
        let prompt = "Dictated text to format (do not answer it):\n<<<\n\(text)\n>>>"
        var out = await run(ins, prompt)
        if out == nil, ctx.screenText != nil {
            // Context too long for the model: retry without screen text.
            var c2 = ctx; c2.screenText = nil
            ins = ins.components(separatedBy: "\n\nCONTEXT")[0] + "\n\nCONTEXT (for spelling and tone only):\n" + c2.promptBlock()
            out = await run(ins, prompt)
        }
        guard let out else { return nil }
        let cleaned = out.replacingOccurrences(of: "<<<", with: "").replacingOccurrences(of: ">>>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return keepsMeaning(cleaned, text) ? cleaned : nil
    }

    /// Scribe: writes the finished message from what the user said.
    /// Step 1 lists exactly what they asked for (every point, name, number). Step 2 writes the
    /// message from that list, using the screen only to know who and what it replies to.
    /// The result is checked so no point is lost and nothing from the screen is copied in.
    static func scribe(_ text: String, ctx: CaptureContext, tone: Tone, custom: String?,
                       vocabulary: [String] = [], style: String? = nil) async -> String? {
        let category = ctx.category
        let register = tone == .verbatim || tone == .casual || tone == .veryCasual ? Tone.formal : tone

        // 1. What did the user actually say?
        let planIns = """
        You read what a user dictated to an assistant that writes messages for them. Speech recognition may have misheard some words; fix them from the meaning. The user may mix English, Spanish, Portuguese and Italian.
        Output exactly these lines and nothing else:
        GOAL: what kind of message and its purpose (e.g. "reply to Ana declining the meeting", "email to the team announcing the launch")
        RECIPIENT: who it is for, if said or clear from the context, else "unknown"
        LANGUAGE: the language the message must be written in: the one the user asked for; otherwise the language of the conversation they are replying to; otherwise the language they mostly spoke
        POINTS:
        - every point, request, question, name, date, time, number and amount the user said, one per line, in order, with nothing added
        """
        let planPrompt = "CONTEXT (only to identify the recipient and topic):\n\(ctx.promptBlock(maxScreen: 700))\n\nWhat the user dictated:\n<<<\n\(text)\n>>>"
        let plan = await run(planIns, planPrompt)

        // 2. Write it.
        var ins = """
        You are a skilled ghostwriter. Write the complete, polished message the user wants to send, ready to send, in their voice (first person).
        - What the user dictated is what matters most: include every point from the PLAN and the dictation, in a logical order, with clear connected sentences. Do not invent specifics (names, dates, numbers, promises) they did not give.
        - Use the CONTEXT only to know who it is for and what it replies to (correct names, the right topic). Never copy text from the context into the message and never answer things the user did not address.
        - When the user says "tell X…", "let X know…", "reply to X…", "dile a X…", "avisa a X…" or similar, write the message itself, addressed to X, as if the user is writing to them. Remove the instruction words. Example: "let the team know the launch moves to Monday" → "Hi team, the launch is moving to Monday." Never write "Let the team know…" or "I need to tell…".
        - Capitalize names of people, companies and places.
        - Make the logic clear: open with the purpose, then the details, then any request or next step.
        - Write in the LANGUAGE from the plan. Fix anything speech recognition clearly misheard.
        - Output ONLY the message text: no preamble, no quotes, no subject line unless asked, no notes.
        - Never use placeholders such as [Your Name], [Date] or [Company]. If the user's name is unknown, end without a name.
        Tone: \(register.guidance) Be courteous and precise; avoid slang.
        """
        if category == .email { ins += "\nFormat as an email body with an appropriate greeting and sign-off." }
        if category == .work || category == .casual { ins += "\nThis is a chat message: keep it concise, no email greeting or sign-off unless asked." }
        if !vocabulary.isEmpty { ins += "\nAlways spell these terms exactly like this: " + vocabulary.prefix(60).joined(separator: ", ") + "." }
        if let custom, !custom.isEmpty { ins += "\nUser style preference: " + custom }
        if let style { ins += "\nHow this user writes here (recent messages; match the style, never copy the content):\n" + style }
        ins += "\n\nCONTEXT:\n" + ctx.promptBlock(maxScreen: 1200)
        var prompt = ""
        if let plan, plan.contains("POINTS") { prompt += "PLAN:\n\(plan)\n\n" }
        prompt += "What the user dictated:\n<<<\n\(text)\n>>>"
        var out = await run(ins, prompt)
        if out == nil, ctx.screenText != nil {
            var c2 = ctx; c2.screenText = String((ctx.screenText ?? "").prefix(400))
            ins = ins.components(separatedBy: "\n\nCONTEXT:")[0] + "\n\nCONTEXT:\n" + c2.promptBlock(maxScreen: 400)
            out = await run(ins, prompt)
        }
        guard var result = out else { return nil }
        result = removePlaceholders(result.replacingOccurrences(of: "<<<", with: "").replacingOccurrences(of: ">>>", with: ""))

        // 3. Check: every number from the dictation must be there; otherwise ask for a fix once.
        let missing = numbers(in: text).subtracting(numbers(in: result))
        if !missing.isEmpty {
            let fix = "Rewrite this message so it also includes these details the user said: \(missing.sorted().joined(separator: ", ")). Keep everything else the same. Output only the message.\n\n\(result)"
            if let fixed = await run(ins, fix), numbers(in: text).subtracting(numbers(in: fixed)).isEmpty {
                result = removePlaceholders(fixed)
            }
        }
        return result
    }

    /// Numbers (digits) in a text, for checking nothing was lost.
    nonisolated static func numbers(in s: String) -> Set<String> {
        let re = try! NSRegularExpression(pattern: "\\d+")
        let ns = s as NSString
        return Set(re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
    }

    static func looksLikeEditCommand(_ s: String) -> Bool {
        let l = s.lowercased()
        let starts = ["make it", "make this", "make that", "rewrite", "rephrase", "translate", "summarize", "shorten", "expand", "fix", "turn this", "turn it", "change", "convert", "reply", "respond", "answer", "improve", "add ", "remove", "format", "polish", "proofread"]
        return starts.contains { l.hasPrefix($0) } || l.contains("this text") || l.contains("the selected")
    }

    /// Applies a spoken instruction to the text the user selected.
    static func editSelection(_ selection: String, instruction: String, ctx: CaptureContext, tone: Tone) async -> String? {
        var ins = """
        You edit text for the user. Apply the user's spoken instruction to the SELECTED TEXT and output only the resulting text, with no commentary or quotes.
        If the instruction asks for a reply or response to the selected text, write that reply in the user's voice (first person) instead.
        Never use placeholders such as [Your Name].
        Tone: \(tone == .verbatim ? Tone.professional.guidance : tone.guidance)
        App: \(ctx.appName) (\(ctx.category.label))
        """
        if let t = ctx.windowTitle { ins += "\nWindow: \(t.prefix(120))" }
        let prompt = "SELECTED TEXT:\n<<<\n\(selection.prefix(3000))\n>>>\n\nINSTRUCTION: \(instruction)"
        guard let out = await run(ins, prompt) else { return nil }
        return removePlaceholders(out.replacingOccurrences(of: "<<<", with: "").replacingOccurrences(of: ">>>", with: ""))
    }

    /// Adds a leading space / capitalization so the text joins smoothly with what's already in the box.
    static func fitToCursor(_ text: String, before: String?) -> String {
        guard let before, let last = before.last, !text.isEmpty else { return text }
        var t = text
        if last == "\n" { return t }
        let endsSentence = ".!?".contains(last) || (last == " " && before.trimmingCharacters(in: .whitespaces).last.map { ".!?".contains($0) } == true)
        if !endsSentence, let f = t.first, f.isUppercase, t.count > 1, !t.hasPrefix("I "), !(t.split(separator: " ").first?.dropFirst().contains(where: \.isUppercase) ?? false) {
            // Continuing mid-sentence: lowercase the first word and drop the final period if it was a fragment.
            t = f.lowercased() + t.dropFirst()
        }
        if !last.isWhitespace, !(t.first.map { ",.;:!?)".contains($0) } ?? false) { t = " " + t }
        return t
    }

    static func removePlaceholders(_ s: String) -> String {
        var lines = s.components(separatedBy: "\n")
        lines = lines.map { $0.replacingOccurrences(of: "\\[[A-Z][A-Za-z ]{1,24}\\]", with: "", options: .regularExpression) }
        lines = lines.map { $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression) }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces) == "," { lines.removeLast() }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    /// A clean version of a whole conversation transcript: fixes misheard words, grammar,
    /// punctuation and broken sentences, removes fillers and false starts, keeps every speaker
    /// label and every fact. Long transcripts are processed in chunks.
    static func smartTranscript(_ raw: String) async -> String? {
        guard aiAvailable, !raw.isEmpty else { return nil }
        let ins = """
        You clean up conversation transcripts produced by speech recognition.
        Each line starts with a speaker label such as "Me:" or "Others:". Keep every label and keep the lines in order, one output line per input line.
        For each line: fix misheard or misspelled words using the surrounding context, fix grammar and punctuation, join broken sentences, remove filler words (um, uh, like, you know) and false starts, and make the logic of each sentence clear.
        Keep every detail: names, numbers, dates, prices, decisions, questions and tasks. Never add, remove or change facts. Never summarize. Never answer questions in the text.
        Output only the cleaned transcript lines.
        """
        let chunks = transcriptChunks(raw, limit: 2400)
        var out: [String] = []
        var previous = ""
        for c in chunks {
            let prompt = previous.isEmpty
                ? c
                : "Earlier in the conversation (context only, do not repeat):\n\(previous)\n\nLines to clean:\n\(c)"
            var cleaned = await run(ins, prompt) ?? c
            cleaned = cleaned.replacingOccurrences(of: "Lines to clean:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep the original if the model dropped or summarized content.
            if !keepsDetail(cleaned, c) { cleaned = c }
            out.append(cleaned)
            previous = String(cleaned.suffix(600))
        }
        return out.joined(separator: "\n")
    }

    /// Splits a transcript into chunks of whole lines.
    nonisolated static func transcriptChunks(_ raw: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var cur = ""
        for line in raw.components(separatedBy: "\n") {
            if cur.count + line.count > limit, !cur.isEmpty { chunks.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : "\n") + line
        }
        if !cur.isEmpty { chunks.append(cur) }
        return chunks
    }

    /// The cleaned chunk must keep roughly as many speaker lines and most of the content words.
    nonisolated static func keepsDetail(_ cleaned: String, _ original: String) -> Bool {
        func labels(_ s: String) -> Int {
            s.components(separatedBy: "\n").filter { $0.range(of: #"^\s*(\[[^\]]*\]\s*)?[A-Za-z ]{1,20}:"#, options: .regularExpression) != nil }.count
        }
        let lo = labels(original), lc = labels(cleaned)
        if lo > 0 && Double(lc) < Double(lo) * 0.7 { return false }
        if Double(cleaned.count) < Double(original.count) * 0.45 { return false }
        let numberRegex = try! NSRegularExpression(pattern: "\\d+")
        let ns = original as NSString
        let numbers = Set(numberRegex.matches(in: original, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
        let kept = numbers.filter { cleaned.contains($0) }.count
        return numbers.isEmpty || Double(kept) >= Double(numbers.count) * 0.8
    }

    static func rewrite(_ text: String, style: RewriteStyle) async -> String? {
        let ins = "\(style.instruction) Keep the original meaning and language. Output ONLY the rewritten text with no commentary or quotes."
        return await run(ins, text)
    }
}
