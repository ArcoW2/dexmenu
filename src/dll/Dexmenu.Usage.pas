unit Dexmenu.Usage;

// The use counts (docs/plans/executed/02-PLAN-own-menu.md 3.9): every choice in Dexmenu's menu counted per item and kind of
// right-click, in <DataFolder>\usage.json:
//   { "format": 1, "kinds": { "file": { "Open": 12, "7-Zip > Add to archive...": 3 } } }
// An item is known by its path in Windows' menu and its text (UsageKey), so a count holds across right-clicks.
// Beside "kinds", "last" holds the time of each item's last use by the same kind and key, in UTC, as a text that
// sorts as the time does (docs/plans/executed/09-PLAN-used-rules.md 3.2):
//   "last": { "file": { "Open": "2026-11-23T14:05:09.120Z" } }
// An older DLL reads "kinds" only and keeps "last" when it writes a count.

interface

uses
  System.Generics.Collections, Dexmenu.Tree;

// The item's key: its submenus and its text, 'A > B > Name'; just 'Name' at the top.
function UsageKey(Node: TNode): string;
// The counts of one kind of right-click (the caller frees it; empty when there are none).
function ReadUsage(const Kind: string): TDictionary<string, Integer>;
// The times of last use of one kind, by key (the caller frees it; empty when there are none; an item counted before
// times were kept has none).
function ReadLastUse(const Kind: string): TDictionary<string, string>;
// The time now as kept in "last".
function UsageTimeNow: string;
// One choice counted. Several Explorer processes may count at once: a named mutex keeps them in turn.
procedure CountChoice(const Kind, Key: string);
function UsageFile: string;
// Whether a count is of an item inside a submenu.
function UsageGoesDeeper(Usage: TDictionary<string, Integer>): Boolean;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.JSON, Dexmenu.Log, Dexmenu.Json;

function UsageKey(Node: TNode): string;
begin
  if Node.Path = '' then
    Result := Node.Name
  else
    Result := Node.Path + ' > ' + Node.Name;
end;

function UsageGoesDeeper(Usage: TDictionary<string, Integer>): Boolean;
var
  Key: string;
begin
  Result := False;
  if Usage <> nil then
    for Key in Usage.Keys do
      if Pos(' > ', Key) > 0 then
        Exit(True);
end;

function UsageFile: string;
begin
  Result := DataFolder + '\usage.json';
end;

function ReadRoot: TJSONObject;
var
  Text, Error: string;
  V: TJSONValue;
begin
  Result := nil;
  if FileExists(UsageFile) and ReadTextFile(UsageFile, Text) then
  begin
    V := ParseWithComments(Text, Error);
    if V is TJSONObject then
      Result := TJSONObject(V)
    else
    begin
      V.Free;
      if Error <> '' then
        Log('usage not read: ' + Error);
    end;
  end;
end;

function ReadUsage(const Kind: string): TDictionary<string, Integer>;
var
  Root: TJSONObject;
  Kinds, Counts: TJSONValue;
  P: TJSONPair;
begin
  Result := TDictionary<string, Integer>.Create;
  try
    Root := ReadRoot;
    try
      if Root = nil then
        Exit;
      Kinds := Root.GetValue('kinds');
      if not (Kinds is TJSONObject) then
        Exit;
      Counts := TJSONObject(Kinds).GetValue(Kind);
      if Counts is TJSONObject then
        for P in TJSONObject(Counts) do
          if P.JsonValue is TJSONNumber then
            Result.AddOrSetValue(P.JsonString.Value, TJSONNumber(P.JsonValue).AsInt);
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      Log('usage not read: ' + E.Message);
  end;
end;

function ReadLastUse(const Kind: string): TDictionary<string, string>;
var
  Root: TJSONObject;
  Last, Times: TJSONValue;
  P: TJSONPair;
begin
  Result := TDictionary<string, string>.Create;
  try
    Root := ReadRoot;
    try
      if Root = nil then
        Exit;
      Last := Root.GetValue('last');
      if not (Last is TJSONObject) then
        Exit;
      Times := TJSONObject(Last).GetValue(Kind);
      if Times is TJSONObject then
        for P in TJSONObject(Times) do
          if P.JsonValue is TJSONString then
            Result.AddOrSetValue(P.JsonString.Value, P.JsonValue.Value);
    finally
      Root.Free;
    end;
  except
    on E: Exception do
      Log('usage not read: ' + E.Message);
  end;
end;

function UsageTimeNow: string;
var
  T: TSystemTime;
begin
  GetSystemTime(T);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.3dZ', [T.wYear, T.wMonth, T.wDay, T.wHour, T.wMinute, T.wSecond,
    T.wMilliseconds]);
end;

// The object Name in Parent, made when it is missing or not an object.
function ObjectIn(Parent: TJSONObject; const Name: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := Parent.GetValue(Name);
  if V is TJSONObject then
    Exit(TJSONObject(V));
  Parent.RemovePair(Name).Free;
  Result := TJSONObject.Create;
  Parent.AddPair(Name, Result);
end;

procedure CountChoice(const Kind, Key: string);
var
  Mutex: THandle;
  Root, Kinds, Counts, Times: TJSONObject;
  V: TJSONValue;
  Count: Integer;
  Lines: TStringList;
begin
  if (Kind = '') or (Key = '') then
    Exit;
  Mutex := CreateMutex(nil, False, 'Local\DexmenuUsage');
  try
    if (Mutex <> 0) and (WaitForSingleObject(Mutex, 2000) = WAIT_TIMEOUT) then
    begin
      Log('usage not written: busy');
      CloseHandle(Mutex);
      Exit;
    end;
    try
      Root := ReadRoot;
      if Root = nil then
        Root := TJSONObject.Create;
      try
        if Root.GetValue('format') = nil then
          Root.AddPair('format', TJSONNumber.Create(1));
        V := Root.GetValue('kinds');
        if V is TJSONObject then
          Kinds := TJSONObject(V)
        else
        begin
          Root.RemovePair('kinds').Free;
          Kinds := TJSONObject.Create;
          Root.AddPair('kinds', Kinds);
        end;
        V := Kinds.GetValue(Kind);
        if V is TJSONObject then
          Counts := TJSONObject(V)
        else
        begin
          Kinds.RemovePair(Kind).Free;
          Counts := TJSONObject.Create;
          Kinds.AddPair(Kind, Counts);
        end;
        Count := 0;
        V := Counts.GetValue(Key);
        if V is TJSONNumber then
          Count := TJSONNumber(V).AsInt;
        Counts.RemovePair(Key).Free;
        Counts.AddPair(Key, TJSONNumber.Create(Count + 1));
        Times := ObjectIn(ObjectIn(Root, 'last'), Kind);
        Times.RemovePair(Key).Free;
        Times.AddPair(Key, UsageTimeNow);
        ForceDirectories(ExtractFilePath(UsageFile));
        Lines := TStringList.Create;
        try
          Lines.Text := Root.Format(2);
          Lines.SaveToFile(UsageFile + '.tmp', TEncoding.UTF8);
        finally
          Lines.Free;
        end;
        MoveFileEx(PChar(UsageFile + '.tmp'), PChar(UsageFile), MOVEFILE_REPLACE_EXISTING);
      finally
        Root.Free;
      end;
    finally
      if Mutex <> 0 then
        ReleaseMutex(Mutex);
    end;
  except
    on E: Exception do
      Log('usage not written: ' + E.Message);
  end;
  if Mutex <> 0 then
    CloseHandle(Mutex);
end;

end.
