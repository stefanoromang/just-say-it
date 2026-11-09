// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text.RegularExpressions;

namespace JustSayIt;

/// A call app Just Say It recognises: Windows executables / Store packages and browser window titles.
public sealed record CallService(string Id, string Name, string[] ExeNames, string[] PackageHints, string[] TitleHints, bool Web);

/// Every supported call app (same list as the Mac app).
public static class CallApps
{
    public static readonly CallService[] Services =
    {
        new("teams", "Microsoft Teams", new[] { "ms-teams", "teams", "msteams" }, new[] { "msteams_", "microsoftteams" }, new[] { "microsoft teams" }, true),
        new("meet", "Google Meet", Array.Empty<string>(), Array.Empty<string>(), new[] { "google meet", "meet.google.com" }, true),
        new("zoom", "Zoom", new[] { "zoom", "cpthost" }, new[] { "zoom.us", "\\zoom\\bin\\" }, new[] { "zoom meeting", "zoom workplace", "zoom webinar" }, true),
        new("facetime", "FaceTime", Array.Empty<string>(), Array.Empty<string>(), new[] { "facetime" }, true),
        new("webex", "Cisco Webex", new[] { "webex", "ciscocollabhost", "atmgr", "webexmta", "ptoneclk" }, new[] { "\\webex\\", "cisco.webex" }, new[] { "webex" }, true),
        new("slack", "Slack (Huddles)", new[] { "slack" }, new[] { "slacktechnologies.slack", "91750d7e.slack" }, new[] { "huddle" }, true),
        new("discord", "Discord", new[] { "discord", "discordptb", "discordcanary" }, Array.Empty<string>(), new[] { "discord" }, true),
        new("skype", "Skype", new[] { "skype" }, new[] { "microsoft.skypeapp" }, new[] { "skype" }, true),
        new("whereby", "Whereby", new[] { "whereby" }, Array.Empty<string>(), new[] { "whereby" }, true),
        new("jitsi", "Jitsi Meet", new[] { "jitsi meet", "jitsi-meet" }, Array.Empty<string>(), new[] { "jitsi meet", "meet.jit.si" }, true),
        new("ringcentral", "RingCentral", new[] { "ringcentral", "ringcentralvideo", "rcvideo", "ringcentral meetings" }, new[] { "ringcentral" }, new[] { "ringcentral" }, true),
        new("goto", "GoTo Meeting", new[] { "g2mcomm", "g2mstart", "g2mlauncher", "goto", "gotomeeting" }, new[] { "\\goto\\", "gotomeeting" }, new[] { "goto meeting", "gotomeeting" }, true),
        new("zoho", "Zoho Meeting", new[] { "zohomeeting", "zoho meeting" }, new[] { "zoho" }, new[] { "zoho meeting" }, true),
        new("signal", "Signal", new[] { "signal" }, Array.Empty<string>(), new[] { "signal" }, false),
        new("whatsapp", "WhatsApp", new[] { "whatsapp", "whatsapp.root" }, new[] { "whatsappdesktop" }, Array.Empty<string>(), false),
        new("telegram", "Telegram", new[] { "telegram" }, new[] { "telegramdesktop" }, Array.Empty<string>(), false),
    };

    public static CallService? ById(string id) => Services.FirstOrDefault(s => s.Id == id);

    static readonly string[] Browsers = { "chrome", "msedge", "brave", "firefox", "opera", "vivaldi", "arc" };

    /// The call app behind an executable path or Store package name (from the microphone list).
    public static CallService? Service(string exePathOrPackage)
    {
        var e = exePathOrPackage.ToLowerInvariant().Replace('/', '\\');
        var exe = Path.GetFileNameWithoutExtension(e.Contains('\\') ? e[(e.LastIndexOf('\\') + 1)..] : e);
        foreach (var s in Services)
        {
            if (e.EndsWith(".exe") && s.ExeNames.Contains(exe)) return s;
            if (s.PackageHints.Any(h => e.Contains(h))) return s;
        }
        return null;
    }

    public static bool IsBrowser(string exePathOrProcess)
    {
        var name = Path.GetFileNameWithoutExtension(exePathOrProcess.ToLowerInvariant());
        return Browsers.Contains(name);
    }

    /// The web call shown in a browser window title (only services that have a web version).
    public static CallService? ServiceForTitle(string title)
    {
        var t = title.ToLowerInvariant();
        // A Meet tab is titled "Meet - abc-defg-hij" or "Meet – <meeting name>".
        if (t.StartsWith("meet - ") || t.StartsWith("meet – ")) return ById("meet");
        return Services.FirstOrDefault(s => s.Web && s.TitleHints.Any(h => t.Contains(h)));
    }

    /// Legacy helpers (calendar links and older tests).
    public static MeetingPlatform? Kind(string exePathOrPackage) => ToPlatform(Service(exePathOrPackage));
    public static MeetingPlatform? PlatformForTitle(string title) => ToPlatform(ServiceForTitle(title));

    public static MeetingPlatform? ToPlatform(CallService? s) => s?.Id switch
    {
        "teams" => MeetingPlatform.Teams,
        "zoom" => MeetingPlatform.Zoom,
        "meet" => MeetingPlatform.Meet,
        _ => null,
    };

    public static string CleanTitle(string raw, CallService s)
    {
        var t = raw;
        foreach (var cut in new[] { " - Google Chrome", " – Google Chrome", " - Microsoft\u200b Edge", " - Microsoft Edge", " - Brave", " — Mozilla Firefox",
                                    " - Mozilla Firefox", " - Opera", " - Vivaldi", " | Microsoft Teams", " - Microsoft Teams", " - Slack", " | Slack",
                                    " - Discord", " - Webex", " - Work", " - Personal" })
            t = t.Replace(cut, "");
        t = Regex.Replace(t, @"\s+and \d+ more pages?$", "").Trim();
        if (t.StartsWith("Meet - ") || t.StartsWith("Meet – ")) t = t[7..];
        var low = t.ToLowerInvariant();
        if (t.Length == 0 || low == "meet" || low == s.Name.ToLowerInvariant() || low is "microsoft teams" or "google meet" or "zoom" or "zoom workplace")
            return $"{s.Name} call";
        return t.Length > 80 ? t[..80] : t;
    }
}
