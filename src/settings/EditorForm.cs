using System.Text.Json;
using Microsoft.Web.WebView2.WinForms;

namespace Dexmenu.Settings;

/// <summary>A layout's editor window (plan 00 steps 4 and 5; docs/plans/executed/05-PLAN-settings-windows.md 3.6): one layout,
/// named in the title; several can be open. The page (web\index.html in WebView2) fills the window with four panes:
/// the rules, the cards, the selected card and the preview, with the same splitters between them. The preview pane's
/// area is a window DexmenuShell.dll draws the menu into, from the layout being edited and the items that kind of
/// right-click showed; the page tells where that area is (previewRect) and the window is placed over it. Every edit
/// goes to the preview at once; saving writes the layout file. The file, settings.json and the seen items are
/// watched: a change reloads them (an unsaved edit is kept). An item hovered or clicked in the preview selects the
/// card and rule that placed it; a card selected marks its items there.
/// The preview's bar (in the page): the kind of right-click, and a base folder with the item(s) right-clicked in it;
/// with a folder the preview shows Windows' real menu of that right-click there (ShellMenu: a Git folder differs from
/// an SVN one), the seen items' others striped; without one, the seen items of that kind. Every kind can be chosen;
/// one this layout is not set for says so. Closing with unsaved changes asks to save them. With --selftest &lt;file&gt;
/// it runs the editor's self-test (web\selftest.html) instead, writes its lines to the file and exits with the number
/// of failures.</summary>
sealed class EditorForm : Form, IThemed
{
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly Panel previewHost = new() { Visible = false };   // over the page's preview area; the DLL draws in it
    readonly System.Windows.Forms.Timer settle = new() { Interval = 150 };
    readonly List<FileSystemWatcher> watchers = [];
    readonly Native.PreviewCallback callback;   // kept: the DLL holds it
    readonly string? selftest;
    readonly bool startOnLast;   // no --kind given: the preview starts on the last right-click
    IntPtr preview;
    string kind;
    string? folder;              // the preview's base folder; null: the seen items
    List<string> entries = [];   // what can be right-clicked in it for the kind
    List<string> chosen = [];    // the item(s) right-clicked there
    string liveError = "";
    string? liveSeen;            // Windows' real menu there, as seen items' text (merged with the seen file)
    string? currentFile;         // the layout file being edited; null: the built-in base layout
    string? editedText;          // an edit not yet saved
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
        if (!Kinds.Any(x => x.Kind == kind)) kind = "file";
        startOnLast = kindArgument is null;
        SetTitle();
        callback = Placed;
        Controls.Add(previewHost);
        Controls.Add(web);
        previewHost.BringToFront();
        settle.Tick += (_, _) => { settle.Stop(); Reload(); };
        previewHost.Resize += (_, _) => FitPreview();
        HandleCreated += (_, _) => Themes.Apply(this, web);
        FormClosing += AskToSave;
        Load += async (_, _) => await Start();
    }

    public string? LayoutName => currentFile is null ? null : Path.GetFileNameWithoutExtension(currentFile);

    void SetTitle() => Text = "Dexmenu - " + (LayoutName ?? "(built in)");

    static readonly (string Kind, string Name)[] Kinds =
        [("file", "a file"), ("folder", "a folder"), ("several", "several items"), ("background", "a folder's empty part"),
         ("desktop", "the desktop's empty part"), ("drive", "a drive")];

    // A kind of right-click this layout is set for, for the preview to start on.
    string? FirstKindOfThis() =>
        LayoutName is { } n ? DataFolder.Kinds().Where(k => string.Equals(k.Layout, n, StringComparison.OrdinalIgnoreCase))
            .Select(k => k.Kind.StartsWith("dialog-") ? k.Kind["dialog-".Length..] : k.Kind)
            .FirstOrDefault(k => Kinds.Any(x => x.Kind == k)) : null;

    public void ApplyTheme()
    {
        Themes.Apply(this, web);
        previewHost.BackColor = BackColor;
        Post(new { type = "theme", theme = Themes.Name });
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
        // The window's minimum: the page's four panes at their minimum (rules 320, cards 520, the card's panel 400, the
        // preview 300 CSS pixels, with the splitters), in the display's scale; the starting size within the screen.
        var scale = DeviceDpi / 96.0;
        MinimumSize = SizeFromClientSize(new Size((int)Math.Ceiling(1560 * scale), (int)(520 * scale)));
        var screen = Screen.FromControl(this).WorkingArea;
        Size = new Size(Math.Min(screen.Width, Math.Max(MinimumSize.Width, (int)(1800 * scale))),
            Math.Min(screen.Height, Math.Max(MinimumSize.Height, (int)(820 * scale))));
        CenterToScreen();
        if (selftest is null)
        {
            preview = Native.DexmenuPreviewCreate(previewHost.Handle);
            if (preview != IntPtr.Zero) Native.DexmenuPreviewSetCallback(preview, callback);
            FillItems();
            Watch();
            if (startOnLast) ApplyLastRightClick();
            Reload();
        }
        await Pages.Start(web, selftest is null ? "index.html" : "selftest.html", Received,
            () => { pageReady = true; ApplyTheme(); });
    }

    // The preview set to the last right-click Dexmenu showed its menu for (DataFolder.LastRightClick): its kind, its
    // folder and the items right-clicked there, so the live menu is that right-click's.
    void ApplyLastRightClick()
    {
        if (DataFolder.LastRightClick() is not { } last || !Kinds.Any(x => x.Kind == last.Kind) || !Directory.Exists(last.Folder)) return;
        kind = last.Kind;
        folder = last.Folder;
        FillItems();
        var names = last.Items.Select(Path.GetFileName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var picked = entries.Where(names.Contains).ToList();
        if (picked.Count > 0) chosen = kind == "several" ? picked : [picked[0]];
        Live();
        Reload();
    }

    // The items the kind right-clicks in the folder: files (a file), subfolders (a folder), both (several); the first
    // ones chosen. The folder's empty part, the desktop's and the drive need none.
    void FillItems()
    {
        entries = [];
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
        chosen = kind switch
        {
            "file" or "folder" => entries.Take(1).ToList(),
            "several" => entries.Take(2).ToList(),
            _ => [],
        };
    }

    // Windows' real menu of the right-click in the folder, or none (the seen items). The desktop's empty part is the
    // desktop's, whatever the folder.
    void Live()
    {
        liveSeen = null;
        liveError = "";
        if (kind == "desktop")
        {
            liveSeen = ShellMenu.SeenOf(Handle, "background", Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), [],
                DataFolder.ReadSeen(kind), out liveError);
            return;
        }
        if (folder is null) return;
        if (kind is "file" or "folder" or "several" && chosen.Count == 0) { liveError = "nothing to right-click here"; return; }
        Cursor = Cursors.WaitCursor;
        try { liveSeen = ShellMenu.SeenOf(Handle, kind, folder, chosen.Select(c => Path.Combine(folder, c)).ToList(), DataFolder.ReadSeen(kind), out liveError); }
        finally { Cursor = Cursors.Default; }
    }

    string SeenText() => liveSeen ?? DataFolder.ReadSeen(kind);

    void FitPreview()
    {
        if (preview != IntPtr.Zero)
            Native.MoveWindow(preview, 0, 0, previewHost.ClientSize.Width, previewHost.ClientSize.Height, true);
    }

    // The layout file's folder, the data folder (settings.json) and the seen items: a change reloads (after it settles).
    void Watch()
    {
        foreach (var w in watchers) w.Dispose();
        watchers.Clear();
        var folders = new List<string> { DataFolder.SeenFolder, DataFolder.Root };
        if (currentFile is not null && Path.GetDirectoryName(currentFile) is string dir) folders.Add(dir);
        foreach (var f in folders.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(f)) continue;
            var w = new FileSystemWatcher(f) { NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName, EnableRaisingEvents = true };
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

    // The preview's bar as the page shows it.
    void PostPreviewBar()
    {
        // a kind this layout is not set for (as the DLL decides; tests: one layout for every kind)
        var used = DataFolder.Resolve(kind);
        var notMeant = LayoutName is { } me && Environment.GetEnvironmentVariable("DEXMENU_LAYOUT_FILE") is not { Length: > 0 }
            && !string.Equals(used, me, StringComparison.OrdinalIgnoreCase);
        Post(new
        {
            type = "previewBar",
            kinds = Kinds.Select(k => new { kind = k.Kind, name = k.Name }),
            kind, folder, entries, chosen,
            pick = kind switch { "file" or "folder" => "one", "several" => "many", _ => "none" },
            liveError, notMeant, used = used switch { null => "the built-in layout", "none" => "Windows' own menu", _ => "\"" + used + "\"" }, last = DataFolder.LastRightClick() is not null,
        });
    }

    // The preview from the edit in progress or the file; the page gets the file's state when nothing is being edited.
    void Reload()
    {
        if (selftest is not null) return;
        var text = FileText(out var source);
        var error = preview == IntPtr.Zero
            ? "DexmenuShell.dll did not make the preview"
            : Native.SetPreview(preview, editedText ?? text, SeenText(), kind);
        if (!pageReady) return;
        PostPreviewBar();
        PostCounts();
        PostPalette();
        PostFonts();
        if (editedText is not null)
        {
            Post(new { type = "preview", error });
            return;
        }
        Post(new { type = "state", kind, layout = text, source, name = LayoutName, theme = Themes.Name, error });
    }

    void Post(object message) => web.CoreWebView2?.PostWebMessageAsJson(JsonSerializer.Serialize(message));

    // The stored use counts per card of what the preview shows (plan 02 3.9), for the cards view's gutter.
    void PostCounts()
    {
        if (preview == IntPtr.Zero) return;
        Post(new { type = "counts", counts = System.Text.Json.Nodes.JsonNode.Parse(Native.PreviewCounts(preview)) });
    }

    // the theme's palette for the card panel's colour pickers (plan 03 3.6), with every reload: the theme may have changed
    void PostPalette()
    {
        try { Post(new { type = "palette", palette = System.Text.Json.Nodes.JsonNode.Parse(Native.ThemePalette()) }); }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException or System.Text.Json.JsonException) { }
        // what a rule without states of its own takes (the main window's General): the rule panel shows it
        Post(new { type = "ruleStates", states = DataFolder.Menu()["states"]?.GetValue<string>() ?? "both" });
        // the themes there are, for the menu's own theme (its panel)
        Post(new { type = "themes", names = DataFolder.ThemeNames() });
    }

    // The installed font families (as LexPen lists them), for a note's font (plan 03 3.6): once per window.
    static string[]? fontFamilies;
    bool fontsSent;
    void PostFonts()
    {
        if (fontsSent) return;
        fontsSent = true;
        if (fontFamilies is null)
        {
            using var installed = new System.Drawing.Text.InstalledFontCollection();
            fontFamilies = installed.Families.Select(f => f.Name).Where(n => !n.StartsWith('@'))   // not the vertical East Asian variants
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase).ToArray();
        }
        Post(new { type = "fonts", fonts = fontFamilies });
    }

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
                PostCounts();
                PostPalette();   // the layout may choose its own theme: the colour pickers follow it
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
                Themes.Toggle();
                DexmenuApp.Instance.ThemeChanged();
                break;
            case "mark":
                if (preview != IntPtr.Zero) Native.DexmenuPreviewMark(preview, Str("cardId"));
                break;
            case "previewRect":
                // the page's preview area (CSS pixels, within the page) as the preview window's place
                var scale = DeviceDpi / 96.0;
                var r = new Rectangle((int)Math.Round(m.GetProperty("x").GetDouble() * scale), (int)Math.Round(m.GetProperty("y").GetDouble() * scale),
                    (int)Math.Round(m.GetProperty("w").GetDouble() * scale), (int)Math.Round(m.GetProperty("h").GetDouble() * scale));
                previewHost.Bounds = r;
                previewHost.Visible = r.Width > 0 && r.Height > 0;
                break;
            case "previewKind":
                if (Kinds.Any(x => x.Kind == Str("kind"))) { kind = Str("kind"); FillItems(); Live(); Reload(); }
                break;
            case "pickNoteFile":
                // a file for a note to show (plan 14), with the folders its path may start with, to write them as variables
                using (var dialog = new OpenFileDialog { Title = "A file for the note to show", Filter = "Text|*.txt;*.md;*.log|All files|*.*" })
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) break;
                    Post(new
                    {
                        type = "pickedNoteFile",
                        path = dialog.FileName,
                        appdata = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                        userprofile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                    });
                }
                break;
            case "pickImage":
                // a background image's file (plan 03 3.4), for the colour field that asked
                using (var dialog = new OpenFileDialog
                {
                    Title = "A background image",
                    Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff;*.ico|All files|*.*"
                })
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) break;
                    Post(new { type = "pickedImage", path = dialog.FileName });
                }
                break;
            case "pickFolder":
                using (var dialog = new FolderBrowserDialog { SelectedPath = folder ?? "", Description = "The folder in which the preview's right-click is" })
                {
                    if (dialog.ShowDialog(this) != DialogResult.OK) break;
                    folder = dialog.SelectedPath;
                }
                FillItems();
                Live();
                Reload();
                break;
            case "noFolder":
                folder = null;
                FillItems();
                Live();
                Reload();
                break;
            case "pickItems":
                chosen = m.GetProperty("names").EnumerateArray().Select(n => n.GetString() ?? "").Where(entries.Contains).ToList();
                Live();
                Reload();
                break;
            case "last":
                ApplyLastRightClick();
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
                foreach (var other in DexmenuApp.Instance.Editors) if (other != this && other.LayoutName == from) other.FileRenamed(path);
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
