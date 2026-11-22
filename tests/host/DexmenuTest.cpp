// DexmenuTest.exe: the test host (docs/plans/01-PLAN-dexmenu.md 3.11, 02-PLAN-own-menu.md 3.12, plan 00 step 3).
// Builds Windows' right-click menu for the given files and folders as Explorer does (the parent folder's IContextMenu,
// QueryContextMenu), reads it, then shows it with TrackPopupMenuEx as Explorer does.
//
//   DexmenuTest.exe [--prefix LexPen.] [--late] [--choose <verb>] [--open <text>] [--expect-windows] <path> [...]
//   DexmenuTest.exe --invoke <verb> <path> [...]
//
// DEXMENU=0 (off): the shown menu (the HMENU of the first WM_INITMENUPOPUP) must be Windows' menu.
// DEXMENU=1 (on): Dexmenu's own menu must show (a DexmenuMenu window, no Windows menu window); it is read from the
// file DEXMENU_DUMP names, which the DLL writes after each redraw. With the base layout every top-level item of
// Windows' menu must be a card, in Windows' order, with its id, text, state and submenu mark. The host acts on the
// real window from a timer (which runs inside the menu's loop): Esc, a click on a card (--choose: the card of that
// verb; the call must return its id), or a click on a submenu card (--open: the card of that text; its level must
// show with items, filled when opened as Send to is). --expect-windows: Windows' own menu must show instead (a broken
// layout).
//
// --late, either way: while the menu is shown, Explorer's later calls are made on Windows' menu by id (the first item
// whose verb starts with --prefix disabled, the last deleted); the shown menu and Windows' menu after the call must have
// those changes.
//
// The items under test are found by their verb (GetCommandString GCS_VERBW), not their text. Exit code 0: pass. Run it
// with DEXMENU set to 1 or 0: without it the DLL follows the registry.

#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shobjidl_core.h>
#include <cstdio>
#include <fcntl.h>
#include <io.h>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

const UINT First = 1, Last = 0x7FFF;

struct Node
{
    std::wstring text, verb;
    UINT id = 0, state = 0, type = 0;
    HMENU sub = nullptr;
    std::vector<Node> children;
};

// A card as the DLL's dump has it.
struct Card
{
    std::wstring kind, text;
    UINT id = 0;
    bool enabled = false, sub = false;
    int x = 0, y = 0;   // its middle, screen pixels
};

struct Level
{
    int index = 0, x = 0, y = 0;
    HWND wnd = nullptr;
    std::vector<Card> cards;
};

IContextMenu* menu = nullptr;
IContextMenu3* menu3 = nullptr;
HMENU windowsMenu = nullptr;
bool on = false;
UINT lateDisable = 0, lateDelete = 0;
std::wstring dumpPath, chooseVerb, openText;
int holdMs = 0;   // --hold: the menu left open this long before the test acts (for a screenshot); off: then printed
UINT chooseId = 0;

// What happened while the menu was shown.
bool sawWindowsMenu = false, sawOwnMenu = false, lateApplied = false, finished = false, timedOut = false;
std::vector<Node> shownWindows;       // off: the Windows menu shown
std::vector<Level> ownFirst, ownLate, ownOpened;
int ticks = 0, state = 0;
std::wstring lastDump;

std::wstring VerbOf(UINT id)
{
    if (!menu || id < First || id > Last) return {};
    wchar_t verb[256] = {};
    if (FAILED(menu->GetCommandString(id - First, GCS_VERBW, nullptr, reinterpret_cast<char*>(verb), 256))) return {};
    return verb;
}

// The text without & and the accelerator, as the DLL names items.
std::wstring NameOf(const std::wstring& text)
{
    std::wstring name;
    for (size_t i = 0; i < text.size() && text[i] != L'\t'; i++)
    {
        if (text[i] == L'&' && i + 1 < text.size() && text[i + 1] != L'&') continue;
        if (text[i] == L'&') i++;
        if (i < text.size()) name += text[i];
    }
    while (!name.empty() && name.back() == L' ') name.pop_back();
    while (!name.empty() && name.front() == L' ') name.erase(0, 1);
    return name;
}

std::vector<Node> Tree(HMENU m, int depth)
{
    std::vector<Node> nodes;
    const int count = GetMenuItemCount(m);
    for (int i = 0; i < count; i++)
    {
        MENUITEMINFOW info = { sizeof(info), MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_STRING };
        wchar_t text[512] = {};
        info.dwTypeData = text;
        info.cch = 512;
        if (!GetMenuItemInfoW(m, i, TRUE, &info)) continue;
        Node n;
        n.type = info.fType;
        n.state = info.fState & (MFS_DISABLED | MFS_CHECKED | MFS_DEFAULT);
        n.id = info.wID;
        n.sub = info.hSubMenu;
        if (!(info.fType & (MFT_SEPARATOR | MFT_BITMAP))) n.text = text;
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

bool Same(const Node& a, const Node& b)
{
    return a.text == b.text && a.id == b.id && a.state == b.state && a.type == b.type && a.sub == b.sub;
}

bool SameList(const std::vector<Node>& a, const std::vector<Node>& b)
{
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); i++) if (!Same(a[i], b[i])) return false;
    return true;
}

int failures = 0;

void Check(bool ok, const std::wstring& what)
{
    wprintf(L"%s %s\n", ok ? L"PASS" : L"FAIL", what.c_str());
    if (!ok) failures++;
}

// ---- the DLL's dump -----------------------------------------------------------------------------------------------

std::wstring ReadUtf8(const std::wstring& path)
{
    std::ifstream f(path, std::ios::binary);
    if (!f) return {};
    std::stringstream ss;
    ss << f.rdbuf();
    std::string bytes = ss.str();
    if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF) bytes.erase(0, 3);
    const int n = MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    std::wstring text(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), text.data(), n);
    return text;
}

std::wstring Field(const std::wstring& line, const std::wstring& name)
{
    const auto at = line.find(L" " + name + L"=");
    if (at == std::wstring::npos) return {};
    const auto start = at + name.size() + 2;
    if (name == L"text") return line.substr(start);
    const auto end = line.find(L' ', start);
    return line.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
}

std::vector<Level> ParseDump(const std::wstring& text)
{
    std::vector<Level> levels;
    std::wistringstream in(text);
    std::wstring line;
    while (std::getline(in, line))
    {
        if (!line.empty() && line.back() == L'\r') line.pop_back();
        if (line.rfind(L"level ", 0) == 0)
        {
            Level l;
            l.index = _wtoi(line.c_str() + 6);
            l.wnd = reinterpret_cast<HWND>(static_cast<INT_PTR>(_wtoi64(Field(line, L"wnd").c_str())));
            l.x = _wtoi(Field(line, L"x").c_str());
            l.y = _wtoi(Field(line, L"y").c_str());
            levels.push_back(l);
        }
        else if (line.rfind(L"card ", 0) == 0 && !levels.empty())
        {
            Card c;
            c.kind = line.substr(5, line.find(L' ', 5) - 5);
            c.id = static_cast<UINT>(_wtoi(Field(line, L"id").c_str()));
            c.enabled = Field(line, L"enabled") == L"1";
            c.sub = Field(line, L"sub") == L"1";
            c.x = _wtoi(Field(line, L"x").c_str());
            c.y = _wtoi(Field(line, L"y").c_str());
            c.text = Field(line, L"text");
            levels.back().cards.push_back(c);
        }
    }
    return levels;
}

void PrintLevels(const std::vector<Level>& levels)
{
    for (const auto& l : levels)
    {
        wprintf(L"  level %d\n", l.index);
        for (const auto& c : l.cards)
            wprintf(L"    %s \"%s\" id=%u%s%s\n", c.kind.c_str(), c.text.c_str(), c.id, c.enabled ? L"" : L" disabled",
                c.sub ? L" submenu" : L"");
    }
}

BOOL CALLBACK FindWindowsMenu(HWND wnd, LPARAM found)
{
    wchar_t cls[64] = {};
    GetClassNameW(wnd, cls, 64);
    if (IsWindowVisible(wnd) && wcscmp(cls, L"#32768") == 0) *reinterpret_cast<bool*>(found) = true;
    return TRUE;
}

bool WindowsMenuVisible()
{
    bool found = false;
    EnumThreadWindows(GetCurrentThreadId(), FindWindowsMenu, reinterpret_cast<LPARAM>(&found));
    return found;
}

BOOL CALLBACK FindOwnMenu(HWND wnd, LPARAM found)
{
    wchar_t cls[64] = {};
    GetClassNameW(wnd, cls, 64);
    if (IsWindowVisible(wnd) && wcscmp(cls, L"DexmenuMenu") == 0) *reinterpret_cast<bool*>(found) = true;
    return TRUE;
}

bool OwnMenuVisible()
{
    bool found = false;
    EnumThreadWindows(GetCurrentThreadId(), FindOwnMenu, reinterpret_cast<LPARAM>(&found));
    return found;
}

// Every visible DexmenuMenu window of this thread gets Esc (the way out when the dump cannot be read).
BOOL CALLBACK EscapeOwnMenu(HWND wnd, LPARAM)
{
    wchar_t cls[64] = {};
    GetClassNameW(wnd, cls, 64);
    if (IsWindowVisible(wnd) && wcscmp(cls, L"DexmenuMenu") == 0) PostMessageW(wnd, WM_KEYDOWN, VK_ESCAPE, 0);
    return TRUE;
}

void ApplyLate()
{
    if (lateDisable)
    {
        MENUITEMINFOW info = { sizeof(info), MIIM_STATE };
        info.fState = MFS_DISABLED;
        SetMenuItemInfoW(windowsMenu, lateDisable, FALSE, &info);
    }
    if (lateDelete) DeleteMenu(windowsMenu, lateDelete, MF_BYCOMMAND);
    lateApplied = true;
}

void Click(const Level& l, const Card& c)
{
    PostMessageW(l.wnd, WM_LBUTTONUP, 0, MAKELPARAM(c.x - l.x, c.y - l.y));
}

void Escape(const std::vector<Level>& levels)
{
    if (!levels.empty()) PostMessageW(levels.front().wnd, WM_KEYDOWN, VK_ESCAPE, 0);
}

// The steps while Dexmenu's menu is shown, one per timer tick.
void Tick(HWND hwnd)
{
    if (finished) return;
    if (++ticks > 150 + holdMs / 60)   // the menu never did what was expected
    {
        timedOut = true;
        finished = true;
        const auto levels = ParseDump(ReadUtf8(dumpPath));
        fwprintf(stderr, L"timed out: state %d, own menu %s, %zu level(s) in the dump\n", state,
            OwnMenuVisible() ? L"visible" : L"not visible", levels.size());
        EndMenu();
        EnumThreadWindows(GetCurrentThreadId(), EscapeOwnMenu, 0);
        EnumThreadWindows(GetCurrentThreadId(), EscapeOwnMenu, 0);
        return;
    }
    if (WindowsMenuVisible())
    {
        sawWindowsMenu = true;
        finished = true;
        EndMenu();
        return;
    }
    if (!OwnMenuVisible()) return;
    sawOwnMenu = true;
    const std::wstring text = ReadUtf8(dumpPath);
    const auto levels = ParseDump(text);
    if (levels.empty()) return;
    switch (state)
    {
    case 0:   // the first picture
        if (ticks * 60 < holdMs) return;
        ownFirst = levels;
        lastDump = text;
        if (lateDisable || lateDelete)
        {
            ApplyLate();
            state = 1;
            return;
        }
        state = 2;
        [[fallthrough]];
    case 2:   // act
        if (state == 1) return;
        if (!chooseVerb.empty() && openText.empty())
        {
            for (const auto& c : levels.front().cards)
                if (c.id == chooseId && chooseId != 0)
                {
                    Click(levels.front(), c);
                    finished = true;
                    return;
                }
            finished = true;   // not there: the check fails
            Escape(levels);
            return;
        }
        if (!openText.empty())
        {
            for (const auto& c : levels.front().cards)
                if (c.text == openText && c.sub)
                {
                    Click(levels.front(), c);
                    state = 3;
                    return;
                }
            finished = true;
            Escape(levels);
            return;
        }
        finished = true;
        Escape(levels);
        return;
    case 1:   // waiting for the redraw after the late changes
        if (text == lastDump) return;
        ownLate = levels;
        state = 2;
        Tick(hwnd);
        return;
    case 3:   // waiting for the opened submenu; then a click in it (--choose) or Esc
        if (levels.size() < 2 || levels[1].cards.empty()) return;
        ownOpened = levels;
        finished = true;
        if (chooseId != 0)
            for (const auto& c : levels[1].cards)
                if (c.id == chooseId) { Click(levels[1], c); return; }
        PostMessageW(levels.front().wnd, WM_KEYDOWN, VK_ESCAPE, 0);
        PostMessageW(levels.front().wnd, WM_KEYDOWN, VK_ESCAPE, 0);
        return;
    }
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (menu3 && (msg == WM_INITMENUPOPUP || msg == WM_DRAWITEM || msg == WM_MEASUREITEM || msg == WM_MENUCHAR))
    {
        LRESULT result = 0;
        if (SUCCEEDED(menu3->HandleMenuMsg2(msg, wp, lp, &result)) && msg != WM_INITMENUPOPUP) return result;
    }
    if (msg == WM_INITMENUPOPUP && !on && shownWindows.empty() && reinterpret_cast<HMENU>(wp) == windowsMenu)
    {
        // Off: Windows' menu is being shown; the late changes as Explorer makes them, then its items as shown.
        if (lateDisable || lateDelete) ApplyLate();
        shownWindows = Tree(windowsMenu, 1);
        sawWindowsMenu = true;
        SetTimer(hwnd, 1, holdMs > 0 ? holdMs : 50, nullptr);   // --hold: the changes the shell makes while shown come in
        return 0;
    }
    if (msg == WM_TIMER && wp == 1)
    {
        KillTimer(hwnd, 1);
        if (holdMs > 0)
        {
            // Off and held: Windows' own menu as it is after the shell's late changes (items added, deleted)
            wprintf(L"== Windows' menu after %d ms shown\n", holdMs);
            Print(Tree(windowsMenu, 1), 2);
        }
        EndMenu();
        return 0;
    }
    if (msg == WM_TIMER && wp == 2) { Tick(hwnd); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

}   // namespace

int wmain(int argc, wchar_t** argv)
{
    std::wstring prefix = L"LexPen.", invoke;
    bool late = false, expectWindows = false, anyLayout = false;
    std::vector<std::wstring> paths;
    for (int i = 1; i < argc; i++)
    {
        const std::wstring a = argv[i];
        if (a == L"--prefix" && i + 1 < argc) prefix = argv[++i];
        else if (a == L"--invoke" && i + 1 < argc) invoke = argv[++i];
        else if (a == L"--choose" && i + 1 < argc) chooseVerb = argv[++i];
        else if (a == L"--open" && i + 1 < argc) openText = argv[++i];
        else if (a == L"--late") late = true;
        else if (a == L"--hold" && i + 1 < argc) holdMs = _wtoi(argv[++i]);
        else if (a == L"--expect-windows") expectWindows = true;
        else if (a == L"--any-layout") anyLayout = true;   // a layout of rules: no check of the base layout's cards
        else paths.push_back(a);
    }
    _setmode(_fileno(stdout), _O_U8TEXT);   // UTF-8, so titles beyond ASCII survive a redirect
    if (paths.empty()) { fwprintf(stderr, L"usage: see the comment at the top of DexmenuTest.cpp\n"); return 2; }
    wchar_t env[8] = {};
    on = GetEnvironmentVariableW(L"DEXMENU", env, 8) && wcscmp(env, L"1") == 0;
    wchar_t temp[MAX_PATH] = {};
    GetTempPathW(MAX_PATH, temp);
    dumpPath = std::wstring(temp) + L"dexmenu-dump-" + std::to_wstring(GetCurrentProcessId()) + L".txt";
    SetEnvironmentVariableW(L"DEXMENU_DUMP", dumpPath.c_str());
    DeleteFileW(dumpPath.c_str());

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
    windowsMenu = hmenu;
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

    auto windows = Tree(hmenu, 1);
    wprintf(L"== Windows' menu\n");
    Print(windows, 2);
    for (const auto& n : windows) if (n.verb == chooseVerb && !chooseVerb.empty()) chooseId = n.id;

    // --late: the first item under test disabled, the last (when there are two or more) deleted, while shown; what
    // Windows' menu is expected to be from then on.
    if (late)
    {
        std::vector<UINT> ids;
        for (const auto& n : windows) if (!IsLine(n) && n.verb.rfind(prefix, 0) == 0) ids.push_back(n.id);
        if (!ids.empty()) lateDisable = ids.front();
        if (ids.size() > 1) lateDelete = ids.back();
        for (auto& n : windows) if (lateDisable && n.id == lateDisable && !IsLine(n)) n.state |= MFS_DISABLED;
        std::erase_if(windows, [](const Node& n) { return lateDelete && n.id == lateDelete && !IsLine(n); });
        wprintf(L"== Late: id %u disabled, id %u deleted, while shown\n", lateDisable, lateDelete);
    }

    // Shown away from the mouse, so a real click while the test runs does not land on it.
    POINT cursor = {};
    GetCursorPos(&cursor);
    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST), &mi);
    const auto& work = mi.rcWork;
    const POINT at = { cursor.x < (work.left + work.right) / 2 ? work.right - 1 : work.left,
                       cursor.y < (work.top + work.bottom) / 2 ? work.bottom - 1 : work.top };
    if (on) SetTimer(hwnd, 2, 60, nullptr);
    const BOOL chosen = TrackPopupMenuEx(hmenu, TPM_RETURNCMD | TPM_RIGHTBUTTON, at.x, at.y, hwnd, nullptr);
    KillTimer(hwnd, 2);
    wprintf(L"returned: %d\n", chosen);

    std::vector<Node> tested;
    for (const auto& n : windows) if (!IsLine(n) && n.verb.rfind(prefix, 0) == 0) tested.push_back(n);
    wprintf(L"== Items with verb %s* in Windows' menu: ", prefix.c_str());
    for (const auto& n : tested) wprintf(L"[%s] ", Describe(n).c_str());
    wprintf(L"\n");

    Check(SameList(Tree(hmenu, 1), windows), L"after the call Windows' menu is as expected (as it was, or with the late changes)");

    if (!on || expectWindows)
    {
        Check(sawWindowsMenu, L"Windows' own menu was shown");
        Check(!sawOwnMenu, L"Dexmenu's menu was not shown");
        if (!on)
        {
            wprintf(L"== Shown menu (Dexmenu off)\n");
            Print(shownWindows, 2);
            Check(SameList(shownWindows, windows), L"the shown items are Windows' items");
        }
        Check(chosen == 0, L"closed without a choice: 0 returned");
    }
    else
    {
        Check(sawOwnMenu && !sawWindowsMenu, L"Dexmenu's own menu was shown, not Windows' menu");
        Check(!timedOut, L"the menu did what the test asked in time");
        const auto& shown = ownLate.empty() ? ownFirst : ownLate;
        wprintf(L"== Dexmenu's menu%s\n", ownLate.empty() ? L"" : L" after the late changes");
        PrintLevels(shown);
        // The base layout: every top-level item with a text a card, in Windows' order, as Windows' menu has it.
        std::vector<Card> expected;
        for (const auto& n : windows)
        {
            if (IsLine(n)) continue;
            const auto name = NameOf(n.text);
            if (name.empty() && !n.sub) continue;
            Card c;
            c.kind = L"item";
            c.id = n.id;
            c.text = name;
            c.enabled = !(n.state & MFS_DISABLED);
            c.sub = n.sub != nullptr;
            expected.push_back(c);
        }
        std::vector<Card> got;
        if (!shown.empty()) for (const auto& c : shown.front().cards) if (c.kind != L"separator") got.push_back(c);
        bool same = got.size() == expected.size();
        for (size_t i = 0; same && i < got.size(); i++)
            same = got[i].id == expected[i].id && got[i].text == expected[i].text &&
                got[i].enabled == expected[i].enabled && got[i].sub == expected[i].sub;
        if (!anyLayout) Check(same, L"every item of Windows' menu a card, in its order, with its id, text, state and submenu mark");
        if (late)
        {
            Check(lateApplied && !ownLate.empty(), L"the menu was drawn again after the late changes");
            bool deletedGone = true, disabledShown = !lateDisable;
            for (const auto& c : got)
            {
                if (lateDelete && c.id == lateDelete) deletedGone = false;
                if (lateDisable && c.id == lateDisable) disabledShown = !c.enabled;
            }
            Check(deletedGone, L"the item deleted while shown is gone");
            Check(disabledShown, L"the item disabled while shown is shown disabled");
        }
        if (!openText.empty())
        {
            Check(ownOpened.size() >= 2 && !ownOpened[1].cards.empty(), L"the submenu \"" + openText + L"\" opened with items");
            if (ownOpened.size() >= 2) PrintLevels(ownOpened);
        }
        if (!chooseVerb.empty())
            Check(chooseId != 0 && static_cast<UINT>(chosen) == chooseId,
                L"a click on the card of " + chooseVerb + L" returned its id " + std::to_wstring(chooseId));
        else
            Check(chosen == 0, L"closed without a choice: 0 returned");
    }

    menu->Release();
    if (menu3) menu3->Release();
    parent->Release();
    for (auto p : absolute) CoTaskMemFree(p);
    DestroyMenu(hmenu);
    OleUninitialize();
    DeleteFileW(dumpPath.c_str());
    wprintf(L"%s\n", failures ? L"FAILED" : L"OK");
    return failures ? 1 : 0;
}
