// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text.RegularExpressions;

namespace JustSayIt;

public enum MeetingPlatform { Zoom, Meet, Teams }

public record MeetingLink(MeetingPlatform Platform, string Url);

/// Finds Zoom / Google Meet / Microsoft Teams join links in calendar text.
public static class MeetingLinks
{
    static readonly (MeetingPlatform, Regex)[] Patterns =
    {
        (MeetingPlatform.Zoom, new(@"https://(?:[\w-]+\.)?zoom\.us/(?:j|my|w|s)/[\w?=.&%-]+", RegexOptions.IgnoreCase)),
        (MeetingPlatform.Zoom, new(@"https://(?:[\w-]+\.)?zoomgov\.com/j/[\w?=.&%-]+", RegexOptions.IgnoreCase)),
        (MeetingPlatform.Meet, new(@"https://meet\.google\.com/[a-z]{3,4}-[a-z]{3,4}-[a-z]{3,4}(?:\?[\w=&%.-]*)?", RegexOptions.IgnoreCase)),
        (MeetingPlatform.Teams, new(@"https://teams\.microsoft\.com/l/meetup-join/[^\s""<>]+", RegexOptions.IgnoreCase)),
        (MeetingPlatform.Teams, new(@"https://teams\.live\.com/meet/[\w?=&%-]+", RegexOptions.IgnoreCase)),
        (MeetingPlatform.Teams, new(@"https://teams\.microsoft\.com/meet/[\w?=&%-]+", RegexOptions.IgnoreCase)),
    };

    public static string Name(MeetingPlatform p) => p switch
    {
        MeetingPlatform.Zoom => "Zoom",
        MeetingPlatform.Meet => "Google Meet",
        _ => "Microsoft Teams",
    };

    public static MeetingLink? Find(params string?[] texts)
    {
        foreach (var text in texts)
        {
            if (string.IsNullOrEmpty(text)) continue;
            foreach (var (platform, rx) in Patterns)
            {
                var m = rx.Match(text);
                if (m.Success) return new MeetingLink(platform, m.Value.TrimEnd('.', ',', ';', ')', '>', ']'));
            }
        }
        return null;
    }

    /// Opens Zoom meetings directly in the Zoom app (skips the browser page).
    public static string AppUrl(MeetingLink link)
    {
        if (link.Platform != MeetingPlatform.Zoom || !Uri.TryCreate(link.Url, UriKind.Absolute, out var u)) return link.Url;
        var parts = u.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || parts[0] != "j") return link.Url;
        var q = System.Web.HttpUtility.ParseQueryString(u.Query);
        var url = $"zoommtg://{u.Host}/join?action=join&confno={parts[1]}";
        if (!string.IsNullOrEmpty(q["pwd"])) url += "&pwd=" + Uri.EscapeDataString(q["pwd"]!);
        return url;
    }
}
