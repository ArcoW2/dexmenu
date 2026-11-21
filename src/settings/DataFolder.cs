using System.Text.Json;

namespace Dexmenu.Settings;

/// <summary>Where Dexmenu keeps a user's things (docs/plans/02-PLAN-own-menu.md 3.4, 3.5): %APPDATA%\Dexmenu with
/// settings.json ("layout": the active layout's name), layouts\&lt;name&gt;.json and seen\&lt;kind&gt;.json (the items each kind
/// of right-click showed, written by the DLL). DEXMENU_LAYOUT_FILE and DEXMENU_SEEN_FOLDER override them for the tests,
/// as in the DLL.</summary>
static class DataFolder
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Dexmenu");

    public static string SeenFolder =>
        Environment.GetEnvironmentVariable("DEXMENU_SEEN_FOLDER") is { Length: > 0 } f ? f : Path.Combine(Root, "seen");

    /// <summary>The layout file in use, or null when the built-in base layout is (no settings, no file).</summary>
    public static string? LayoutFile
    {
        get
        {
            if (Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is { Length: > 0 } env) return env;
            try
            {
                var settings = Path.Combine(Root, "settings.json");
                if (!File.Exists(settings)) return null;
                using var doc = JsonDocument.Parse(File.ReadAllText(settings),
                    new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
                if (doc.RootElement.TryGetProperty("layout", out var name) && name.GetString() is { Length: > 0 } n)
                    return Path.Combine(Root, "layouts", n + ".json");
            }
            catch (Exception e) when (e is IOException or JsonException) { }
            return null;
        }
    }

    /// <summary>The kinds of right-click Dexmenu has seen items for, the most recent first.</summary>
    public static string[] SeenKinds() =>
        Directory.Exists(SeenFolder)
            ? new DirectoryInfo(SeenFolder).GetFiles("*.json").OrderByDescending(f => f.LastWriteTimeUtc)
                .Select(f => Path.GetFileNameWithoutExtension(f.Name)).ToArray()
            : [];

    public static string ReadSeen(string kind)
    {
        var path = Path.Combine(SeenFolder, kind + ".json");
        try { return File.Exists(path) ? File.ReadAllText(path) : ""; }
        catch (IOException) { return ""; }
    }
}
