// DexmenuShell.dll: the spike of docs/plans/01-PLAN-dexmenu.md (3.1 - 3.4). A context menu handler that adds nothing:
// its QueryContextMenu notes the HMENU being built, and a hook on TrackPopupMenu(Ex) shows that menu arranged by the
// layout instead. The arranged menu holds Windows' own items (same ids, states, bitmaps, item data, submenu handles),
// so the program runs the chosen id on the menu it built, as before. After the call every item is put back.
//
// On when the environment variable DEXMENU is 1, off when it is 0 (the tests); without it, on only when
// HKCU\Software\Dexmenu Enabled is 1. Off: no
// hook is set and every call passes through. Any error: Windows' menu shown untouched, the error in
// %LOCALAPPDATA%\Dexmenu\dexmenu.log.
//
// The layout (DEXMENU_LAYOUT, else %APPDATA%\Dexmenu\layout.txt), UTF-8 text:
//   # a comment
//   [from LexPen]          a submenu of the user's own, placed where its first item was
//   Edit in LexPen         an item of Windows' menu by its text (no &, no accelerator), * and ? as wildcards
// The spike matches top-level items only; a top-level submenu matched by its text moves whole.

#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shobjidl_core.h>
#include <wrl/module.h>
#include <wrl/implements.h>
#include <algorithm>
#include <string>
#include <vector>
#include "../vendor/minhook/include/MinHook.h"

using namespace Microsoft::WRL;

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {

// ---- settings and log -------------------------------------------------------------------------------------------

bool Enabled()
{
    wchar_t env[8] = {};
    if (GetEnvironmentVariableW(L"DEXMENU", env, 8)) return wcscmp(env, L"1") == 0;   // the tests: 1 on, 0 off
    DWORD value = 0, size = sizeof(value);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Dexmenu", L"Enabled", RRF_RT_REG_DWORD, nullptr, &value, &size);
    return value == 1;
}

std::wstring KnownFolder(REFKNOWNFOLDERID id)
{
    PWSTR path = nullptr;
    std::wstring result;
    if (SUCCEEDED(SHGetKnownFolderPath(id, 0, nullptr, &path))) result = path;
    CoTaskMemFree(path);
    return result;
}

void Log(const std::wstring& text)
{
    const auto folder = KnownFolder(FOLDERID_LocalAppData) + L"\\Dexmenu";
    CreateDirectoryW(folder.c_str(), nullptr);
    const HANDLE h = CreateFileW((folder + L"\\dexmenu.log").c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_ALWAYS, 0, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    wchar_t exe[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    SYSTEMTIME t;
    GetLocalTime(&t);
    wchar_t stamp[64];
    swprintf_s(stamp, L"%04u-%02u-%02u %02u:%02u:%02u ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond);
    const auto line = std::wstring(stamp) + exe + L": " + text + L"\r\n";
    const int n = WideCharToMultiByte(CP_UTF8, 0, line.c_str(), static_cast<int>(line.size()), nullptr, 0, nullptr, nullptr);
    std::string bytes(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, line.c_str(), static_cast<int>(line.size()), bytes.data(), n, nullptr, nullptr);
    DWORD written = 0;
    WriteFile(h, bytes.data(), n, &written, nullptr);
    CloseHandle(h);
}

// HKCU\Software\Dexmenu Trace 1: every menu noted and every show call in the log (to see what a program does).
bool Tracing()
{
    DWORD value = 0, size = sizeof(value);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Dexmenu", L"Trace", RRF_RT_REG_DWORD, nullptr, &value, &size);
    return value == 1;
}

std::wstring Hex(const void* p)
{
    wchar_t s[32];
    swprintf_s(s, L"%p", p);
    return s;
}

// ---- the layout ---------------------------------------------------------------------------------------------------

struct Group
{
    std::wstring name;
    std::vector<std::wstring> patterns;
};

std::wstring LayoutPath()
{
    wchar_t env[MAX_PATH] = {};
    if (GetEnvironmentVariableW(L"DEXMENU_LAYOUT", env, MAX_PATH)) return env;
    return KnownFolder(FOLDERID_RoamingAppData) + L"\\Dexmenu\\layout.txt";
}

std::wstring Trim(const std::wstring& s)
{
    const wchar_t* space = L" \t\r\n";
    const auto first = s.find_first_not_of(space);
    if (first == std::wstring::npos) return {};
    return s.substr(first, s.find_last_not_of(space) - first + 1);
}

SRWLOCK layoutLock = SRWLOCK_INIT;
std::vector<Group> layout;
FILETIME layoutStamp = {};

// The layout, read again when the file's time stamp changed. No file: no groups (Windows' menu as it is).
std::vector<Group> Layout()
{
    const auto path = LayoutPath();
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    const bool exists = GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data) != 0;
    AcquireSRWLockExclusive(&layoutLock);
    if (!exists) layout.clear();
    else if (CompareFileTime(&data.ftLastWriteTime, &layoutStamp) != 0)
    {
        layout.clear();
        const HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
        if (h != INVALID_HANDLE_VALUE)
        {
            std::string bytes(data.nFileSizeLow, '\0');
            DWORD read = 0;
            ReadFile(h, bytes.data(), data.nFileSizeLow, &read, nullptr);
            CloseHandle(h);
            bytes.resize(read);
            const int start = bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF ? 3 : 0;
            const int n = MultiByteToWideChar(CP_UTF8, 0, bytes.data() + start, static_cast<int>(bytes.size()) - start, nullptr, 0);
            std::wstring text(n, L'\0');
            MultiByteToWideChar(CP_UTF8, 0, bytes.data() + start, static_cast<int>(bytes.size()) - start, text.data(), n);
            size_t at = 0;
            while (at <= text.size())
            {
                auto end = text.find(L'\n', at);
                if (end == std::wstring::npos) end = text.size();
                const auto line = Trim(text.substr(at, end - at));
                at = end + 1;
                if (line.empty() || line[0] == L'#') continue;
                if (line.front() == L'[' && line.back() == L']') layout.push_back({ Trim(line.substr(1, line.size() - 2)), {} });
                else if (!layout.empty()) layout.back().patterns.push_back(line);
            }
            layoutStamp = data.ftLastWriteTime;
        }
    }
    auto copy = layout;
    ReleaseSRWLockExclusive(&layoutLock);
    return copy;
}

bool Matches(const wchar_t* pattern, const wchar_t* text)
{
    if (*pattern == 0) return *text == 0;
    if (*pattern == L'*') return Matches(pattern + 1, text) || (*text && Matches(pattern, text + 1));
    if (*text == 0) return false;
    if (*pattern != L'?' && towlower(*pattern) != towlower(*text)) return false;
    return Matches(pattern + 1, text + 1);
}

// An item's name: its text without the & of its key letter and without the accelerator after a tab.
std::wstring NameOf(const std::wstring& text)
{
    std::wstring name;
    for (size_t i = 0; i < text.size() && text[i] != L'\t'; i++)
    {
        if (text[i] == L'&' && i + 1 < text.size() && text[i + 1] != L'&') continue;
        if (text[i] == L'&') i++;
        name += text[i];
    }
    return Trim(name);
}

// ---- menus read and built -----------------------------------------------------------------------------------------

struct Item
{
    MENUITEMINFOW info = { sizeof(MENUITEMINFOW) };
    std::wstring text;
    bool hasText = false;
};

const UINT Mask = MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_DATA | MIIM_BITMAP | MIIM_CHECKMARKS;

// One item, by position or by its id (searched in submenus too, as Windows does).
bool ReadItem(HMENU menu, UINT at, bool byPosition, Item& item)
{
    item = Item();
    item.info.fMask = Mask | MIIM_STRING;
    item.info.dwTypeData = nullptr;
    if (!GetMenuItemInfoW(menu, at, byPosition, &item.info)) return false;
    // Owner-drawn items too: Explorer's full menu makes every item owner-drawn before showing it, and the text stays
    // with the item apart from its type.
    if (!(item.info.fType & (MFT_SEPARATOR | MFT_BITMAP)) && item.info.cch > 0)
    {
        item.text.resize(item.info.cch + 1);
        item.info.cch++;
        item.info.dwTypeData = item.text.data();
        if (!GetMenuItemInfoW(menu, at, byPosition, &item.info)) return false;
        item.text.resize(wcslen(item.text.c_str()));
        item.hasText = true;
    }
    return true;
}

bool Read(HMENU menu, std::vector<Item>& items)
{
    const int count = GetMenuItemCount(menu);
    if (count < 0) return false;
    for (int i = 0; i < count; i++)
    {
        Item item;
        if (!ReadItem(menu, i, true, item)) return false;
        items.push_back(item);
    }
    return true;
}

bool Insert(HMENU menu, const Item& item)
{
    MENUITEMINFOW info = item.info;
    info.fMask = Mask | (item.hasText ? MIIM_STRING : 0);
    info.dwTypeData = item.hasText ? const_cast<wchar_t*>(item.text.c_str()) : nullptr;
    return InsertMenuItemW(menu, GetMenuItemCount(menu), TRUE, &info) != 0;
}

bool IsSeparator(const Item& item) { return (item.info.fType & MFT_SEPARATOR) != 0; }

// No line at the start or end, never two in a row.
std::vector<Item> WithoutStrayLines(const std::vector<Item>& items)
{
    std::vector<Item> result;
    for (const auto& item : items)
    {
        if (IsSeparator(item) && (result.empty() || IsSeparator(result.back()))) continue;
        result.push_back(item);
    }
    while (!result.empty() && IsSeparator(result.back())) result.pop_back();
    return result;
}

void Empty(HMENU menu)
{
    while (GetMenuItemCount(menu) > 0) RemoveMenu(menu, 0, MF_BYPOSITION);   // submenus taken out, not destroyed
}

// A menu shown arranged: what to put back afterwards.
struct Arranged
{
    HMENU original = nullptr;
    HMENU shown = nullptr;
    std::vector<HMENU> made;       // the new top menu and the user's submenus
    std::vector<Item> items;       // Windows' items, in Windows' order
    bool emptied = false;          // Windows' items taken out of the original
};

// Everything as it was: the new menus gone, Windows' items back in the original in their order.
void Restore(Arranged& a)
{
    for (auto m : a.made) { Empty(m); DestroyMenu(m); }
    a.made.clear();
    if (!a.emptied) return;
    Empty(a.original);
    for (const auto& item : a.items) Insert(a.original, item);
    a.emptied = false;
}

// Windows' menu laid out by the layout into a new menu, its items moved there. False: nothing to arrange or an error;
// the original menu is then as it was.
bool Arrange(HMENU original, Arranged& a)
{
    a.original = original;
    if (!Read(original, a.items)) return false;
    const auto groups = Layout();
    if (Tracing())
        for (const auto& item : a.items)
        {
            wchar_t line[96];
            swprintf_s(line, L"  item id=%u type=0x%X state=0x%X data=%p bitmap=%p text=", item.info.wID, item.info.fType,
                item.info.fState, reinterpret_cast<void*>(item.info.dwItemData), static_cast<void*>(item.info.hbmpItem));
            Log(line + (item.hasText ? L"\"" + NameOf(item.text) + L"\"" : std::wstring(L"(none)")));
        }

    // Which group each item goes to (-1: stays where it is).
    std::vector<int> groupOf(a.items.size(), -1);
    bool any = false;
    for (size_t i = 0; i < a.items.size(); i++)
    {
        if (IsSeparator(a.items[i]) || !a.items[i].hasText) continue;
        const auto name = NameOf(a.items[i].text);
        for (size_t g = 0; g < groups.size() && groupOf[i] < 0; g++)
            for (const auto& p : groups[g].patterns)
                if (Matches(p.c_str(), name.c_str())) { groupOf[i] = static_cast<int>(g); any = true; break; }
    }
    if (!any) return false;

    // The new menus: one per group, holding its items in Windows' order (no lines: a submenu is one group).
    MENUINFO style = { sizeof(MENUINFO), MIM_STYLE | MIM_MENUDATA | MIM_BACKGROUND | MIM_MAXHEIGHT | MIM_HELPID };
    const bool hasStyle = GetMenuInfo(original, &style) != 0;
    auto make = [&]() {
        const HMENU m = CreatePopupMenu();
        if (m) { a.made.push_back(m); if (hasStyle) SetMenuInfo(m, &style); }
        return m;
    };
    a.shown = make();
    if (!a.shown) return false;
    std::vector<HMENU> groupMenu(groups.size(), nullptr);

    // The top level: Windows' order, each group's submenu where its first item was.
    std::vector<Item> top;
    for (size_t i = 0; i < a.items.size(); i++)
    {
        const int g = groupOf[i];
        if (g < 0) { top.push_back(a.items[i]); continue; }
        if (groupMenu[g]) continue;
        groupMenu[g] = make();
        if (!groupMenu[g]) return false;
        Item sub;
        sub.info.fType = MFT_STRING;
        sub.info.hSubMenu = groupMenu[g];
        sub.text = groups[g].name;
        sub.hasText = true;
        top.push_back(sub);
    }

    Empty(original);   // every item now lives in the new menus only; Restore puts them back
    a.emptied = true;
    for (size_t i = 0; i < a.items.size(); i++)
        if (groupOf[i] >= 0 && !Insert(groupMenu[groupOf[i]], a.items[i])) return false;
    for (const auto& item : WithoutStrayLines(top))
        if (!Insert(a.shown, item)) return false;
    return true;
}

// ---- the menus being built, and the hook --------------------------------------------------------------------------

SRWLOCK notedLock = SRWLOCK_INIT;
std::vector<HMENU> noted;

void Note(HMENU menu)
{
    AcquireSRWLockExclusive(&notedLock);
    std::erase_if(noted, [](HMENU m) { return !IsMenu(m); });
    if (std::find(noted.begin(), noted.end(), menu) == noted.end()) noted.push_back(menu);
    ReleaseSRWLockExclusive(&notedLock);
}

bool TakeNoted(HMENU menu)
{
    AcquireSRWLockExclusive(&notedLock);
    const auto at = std::find(noted.begin(), noted.end(), menu);
    const bool found = at != noted.end();
    if (found) noted.erase(at);
    ReleaseSRWLockExclusive(&notedLock);
    return found;
}

using TrackPopupMenuExFn = BOOL(WINAPI*)(HMENU, UINT, int, int, HWND, LPTPMPARAMS);
using TrackPopupMenuFn = BOOL(WINAPI*)(HMENU, UINT, int, int, int, HWND, const RECT*);
TrackPopupMenuExFn realTrackPopupMenuEx = nullptr;
TrackPopupMenuFn realTrackPopupMenu = nullptr;

// ---- changes made while an arranged menu is shown (plan 01 3.1) ---------------------------------------------------
// Explorer sets Explorer commands' states after the show, on its own menu, by id: SetMenuItemInfoW (MIIM_STATE) for an
// item shown, DeleteMenu for one hidden. Those items are in the arranged menu then, so such a call by id on Windows'
// menu, from the thread showing it, is made on the arranged menu instead (a search by id covers the user's submenus),
// and the saved item follows it, so Windows' menu is put back with the change. A group left empty goes. Calls by
// position on Windows' menu cannot be mapped and are left as they are. With Trace on, every call is in the log.

SRWLOCK activeLock = SRWLOCK_INIT;
Arranged* active = nullptr;           // the arranged menu being shown, if any
DWORD activeThread = 0;               // the thread showing it
bool activeTrace = false;
thread_local bool own = false;        // Dexmenu's own menu calls (arranging, putting back): not traced or redirected

// The menu a call is made on: the arranged one for a by-id call on Windows' menu while it is shown arranged.
HMENU Target(HMENU m, bool byPosition)
{
    if (own || byPosition || GetCurrentThreadId() != activeThread) return m;
    AcquireSRWLockShared(&activeLock);
    const HMENU target = active && m == active->original ? active->shown : m;
    ReleaseSRWLockShared(&activeLock);
    return target;
}

// After a redirected call on item `id`: the saved item as the arranged menu now has it, or gone; an empty group gone.
void Follow(UINT id, bool gone)
{
    Arranged* a = active;   // only the showing thread redirects, and only while it shows
    if (!a) return;
    own = true;
    for (size_t i = 0; i < a->items.size(); i++)
    {
        if (IsSeparator(a->items[i]) || a->items[i].info.wID != id) continue;
        if (gone) a->items.erase(a->items.begin() + i);
        else
        {
            Item now;
            if (ReadItem(a->shown, id, false, now)) a->items[i] = now;
        }
        break;
    }
    if (gone)
        for (size_t g = 1; g < a->made.size(); g++)
        {
            const HMENU group = a->made[g];
            if (GetMenuItemCount(group) != 0) continue;
            for (int p = GetMenuItemCount(a->shown) - 1; p >= 0; p--)
                if (GetSubMenu(a->shown, p) == group) RemoveMenu(a->shown, p, MF_BYPOSITION);
            DestroyMenu(group);
            a->made.erase(a->made.begin() + g);
            g--;
        }
    own = false;
}

std::wstring RoleOf(HMENU m)
{
    if (!active) return L"?";
    if (m == active->original) return L"ORIGINAL";
    if (m == active->shown) return L"arranged";
    for (auto x : active->made) if (x == m) return L"group";
    for (const auto& item : active->items) if (item.info.hSubMenu == m) return L"windows-submenu";
    return L"other";
}

void TraceCall(const wchar_t* call, HMENU m, UINT item, bool byPosition, const std::wstring& what, BOOL result)
{
    if (own) return;
    AcquireSRWLockShared(&activeLock);
    const bool on = active && activeTrace;
    std::wstring role = on ? RoleOf(m) : L"";
    ReleaseSRWLockShared(&activeLock);
    if (!on) return;
    wchar_t line[200];
    swprintf_s(line, L"  call %s thread=%lu menu=%p (%s) %s=%u %s -> %d", call, GetCurrentThreadId(), static_cast<void*>(m),
        role.c_str(), byPosition ? L"pos" : L"id", item, what.c_str(), result);
    own = true;
    Log(line);
    own = false;
}

std::wstring InfoText(LPCMENUITEMINFOW info)
{
    if (!info) return L"null";
    wchar_t s[120];
    swprintf_s(s, L"mask=0x%X type=0x%X state=0x%X id=%u", info->fMask, info->fType, info->fState, info->wID);
    return s;
}

using EnableMenuItemFn = BOOL(WINAPI*)(HMENU, UINT, UINT);
using SetMenuItemInfoWFn = BOOL(WINAPI*)(HMENU, UINT, BOOL, LPCMENUITEMINFOW);
using InsertMenuItemWFn = BOOL(WINAPI*)(HMENU, UINT, BOOL, LPCMENUITEMINFOW);
using DeleteMenuFn = BOOL(WINAPI*)(HMENU, UINT, UINT);
using ModifyMenuWFn = BOOL(WINAPI*)(HMENU, UINT, UINT, UINT_PTR, LPCWSTR);
using CheckMenuItemFn = DWORD(WINAPI*)(HMENU, UINT, UINT);
EnableMenuItemFn realEnableMenuItem = nullptr;
SetMenuItemInfoWFn realSetMenuItemInfoW = nullptr;
InsertMenuItemWFn realInsertMenuItemW = nullptr;
DeleteMenuFn realDeleteMenu = nullptr;
DeleteMenuFn realRemoveMenu = nullptr;
ModifyMenuWFn realModifyMenuW = nullptr;
CheckMenuItemFn realCheckMenuItem = nullptr;

// Each call: made on its target (Target), traced, and for a redirected one the saved item follows (Follow).
BOOL WINAPI HookEnableMenuItem(HMENU m, UINT item, UINT flags)
{
    const bool byPosition = (flags & MF_BYPOSITION) != 0;
    const HMENU t = Target(m, byPosition);
    const BOOL r = realEnableMenuItem(t, item, flags);
    TraceCall(L"EnableMenuItem", m, item, byPosition, L"flags=0x" + std::to_wstring(flags) + (t != m ? L" redirected" : L""), r);
    if (t != m && r != -1) Follow(item, false);
    return r;
}

BOOL WINAPI HookSetMenuItemInfoW(HMENU m, UINT item, BOOL byPosition, LPCMENUITEMINFOW info)
{
    const HMENU t = Target(m, byPosition != 0);
    const BOOL r = realSetMenuItemInfoW(t, item, byPosition, info);
    TraceCall(L"SetMenuItemInfoW", m, item, byPosition != 0, InfoText(info) + (t != m ? L" redirected" : L""), r);
    if (t != m && r) Follow(info && (info->fMask & MIIM_ID) ? info->wID : item, false);
    return r;
}

BOOL WINAPI HookInsertMenuItemW(HMENU m, UINT item, BOOL byPosition, LPCMENUITEMINFOW info)
{
    const BOOL r = realInsertMenuItemW(m, item, byPosition, info);
    TraceCall(L"InsertMenuItemW", m, item, byPosition != 0, InfoText(info), r);
    return r;
}

BOOL WINAPI HookDeleteMenu(HMENU m, UINT item, UINT flags)
{
    const bool byPosition = (flags & MF_BYPOSITION) != 0;
    const HMENU t = Target(m, byPosition);
    const BOOL r = realDeleteMenu(t, item, flags);
    TraceCall(L"DeleteMenu", m, item, byPosition, t != m ? L"redirected" : L"", r);
    if (t != m && r) Follow(item, true);
    return r;
}

BOOL WINAPI HookRemoveMenu(HMENU m, UINT item, UINT flags)
{
    const bool byPosition = (flags & MF_BYPOSITION) != 0;
    const HMENU t = Target(m, byPosition);
    const BOOL r = realRemoveMenu(t, item, flags);
    TraceCall(L"RemoveMenu", m, item, byPosition, t != m ? L"redirected" : L"", r);
    if (t != m && r) Follow(item, true);
    return r;
}

BOOL WINAPI HookModifyMenuW(HMENU m, UINT item, UINT flags, UINT_PTR id, LPCWSTR text)
{
    const bool byPosition = (flags & MF_BYPOSITION) != 0;
    const HMENU t = Target(m, byPosition);
    const BOOL r = realModifyMenuW(t, item, flags, id, text);
    TraceCall(L"ModifyMenuW", m, item, byPosition, L"flags=0x" + std::to_wstring(flags) + L" newid=" + std::to_wstring(id) + (t != m ? L" redirected" : L""), r);
    if (t != m && r) Follow((flags & MF_POPUP) ? item : static_cast<UINT>(id), false);
    return r;
}

DWORD WINAPI HookCheckMenuItem(HMENU m, UINT item, UINT flags)
{
    const bool byPosition = (flags & MF_BYPOSITION) != 0;
    const HMENU t = Target(m, byPosition);
    const DWORD r = realCheckMenuItem(t, item, flags);
    TraceCall(L"CheckMenuItem", m, item, byPosition, L"flags=0x" + std::to_wstring(flags) + (t != m ? L" redirected" : L""), static_cast<BOOL>(r));
    if (t != m && r != static_cast<DWORD>(-1)) Follow(item, false);
    return r;
}

template <typename Show>
BOOL ShowArranged(HMENU menu, Show show)
{
    const bool trace = Tracing();
    if (!TakeNoted(menu) || !Enabled())
    {
        if (trace) Log(L"show " + Hex(menu) + L" (" + std::to_wstring(GetMenuItemCount(menu)) + L" items): not noted, passed through");
        return show(menu);
    }
    Arranged a;
    bool arranged = false;
    own = true;
    try { arranged = Arrange(menu, a); }
    catch (...) { arranged = false; }
    own = false;
    if (trace) Log(L"show " + Hex(menu) + L" (" + std::to_wstring(a.items.size()) + L" items): noted, "
        + (arranged ? L"arranged into " + std::to_wstring(GetMenuItemCount(a.shown)) + L" items" : std::wstring(L"nothing to arrange")));
    if (!arranged)
    {
        if (!a.made.empty()) Log(L"arranging failed; Windows' menu shown");
        own = true;
        Restore(a);
        own = false;
        return show(menu);
    }
    AcquireSRWLockExclusive(&activeLock);
    active = &a;
    activeThread = GetCurrentThreadId();
    activeTrace = trace;
    ReleaseSRWLockExclusive(&activeLock);
    const BOOL result = show(a.shown);
    AcquireSRWLockExclusive(&activeLock);
    active = nullptr;
    activeThread = 0;
    ReleaseSRWLockExclusive(&activeLock);
    if (trace) Log(L"show " + Hex(menu) + L" closed, returned " + std::to_wstring(result));
    own = true;
    Restore(a);
    own = false;
    return result;
}

BOOL WINAPI HookTrackPopupMenuEx(HMENU menu, UINT flags, int x, int y, HWND owner, LPTPMPARAMS params)
{
    return ShowArranged(menu, [&](HMENU m) { return realTrackPopupMenuEx(m, flags, x, y, owner, params); });
}

BOOL WINAPI HookTrackPopupMenu(HMENU menu, UINT flags, int x, int y, int reserved, HWND owner, const RECT* rect)
{
    return ShowArranged(menu, [&](HMENU m) { return realTrackPopupMenu(m, flags, x, y, reserved, owner, rect); });
}

INIT_ONCE hooksOnce = INIT_ONCE_STATIC_INIT;

BOOL CALLBACK SetHooks(PINIT_ONCE, PVOID, PVOID*)
{
    // Kept loaded from now on: the hooks point into this DLL.
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&__ImageBase), &self);
    if (MH_Initialize() != MH_OK
        || MH_CreateHookApi(L"user32", "TrackPopupMenuEx", reinterpret_cast<LPVOID>(&HookTrackPopupMenuEx), reinterpret_cast<LPVOID*>(&realTrackPopupMenuEx)) != MH_OK
        || MH_CreateHookApi(L"user32", "TrackPopupMenu", reinterpret_cast<LPVOID>(&HookTrackPopupMenu), reinterpret_cast<LPVOID*>(&realTrackPopupMenu)) != MH_OK
        || MH_CreateHookApi(L"user32", "EnableMenuItem", reinterpret_cast<LPVOID>(&HookEnableMenuItem), reinterpret_cast<LPVOID*>(&realEnableMenuItem)) != MH_OK
        || MH_CreateHookApi(L"user32", "SetMenuItemInfoW", reinterpret_cast<LPVOID>(&HookSetMenuItemInfoW), reinterpret_cast<LPVOID*>(&realSetMenuItemInfoW)) != MH_OK
        || MH_CreateHookApi(L"user32", "InsertMenuItemW", reinterpret_cast<LPVOID>(&HookInsertMenuItemW), reinterpret_cast<LPVOID*>(&realInsertMenuItemW)) != MH_OK
        || MH_CreateHookApi(L"user32", "DeleteMenu", reinterpret_cast<LPVOID>(&HookDeleteMenu), reinterpret_cast<LPVOID*>(&realDeleteMenu)) != MH_OK
        || MH_CreateHookApi(L"user32", "RemoveMenu", reinterpret_cast<LPVOID>(&HookRemoveMenu), reinterpret_cast<LPVOID*>(&realRemoveMenu)) != MH_OK
        || MH_CreateHookApi(L"user32", "ModifyMenuW", reinterpret_cast<LPVOID>(&HookModifyMenuW), reinterpret_cast<LPVOID*>(&realModifyMenuW)) != MH_OK
        || MH_CreateHookApi(L"user32", "CheckMenuItem", reinterpret_cast<LPVOID>(&HookCheckMenuItem), reinterpret_cast<LPVOID*>(&realCheckMenuItem)) != MH_OK
        || MH_EnableHook(MH_ALL_HOOKS) != MH_OK)
    {
        Log(L"hooks not set");
        return FALSE;
    }
    return TRUE;
}

// ---- the context menu handler -------------------------------------------------------------------------------------

class DECLSPEC_UUID("CD4EEF01-47D9-4172-A48A-F6E61850D170") Handler
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>, IShellExtInit, IContextMenu>
{
public:
    IFACEMETHODIMP Initialize(PCIDLIST_ABSOLUTE, IDataObject*, HKEY) override { return S_OK; }

    IFACEMETHODIMP QueryContextMenu(HMENU menu, UINT, UINT, UINT, UINT flags) override
    {
        if (!(flags & CMF_DEFAULTONLY) && Enabled() && InitOnceExecuteOnce(&hooksOnce, SetHooks, nullptr, nullptr))
        {
            Note(menu);
            if (Tracing()) Log(L"noted " + Hex(menu) + L" (" + std::to_wstring(GetMenuItemCount(menu)) + L" items so far, flags " + std::to_wstring(flags) + L")");
        }
        return MAKE_HRESULT(SEVERITY_SUCCESS, 0, 0);   // no items of its own
    }

    IFACEMETHODIMP InvokeCommand(CMINVOKECOMMANDINFO*) override { return E_FAIL; }
    IFACEMETHODIMP GetCommandString(UINT_PTR, UINT, UINT*, CHAR*, UINT) override { return E_INVALIDARG; }
};

CoCreatableClass(Handler)

}   // namespace

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** object)
{
    return Module<InProc>::GetModule().GetClassObject(clsid, iid, object);
}

STDAPI DllCanUnloadNow()
{
    return Module<InProc>::GetModule().Terminate() ? S_OK : S_FALSE;
}
