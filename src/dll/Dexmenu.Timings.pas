unit Dexmenu.Timings;

// The right-clicks' timings (docs/plans/16-PLAN-diagnostics.md 3.2): per right-click Dexmenu handled, one entry in
// %LOCALAPPDATA%\Dexmenu\timings.json (DEXMENU_TIMINGS_FILE: the tests), the last 10 per program kept. Written after
// the menu closed, so the write costs the user nothing; several programs write it, one at a time (a named mutex).
//
//   { "entries": [ { "at": "2026-11-26T08:01:02.123", "program": "C:\\Windows\\explorer.exe", "kind": "file",
//                    "shown": "dexmenu" | "windows", "why": "<why Windows' menu>", "first": true,
//                    "wait": 812, "steps": [ [ "layout", 3 ], [ "read", 12 ], ... ] } ] }
//
// wait: ms from Dexmenu's handler being asked (QueryContextMenu) to the program's show call; steps: Dexmenu's own, in
// ms, in order; first: the first menu Dexmenu showed in this process (slower: the DLL and the drawing set up).

interface

type
  TTimingStep = record
    Name: string;
    Ms: Int64;
  end;

  TTiming = record
    Kind: string;
    Shown: string;     // 'dexmenu' or 'windows'
    Why: string;       // why Windows' menu ('' for Dexmenu's)
    First: Boolean;
    Wait: Int64;       // -1: not known
    Steps: TArray<TTimingStep>;
  end;

procedure AddStep(var Steps: TArray<TTimingStep>; const Name: string; Ms: Int64);
// Appends the entry, keeping the last KeepPerProgram of each program.
procedure RecordTiming(const T: TTiming);
function TimingsFile: string;
// The file's text with the entry appended and each program's oldest dropped beyond Keep; for the tests.
function TimingsWith(const Text, Program_, At: string; const T: TTiming; Keep: Integer): string;

const
  KeepPerProgram = 10;

implementation

uses
  Winapi.Windows, System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections, Dexmenu.Log, Dexmenu.Json;

procedure AddStep(var Steps: TArray<TTimingStep>; const Name: string; Ms: Int64);
begin
  SetLength(Steps, Length(Steps) + 1);
  Steps[High(Steps)].Name := Name;
  Steps[High(Steps)].Ms := Ms;
end;

function TimingsFile: string;
var
  Env: array[0..MAX_PATH] of Char;
begin
  if GetEnvironmentVariable('DEXMENU_TIMINGS_FILE', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := LocalAppData + '\Dexmenu\timings.json';
end;

function EntryOf(const Program_, At: string; const T: TTiming): TJSONObject;
var
  Steps, Step: TJSONArray;
  S: TTimingStep;
begin
  Result := TJSONObject.Create;
  Result.AddPair('at', At);
  Result.AddPair('program', Program_);
  Result.AddPair('kind', T.Kind);
  Result.AddPair('shown', T.Shown);
  if T.Why <> '' then
    Result.AddPair('why', T.Why);
  Result.AddPair('first', TJSONBool.Create(T.First));
  if T.Wait >= 0 then
    Result.AddPair('wait', TJSONNumber.Create(T.Wait));
  Steps := TJSONArray.Create;
  for S in T.Steps do
  begin
    Step := TJSONArray.Create;
    Step.Add(S.Name);
    Step.Add(S.Ms);
    Steps.AddElement(Step);
  end;
  Result.AddPair('steps', Steps);
end;

function TimingsWith(const Text, Program_, At: string; const T: TTiming; Keep: Integer): string;
var
  Root: TJSONValue;
  Old, Kept: TJSONArray;
  Counts: TDictionary<string, Integer>;
  Error, P: string;
  I, N: Integer;
  E: TJSONValue;
  Picked: TList<TJSONValue>;
begin
  Root := nil;
  if Text <> '' then
    Root := ParseWithComments(Text, Error);
  Counts := TDictionary<string, Integer>.Create;
  Picked := TList<TJSONValue>.Create;
  Kept := TJSONArray.Create;
  try
    Old := nil;
    if (Root is TJSONObject) and (TJSONObject(Root).GetValue('entries') is TJSONArray) then
      Old := TJSONArray(TJSONObject(Root).GetValue('entries'));
    // newest first, each program's first Keep taken (the new one counts), then put back oldest first
    Counts.Add(AnsiLowerCase(Program_), 1);
    if Old <> nil then
      for I := Old.Count - 1 downto 0 do
      begin
        E := Old.Items[I];
        if not (E is TJSONObject) or not (TJSONObject(E).GetValue('program') is TJSONString) then
          Continue;
        P := AnsiLowerCase(TJSONObject(E).GetValue('program').Value);
        if not Counts.TryGetValue(P, N) then
          N := 0;
        if N >= Keep then
          Continue;
        Counts.AddOrSetValue(P, N + 1);
        Picked.Insert(0, E);
      end;
    for E in Picked do
      Kept.AddElement(TJSONValue(E.Clone));
    Kept.AddElement(EntryOf(Program_, At, T));
    Result := '{ "entries": ' + Kept.ToJSON + ' }';
  finally
    Kept.Free;
    Picked.Free;
    Counts.Free;
    Root.Free;
  end;
end;

procedure RecordTiming(const T: TTiming);
var
  Mutex: THandle;
  Path, Text: string;
  Exe: array[0..MAX_PATH] of Char;
begin
  try
    GetModuleFileName(0, Exe, MAX_PATH);
    Path := TimingsFile;
    Mutex := CreateMutex(nil, False, 'Local\DexmenuTimings');
    if Mutex <> 0 then
      WaitForSingleObject(Mutex, 2000);
    try
      Text := '';
      if FileExists(Path) then
        Text := TFile.ReadAllText(Path, TEncoding.UTF8);
      ForceDirectories(ExtractFileDir(Path));
      TFile.WriteAllText(Path + '.tmp', TimingsWith(Text, Exe, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now), T,
        KeepPerProgram), TEncoding.UTF8);
      MoveFileEx(PChar(Path + '.tmp'), PChar(Path), MOVEFILE_REPLACE_EXISTING);
    finally
      if Mutex <> 0 then
      begin
        ReleaseMutex(Mutex);
        CloseHandle(Mutex);
      end;
    end;
  except
    on E: Exception do
      Log('timings not written: ' + E.Message);
  end;
end;

end.
