using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>The settings app's window (plan 00 steps 4 and 5): two panes. Left, the layout editor (web\index.html in
/// WebView2); right, the preview, a window DexmenuShell.dll draws the menu into from the layout being edited and the
/// items that kind of right-click showed. Every edit goes to the preview at once; saving writes the layout file. The
/// file, settings.json and the seen items are watched: a change reloads them (an unsaved edit is kept). An item hovered
/// or clicked in the preview selects the card and rule that placed it; a card selected marks its items there.
/// With --selftest &lt;file&gt; it runs the editor's self-test (web\selftest.html) instead, writes its lines to the file
/// and exits with the number of failures.</summary>
sealed class MainForm : Form
{
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly Panel previewPanel = new() { Dock = DockStyle.Fill };
    readonly SplitContainer split = new() { Dock = DockStyle.Fill, Orientation = Orientation.Vertical };
    readonly System.Windows.Forms.Timer settle = new() { Interval = 150 };
    readonly List<FileSystemWatcher> watchers = [];
    readonly Native.PreviewCallback callback;   // kept: the DLL holds it
    readonly string? selftest;
    IntPtr preview;
    string kind;
    string? currentFile;     // the layout file being edited; null: the built-in base layout
    string? editedText;      // an edit not yet saved
    bool pageReady;

    public MainForm(string? kindArgument, string? selftestFile)
    {
        Text = "Dexmenu";
        Width = 1500;
        Height = 820;
        StartPosition = FormStartPosition.CenterScreen;
        selftest = selftestFile;
        kind = kindArgument ?? DataFolder.SeenKinds().FirstOrDefault() ?? "file";
        currentFile = DataFolder.LayoutFile;
        callback = Placed;
        split.Panel1.Controls.Add(web);
        split.Panel2.Controls.Add(previewPanel);
        Controls.Add(split);
        settle.Tick += (_, _) => { settle.Stop(); Reload(); };
        previewPanel.Resize += (_, _) => FitPreview();
        Load += async (_, _) => await Start();
    }

    async Task Start()
    {
        split.SplitterDistance = Width * 70 / 100;   // the page's three panes, then the preview
        if (selftest is null)
        {
            preview = Native.DexmenuPreviewCreate(previewPanel.Handle);
            if (preview != IntPtr.Zero) Native.DexmenuPreviewSetCallback(preview, callback);
            FitPreview();
            Watch();
            Reload();
        }
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dexmenu", "WebView2");
        var env = await CoreWebView2Environment.CreateAsync(null, data);
        await web.EnsureCoreWebView2Async(env);
        WebFiles.Serve(web.CoreWebView2);
        web.CoreWebView2.WebMessageReceived += (_, e) => Received(e.WebMessageAsJson);
        web.CoreWebView2.NavigationCompleted += (_, _) => { pageReady = true; Reload(); };
        web.CoreWebView2.Navigate("https://dexmenu.app/" + (selftest is null ? "index.html" : "selftest.html"));
    }

    void FitPreview()
    {
        if (preview != IntPtr.Zero)
            Native.MoveWindow(preview, 0, 0, previewPanel.ClientSize.Width, previewPanel.ClientSize.Height, true);
    }

    // The layout file's folder, the data folder (settings.json) and the seen items: a change reloads (after it settles).
    void Watch()
    {
        foreach (var w in watchers) w.Dispose();
        watchers.Clear();
        var folders = new List<string> { DataFolder.SeenFolder, DataFolder.Root };
        if (currentFile is not null && Path.GetDirectoryName(currentFile) is string dir) folders.Add(dir);
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

    string FileText(out string source)
    {
        if (currentFile is not null && File.Exists(currentFile))
        {
            source = currentFile;
            try { return File.ReadAllText(currentFile); }
            catch (IOException) { }
        }
        source = "(built in)";
        return Native.BaseLayout();
    }

    string? LayoutName => currentFile is null ? null : Path.GetFileNameWithoutExtension(currentFile);

    static string[] LayoutNames()
    {
        var folder = Path.Combine(DataFolder.Root, "layouts");
        return Directory.Exists(folder) ? Directory.GetFiles(folder, "*.json").Select(Path.GetFileNameWithoutExtension).OfType<string>().ToArray() : [];
    }

    static string? ActiveName()
    {
        var path = Path.Combine(DataFolder.Root, "settings.json");
        try { return File.Exists(path) && JsonNode.Parse(File.ReadAllText(path))?["layout"]?.GetValue<string>() is string n ? n : null; }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException) { return null; }
    }

    // The preview from the edit in progress or the file; the page gets the file's state when nothing is being edited.
    void Reload()
    {
        if (selftest is not null) return;
        var text = FileText(out var source);
        var error = preview == IntPtr.Zero
            ? "DexmenuShell.dll did not make the preview"
            : Native.SetPreview(preview, editedText ?? text, DataFolder.ReadSeen(kind), kind);
        if (!pageReady) return;
        var kinds = DataFolder.SeenKinds();
        if (!kinds.Contains(kind)) kinds = [kind, .. kinds];
        if (editedText is not null)
        {
            Post(new { type = "preview", error });
            return;
        }
        Post(new { type = "state", kind, kinds, layout = text, source, name = LayoutName, layouts = LayoutNames(), active = ActiveName(), error,
            registration = RegistrationState() });
    }

    void Post(object message) => web.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(message));

    void Placed(int previewEvent, string cardId, int rule) =>
        Post(new { type = "placed", @event = previewEvent, cardId, rule });

    void Received(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var m = doc.RootElement;
        string Str(string name) => m.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
        switch (Str("type"))
        {
            case "selftest":
                File.WriteAllLines(selftest!, m.GetProperty("lines").EnumerateArray().Select(l => l.GetString() ?? ""));
                Environment.Exit(m.GetProperty("failures").GetInt32());
                break;
            case "kind":
                if (Str("kind") is { Length: > 0 } k) { kind = k; Reload(); }
                break;
            case "edit":
                // quiet: the editor only added ids to what it loaded; the preview gets them, but it is no unsaved change,
                // so the file on disk is still followed
                if (!m.TryGetProperty("quiet", out _)) editedText = Str("layout");
                Post(new { type = "preview", error = Native.SetPreview(preview, Str("layout"), DataFolder.ReadSeen(kind), kind) });
                break;
            case "save":
                Save(Str("name"), Str("layout"));
                break;
            case "open":
                if (Str("name") is { Length: > 0 } open)
                {
                    currentFile = Path.Combine(DataFolder.Root, "layouts", open + ".json");
                    editedText = null;
                    Watch();
                    Reload();
                }
                break;
            case "activate":
                Activate(Str("name"));
                break;
            case "mark":
                if (preview != IntPtr.Zero) Native.DexmenuPreviewMark(preview, Str("cardId"));
                break;
            case "register":
            case "unregister":
                try
                {
                    if (Str("type") == "register") Registration.Register(); else Registration.Unregister();
                    if (m.TryGetProperty("restart", out var restart) && restart.GetBoolean()) Registration.RestartExplorer();
                    Post(new { type = "registration", registration = RegistrationState() });
                }
                catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException or IOException)
                {
                    Post(new { type = "registration", registration = RegistrationState(), error = e.Message });
                }
                break;
        }
    }

    // What the page shows about the registration: on for this user (this app's DLL), another DLL registered, or off.
    static object RegistrationState()
    {
        var dll = Registration.RegisteredDll;
        var ours = dll is not null && string.Equals(Path.GetFullPath(dll), Path.GetFullPath(Registration.DllPath), StringComparison.OrdinalIgnoreCase);
        return new { registered = dll is not null, ours, dll, enabled = Registration.Enabled };
    }

    // The layout written under a name (layouts\<name>.json); with DEXMENU_LAYOUT_FILE (the tests) to that file.
    void Save(string name, string text)
    {
        if (name.Length == 0 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return;
        var path = Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is { Length: > 0 } env && Path.GetFileNameWithoutExtension(env) == name
            ? env
            : Path.Combine(DataFolder.Root, "layouts", name + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text + Environment.NewLine);
        currentFile = path;
        editedText = null;
        Watch();
        Post(new { type = "saved" });
        Reload();
    }

    // settings.json's "layout": the layout Dexmenu uses at a right-click; its other settings kept.
    static void Activate(string name)
    {
        if (name.Length == 0) return;
        var path = Path.Combine(DataFolder.Root, "settings.json");
        JsonObject settings;
        try { settings = File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject o ? o : []; }
        catch (JsonException) { settings = []; }
        settings["layout"] = name;
        Directory.CreateDirectory(DataFolder.Root);
        File.WriteAllText(path, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var w in watchers) w.Dispose();
        base.OnFormClosed(e);
    }
}
