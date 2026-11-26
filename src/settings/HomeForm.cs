using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>The main window (docs/plans/executed/05-PLAN-settings-windows.md 3.3 - 3.5): only about Dexmenu itself, never inside
/// a layout. The page (web\main.html) has its panels as tabs: General (the registration; every menu's settings by
/// what they are about: action, collecting, look), Right-clicks (which layout each kind of right-click gets, in the
/// order they are tried), Layouts (new, edit, copy, rename, delete) and Diagnostics (plan 16: the extensions timed,
/// the last right-clicks' timings per program). The page measures the
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
    readonly System.Windows.Forms.Timer timingsSettle = new() { Interval = 300 };
    bool measuring;                 // a Diagnostics measurement runs (one at a time)
    CancellationTokenSource? stopCurrent;   // Stop: the handler being measured now stopped

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
        timingsSettle.Tick += (_, _) => { timingsSettle.Stop(); PostDiagnostics(); };
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
        // the right-clicks' timings, written by the DLL after each menu (plan 16 3.2)
        var timings = Diagnostics.TimingsFile;
        Directory.CreateDirectory(Path.GetDirectoryName(timings)!);
        var t = new FileSystemWatcher(Path.GetDirectoryName(timings)!, Path.GetFileName(timings))
            { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, EnableRaisingEvents = true };
        FileSystemEventHandler again = (_, _) => BeginInvoke(() => { timingsSettle.Stop(); timingsSettle.Start(); });
        t.Changed += again;
        t.Created += again;
        t.Renamed += (_, _) => BeginInvoke(() => { timingsSettle.Stop(); timingsSettle.Start(); });
        watchers.Add(t);
    }

    // ---- Diagnostics (plan 16) ------------------------------------------------------------------------------------

    void PostDiagnostics()
    {
        if (!pageReady) return;
        var message = new System.Text.Json.Nodes.JsonObject
        {
            ["type"] = "diagnostics",
            ["measured"] = Diagnostics.MeasuredNow(),
            ["timings"] = Diagnostics.TimingEntries(),
            ["hangSeconds"] = Diagnostics.HangSeconds,
            ["profile"] = Diagnostics.Profile,
            ["measuring"] = measuring,
            ["dexmenu"] = Registration.Clsid,
        };
        web.CoreWebView2?.PostWebMessageAsJson(message.ToJsonString());
    }

    // Each handler of the kind in a measuring process of its own, one after another, the page told which one runs;
    // the result kept (Diagnostics.KeepMeasured) and shown.
    async Task Measure(string kind, string? file)
    {
        if (measuring || !Diagnostics.Kinds.Contains(kind)) return;
        measuring = true;
        var invariant = System.Globalization.CultureInfo.InvariantCulture;
        try
        {
            var hang = Diagnostics.HangSeconds;
            var sample = Diagnostics.Sample(kind, file);
            var handlers = Diagnostics.Handlers(kind, sample);
            var result = new System.Text.Json.Nodes.JsonObject
            {
                ["at"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", invariant),
                ["sample"] = sample,
                ["hangSeconds"] = hang,
            };
            Post(new { type = "measuring", kind, name = "Windows' whole menu", index = 0, count = handlers.Count });
            stopCurrent = new CancellationTokenSource();
            string[] menuArgs = ["--measure-menu", kind, sample, hang.ToString(invariant)];
            if (Diagnostics.Profile) menuArgs = [.. menuArgs, "profile"];
            result["windows"] = await Diagnostics.RunMeasuring(menuArgs, hang, stopCurrent.Token)
                ?? new System.Text.Json.Nodes.JsonObject { ["stopped"] = true };
            var list = new System.Text.Json.Nodes.JsonArray();
            for (var i = 0; i < handlers.Count; i++)
            {
                var h = handlers[i];
                var entry = new System.Text.Json.Nodes.JsonObject
                {
                    ["clsid"] = h.Clsid, ["name"] = h.Name, ["key"] = h.Key, ["dll"] = h.Dll,
                    ["blocked"] = h.Blocked, ["byDexmenu"] = h.ByDexmenu, ["packaged"] = h.Packaged,
                };
                if (h.Blocked is null)
                {
                    Post(new { type = "measuring", kind, name = h.Name, index = i + 1, count = handlers.Count });
                    stopCurrent = new CancellationTokenSource();
                    string[] handlerArgs = ["--measure-handler", kind, sample, h.Clsid, hang.ToString(invariant)];
                    if (h.Packaged) handlerArgs = [.. handlerArgs, "packaged"];
                    var r = await Diagnostics.RunMeasuring(handlerArgs, hang, stopCurrent.Token);
                    if (r is null) entry["stopped"] = true;
                    else foreach (var (k, v) in r) entry[k] = v?.DeepClone();
                }
                list.Add(entry);
            }
            result["handlers"] = list;
            Diagnostics.KeepMeasured(kind, result);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            Problem("Measuring stopped: " + e.Message);
        }
        finally
        {
            measuring = false;
            stopCurrent = null;
            PostDiagnostics();
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
            theme = Themes.Name,
            menu = DataFolder.Menu(),
            themes = DataFolder.ThemeNames(),
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
                case "closeReady":
                    BeginInvoke(CloseNow);
                    break;
                case "diagnostics":
                    PostDiagnostics();
                    break;
                case "measure":
                    _ = Measure(Str("kind"), Str("file") is { Length: > 0 } f ? f : null);
                    break;
                case "stopMeasure":
                    stopCurrent?.Cancel();
                    break;
                case "pickMeasureFile":
                    using (var dialog = new OpenFileDialog { Title = "A file to measure the extensions with" })
                    {
                        if (dialog.ShowDialog(this) == DialogResult.OK) Post(new { type = "pickedMeasureFile", path = dialog.FileName });
                    }
                    break;
                case "switchHandler":
                    Diagnostics.Switch(Str("clsid"), Str("name"), m.TryGetProperty("off", out var off) && off.ValueKind == JsonValueKind.True);
                    PostDiagnostics();
                    break;
                case "setProfile":
                    Diagnostics.Profile = m.TryGetProperty("value", out var pv) && pv.ValueKind == JsonValueKind.True;
                    PostDiagnostics();
                    break;
                case "setHang":
                    if (m.TryGetProperty("value", out var hv) && hv.TryGetDouble(out var hs) && hs > 0) Diagnostics.HangSeconds = hs;
                    PostDiagnostics();
                    break;
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
                case "setMenu":
                    // one setting: submenus (next, under, replace) or a true / false one
                    var name = Str("name");
                    if (name == "submenus") DataFolder.SetMenu(name, Str("value") is "under" or "replace" ? Str("value") : "next");
                    else if (name == "onClickOnly")
                        DataFolder.SetMenu(name, m.TryGetProperty("value", out var on) && on.ValueKind == JsonValueKind.True);
                    else if (name is "submenuMark" or "actionMark") DataFolder.SetMenu(name, Str("value"));
                    else if (name is "themeLight" or "themeDark" && Str("value").Length > 0) DataFolder.SetMenu(name, Str("value"));
                    else if (name == "textSize" && m.TryGetProperty("value", out var t) && t.TryGetDouble(out var size))
                        DataFolder.SetMenu(name, Math.Clamp(Math.Round(size, 1), 0.6, 2.5));
                    else if (name == "states") DataFolder.SetMenu(name, Str("value") is "enabled" or "disabled" ? Str("value") : "both");
                    else if (name == "widths" && m.TryGetProperty("value", out var widths) && widths.ValueKind == JsonValueKind.Array)
                        DataFolder.SetMenu(name, System.Text.Json.Nodes.JsonNode.Parse(widths.GetRawText())!);
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
                    Themes.Toggle();
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

    // Closing by the user: the field being typed in left first, so its change is saved (the page posts it, then
    // "closeReady"; the page's messages come in the order sent), then closed. A page that does not answer within a
    // second: closed anyway.
    bool closeReady;
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!closeReady && e.CloseReason == CloseReason.UserClosing && pageReady && web.CoreWebView2 is not null)
        {
            e.Cancel = true;
            _ = web.CoreWebView2.ExecuteScriptAsync(
                "if (document.activeElement && document.activeElement.blur) document.activeElement.blur();" +
                "chrome.webview.postMessage({ type: 'closeReady' });");
            var fallback = new System.Windows.Forms.Timer { Interval = 1000 };
            fallback.Tick += (_, _) => { fallback.Dispose(); CloseNow(); };
            fallback.Start();
            return;
        }
        base.OnFormClosing(e);
    }

    void CloseNow()
    {
        if (closeReady || IsDisposed) return;
        closeReady = true;
        Close();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var w in watchers) w.Dispose();
        base.OnFormClosed(e);
    }
}
