// Tests for Just Say It's text cleanup – created by Stefano Roman Gunness · MIT License

using JustSayIt;

public class RuleCleanTests
{
    [Theory]
    [InlineData("um so I think we should uh meet tomorrow", "So I think we should meet tomorrow")]
    [InlineData("I was like, going to the store", "I was going to the store")]
    [InlineData("you know it works", "It works")]
    [InlineData("the the report is ready", "The report is ready")]
    public void RemovesFillersAndRepeats(string input, string expected) =>
        Assert.Equal(expected, TextBrain.RuleClean(input));

    [Fact]
    public void ScratchThatDropsPreviousSentence() =>
        Assert.Equal("Send it Monday",
            TextBrain.RuleClean("send it friday. scratch that. send it Monday"));

    [Fact]
    public void ScratchThatAtStartKeepsTheRest() =>
        Assert.Equal("Hello there", TextBrain.RuleClean("scratch that hello there"));

    [Theory]
    [InlineData("hello comma how are you question mark", "Hello, how are you?")]
    [InlineData("first line new line second line", "First line\nSecond line")]
    [InlineData("intro new paragraph body", "Intro\n\nBody")]
    public void SpokenPunctuationAndLayout(string input, string expected) =>
        Assert.Equal(expected, TextBrain.RuleClean(input));

    [Fact]
    public void CapitalizesSentences() =>
        Assert.Equal("One. Two! Three?", TextBrain.CapitalizeSentences("one. two! three?"));
}

public class DictionaryAndSnippetTests
{
    [Fact]
    public void ReplacementsAndVocabularyCasing()
    {
        var reps = new[] { new Replacement { Heard = "cloud code", Write = "Claude Code" } };
        var output = TextBrain.ApplyReplacements("i use cloud code and kubernetes", reps, new[] { "Kubernetes" });
        Assert.Equal("i use Claude Code and Kubernetes", output);
    }

    [Fact]
    public void ReplacementWithDollarSignIsLiteral()
    {
        var reps = new[] { new Replacement { Heard = "price", Write = "$5" } };
        Assert.Equal("the $5 is fine", TextBrain.ApplyReplacements("the price is fine", reps, Array.Empty<string>()));
    }

    [Fact]
    public void WholeUtteranceSnippet()
    {
        var sn = new[] { new Snippet { Trigger = "my address", Text = "1 Main St" } };
        Assert.Equal(("1 Main St", true), TextBrain.ExpandSnippets("My address.", sn));
    }

    [Fact]
    public void InlineSnippet()
    {
        var sn = new[] { new Snippet { Trigger = "my link", Text = "https://x.y" } };
        var (text, whole) = TextBrain.ExpandSnippets("here it is insert my link thanks", sn);
        Assert.False(whole);
        Assert.Equal("here it is https://x.y thanks", text);
    }
}

public class HelperTests
{
    [Theory]
    [InlineData("make this shorter", true)]
    [InlineData("translate to Spanish", true)]
    [InlineData("reply saying yes", true)]
    [InlineData("I will be there at noon", false)]
    public void DetectsEditCommands(string s, bool expected) =>
        Assert.Equal(expected, TextBrain.LooksLikeEditCommand(s));

    [Fact]
    public void KeepsMeaningRejectsAnswers() =>
        Assert.False(TextBrain.KeepsMeaning("Paris", "What's the capital of France"));

    [Fact]
    public void KeepsMeaningAcceptsCleanup() =>
        Assert.True(TextBrain.KeepsMeaning("I think we should meet on Wednesday at 3 PM.", "I think we should meet on Tuesday no wait Wednesday at 3pm"));

    [Fact]
    public void RemovesPlaceholders() =>
        Assert.Equal("Hi John,\n\nThanks!\n\nBest regards,",
            TextBrain.RemovePlaceholders("Hi John,\n\nThanks!\n\nBest regards,\n[Your Name]"));

    [Theory]
    [InlineData("Thanks a lot.", "Great talking to you. ", "Thanks a lot.")]
    [InlineData("Thanks a lot.", "I wanted to say", " thanks a lot.")]
    [InlineData("I agree.", "Well", " I agree.")]
    [InlineData("Hello.", null, "Hello.")]
    public void FitsToCursor(string text, string? before, string expected) =>
        Assert.Equal(expected, TextBrain.FitToCursor(text, before));
}
