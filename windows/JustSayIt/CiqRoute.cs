// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

namespace JustSayIt;

/// The CollectivIQ sending rule (kept separate so it can be unit-tested).
public static class CiqRoute
{
    /// Where a message goes: a new CIQ chat, a DDR's direct-message chat, or decided by the sending
    /// rule once CollectivIQ is open (Auto).
    public record Destination(string? Ddr, bool Auto = false)
    {
        public static readonly Destination Chat = new((string?)null);
        public static readonly Destination Routed = new((string?)null, true);
    }

    /// Models that answer in CIQ Chat when the notes go there.
    public static readonly string[] ChatModels = { "Gemini", "Nemotron" };

    /// Where the notes end up, decided from this person's DDRs in CollectivIQ:
    /// a DDR called Notetaker → the raw transcript goes there; no Notetaker but another DDR (their
    /// assistant) → the AI version goes to the first one; no DDR at all → the AI version goes to
    /// CIQ Chat, answered by Gemini and Nemotron.
    public sealed record Route(string Kind, string? Name)
    {
        public static Route? Parse(string r)
        {
            if (r == "route:none") return new("chat", null);
            if (r.StartsWith("route:notetaker:")) return new("notetaker", r["route:notetaker:".Length..]);
            if (r.StartsWith("route:assistant:")) return new("assistant", r["route:assistant:".Length..]);
            return null;
        }
        public Destination Destination => Name == null ? Destination.Chat : new Destination(Name);
        public bool SendsRaw => Kind == "notetaker";
        public string Label => Kind switch
        {
            "notetaker" => $"the raw transcript to your {Name} DDR",
            "assistant" => $"the AI version to your assistant ({Name})",
            _ => "the AI version to CIQ Chat (Gemini + Nemotron)",
        };
    }

}
