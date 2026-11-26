using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace Dexmenu.Settings;

/// <summary>Diagnostics (docs/plans/16-PLAN-diagnostics.md): the context menu handlers registered for a kind of
/// right-click, each timed in a measuring process of its own (this app started with --measure-handler, so a handler
/// that crashes or hangs does not take the app with it), Windows' whole menu timed the same way (--measure-menu), a
/// handler switched off and on (Windows' blocked list for the user), and the right-clicks' timings the DLL keeps
/// (Dexmenu.Timings).</summary>
static class Diagnostics
{
    /// <summary>The kinds of right-click measured, each on a sample of its own.</summary>
    public static readonly string[] Kinds = ["file", "folder", "background", "drive"];

    /// <summary>How long one handler may take before it is stopped, when the user set nothing (plan 16 3.1).</summary>
    public const double DefaultHangSeconds = 10;

    public static string LocalFolder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Dexmenu");

    /// <summary>The right-clicks' timings (the DLL writes it; DEXMENU_TIMINGS_FILE: the tests).</summary>
    public static string TimingsFile => Environment.GetEnvironmentVariable("DEXMENU_TIMINGS_FILE") is { Length: > 0 } f
        ? f : Path.Combine(LocalFolder, "timings.json");

    /// <summary>The last measurement of each kind, kept until measured again.</summary>
    public static string MeasuredFile => Path.Combine(LocalFolder, "measured.json");

    const string BlockedKey = @"Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked";

    /// <summary>A handler as the registry has it. Blocked: "user" (HKCU's list), "machine" (HKLM's) or null;
    /// ByDexmenu: switched off from the page (only those can be switched on there).</summary>
    public record Handler(string Clsid, string Name, string Key, string Dll, string? Blocked, bool ByDexmenu, bool Packaged = false);

    // ---- the samples ------------------------------------------------------------------------------------------------

    /// <summary>What a kind is measured on: a file (the user's own when given, else a .txt made for it), a folder made
    /// for it, the samples' folder's empty part, the system drive.</summary>
    public static string Sample(string kind, string? file)
    {
        var dir = Path.Combine(Path.GetTempPath(), "Dexmenu measure");
        Directory.CreateDirectory(dir);
        switch (kind)
        {
            case "file":
                if (file is { Length: > 0 } && File.Exists(file)) return file;
                var txt = Path.Combine(dir, "sample.txt");
                if (!File.Exists(txt)) File.WriteAllText(txt, "Dexmenu's sample file for measuring the right-click's extensions.");
                return txt;
            case "folder":
                var sub = Path.Combine(dir, "sample folder");
                Directory.CreateDirectory(sub);
                return sub;
            case "background":
                return dir;
            default:
                return Path.GetPathRoot(Environment.SystemDirectory) ?? @"C:\";
        }
    }

    // ---- the handlers -----------------------------------------------------------------------------------------------

    /// <summary>The registry keys whose shellex\ContextMenuHandlers Windows uses for the kind (plan 16 3.1).</summary>
    static IEnumerable<string> KeysOf(string kind, string sample)
    {
        switch (kind)
        {
            case "file":
                yield return "*";
                yield return "AllFilesystemObjects";
                var ext = Path.GetExtension(sample);
                if (ext.Length > 0)
                {
                    yield return ext;
                    using var e = Registry.ClassesRoot.OpenSubKey(ext);
                    if (e?.GetValue("") is string { Length: > 0 } progId) yield return progId;
                    yield return @"SystemFileAssociations\" + ext;
                    if (e?.GetValue("PerceivedType") is string { Length: > 0 } perceived) yield return @"SystemFileAssociations\" + perceived;
                }
                break;
            case "folder":
                yield return "Directory";
                yield return "Folder";
                yield return "AllFilesystemObjects";
                break;
            case "background":
                yield return @"Directory\Background";
                break;
            case "drive":
                yield return "Drive";
                yield return "Folder";
                yield return "AllFilesystemObjects";
                break;
        }
    }

    static bool IsGuid(string s) => s.StartsWith('{') && Guid.TryParse(s, out _);

    /// <summary>Every handler of the kind, each once (by its CLSID), in the order Windows' keys list them.</summary>
    public static List<Handler> Handlers(string kind, string sample)
    {
        var list = new List<Handler>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ours = SwitchedOff();
        foreach (var key in KeysOf(kind, sample))
        {
            using var handlers = Registry.ClassesRoot.OpenSubKey(key + @"\shellex\ContextMenuHandlers");
            if (handlers is null) continue;
            foreach (var sub in handlers.GetSubKeyNames())
            {
                using var h = handlers.OpenSubKey(sub);
                var value = h?.GetValue("") as string ?? "";
                var clsid = IsGuid(value) ? value : IsGuid(sub) ? sub : null;
                if (clsid is null) continue;
                clsid = "{" + Guid.Parse(clsid).ToString().ToUpperInvariant() + "}";
                if (!seen.Add(clsid)) continue;
                using var c = Registry.ClassesRoot.OpenSubKey(@"CLSID\" + clsid);
                using var server = c?.OpenSubKey("InprocServer32");
                var name = !IsGuid(sub) ? sub : c?.GetValue("") is string { Length: > 0 } n ? n : clsid;
                var dll = Environment.ExpandEnvironmentVariables(server?.GetValue("") as string ?? "");
                list.Add(new Handler(clsid, name, key, dll, BlockedState(clsid), ours.Contains(clsid)));
            }
        }
        foreach (var p in PackagedHandlers(kind, sample))
            if (seen.Add(p.Clsid)) list.Add(p with { Blocked = BlockedState(p.Clsid), ByDexmenu = ours.Contains(p.Clsid) });
        return list;
    }

    // ---- packaged apps' extensions (plan 16 3.8) ---------------------------------------------------------------------

    const string Repository = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";

    /// <summary>The item types a packaged app's menu extension names (its manifest's FileExplorerContextMenus) that
    /// fit the kind.</summary>
    static string[] ItemTypesOf(string kind, string sample) => kind switch
    {
        "file" => ["*", Path.GetExtension(sample).ToLowerInvariant()],
        "folder" => ["Directory", "Folder"],
        "background" => [@"Directory\Background"],
        _ => ["Drive"],
    };

    /// <summary>The packaged apps' menu extensions for the kind (Windows 11's: IExplorerCommand, run by Windows in a
    /// process of their own): from each of the user's packages' manifest, its FileExplorerContextMenus verbs whose item
    /// type fits. Dll: the package's folder.</summary>
    public static List<Handler> PackagedHandlers(string kind, string sample)
    {
        var list = new List<Handler>();
        var types = ItemTypesOf(kind, sample);
        using var packages = Registry.CurrentUser.OpenSubKey(Repository);
        if (packages is null) return list;
        foreach (var full in packages.GetSubKeyNames())
        {
            using var p = packages.OpenSubKey(full);
            var root = p?.GetValue("PackageRootFolder") as string ?? "";
            var manifest = new[] { Path.Combine(root, "AppxManifest.xml"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps", full, "AppxManifest.xml") }
                .FirstOrDefault(m => m.Length > 0 && SafeExists(m));
            if (manifest is null) continue;
            string text;
            try { text = File.ReadAllText(manifest); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }
            if (!text.Contains("FileExplorerContextMenus", StringComparison.Ordinal)) continue;
            var display = p?.GetValue("DisplayName") as string ?? "";
            if (display.Length == 0 || display.StartsWith("ms-resource:", StringComparison.Ordinal)) display = full.Split('_')[0];
            try
            {
                var doc = System.Xml.Linq.XDocument.Parse(text);
                foreach (var menus in doc.Descendants().Where(d => d.Name.LocalName == "FileExplorerContextMenus"))
                    foreach (var itemType in menus.Elements().Where(e => e.Name.LocalName == "ItemType"))
                    {
                        var type = (string?)itemType.Attribute("Type") ?? "";
                        if (!types.Contains(type, StringComparer.OrdinalIgnoreCase)) continue;
                        foreach (var verb in itemType.Elements().Where(e => e.Name.LocalName == "Verb"))
                        {
                            var raw = (string?)verb.Attribute("Clsid") ?? "";
                            if (!Guid.TryParse(raw, out var g)) continue;
                            var clsid = "{" + g.ToString().ToUpperInvariant() + "}";
                            if (list.Any(h => h.Clsid == clsid)) continue;
                            list.Add(new Handler(clsid, display + " (" + ((string?)verb.Attribute("Id") ?? "app") + ")",
                                "app: " + type, root.Length > 0 ? root : Path.GetDirectoryName(manifest)!, null, false, Packaged: true));
                        }
                    }
            }
            catch (System.Xml.XmlException) { }
        }
        return list;
    }

    static bool SafeExists(string path)
    {
        try { return File.Exists(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
    }

    /// <summary>A packaged COM class's package and its app's name (HKCR\PackagedCom\ClassIndex; the user's packages'
    /// display names): what a COM surrogate (dllhost /Processid:{clsid}) Windows started runs. Not packaged: the
    /// AppID's or the class's own name (Windows' thumbnail cache, ...); null when it has none.</summary>
    public static string? PackagedClassName(string clsid)
    {
        using var index = Registry.ClassesRoot.OpenSubKey(@"PackagedCom\ClassIndex\" + clsid);
        if (index is null)
        {
            using var app = Registry.ClassesRoot.OpenSubKey(@"AppID\" + clsid);
            using var cls = Registry.ClassesRoot.OpenSubKey(@"CLSID\" + clsid);
            return app?.GetValue("") as string is { Length: > 0 } a ? a : cls?.GetValue("") as string is { Length: > 0 } c ? c : null;
        }
        using var packages = Registry.CurrentUser.OpenSubKey(Repository);
        foreach (var full in index.GetSubKeyNames().Reverse())   // the newest version last in the index
        {
            using var p = packages?.OpenSubKey(full);
            if (p is null) continue;
            var display = p.GetValue("DisplayName") as string ?? "";
            return display.Length > 0 && !display.StartsWith("ms-resource:", StringComparison.Ordinal) ? display : full.Split('_')[0];
        }
        return index.GetSubKeyNames().FirstOrDefault()?.Split('_')[0];
    }

    static string? BlockedState(string clsid)
    {
        using (var user = Registry.CurrentUser.OpenSubKey(BlockedKey))
            if (user?.GetValue(clsid) is not null) return "user";
        using (var machine = Registry.LocalMachine.OpenSubKey(BlockedKey))
            if (machine?.GetValue(clsid) is not null) return "machine";
        return null;
    }

    // ---- switching a handler off and on (plan 16 3.6) ---------------------------------------------------------------

    /// <summary>The handlers switched off from the page (settings.json "diagnostics"."switchedOff").</summary>
    public static HashSet<string> SwitchedOff()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (DataFolder.ReadSettings()["diagnostics"]?["switchedOff"] is JsonArray a)
            foreach (var e in a) if (e?.GetValue<string>() is { Length: > 0 } s) set.Add(s);
        return set;
    }

    /// <summary>A handler off (on the user's blocked list, remembered as switched off here) or on again (only one
    /// switched off here). Dexmenu's own handler is never switched off.</summary>
    public static void Switch(string clsid, string name, bool off)
    {
        if (!IsGuid(clsid) || string.Equals(clsid, Registration.Clsid, StringComparison.OrdinalIgnoreCase)) return;
        var ours = SwitchedOff();
        if (off)
        {
            if (BlockedState(clsid) is not null) return;
            using var key = Registry.CurrentUser.CreateSubKey(BlockedKey);
            key.SetValue(clsid, name);
            ours.Add(clsid);
        }
        else
        {
            if (!ours.Contains(clsid)) return;
            using var key = Registry.CurrentUser.OpenSubKey(BlockedKey, writable: true);
            key?.DeleteValue(clsid, throwOnMissingValue: false);
            ours.Remove(clsid);
        }
        var settings = DataFolder.ReadSettings();
        var d = settings["diagnostics"] as JsonObject ?? [];
        settings["diagnostics"] = d;
        d["switchedOff"] = new JsonArray(ours.Order().Select(s => (JsonNode)JsonValue.Create(s)!).ToArray());
        DataFolder.WriteSettings(settings);
    }

    /// <summary>Whether Windows' whole menu is profiled too (settings.json "diagnostics"."profile"; on unless set off).
    /// </summary>
    public static bool Profile
    {
        get => DataFolder.ReadSettings()["diagnostics"]?["profile"] is not JsonValue v || !v.TryGetValue<bool>(out var on) || on;
        set
        {
            var settings = DataFolder.ReadSettings();
            var d = settings["diagnostics"] as JsonObject ?? [];
            settings["diagnostics"] = d;
            d["profile"] = value;
            DataFolder.WriteSettings(settings);
        }
    }

    /// <summary>The hang limit, in seconds (settings.json "diagnostics"."hangSeconds").</summary>
    public static double HangSeconds
    {
        get => DataFolder.ReadSettings()["diagnostics"]?["hangSeconds"] is JsonValue v && v.TryGetValue<double>(out var s) && s > 0
            ? s : DefaultHangSeconds;
        set
        {
            var settings = DataFolder.ReadSettings();
            var d = settings["diagnostics"] as JsonObject ?? [];
            settings["diagnostics"] = d;
            d["hangSeconds"] = Math.Clamp(Math.Round(value, 1), 0.5, 600);
            DataFolder.WriteSettings(settings);
        }
    }

    // ---- the measuring process's side --------------------------------------------------------------------------------

    /// <summary>--measure-handler &lt;out&gt; &lt;kind&gt; &lt;sample&gt; &lt;clsid&gt; &lt;hang seconds&gt;: one handler, fresh and warm, as
    /// JSON to the file. A handler that takes longer than the hang limit: "hanging" written, the process ended.
    /// Packaged: a packaged app's extension (MeasureCommandOnce).</summary>
    public static int MeasureHandlerMain(string outFile, string kind, string sample, string clsid, double hang, bool packaged)
    {
        var result = new JsonObject();
        using var watchdog = new System.Threading.Timer(_ =>
        {
            result["hanging"] = true;
            try { File.WriteAllText(outFile, result.ToJsonString()); } catch (IOException) { }
            Environment.Exit(3);
        }, null, (int)(hang * 1000), Timeout.Infinite);
        try
        {
            result["fresh"] = packaged ? MeasureCommandOnce(kind, sample, clsid) : MeasureOnce(kind, sample, clsid);
            result["warm"] = packaged ? MeasureCommandOnce(kind, sample, clsid) : MeasureOnce(kind, sample, clsid);
        }
        catch (Exception e) when (e is COMException or ArgumentException or InvalidCastException or FileNotFoundException)
        {
            result["error"] = e.Message;
        }
        watchdog.Change(Timeout.Infinite, Timeout.Infinite);
        File.WriteAllText(outFile, result.ToJsonString());
        return 0;
    }

    static JsonObject MeasureOnce(string kind, string sample, string clsid)
    {
        var r = new JsonObject();
        IntPtr pidl = IntPtr.Zero, parent = IntPtr.Zero, unknown = IntPtr.Zero, data = IntPtr.Zero, menu = IntPtr.Zero;
        try
        {
            if (SHParseDisplayName(Path.GetFullPath(sample), IntPtr.Zero, out pidl, 0, out _) < 0)
                throw new FileNotFoundException("the sample is not there", sample);
            IntPtr folderPidl = IntPtr.Zero;
            if (kind == "background")
                folderPidl = pidl;   // a folder's empty part: the folder, no items
            else
            {
                parent = ILClone(pidl);
                ILRemoveLastID(parent);
                var iid = typeof(IDataObjectMarker).GUID;
                if (SHCreateDataObject(parent, 1, [ILFindLastID(pidl)], IntPtr.Zero, ref iid, out data) < 0)
                    throw new ArgumentException("no data object for the sample");
            }
            var sw = Stopwatch.StartNew();
            var c = new Guid(clsid);
            var unk = new Guid("00000000-0000-0000-C000-000000000046");
            var hr = CoCreateInstance(ref c, IntPtr.Zero, 1 /* CLSCTX_INPROC_SERVER */, ref unk, out unknown);
            r["create"] = sw.ElapsedMilliseconds;
            if (hr < 0) { r["error"] = $"not loaded (0x{hr:X8})"; return r; }
            sw.Restart();
            var initIid = typeof(IShellExtInit).GUID;
            if (Marshal.QueryInterface(unknown, in initIid, out var init) >= 0)
            {
                try
                {
                    var i = (IShellExtInit)Marshal.GetObjectForIUnknown(init);
                    var ihr = i.Initialize(folderPidl, data, IntPtr.Zero);
                    if (ihr < 0) r["initError"] = $"0x{ihr:X8}";
                }
                finally { Marshal.Release(init); }
            }
            r["init"] = sw.ElapsedMilliseconds;
            sw.Restart();
            var cmIid = typeof(IContextMenu).GUID;
            if (Marshal.QueryInterface(unknown, in cmIid, out var cmPtr) < 0) { r["error"] = "not a context menu handler"; return r; }
            try
            {
                var cm = (IContextMenu)Marshal.GetObjectForIUnknown(cmPtr);
                menu = CreatePopupMenu();
                var qhr = cm.QueryContextMenu(menu, 0, 1, 0x7FFF, 0);
                r["query"] = sw.ElapsedMilliseconds;
                r["items"] = qhr >= 0 ? GetMenuItemCount(menu) : 0;
                if (qhr < 0) r["queryError"] = $"0x{qhr:X8}";
            }
            finally { Marshal.Release(cmPtr); }
            return r;
        }
        finally
        {
            if (menu != IntPtr.Zero) DestroyMenu(menu);
            if (unknown != IntPtr.Zero) Marshal.Release(unknown);
            if (data != IntPtr.Zero) Marshal.Release(data);
            if (parent != IntPtr.Zero) Marshal.FreeCoTaskMem(parent);
            if (pidl != IntPtr.Zero) Marshal.FreeCoTaskMem(pidl);
        }
    }

    // A packaged app's extension as Windows uses it: made in a process of its own (COM, out of process: a surrogate
    // Windows starts when none runs), then its title and its state for the sample asked (IExplorerCommand). create: the
    // activation, init: GetTitle, query: GetState; items: 1 when it shows, 0 when hidden.
    static JsonObject MeasureCommandOnce(string kind, string sample, string clsid)
    {
        var r = new JsonObject();
        IntPtr item = IntPtr.Zero, array = IntPtr.Zero, unknown = IntPtr.Zero;
        try
        {
            var shellItem = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
            var shellItemArray = new Guid("b63ea76d-1f85-456f-a19c-48159efa858b");
            if (SHCreateItemFromParsingName(Path.GetFullPath(sample), IntPtr.Zero, ref shellItem, out item) < 0)
                throw new FileNotFoundException("the sample is not there", sample);
            if (SHCreateShellItemArrayFromShellItem(item, ref shellItemArray, out array) < 0)
                throw new ArgumentException("no item array for the sample");
            // its process runs already (an earlier right-click, Windows' whole menu just measured): no start in the time
            if (Surrogates().ContainsValue(clsid.ToUpperInvariant())) r["running"] = true;
            var sw = Stopwatch.StartNew();
            var c = new Guid(clsid);
            var unk = new Guid("00000000-0000-0000-C000-000000000046");
            var hr = CoCreateInstance(ref c, IntPtr.Zero, 4 /* CLSCTX_LOCAL_SERVER */, ref unk, out unknown);
            r["create"] = sw.ElapsedMilliseconds;
            if (hr < 0) { r["error"] = $"not started (0x{hr:X8})"; return r; }
            var cmdIid = typeof(IExplorerCommand).GUID;
            if (Marshal.QueryInterface(unknown, in cmdIid, out var cmdPtr) < 0) { r["error"] = "not a menu extension"; return r; }
            try
            {
                var cmd = (IExplorerCommand)Marshal.GetObjectForIUnknown(cmdPtr);
                sw.Restart();
                if (cmd.GetTitle(array, out var title) >= 0 && title != IntPtr.Zero)
                {
                    r["title"] = Marshal.PtrToStringUni(title);
                    Marshal.FreeCoTaskMem(title);
                }
                r["init"] = sw.ElapsedMilliseconds;
                sw.Restart();
                var shr = cmd.GetState(array, false, out var state);
                r["query"] = sw.ElapsedMilliseconds;
                r["items"] = shr >= 0 && (state & 2 /* ECS_HIDDEN */) == 0 ? 1 : 0;
            }
            finally { Marshal.Release(cmdPtr); }
            return r;
        }
        finally
        {
            if (unknown != IntPtr.Zero) Marshal.Release(unknown);
            if (array != IntPtr.Zero) Marshal.Release(array);
            if (item != IntPtr.Zero) Marshal.Release(item);
        }
    }

    // The COM surrogates running now (dllhost.exe /Processid:{clsid}), by process id: the class each runs.
    static Dictionary<int, string> Surrogates()
    {
        var list = new Dictionary<int, string>();
        foreach (var p in Process.GetProcessesByName("dllhost"))
            using (p)
            {
                var line = CommandLine(p.Id);
                var at = line.IndexOf("/Processid:", StringComparison.OrdinalIgnoreCase);
                if (at >= 0) list[p.Id] = line[(at + "/Processid:".Length)..].Trim().Trim('"').ToUpperInvariant();
            }
        return list;
    }

    // A process's command line (NtQueryInformationProcess, ProcessCommandLineInformation); "" when it cannot be read.
    static string CommandLine(int pid)
    {
        var h = OpenProcess(0x1000 /* QUERY_LIMITED_INFORMATION */, false, pid);
        if (h == IntPtr.Zero) return "";
        var buffer = Marshal.AllocHGlobal(4096);
        try
        {
            if (NtQueryInformationProcess(h, 60, buffer, 4096, out _) != 0) return "";
            var length = (ushort)Marshal.ReadInt16(buffer);
            var text = Marshal.ReadIntPtr(buffer, 8);
            return text == IntPtr.Zero ? "" : Marshal.PtrToStringUni(text, length / 2);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
            CloseHandle(h);
        }
    }

    /// <summary>--measure-menu &lt;out&gt; &lt;kind&gt; &lt;sample&gt; &lt;hang seconds&gt; [profile]: Windows' whole menu for the
    /// sample, built as Explorer builds it (ShellMenu), fresh and warm; with profile, each sampled (Profiler: where its
    /// time goes, per DLL; the sampling adds a little to the times). Per pass also the processes Windows started for
    /// it (COM surrogates of packaged apps' extensions: "started").</summary>
    public static int MeasureMenuMain(string outFile, string kind, string sample, double hang, bool profile)
    {
        var result = new JsonObject();
        using var watchdog = new System.Threading.Timer(_ =>
        {
            result["hanging"] = true;
            try { File.WriteAllText(outFile, result.ToJsonString()); } catch (IOException) { }
            Environment.Exit(3);
        }, null, (int)(hang * 1000), Timeout.Infinite);
        using var owner = new Form();
        string folder; List<string> items;
        if (kind is "background" or "drive") { folder = sample; items = []; }
        else { folder = Path.GetDirectoryName(Path.GetFullPath(sample))!; items = [Path.GetFullPath(sample)]; }
        foreach (var pass in new[] { "fresh", "warm" })
        {
            var before = Surrogates();
            var t = ShellMenu.Time(owner.Handle, kind, folder, items, out var error, profile, out var profiled);
            result[pass] = t is { } x ? new JsonObject { ["bind"] = x.Bind, ["query"] = x.Query, ["items"] = x.Items }
                : new JsonObject { ["error"] = error };
            if (profiled is not null) result[pass]!["profile"] = profiled;
            var started = new JsonArray();
            foreach (var (pid, clsid) in Surrogates())
                if (!before.ContainsKey(pid))
                    started.Add(new JsonObject { ["clsid"] = clsid, ["name"] = PackagedClassName(clsid) ?? clsid });
            result[pass]!["started"] = started;
        }
        watchdog.Change(Timeout.Infinite, Timeout.Infinite);
        File.WriteAllText(outFile, result.ToJsonString());
        return 0;
    }

    // ---- the app's side: running the measuring processes ------------------------------------------------------------

    /// <summary>A measuring process, waited for (its own hang limit ends a hanging handler; this one's, a little
    /// longer, ends a process that does not even start it); null when stopped by hand (Stop) or when it gave nothing.
    /// </summary>
    public static async Task<JsonObject?> RunMeasuring(string[] args, double hang, CancellationToken stop)
    {
        var outFile = Path.Combine(Path.GetTempPath(), "Dexmenu measure", "result-" + Guid.NewGuid().ToString("N") + ".json");
        var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add(args[0]);
        start.ArgumentList.Add(outFile);
        foreach (var a in args.Skip(1)) start.ArgumentList.Add(a);
        using var p = Process.Start(start)!;
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(hang + 15));
        using var either = CancellationTokenSource.CreateLinkedTokenSource(stop, limit.Token);
        try { await p.WaitForExitAsync(either.Token); }
        catch (OperationCanceledException)
        {
            try { p.Kill(true); } catch (InvalidOperationException) { }
            if (stop.IsCancellationRequested) return null;
            return new JsonObject { ["hanging"] = true };
        }
        try
        {
            if (!File.Exists(outFile)) return new JsonObject { ["error"] = $"the measuring process ended without a result (exit {p.ExitCode})" };
            return JsonNode.Parse(File.ReadAllText(outFile)) as JsonObject;
        }
        catch (Exception e) when (e is IOException or JsonException) { return new JsonObject { ["error"] = e.Message }; }
        finally { try { File.Delete(outFile); } catch (IOException) { } }
    }

    /// <summary>The kept measurements, { kind: result }; empty when none.</summary>
    public static JsonObject ReadMeasured()
    {
        try { return File.Exists(MeasuredFile) && JsonNode.Parse(File.ReadAllText(MeasuredFile)) is JsonObject o ? o : []; }
        catch (Exception e) when (e is IOException or JsonException) { return []; }
    }

    public static void KeepMeasured(string kind, JsonObject result)
    {
        var all = ReadMeasured();
        all[kind] = result;
        Directory.CreateDirectory(LocalFolder);
        File.WriteAllText(MeasuredFile, all.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>The kept measurements with each handler's blocked state as it is now (it may have changed since).</summary>
    public static JsonObject MeasuredNow()
    {
        var all = ReadMeasured();
        var ours = SwitchedOff();
        foreach (var (_, kind) in all)
            if (kind?["handlers"] is JsonArray handlers)
                foreach (var h in handlers.OfType<JsonObject>())
                    if (h["clsid"]?.GetValue<string>() is { } clsid)
                    {
                        h["blocked"] = BlockedState(clsid);
                        h["byDexmenu"] = ours.Contains(clsid);
                    }
        return all;
    }

    /// <summary>The right-clicks' timings as the DLL wrote them ({ "entries": [...] }), or none.</summary>
    public static JsonNode TimingEntries()
    {
        try
        {
            if (File.Exists(TimingsFile) && JsonNode.Parse(File.ReadAllText(TimingsFile))?["entries"] is JsonArray a)
                return a.DeepClone();
        }
        catch (Exception e) when (e is IOException or JsonException) { }
        return new JsonArray();
    }

    // ---- interop -----------------------------------------------------------------------------------------------------

    [ComImport, Guid("0000010e-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDataObjectMarker { }

    [ComImport, Guid("000214E8-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellExtInit
    {
        [PreserveSig] int Initialize(IntPtr pidlFolder, IntPtr dataObject, IntPtr hkeyProgId);
    }

    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr pidl, uint sfgaoIn, out uint sfgaoOut);

    [DllImport("shell32.dll")]
    static extern int SHCreateDataObject(IntPtr pidlFolder, uint count, IntPtr[] pidls, IntPtr inner, ref Guid riid, out IntPtr obj);

    [DllImport("shell32.dll")]
    static extern IntPtr ILFindLastID(IntPtr pidl);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, ref Guid riid, out IntPtr item);

    [DllImport("shell32.dll")]
    static extern int SHCreateShellItemArrayFromShellItem(IntPtr item, ref Guid riid, out IntPtr array);

    [DllImport("kernel32.dll")]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationProcess(IntPtr process, int infoClass, IntPtr info, int length, out int returned);

    [ComImport, Guid("a08ce4d0-fa25-44ab-b57c-c7b1c323e0b9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IExplorerCommand
    {
        [PreserveSig] int GetTitle(IntPtr items, out IntPtr name);
        [PreserveSig] int GetIcon(IntPtr items, out IntPtr icon);
        [PreserveSig] int GetToolTip(IntPtr items, out IntPtr tip);
        [PreserveSig] int GetCanonicalName(out Guid guid);
        [PreserveSig] int GetState(IntPtr items, [MarshalAs(UnmanagedType.Bool)] bool okToBeSlow, out uint state);
    }

    [DllImport("shell32.dll")]
    static extern IntPtr ILClone(IntPtr pidl);

    [DllImport("shell32.dll")]
    static extern bool ILRemoveLastID(IntPtr pidl);

    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint context, ref Guid iid, out IntPtr obj);

    [DllImport("user32.dll")]
    static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll")]
    static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    static extern int GetMenuItemCount(IntPtr menu);
}
