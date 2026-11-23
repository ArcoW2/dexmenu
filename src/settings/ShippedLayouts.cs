namespace Dexmenu.Settings;

/// <summary>The layouts Dexmenu ships (plan 02 3.10), named "Default A", "Default B", ...: written into the layouts
/// folder once each (settings.json "shipped" remembers which), so a layout the user deleted or changed is left as it
/// is. A new user's every other kind of right-click uses "Default A".</summary>
static class ShippedLayouts
{
    public const string First = "Default A";

    // The rules match Windows' texts (an English Windows): a rule on the verb is not yet possible.
    static readonly (string Name, string Text)[] All =
    [
        (First, """
        {
          "format": 1,
          "lines": [
            { "line": [
              { "id": "cut", "card": "Cut", "icon": "E8C6", "rules": [ { "name": { "equals": "Cut" } } ] },
              { "id": "copy", "card": "Copy", "icon": "E8C8", "rules": [ { "name": { "equals": "Copy" } } ] },
              { "id": "paste", "card": "Paste", "icon": "E77F", "rules": [ { "name": { "equals": "Paste" } } ] },
              { "id": "rename", "card": "Rename", "icon": "E8AC", "rules": [ { "name": { "equals": "Rename" } } ] },
              { "id": "delete", "card": "Delete", "icon": "E74D", "rules": [ { "name": { "equals": "Delete" } } ] }
            ] },
            { "line": [
              { "id": "properties", "card": "Properties", "icon": "E946", "rules": [ { "name": { "equals": "Properties" } } ] }
            ] },
            { "id": "d1", "divider": "" },
            { "line": [
              { "id": "open", "card": "Open", "icon": "E8E5", "rules": [ { "name": { "equals": "Open" } } ] },
              { "id": "openwith", "card": "Open with", "icon": "E7AC", "rules": [ { "name": { "regex": "^Open with(\\.\\.\\.)?$" } } ] }
            ] },
            { "id": "d2", "divider": "" },
            { "line": [ { "id": "rest", "card": "Rest", "rules": [ "remaining" ] } ] },
            { "id": "d3", "divider": "" },
            { "line": [
              { "id": "about", "note": "Dexmenu - default menu" },
              { "id": "edit", "card": "Edit menu...", "own": "editMenu" },
              { "id": "windows", "card": "Windows' menu", "own": "windowsMenu" }
            ] }
          ]
        }
        """),
        ("Default B", """
        {
          "format": 1,
          "lines": [
            { "id": "search", "search": true },
            { "line": [
              { "id": "cut", "card": "Cut", "icon": "E8C6", "rules": [ { "name": { "equals": "Cut" } } ] },
              { "id": "copy", "card": "Copy", "icon": "E8C8", "rules": [ { "name": { "equals": "Copy" } } ] },
              { "id": "paste", "card": "Paste", "icon": "E77F", "rules": [ { "name": { "equals": "Paste" } } ] },
              { "id": "rename", "card": "Rename", "icon": "E8AC", "rules": [ { "name": { "equals": "Rename" } } ] },
              { "id": "delete", "card": "Delete", "icon": "E74D", "rules": [ { "name": { "equals": "Delete" } } ] }
            ] },
            { "id": "d1", "divider": "" },
            { "line": [
              { "id": "open", "card": "Open", "icon": "E8E5", "rules": [ { "name": { "equals": "Open" } } ] },
              { "id": "openwith", "card": "Open with", "icon": "E7AC", "rules": [ { "name": { "regex": "^Open with(\\.\\.\\.)?$" } } ] },
              { "id": "properties", "card": "Properties", "icon": "E946", "rules": [ { "name": { "equals": "Properties" } } ] }
            ] },
            { "id": "d2", "divider": "" },
            { "line": [
              { "id": "archive", "card": "Archive", "buttons": true, "rules": [ { "name": { "regex": "^(7-Zip|WinRAR|Extract All\\.\\.\\.)$" } } ] },
              { "id": "code", "card": "Code", "buttons": true, "rules": [ { "name": { "regex": "^Open (with|in) (Code|Visual Studio)" } } ] }
            ] },
            { "line": [
              { "id": "git", "card": "Git", "buttons": true, "rules": [ { "name": { "regex": "^(TortoiseGit$|Git |Open Git )" } } ] },
              { "id": "svn", "card": "SVN", "buttons": true, "rules": [ { "name": { "regex": "^(TortoiseSVN$|SVN )" } } ] }
            ] },
            { "id": "d3", "divider": "" },
            { "line": [ { "id": "rest", "card": "Rest", "rules": [ "remaining" ] } ] },
            { "id": "d9", "divider": "" },
            { "line": [
              { "id": "about", "note": "Dexmenu - cards per program" },
              { "id": "edit", "card": "Edit menu...", "own": "editMenu" },
              { "id": "windows", "card": "Windows' menu", "own": "windowsMenu" }
            ] }
          ]
        }
        """),
        ("Default C", """
        {
          "format": 1,
          "lines": [
            { "line": [
              { "id": "open", "card": "Open", "icon": "E8E5", "menu": [
                { "line": [ { "id": "openrules", "card": "Open and edit", "rules": [ { "name": { "regex": "^(Open|Edit|View|Print|Run)\\b" } } ] } ] }
              ] },
              { "id": "share", "card": "Share and send", "icon": "E72D", "menu": [
                { "line": [ { "id": "sharerules", "card": "Share", "rules": [ { "name": { "regex": "^(Share|Send to|Copy as path|Give access)" } } ] } ] }
              ] }
            ] },
            { "line": [
              { "id": "archive", "card": "Archive", "icon": "E7B8", "menu": [
                { "line": [ { "id": "archiverules", "card": "Archive", "rules": [ { "name": { "regex": "zip|7z|archive|extract|compress" } } ] } ] }
              ] },
              { "id": "vcs", "card": "Version control", "icon": "E8D4", "menu": [
                { "line": [ { "id": "vcsrules", "card": "Version control", "rules": [ { "name": { "regex": "git|svn|tortoise" } } ] } ] }
              ] }
            ] },
            { "line": [
              { "id": "file", "card": "File", "icon": "E7C3", "menu": [
                { "line": [ { "id": "filerules", "card": "File", "rules": [ { "name": { "any": [ "Cut", "Copy", "Paste", "Rename", "Delete", "Properties" ] } } ] } ] }
              ] },
              { "id": "more", "card": "More", "icon": "E712", "menu": [
                { "line": [ { "id": "rest", "card": "Rest", "rules": [ "remaining" ] } ] }
              ] }
            ] },
            { "id": "d9", "divider": "" },
            { "line": [
              { "id": "about", "note": "Dexmenu - by task" },
              { "id": "edit", "card": "Edit menu...", "own": "editMenu" },
              { "id": "windows", "card": "Windows' menu", "own": "windowsMenu" }
            ] }
          ]
        }
        """),
        ("Default D", """
        {
          "format": 1,
          "lines": [
            { "id": "search", "search": true },
            { "id": "most", "mostUsed": true },
            { "id": "d1", "divider": "" },
            { "line": [
              { "id": "all", "card": "All items", "icon": "E700", "menu": [
                { "line": [ { "id": "rest", "card": "Rest", "rules": [ "remaining" ] } ] }
              ] }
            ] },
            { "id": "d9", "divider": "" },
            { "line": [
              { "id": "about", "note": "Dexmenu - minimal" },
              { "id": "edit", "card": "Edit menu...", "own": "editMenu" },
              { "id": "windows", "card": "Windows' menu", "own": "windowsMenu" }
            ] }
          ]
        }
        """),
    ];

    /// <summary>Every shipped layout not written before written now, when no layout of that name is there.</summary>
    public static void Ensure()
    {
        var settings = DataFolder.ReadSettings();
        var shipped = settings["shipped"] as System.Text.Json.Nodes.JsonArray ?? new System.Text.Json.Nodes.JsonArray();
        var done = shipped.Select(n => n?.GetValue<string>()).ToHashSet();
        var changed = false;
        foreach (var (name, text) in All)
        {
            if (done.Contains(name)) continue;
            var path = DataFolder.LayoutPath(name);
            if (!File.Exists(path))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, text + Environment.NewLine);
            }
            shipped.Add(name);
            changed = true;
        }
        if (!changed) return;
        settings["shipped"] = shipped;
        DataFolder.WriteSettings(settings);
    }
}
