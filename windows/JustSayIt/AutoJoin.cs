// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using Ical.Net;
using Ical.Net.CalendarComponents;
using Ical.Net.DataTypes;

namespace JustSayIt;

public record UpcomingMeeting(string Id, string Title, DateTime Start, DateTime End, MeetingLink Link, string Calendar, List<string> Attendees);

/// Reads your Google / Microsoft calendars through their private iCal (ICS) links,
/// joins Zoom / Meet / Teams calls on time and runs the Note Taker for each one.
public sealed class AutoJoin
{
    public static AutoJoin Shared { get; } = new();

    public List<UpcomingMeeting> Upcoming { get; private set; } = new();
    public UpcomingMeeting? Current { get; private set; }
    public string LastAction { get; private set; } = "";
    public string LastError { get; private set; } = "";
    public event Action? Changed;

    readonly HashSet<string> joined = new();
    readonly HashSet<string> notified = new();
    readonly System.Windows.Forms.Timer tick = new() { Interval = 15_000 };
    readonly System.Windows.Forms.Timer reload = new() { Interval = 5 * 60_000 };
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public void Boot()
    {
        tick.Tick += (_, _) => Tick();
        reload.Tick += async (_, _) => await Refresh();
        tick.Start();
        reload.Start();
        _ = Refresh();
    }

    public async Task Refresh()
    {
        var feeds = Store.Shared.Prefs.CalendarFeeds.Where(f => f.Url.Length > 0).ToList();
        var list = new List<UpcomingMeeting>();
        var errors = new List<string>();
        foreach (var feed in feeds)
        {
            try
            {
                var url = feed.Url.Trim().Replace("webcal://", "https://", StringComparison.OrdinalIgnoreCase);
                var ics = await Http.GetStringAsync(url);
                list.AddRange(Parse(ics, feed.Name, DateTime.Now));
            }
            catch (Exception e) { errors.Add($"{feed.Name}: {e.Message}"); }
        }
        Upcoming = list.GroupBy(m => m.Id).Select(g => g.First()).OrderBy(m => m.Start).ToList();
        LastError = string.Join(" · ", errors);
        Changed?.Invoke();
    }

    /// Expands events (including recurring ones) in the next 36 hours that contain a meeting link.
    public static List<UpcomingMeeting> Parse(string ics, string calendarName, DateTime now)
    {
        var cal = Calendar.Load(ics) ?? throw new FormatException("Not a valid calendar (ICS) file");
        var from = new CalDateTime(now.AddHours(-3).ToUniversalTime(), "UTC");
        var to = new CalDateTime(now.AddHours(36).ToUniversalTime(), "UTC");
        var result = new List<UpcomingMeeting>();
        foreach (var occ in cal.GetOccurrences<CalendarEvent>(from).TakeWhile(o => o.Period.StartTime.LessThan(to)))
        {
            if (occ.Source is not CalendarEvent ev) continue;
            if (ev.Start?.HasTime == false) continue; // all-day
            if (string.Equals(ev.Status, "CANCELLED", StringComparison.OrdinalIgnoreCase)) continue;
            var link = MeetingLinks.Find(ev.Url?.ToString(), ev.Location, ev.Description,
                ev.Properties.FirstOrDefault(p => p.Name.Equals("X-GOOGLE-CONFERENCE", StringComparison.OrdinalIgnoreCase))?.Value?.ToString(),
                ev.Properties.FirstOrDefault(p => p.Name.Equals("X-MICROSOFT-SKYPETEAMSMEETINGURL", StringComparison.OrdinalIgnoreCase))?.Value?.ToString());
            if (link == null) continue;
            var start = occ.Period.StartTime.AsUtc.ToLocalTime();
            var end = (occ.Period.EndTime ?? occ.Period.StartTime.Add(ev.Duration ?? Ical.Net.DataTypes.Duration.FromHours(1))).AsUtc.ToLocalTime();
            if (end <= now) continue;
            var attendees = ev.Attendees.Select(a => string.IsNullOrWhiteSpace(a.CommonName) ? a.Value?.ToString().Replace("mailto:", "") ?? "" : a.CommonName)
                .Where(s => s.Length > 0).Take(12).ToList();
            result.Add(new UpcomingMeeting($"{ev.Uid}@{start:O}", string.IsNullOrWhiteSpace(ev.Summary) ? "Meeting" : ev.Summary,
                start, end, link, calendarName, attendees));
        }
        return result;
    }

    void Tick()
    {
        var p = Store.Shared.Prefs;
        if (!p.AutoJoinEnabled) return;
        var now = DateTime.Now;
        foreach (var m in Upcoming.Where(m => !joined.Contains(m.Id)))
        {
            var joinAt = m.Start.AddSeconds(-p.AutoJoinLeadSeconds);
            if (now >= joinAt && now < m.Start.AddMinutes(10) && now < m.End)
            {
                Join(m);
                break;
            }
            if (now >= joinAt.AddMinutes(-2) && now < joinAt && notified.Add(m.Id))
            {
                LastAction = $"Joining “{m.Title}” at {m.Start:t}";
                Controller.Shared.Overlay.ShowState(OverlayState.Error, $"Joining “{m.Title}” in 2 min – {MeetingLinks.Name(m.Link.Platform)}");
                Changed?.Invoke();
            }
        }
        if (Current != null && now >= Current.End.AddSeconds(p.AutoJoinStopGraceSeconds)) FinishCurrent();
    }

    public void Join(UpcomingMeeting m)
    {
        joined.Add(m.Id);
        var p = Store.Shared.Prefs;
        bool opened = Open(MeetingLinks.AppUrl(m.Link)) || Open(m.Link.Url);
        LastAction = (opened ? "Joined" : "Couldn't open") + $" “{m.Title}” on {MeetingLinks.Name(m.Link.Platform)}";
        Changed?.Invoke();
        if (!opened || !p.AutoJoinStartNotes || !p.NoteTakerEnabled) return;
        Current = m;
        _ = Task.Run(async () =>
        {
            var notes = NoteTaker.Shared;
            if (notes.IsRecording) await notes.Stop();
            await Task.Delay(4000);
            await Ui.Run(NoteWindow.ShowShared);
            await notes.Start(m);
        });
    }

    public void FinishCurrent()
    {
        if (Current == null) return;
        Current = null;
        _ = NoteTaker.Shared.Stop();
        Changed?.Invoke();
    }

    static bool Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); return true; }
        catch { return false; }
    }
}
