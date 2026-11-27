using System.Runtime.InteropServices;
using System.Text;

namespace Dexmenu.Settings;

/// <summary>DexmenuShell.dll's exports for the settings app (src/dll/Dexmenu.Preview.pas). The DLL draws the preview
/// with the same code as a right-click, so what the preview shows is the menu. No hook is set in this process.</summary>
static class Native
{
    const string Dll = "DexmenuShell.dll";

    /// <summary>The preview's report: an item hovered (1) or clicked (2), the card that placed it and the rule that found
    /// it (-1: none).</summary>
    [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    public delegate void PreviewCallback(int previewEvent, string cardId, int rule);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    public static extern IntPtr DexmenuPreviewCreate(IntPtr parent);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern bool DexmenuPreviewSet(IntPtr wnd, string layout, string seen, string kind, StringBuilder error, int errorChars);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    public static extern void DexmenuPreviewSetCallback(IntPtr wnd, PreviewCallback callback);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    public static extern void DexmenuPreviewMark(IntPtr wnd, string cardId);

    /// <summary>The preview's look: 0 as Windows' apps are, 1 light, 2 dark.</summary>
    [DllImport(Dll)]
    public static extern void DexmenuSetTheme(int mode);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern int DexmenuBaseLayout(StringBuilder? buffer, int chars);

    /// <summary>A real menu (ShellMenu) as seen items' text, merged into a seen file's text; the characters it needs.</summary>
    [DllImport(Dll, CharSet = CharSet.Unicode)]
    public static extern int DexmenuSeenOfMenu(IntPtr menu, string seen, string kind, string hints, StringBuilder? buffer, int chars);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr wnd, int x, int y, int width, int height, bool repaint);

    /// <summary>What the preview shows; null when it shows it, else the reason it cannot.</summary>
    public static string? SetPreview(IntPtr wnd, string layout, string seen, string kind)
    {
        var error = new StringBuilder(1024);
        return DexmenuPreviewSet(wnd, layout, seen, kind, error, error.Capacity) ? null : error.ToString();
    }

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern int DexmenuThemePalette(StringBuilder? buffer, int chars);

    /// <summary>The palette of the theme the preview draws with, as JSON { "name": "#rrggbbaa" } (plan 03 3.6).</summary>
    public static string ThemePalette()
    {
        var chars = DexmenuThemePalette(null, 0);
        var buffer = new StringBuilder(chars);
        DexmenuThemePalette(buffer, chars);
        return buffer.ToString();
    }

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern int DexmenuThemePaletteOf(string light, string dark, StringBuilder? buffer, int chars);

    /// <summary>The palette of a theme pair ("" a built-in one) for the mode the preview draws in, as ThemePalette
    /// (docs/plans/15-PLAN-card-themes.md 3.4: the colour pickers of a card in that pair).</summary>
    public static string ThemePaletteOf(string light, string dark)
    {
        var chars = DexmenuThemePaletteOf(light, dark, null, 0);
        var buffer = new StringBuilder(chars);
        DexmenuThemePaletteOf(light, dark, buffer, chars);
        return buffer.ToString();
    }

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern int DexmenuPreviewCounts(IntPtr wnd, StringBuilder? buffer, int chars);

    /// <summary>The stored use counts per card of what the preview shows, as JSON { "card id": count }.</summary>
    public static string PreviewCounts(IntPtr wnd)
    {
        var chars = DexmenuPreviewCounts(wnd, null, 0);
        var buffer = new StringBuilder(chars);
        DexmenuPreviewCounts(wnd, buffer, chars);
        return buffer.ToString();
    }

    /// <summary>The built-in base layout (only the remaining card): the layout when the user has none.</summary>
    public static string BaseLayout()
    {
        var chars = DexmenuBaseLayout(null, 0);
        var buffer = new StringBuilder(chars);
        DexmenuBaseLayout(buffer, chars);
        return buffer.ToString();
    }
}
