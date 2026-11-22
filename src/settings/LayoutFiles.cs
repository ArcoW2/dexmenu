namespace Dexmenu.Settings;

/// <summary>The layouts as files (docs/plans/05-PLAN-settings-windows.md 3.5): layouts\&lt;name&gt;.json in the data
/// folder. New, copy, rename and delete; a rename or delete keeps settings.json's kinds right (they follow a rename;
/// a deleted layout's kinds are set to none, Windows' own menu). Tested by --selftest-files (Program).</summary>
static class LayoutFiles
{
    static string Folder => Path.Combine(DataFolder.Root, "layouts");

    /// <summary>Every layout's name, sorted.</summary>
    public static List<string> Names() =>
        Directory.Exists(Folder)
            ? Directory.GetFiles(Folder, "*.json").Select(Path.GetFileNameWithoutExtension).OfType<string>()
                .Order(StringComparer.OrdinalIgnoreCase).ToList()
            : [];

    /// <summary>The kinds set to a layout in settings.json (directly, not those that fall through to it).</summary>
    public static List<string> KindsOf(string name) =>
        DataFolder.Kinds().Where(k => string.Equals(k.Layout, name, StringComparison.OrdinalIgnoreCase)).Select(k => k.Kind).ToList();

    /// <summary>Why a name cannot be a new layout's, or null when it can.</summary>
    public static string? Problem(string name)
    {
        name = name.Trim();
        if (name.Length == 0) return "a name is needed";
        if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return "a name cannot hold \\ / : * ? \" < > |";
        if (string.Equals(name, "none", StringComparison.OrdinalIgnoreCase)) return "\"none\" means Windows' own menu";
        if (Names().Any(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase))) return "a layout of that name exists";
        return null;
    }

    /// <summary>A new layout with only the remaining card (the base layout).</summary>
    public static void New(string name, string baseLayout)
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(DataFolder.LayoutPath(name.Trim()), baseLayout + Environment.NewLine);
    }

    /// <summary>A copy under a new name, set for no kind.</summary>
    public static void Copy(string from, string to) => File.Copy(DataFolder.LayoutPath(from), DataFolder.LayoutPath(to.Trim()));

    /// <summary>The file renamed; the kinds set to it follow.</summary>
    public static void Rename(string from, string to)
    {
        to = to.Trim();
        File.Move(DataFolder.LayoutPath(from), DataFolder.LayoutPath(to));
        foreach (var kind in KindsOf(from)) DataFolder.SetLayout(kind, to);
    }

    /// <summary>The file to the recycle bin; the kinds set to it are set to none (Windows' own menu).</summary>
    public static void Delete(string name, bool toRecycleBin = true)
    {
        var kinds = KindsOf(name);
        if (toRecycleBin)
            Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(DataFolder.LayoutPath(name),
                Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
        else File.Delete(DataFolder.LayoutPath(name));
        foreach (var kind in kinds) DataFolder.SetLayout(kind, "none");
    }

    /// <summary>The operations checked on a data folder of the test's own (DEXMENU_DATA): each line PASS or FAIL.</summary>
    public static List<string> SelfTest(string baseLayout)
    {
        var lines = new List<string>();
        void Check(bool ok, string what) => lines.Add((ok ? "PASS " : "FAIL ") + what);
        ShippedLayouts.Ensure();
        DataFolder.EnsureKinds();
        Check(Names().SequenceEqual([ShippedLayouts.First]) && KindsOf(ShippedLayouts.First).SequenceEqual(["default"]),
            "first start: the shipped layout Default A, set for every other right-click");
        File.Delete(DataFolder.LayoutPath(ShippedLayouts.First));
        ShippedLayouts.Ensure();
        Check(!Names().Contains(ShippedLayouts.First), "a shipped layout the user deleted is not written again");
        File.WriteAllText(DataFolder.LayoutPath("Default"), baseLayout);
        Check(Problem("Default") is not null && Problem("a/b") is not null && Problem("none") is not null && Problem("Mine") is null,
            "names: an existing one, a bad character and \"none\" refused");
        New("Mine", baseLayout);
        Check(Names().Contains("Mine") && KindsOf("Mine").Count == 0, "New: a layout, set for no kind");
        DataFolder.SetLayout("file", "Mine");
        DataFolder.SetLayout("folder", "Mine");
        Copy("Mine", "Mine copy");
        Check(Names().Contains("Mine copy") && KindsOf("Mine copy").Count == 0, "Copy: a copy, set for no kind");
        Rename("Mine", "Files");
        Check(!Names().Contains("Mine") && KindsOf("Files").SequenceEqual(["file", "folder"]), "Rename: the kinds follow");
        Delete("Files", toRecycleBin: false);
        Check(!Names().Contains("Files") && DataFolder.LayoutOf("file") == "none" && DataFolder.LayoutOf("folder") == "none",
            "Delete: its kinds set to none (Windows' own menu)");
        var before = DataFolder.Kinds().Select(k => k.Kind).ToList();
        DataFolder.MoveKind(before.IndexOf("file"), 0);
        var after = DataFolder.Kinds().Select(k => k.Kind).ToList();
        Check(after[0] == "file" && after[^1] == "default", "the kinds' order: file moved first, default stays last");
        DataFolder.SetLayout("file", "Default");
        Check(DataFolder.Resolve("dialog-file") == "Default", "a file in a dialog with its kind not set: the file kind decides");
        DataFolder.SetLayout("dialog-file", "Mine copy");
        Check(DataFolder.Resolve("dialog-file") == "Default", "file before dialog-file in the order: file still decides");
        return lines;
    }
}
