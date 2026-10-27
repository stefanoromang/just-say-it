// Minimal stand-in for the Windows-only context type so TextBrain compiles in tests.
// Just Say It – created by Stefano Roman Gunness · MIT License

namespace JustSayIt;

public class CaptureContext
{
    public string AppName = "Test";
    public AppCategory Category = AppCategory.Other;
    public string PromptBlock() => "App: Test";
}
