unit Dexmenu.Layout;

// The layout file (docs/plans/02-PLAN-own-menu.md 3.3, 3.5; plan 00 step 2): JSON with comments. Each kind of
// right-click is a key (for now only "default"); its value is a list of lines, top to bottom; a line holds cards. A
// card has a title and either rules or a menu (lines again, one level down). Every kind has exactly one card with the
// rule "remaining", which takes every top-level item no other rule took and places each, with its subitems, at its
// own place.
//
//   // the base layout: Windows' menu as cards
//   { "default": [ { "line": [ { "card": "Remaining", "rules": [ "remaining" ] } ] } ] }
//
// Which file: DEXMENU_LAYOUT_FILE (the tests), else %APPDATA%\Dexmenu\settings.json's "layout" (a name) as
// %APPDATA%\Dexmenu\layouts\<name>.json; no settings or no file: the built-in base layout. Read again when the file
// changes. A file that cannot be read or is not valid: no layout, the reason given (the menu then is Windows' own).

interface

uses
  System.Generics.Collections, System.JSON, Dexmenu.Rules;

type
  TLine = class;
  TCard = class;

  TRuleKind = (rkRemaining, rkMatch);

  TRule = class
  public
    Kind: TRuleKind;
    Raw: TJSONObject;    // rkMatch: the rule as written
    Spec: TRuleSpec;     // rkMatch: the rule parsed (Dexmenu.Rules); Spec.Valid False: it finds nothing
    Card: TCard;         // the card it is on
    Index: Integer;      // its place on that card, from 0
    destructor Destroy; override;
  end;

  TCard = class
  public
    Id: string;            // "id", or made up (c1, c2, ...) when the layout has none
    Title: string;         // "card": its name in the editor, and its title when it holds several items
    ShownTitle: string;    // "title": its title also when it holds one item ('' : the item's own text)
    RenameFrom, RenameTo: string;   // "rename": { "regex": ..., "replace": ... } on the item's text
    Parent: TCard;         // the card with a menu it sits in; nil at the top
    Hidden: Boolean;       // "hidden": shows nothing; its rules still take their items, so they show nowhere
    Rules: TObjectList<TRule>;
    Menu: TObjectList<TLine>;   // a card with a menu; nil for a card with rules
    constructor Create;
    destructor Destroy; override;
    function IsRemaining: Boolean;
  end;

  TLine = class
  public
    Cards: TObjectList<TCard>;
    constructor Create;
    destructor Destroy; override;
  end;

  TLines = TObjectList<TLine>;

  ILayout = interface
    ['{6B0B6E2C-3E0B-4E8E-9C61-2D0E54D7A0A1}']
    // The lines of a kind of right-click; the default kind's when that kind has none.
    function Lines(const Kind: string): TLines;
    function Source: string;   // the file it came from, or '(built in)'
  end;

// Parses a layout; nil and Error set when it is not valid.
function ParseLayout(const Text, Source: string; out Error: string): ILayout;
// The layout in use now (see above); nil and Error set when the file cannot be used.
function CurrentLayout(out Error: string): ILayout;
// The file CurrentLayout reads, or '' when it uses the built-in base layout.
function LayoutFile: string;

const
  BaseLayout = '// the base layout: Windows'' menu as cards'#10 +
    '{ "default": [ { "line": [ { "card": "Remaining", "rules": [ "remaining" ] } ] } ] }';

implementation

uses
  Winapi.Windows, System.SysUtils, System.SyncObjs, Dexmenu.Json, Dexmenu.Log;

type
  TLayout = class(TInterfacedObject, ILayout)
  private
    FKinds: TObjectDictionary<string, TLines>;
    FSource: string;
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Lines(const Kind: string): TLines;
    function Source: string;
  end;

destructor TRule.Destroy;
begin
  Raw.Free;
  inherited;
end;

constructor TCard.Create;
begin
  inherited;
  Rules := TObjectList<TRule>.Create;
end;

destructor TCard.Destroy;
begin
  Rules.Free;
  Menu.Free;
  inherited;
end;

function TCard.IsRemaining: Boolean;
var
  R: TRule;
begin
  for R in Rules do
    if R.Kind = rkRemaining then
      Exit(True);
  Result := False;
end;

constructor TLine.Create;
begin
  inherited;
  Cards := TObjectList<TCard>.Create;
end;

destructor TLine.Destroy;
begin
  Cards.Free;
  inherited;
end;

constructor TLayout.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FKinds := TObjectDictionary<string, TLines>.Create([doOwnsValues]);
end;

destructor TLayout.Destroy;
begin
  FKinds.Free;
  inherited;
end;

function TLayout.Lines(const Kind: string): TLines;
begin
  if not FKinds.TryGetValue(Kind, Result) then
    Result := FKinds['default'];
end;

function TLayout.Source: string;
begin
  Result := FSource;
end;

// ---- parsing ------------------------------------------------------------------------------------------------------

function ParseLines(Value: TJSONValue; const Where: string; Parent: TCard; Lines: TLines; var Error: string): Boolean;
  forward;

threadvar
  NextCardId: Integer;   // ids made up per parse; a layout may be parsed on several threads

function ParseCard(Value: TJSONValue; const Where: string; Parent: TCard; out Card: TCard; var Error: string): Boolean;
var
  Obj: TJSONObject;
  Rules, Menu: TJSONValue;
  Item: TJSONValue;
  Rule: TRule;
begin
  Card := nil;
  Result := False;
  if not (Value is TJSONObject) then
  begin
    Error := Where + ': a card must be an object';
    Exit;
  end;
  Obj := TJSONObject(Value);
  if not (Obj.GetValue('card') is TJSONString) then
  begin
    Error := Where + ': a card needs "card" (its title)';
    Exit;
  end;
  Card := TCard.Create;
  try
    Card.Title := Obj.GetValue('card').Value;
    Card.Parent := Parent;
    Inc(NextCardId);
    if Obj.GetValue('id') is TJSONString then
      Card.Id := Obj.GetValue('id').Value
    else
      Card.Id := 'c' + IntToStr(NextCardId);
    if Obj.GetValue('title') is TJSONString then
      Card.ShownTitle := Obj.GetValue('title').Value;
    if Obj.GetValue('hidden') is TJSONBool then
      Card.Hidden := TJSONBool(Obj.GetValue('hidden')).AsBoolean;   // not for the remaining card (Dexmenu.Place)
    if (Obj.GetValue('rename') is TJSONObject) and (TJSONObject(Obj.GetValue('rename')).GetValue('regex') <> nil) then
    begin
      Card.RenameFrom := TJSONObject(Obj.GetValue('rename')).GetValue('regex').Value;
      if TJSONObject(Obj.GetValue('rename')).GetValue('replace') <> nil then
        Card.RenameTo := TJSONObject(Obj.GetValue('rename')).GetValue('replace').Value;
    end;
    Rules := Obj.GetValue('rules');
    Menu := Obj.GetValue('menu');
    if (Rules <> nil) and (Menu <> nil) then
    begin
      Error := Where + ' "' + Card.Title + '": a card has either rules or a menu, not both';
      Exit;
    end;
    if Rules <> nil then
    begin
      if not (Rules is TJSONArray) then
      begin
        Error := Where + ' "' + Card.Title + '": "rules" must be a list';
        Exit;
      end;
      for Item in TJSONArray(Rules) do
      begin
        Rule := TRule.Create;
        Rule.Card := Card;
        Rule.Index := Card.Rules.Count;
        Card.Rules.Add(Rule);
        if (Item is TJSONString) and (Item.Value = 'remaining') then
          Rule.Kind := rkRemaining
        else if Item is TJSONObject then
        begin
          Rule.Kind := rkMatch;
          Rule.Raw := TJSONObject(Item.Clone);
          Rule.Spec := ParseRule(Rule.Raw);
        end
        else
        begin
          Error := Where + ' "' + Card.Title + '": a rule is "remaining" or an object';
          Exit;
        end;
      end;
    end;
    if Menu <> nil then
    begin
      Card.Menu := TLines.Create;
      if not ParseLines(Menu, Where + ' > ' + Card.Title, Card, Card.Menu, Error) then
        Exit;
    end;
    Result := True;
  finally
    if not Result then
      FreeAndNil(Card);
  end;
end;

function ParseLines(Value: TJSONValue; const Where: string; Parent: TCard; Lines: TLines; var Error: string): Boolean;
var
  Entry, CardValue: TJSONValue;
  LineCards: TJSONValue;
  Line: TLine;
  Card: TCard;
begin
  Result := False;
  if not (Value is TJSONArray) then
  begin
    Error := Where + ': must be a list of lines';
    Exit;
  end;
  for Entry in TJSONArray(Value) do
  begin
    if not (Entry is TJSONObject) then
    begin
      Error := Where + ': a line must be an object';
      Exit;
    end;
    LineCards := TJSONObject(Entry).GetValue('line');
    if LineCards = nil then
      Continue;   // other kinds of line (divider, row, ...) come with later steps
    if not (LineCards is TJSONArray) then
    begin
      Error := Where + ': "line" must be a list of cards';
      Exit;
    end;
    Line := TLine.Create;
    Lines.Add(Line);
    for CardValue in TJSONArray(LineCards) do
    begin
      if not ParseCard(CardValue, Where, Parent, Card, Error) then
        Exit;
      Line.Cards.Add(Card);
    end;
  end;
  Result := True;
end;

function CountRemaining(Lines: TLines): Integer;
var
  Line: TLine;
  Card: TCard;
begin
  Result := 0;
  for Line in Lines do
    for Card in Line.Cards do
    begin
      if Card.IsRemaining then
        Inc(Result);
      if Card.Menu <> nil then
        Inc(Result, CountRemaining(Card.Menu));
    end;
end;

function ParseLayout(const Text, Source: string; out Error: string): ILayout;
var
  Root: TJSONValue;
  Pair: TJSONPair;
  Layout: TLayout;
  Lines: TLines;
  N: Integer;
begin
  Result := nil;
  Root := ParseWithComments(Text, Error);
  if Root = nil then
  begin
    Error := Source + ': ' + Error;
    Exit;
  end;
  Layout := TLayout.Create(Source);
  try
    if not (Root is TJSONObject) then
    begin
      Error := Source + ': the layout must be an object, a kind of right-click per key';
      Exit;
    end;
    NextCardId := 0;
    for Pair in TJSONObject(Root) do
    begin
      if Pair.JsonString.Value = 'template' then
        Continue;   // the template card's look: plan 03, step 6
      Lines := TLines.Create;
      Layout.FKinds.Add(Pair.JsonString.Value, Lines);
      if not ParseLines(Pair.JsonValue, Source + ' ' + Pair.JsonString.Value, nil, Lines, Error) then
        Exit;
      N := CountRemaining(Lines);
      if N <> 1 then
      begin
        Error := Format('%s %s: exactly one remaining card needed, found %d', [Source, Pair.JsonString.Value, N]);
        Exit;
      end;
    end;
    if not Layout.FKinds.ContainsKey('default') then
    begin
      Error := Source + ': the kind "default" is missing';
      Exit;
    end;
    Result := Layout;
    Layout := nil;
  finally
    Layout.Free;   // only when not handed out
    Root.Free;
  end;
end;

// ---- the layout in use ---------------------------------------------------------------------------------------------

var
  Lock: TCriticalSection;
  CachedPath: string;
  CachedStamp: TFileTime;
  Cached: ILayout;
  CachedError: string;
  Base: ILayout;

function LayoutFile: string;
var
  Env: array[0..MAX_PATH] of Char;
  Text, Error, Name: string;
  Settings: TJSONValue;
begin
  if GetEnvironmentVariable('DEXMENU_LAYOUT_FILE', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := '';
  if not ReadTextFile(RoamingAppData + '\Dexmenu\settings.json', Text) then
    Exit;
  Settings := ParseWithComments(Text, Error);
  try
    if (Settings is TJSONObject) and (TJSONObject(Settings).GetValue('layout') is TJSONString) then
    begin
      Name := TJSONObject(Settings).GetValue('layout').Value;
      if Name <> '' then
        Result := RoamingAppData + '\Dexmenu\layouts\' + Name + '.json';
    end;
  finally
    Settings.Free;
  end;
end;

function CurrentLayout(out Error: string): ILayout;
var
  Path, Text: string;
  Data: TWin32FileAttributeData;
begin
  Error := '';
  Path := LayoutFile;
  Lock.Enter;
  try
    if (Path = '') or not GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Data) then
    begin
      if Base = nil then
        Base := ParseLayout(BaseLayout, '(built in)', Error);
      Exit(Base);
    end;
    if (Path <> CachedPath) or (CompareFileTime(Data.ftLastWriteTime, CachedStamp) <> 0) then
    begin
      CachedPath := Path;
      CachedStamp := Data.ftLastWriteTime;
      Cached := nil;
      CachedError := '';
      if not ReadTextFile(Path, Text) then
        CachedError := Path + ': cannot be read'
      else
        Cached := ParseLayout(Text, Path, CachedError);
      if Cached = nil then
        Log('layout not used: ' + CachedError);
    end;
    Error := CachedError;
    Result := Cached;
  finally
    Lock.Leave;
  end;
end;

initialization
  Lock := TCriticalSection.Create;

end.
