using JustSayIt;

public class TranscriptTests
{
    [Fact]
    public void ImportsVttNamesAndEntities()
    {
        var rows = MeetingTranscript.Parse("WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n<v María Rossi>Hello &amp; welcome.</v>\n\n00:00:04.000 --> 00:00:05.000\n<v Stefano>Thank you.</v>");
        Assert.Equal(2, rows.Count);
        Assert.Equal("María Rossi", rows[0].Speaker);
        Assert.Equal("Hello & welcome.", rows[0].Text);
        Assert.Equal("Stefano", rows[1].Speaker);
    }

    [Theory]
    [InlineData("1\n00:00:01,000 --> 00:00:02,000\nAna: Hola.", "Ana", "Hola.")]
    [InlineData("Unattributed speech.", "Speaker", "Unattributed speech.")]
    public void DoesNotGuessNames(string input, string speaker, string text)
    {
        var row = Assert.Single(MeetingTranscript.Parse(input));
        Assert.Equal(speaker, row.Speaker); Assert.Equal(text, row.Text);
    }

    [Fact]
    public void RevisionsDoNotDuplicateOrMixMeetings()
    {
        var rows = new List<MeetingCaption>(); string? session = null;
        var row = new MeetingCaption("meet", "first", "1", "Ana", "Hello", 1);
        MeetingTranscript.Merge(new[] { row, row with { Text = "Hello everyone." }, row with { Session = "other" } }, rows, ref session);
        Assert.Single(rows); Assert.Equal("Hello everyone.", rows[0].Text);
        Assert.Equal("first", session);
    }

    [Fact]
    public void RejectsInvalidCaption()
    {
        Assert.False(new MeetingCaption("unknown", "x", "1", "Ana", "Hello", 1).Valid);
        Assert.False(new MeetingCaption("meet", "x", "1", "", "Hello", 1).Valid);
    }

    [Fact]
    public void LabelsBackupSeparately()
    {
        var result = MeetingTranscript.Combined("Me: local", new[] { new MeetingCaption("meet", "first", "1", "Ana", "Hola", 1) });
        Assert.Contains("Ana: Hola", result); Assert.Contains("LOCAL AUDIO BACKUP", result);
    }
}
