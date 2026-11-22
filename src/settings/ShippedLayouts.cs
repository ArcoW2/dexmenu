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
