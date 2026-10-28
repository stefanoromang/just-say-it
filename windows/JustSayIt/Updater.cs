// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace JustSayIt;

/// Checks GitHub Releases for a newer version, downloads the installer and runs it silently.
public sealed class Updater
{
    public static Updater Shared { get; } = new();
    public const string Repo = "stefanoromang/just-say-it";

    public string? Latest { get; private set; }
    public string Notes { get; private set; } = "";
    public string Status { get; private set; } = "";
    public bool Installing { get; private set; }
    public event Action? Changed;

    string? setupUrl;
    readonly System.Windows.Forms.Timer timer = new() { Interval = 24 * 3600 * 1000 };
    static readonly HttpClient Http = CreateHttp();

    static HttpClient CreateHttp()
    {
        var h = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        h.DefaultRequestHeaders.UserAgent.ParseAdd("JustSayIt-Updater");
        return h;
    }

    public static string Current
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v == null ? "0" : $"{v.Major}.{v.Minor}" + (v.Build > 0 ? $".{v.Build}" : "");
        }
    }

    public bool UpdateAvailable => Latest != null && IsNewer(Latest, Current) && setupUrl != null;

    public void Boot()
    {
        timer.Tick += async (_, _) => await Check(false);
        timer.Start();
        _ = Check(false);
    }

    /// "1.10" > "1.9", "2.0" > "1.12.3".
    public static bool IsNewer(string a, string b)
    {
        static int[] Parts(string s) => s.Trim().TrimStart('v', 'V').Split('.')
            .Select(p => int.TryParse(new string(p.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0).ToArray();
        var x = Parts(a); var y = Parts(b);
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int l = i < x.Length ? x[i] : 0, r = i < y.Length ? y[i] : 0;
            if (l != r) return l > r;
        }
        return false;
    }

    public async Task Check(bool userInitiated)
    {
        var p = Store.Shared.Prefs;
        if (!p.CheckForUpdates && !userInitiated) return;
        Set("Checking for updates…");
        try
        {
            using var doc = JsonDocument.Parse(await Http.GetStringAsync($"https://api.github.com/repos/{Repo}/releases/latest"));
            var root = doc.RootElement;
            Latest = root.GetProperty("tag_name").GetString()?.TrimStart('v', 'V');
            Notes = root.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";
            setupUrl = root.GetProperty("assets").EnumerateArray()
                .Select(a => (name: a.GetProperty("name").GetString() ?? "", url: a.GetProperty("browser_download_url").GetString() ?? ""))
                .FirstOrDefault(a => a.name.StartsWith("JustSayIt-Setup-") && a.name.EndsWith(".exe")).url;
            if (string.IsNullOrEmpty(setupUrl)) setupUrl = null;

            if (UpdateAvailable)
            {
                Set($"Version {Latest} is available (you have {Current}).");
                if (!userInitiated && p.SkippedVersion != Latest) await Ui.Run(Prompt);
            }
            else Set(Latest != null && IsNewer(Latest, Current) ? $"Version {Latest} is being prepared, try again in a few minutes." : $"You're up to date ({Current}).");
        }
        catch (Exception e) { Set(userInitiated ? "Couldn't check for updates: " + e.Message : ""); }
    }

    void Prompt()
    {
        var text = $"Just Say It {Latest} is available. You have {Current}.\n\nInstall it now? Just Say It will restart when it's done.\n\n{Summary(Notes)}";
        if (text.Length > 900) text = text[..900] + "…";
        var r = MessageBox.Show(text, "Update available", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Information, MessageBoxDefaultButton.Button1);
        if (r == DialogResult.Yes) _ = Install();
        else if (r == DialogResult.Cancel && Latest != null) { Store.Shared.Prefs.SkippedVersion = Latest; Store.Shared.Save(); }
    }

    public static string Summary(string md)
    {
        var lines = md.Split('\n')
            .Where(l => !l.StartsWith("```") && !l.Contains("curl ") && !l.Contains("irm "))
            .Select(l => l.Replace("**", "").Replace("`", "").Replace("### ", ""));
        return Regex.Replace(string.Join("\n", lines), @"\n{3,}", "\n\n").Trim();
    }

    public async Task Install()
    {
        if (Installing || setupUrl == null) return;
        Installing = true;
        Set($"Downloading Just Say It {Latest}…");
        try
        {
            var path = Path.Combine(Path.GetTempPath(), $"JustSayIt-Setup-{Latest}.exe");
            await using (var src = await Http.GetStreamAsync(setupUrl))
            await using (var dst = File.Create(path))
                await src.CopyToAsync(dst);
            Set("Installing… Just Say It will restart.");
            // The installer closes this app, installs over it and relaunches it.
            // /CURRENTUSER keeps it a per-user install, so no administrator prompt appears.
            Process.Start(new ProcessStartInfo(path, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /CURRENTUSER /RELAUNCH")
            { UseShellExecute = true });
            await Task.Delay(1500);
            await Ui.Run(Application.Exit);
        }
        catch (Exception e)
        {
            Installing = false;
            Set("Update failed: " + e.Message);
        }
    }

    void Set(string s) { Status = s; Changed?.Invoke(); }
}
