using System.Text.Json;

namespace Dexmenu.Settings;

/// <summary>Where Dexmenu keeps a user's things (docs/plans/02-PLAN-own-menu.md 3.4, 3.5; plan 05 3.2): %APPDATA%\Dexmenu
/// with settings.json ("kinds": which layout each kind of right-click gets, in the order they are tried),
/// layouts\&lt;name&gt;.json and seen\&lt;kind&gt;.json (the items each kind of right-click showed, written by the DLL).
/// DEXMENU_DATA (the whole folder), DEXMENU_LAYOUT_FILE and DEXMENU_SEEN_FOLDER override them for the tests, as in the
/// DLL.</summary>
static class DataFolder
{
    public static string Root => Environment.GetEnvironmentVariable("DEXMENU_DATA") is { Length: > 0 } d
        ? d : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Dexmenu");

    public static string SeenFolder =>
        Environment.GetEnvironmentVariable("DEXMENU_SEEN_FOLDER") is { Length: > 0 } f ? f : Path.Combine(Root, "seen");

    static string SettingsFile => Path.Combine(Root, "settings.json");
    public static string LayoutPath(string name) => Path.Combine(Root, "layouts", name + ".json");

    /// <summary>The kinds of right-click, in the order they start in (plan 05 3.2): the dialog kinds first (not set, so
    /// a dialog gets Explorer's kinds until the user sets them), every other last.</summary>
    public static readonly string[] KindOrder =
        ["dialog-file", "dialog-folder", "dialog-several", "dialog-background", "dialog-drive",
         "file", "folder", "several", "background", "desktop", "drive", "default"];

    /// <summary>How the app names each kind of right-click.</summary>
    public static readonly Dictionary<string, string> KindNames = new()
    {
        ["dialog-file"] = "a file in an Open or Save dialog", ["dialog-folder"] = "a folder in an Open or Save dialog",
        ["dialog-several"] = "several items in an Open or Save dialog", ["dialog-background"] = "an empty part in an Open or Save dialog",
        ["dialog-drive"] = "a drive in an Open or Save dialog",
        ["file"] = "a file", ["folder"] = "a folder", ["several"] = "several items", ["background"] = "a folder's empty part",
        ["desktop"] = "the desktop's empty part", ["drive"] = "a drive", ["default"] = "every other right-click",
    };

    /// <summary>The kinds as settings.json has them, in their order: kind and layout (a name, "none", or null: not set).
    /// </summary>
    public static List<(string Kind, string? Layout)> Kinds()
    {
        var list = new List<(string, string?)>();
        if (ReadSettings()["kinds"] is System.Text.Json.Nodes.JsonArray kinds)
            foreach (var e in kinds)
                if (e?["kind"]?.GetValue<string>() is { Length: > 0 } k) list.Add((k, e["layout"]?.GetValue<string>()));
        return list;
    }

    /// <summary>The kinds in a new order (a kind moved from one place to another); default stays last.</summary>
    public static void MoveKind(int from, int to)
    {
        var settings = ReadSettings();
        if (settings["kinds"] is not System.Text.Json.Nodes.JsonArray kinds || from < 0 || from >= kinds.Count || to < 0 || to >= kinds.Count) return;
        var moved = kinds[from];
        if (moved?["kind"]?.GetValue<string>() == "default") return;
        kinds.RemoveAt(from);
        kinds.Insert(Math.Min(to, kinds.Count), moved);
        // default always last
        var def = kinds.FirstOrDefault(e => e?["kind"]?.GetValue<string>() == "default");
        if (def is not null) { kinds.Remove(def); kinds.Add(def); }
        WriteSettings(settings);
    }

    /// <summary>The layout a kind of right-click gets, as the DLL decides (Dexmenu.Layout.CurrentLayout): the first kind
    /// in the order that fits and is set; "none" for Windows' own menu; null for the built-in base layout.</summary>
    public static string? Resolve(string kind)
    {
        foreach (var (k, layout) in Kinds())
        {
            var fits = k == kind || k == "default" || (kind.StartsWith("dialog-") && k == kind["dialog-".Length..]);
            if (fits && layout is { Length: > 0 }) return layout;
        }
        return null;
    }

    internal static System.Text.Json.Nodes.JsonObject ReadSettings()
    {
        try
        {
            return File.Exists(SettingsFile) && System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(SettingsFile),
                documentOptions: new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true })
                is System.Text.Json.Nodes.JsonObject o ? o : [];
        }
        catch (Exception e) when (e is IOException or JsonException) { return []; }
    }

    internal static void WriteSettings(System.Text.Json.Nodes.JsonObject settings)
    {
        Directory.CreateDirectory(Root);
        File.WriteAllText(SettingsFile, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>First start (plan 05 3.1, 3.2): settings.json gets "kinds" when it has none: every kind in its starting
    /// order, not set, and "every other" (default) set to the layout the older "layout" named, or to the Default layout
    /// (only the remaining card), made when missing. The user's layouts are not touched.</summary>
    public static void EnsureKinds(string baseLayout)
    {
        var settings = ReadSettings();
        if (settings["kinds"] is System.Text.Json.Nodes.JsonArray) return;
        var named = settings["layout"]?.GetValue<string>();
        var defaultLayout = named is { Length: > 0 } && File.Exists(LayoutPath(named)) ? named : "Default";
        if (defaultLayout == "Default" && !File.Exists(LayoutPath("Default")))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LayoutPath("Default"))!);
            File.WriteAllText(LayoutPath("Default"), baseLayout + Environment.NewLine);
        }
        var kinds = new System.Text.Json.Nodes.JsonArray();
        foreach (var kind in KindOrder)
        {
            var entry = new System.Text.Json.Nodes.JsonObject { ["kind"] = kind };
            if (kind == "default") entry["layout"] = defaultLayout;
            kinds.Add(entry);
        }
        settings["kinds"] = kinds;
        settings.Remove("layout");
        WriteSettings(settings);
    }

    /// <summary>The layout a kind is set to: its name, "none" (Windows' own menu) or null (not set).</summary>
    public static string? LayoutOf(string kind)
    {
        if (ReadSettings()["kinds"] is not System.Text.Json.Nodes.JsonArray kinds) return null;
        foreach (var e in kinds)
            if (e?["kind"]?.GetValue<string>() == kind) return e["layout"]?.GetValue<string>();
        return null;
    }

    /// <summary>A kind set to a layout (a name, "none", or null: not set); a kind not listed is added before default.</summary>
    public static void SetLayout(string kind, string? layout)
    {
        var settings = ReadSettings();
        if (settings["kinds"] is not System.Text.Json.Nodes.JsonArray kinds) { kinds = []; settings["kinds"] = kinds; }
        var entry = kinds.OfType<System.Text.Json.Nodes.JsonObject>().FirstOrDefault(e => e["kind"]?.GetValue<string>() == kind);
        if (entry is null)
        {
            entry = new System.Text.Json.Nodes.JsonObject { ["kind"] = kind };
            var at = kinds.Count;
            for (var i = 0; i < kinds.Count; i++) if (kinds[i]?["kind"]?.GetValue<string>() == "default") at = i;
            kinds.Insert(at, entry);
        }
        if (layout is null) entry.Remove("layout"); else entry["layout"] = layout;
        WriteSettings(settings);
    }

    /// <summary>The layout file the editor opens (until plan 05's editor window: every other kind's), or null when the
    /// built-in base layout is in use.</summary>
    public static string? LayoutFile
    {
        get
        {
            if (Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is { Length: > 0 } env) return env;
            var name = LayoutOf("default") ?? ReadSettings()["layout"]?.GetValue<string>();
            return name is { Length: > 0 } && name != "none" ? LayoutPath(name) : null;
        }
    }

    /// <summary>The kinds of right-click Dexmenu has seen items for, the most recent first.</summary>
    public static string[] SeenKinds() =>
        Directory.Exists(SeenFolder)
            ? new DirectoryInfo(SeenFolder).GetFiles("*.json").OrderByDescending(f => f.LastWriteTimeUtc)
                .Select(f => Path.GetFileNameWithoutExtension(f.Name)).Where(k => k != "last").ToArray()
            : [];

    /// <summary>The last right-click Dexmenu showed its menu for (seen\last.json, written by the DLL): its kind, folder
    /// and items; null when there is none or it cannot be read.</summary>
    public static (string Kind, string Folder, string[] Items)? LastRightClick()
    {
        var path = Path.Combine(SeenFolder, "last.json");
        try
        {
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var r = doc.RootElement;
            var kind = r.GetProperty("kind").GetString() ?? "";
            var folder = r.GetProperty("folder").GetString() ?? "";
            var items = r.TryGetProperty("items", out var list) ? list.EnumerateArray().Select(i => i.GetString() ?? "").ToArray() : [];
            return kind.Length > 0 && folder.Length > 0 ? (kind, folder, items) : null;
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException or KeyNotFoundException) { return null; }
    }

    public static string ReadSeen(string kind)
    {
        var path = Path.Combine(SeenFolder, kind + ".json");
        try { return File.Exists(path) ? File.ReadAllText(path) : ""; }
        catch (IOException) { return ""; }
    }
}
