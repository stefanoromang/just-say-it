// Tests for meeting links and calendar parsing – created by Stefano Roman Gunness · MIT License

using Ical.Net;
using Ical.Net.CalendarComponents;
using Ical.Net.DataTypes;
using Ical.Net.Serialization;
using JustSayIt;

public class MeetingLinkTests
{
    [Theory]
    [InlineData("Join Zoom Meeting https://us06web.zoom.us/j/81234567890?pwd=AbC1.1 ID 812", MeetingPlatform.Zoom)]
    [InlineData("Join with Google Meet: https://meet.google.com/abc-defg-hij", MeetingPlatform.Meet)]
    [InlineData("Join: <https://teams.microsoft.com/l/meetup-join/19%3ameeting_X%40thread.v2/0?context=%7b%7d>", MeetingPlatform.Teams)]
    [InlineData("https://teams.live.com/meet/9876543210?p=xyz", MeetingPlatform.Teams)]
    public void FindsLinks(string text, MeetingPlatform expected) =>
        Assert.Equal(expected, MeetingLinks.Find(null, text)!.Platform);

    [Fact]
    public void IgnoresOtherLinks() =>
        Assert.Null(MeetingLinks.Find("Lunch at noon", "https://docs.google.com/document/d/1"));

    [Fact]
    public void TeamsLinkHasNoTrailingBracket() =>
        Assert.EndsWith("%7d", MeetingLinks.Find("<https://teams.microsoft.com/l/meetup-join/19%3ameeting_X%40thread.v2/0?context=%7b%7d>")!.Url);

    [Fact]
    public void ZoomOpensInApp() =>
        Assert.Equal("zoommtg://zoom.us/join?action=join&confno=123&pwd=x",
            MeetingLinks.AppUrl(MeetingLinks.Find("https://zoom.us/j/123?pwd=x")!));
}

/// Calendar parsing lives in AutoJoin (Windows-only); this checks the same Ical.Net usage.
public class CalendarParseTests
{
    static string BuildIcs(DateTime now)
    {
        var cal = new Calendar();
        cal.Events.Add(new CalendarEvent
        {
            Uid = "zoom1", Summary = "Design review",
            Start = new CalDateTime(now.AddHours(2).ToUniversalTime(), "UTC"), End = new CalDateTime(now.AddHours(3).ToUniversalTime(), "UTC"),
            Description = "Join Zoom https://zoom.us/j/111?pwd=a",
        });
        var weekly = new CalendarEvent
        {
            Uid = "teams1", Summary = "Weekly sync",
            Start = new CalDateTime(now.AddDays(-7).AddHours(5).ToUniversalTime(), "UTC"), End = new CalDateTime(now.AddDays(-7).AddHours(6).ToUniversalTime(), "UTC"),
            Location = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_W%40thread.v2/0",
        };
        weekly.RecurrenceRules.Add(new RecurrencePattern(FrequencyType.Weekly, 1));
        cal.Events.Add(weekly);
        cal.Events.Add(new CalendarEvent
        {
            Uid = "lunch", Summary = "Lunch",
            Start = new CalDateTime(now.AddHours(4).ToUniversalTime(), "UTC"), End = new CalDateTime(now.AddHours(5).ToUniversalTime(), "UTC"),
        });
        return new CalendarSerializer().SerializeToString(cal)!;
    }

    [Fact]
    public void FindsMeetingsIncludingRecurring()
    {
        var now = DateTime.Now;
        var cal = Calendar.Load(BuildIcs(now))!;
        var from = new CalDateTime(now.AddHours(-3).ToUniversalTime(), "UTC");
        var to = new CalDateTime(now.AddHours(36).ToUniversalTime(), "UTC");
        var found = cal.GetOccurrences<CalendarEvent>(from).TakeWhile(o => o.Period.StartTime.LessThan(to))
            .Select(o => (CalendarEvent)o.Source)
            .Where(e => MeetingLinks.Find(e.Url?.ToString(), e.Location, e.Description) != null)
            .Select(e => e.Summary).ToList();
        Assert.Contains("Design review", found);
        Assert.Contains("Weekly sync", found);
        Assert.DoesNotContain("Lunch", found);
    }
}

/// Live-call detection helpers (same logic as CallApps in the Windows app).
public class LiveCallTitleTests
{
    static MeetingPlatform? ForTitle(string title)
    {
        var t = title.ToLowerInvariant();
        if (t.StartsWith("meet - ") || t.StartsWith("meet – ") || t.Contains("google meet") || t.Contains("meet.google.com")) return MeetingPlatform.Meet;
        if (t.Contains("microsoft teams")) return MeetingPlatform.Teams;
        if (t.Contains("zoom meeting") || t.Contains("zoom workplace") || t.Contains("zoom webinar")) return MeetingPlatform.Zoom;
        return null;
    }

    [Theory]
    [InlineData("Meet - abc-defg-hij - Google Chrome", MeetingPlatform.Meet)]
    [InlineData("Weekly sync | Microsoft Teams", MeetingPlatform.Teams)]
    [InlineData("Zoom Meeting", MeetingPlatform.Zoom)]
    public void DetectsCallWindows(string title, MeetingPlatform expected) => Assert.Equal(expected, ForTitle(title));

    [Theory]
    [InlineData("Inbox (3) - Gmail - Google Chrome")]
    [InlineData("YouTube - Google Chrome")]
    public void IgnoresOtherWindows(string title) => Assert.Null(ForTitle(title));
}
