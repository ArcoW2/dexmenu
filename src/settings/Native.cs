using System.Runtime.InteropServices;
using System.Text;

namespace Dexmenu.Settings;

/// <summary>DexmenuShell.dll's exports for the settings app (src/dll/Dexmenu.Preview.pas). The DLL draws the preview
/// with the same code as a right-click, so what the preview shows is the menu. No hook is set in this process.</summary>
static class Native
{
    const string Dll = "DexmenuShell.dll";

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    public static extern IntPtr DexmenuPreviewCreate(IntPtr parent);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern bool DexmenuPreviewSet(IntPtr wnd, string layout, string seen, string kind, StringBuilder error, int errorChars);

    [DllImport(Dll, CharSet = CharSet.Unicode)]
    static extern int DexmenuBaseLayout(StringBuilder? buffer, int chars);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr wnd, int x, int y, int width, int height, bool repaint);

    /// <summary>What the preview shows; null when it shows it, else the reason it cannot.</summary>
    public static string? SetPreview(IntPtr wnd, string layout, string seen, string kind)
    {
        var error = new StringBuilder(1024);
        return DexmenuPreviewSet(wnd, layout, seen, kind, error, error.Capacity) ? null : error.ToString();
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
