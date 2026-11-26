using System.Diagnostics;
using Microsoft.Win32;

namespace Dexmenu.Settings;

/// <summary>Dexmenu registered for the current user (docs/plans/01-PLAN-dexmenu.md 3.9): DexmenuShell.dll next to the
/// app as the context menu handler for files and folders, a folder's empty part and drives (HKCU\Software\Classes, no
/// administrator needed), and switched on (HKCU\Software\Dexmenu Enabled). Unregistering takes the handler away and
/// switches it off. Explorer loads the DLL, and lets go of it, only when it starts: hence restarting it.
/// Registering for every user of the computer is the installer's (plan 00 step 7).</summary>
static class Registration
{
    public const string Clsid = "{CD4EEF01-47D9-4172-A48A-F6E61850D170}";
    const string Classes = @"Software\Classes";
    // files and folders, a folder's empty part, the desktop's empty part (plan 05 3.2), drives
    static readonly string[] Kinds = ["AllFilesystemObjects", @"Directory\Background", "DesktopBackground", "Drive"];

    public static string DllPath => Path.Combine(AppContext.BaseDirectory, "DexmenuShell.dll");

    /// <summary>The DLL registered for this user, or null.</summary>
    public static string? RegisteredDll
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey($@"{Classes}\CLSID\{Clsid}\InprocServer32");
            return key?.GetValue(null) as string;
        }
    }

    public static bool Enabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Dexmenu");
            return key?.GetValue("Enabled") is int v && v == 1;
        }
    }

    public static void Register()
    {
        using (var server = Registry.CurrentUser.CreateSubKey($@"{Classes}\CLSID\{Clsid}"))
            server.SetValue(null, "Dexmenu");
        using (var inproc = Registry.CurrentUser.CreateSubKey($@"{Classes}\CLSID\{Clsid}\InprocServer32"))
        {
            inproc.SetValue(null, DllPath);
            inproc.SetValue("ThreadingModel", "Apartment");
        }
        foreach (var kind in Kinds)
        {
            using var handler = Registry.CurrentUser.CreateSubKey($@"{Classes}\{kind}\shellex\ContextMenuHandlers\Dexmenu");
            handler.SetValue(null, Clsid);
        }
        SetEnabled(true);
    }

    public static void Unregister()
    {
        foreach (var kind in Kinds)
            Registry.CurrentUser.DeleteSubKeyTree($@"{Classes}\{kind}\shellex\ContextMenuHandlers\Dexmenu", throwOnMissingSubKey: false);
        Registry.CurrentUser.DeleteSubKeyTree($@"{Classes}\CLSID\{Clsid}", throwOnMissingSubKey: false);
        SetEnabled(false);
    }

    static void SetEnabled(bool on)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Dexmenu");
        key.SetValue("Enabled", on ? 1 : 0, RegistryValueKind.DWord);
    }

    /// <summary>Explorer ended and started again (this user's session), so it loads, or lets go of, the DLL. Its open
    /// windows close.</summary>
    public static void RestartExplorer()
    {
        var session = Process.GetCurrentProcess().SessionId;
        foreach (var p in Process.GetProcessesByName("explorer").Where(p => p.SessionId == session))
        {
            try { p.Kill(); p.WaitForExit(5000); }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        }
        // Windows starts the shell again by itself; when it has not after a moment, it is started here.
        for (var i = 0; i < 30; i++)
        {
            if (Process.GetProcessesByName("explorer").Any(p => p.SessionId == session)) return;
            Thread.Sleep(100);
        }
        // without this process's DEXMENU_EDITOR (Program), else Dexmenu would stay out of that Explorer
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"))
            { UseShellExecute = false };
        start.Environment.Remove("DEXMENU_EDITOR");
        Process.Start(start);
    }
}
