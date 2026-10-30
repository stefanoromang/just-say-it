// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Net.Http;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JustSayIt;

/// Turns a raw transcript into finished text. Fast rules always run; a local
/// Ollama model (free, offline) polishes when it is installed.
public static class TextBrain
{
    static readonly string[] Fillers = { "um", "umm", "uh", "uhh", "uh huh", "er", "erm", "ah", "hmm", "mm", "you know", "i mean", "sort of", "kind of like" };
    const RegexOptions I = RegexOptions.IgnoreCase;

    // MARK: Fast local rules

    public static string RuleClean(string input)
    {
        var s = " " + input + " ";
        foreach (var cmd in new[] { "scratch that", "delete that", "strike that", "never mind that" })
        {
            int idx;
            while ((idx = s.IndexOf(cmd, StringComparison.OrdinalIgnoreCase)) >= 0)
            {
                var before = s[..idx].TrimEnd();
                if (before.Length > 0 && ".!?,".Contains(before[^1])) before = before[..^1];
                int cut = before.LastIndexOfAny(new[] { '.', '!', '?', '\n' });
                var after = s[(idx + cmd.Length)..].TrimStart('.', ',', '!', '?', ' ');
                s = (cut >= 0 ? s[..(cut + 1)] : "") + " " + after;
            }
        }
        foreach (var f in Fillers)
            s = Regex.Replace(s, @"(?<![\p{L}'])" + Regex.Escape(f) + @"(?![\p{L}'])[,.]?", "", I);
        s = Regex.Replace(s, @"(?<=[,.]|^|\s)like,\s", " ", I);
        var spoken = new (string, string)[]
        {
            ("new paragraph", "\n\n"), ("new line", "\n"), ("next line", "\n"),
            ("question mark", "?"), ("exclamation point", "!"), ("exclamation mark", "!"),
            ("full stop", "."), ("comma", ","), ("colon", ":"), ("semicolon", ";"),
        };
        foreach (var (k, v) in spoken)
            s = Regex.Replace(s, @"\s*\b" + k + @"\b[,.]?\s*", v.StartsWith("\n") ? v : v + " ", I);
        s = Regex.Replace(s, @"\b(\w+)(\s+\1\b)+", "$1", I);
        s = Regex.Replace(s, @"[ \t]+", " ");
        s = Regex.Replace(s, @" +([,.!?;:])", "$1");
        s = Regex.Replace(s, @"([,.!?;:])(?=[A-Za-z])", "$1 ");
        s = Regex.Replace(s, @",+", ",");
        s = Regex.Replace(s, @"^[\s,.]+", "");
        s = Regex.Replace(s, @" *\n *", "\n");
        return CapitalizeSentences(s.Trim(' ', '\t'));
    }

    public static string CapitalizeSentences(string s)
    {
        var sb = new StringBuilder(s.Length);
        bool cap = true;
        foreach (var ch in s)
        {
            if (cap && char.IsLetter(ch)) { sb.Append(char.ToUpper(ch)); cap = false; continue; }
            sb.Append(ch);
            if (".!?\n".Contains(ch)) cap = true; else if (!char.IsWhiteSpace(ch)) cap = false;
        }
        return sb.ToString();
    }

    public static string ApplyReplacements(string s, IEnumerable<Replacement> reps, IEnumerable<string> vocab)
    {
        foreach (var r in reps.Where(r => r.Heard.Length > 0))
            s = Regex.Replace(s, @"\b" + Regex.Escape(r.Heard) + @"\b", r.Write.Replace("$", "$$"), I);
        foreach (var w in vocab.Where(w => w.Length > 0))
            s = Regex.Replace(s, @"\b" + Regex.Escape(w) + @"\b", w.Replace("$", "$$"), I);
        return s;
    }

    public static (string text, bool whole) ExpandSnippets(string s, IEnumerable<Snippet> snippets)
    {
        var norm = s.ToLowerInvariant().Trim().Trim('.', ',', '!', '?');
        foreach (var sn in snippets.Where(x => x.Trigger.Length > 0))
        {
            var t = sn.Trigger.ToLowerInvariant();
            if (norm == t || norm == "insert " + t) return (sn.Text, true);
        }
        foreach (var sn in snippets.Where(x => x.Trigger.Length > 0))
            s = Regex.Replace(s, @"\binsert\s+" + Regex.Escape(sn.Trigger) + @"\b[.,]?", sn.Text.Replace("$", "$$"), I);
        return (s, false);
    }

    public static bool LooksLikeEditCommand(string s)
    {
        var l = s.ToLowerInvariant();
        string[] starts = { "make it", "make this", "make that", "rewrite", "rephrase", "translate", "summarize", "shorten", "expand", "fix", "turn this", "turn it", "change", "convert", "reply", "respond", "answer", "improve", "add ", "remove", "format", "polish", "proofread" };
        return starts.Any(l.StartsWith) || l.Contains("this text") || l.Contains("the selected");
    }

    public static bool KeepsMeaning(string output, string input)
    {
        var stop = new HashSet<string> { "the", "a", "an", "and", "or", "to", "of", "is", "it", "i", "you", "so", "like", "um", "uh", "that", "this", "in", "on", "at", "for", "be", "we", "my" };
        HashSet<string> Words(string x) => Regex.Split(x.ToLowerInvariant(), @"[^\p{L}\p{N}']+")
            .Where(w => w.Length > 1 && !stop.Contains(w)).ToHashSet();
        var src = Words(input);
        if (src.Count < 2) return true;
        return (double)src.Intersect(Words(output)).Count() / src.Count >= 0.5;
    }

    public static string RemovePlaceholders(string s)
    {
        var lines = s.Split('\n').Select(l => Regex.Replace(l, @"\[[A-Z][A-Za-z ]{1,24}\]", "").TrimEnd()).ToList();
        while (lines.Count > 0 && (lines[^1].Trim().Length == 0 || lines[^1].Trim() == ",")) lines.RemoveAt(lines.Count - 1);
        return Regex.Replace(string.Join("\n", lines), @"\n{3,}", "\n\n");
    }

    public static string FitToCursor(string text, string? before)
    {
        if (string.IsNullOrEmpty(before) || text.Length == 0) return text;
        char last = before[^1];
        if (last == '\n') return text;
        var trimmed = before.TrimEnd();
        bool endsSentence = trimmed.Length > 0 && ".!?".Contains(trimmed[^1]);
        var t = text;
        if (!endsSentence && t.Length > 1 && char.IsUpper(t[0]) && !t.StartsWith("I "))
        {
            var first = t.Split(' ')[0];
            if (!first.Skip(1).Any(char.IsUpper)) t = char.ToLower(t[0]) + t[1..];
        }
        if (!char.IsWhiteSpace(last) && !",.;:!?)".Contains(t[0])) t = " " + t;
        return t;
    }

    // MARK: Local AI (Ollama)

    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };
    static DateTime lastCheck = DateTime.MinValue;
    static bool lastAvailable;

    public static async Task<bool> AiAvailable()
    {
        if ((DateTime.Now - lastCheck).TotalSeconds < 20) return lastAvailable;
        lastCheck = DateTime.Now;
        try
        {
            var p = Store.Shared.Prefs;
            using var cts = new CancellationTokenSource(1500);
            var json = await Http.GetStringAsync(p.OllamaUrl.TrimEnd('/') + "/api/tags", cts.Token);
            using var doc = JsonDocument.Parse(json);
            lastAvailable = doc.RootElement.GetProperty("models").EnumerateArray()
                .Any(m => (m.GetProperty("name").GetString() ?? "").StartsWith(p.OllamaModel.Split(':')[0]));
        }
        catch { lastAvailable = false; }
        return lastAvailable;
    }

    public static void ResetAiCheck() => lastCheck = DateTime.MinValue;

    static async Task<string?> Run(string instructions, string prompt)
    {
        if (!await AiAvailable()) return null;
        var p = Store.Shared.Prefs;
        try
        {
            var body = new
            {
                model = p.OllamaModel,
                stream = false,
                keep_alive = "30m",
                options = new { temperature = 0, num_ctx = 4096 },
                messages = new object[]
                {
                    new { role = "system", content = instructions },
                    new { role = "user", content = prompt },
                },
            };
            using var resp = await Http.PostAsJsonAsync(p.OllamaUrl.TrimEnd('/') + "/api/chat", body);
            resp.EnsureSuccessStatusCode();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            var text = doc.RootElement.GetProperty("message").GetProperty("content").GetString()?.Trim();
            return string.IsNullOrEmpty(text) ? null : StripWrapping(text);
        }
        catch { return null; }
    }

    /// Loads the model into memory so the first dictation is fast.
    public static async Task Prewarm()
    {
        if (!await AiAvailable()) return;
        var p = Store.Shared.Prefs;
        try { await Http.PostAsJsonAsync(p.OllamaUrl.TrimEnd('/') + "/api/generate", new { model = p.OllamaModel, keep_alive = "30m" }); } catch { }
    }

    static string StripWrapping(string t)
    {
        foreach (var pre in new[] { "Here is the cleaned text:", "Here's the cleaned text:", "Cleaned text:", "Output:", "Here is the rewritten text:", "Here is the formatted text:" })
            if (t.StartsWith(pre, StringComparison.OrdinalIgnoreCase)) t = t[pre.Length..];
        t = t.Replace("<<<", "").Replace(">>>", "").Trim();
        if (t.Length > 2 && t[0] == '"' && t[^1] == '"' && !t[1..^1].Contains('"')) t = t[1..^1];
        return t;
    }

    public static async Task<string?> Polish(string text, CaptureContext ctx, Tone tone, string? custom, List<string> vocab)
    {
        var ins = $"""
        You are a dictation formatter. The user spoke the text below and it was transcribed by speech recognition. Rewrite it as the finished text the user intended to type.
        Rules:
        - Remove filler words (um, uh, like, you know, I mean), stutters, and false starts.
        - When the speaker corrects themselves ("no wait", "actually", "I mean", "sorry", "or rather"), delete the wrong part and the correction phrase, keeping only the corrected version. Example: "meet on Tuesday no wait Wednesday" -> "meet on Wednesday".
        - Remove casual filler like "like", "so" at the start, and "you know"; "at like 3pm" -> "at 3 PM".
        - Fix punctuation, capitalization, and obvious recognition errors. Use the CONTEXT to spell names, people, companies and terms correctly.
        - When the speaker lists several items, format them as a list with "- " bullets, or numbers if they said first/second/third.
        - Keep the speaker's meaning and their own words, including hedges like "I think". Never add facts, greetings, or sign-offs they did not say.
        - The text is something the user is typing to someone else. If it contains a question or request, output the question itself, nicely formatted. Never answer it.
        - If the box already contains text, continue naturally from it (do not repeat it).
        - Output ONLY the final text, with no quotes or commentary.
        Tone: {Labels.Guidance(tone)}
        """;
        if (ctx.Category is AppCategory.Code or AppCategory.Ai) ins += "\nPreserve technical terms, code identifiers, file names and commands exactly.";
        if (vocab.Count > 0) ins += "\nAlways spell these terms exactly like this: " + string.Join(", ", vocab) + ".";
        if (!string.IsNullOrWhiteSpace(custom)) ins += "\nUser style preference: " + custom;
        ins += "\n\nCONTEXT (for spelling and tone only; never copy it into the output):\n" + ctx.PromptBlock();
        var output = await Run(ins, $"Dictated text to format (do not answer it):\n<<<\n{text}\n>>>");
        return output != null && KeepsMeaning(output, text) ? output : null;
    }

    public static async Task<string?> Scribe(string text, CaptureContext ctx, Tone tone, string? custom)
    {
        var ins = $"""
        You are a ghostwriter. The user spoke rough notes or an instruction describing a message they want to send. Write the complete, polished message for them, ready to send, in their voice (first person).
        - Follow the instruction's intent; include every point they mentioned and do not invent specifics (names, dates, numbers) they did not give.
        - Use the CONTEXT to understand what they are replying to: address the right person by name and refer to the right topic when it is clear.
        - Output ONLY the message text, with no preamble, no quotes and no subject line unless asked.
        - Never use placeholders such as [Your Name], [Date] or [Company]. If the user's name is unknown, end without a name.
        Tone: {Labels.Guidance(tone == Tone.Verbatim ? Tone.Professional : tone)}
        """;
        if (ctx.Category == AppCategory.Email) ins += "\nFormat as an email body with a short greeting and sign-off when appropriate.";
        if (!string.IsNullOrWhiteSpace(custom)) ins += "\nUser style preference: " + custom;
        ins += "\n\nCONTEXT:\n" + ctx.PromptBlock();
        var output = await Run(ins, "User's instruction:\n" + text);
        return output == null ? null : RemovePlaceholders(output);
    }

    public static async Task<string?> EditSelection(string selection, string instruction, CaptureContext ctx, Tone tone)
    {
        var ins = $"""
        You edit text for the user. Apply the user's spoken instruction to the SELECTED TEXT and output only the resulting text, with no commentary or quotes.
        If the instruction asks for a reply or response to the selected text, write that reply in the user's voice (first person) instead.
        Never use placeholders such as [Your Name].
        Tone: {Labels.Guidance(tone == Tone.Verbatim ? Tone.Professional : tone)}
        App: {ctx.AppName} ({Labels.Of(ctx.Category)})
        """;
        var sel = selection.Length > 3000 ? selection[..3000] : selection;
        var output = await Run(ins, $"SELECTED TEXT:\n<<<\n{sel}\n>>>\n\nINSTRUCTION: {instruction}");
        return output == null ? null : RemovePlaceholders(output);
    }

    /// A clean version of a whole conversation transcript: fixes misheard words, grammar and
    /// broken sentences, removes fillers, keeps every speaker label and fact. Processed in chunks.
    public static async Task<string?> SmartTranscript(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || !await AiAvailable()) return null;
        const string ins = """
            You clean up conversation transcripts produced by speech recognition.
            Each line starts with a speaker label such as "Me:" or "Others:". Keep every label and keep the lines in order.
            For each line: fix misheard or misspelled words using the surrounding context, fix grammar and punctuation, join broken sentences, remove filler words (um, uh, like, you know) and false starts, and make the logic of each sentence clear.
            Never add, remove or change facts, names, numbers, dates or decisions. Never summarize. Never answer questions in the text.
            Output only the cleaned transcript lines.
            """;
        var chunks = new List<string>();
        var cur = new StringBuilder();
        foreach (var line in raw.Split('\n'))
        {
            if (cur.Length + line.Length > 2500 && cur.Length > 0) { chunks.Add(cur.ToString()); cur.Clear(); }
            if (cur.Length > 0) cur.Append('\n');
            cur.Append(line);
        }
        if (cur.Length > 0) chunks.Add(cur.ToString());
        var outp = new List<string>();
        foreach (var c in chunks) outp.Add(await Run(ins, c) ?? c);
        return string.Join("\n", outp);
    }

    public static Task<string?> SummarizeMeeting(string transcript) => Run("""
        You write meeting notes from a transcript. Lines starting with "Me:" are the user; "Others:" is everyone else.
        Write in Markdown with exactly these sections:
        ## Summary
        (3–5 sentences)
        ## Key points
        (bullets)
        ## Decisions
        (bullets, or "None")
        ## Action items
        (bullets as "- [ ] who – what – when", or "None")
        List every task anyone agreed to do as an action item, including tasks for people other than the speaker.
        Use only information from the transcript. Do not invent names, dates or numbers.
        """, transcript);

    public static Task<string?> Rewrite(string text, RewriteStyle style) =>
        Run($"{Labels.Instruction(style)} Keep the original meaning and language. Output ONLY the rewritten text with no commentary or quotes.", text);
}
