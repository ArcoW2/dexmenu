using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>A layout's editor window (plan 00 steps 4 and 5; docs/plans/05-PLAN-settings-windows.md 3.6): one layout,
/// named in the title; several can be open. Left, the layout editor (web\index.html in WebView2); right, the preview, a window DexmenuShell.dll draws the menu into from the layout being edited and the
/// items that kind of right-click showed. Every edit goes to the preview at once; saving writes the layout file. The
/// file, settings.json and the seen items are watched: a change reloads them (an unsaved edit is kept). An item hovered
/// or clicked in the preview selects the card and rule that placed it; a card selected marks its items there.
/// Above the preview: the kind of right-click, and a base folder with the item(s) right-clicked in it; with a folder
/// the preview shows Windows' real menu of that right-click there (ShellMenu: a Git folder differs from an SVN one),
/// the seen items' others striped; without one, the seen items of that kind.
/// Every kind can be chosen for the preview; one this layout is not set for says so. Closing with unsaved changes
/// asks to save them. With --selftest &lt;file&gt; it runs the editor's self-test (web\selftest.html) instead, writes
/// its lines to the file and exits with the number of failures.</summary>
sealed class EditorForm : Form, IThemed
{
    readonly Label notMeant = new() { AutoSize = true, ForeColor = Color.DarkGoldenrod, Padding = new Padding(0, 6, 0, 0),
        Text = "This layout is not meant for this kind" };
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly Panel previewPanel = new() { Dock = DockStyle.Fill };
    readonly FlowLayoutPanel previewBar = new() { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Padding = new Padding(4) };
    readonly ComboBox kindBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 150 };
    readonly TextBox folderBox = new() { ReadOnly = true, Width = 230, PlaceholderText = "no folder: the seen items" };
    readonly Button folderButton = new() { Text = "Folder...", AutoSize = true };
    readonly Button noFolderButton = new() { Text = "x", Width = 24 };
    readonly Button lastButton = new() { Text = "Last right-click", AutoSize = true };
    bool applying;           // the bar set from the last right-click: its own change events wait
    readonly bool startOnLast;   // no --kind given: the preview starts on the last right-click
    readonly ComboBox itemBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
    readonly Button itemsButton = new() { AutoSize = true };
    readonly CheckedListBox itemsList = new() { CheckOnClick = true, Width = 260, Height = 300, BorderStyle = BorderStyle.None };
    readonly ToolStripDropDown itemsDrop = new() { Padding = Padding.Empty };
    readonly Label liveError = new() { AutoSize = true, ForeColor = Color.Firebrick, Padding = new Padding(0, 6, 0, 0) };
    string? folder;          // the base folder; null: the seen items
    string? liveSeen;        // Windows' real menu there, as seen items' text (merged with the seen file)
    readonly SplitContainer split = new() { Dock = DockStyle.Fill, Orientation = Orientation.Vertical, SplitterWidth = 6 };
    readonly System.Windows.Forms.Timer settle = new() { Interval = 150 };
    readonly List<FileSystemWatcher> watchers = [];
    readonly Native.PreviewCallback callback;   // kept: the DLL holds it
    readonly string? selftest;
    IntPtr preview;
    string kind;
    string? currentFile;     // the layout file being edited; null: the built-in base layout
    string? editedText;      // an edit not yet saved
    bool pageReady;

    /// <summary>layoutFile: the layout this window edits (null: the built-in base layout, the tests).</summary>
    public EditorForm(string? layoutFile, string? kindArgument, string? selftestFile)
    {
        Width = 1500;
        Height = 820;
        StartPosition = FormStartPosition.CenterScreen;
        selftest = selftestFile;
        currentFile = layoutFile;
        kind = kindArgument ?? FirstKindOfThis() ?? DataFolder.SeenKinds().FirstOrDefault() ?? "file";
        startOnLast = kindArgument is null;
        SetTitle();
        callback = Placed;
        split.Panel1.Controls.Add(web);
        split.Panel2.Controls.Add(previewPanel);
        split.Panel2.Controls.Add(previewBar);
        previewPanel.BringToFront();   // docked last: the room the bar leaves
        BuildPreviewBar();
        Controls.Add(split);
        settle.Tick += (_, _) => { settle.Stop(); Reload(); };
        previewPanel.Resize += (_, _) => FitPreview();
        HandleCreated += (_, _) => Themes.Apply(this, web);
        FormClosing += AskToSave;
        Load += async (_, _) => await Start();
    }

    public string? LayoutName => currentFile is null ? null : Path.GetFileNameWithoutExtension(currentFile);

    void SetTitle() => Text = "Dexmenu - " + (LayoutName ?? "(built in)");

    // A kind of right-click this layout is set for, for the preview to start on.
    string? FirstKindOfThis() =>
        LayoutName is { } n ? DataFolder.Kinds().Where(k => string.Equals(k.Layout, n, StringComparison.OrdinalIgnoreCase))
            .Select(k => k.Kind.StartsWith("dialog-") ? k.Kind["dialog-".Length..] : k.Kind)
            .FirstOrDefault(k => Kinds.Any(x => x.Kind == k)) : null;

    public void ApplyTheme()
    {
        Themes.Apply(this, web);
        // the splitter before the preview: in the line colour, so it shows on either theme (it is drawn in the
        // SplitContainer's own colour; the panes keep the window's)
        split.BackColor = Themes.Dark ? Color.FromArgb(0x3A, 0x3A, 0x3A) : Color.FromArgb(0xD0, 0xD0, 0xD0);
        split.Panel1.BackColor = split.Panel2.BackColor = BackColor;
        previewBar.BackColor = BackColor;
        previewBar.ForeColor = ForeColor;
        if (preview != IntPtr.Zero) Native.MoveWindow(preview, 0, 0, previewPanel.ClientSize.Width, previewPanel.ClientSize.Height, true);
        Post(new { type = "theme", theme = DataFolder.Theme });
        Reload();
    }

    /// <summary>The file renamed elsewhere (the main window's Rename): this window edits it under its new name.</summary>
    public void FileRenamed(string path)
    {
        currentFile = path;
        SetTitle();
        Watch();
        Reload();
    }

    // Closing with unsaved changes (plan 05 3.6): Yes saves them, No closes without, Cancel stays open.
    void AskToSave(object? sender, FormClosingEventArgs e)
    {
        if (editedText is null || selftest is not null) return;
        var answer = MessageBox.Show(this, $"Save the changes to \"{LayoutName ?? "the layout"}\"?", "Dexmenu",
            MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (answer == DialogResult.Cancel) { e.Cancel = true; return; }
        if (answer == DialogResult.Yes && !Save(LayoutName ?? "Default", editedText)) e.Cancel = true;
    }

    async Task Start()
    {
        // Each half a minimum (plan 05 3.6): the page holds its three panes at their minimum (rules 160, cards 260, the
        // card's panel 200 CSS pixels, the splitters and the scrollbar), the preview a narrow menu; the window not
        // smaller than both.
        var scale = DeviceDpi / 96.0;
        split.Panel1MinSize = (int)Math.Ceiling(660 * scale);
        split.Panel2MinSize = (int)Math.Ceiling(300 * scale);
        MinimumSize = SizeFromClientSize(new Size(split.Panel1MinSize + split.Panel2MinSize + split.SplitterWidth, (int)(520 * scale)));
        split.SplitterDistance = Math.Max(split.Panel1MinSize, Width * 70 / 100);   // the page's three panes, then the preview
        if (selftest is null)
        {
            preview = Native.DexmenuPreviewCreate(previewPanel.Handle);
            if (preview != IntPtr.Zero) Native.DexmenuPreviewSetCallback(preview, callback);
            FitPreview();
            Watch();
            if (startOnLast) ApplyLastRightClick();
            Reload();
        }
        await Pages.Start(web, selftest is null ? "index.html" : "selftest.html", Received,
            () => { pageReady = true; ApplyTheme(); });
    }

    static readonly (string Kind, string Name)[] Kinds =
        [("file", "a file"), ("folder", "a folder"), ("several", "several items"), ("background", "a folder's empty part"),
         ("desktop", "the desktop's empty part"), ("drive", "a drive")];

    void BuildPreviewBar()
    {
        Label Text(string t) => new() { Text = t, AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
        foreach (var (k, name) in Kinds) kindBox.Items.Add(name);
        if (!Kinds.Any(x => x.Kind == kind)) kind = "file";
        kindBox.SelectedIndex = Array.FindIndex(Kinds, x => x.Kind == kind);
        itemsDrop.Items.Add(new ToolStripControlHost(itemsList) { Padding = Padding.Empty, AutoSize = false, Size = itemsList.Size });
        previewBar.Controls.AddRange([Text("Right-click on"), kindBox, Text("in"), folderBox, folderButton, noFolderButton, itemBox, itemsButton,
            lastButton, notMeant, liveError]);
        kindBox.SelectedIndexChanged += (_, _) => { if (applying) return; kind = Kinds[kindBox.SelectedIndex].Kind; FillItems(); Live(); Reload(); };
        lastButton.Click += (_, _) => ApplyLastRightClick();
        lastButton.Enabled = DataFolder.LastRightClick() is not null;
        folderButton.Click += (_, _) =>
        {
            using var dialog = new FolderBrowserDialog { SelectedPath = folder ?? "", Description = "The folder in which the preview's right-click is" };
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            folder = dialog.SelectedPath;
            FillItems();
            Live();
            Reload();
        };
        noFolderButton.Click += (_, _) => { folder = null; FillItems(); Live(); Reload(); };
        itemBox.SelectedIndexChanged += (_, _) => { if (itemBox.Visible && !applying) { Live(); Reload(); } };
        itemsButton.Click += (_, _) => itemsDrop.Show(itemsButton, 0, itemsButton.Height);
        itemsList.ItemCheck += (_, _) => { if (!applying) BeginInvoke(() => { ItemsButtonText(); Live(); Reload(); }); };
        FillItems();
    }

    // The preview set to the last right-click Dexmenu showed its menu for (DataFolder.LastRightClick): its kind, its
    // folder and the items right-clicked there, so the live menu is that right-click's.
    void ApplyLastRightClick()
    {
        if (DataFolder.LastRightClick() is not { } last || !Kinds.Any(x => x.Kind == last.Kind) || !Directory.Exists(last.Folder)) return;
        applying = true;
        try
        {
            kind = last.Kind;
            kindBox.SelectedIndex = Array.FindIndex(Kinds, x => x.Kind == kind);
            folder = last.Folder;
            FillItems();
            var names = last.Items.Select(Path.GetFileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (itemBox.Visible)
                for (var i = 0; i < itemBox.Items.Count; i++)
                    if (itemBox.Items[i] is string name && names.Contains(name)) { itemBox.SelectedIndex = i; break; }
            if (itemsButton.Visible)
                for (var i = 0; i < itemsList.Items.Count; i++) itemsList.SetItemChecked(i, itemsList.Items[i] is string name && names.Contains(name));
            ItemsButtonText();
        }
        finally { applying = false; }
        Live();
        Reload();
    }

    // The items the kind right-clicks in the folder: files (a file), subfolders (a folder), both (several); the first
    // ones chosen. The folder's empty part and the drive need none.
    void FillItems()
    {
        folderBox.Text = folder ?? "";
        noFolderButton.Visible = folder is not null;
        var entries = new List<string>();
        if (folder is not null && Directory.Exists(folder))
        {
            var info = new DirectoryInfo(folder);
            bool Shown(FileSystemInfo f) => (f.Attributes & (FileAttributes.Hidden | FileAttributes.System)) == 0;
            try
            {
                if (kind is "folder" or "several")
                    entries.AddRange(info.EnumerateDirectories().Where(Shown).Select(d => d.Name).Order(StringComparer.OrdinalIgnoreCase));
                if (kind is "file" or "several")
                    entries.AddRange(info.EnumerateFiles().Where(Shown).Select(f => f.Name).Order(StringComparer.OrdinalIgnoreCase));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        var one = folder is not null && kind is "file" or "folder";
        itemBox.Visible = false;
        itemBox.Items.Clear();
        if (one)
        {
            itemBox.Items.AddRange([.. entries]);
            if (entries.Count > 0) itemBox.SelectedIndex = 0;
        }
        itemBox.Visible = one;
        itemsList.Items.Clear();
        for (var i = 0; i < entries.Count; i++) itemsList.Items.Add(entries[i], kind == "several" && i < 2);
        itemsButton.Visible = folder is not null && kind == "several";
        ItemsButtonText();
    }

    void ItemsButtonText()
    {
        var n = itemsList.CheckedItems.Count;
        itemsButton.Text = n == 0 ? "Choose items..." : n + (n == 1 ? " item: " : " items: ") + string.Join(", ", itemsList.CheckedItems.Cast<string>().Take(2)) + (n > 2 ? ", ..." : "");
    }

    // Windows' real menu of the right-click in the folder, or none (the seen items). The desktop's empty part is the
    // desktop's, whatever the folder.
    void Live()
    {
        liveSeen = null;
        liveError.Text = "";
        if (kind == "desktop")
        {
            liveSeen = ShellMenu.SeenOf(Handle, "background", Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), [],
                DataFolder.ReadSeen(kind), out var desktopError);
            liveError.Text = desktopError;
            return;
        }
        if (folder is null) return;
        IReadOnlyList<string> chosen = kind switch
        {
            "file" or "folder" => itemBox.SelectedItem is string s ? [Path.Combine(folder, s)] : [],
            "several" => itemsList.CheckedItems.Cast<string>().Select(s => Path.Combine(folder, s)).ToList(),
            _ => [],
        };
        if (kind is "file" or "folder" or "several" && chosen.Count == 0) { liveError.Text = "nothing to right-click here"; return; }
        Cursor = Cursors.WaitCursor;
        try
        {
            liveSeen = ShellMenu.SeenOf(Handle, kind, folder, chosen, DataFolder.ReadSeen(kind), out var error);
            liveError.Text = error;
        }
        finally { Cursor = Cursors.Default; }
    }

    string SeenText() => liveSeen ?? DataFolder.ReadSeen(kind);

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

    // The preview from the edit in progress or the file; the page gets the file's state when nothing is being edited.
    void Reload()
    {
        if (selftest is not null) return;
        lastButton.Enabled = DataFolder.LastRightClick() is not null;
        // a kind this layout is not set for (as the DLL decides; tests: one layout for every kind)
        notMeant.Visible = LayoutName is { } me && Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is not { Length: > 0 }
            && !string.Equals(DataFolder.Resolve(kind), me, StringComparison.OrdinalIgnoreCase);
        var text = FileText(out var source);
        var error = preview == IntPtr.Zero
            ? "DexmenuShell.dll did not make the preview"
            : Native.SetPreview(preview, editedText ?? text, SeenText(), kind);
        if (!pageReady) return;
        if (editedText is not null)
        {
            Post(new { type = "preview", error });
            return;
        }
        Post(new { type = "state", kind, kindName = Kinds.FirstOrDefault(x => x.Kind == kind).Name ?? kind, layout = text, source,
            name = LayoutName, theme = DataFolder.Theme, error });
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
            case "edit":
                // quiet: the editor only added ids to what it loaded; the preview gets them, but it is no unsaved change,
                // so the file on disk is still followed
                if (!m.TryGetProperty("quiet", out _)) editedText = Str("layout");
                Post(new { type = "preview", error = Native.SetPreview(preview, Str("layout"), SeenText(), kind) });
                break;
            case "save":
                Save(Str("name"), Str("layout"));
                break;
            case "saveAs":
                if (LayoutFiles.Problem(Str("name")) is { } problem) { Post(new { type = "problem", text = problem }); break; }
                Save(Str("name"), Str("layout"), asCopy: true);
                break;
            case "close":
                Close();
                break;
            case "theme":
                DataFolder.Theme = Str("theme");
                DexmenuApp.Instance?.ThemeChanged();
                if (DexmenuApp.Instance is null) ApplyTheme();
                break;
            case "mark":
                if (preview != IntPtr.Zero) Native.DexmenuPreviewMark(preview, Str("cardId"));
                break;
        }
    }

    // The layout written under a name (layouts\<name>.json; with DEXMENU_LAYOUT_FILE, the tests, to that file). A new
    // name renames this layout (the kinds set to it follow) unless asCopy (Save as: the old file stays, this window
    // edits the new one). False when not written.
    bool Save(string name, string text, bool asCopy = false)
    {
        name = name.Trim();
        if (name.Length == 0 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
        {
            Post(new { type = "problem", text = "not saved: the name is empty or holds \\ / : * ? \" < > |" });
            return false;
        }
        string path;
        if (Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is { Length: > 0 } env && Path.GetFileNameWithoutExtension(env) == name)
            path = env;
        else
        {
            path = DataFolder.LayoutPath(name);
            var renaming = !asCopy && LayoutName is { } old && !string.Equals(old, name, StringComparison.OrdinalIgnoreCase)
                && currentFile is not null && File.Exists(currentFile);
            if (renaming)
            {
                if (LayoutFiles.Problem(name) is { } problem) { Post(new { type = "problem", text = "not saved: " + problem }); return false; }
                var from = LayoutName!;
                LayoutFiles.Rename(from, name);
                foreach (var other in DexmenuApp.Instance?.Editors ?? []) if (other != this && other.LayoutName == from) other.FileRenamed(path);
            }
        }
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text + Environment.NewLine);
        currentFile = path;
        editedText = null;
        SetTitle();
        Watch();
        Post(new { type = "saved" });
        Reload();
        return true;
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        foreach (var w in watchers) w.Dispose();
        settle.Dispose();
        base.OnFormClosed(e);
    }
}
