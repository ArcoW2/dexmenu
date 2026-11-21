using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>The settings app's window (plan 00 step 4): two panes. Left, the layout and the kind of right-click
/// (web\index.html in WebView2); right, the preview, a window DexmenuShell.dll draws the menu into from the layout and
/// the items that kind of right-click showed. The layout file and the seen items are watched: a change redraws both.
/// </summary>
sealed class MainForm : Form
{
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly Panel previewPanel = new() { Dock = DockStyle.Fill };
    readonly SplitContainer split = new() { Dock = DockStyle.Fill, Orientation = Orientation.Vertical };
    readonly System.Windows.Forms.Timer settle = new() { Interval = 150 };
    readonly List<FileSystemWatcher> watchers = [];
    IntPtr preview;
    string kind;
    bool pageReady;

    public MainForm(string? kindArgument)
    {
        Text = "Dexmenu";
        Width = 1100;
        Height = 760;
        StartPosition = FormStartPosition.CenterScreen;
        kind = kindArgument ?? DataFolder.SeenKinds().FirstOrDefault() ?? "file";
        split.Panel1.Controls.Add(web);
        split.Panel2.Controls.Add(previewPanel);
        Controls.Add(split);
        settle.Tick += (_, _) => { settle.Stop(); Reload(); };
        previewPanel.Resize += (_, _) => FitPreview();
        Load += async (_, _) => await Start();
    }

    async Task Start()
    {
        split.SplitterDistance = Width * 45 / 100;
        preview = Native.DexmenuPreviewCreate(previewPanel.Handle);
        FitPreview();
        Watch();
        Reload();
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dexmenu", "WebView2");
        var env = await CoreWebView2Environment.CreateAsync(null, data);
        await web.EnsureCoreWebView2Async(env);
        web.CoreWebView2.SetVirtualHostNameToFolderMapping("dexmenu.app", Path.Combine(AppContext.BaseDirectory, "web"),
            CoreWebView2HostResourceAccessKind.Allow);
        web.CoreWebView2.WebMessageReceived += (_, e) => Received(e.WebMessageAsJson);
        web.CoreWebView2.NavigationCompleted += (_, _) => { pageReady = true; Reload(); };
        web.CoreWebView2.Navigate("https://dexmenu.app/index.html");
    }

    void FitPreview()
    {
        if (preview != IntPtr.Zero)
            Native.MoveWindow(preview, 0, 0, previewPanel.ClientSize.Width, previewPanel.ClientSize.Height, true);
    }

    // The layout file's folder and the seen items' folder: a change there reloads (after it settles).
    void Watch()
    {
        foreach (var w in watchers) w.Dispose();
        watchers.Clear();
        var folders = new List<string> { DataFolder.SeenFolder };
        if (DataFolder.LayoutFile is string file && Path.GetDirectoryName(file) is string dir) folders.Add(dir);
        folders.Add(DataFolder.Root);   // settings.json: another active layout
        foreach (var folder in folders.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(folder)) continue;
            var w = new FileSystemWatcher(folder) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, EnableRaisingEvents = true };
            w.Changed += Changed;
            w.Created += Changed;
            w.Renamed += Changed;
            watchers.Add(w);
        }
    }

    void Changed(object sender, FileSystemEventArgs e) => BeginInvoke(() => { settle.Stop(); settle.Start(); });

    string LayoutText(out string source)
    {
        if (DataFolder.LayoutFile is string file && File.Exists(file))
        {
            source = file;
            try { return File.ReadAllText(file); }
            catch (IOException) { }
        }
        source = "(built in)";
        return Native.BaseLayout();
    }

    void Reload()
    {
        var layout = LayoutText(out var source);
        var error = preview == IntPtr.Zero
            ? "DexmenuShell.dll did not make the preview"
            : Native.SetPreview(preview, layout, DataFolder.ReadSeen(kind), kind);
        if (!pageReady) return;
        var kinds = DataFolder.SeenKinds();
        if (!kinds.Contains(kind)) kinds = [kind, .. kinds];
        var message = JsonSerializer.Serialize(new { type = "state", kind, kinds, layout, source, error });
        web.CoreWebView2.PostWebMessageAsJson(message);
    }

    void Received(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.GetProperty("type").GetString() == "kind" && root.GetProperty("kind").GetString() is { Length: > 0 } k)
        {
            kind = k;
            Reload();
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var w in watchers) w.Dispose();
        base.OnFormClosed(e);
    }
}
