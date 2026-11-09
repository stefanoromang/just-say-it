// Just Say It – created by Stefano Roman Gunness · MIT License

using JustSayIt;

/// Mixed-language dictation and learning (same code as the Windows app).
public class LanguageMixTests
{
    static float[] Tone(double seconds, double amp = 0.3)
    {
        var a = new float[(int)(seconds * LanguageMix.Rate)];
        for (int i = 0; i < a.Length; i++) a[i] = (float)(amp * Math.Sin(i * 2 * Math.PI * 220 / LanguageMix.Rate));
        return a;
    }
    static float[] Silence(double seconds) => new float[(int)(seconds * LanguageMix.Rate)];

    [Fact]
    public void SplitsPhrasesAtPauses()
    {
        var audio = Tone(2).Concat(Silence(0.6)).Concat(Tone(2.5)).Concat(Silence(0.6)).Concat(Tone(1.5)).ToArray();
        var parts = LanguageMix.SplitAtPauses(audio);
        Assert.Equal(3, parts.Count);
    }

    [Fact]
    public void ShortGapsDoNotSplit()
    {
        var audio = Tone(2).Concat(Silence(0.1)).Concat(Tone(2)).ToArray();
        Assert.Single(LanguageMix.SplitAtPauses(audio));
    }

    [Fact]
    public void TagsEachPhraseAndMergesNeighbours()
    {
        // en (2s) · es (2.5s) · es (2s) · en (1.5s)
        var audio = Tone(2).Concat(Silence(0.6)).Concat(Tone(2.5, 0.31)).Concat(Silence(0.6)).Concat(Tone(2, 0.32)).Concat(Silence(0.6)).Concat(Tone(1.5, 0.33)).ToArray();
        var answers = new Queue<(string?, float)>(new[] { ("en", 0.9f), ("es", 0.95f), ("es", 0.9f), ("en", 0.8f) });
        var pieces = LanguageMix.Tag(audio, new[] { "en", "es" }, (_, _) => answers.Dequeue()!);
        Assert.Equal(new[] { "en", "es", "en" }, pieces.Select(p => p.Language));
        Assert.InRange(pieces[^1].Start + pieces[^1].Length, audio.Length - 3200, audio.Length);
    }

    [Fact]
    public void UnsurePhraseFollowsNeighbours()
    {
        var audio = Tone(2).Concat(Silence(0.6)).Concat(Tone(2)).Concat(Silence(0.6)).Concat(Tone(2)).ToArray();
        var answers = new Queue<(string?, float)>(new[] { ("es", 0.9f), ("en", 0.4f), ("es", 0.9f) });
        var pieces = LanguageMix.Tag(audio, new[] { "en", "es" }, (_, _) => answers.Dequeue()!);
        Assert.Single(pieces);
        Assert.Equal("es", pieces[0].Language);
    }

    [Fact]
    public void UnknownAnswerFallsBackToMainLanguage()
    {
        var pieces = LanguageMix.Tag(Tone(2), new[] { "en", "es" }, (_, _) => ("fr", 0.9f));
        Assert.Equal("en", pieces[0].Language);
    }

    [Fact]
    public void JoinAddsSentenceBreaks() =>
        Assert.Equal("I wanted to confirm Thursday. Necesito el presupuesto. Thanks", LanguageMix.Join(new[] { "I wanted to confirm Thursday", "Necesito el presupuesto.", " Thanks " }));

    [Fact]
    public void SpokenLanguages()
    {
        var p = new Prefs { Language = "en", Languages = new() { "es", "en", "pt", "it", "fr" } };
        Assert.Equal(new[] { "en", "es", "pt", "it" }, p.SpokenLanguages());
        Assert.Empty(new Prefs { Language = "auto" }.SpokenLanguages());
    }
}

public class LearningTests
{
    [Fact]
    public void LearnsNameAndCasingFixes()
    {
        var subs = LearnCore.Substitutions("Please send it to Mark at Acme by Friday", "Please send it to Marc at ACME by Friday");
        Assert.Contains(("Mark", "Marc"), subs);
        Assert.Contains(("Acme", "ACME"), subs);
    }

    [Fact]
    public void IgnoresBigRewrites() =>
        Assert.Empty(LearnCore.Substitutions("can you send me the report", "Kindly forward the quarterly summary document to me at your earliest convenience"));

    [Fact]
    public void TwoCorrectionsBecomeAutomatic()
    {
        var l = new Learning();
        LearnCore.Learn(l, "Talk to Mark tomorrow", "Talk to Marc tomorrow");
        Assert.Empty(LearnCore.LearnedFixes(l));
        LearnCore.Learn(l, "Mark said yes", "Marc said yes");
        Assert.Contains(("mark", "Marc"), LearnCore.LearnedFixes(l));
        Assert.Contains("Marc", LearnCore.LearnedTerms(l));
    }

    [Fact]
    public void LanguagePriorAndStyle()
    {
        var l = new Learning();
        l.LanguageCounts["en"] = 8; l.LanguageCounts["es"] = 2;
        Assert.Equal(0.8, LearnCore.LanguagePrior(l)["en"], 3);
        LearnCore.Remember(l, "Hi team, the launch moves to Monday. Thanks!", "Work");
        Assert.Contains("launch moves", LearnCore.StyleBlock(l, "Work"));
    }
}

public class CiqRouteTests
{
    [Theory]
    [InlineData("route:notetaker:Notetaker", "notetaker", "Notetaker", true)]
    [InlineData("route:assistant:Ana – Assistant", "assistant", "Ana – Assistant", false)]
    [InlineData("route:none", "chat", null, false)]
    public void ParsesRoutes(string r, string kind, string? name, bool raw)
    {
        var route = CiqRoute.Route.Parse(r)!;
        Assert.Equal(kind, route.Kind);
        Assert.Equal(name, route.Destination.Ddr);
        Assert.Equal(raw, route.SendsRaw);
    }

    [Fact]
    public void IgnoresOtherResults()
    {
        Assert.Null(CiqRoute.Route.Parse("wait"));
        Assert.Null(CiqRoute.Route.Parse("login"));
    }

    [Fact]
    public void ChatUsesGeminiAndNemotron() => Assert.Equal(new[] { "Gemini", "Nemotron" }, CiqRoute.ChatModels);
}
