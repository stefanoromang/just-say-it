// Just Say It – created by Stefano Roman Gunness · MIT License
using System.Text.RegularExpressions;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace JustSayIt;

public sealed record MeetingCaption(
    [property: JsonPropertyName("service")] string Service,
    [property: JsonPropertyName("session")] string Session,
    [property: JsonPropertyName("segment")] string Segment,
    [property: JsonPropertyName("speaker")] string Speaker,
    [property: JsonPropertyName("text")] string Text,
    [property: JsonPropertyName("received")] double Received)
{
    public bool Valid => Service is "teams" or "meet" or "import" && !string.IsNullOrWhiteSpace(Session) && Session.Length <= 64
        && !string.IsNullOrWhiteSpace(Segment) && Segment.Length <= 100 && !string.IsNullOrWhiteSpace(Speaker) && Speaker.Length <= 200
        && !string.IsNullOrWhiteSpace(Text) && Text.Length <= 12000 && double.IsFinite(Received) && Received >= 0;
}

public static class MeetingTranscript
{
    public static void Merge(IEnumerable<MeetingCaption> rows, List<MeetingCaption> lines, ref string? session)
    {
        foreach (var row in rows.Where(r => r.Valid))
        {
            session ??= row.Session;
            if (session != row.Session) continue;
            int i = lines.FindIndex(l => l.Session == row.Session && l.Segment == row.Segment);
            if (i >= 0) lines[i] = row; else lines.Add(row);
        }
    }

    public static string Text(IEnumerable<MeetingCaption> lines) => string.Join("\n", lines.Select(l => $"{l.Speaker}: {l.Text}"));
    public static string Combined(string local, IReadOnlyCollection<MeetingCaption> captions) => captions.Count == 0 ? local
        : "MEETING PLATFORM TRANSCRIPT (speaker names supplied by the platform)\n" + Text(captions)
        + "\n\nLOCAL AUDIO BACKUP (may overlap the platform transcript; do not count repeated statements twice)\n" + local;

    public static List<MeetingCaption> Parse(string input)
    {
        string session = Guid.NewGuid().ToString();
        var result = new List<MeetingCaption>();
        foreach (var block in input.Replace("\r\n", "\n").Replace('\r', '\n').Split("\n\n"))
        {
            var lines = block.Split('\n').Select(l => l.Trim()).ToList();
            if (lines.Count == 0 || lines[0].StartsWith("WEBVTT") || lines[0].StartsWith("NOTE")) continue;
            int time = lines.FindIndex(l => l.Contains("-->"));
            if (time >= 0) lines = lines.Skip(time + 1).ToList();
            else lines.RemoveAll(l => Regex.IsMatch(l, @"^\d+$"));
            string cueSpeaker = "Speaker";
            foreach (var line in lines.Where(l => l.Length > 0))
            {
                string speaker = "Speaker", text = line;
                var tag = Regex.Match(line, @"^<v(?:\.[^ >]+)?\s+([^>]+)>");
                if (tag.Success) { speaker = tag.Groups[1].Value; text = line[tag.Length..].Replace("</v>", ""); }
                else
                {
                    int colon = line.IndexOf(':');
                    if (colon > 0 && colon <= 100 && !line[..colon].Any(char.IsDigit)) { speaker = line[..colon]; text = line[(colon + 1)..]; }
                    else if (time >= 0) speaker = cueSpeaker;
                }
                cueSpeaker = speaker;
                text = Regex.Replace(text, "<[^>]+>", "").Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">").Trim();
                var row = new MeetingCaption("import", session, result.Count.ToString(), speaker, text, DateTimeOffset.UtcNow.ToUnixTimeSeconds());
                if (row.Valid) result.Add(row);
            }
        }
        return result;
    }
}
