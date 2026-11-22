using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>The settings app's windows (docs/plans/05-PLAN-settings-windows.md): the main window and any number of
/// editor windows, one per layout. The app ends when its last window closes. The theme (light, dark, as Windows) goes
/// for every window at once.</summary>
sealed class DexmenuApp : ApplicationContext
{
    public static DexmenuApp Instance { get; private set; } = null!;
    readonly List<Form> windows = [];

    public DexmenuApp(Form first)
    {
        Instance = this;
        Show(first);
    }

    public void Show(Form form)
    {
        windows.Add(form);
        form.FormClosed += (_, _) =>
        {
            windows.Remove(form);
            if (windows.Count == 0) ExitThread();
        };
        form.Show();
    }

    /// <summary>The main window, brought to the front, or opened.</summary>
    public void OpenHome()
    {
        if (windows.OfType<HomeForm>().FirstOrDefault() is { } home) { Front(home); return; }
        Show(new HomeForm());
    }

    /// <summary>A layout's editor window, brought to the front when it is open, else opened.</summary>
    public void OpenEditor(string name)
    {
        if (Editors.FirstOrDefault(e => string.Equals(e.LayoutName, name, StringComparison.OrdinalIgnoreCase)) is { } open)
        {
            Front(open);
            return;
        }
        Show(new EditorForm(DataFolder.LayoutPath(name), null, null));
    }

    public IEnumerable<EditorForm> Editors => windows.OfType<EditorForm>();

    /// <summary>A layout renamed (in the main window or by an editor's Save): its open editor follows.</summary>
    public void Renamed(string from, string to)
    {
        foreach (var e in Editors.Where(e => string.Equals(e.LayoutName, from, StringComparison.OrdinalIgnoreCase)).ToList())
            e.FileRenamed(DataFolder.LayoutPath(to));
    }

    /// <summary>The theme changed in one window: every window follows.</summary>
    public void ThemeChanged()
    {
        Themes.ApplyGlobal();
        foreach (var w in windows) (w as IThemed)?.ApplyTheme();
    }

    static void Front(Form f)
    {
        if (f.WindowState == FormWindowState.Minimized) f.WindowState = FormWindowState.Normal;
        f.Activate();
        f.BringToFront();
    }
}

/// <summary>A window that follows the theme.</summary>
interface IThemed
{
    void ApplyTheme();
}

/// <summary>Light or dark (docs/plans/05-PLAN-settings-windows.md 3.3): settings.json's "theme", "windows" as Windows'
/// apps are. A window's title bar (DWM), its page (WebView2's preferred colour scheme, which the pages' CSS follows) and
/// the preview the DLL draws.</summary>
static class Themes
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

    public static bool Dark => DataFolder.Theme switch
    {
        "dark" => true,
        "light" => false,
        _ => Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "AppsUseLightTheme", 1) is int v && v == 0,
    };

    /// <summary>What is the same for every window: the preview's look (the DLL).</summary>
    public static void ApplyGlobal()
    {
        try { Native.DexmenuSetTheme(DataFolder.Theme switch { "light" => 1, "dark" => 2, _ => 0 }); }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { }
    }

    public static void Apply(Form form, WebView2? web)
    {
        var dark = Dark ? 1 : 0;
        if (form.IsHandleCreated) DwmSetWindowAttribute(form.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int));
        form.BackColor = Dark ? Color.FromArgb(0x1F, 0x1F, 0x1F) : SystemColors.Control;
        form.ForeColor = Dark ? Color.FromArgb(0xF0, 0xF0, 0xF0) : SystemColors.ControlText;
        if (web?.CoreWebView2 is { } core)
            core.Profile.PreferredColorScheme = DataFolder.Theme switch
            {
                "light" => CoreWebView2PreferredColorScheme.Light,
                "dark" => CoreWebView2PreferredColorScheme.Dark,
                _ => CoreWebView2PreferredColorScheme.Auto,
            };
    }
}

/// <summary>What both kinds of window do with their page: WebView2 set up with the shared environment, the page
/// served (WebFiles), the clipboard granted to it.</summary>
static class Pages
{
    [DllImport("user32.dll")]
    static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);

    static Task<CoreWebView2Environment>? environment;

    public static async Task Start(WebView2 web, string page, Action<string> received, Action loaded)
    {
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dexmenu", "WebView2");
        environment ??= CoreWebView2Environment.CreateAsync(null, data);
        await web.EnsureCoreWebView2Async(await environment);
        WebFiles.Serve(web.CoreWebView2);
        // the editors' Ctrl+C / Ctrl+V of cards and rules (plan 05 3.6): the page may read the clipboard
        web.CoreWebView2.PermissionRequested += (_, e) =>
        {
            if (e.PermissionKind == CoreWebView2PermissionKind.ClipboardRead) e.State = CoreWebView2PermissionState.Allow;
        };
        web.CoreWebView2.WebMessageReceived += (_, e) => received(e.WebMessageAsJson);
        web.CoreWebView2.NavigationCompleted += async (_, _) =>
        {
            loaded();
            // DEXMENU_SCREENSHOT (to check the page's look by hand or by a script): the page as a PNG, then the window
            // closes
            if (Environment.GetEnvironmentVariable("DEXMENU_SCREENSHOT") is { Length: > 0 } shot && web.FindForm() is { } form)
            {
                await Task.Delay(2500);
                // the whole window as it shows (the page and the preview window over it)
                using (var bmp = new Bitmap(form.Width, form.Height))
                {
                    using (var g = Graphics.FromImage(bmp))
                    {
                        var dc = g.GetHdc();
                        PrintWindow(form.Handle, dc, 2);   // PW_RENDERFULLCONTENT
                        g.ReleaseHdc(dc);
                    }
                    bmp.Save(shot, System.Drawing.Imaging.ImageFormat.Png);
                }
                form.Close();
            }
        };
        web.CoreWebView2.Navigate("https://" + WebFiles.Host + "/" + page);
    }
}
