using System.Reflection;
using Microsoft.Web.WebView2.Core;

namespace Dexmenu.Settings;

/// <summary>
/// The page's files (web\ in the project): built into the exe as resources, so a publish is one exe with only
/// DexmenuShell.dll and WebView2Loader.dll next to it (as Foldex and LexPen). Served at https://dexmenu.app/. A build
/// that is not a publish (bin, build.cmd) serves the project's own src\settings\web instead, so an edit applies on a
/// reload, without a build.
/// </summary>
static class WebFiles
{
    public const string Host = "dexmenu.app";
    const string Prefix = "web\\";   // the resource names: web\editor.js (Dexmenu.Settings.csproj)

    static readonly Assembly Assembly = typeof(WebFiles).Assembly;
    static readonly Dictionary<string, string> Names = Assembly.GetManifestResourceNames()
        .Where(n => n.StartsWith(Prefix, StringComparison.Ordinal))
        .ToDictionary(n => n[Prefix.Length..].Replace('\\', '/'), n => n, StringComparer.OrdinalIgnoreCase);

#if PROJECT_WEB
    static readonly string? ProjectWeb = FindProjectWeb(AppContext.BaseDirectory);
#else
    static readonly string? ProjectWeb = null;   // readonly, not const: a const null makes every test of it a warning
#endif

    static readonly Dictionary<string, string> Types = new(StringComparer.OrdinalIgnoreCase)
    {
        [".html"] = "text/html; charset=utf-8", [".js"] = "text/javascript; charset=utf-8", [".css"] = "text/css; charset=utf-8",
        [".json"] = "application/json; charset=utf-8", [".svg"] = "image/svg+xml", [".png"] = "image/png",
    };

    /// <summary>src\settings\web, up from the exe's folder (bin is beside src), or null.</summary>
    static string? FindProjectWeb(string from)
    {
        for (var dir = new DirectoryInfo(from); dir is not null; dir = dir.Parent)
        {
            var web = Path.Combine(dir.FullName, "src", "settings", "web");
            if (File.Exists(Path.Combine(web, "index.html"))) return web;
        }
        return null;
    }

    /// <summary>Makes a WebView2 serve the page at https://dexmenu.app/.</summary>
    public static void Serve(CoreWebView2 core)
    {
        if (ProjectWeb is not null)
        {
            core.SetVirtualHostNameToFolderMapping(Host, ProjectWeb, CoreWebView2HostResourceAccessKind.Allow);
            return;
        }
        core.AddWebResourceRequestedFilter($"https://{Host}/*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) =>
        {
            var uri = new Uri(e.Request.Uri);
            if (!uri.Host.Equals(Host, StringComparison.OrdinalIgnoreCase)) return;
            var path = Uri.UnescapeDataString(uri.AbsolutePath).TrimStart('/');
            var stream = Names.TryGetValue(path, out var name) ? Assembly.GetManifestResourceStream(name) : null;
            e.Response = stream is null
                ? core.Environment.CreateWebResourceResponse(null, 404, "Not Found", "")
                : core.Environment.CreateWebResourceResponse(stream, 200, "OK",
                    $"Content-Type: {Types.GetValueOrDefault(Path.GetExtension(path), "application/octet-stream")}");
        };
    }
}
