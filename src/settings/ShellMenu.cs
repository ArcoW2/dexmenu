using System.Runtime.InteropServices;

namespace Dexmenu.Settings;

/// <summary>
/// Windows' real menu of a right-click, built in the settings app for the preview (docs/plans/executed/02-PLAN-own-menu.md
/// 3.8): the items in a base folder (a file, a folder, several items), the folder's empty part, or its drive, asked
/// from the shell as Explorer asks for them (as the test host, tests/host/DexmenuTest.cpp). Every submenu is opened
/// once (WM_INITMENUPOPUP to the menu's handler), as extensions such as Send to fill theirs only then. So a Git folder
/// shows TortoiseGit's items and an SVN folder TortoiseSVN's. The extensions run in this process; Dexmenu's own
/// handler sets no hook here.
/// </summary>
static class ShellMenu
{
    /// <summary>The menu's items as seen items' text (DexmenuSeenOfMenu: merged into <paramref name="seen"/>, so items
    /// hidden for this selection still show, striped); null and <paramref name="error"/> when the shell gave none.</summary>
    public static string? SeenOf(IntPtr owner, string kind, string folder, IReadOnlyList<string> items, string seen, out string error)
    {
        error = "";
        IContextMenu? menu = null;
        var pidls = new List<IntPtr>();
        var hmenu = IntPtr.Zero;
        try
        {
            menu = kind switch
            {
                "background" => Background(owner, folder, pidls),
                "drive" => Items(owner, [Path.GetPathRoot(Path.GetFullPath(folder))!], pidls),
                _ => Items(owner, items, pidls),
            };
            if (menu is null) { error = "Windows gave no menu for this right-click"; return null; }
            hmenu = CreatePopupMenu();
            var hr = menu.QueryContextMenu(hmenu, 0, 1, 0x7FFF, CMF_NORMAL | CMF_CANRENAME);
            if (hr < 0) { error = $"Windows gave no menu for this right-click (0x{hr:X8})"; return null; }
            OpenSubmenus(menu, hmenu);
            var hints = new Dictionary<string, string>();
            HelpTexts(menu, hmenu, hints);
            var hintsJson = System.Text.Json.JsonSerializer.Serialize(hints);
            var chars = Native.DexmenuSeenOfMenu(hmenu, seen, kind, hintsJson, null, 0);
            var buffer = new System.Text.StringBuilder(chars);
            Native.DexmenuSeenOfMenu(hmenu, seen, kind, hintsJson, buffer, chars);
            return buffer.ToString();
        }
        catch (Exception e) when (e is COMException or ArgumentException or IOException or InvalidCastException)
        {
            error = "Windows gave no menu for this right-click: " + e.Message;
            return null;
        }
        finally
        {
            if (hmenu != IntPtr.Zero) DestroyMenu(hmenu);
            if (menu is not null) Marshal.ReleaseComObject(menu);
            foreach (var p in pidls) Marshal.FreeCoTaskMem(p);
        }
    }

    /// <summary>How long Windows takes to build the menu of a right-click (plan 16 3.1): binding the items and getting
    /// the menu object, then QueryContextMenu (every extension's part), in ms, and the items it has; null and
    /// <paramref name="error"/> when the shell gave none. Nothing opened, nothing read. Profile: the whole of it
    /// sampled (Profiler; plan 16 3.7), the result in <paramref name="profiled"/>.</summary>
    public static (long Bind, long Query, int Items)? Time(IntPtr owner, string kind, string folder, IReadOnlyList<string> items,
        out string error, bool profile, out System.Text.Json.Nodes.JsonObject? profiled)
    {
        error = "";
        profiled = null;
        IContextMenu? menu = null;
        var pidls = new List<IntPtr>();
        var hmenu = IntPtr.Zero;
        var profiler = profile ? Profiler.Start() : null;
        try
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            menu = kind switch
            {
                "background" => Background(owner, folder, pidls),
                "drive" => Items(owner, [Path.GetPathRoot(Path.GetFullPath(folder))!], pidls),
                _ => Items(owner, items, pidls),
            };
            var bind = sw.ElapsedMilliseconds;
            if (menu is null) { error = "Windows gave no menu for this right-click"; return null; }
            hmenu = CreatePopupMenu();
            sw.Restart();
            var hr = menu.QueryContextMenu(hmenu, 0, 1, 0x7FFF, CMF_NORMAL | CMF_CANRENAME);
            var query = sw.ElapsedMilliseconds;
            // stopped before the menu's handlers are let go: their DLLs' names read while loaded
            profiled = profiler?.Stop();
            profiler = null;
            if (hr < 0) { error = $"Windows gave no menu for this right-click (0x{hr:X8})"; return null; }
            return (bind, query, GetMenuItemCount(hmenu));
        }
        catch (Exception e) when (e is COMException or ArgumentException or IOException or InvalidCastException)
        {
            error = "Windows gave no menu for this right-click: " + e.Message;
            return null;
        }
        finally
        {
            profiler?.Stop();
            if (hmenu != IntPtr.Zero) DestroyMenu(hmenu);
            if (menu is not null) Marshal.ReleaseComObject(menu);
            foreach (var p in pidls) Marshal.FreeCoTaskMem(p);
        }
    }

    // A file, a folder, several items of one folder, or a drive: the parent folder's menu for them.
    static IContextMenu? Items(IntPtr owner, IReadOnlyList<string> paths, List<IntPtr> pidls)
    {
        if (paths.Count == 0) return null;
        var children = new IntPtr[paths.Count];
        IShellFolder? parent = null;
        try
        {
            for (var i = 0; i < paths.Count; i++)
            {
                Check(SHParseDisplayName(paths[i], IntPtr.Zero, out var pidl, 0, out _));
                pidls.Add(pidl);
                var iid = typeof(IShellFolder).GUID;
                Check(SHBindToParent(pidl, ref iid, out var folder, out var child));
                if (parent is null) parent = (IShellFolder)folder; else Marshal.ReleaseComObject(folder);
                children[i] = child;
            }
            var cm = typeof(IContextMenu).GUID;
            Check(parent!.GetUIObjectOf(owner, (uint)children.Length, children, ref cm, IntPtr.Zero, out var obj));
            return (IContextMenu)obj;
        }
        finally
        {
            if (parent is not null) Marshal.ReleaseComObject(parent);
        }
    }

    // The folder's empty part: the folder's own background menu.
    static IContextMenu? Background(IntPtr owner, string folder, List<IntPtr> pidls)
    {
        Check(SHParseDisplayName(Path.GetFullPath(folder), IntPtr.Zero, out var pidl, 0, out _));
        pidls.Add(pidl);
        Check(SHGetDesktopFolder(out var desktop));
        IShellFolder? shellFolder = null;
        try
        {
            var sf = typeof(IShellFolder).GUID;
            Check(desktop.BindToObject(pidl, IntPtr.Zero, ref sf, out var obj));
            shellFolder = (IShellFolder)obj;
            var cm = typeof(IContextMenu).GUID;
            if (ViewBackground(shellFolder) is { } fromView) return fromView;
            Check(shellFolder.CreateViewObject(owner, ref cm, out var view));
            return (IContextMenu)view;
        }
        finally
        {
            if (shellFolder is not null) Marshal.ReleaseComObject(shellFolder);
            Marshal.ReleaseComObject(desktop);
        }
    }

    // The folder view's own menu of its empty part (View, Sort by, Group by, Refresh, Paste, ... with the folder's and
    // the extensions' items), as Explorer shows it: a folder view (DefView) made for the folder; null when none.
    static IContextMenu? ViewBackground(IShellFolder folder)
    {
        var create = new SFV_CREATE { cbSize = (uint)Marshal.SizeOf<SFV_CREATE>(),
            pshf = Marshal.GetComInterfaceForObject(folder, typeof(IShellFolder)) };
        try
        {
            if (SHCreateShellFolderView(ref create, out var view) < 0 || view is null) return null;
            try
            {
                var cm = typeof(IContextMenu).GUID;
                return view.GetItemObject(SVGIO_BACKGROUND, ref cm, out var obj) >= 0 ? obj as IContextMenu : null;
            }
            finally { Marshal.ReleaseComObject(view); }
        }
        finally { Marshal.Release(create.pshf); }
    }

    // Every submenu opened once, deepest last, as Windows' menu does when it shows them.
    static void OpenSubmenus(IContextMenu menu, IntPtr hmenu)
    {
        var count = GetMenuItemCount(hmenu);
        for (var i = 0; i < count; i++)
        {
            var sub = GetSubMenu(hmenu, i);
            if (sub == IntPtr.Zero) continue;
            try
            {
                if (menu is IContextMenu3 m3) m3.HandleMenuMsg2(WM_INITMENUPOPUP, sub, (IntPtr)i, out _);
                else if (menu is IContextMenu2 m2) m2.HandleMenuMsg(WM_INITMENUPOPUP, sub, (IntPtr)i);
            }
            catch (COMException) { }   // a handler that does not take it: its submenu as it is
            OpenSubmenus(menu, sub);
        }
    }

    // Every item's own hint: the help text its handler gives (GCS_HELPTEXTW, what Explorer once showed in its status
    // bar), by the item's id; items without one are left out.
    static void HelpTexts(IContextMenu menu, IntPtr hmenu, Dictionary<string, string> hints)
    {
        var buffer = Marshal.AllocHGlobal(1024 * 2);
        try { Walk(hmenu); }
        finally { Marshal.FreeHGlobal(buffer); }

        string Command(int id, uint type)
        {
            Marshal.WriteInt16(buffer, 0);
            try
            {
                return menu.GetCommandString((UIntPtr)(id - 1), type, IntPtr.Zero, buffer, 1024) >= 0
                    ? Marshal.PtrToStringUni(buffer)?.Trim() ?? "" : "";
            }
            catch (COMException) { return ""; }   // a handler that gives none
        }

        void Walk(IntPtr m)
        {
            var count = GetMenuItemCount(m);
            for (var i = 0; i < count; i++)
            {
                var sub = GetSubMenu(m, i);
                if (sub != IntPtr.Zero) { Walk(sub); continue; }
                var id = GetMenuItemID(m, i);
                if (id < 1 || id > 0x7FFF) continue;
                var text = Command(id, GCS_HELPTEXTW);
                // some handlers give their command's name (7-Zip's SevenZipCompress) or the item's own text: no hint
                if (text.Length > 0 && text != Command(id, GCS_VERBW)) hints[id.ToString()] = text;
            }
        }
    }

    static void Check(int hr)
    {
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
    }

    const uint SVGIO_BACKGROUND = 0;

    [StructLayout(LayoutKind.Sequential)]
    struct SFV_CREATE
    {
        public uint cbSize;
        public IntPtr pshf, psvOuter, psfvcb;
    }

    [DllImport("shell32.dll")]
    static extern int SHCreateShellFolderView(ref SFV_CREATE create, out IShellView view);

    [ComImport, Guid("000214E3-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellView
    {
        [PreserveSig] int GetWindow(out IntPtr wnd);
        [PreserveSig] int ContextSensitiveHelp(bool enterMode);
        [PreserveSig] int TranslateAccelerator(IntPtr msg);
        [PreserveSig] int EnableModeless(bool enable);
        [PreserveSig] int UIActivate(uint state);
        [PreserveSig] int Refresh();
        [PreserveSig] int CreateViewWindow(IntPtr previous, IntPtr folderSettings, IntPtr browser, IntPtr rect, out IntPtr wnd);
        [PreserveSig] int DestroyViewWindow();
        [PreserveSig] int GetCurrentInfo(IntPtr folderSettings);
        [PreserveSig] int AddPropertySheetPages(uint reserved, IntPtr add, IntPtr lParam);
        [PreserveSig] int SaveViewState();
        [PreserveSig] int SelectItem(IntPtr pidl, uint flags);
        [PreserveSig] int GetItemObject(uint item, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object obj);
    }

    const uint GCS_VERBW = 4, GCS_HELPTEXTW = 5;

    [DllImport("user32.dll")]
    static extern int GetMenuItemID(IntPtr menu, int position);

    const uint CMF_NORMAL = 0, CMF_CANRENAME = 0x10, WM_INITMENUPOPUP = 0x0117;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr pidl, uint sfgaoIn, out uint sfgaoOut);

    [DllImport("shell32.dll")]
    static extern int SHBindToParent(IntPtr pidl, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object folder, out IntPtr childPidl);

    [DllImport("shell32.dll")]
    static extern int SHGetDesktopFolder(out IShellFolder folder);

    [DllImport("user32.dll")]
    static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll")]
    static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    static extern int GetMenuItemCount(IntPtr menu);

    [DllImport("user32.dll")]
    static extern IntPtr GetSubMenu(IntPtr menu, int position);

    [ComImport, Guid("000214E6-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellFolder
    {
        [PreserveSig] int ParseDisplayName(IntPtr owner, IntPtr bindContext, [MarshalAs(UnmanagedType.LPWStr)] string name,
            out uint eaten, out IntPtr pidl, ref uint attributes);
        [PreserveSig] int EnumObjects(IntPtr owner, uint flags, out IntPtr enumIdList);
        [PreserveSig] int BindToObject(IntPtr pidl, IntPtr bindContext, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object obj);
        [PreserveSig] int BindToStorage(IntPtr pidl, IntPtr bindContext, ref Guid riid, out IntPtr obj);
        [PreserveSig] int CompareIDs(IntPtr lParam, IntPtr pidl1, IntPtr pidl2);
        [PreserveSig] int CreateViewObject(IntPtr owner, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object obj);
        [PreserveSig] int GetAttributesOf(uint count, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] pidls, ref uint attributes);
        [PreserveSig] int GetUIObjectOf(IntPtr owner, uint count, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] pidls, ref Guid riid,
            IntPtr reserved, [MarshalAs(UnmanagedType.Interface)] out object obj);
        [PreserveSig] int GetDisplayNameOf(IntPtr pidl, uint flags, IntPtr name);
        [PreserveSig] int SetNameOf(IntPtr owner, IntPtr pidl, [MarshalAs(UnmanagedType.LPWStr)] string name, uint flags, out IntPtr pidlOut);
    }

    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(IntPtr info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint chars);
    }

    [ComImport, Guid("000214F4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu2
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(IntPtr info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint chars);
        [PreserveSig] int HandleMenuMsg(uint msg, IntPtr wParam, IntPtr lParam);
    }

    [ComImport, Guid("BCFCE0A0-EC17-11D0-8D10-00A0C90F2719"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu3
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(IntPtr info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint chars);
        [PreserveSig] int HandleMenuMsg(uint msg, IntPtr wParam, IntPtr lParam);
        [PreserveSig] int HandleMenuMsg2(uint msg, IntPtr wParam, IntPtr lParam, out IntPtr result);
    }
}
