// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Text.Json;
using System.Text.Json.Serialization;

namespace JustSayIt;

public enum AppCategory { Email, Work, Casual, Ai, Code, Other }

public enum Tone { Formal, Professional, Casual, VeryCasual, Verbatim }

public enum HotkeyChoice { RightAlt, RightCtrl, F8, ScrollLock }

public enum RewriteStyle { Formal, Casual, Concise, Enthusiastic, Longer, Summarize, Grammar }

public enum ModelSize { Base, Small, Turbo }

public static class Labels
{
    public static string Of(AppCategory c) => c switch
    {
        AppCategory.Email => "Email",
        AppCategory.Work => "Work chat",
        AppCategory.Casual => "Personal messages",
        AppCategory.Ai => "AI chats & prompts",
        AppCategory.Code => "Code editors",
        _ => "Everything else",
    };

    public static string Of(Tone t) => t switch
    {
        Tone.Formal => "Formal",
        Tone.Professional => "Professional",
        Tone.Casual => "Casual",
        Tone.VeryCasual => "Very casual",
        _ => "Exact words (only clean up)",
    };

    public static string Guidance(Tone t) => t switch
    {
        Tone.Formal => "Use a formal, polished register with complete sentences and proper capitalization.",
        Tone.Professional => "Use a clear, friendly, professional register with complete sentences.",
        Tone.Casual => "Use a relaxed conversational register. Contractions are fine. Keep it short.",
        Tone.VeryCasual => "Use a very casual chat register: lowercase is fine, minimal punctuation, no trailing period on single sentences.",
        _ => "Keep the speaker's exact wording; only fix punctuation, capitalization, fillers and self-corrections.",
    };

    public static string Of(HotkeyChoice h) => h switch
    {
        HotkeyChoice.RightAlt => "Right Alt",
        HotkeyChoice.RightCtrl => "Right Ctrl",
        HotkeyChoice.F8 => "F8",
        _ => "Scroll Lock",
    };

    public static int VirtualKey(HotkeyChoice h) => h switch
    {
        HotkeyChoice.RightAlt => 0xA5,   // VK_RMENU
        HotkeyChoice.RightCtrl => 0xA3,  // VK_RCONTROL
        HotkeyChoice.F8 => 0x77,
        _ => 0x91,                       // VK_SCROLL
    };

    public static string Of(RewriteStyle s) => s switch
    {
        RewriteStyle.Formal => "More formal",
        RewriteStyle.Casual => "More casual",
        RewriteStyle.Concise => "Shorter & concise",
        RewriteStyle.Enthusiastic => "Enthusiastic",
        RewriteStyle.Longer => "Make it longer",
        RewriteStyle.Summarize => "Summarize",
        _ => "Fix grammar only",
    };

    public static string Instruction(RewriteStyle s) => s switch
    {
        RewriteStyle.Formal => "Rewrite the text in a more formal, polished tone.",
        RewriteStyle.Casual => "Rewrite the text in a relaxed, casual tone.",
        RewriteStyle.Concise => "Rewrite the text to be as short and clear as possible while keeping every key point.",
        RewriteStyle.Enthusiastic => "Rewrite the text with a warm, enthusiastic, upbeat tone.",
        RewriteStyle.Longer => "Expand the text with more detail and complete sentences, without inventing facts.",
        RewriteStyle.Summarize => "Summarize the text in one to three sentences.",
        _ => "Fix only grammar, spelling and punctuation. Do not change wording otherwise.",
    };

    public static string Of(ModelSize m) => m switch
    {
        ModelSize.Base => "Fast (base, 140 MB)",
        ModelSize.Small => "Balanced (small, 470 MB)",
        _ => "Best accuracy (large-v3-turbo, 1.6 GB)",
    };
}

public class CalendarFeed { public string Name { get; set; } = ""; public string Url { get; set; } = ""; }

public class Replacement { public string Heard { get; set; } = ""; public string Write { get; set; } = ""; }

public class Snippet { public string Trigger { get; set; } = ""; public string Text { get; set; } = ""; }

public class HistoryItem
{
    public DateTime Date { get; set; }
    public string Raw { get; set; } = "";
    public string Final { get; set; } = "";
    public string App { get; set; } = "";
    public double Seconds { get; set; }
    public int Words { get; set; }
}

public class Prefs
{
    public HotkeyChoice Hotkey { get; set; } = HotkeyChoice.RightAlt;
    public string Language { get; set; } = "auto";
    public ModelSize Model { get; set; } = ModelSize.Small;
    public bool AiCleanup { get; set; } = true;
    public string OllamaUrl { get; set; } = "http://localhost:11434";
    public string OllamaModel { get; set; } = "llama3.2:3b";
    public bool PlaySounds { get; set; } = true;
    public bool RestoreClipboard { get; set; } = true;
    public bool AutoInsert { get; set; } = true;
    public bool ShowResultCard { get; set; } = true;
    public bool StartWithWindows { get; set; } = true;
    public bool UseScreenContext { get; set; } = true;
    public bool NoteTakerEnabled { get; set; } = true;
    public bool NoteCaptureSystemAudio { get; set; } = true;
    public bool AutoJoinEnabled { get; set; } = false;
    public bool AutoJoinStartNotes { get; set; } = true;
    public int AutoJoinLeadSeconds { get; set; } = 60;
    public int AutoJoinStopGraceSeconds { get; set; } = 120;
    public List<CalendarFeed> CalendarFeeds { get; set; } = new();
    public bool CheckForUpdates { get; set; } = true;
    public string? SkippedVersion { get; set; }
    public bool AutoRecordCalls { get; set; } = true;
    public bool RecordTeamsCalls { get; set; } = true;
    public bool RecordZoomCalls { get; set; } = true;
    public bool RecordMeetCalls { get; set; } = true;
    public bool CiqEnabled { get; set; } = false;
    public string CiqModel { get; set; } = "Nemotron";
    public bool CiqShowPreview { get; set; } = true;
    public string CiqPrompt { get; set; } = Prompts.CiqStandard;
    public Dictionary<AppCategory, Tone> Tones { get; set; } = new()
    {
        [AppCategory.Email] = Tone.Professional, [AppCategory.Work] = Tone.Professional,
        [AppCategory.Casual] = Tone.Casual, [AppCategory.Ai] = Tone.Verbatim,
        [AppCategory.Code] = Tone.Verbatim, [AppCategory.Other] = Tone.Professional,
    };
    public Dictionary<AppCategory, string> CustomInstructions { get; set; } = new();
    public List<string> Vocabulary { get; set; } = new();
    public List<Replacement> Replacements { get; set; } = new();
    public List<Snippet> Snippets { get; set; } = new();
    public int TotalWords { get; set; }
    public double TotalSeconds { get; set; }
}

public class Store
{
    // Order matters: static fields initialize top to bottom, and the constructor
    // uses Dir and Json, so they must come before Shared.
    public static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JustSayIt");

    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static Store Shared { get; } = new();

    public Prefs Prefs { get; private set; }
    public List<HistoryItem> History { get; private set; }
    public event Action? Changed;

    string PrefsPath => Path.Combine(Dir, "prefs.json");
    string HistoryPath => Path.Combine(Dir, "history.json");

    Store()
    {
        Directory.CreateDirectory(Dir);
        Prefs = Load<Prefs>(PrefsPath) ?? new Prefs();
        // Upgrade people still on the old short default to the standard meeting prompt.
        var trimmed = (Prefs.CiqPrompt ?? "").Trim().TrimEnd('.');
        if (trimmed.Length == 0 || trimmed == Prompts.CiqOldDefault.TrimEnd('.')) Prefs.CiqPrompt = Prompts.CiqStandard;
        History = Load<List<HistoryItem>>(HistoryPath) ?? new();
    }

    static T? Load<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), Json) : default; }
        catch { return default; }
    }

    public Tone ToneFor(AppCategory c) => Prefs.Tones.TryGetValue(c, out var t) ? t : Tone.Professional;

    public void Save()
    {
        File.WriteAllText(PrefsPath, JsonSerializer.Serialize(Prefs, Json));
        Changed?.Invoke();
    }

    public void Record(HistoryItem item)
    {
        History.Insert(0, item);
        if (History.Count > 300) History.RemoveRange(300, History.Count - 300);
        Prefs.TotalWords += item.Words;
        Prefs.TotalSeconds += item.Seconds;
        File.WriteAllText(HistoryPath, JsonSerializer.Serialize(History, Json));
        Save();
    }

    public void ClearHistory()
    {
        History.Clear();
        File.WriteAllText(HistoryPath, "[]");
        Changed?.Invoke();
    }
}

public static class Prompts
{
    public const string CiqOldDefault = "Summarize this meeting: key points, decisions, action items with owners and dates, and open questions.";

    /// Placed before every note or transcript sent to CollectivIQ.
    public const string CiqStandard = """
Instructions:

Analyze the provided meeting transcript/recording/notes in full detail and produce a professional, structured summary using the exact format below. Preserve chronological flow (beginning → middle → end) and use direct quotes where impactful. Use bullet points throughout. Do not omit minor details — capture the full arc of the conversation.

1. Meeting Metadata
Date:
Time (start–end):
Duration:
Location / Platform (in-person, Zoom, Teams, etc.):
Meeting Purpose / Objective:

2. Participants
Attendees (full list, with roles/titles if known):
Who called/organized the meeting:
Who joined late or left early (if noted):
Absent/expected-but-missing participants:

3. Opening — How the Meeting Started
Context or agenda set at the outset
Any recap of previous meeting/action items referenced early on
Initial tone/framing of the discussion

4. Chronological Flow of Discussion (Beginning → Middle → End)
Bullet-by-bullet walkthrough of how topics progressed
Note transitions between subjects
Flag any tense moments, disagreements, or pivots in direction

5. Key Discussion Points
Bullet list of each major topic raised
Who raised each point
Supporting context/data mentioned

6. Decisions Made
Bullet list of every concrete decision
Who made/approved the decision
Rationale given (if any)

7. Open Questions / Unresolved Items
Bullet list of questions raised but not answered
Who owns finding the answer (if assigned)

8. Risks Identified
Bullet list of risks discussed
Severity/impact if mentioned
Who flagged the risk

9. Blockers
Bullet list of current blockers
What/who is causing the blocker
Dependencies involved

10. Solutions Proposed
Bullet list of solutions/ideas brought to the table
Who proposed each
Whether it was accepted, rejected, or left pending

11. Issues Resolved During the Meeting
Bullet list of problems that were actually solved/closed out in real time

12. Timelines & Deadlines
Bullet list of all dates, milestones, or deadlines mentioned
Owner responsible for each

13. Next Steps / Action Items
Bullet list format: Action → Owner → Due Date

14. Key Quotes
Pull 3–6 of the most important or revealing direct quotes
Attribute each to the speaker
Note why the quote matters (decision-defining, risk-flagging, conflict, resolution, etc.)

15. Closing — How the Meeting Ended
Final summary/recap given (if any)
Any last-minute decisions or action items added at the end
Sentiment/tone at close (agreement, unresolved tension, enthusiasm, etc.)

16. Overall Meeting Assessment
Was the stated purpose achieved?
What progress was made vs. what remains outstanding?
Any recommendations for the next meeting's agenda?

Formatting rules:
Use nested bullet points, not paragraphs
Bold key terms (decisions, owners, dates)
Keep quotes exact and short, with speaker attribution
Flag anything ambiguous as "unclear/unconfirmed" rather than guessing
Paste your transcript or notes right after this prompt whenever you're ready, and I'll run the full breakdown for you IN PLAIN TEXT
- HERE IS THE INFORMATION :
""";
}
