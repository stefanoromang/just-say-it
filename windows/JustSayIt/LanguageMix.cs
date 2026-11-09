// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

namespace JustSayIt;

/// Mixed-language speech: splits a recording at pauses, finds the language of each phrase among the
/// languages the user speaks, and joins neighbouring phrases in the same language. You never have
/// to say or switch which language you're speaking.
public static class LanguageMix
{
    public sealed record Piece(int Start, int Length, string Language);

    public const int Rate = 16000;

    /// Phrases of speech, split at pauses of 300 ms or more. Very short phrases join the one before.
    public static List<(int start, int len)> SplitAtPauses(float[] a)
    {
        int win = Rate / 50; // 20 ms
        var e = new List<double>();
        for (int i = 0; i + win <= a.Length; i += win)
        {
            double sum = 0;
            for (int j = i; j < i + win; j++) sum += a[j] * a[j];
            e.Add(Math.Sqrt(sum / win));
        }
        var res = new List<(int, int)>();
        if (e.Count == 0) return res;
        var sorted = e.OrderBy(x => x).ToList();
        double noise = sorted[(int)(sorted.Count * 0.1)], peak = sorted[Math.Min(sorted.Count - 1, (int)(sorted.Count * 0.95))];
        double thr = noise + (peak - noise) * 0.12;
        var parts = new List<(int, int)>();
        int segStart = -1, quiet = 0;
        for (int k = 0; k < e.Count; k++)
        {
            if (e[k] > thr) { if (segStart < 0) segStart = k; quiet = 0; }
            else if (segStart >= 0 && ++quiet >= 15) { parts.Add((segStart, k - quiet + 1)); segStart = -1; quiet = 0; }
        }
        if (segStart >= 0) parts.Add((segStart, e.Count));
        int pad = Rate * 15 / 100;
        foreach (var (a0, b0) in parts)
        {
            int st = Math.Max(0, a0 * win - pad), en = Math.Min(a.Length, b0 * win + pad);
            if (res.Count > 0 && (res[^1].Item2 < Rate * 12 / 10 || en - st < Rate * 6 / 10))
            {
                var p = res[^1];
                res[^1] = (p.Item1, en - p.Item1);
            }
            else res.Add((st, en - st));
        }
        return res;
    }

    /// Tags every phrase with its language (detect = the speech model's language detector, limited to
    /// the candidates) and merges neighbours in the same language. Phrases the detector isn't sure about
    /// keep the language around them.
    public static List<Piece> Tag(float[] samples, IReadOnlyList<string> langs,
                                  Func<float[], string[], (string? lang, float prob)> detect,
                                  IReadOnlyDictionary<string, double>? prior = null)
    {
        var cands = langs.ToArray();
        var phrases = SplitAtPauses(samples);
        if (phrases.Count == 0) phrases.Add((0, samples.Length));
        var tagged = new List<(int start, int len, string lang, float prob)>();
        foreach (var (st, len) in phrases)
        {
            // The detector works best on at least 3 seconds: pad short phrases with silence.
            var buf = new float[Math.Max(len, Rate * 3)];
            Array.Copy(samples, st, buf, 0, len);
            var (lang, prob) = detect(buf, cands);
            lang = string.IsNullOrEmpty(lang) || !cands.Contains(lang) ? cands[0] : lang;
            tagged.Add((st, len, lang, prob));
        }
        // Unsure phrases (below 0.6) follow their neighbours when both sides agree, or the language you use most.
        for (int i = 0; i < tagged.Count; i++)
        {
            if (tagged[i].prob >= 0.6) continue;
            string? before = i > 0 ? tagged[i - 1].lang : null, after = i + 1 < tagged.Count ? tagged[i + 1].lang : null;
            string? pick = before != null && before == after ? before : null;
            if (pick == null && prior != null && prior.Count > 0 && tagged[i].prob < 0.45)
                pick = cands.OrderByDescending(c => prior.TryGetValue(c, out var v) ? v : 0).First();
            if (pick != null) tagged[i] = (tagged[i].start, tagged[i].len, pick, tagged[i].prob);
        }
        var pieces = new List<Piece>();
        foreach (var t in tagged)
        {
            if (pieces.Count > 0 && pieces[^1].Language == t.lang)
            {
                var p = pieces[^1];
                pieces[^1] = p with { Length = t.start + t.len - p.Start };
            }
            else pieces.Add(new Piece(t.start, t.len, t.lang));
        }
        return pieces;
    }

    /// Joins phrases, adding a sentence break when one ends without punctuation and the next starts a sentence.
    public static string Join(IEnumerable<string> parts)
    {
        var sb = new System.Text.StringBuilder();
        foreach (var raw in parts)
        {
            var t = raw.Trim();
            if (t.Length == 0) continue;
            if (sb.Length > 0)
            {
                char last = sb[^1];
                if (!".!?…:;".Contains(last) && char.IsUpper(t[0])) sb.Append('.');
                sb.Append(' ');
            }
            sb.Append(t);
        }
        return sb.ToString();
    }
}
