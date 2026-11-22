unit Dexmenu.Theme;

// Themes (docs/plans/03-PLAN-menu-look.md 3.2, 3.3): a JSON file with comments, "name", "base" (another theme), a
// "palette" (named colours and "basecolor") and, per element and state, its properties. A theme holds only what
// differs from its base; "light" and "dark" are built in and set everything. A colour in an element is a literal
// ("#rrggbb", "rgba(...)"), a palette name, or { "color": <palette name or literal>, "intensity": 0 - 200,
// "opacity": 0 - 100 }: intensity 0 the base colour, 100 the colour, 200 the base colour inverted, mixed per
// channel in sRGB; opacity, when given, overrules the colour's own alpha.

interface

uses
  System.SysUtils, System.JSON;

type
  TRGBA = record
    R, G, B, A: Single;   // 0 - 1
  end;

  TTheme = class
  private
    FRoot: TJSONObject;     // the theme with its bases merged in (owned)
    FPalette: TJSONObject;  // FRoot's palette (not owned)
    function Value(const Element, State, Prop: string): TJSONValue;
    function Resolve(V: TJSONValue; out Color: TRGBA; Depth: Integer = 0): Boolean;
    procedure Problem(const Text: string);
  public
    Name: string;
    Problems: string;       // what could not be read (an unknown palette name, a bad colour), for the log
    constructor Create(Root: TJSONObject; const AName: string);
    destructor Destroy; override;
    // A property's colour: Element.State.Prop, else Element.normal.Prop, else Default.
    function Color(const Element, State, Prop: string; const Default: TRGBA): TRGBA;
    // A property's number (a radius, a width): as Color, a number.
    function Number(const Element, State, Prop: string; Default: Single): Single;
  end;

// A colour from its text: "#rgb", "#rrggbb", "#rrggbbaa", "rgba(r, g, b, a)", "rgb(r, g, b)".
function ParseColor(const Text: string; out Color: TRGBA): Boolean;
function RGBA(R, G, B: Byte; A: Single = 1): TRGBA;
// The intensity mix (plan 03 3.2): 0 Base, 100 Color, 200 Base inverted; per channel in sRGB; Color's alpha kept.
function Intensity(const Base, Color: TRGBA; Value: Single): TRGBA;
// The theme for light or dark, as the global settings name it (menu.themeLight, menu.themeDark; else "light" and
// "dark"), from %APPDATA%\Dexmenu\themes, then the DLL's themes folder, then the built-in ones. Read again when its
// files change. The caller does not free it.
function CurrentTheme(Dark: Boolean): TTheme;
// A theme from its text and those of its bases (Lookup gives a base theme's text by name); for the tests.
function ThemeFromText(const Text: string; Lookup: TFunc<string, string>; out Error: string): TTheme;
// The built-in themes' names.
const
  BuiltInLight = 'light';
  BuiltInDark = 'dark';

implementation

uses
  Winapi.Windows, System.Math, System.Generics.Collections, System.SyncObjs, System.IOUtils,
  Dexmenu.Json, Dexmenu.Log, Dexmenu.Layout;

const
  // The built-in themes: everything the engine draws today, in Windows 11's colours.
  LightText =
    '{ "name": "light",' +
    '  "palette": { "basecolor": "#f9f9f9", "surface": "#f9f9f9", "border": "#d0d0d0", "text": "#1b1b1b",' +
    '               "dim": "#a0a0a0", "line": "#e0e0e0", "accent": "#2f6fd6" },' +
    '  "menu": { "normal": { "background": "surface", "border": "border", "radius": 8 } },' +
    '  "card": { "normal": { "foreground": "text", "extra": "dim", "mark": "text", "radius": 4 },' +
    '            "hover": { "background": { "color": "#000000", "opacity": 6 } },' +
    '            "disabled": { "foreground": "dim", "mark": "dim" },' +
    '            "focused": { "border": "accent" },' +
    '            "unavailable": { "background": { "color": "#000000", "opacity": 9 } } },' +
    '  "divider": { "normal": { "border": "line", "foreground": "dim" } } }';
  DarkText =
    '{ "name": "dark",' +
    '  "palette": { "basecolor": "#2b2b2b", "surface": "#2b2b2b", "border": "#454545", "text": "#ffffff",' +
    '               "dim": "#808080", "line": "#454545", "accent": "#6aa8ff" },' +
    '  "menu": { "normal": { "background": "surface", "border": "border", "radius": 8 } },' +
    '  "card": { "normal": { "foreground": "text", "extra": "dim", "mark": "text", "radius": 4 },' +
    '            "hover": { "background": { "color": "text", "opacity": 8 } },' +
    '            "disabled": { "foreground": "dim", "mark": "dim" },' +
    '            "focused": { "border": "accent" },' +
    '            "unavailable": { "background": { "color": "text", "opacity": 10 } } },' +
    '  "divider": { "normal": { "border": "line", "foreground": "dim" } } }';

function RGBA(R, G, B: Byte; A: Single): TRGBA;
begin
  Result.R := R / 255;
  Result.G := G / 255;
  Result.B := B / 255;
  Result.A := A;
end;

function ParseColor(const Text: string; out Color: TRGBA): Boolean;
var
  T, Inner: string;
  Parts: TArray<string>;
  V: Cardinal;
  N: Integer;
  F: Double;
  Fmt: TFormatSettings;
begin
  Result := False;
  Color := RGBA(0, 0, 0);
  T := Trim(Text).ToLower;
  Fmt := TFormatSettings.Invariant;
  if T.StartsWith('#') then
  begin
    Inner := Copy(T, 2, MaxInt);
    if not TryStrToUInt('$' + Inner, V) then
      Exit;
    case Length(Inner) of
      3: Color := RGBA(((V shr 8) and $F) * 17, ((V shr 4) and $F) * 17, (V and $F) * 17);
      6: Color := RGBA((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
      8: Color := RGBA((V shr 24) and $FF, (V shr 16) and $FF, (V shr 8) and $FF, (V and $FF) / 255);
    else
      Exit;
    end;
    Exit(True);
  end;
  if (T.StartsWith('rgba(') or T.StartsWith('rgb(')) and T.EndsWith(')') then
  begin
    Inner := Copy(T, Pos('(', T) + 1, Length(T) - Pos('(', T) - 1);
    Parts := Inner.Split([',']);
    if not (Length(Parts) in [3, 4]) then
      Exit;
    for N := 0 to 2 do
      if not TryStrToFloat(Trim(Parts[N]), F, Fmt) or (F < 0) or (F > 255) then
        Exit;
    Color := RGBA(Round(StrToFloat(Trim(Parts[0]), Fmt)), Round(StrToFloat(Trim(Parts[1]), Fmt)),
      Round(StrToFloat(Trim(Parts[2]), Fmt)));
    if Length(Parts) = 4 then
    begin
      if not TryStrToFloat(Trim(Parts[3]), F, Fmt) or (F < 0) or (F > 1) then
        Exit;
      Color.A := F;
    end;
    Exit(True);
  end;
end;

function Intensity(const Base, Color: TRGBA; Value: Single): TRGBA;

  function Mix(A, B, T: Single): Single;
  begin
    Result := A + (B - A) * T;
  end;

begin
  Value := Max(0, Min(200, Value));
  Result := Color;
  if Value <= 100 then
  begin
    Result.R := Mix(Base.R, Color.R, Value / 100);
    Result.G := Mix(Base.G, Color.G, Value / 100);
    Result.B := Mix(Base.B, Color.B, Value / 100);
  end
  else
  begin
    Result.R := Mix(Color.R, 1 - Base.R, (Value - 100) / 100);
    Result.G := Mix(Color.G, 1 - Base.G, (Value - 100) / 100);
    Result.B := Mix(Color.B, 1 - Base.B, (Value - 100) / 100);
  end;
end;

// ---- the theme --------------------------------------------------------------------------------------------------------

constructor TTheme.Create(Root: TJSONObject; const AName: string);
begin
  inherited Create;
  FRoot := Root;
  Name := AName;
  if FRoot.GetValue('palette') is TJSONObject then
    FPalette := TJSONObject(FRoot.GetValue('palette'));
end;

destructor TTheme.Destroy;
begin
  FRoot.Free;
  inherited;
end;

procedure TTheme.Problem(const Text: string);
begin
  if Pos(Text, Problems) = 0 then
    Problems := Problems + Text + '; ';
end;

function TTheme.Value(const Element, State, Prop: string): TJSONValue;
var
  E, S: TJSONValue;
begin
  Result := nil;
  E := FRoot.GetValue(Element);
  if not (E is TJSONObject) then
    Exit;
  S := TJSONObject(E).GetValue(State);
  if S is TJSONObject then
    Result := TJSONObject(S).GetValue(Prop);
  if (Result = nil) and (State <> 'normal') then
  begin
    S := TJSONObject(E).GetValue('normal');
    if S is TJSONObject then
      Result := TJSONObject(S).GetValue(Prop);
  end;
end;

function TTheme.Resolve(V: TJSONValue; out Color: TRGBA; Depth: Integer): Boolean;
var
  Base: TRGBA;
  Named: TJSONValue;
  N: Single;
begin
  Result := False;
  Color := RGBA(0, 0, 0);
  if (V = nil) or (Depth > 8) then
    Exit;
  if V is TJSONString then
  begin
    if ParseColor(V.Value, Color) then
      Exit(True);
    // a palette name
    Named := nil;
    if FPalette <> nil then
      Named := FPalette.GetValue(V.Value);
    if Named = nil then
    begin
      Problem('an unknown colour or palette name: ' + V.Value);
      Exit;
    end;
    Exit(Resolve(Named, Color, Depth + 1));
  end;
  if V is TJSONObject then
  begin
    if not Resolve(TJSONObject(V).GetValue('color'), Color, Depth + 1) then
      Exit;
    if TJSONObject(V).GetValue('intensity') is TJSONNumber then
    begin
      N := TJSONNumber(TJSONObject(V).GetValue('intensity')).AsDouble;
      if (N < 0) or (N > 200) then
        Problem(Format('an intensity outside 0 - 200: %g', [N]));
      Base := RGBA(0, 0, 0);
      if (FPalette = nil) or not Resolve(FPalette.GetValue('basecolor'), Base, Depth + 1) then
        Problem('an intensity without a basecolor in the palette');
      Color := Intensity(Base, Color, N);
    end;
    if TJSONObject(V).GetValue('opacity') is TJSONNumber then
      Color.A := Max(0, Min(100, TJSONNumber(TJSONObject(V).GetValue('opacity')).AsDouble)) / 100;
    Exit(True);
  end;
end;

function TTheme.Color(const Element, State, Prop: string; const Default: TRGBA): TRGBA;
begin
  if not Resolve(Value(Element, State, Prop), Result) then
    Result := Default;
end;

function TTheme.Number(const Element, State, Prop: string; Default: Single): Single;
var
  V: TJSONValue;
begin
  V := Value(Element, State, Prop);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsDouble
  else
    Result := Default;
end;

// ---- loading ------------------------------------------------------------------------------------------------------------

// Over: its values over Base's, objects merged to any depth (Base changed; Over not).
procedure MergeInto(Base, Over: TJSONObject);
var
  P: TJSONPair;
  Old: TJSONValue;
begin
  for P in Over do
  begin
    Old := Base.GetValue(P.JsonString.Value);
    if (Old is TJSONObject) and (P.JsonValue is TJSONObject) then
      MergeInto(TJSONObject(Old), TJSONObject(P.JsonValue))
    else
    begin
      Base.RemovePair(P.JsonString.Value).Free;
      Base.AddPair(P.JsonString.Value, TJSONValue(P.JsonValue.Clone));
    end;
  end;
end;

function ThemeFromText(const Text: string; Lookup: TFunc<string, string>; out Error: string): TTheme;
var
  Chain: TList<TJSONObject>;
  V: TJSONValue;
  T, BaseName: string;
  Root: TJSONObject;
  I: Integer;
begin
  Result := nil;
  Error := '';
  Chain := TList<TJSONObject>.Create;
  try
    T := Text;
    while True do
    begin
      V := ParseWithComments(T, Error);
      if not (V is TJSONObject) then
      begin
        V.Free;
        if Error = '' then
          Error := 'a theme must be an object';
        Exit;
      end;
      Chain.Insert(0, TJSONObject(V));
      BaseName := '';
      if TJSONObject(V).GetValue('base') is TJSONString then
        BaseName := TJSONObject(V).GetValue('base').Value;
      if (BaseName = '') or (Chain.Count > 10) then
        Break;
      T := Lookup(BaseName);
      if T = '' then
      begin
        Error := 'its base "' + BaseName + '" is not there';
        Exit;
      end;
    end;
    Root := TJSONObject(Chain[0].Clone);
    for I := 1 to Chain.Count - 1 do
      MergeInto(Root, Chain[I]);
    T := '';
    if Chain.Last.GetValue('name') is TJSONString then
      T := Chain.Last.GetValue('name').Value;
    Result := TTheme.Create(Root, T);
  finally
    for I := 0 to Chain.Count - 1 do
      Chain[I].Free;
    Chain.Free;
  end;
end;

function ThemeFolders: TArray<string>;
begin
  Result := [DataFolder + '\themes', ExtractFilePath(GetModuleName(HInstance)) + 'themes'];
end;

// A theme's text by name: the user's file, the DLL's file, the built-in one; '' when there is none.
function ThemeText(const Name: string): string;
var
  Folder: string;
begin
  Result := '';
  for Folder in ThemeFolders do
    if FileExists(Folder + '\' + Name + '.json') and ReadTextFile(Folder + '\' + Name + '.json', Result) then
      Exit;
  if SameText(Name, BuiltInLight) then
    Result := LightText
  else if SameText(Name, BuiltInDark) then
    Result := DarkText;
end;

// What a theme's files are now (their times), so a change reads it again.
function Stamp(const Name: string): string;
var
  Folder, Path: string;
begin
  Result := Name;
  for Folder in ThemeFolders do
  begin
    Path := Folder + '\' + Name + '.json';
    if FileExists(Path) then
      Result := Result + '|' + Path + '@' + FloatToStr(TFile.GetLastWriteTime(Path));
  end;
end;

var
  Lock: TCriticalSection;
  Loaded: array[Boolean] of TTheme;
  LoadedStamp: array[Boolean] of string;

function CurrentTheme(Dark: Boolean): TTheme;
var
  Name, Error, S: string;
  Theme: TTheme;
  Lookup: TFunc<string, string>;
begin
  Lookup := function(Base: string): string
    begin
      Result := ThemeText(Base);
    end;
  if Dark then
    Name := MenuSettings.ThemeDark
  else
    Name := MenuSettings.ThemeLight;
  Lock.Enter;
  try
    S := Stamp(Name);
    if (Loaded[Dark] <> nil) and (LoadedStamp[Dark] = S) then
      Exit(Loaded[Dark]);
    Theme := nil;
    try
      Theme := ThemeFromText(ThemeText(Name), Lookup, Error);
    except
      on E: Exception do
        Error := E.Message;
    end;
    if (Theme = nil) or (ThemeText(Name) = '') then
    begin
      if Error = '' then
        Error := 'not there';
      Log('theme "' + Name + '" not read: ' + Error + '; the built-in one used');
      FreeAndNil(Theme);
      if Dark then
        Theme := ThemeFromText(DarkText, Lookup, Error)
      else
        Theme := ThemeFromText(LightText, Lookup, Error);
    end;
    Loaded[Dark].Free;
    Loaded[Dark] := Theme;
    LoadedStamp[Dark] := S;
    Result := Theme;
  finally
    Lock.Leave;
  end;
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  Loaded[False].Free;
  Loaded[True].Free;
  Lock.Free;

end.
