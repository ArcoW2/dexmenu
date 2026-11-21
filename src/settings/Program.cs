namespace Dexmenu.Settings;

static class Program
{
    /// <summary>DexmenuSettings.exe [--kind &lt;kind of right-click&gt;] [--selftest &lt;file&gt;]
    /// DexmenuSettings.exe --register | --unregister [--restart-explorer]   (no window; for scripts and the tests)
    /// DexmenuSettings.exe --live &lt;out file&gt; &lt;kind&gt; &lt;folder&gt; [item ...]   (no window; the tests): Windows' real
    /// menu of that right-click, as the preview gets it (ShellMenu), written to the file; exit 1 when there is none.</summary>
    [STAThread]
    static int Main(string[] args)
    {
        // This process is the editor: Dexmenu's handler, run here when ShellMenu builds Windows' real menu (maybe from the
        // registered copy of the DLL, not the one next to this exe), notes nothing and sets no hook (Dexmenu.Hook).
        Environment.SetEnvironmentVariable("DEXMENU_EDITOR", "1");
        if (args.Length >= 4 && args[0] == "--live")
        {
            using var owner = new Form();
            var text = ShellMenu.SeenOf(owner.Handle, args[2], args[3], args.Skip(4).ToList(), "", out var error);
            File.WriteAllText(args[1], text ?? error);
            return text is null ? 1 : 0;
        }
        if (args.Contains("--register") || args.Contains("--unregister"))
        {
            if (args.Contains("--register")) Registration.Register();
            else Registration.Unregister();
            if (args.Contains("--restart-explorer")) Registration.RestartExplorer();
            return 0;
        }
        string? kind = null, selftest = null;
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--kind") kind = args[i + 1];
            if (args[i] == "--selftest") selftest = args[i + 1];
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(kind, selftest));
        return 0;
    }
}
