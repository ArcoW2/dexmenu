namespace Dexmenu.Settings;

static class Program
{
    /// <summary>DexmenuSettings.exe [--kind &lt;kind of right-click&gt;]</summary>
    [STAThread]
    static void Main(string[] args)
    {
        string? kind = null;
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == "--kind") kind = args[i + 1];
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm(kind));
    }
}
