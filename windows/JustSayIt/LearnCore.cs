// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

namespace JustSayIt;

/// What Just Say It has learned about how you speak and write. Stays on this PC.
public class Learning
{
    public Dictionary<string, int> LanguageCounts { get; set; } = new();
    public Dictionary<string, Dictionary<string, int>> Corrections { get; set; } = new();
    public Dictionary<string, int> Terms { get; set; } = new();
    public Dictionary<string, List<string>> Examples { get; set; } = new();
    public int Dictations { get; set; }
    public int Edits { get; set; }
}

/// Learns from every dictation and correction (same rules as the Mac app):
/// languages you use most, words you correct (automatic after two identical fixes),
/// names and terms, and your writing style per kind of app.
public static class LearnCore
{
    static readonly HashSet<string> Common = new() { "i", "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for", "is", "it",
        "el", "la", "los", "las", "de", "y", "o", "que", "en", "un", "una", "e", "il", "lo", "di", "da" };

    public static List<string> Tokens(string s) =>
        s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Select(t => t.Trim(".,;:!?¿¡\"'()[]".ToCharArray())).Where(t => t.Length > 0).ToList();

    /// Short word replacements (1–3 words) between what was written and what you changed it to.
    public static List<(string from, string to)> Substitutions(string original, string edited)
    {
        var a = Tokens(original); var b = Tokens(edited);
        var outp = new List<(string, string)>();
        if (a.Count == 0 || b.Count == 0 || a.Count >= 400 || b.Count >= 400) return outp;
        var la = a.Select(x => x.ToLowerInvariant()).ToList(); var lb = b.Select(x => x.ToLowerInvariant()).ToList();
        var dp = new int[a.Count + 1, b.Count + 1];
        for (int i = a.Count - 1; i >= 0; i--)
            for (int j = b.Count - 1; j >= 0; j--)
                dp[i, j] = la[i] == lb[j] ? dp[i + 1, j + 1] + 1 : Math.Max(dp[i + 1, j], dp[i, j + 1]);
        var gapA = new List<string>(); var gapB = new List<string>();
        void Flush()
        {
            if (gapA.Count > 0 && gapB.Count > 0 && gapA.Count <= 3 && gapB.Count <= 3)
                outp.Add((string.Join(" ", gapA), string.Join(" ", gapB)));
            gapA.Clear(); gapB.Clear();
        }
        int x = 0, y = 0;
        while (x < a.Count || y < b.Count)
        {
            if (x < a.Count && y < b.Count && la[x] == lb[y])
            {
                Flush();
                if (a[x] != b[y] && char.IsUpper(b[y][0])) outp.Add((a[x], b[y]));
                x++; y++;
            }
            else if (y < b.Count && (x == a.Count || dp[x, y + 1] >= dp[x + 1, y])) gapB.Add(b[y++]);
            else gapA.Add(a[x++]);
        }
        Flush();
        int changed = outp.Sum(p => p.Item1.Split(' ').Length);
        return changed > Math.Max(4, a.Count / 3) ? new() : outp;
    }

    public static List<(string heard, string write)> LearnedFixes(Learning l, int minimum = 2) =>
        l.Corrections.Select(kv => (kv.Key, best: kv.Value.OrderByDescending(v => v.Value).FirstOrDefault()))
            .Where(t => t.best.Value >= minimum).Select(t => (t.Key, t.best.Key)).OrderBy(t => t.Item1).ToList();

    public static List<string> LearnedTerms(Learning l, int limit = 60) =>
        l.Terms.OrderByDescending(t => t.Value).ThenBy(t => t.Key).Take(limit).Select(t => t.Key).ToList();

    public static Dictionary<string, double> LanguagePrior(Learning l)
    {
        double total = l.LanguageCounts.Values.Sum();
        return total < 5 ? new() : l.LanguageCounts.ToDictionary(k => k.Key, k => k.Value / total);
    }

    public static void Learn(Learning l, string original, string edited)
    {
        var subs = Substitutions(original, edited);
        if (subs.Count == 0) return;
        l.Edits++;
        foreach (var (from, to) in subs)
        {
            var key = from.ToLowerInvariant();
            if (!l.Corrections.TryGetValue(key, out var d)) l.Corrections[key] = d = new();
            d[to] = d.GetValueOrDefault(to) + 1;
            foreach (var w in to.Split(' '))
                if (w.Length > 1 && (char.IsUpper(w[0]) || w.Any(char.IsDigit)) && !Common.Contains(w.ToLowerInvariant()))
                    l.Terms[w] = l.Terms.GetValueOrDefault(w) + 1;
        }
        if (l.Corrections.Count > 400)
            l.Corrections = l.Corrections.OrderByDescending(c => c.Value.Values.Max()).Take(300).ToDictionary(c => c.Key, c => c.Value);
    }

    public static void Remember(Learning l, string example, string category)
    {
        var t = example.Trim();
        if (t.Length < 25 || t.Length > 600) return;
        if (!l.Examples.TryGetValue(category, out var list)) l.Examples[category] = list = new();
        list.Remove(t);
        list.Insert(0, t);
        if (list.Count > 5) list.RemoveRange(5, list.Count - 5);
    }

    public static string? StyleBlock(Learning l, string category, int maxChars = 700)
    {
        if (!l.Examples.TryGetValue(category, out var ex) || ex.Count == 0) return null;
        var sb = new System.Text.StringBuilder(); int used = 0;
        foreach (var e in ex) { if (used + e.Length > maxChars) continue; sb.Append("- ").Append(e).Append('\n'); used += e.Length; }
        return sb.Length == 0 ? null : sb.ToString();
    }
}

