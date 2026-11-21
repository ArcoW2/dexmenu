namespace Dexmenu.Settings;

static class Program
{
    /// <summary>DexmenuSettings.exe [--kind &lt;kind of right-click&gt;] [--selftest &lt;file&gt;]
    /// DexmenuSettings.exe --register | --unregister [--restart-explorer]   (no window; for scripts and the tests)</summary>
    [STAThread]
    static int Main(string[] args)
    {
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
