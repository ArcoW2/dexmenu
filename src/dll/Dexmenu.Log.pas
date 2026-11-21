unit Dexmenu.Log;

// On or off, the trace switch and the log (docs/plans/01-PLAN-dexmenu.md 3.8, 6.1, 6.2).
// On when the environment variable DEXMENU is 1, off when it is 0 (the tests); without it, on only when
// HKCU\Software\Dexmenu Enabled is 1. HKCU\Software\Dexmenu Trace 1: every menu noted and every show call in the log.
// The log: %LOCALAPPDATA%\Dexmenu\dexmenu.log, UTF-8, one line per event.

interface

function Enabled: Boolean;
function Tracing: Boolean;
procedure Log(const Text: string);
function LocalAppData: string;
function RoamingAppData: string;
function Hex(P: Pointer): string; overload;
function Hex(H: NativeUInt): string; overload;

implementation

uses
  Winapi.Windows, Winapi.ShlObj, Winapi.KnownFolders, Winapi.ActiveX, System.SysUtils;

const
  RRF_RT_REG_DWORD = $00000010;

function RegGetValueW(Key: HKEY; SubKey, Value: PWideChar; Flags: DWORD; ValueType: PDWORD; Data: Pointer;
  DataSize: PDWORD): LONG; stdcall; external advapi32 name 'RegGetValueW';

function SettingDword(const Name: string): DWORD;
var
  Size: DWORD;
begin
  Result := 0;
  Size := SizeOf(Result);
  if RegGetValueW(HKEY_CURRENT_USER, 'Software\Dexmenu', PWideChar(Name), RRF_RT_REG_DWORD, nil, @Result, @Size)
    <> ERROR_SUCCESS then
    Result := 0;
end;

function Enabled: Boolean;
var
  Env: array[0..7] of Char;
begin
  if GetEnvironmentVariable('DEXMENU', Env, Length(Env)) > 0 then
    Exit(string(Env) = '1');
  Result := SettingDword('Enabled') = 1;
end;

function Tracing: Boolean;
begin
  Result := SettingDword('Trace') = 1;
end;

function KnownFolder(const Id: TGUID): string;
var
  Path: PWideChar;
begin
  Result := '';
  if Succeeded(SHGetKnownFolderPath(Id, 0, 0, Path)) then
    Result := Path;
  CoTaskMemFree(Path);
end;

function LocalAppData: string;
begin
  Result := KnownFolder(FOLDERID_LocalAppData);
end;

function RoamingAppData: string;
begin
  Result := KnownFolder(FOLDERID_RoamingAppData);
end;

function Hex(P: Pointer): string;
begin
  Result := IntToHex(NativeUInt(P), SizeOf(Pointer) * 2);
end;

function Hex(H: NativeUInt): string;
begin
  Result := IntToHex(H, SizeOf(Pointer) * 2);
end;

procedure Log(const Text: string);
var
  Folder, Line: string;
  Exe: array[0..MAX_PATH] of Char;
  H: THandle;
  Bytes: TBytes;
  Written: DWORD;
begin
  Folder := LocalAppData + '\Dexmenu';
  CreateDirectory(PChar(Folder), nil);
  H := CreateFile(PChar(Folder + '\dexmenu.log'), FILE_APPEND_DATA, FILE_SHARE_READ or FILE_SHARE_WRITE, nil,
    OPEN_ALWAYS, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  GetModuleFileName(0, Exe, MAX_PATH);
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss ', Now) + string(Exe) + ': ' + Text + #13#10;
  Bytes := TEncoding.UTF8.GetBytes(Line);
  WriteFile(H, Bytes[0], Length(Bytes), Written, nil);
  CloseHandle(H);
end;

end.
