// Minimal stand-in for the Windows-only context type so TextBrain compiles in tests.
// Just Say It – created by Stefano Roman Gunness · MIT License

namespace JustSayIt;

public class CaptureContext
{
    public string AppName = "Test";
    public AppCategory Category = AppCategory.Other;
    public string PromptBlock() => "App: Test";
}

/// Stand-in for the Windows-only local AI types used by Store.
public enum LocalModel { Fast, Quality }

/// Stand-in for the built-in local AI (not used by the text-rule tests).
public static class LocalAI
{
    public static bool Ready => false;
    public static Task<string?> Run(string instructions, string prompt, int maxTokens = 1500) => Task.FromResult<string?>(null);
    public static Task Prewarm() => Task.CompletedTask;
}
