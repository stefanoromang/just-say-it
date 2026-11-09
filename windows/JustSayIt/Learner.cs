// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text.Json;

namespace JustSayIt;

/// Saves and applies what was learned.
public sealed class Learner
{
    public static Learner Shared { get; } = new();
    public Learning Data { get; private set; } = new();
    public event Action? Changed;
    readonly object gate = new();
    static string PathFile => System.IO.Path.Combine(Store.Dir, "learning.json");

    Learner()
    {
        try { if (File.Exists(PathFile)) Data = JsonSerializer.Deserialize<Learning>(File.ReadAllText(PathFile)) ?? new(); } catch { }
        Data.LanguageCounts ??= new(); Data.Corrections ??= new(); Data.Terms ??= new(); Data.Examples ??= new();
    }

    static bool Enabled => Store.Shared.Prefs.LearningEnabled;

    void Save()
    {
        try { File.WriteAllText(PathFile, JsonSerializer.Serialize(Data)); } catch { }
        Changed?.Invoke();
    }

    public void Dictated(string text, IEnumerable<string> languages, AppCategory c)
    {
        if (!Enabled) return;
        lock (gate)
        {
            Data.Dictations++;
            foreach (var l in languages) Data.LanguageCounts[l] = Data.LanguageCounts.GetValueOrDefault(l) + 1;
            LearnCore.Remember(Data, text, c.ToString());
            Save();
        }
    }

    public void Corrected(string original, string edited, AppCategory c)
    {
        if (!Enabled || original == edited) return;
        lock (gate) { LearnCore.Learn(Data, original, edited); LearnCore.Remember(Data, edited, c.ToString()); Save(); }
    }

    public Dictionary<string, double> LanguagePrior() { lock (gate) return Enabled ? LearnCore.LanguagePrior(Data) : new(); }
    public List<Replacement> Fixes { get { lock (gate) return Enabled ? LearnCore.LearnedFixes(Data).Select(f => new Replacement { Heard = f.heard, Write = f.write }).ToList() : new(); } }
    public List<string> Terms { get { lock (gate) return Enabled ? LearnCore.LearnedTerms(Data) : new(); } }
    public string? Style(AppCategory c) { lock (gate) return Enabled ? LearnCore.StyleBlock(Data, c.ToString()) : null; }

    public void ForgetAll() { lock (gate) { Data = new(); Save(); } }
}
