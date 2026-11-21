// DexmenuTest.exe: the test host of docs/plans/01-PLAN-dexmenu.md 3.11. Builds Windows' right-click menu for the given
// files and folders as Explorer does (the parent folder's IContextMenu, QueryContextMenu), reads it, then shows it with
// TrackPopupMenuEx and reads the menu actually shown (the HMENU of the first WM_INITMENUPOPUP) before closing it.
//
//   DexmenuTest.exe [--group "from LexPen"] [--prefix LexPen.] <path> [<path> ...]   (all in one folder)
//
// The items under test are identified by their verb (GetCommandString GCS_VERBW starting with --prefix), not by text,
// so the check does not lean on the layout's patterns. With DEXMENU=1 (Dexmenu on) the shown menu must hold those
// items, exactly as Windows' menu has them (text, id, state, type, bitmap, submenu), in a submenu named --group, and
// every other item as in Windows' menu, in its order. Without it, the shown menu must be Windows' menu. Either way,
// after the call Windows' menu must be as it was. Exit code 0: pass.

#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shobjidl_core.h>
#include <cstdio>
#include <string>
#include <vector>

namespace {

const UINT First = 1, Last = 0x7FFF;

struct Node
{
    std::wstring text, verb;
    UINT id = 0, state = 0, type = 0;
    HBITMAP bitmap = nullptr;
    ULONG_PTR data = 0;
    HMENU sub = nullptr;
    std::vector<Node> children;
};

IContextMenu* menu = nullptr;
IContextMenu3* menu3 = nullptr;
HMENU shownTop = nullptr;
std::vector<Node> shown;
bool sawShown = false;

std::wstring VerbOf(UINT id)
{
    if (!menu || id < First || id > Last) return {};
    wchar_t verb[256] = {};
    if (FAILED(menu->GetCommandString(id - First, GCS_VERBW, nullptr, reinterpret_cast<char*>(verb), 256))) return {};
    return verb;
}

std::vector<Node> Tree(HMENU m, int depth)
{
    std::vector<Node> nodes;
    const int count = GetMenuItemCount(m);
    for (int i = 0; i < count; i++)
    {
        MENUITEMINFOW info = { sizeof(info), MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_BITMAP | MIIM_DATA | MIIM_STRING };
        wchar_t text[512] = {};
        info.dwTypeData = text;
        info.cch = 512;
        if (!GetMenuItemInfoW(m, i, TRUE, &info)) continue;
        Node n;
        n.type = info.fType;
        n.state = info.fState & (MFS_DISABLED | MFS_CHECKED | MFS_DEFAULT);
        n.id = info.wID;
        n.bitmap = info.hbmpItem;
        n.data = info.dwItemData;
        n.sub = info.hSubMenu;
        if (!(info.fType & (MFT_SEPARATOR | MFT_OWNERDRAW | MFT_BITMAP))) n.text = text;
        if (!n.sub && !(info.fType & MFT_SEPARATOR)) n.verb = VerbOf(n.id);
        if (n.sub && depth > 0) n.children = Tree(n.sub, depth - 1);
        nodes.push_back(n);
    }
    return nodes;
}

bool IsLine(const Node& n) { return (n.type & MFT_SEPARATOR) != 0; }

std::wstring Describe(const Node& n)
{
    if (IsLine(n)) return L"----";
    std::wstring s = L"\"" + n.text + L"\" id=" + std::to_wstring(n.id);
    if (n.state & MFS_DISABLED) s += L" disabled";
    if (n.state & MFS_CHECKED) s += L" checked";
    if (n.state & MFS_DEFAULT) s += L" default";
    if (n.type & MFT_OWNERDRAW) s += L" ownerdraw";
    if (n.sub) s += L" submenu";
    if (!n.verb.empty()) s += L" verb=" + n.verb;
    return s;
}

void Print(const std::vector<Node>& nodes, int indent)
{
    for (const auto& n : nodes)
    {
        wprintf(L"%*s%s\n", indent, L"", Describe(n).c_str());
        Print(n.children, indent + 4);
    }
}

// The same item: everything Windows' menu has for it (the submenu by handle: moved, not copied).
bool Same(const Node& a, const Node& b)
{
    return a.text == b.text && a.id == b.id && a.state == b.state && a.type == b.type && a.bitmap == b.bitmap
        && a.data == b.data && a.sub == b.sub;
}

bool SameList(const std::vector<Node>& a, const std::vector<Node>& b)
{
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); i++) if (!Same(a[i], b[i])) return false;
    return true;
}

int failures = 0;

void Check(bool ok, const wchar_t* what)
{
    wprintf(L"%s %s\n", ok ? L"PASS" : L"FAIL", what);
    if (!ok) failures++;
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (menu3 && (msg == WM_INITMENUPOPUP || msg == WM_DRAWITEM || msg == WM_MEASUREITEM || msg == WM_MENUCHAR))
    {
        LRESULT result = 0;
        if (SUCCEEDED(menu3->HandleMenuMsg2(msg, wp, lp, &result)) && msg != WM_INITMENUPOPUP) return result;
    }
    if (msg == WM_INITMENUPOPUP && !sawShown)
    {
        sawShown = true;
        shownTop = reinterpret_cast<HMENU>(wp);
        shown = Tree(shownTop, 1);
        SetTimer(hwnd, 1, 50, nullptr);
        return 0;
    }
    if (msg == WM_TIMER) { KillTimer(hwnd, static_cast<UINT_PTR>(wp)); EndMenu(); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

}   // namespace

int wmain(int argc, wchar_t** argv)
{
    std::wstring group = L"from LexPen", prefix = L"LexPen.", invoke;
    std::vector<std::wstring> paths;
    for (int i = 1; i < argc; i++)
    {
        const std::wstring a = argv[i];
        if (a == L"--group" && i + 1 < argc) group = argv[++i];
        else if (a == L"--prefix" && i + 1 < argc) prefix = argv[++i];
        else if (a == L"--invoke" && i + 1 < argc) invoke = argv[++i];
        else paths.push_back(a);
    }
    if (paths.empty()) { fwprintf(stderr, L"usage: DexmenuTest [--group name] [--prefix verb-prefix] path...\n"); return 2; }
    wchar_t env[8] = {};
    const bool on = GetEnvironmentVariableW(L"DEXMENU", env, 8) && wcscmp(env, L"1") == 0;

    if (FAILED(OleInitialize(nullptr))) return 2;
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"DexmenuTest";
    RegisterClassW(&wc);
    const HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, wc.lpszClassName, L"DexmenuTest", WS_POPUP | WS_VISIBLE, 0, 0, 1, 1,
        nullptr, nullptr, wc.hInstance, nullptr);
    SetForegroundWindow(hwnd);

    // The parent folder's menu for the items, as Explorer asks for it.
    IShellFolder* parent = nullptr;
    std::vector<PIDLIST_ABSOLUTE> absolute;
    std::vector<PCUITEMID_CHILD> children;
    for (const auto& p : paths)
    {
        PIDLIST_ABSOLUTE pidl = nullptr;
        if (FAILED(SHParseDisplayName(p.c_str(), nullptr, &pidl, 0, nullptr))) { fwprintf(stderr, L"not found: %s\n", p.c_str()); return 2; }
        absolute.push_back(pidl);
        PCUITEMID_CHILD child = nullptr;
        if (!parent && FAILED(SHBindToParent(pidl, IID_PPV_ARGS(&parent), &child))) return 2;
        children.push_back(ILFindLastID(pidl));
    }
    if (FAILED(parent->GetUIObjectOf(hwnd, static_cast<UINT>(children.size()), children.data(), IID_IContextMenu, nullptr,
        reinterpret_cast<void**>(&menu)))) return 2;
    menu->QueryInterface(IID_PPV_ARGS(&menu3));
    const HMENU hmenu = CreatePopupMenu();
    if (FAILED(menu->QueryContextMenu(hmenu, 0, First, Last, CMF_NORMAL | CMF_CANRENAME))) return 2;

    // --invoke verb: the item run as a program runs a choice (by its id), no UI; its result printed, nothing shown.
    if (!invoke.empty())
    {
        UINT id = 0;
        for (const auto& n : Tree(hmenu, 0)) if (n.verb == invoke) id = n.id;
        if (!id) { wprintf(L"no item with verb %s\n", invoke.c_str()); return 1; }
        CMINVOKECOMMANDINFOEX info = { sizeof(info) };
        info.fMask = CMIC_MASK_UNICODE | CMIC_MASK_FLAG_NO_UI;
        info.hwnd = hwnd;
        info.lpVerb = MAKEINTRESOURCEA(id - First);
        info.lpVerbW = MAKEINTRESOURCEW(id - First);
        info.nShow = SW_SHOWNORMAL;
        const HRESULT hr = menu->InvokeCommand(reinterpret_cast<CMINVOKECOMMANDINFO*>(&info));
        wprintf(L"invoked %s (id %u): hr=0x%08X\n", invoke.c_str(), id, static_cast<unsigned>(hr));
        return SUCCEEDED(hr) ? 0 : 1;
    }

    const auto windows = Tree(hmenu, 1);
    wprintf(L"== Windows' menu\n");
    Print(windows, 2);

    // Shown away from the mouse, so a real click while the test runs does not land on it.
    POINT cursor = {};
    GetCursorPos(&cursor);
    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &mi);
    const auto& work = mi.rcWork;
    const POINT at = { cursor.x < (work.left + work.right) / 2 ? work.right - 1 : work.left,
                       cursor.y < (work.top + work.bottom) / 2 ? work.bottom - 1 : work.top };
    const BOOL chosen = TrackPopupMenuEx(hmenu, TPM_RETURNCMD | TPM_RIGHTBUTTON, at.x, at.y, hwnd, nullptr);
    wprintf(L"== Shown menu (Dexmenu %s)\n", on ? L"on" : L"off");
    Print(shown, 2);

    Check(sawShown, L"the menu was shown");
    wprintf(L"returned: %d\n", chosen);
    Check(chosen == 0, L"closed without a choice: 0 returned");
    const auto after = Tree(hmenu, 1);
    Check(SameList(after, windows), L"after the call Windows' menu is as it was");

    std::vector<Node> tested, others;   // Windows' top level: the items under test, the rest without lines
    size_t othersBefore = SIZE_MAX;
    for (const auto& n : windows)
    {
        if (IsLine(n)) continue;
        if (!n.verb.empty() && n.verb.rfind(prefix, 0) == 0)
        {
            if (othersBefore == SIZE_MAX) othersBefore = others.size();
            tested.push_back(n);
        }
        else others.push_back(n);
    }
    wprintf(L"== Items with verb %s* in Windows' menu: ", prefix.c_str());
    for (const auto& n : tested) wprintf(L"[%s] ", Describe(n).c_str());
    wprintf(L"\n");

    if (!on || tested.empty())
    {
        Check(shownTop == hmenu || SameList(shown, windows), on ? L"nothing to arrange: Windows' menu shown as it is" : L"Dexmenu off: Windows' menu shown as it is");
        Check(SameList(shown, windows), L"the shown items are Windows' items");
    }
    else
    {
        Check(shownTop != hmenu, L"an arranged menu was shown, not Windows' own");
        std::vector<Node> shownOthers;
        const Node* sub = nullptr;
        size_t subAt = SIZE_MAX;
        for (const auto& n : shown)
        {
            if (IsLine(n)) continue;
            if (n.text == group && n.sub && !sub) { sub = &n; subAt = shownOthers.size(); continue; }
            shownOthers.push_back(n);
        }
        Check(sub != nullptr, (L"a submenu \"" + group + L"\" is there").c_str());
        if (sub)
        {
            std::vector<Node> inSub;
            for (const auto& n : sub->children) if (!IsLine(n)) inSub.push_back(n);
            Check(SameList(inSub, tested), L"the submenu holds exactly those items, each as Windows' menu has it (text, id, state, type, bitmap, data, submenu), in Windows' order");
            Check(subAt == othersBefore, L"the submenu sits where the first of them was");
        }
        Check(SameList(shownOthers, others), L"every other item as in Windows' menu, in its order");
        bool lines = !shown.empty() && !IsLine(shown.front()) && !IsLine(shown.back());
        for (size_t i = 1; i < shown.size(); i++) if (IsLine(shown[i]) && IsLine(shown[i - 1])) lines = false;
        Check(lines, L"no line at the start or end, none twice");
    }

    menu->Release();
    if (menu3) menu3->Release();
    parent->Release();
    for (auto p : absolute) CoTaskMemFree(p);
    DestroyMenu(hmenu);
    OleUninitialize();
    wprintf(L"%s\n", failures ? L"FAILED" : L"OK");
    return failures ? 1 : 0;
}
