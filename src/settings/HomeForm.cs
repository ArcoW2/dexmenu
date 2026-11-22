using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>The main window (docs/plans/05-PLAN-settings-windows.md 3.3 - 3.5): only about Dexmenu itself, never inside
/// a layout. The page (web\main.html) has two panels: General (the registration; which layout each kind of
/// right-click gets, in the order they are tried) and Layouts (new, edit, copy, rename, delete). The page measures the
/// panels and tells the window its minimum size. settings.json and the layouts are watched, so another window's
/// change shows here at once.</summary>
sealed class HomeForm : Form, IThemed
{
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly System.Windows.Forms.Timer settle = new() { Interval = 150 };
    readonly System.Windows.Forms.Timer explorerCheck = new() { Interval = 1500 };
    readonly List<FileSystemWatcher> watchers = [];
    bool pageReady;
    bool restartPending;            // a registration change Explorer has not taken yet (Restart Explorer lit)
    HashSet<int> explorersAtChange = [];

    public HomeForm()
    {
        Text = "Dexmenu";
        // opens as tabs: narrower than both panels side by side, lower than both above each other (main.css minimums)
        Width = 720;
        Height = 720;
        StartPosition = FormStartPosition.CenterScreen;
        Controls.Add(web);
        settle.Tick += (_, _) => { settle.Stop(); PostState(); };
        explorerCheck.Tick += (_, _) => CheckExplorer();
        HandleCreated += (_, _) => Themes.Apply(this, web);
        Load += async (_, _) =>
        {
            Watch();
            await Pages.Start(web, "main.html", Received, () => { pageReady = true; Themes.Apply(this, web); PostState(); });
        };
    }

    public void ApplyTheme()
    {
        Themes.Apply(this, web);
        PostState();
    }

    void Watch()
    {
        foreach (var folder in new[] { DataFolder.Root, Path.Combine(DataFolder.Root, "layouts") })
        {
            Directory.CreateDirectory(folder);
            var w = new FileSystemWatcher(folder) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, EnableRaisingEvents = true };
            w.Changed += Changed;
            w.Created += Changed;
            w.Deleted += Changed;
            w.Renamed += Changed;
            watchers.Add(w);
        }
    }

    void Changed(object sender, FileSystemEventArgs e) => BeginInvoke(() => { settle.Stop(); settle.Start(); });

    static HashSet<int> Explorers()
    {
        var session = Process.GetCurrentProcess().SessionId;
        return Process.GetProcessesByName("explorer").Where(p => p.SessionId == session).Select(p => p.Id).ToHashSet();
    }

    // Restart Explorer stays lit until Explorer has started again (from the button, or otherwise): a new process.
    void CheckExplorer()
    {
        if (!restartPending) { explorerCheck.Stop(); return; }
        var now = Explorers();
        if (now.Count > 0 && !now.IsSubsetOf(explorersAtChange))
        {
            restartPending = false;
            explorerCheck.Stop();
            PostState();
        }
    }

    void PostState()
    {
        if (!pageReady) return;
        var dll = Registration.RegisteredDll;
        var ours = dll is not null && string.Equals(Path.GetFullPath(dll), Path.GetFullPath(Registration.DllPath), StringComparison.OrdinalIgnoreCase);
        var layouts = LayoutFiles.Names();
        Post(new
        {
            type = "state",
            registration = new { registered = dll is not null, ours, dll, enabled = Registration.Enabled, restartPending },
            kinds = DataFolder.Kinds().Select(k => new { kind = k.Kind, name = DataFolder.KindNames.GetValueOrDefault(k.Kind, k.Kind), layout = k.Layout }),
            layouts = layouts.Select(n => new { name = n, kinds = LayoutFiles.KindsOf(n).Select(k => DataFolder.KindNames.GetValueOrDefault(k, k)) }),
            theme = DataFolder.Theme,
        });
    }

    void Post(object message) => web.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(message));

    void Problem(string text) => Post(new { type = "problem", text });

    void Received(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var m = doc.RootElement;
        string Str(string name) => m.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
        try
        {
            switch (Str("type"))
            {
                case "register":
                case "unregister":
                    if (Str("type") == "register") Registration.Register(); else Registration.Unregister();
                    restartPending = true;
                    explorersAtChange = Explorers();
                    explorerCheck.Start();
                    PostState();
                    break;
                case "restart":
                    Registration.RestartExplorer();
                    restartPending = false;
                    PostState();
                    break;
                case "setKind":
                    DataFolder.SetLayout(Str("kind"), m.TryGetProperty("layout", out var l) && l.ValueKind == JsonValueKind.String ? l.GetString() : null);
                    PostState();
                    break;
                case "moveKind":
                    DataFolder.MoveKind(m.GetProperty("from").GetInt32(), m.GetProperty("to").GetInt32());
                    PostState();
                    break;
                case "edit":
                    DexmenuApp.Instance.OpenEditor(Str("name"));
                    break;
                case "new":
                    if (LayoutFiles.Problem(Str("name")) is { } p1) { Problem(p1); break; }
                    LayoutFiles.New(Str("name"), Native.BaseLayout());
                    DexmenuApp.Instance.OpenEditor(Str("name").Trim());
                    PostState();
                    break;
                case "copy":
                    if (LayoutFiles.Problem(Str("to")) is { } p2) { Problem(p2); break; }
                    LayoutFiles.Copy(Str("from"), Str("to"));
                    PostState();
                    break;
                case "rename":
                    if (LayoutFiles.Problem(Str("to")) is { } p3) { Problem(p3); break; }
                    LayoutFiles.Rename(Str("from"), Str("to"));
                    DexmenuApp.Instance.Renamed(Str("from"), Str("to").Trim());
                    PostState();
                    break;
                case "delete":
                    LayoutFiles.Delete(Str("name"));
                    PostState();
                    break;
                case "theme":
                    DataFolder.Theme = Str("theme");
                    DexmenuApp.Instance.ThemeChanged();
                    break;
                case "minsize":
                    // the page's minimum (CSS pixels) as the window's minimum, its frame added
                    var scale = DeviceDpi / 96.0;
                    MinimumSize = SizeFromClientSize(new Size((int)Math.Ceiling(m.GetProperty("w").GetDouble() * scale),
                        (int)Math.Ceiling(m.GetProperty("h").GetDouble() * scale)));
                    break;
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            Problem(e.Message);
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var w in watchers) w.Dispose();
        base.OnFormClosed(e);
    }
}
