// DexmenuShell.dll: the spike of docs/plans/01-PLAN-dexmenu.md (3.1 - 3.4). A context menu handler that adds nothing:
// its QueryContextMenu notes the HMENU being built, and a hook on TrackPopupMenu(Ex) shows that menu arranged by the
// layout instead. The arranged menu holds Windows' own items (same ids, states, bitmaps, item data, submenu handles),
// so the program runs the chosen id on the menu it built, as before. After the call every item is put back.
//
// On only when HKCU\Software\Dexmenu Enabled is 1 or the environment variable DEXMENU is 1 (the tests); otherwise no
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
    if (GetEnvironmentVariableW(L"DEXMENU", env, 8) && wcscmp(env, L"1") == 0) return true;
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

bool Read(HMENU menu, std::vector<Item>& items)
{
    const int count = GetMenuItemCount(menu);
    if (count < 0) return false;
    for (int i = 0; i < count; i++)
    {
        Item item;
        item.info.fMask = Mask | MIIM_STRING;
        item.info.dwTypeData = nullptr;
        if (!GetMenuItemInfoW(menu, i, TRUE, &item.info)) return false;
        if (!(item.info.fType & (MFT_SEPARATOR | MFT_OWNERDRAW | MFT_BITMAP)) && item.info.cch > 0)
        {
            item.text.resize(item.info.cch + 1);
            item.info.cch++;
            item.info.dwTypeData = item.text.data();
            if (!GetMenuItemInfoW(menu, i, TRUE, &item.info)) return false;
            item.text.resize(wcslen(item.text.c_str()));
            item.hasText = true;
        }
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
    try { arranged = Arrange(menu, a); }
    catch (...) { arranged = false; }
    if (trace) Log(L"show " + Hex(menu) + L" (" + std::to_wstring(a.items.size()) + L" items): noted, "
        + (arranged ? L"arranged into " + std::to_wstring(GetMenuItemCount(a.shown)) + L" items" : std::wstring(L"nothing to arrange")));
    if (!arranged)
    {
        if (!a.made.empty()) Log(L"arranging failed; Windows' menu shown");
        Restore(a);
        return show(menu);
    }
    const BOOL result = show(a.shown);
    Restore(a);
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
