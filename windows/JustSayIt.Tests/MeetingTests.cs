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

/// Live-call detection (the app's CallApps list).
public class LiveCallTests
{
    [Theory]
    [InlineData("Meet - abc-defg-hij - Google Chrome", "meet")]
    [InlineData("Weekly sync | Microsoft Teams", "teams")]
    [InlineData("Zoom Meeting", "zoom")]
    [InlineData("Standup - Webex - Google Chrome", "webex")]
    [InlineData("Huddle with Ana - Slack", "slack")]
    [InlineData("MyStandup | Jitsi Meet - Microsoft Edge", "jitsi")]
    [InlineData("stefano-room | Whereby - Google Chrome", "whereby")]
    [InlineData("Zoho Meeting - Google Chrome", "zoho")]
    [InlineData("GoTo Meeting - Brave", "goto")]
    public void DetectsCallWindows(string title, string expected) => Assert.Equal(expected, CallApps.ServiceForTitle(title)?.Id);

    [Theory]
    [InlineData("Inbox (3) - Gmail - Google Chrome")]
    [InlineData("YouTube - Google Chrome")]
    [InlineData("Signal - Google Chrome")]
    public void IgnoresOtherWindows(string title) => Assert.Null(CallApps.ServiceForTitle(title));

    [Theory]
    [InlineData(@"C:\Users\a\AppData\Local\Microsoft\WindowsApps\MSTeams_8wekyb3d8bbwe\ms-teams.exe", "teams")]
    [InlineData("MSTeams_8wekyb3d8bbwe", "teams")]
    [InlineData(@"C:\Users\a\AppData\Roaming\Zoom\bin\Zoom.exe", "zoom")]
    [InlineData(@"C:\Program Files\Cisco Spark\CiscoCollabHost.exe", "webex")]
    [InlineData(@"C:\Users\a\AppData\Local\slack\app-4.41.105\slack.exe", "slack")]
    [InlineData(@"C:\Users\a\AppData\Local\Discord\app-1.0.9\Discord.exe", "discord")]
    [InlineData("Microsoft.SkypeApp_kzf8qxf38zg5c", "skype")]
    [InlineData(@"C:\Program Files\RingCentral\RingCentral.exe", "ringcentral")]
    [InlineData(@"C:\Users\a\AppData\Local\GoTo\GoTo.exe", "goto")]
    [InlineData(@"C:\Users\a\AppData\Local\Programs\signal-desktop\Signal.exe", "signal")]
    [InlineData("5319275A.WhatsAppDesktop_cv1g1gvanyjgm", "whatsapp")]
    [InlineData(@"C:\Users\a\AppData\Roaming\Telegram Desktop\Telegram.exe", "telegram")]
    [InlineData(@"C:\Users\a\AppData\Local\Programs\Jitsi Meet\Jitsi Meet.exe", "jitsi")]
    public void DetectsCallApps(string exe, string expected) => Assert.Equal(expected, CallApps.Service(exe)?.Id);

    [Theory]
    [InlineData(@"C:\Program Files\Google\Chrome\Application\chrome.exe")]
    [InlineData(@"C:\Windows\System32\SoundRecorder.exe")]
    [InlineData(@"C:\Program Files\Spotify\Spotify.exe")]
    public void NonCallAppsAreIgnored(string exe) => Assert.Null(CallApps.Service(exe));

    [Fact]
    public void AllSixteenApps() => Assert.True(CallApps.Services.Length >= 16 && CallApps.Services.Select(s => s.Id).Distinct().Count() == CallApps.Services.Length);

    [Fact]
    public void CleansTitles()
    {
        Assert.Equal("abc-defg-hij", CallApps.CleanTitle("Meet - abc-defg-hij - Google Chrome", CallApps.ById("meet")!));
        Assert.Equal("Weekly sync", CallApps.CleanTitle("Weekly sync | Microsoft Teams", CallApps.ById("teams")!));
        Assert.Equal("Zoom call", CallApps.CleanTitle("Zoom Workplace", CallApps.ById("zoom")!));
    }

    [Fact]
    public void ServiceToggles()
    {
        var p = new Prefs();
        Assert.True(p.IsCallServiceEnabled("discord"));
        p.SetCallServiceEnabled("discord", false);
        p.SetCallServiceEnabled("teams", false);
        Assert.False(p.IsCallServiceEnabled("discord"));
        Assert.False(p.IsCallServiceEnabled("teams"));
        Assert.False(p.RecordTeamsCalls);
        p.SetCallServiceEnabled("discord", true);
        Assert.True(p.IsCallServiceEnabled("discord"));
        Assert.True(p.CiqAutoSend);
        Assert.Equal("both", p.CiqAutoWhat);
        Assert.Equal("ddr", p.CiqAutoWhere);
    }
}

public class SmartTranscriptTests
{
    const string Original = "Me: um so the budget is like 4500 dollars\nOthers: ok and the deadline is march 12\nMe: yeah we ship 3 units";

    [Fact]
    public void KeepsGoodCleanup() => Assert.True(TextBrain.KeepsDetail(
        "Me: So the budget is 4,500 dollars.\nOthers: OK, and the deadline is March 12.\nMe: Yes, we ship 3 units.".Replace("4,500", "4500"), Original));

    [Fact]
    public void RejectsSummary() => Assert.False(TextBrain.KeepsDetail("They discussed the budget and deadline.", Original));

    [Fact]
    public void RejectsLostNumbers() => Assert.False(TextBrain.KeepsDetail(
        "Me: So the budget is a few thousand dollars.\nOthers: OK, and the deadline is in March.\nMe: Yes, we ship some units.", Original));

    [Fact]
    public void ChunksKeepWholeLines()
    {
        var raw = string.Join("\n", Enumerable.Range(1, 200).Select(i => $"Me: line number {i} with some words in it"));
        var chunks = TextBrain.TranscriptChunks(raw, 2400);
        Assert.True(chunks.Count > 1);
        Assert.All(chunks, c => Assert.True(c.Length <= 2400));
        Assert.Equal(raw, string.Join("\n", chunks));
    }
}
