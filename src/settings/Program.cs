namespace Dexmenu.Settings;

static class Program
{
    /// <summary>DexmenuSettings.exe: the main window (HomeForm; docs/plans/executed/05-PLAN-settings-windows.md).
    /// DexmenuSettings.exe --edit &lt;layout&gt;: that layout's editor window.
    /// DexmenuSettings.exe --kind &lt;kind&gt; | --selftest &lt;file&gt;, or with DEXMENU_LAYOUT_FILE set (the tests): an
    /// editor window on the layout in use (DataFolder.LayoutFile), the preview on that kind.
    /// DexmenuSettings.exe --selftest-files &lt;file&gt; (no window; the tests): the layout files' operations on a data
    /// folder of the test's own (DEXMENU_DATA, which it needs), PASS / FAIL lines to the file, exit: the failures.
    /// DexmenuSettings.exe --register | --unregister [--restart-explorer]   (no window; for scripts and the tests)
    /// DexmenuSettings.exe --live &lt;out file&gt; &lt;kind&gt; &lt;folder&gt; [item ...]   (no window; the tests): Windows' real
    /// menu of that right-click, as the preview gets it (ShellMenu), written to the file; exit 1 when there is none.
    /// DexmenuSettings.exe --measure-handler &lt;out&gt; &lt;kind&gt; &lt;sample&gt; &lt;clsid&gt; &lt;hang s&gt; | --measure-menu &lt;out&gt;
    /// &lt;kind&gt; &lt;sample&gt; &lt;hang s&gt; [profile]   (no window; the Diagnostics page's measuring process, plan 16 3.1, 3.7).</summary>
    [STAThread]
    static int Main(string[] args)
    {
        // This process is the editor: Dexmenu's handler, run here when ShellMenu builds Windows' real menu (maybe from the
        // registered copy of the DLL, not the one next to this exe), notes nothing and sets no hook (Dexmenu.Hook).
        Environment.SetEnvironmentVariable("DEXMENU_EDITOR", "1");
        // a measuring process (plan 16 3.1): one handler, or Windows' whole menu, timed; its result to the file
        var invariant = System.Globalization.CultureInfo.InvariantCulture;
        if (args.Length >= 6 && args[0] == "--measure-handler")
            return Diagnostics.MeasureHandlerMain(args[1], args[2], args[3], args[4], double.Parse(args[5], invariant),
                args.Length > 6 && args[6] == "packaged");
        if (args.Length >= 5 && args[0] == "--measure-menu")
            return Diagnostics.MeasureMenuMain(args[1], args[2], args[3], double.Parse(args[4], invariant), args.Length > 5 && args[5] == "profile");
        // the shipped layouts each written once (plan 02 3.10); first start: the kinds setting, every other kind on
        // "Default A" (plan 05 3.1, 3.2); the user's layouts untouched
        if (!args.Contains("--live") && !args.Contains("--selftest") && Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is not { Length: > 0 })
            try { ShippedLayouts.Ensure(); DataFolder.EnsureKinds(); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        if (args.Length >= 4 && args[0] == "--live")
        {
            using var owner = new Form();
            var text = ShellMenu.SeenOf(owner.Handle, args[2], args[3], args.Skip(4).ToList(), "", out var error);
            File.WriteAllText(args[1], text ?? error);
            return text is null ? 1 : 0;
        }
        if (args.Length >= 2 && args[0] == "--selftest-files")
        {
            if (Environment.GetEnvironmentVariable("DEXMENU_DATA") is not { Length: > 0 }) { File.WriteAllText(args[1], "FAIL DEXMENU_DATA not set"); return 1; }
            var lines = LayoutFiles.SelfTest(Native.BaseLayout());
            File.WriteAllLines(args[1], lines);
            return lines.Count(l => l.StartsWith("FAIL"));
        }
        if (args.Contains("--register") || args.Contains("--unregister"))
        {
            if (args.Contains("--register")) Registration.Register();
            else Registration.Unregister();
            if (args.Contains("--restart-explorer")) Registration.RestartExplorer();
            return 0;
        }
        string? kind = null, selftest = null, edit = null;
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--kind") kind = args[i + 1];
            if (args[i] == "--selftest") selftest = args[i + 1];
            if (args[i] == "--edit") edit = args[i + 1];
        }
        ApplicationConfiguration.Initialize();
        Themes.ApplyGlobal();
        Form first = edit is not null ? new EditorForm(DataFolder.LayoutPath(edit), null, null)
            : kind is not null || selftest is not null || Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is { Length: > 0 }
                ? new EditorForm(DataFolder.LayoutFile, kind, selftest)
                : new HomeForm();
        Application.Run(new DexmenuApp(first));
        return 0;
    }
}
