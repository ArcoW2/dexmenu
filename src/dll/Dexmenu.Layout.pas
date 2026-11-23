unit Dexmenu.Layout;

// The layout file (docs/plans/executed/02-PLAN-own-menu.md 3.3, 3.5; plan 05 3.1): JSON with comments, one menu: "lines", a
// list of lines, top to bottom; a line holds cards (or is a divider). A card has a title and either rules or a menu
// (lines again, one level down). The menu has exactly one card with the rule "remaining", which takes every top-level
// item no other rule took and places each, with its subitems, at its own place. "format" says which form the file
// has (FormatVersion now); a newer one than this DLL knows is not used.
//
//   // the base layout: Windows' menu as cards
//   { "format": 1, "lines": [ { "line": [ { "card": "Remaining", "rules": [ "remaining" ] } ] } ] }
//
// A file of the older form (no "format": a section per kind of right-click, "default" among them) is read by its
// "default" section; its other sections are ignored (plan 05 3.1). Which layout a kind of right-click gets is
// settings.json's (plan 05 3.2), not the layout's.
//
// Which file for a kind of right-click: CurrentLayout (below; a name in settings.json as
// %APPDATA%\Dexmenu\layouts\<name>.json). A file that cannot be read or is not valid: no layout, the reason given
// (the menu then is Windows' own).

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
    // "template": which of its card's templates the items it finds follow when the card picks them by rule (from 0;
    // -1: none named, the first)
    TemplateIndex: Integer;
    destructor Destroy; override;
  end;

  TNoteAlign = (naLeft, naText, naCenter, naRight);   // a note's text: left, with the items' text, center, right
  // How a submenu opens (plan 02 3.4, 3.7): as the global setting, next to its card, under it, or
  // in place of the menu (with "<<" back)
  TSubmenuMode = (smDefault, smNext, smUnder, smReplace);
  // How a card lower than its line fits it (plan 03 3.5): as the line says (cfDefault), as tall as the line, or at its
  // own height at the line's top, centre or bottom.
  TCardFit = (cfDefault, cfStretch, cfTop, cfCenter, cfBottom);
  // How a card shows what it found or holds (docs/plans/11-PLAN-cards-hold-content.md 3.1): as its own item (several
  // found: the card multiplied), in a submenu, side by side inside it, under each other inside it. csDefault: its
  // rules: item; a format 1 "menu": submenu; format 2 "content": column.
  TCardShow = (csDefault, csItem, csSubmenu, csRow, csColumn);
  TRestOf = (roMenu, roNone);   // "rest": what does not fit a row's or column's limits: in a "More" submenu, left out
  // "shownWhen" of a card holding cards: only when something in it does something when chosen (the default), when
  // anything in it shows, always
  TShownWhen = (swActionItem, swAnyItem, swAlways);
  // "templatesBy": how the inner cards pick one of several templates: by their place (cycling: the first card the
  // first template, the second the second, ...) or by the rule that found them
  TTemplatesBy = (tbPosition, tbRule);

  // A level's width (DIP): from its minimum, grown by its lines up to its maximum (plan 02 3.4).
  TLevelWidth = record
    MinW, MaxW: Single;
  end;

  // The global settings for every menu (settings.json "menu"; plan 02 3.4).
  TMenuSettings = record
    SubmenuMark: string;      // the mark on a card with a submenu; '' the built-in chevron
    ActionMark: string;       // the mark on an item without one; '' none
    Widths: TArray<TLevelWidth>;   // per level: the top, a first submenu, ...; the last for every deeper one
    States: TStates;          // the states a rule takes when it does not say
    TextSize: Single;         // the menu's size, 1 as drawn; Ctrl+scroll in the menu changes it (plan 02 3.4)
    ThemeLight, ThemeDark: string;   // the themes for Windows' light and dark mode (plan 03 3.3)
    Submenus: TSubmenuMode;   // smNext, smUnder or smReplace
    OnClickOnly: Boolean;     // submenus open only on a click, never on hover
  end;

  TCard = class
  public
    Id: string;            // "id", or made up (c1, c2, ...) when the layout has none
    Title: string;         // "card": its name in the editor, and its title when it holds several items
    ShownTitle: string;    // "title": its title also when it holds one item ('' : the item's own text)
    Icon: string;          // "icon": a glyph's code point in hex ("E8C8") or an icon in a file ("path,index"); '' none
    Own: string;           // "own": Dexmenu's own item placed here, "windowsMenu" or "editMenu" (plan 02 3.6); '' none
    RenameFrom, RenameTo: string;   // "rename": { "regex": ..., "replace": ... } on the item's text
    Parent: TCard;         // the card with a menu it sits in; nil at the top
    Hidden: Boolean;       // "hidden": shows nothing; its rules still take their items, so they show nowhere
    // "hint": shown on hover in place of the item's own hint: a text, or { "regex", "replace" } on the item's own hint
    // (so it can be added to). "comment" is the editor's only.
    HintText: string;
    HintFrom, HintTo: string;
    HintIsRegex: Boolean;
    // "skipDuplicates": of the items its rules found, one per name (Windows 11 shows some programs' items twice: a
    // newer and an older copy); the others are taken all the same, so they show nowhere
    SkipDuplicates: Boolean;
    // A note card ({ "note": "<text>" }, plan 02 3.3): no button, no rules or menu; an empty space or a text of
    // several lines
    IsNote: Boolean;
    NoteText: string;
    NoteAlign: TNoteAlign;   // "align": left (default), text (with the items' text), center, right
    SubmenuMode: TSubmenuMode;   // "submenus": how what opens from this card opens; smDefault: the global setting
    // Its size on a line (plan 03 3.5): "weight", its share of the line's width (1 when not set); "minWidth" (DIP; 0
    // none); "height", in lines of text (0: auto, from its content); "cardFit", how it fits a taller line.
    Weight: Single;
    MinWidth: Single;
    Height: Single;
    CardFit: TCardFit;
    // "wrap": its title wraps over more lines: within its "height" when set (the last line cut with "..."), else the
    // card as high as the lines it needs (plan 03 3.5)
    Wrap: Boolean;
    // "extra": a smaller text with the title, above it ("extraAt": "above") or below it (plan 03 3.6); '' none
    Extra: string;
    ExtraAbove: Boolean;
    // Its own look over the theme's (plan 03 3.6): "background", "foreground", "border", "borderWidth", "radius", and
    // the same per state in "hover" / "pressed"; nil when it has none. Owned.
    Look: TJSONObject;
    // "buttons" (format 1): what its rules found shown inside it side by side, a found submenu unfolded (plan 02 3.3);
    // read as Show csRow
    Buttons: Boolean;
    // What it shows and how (plan 11 3.1): Show; a row's "perRow" and "rows", a column's "perColumn" and "columns" (0:
    // no limit); "rest"; "shownWhen"; "titleAs": "divider" its title drawn as a divider; "square": as high as wide;
    // "templates": the cards its found items' inner cards follow (no rules, no content; owned; none: the theme's card),
    // picked as "templatesBy" says
    Show: TCardShow;
    PerRow, Rows, PerColumn, Columns: Integer;
    RestOf: TRestOf;
    ShownWhen: TShownWhen;
    TitleAsDivider: Boolean;
    Square: Boolean;
    Templates: TObjectList<TCard>;
    TemplatesBy: TTemplatesBy;
    Rules: TObjectList<TRule>;
    // the cards it holds: a format 1 card's "menu", a format 2 card's "content" (a line per card, divider or search
    // box); nil for a card with rules
    Menu: TObjectList<TLine>;
    // The template the inner card for its Position-th found item (from 0), found by Rule, follows; nil for none.
    function TemplateFor(Position: Integer; Rule: TRule): TCard;
    // How it shows its content or what it found, csDefault resolved (csItem for a card with rules)
    function Shows: TCardShow;
    constructor Create;
    destructor Destroy; override;
    function IsRemaining: Boolean;
  end;

  TDividerAlign = (daLeft, daCenter, daRight);

  // A line of cards, or a divider between lines ({ "divider": "<text>" or true, "align": "left|center|right" }): a
  // thin line, with its text where it has one. Its look comes with the themes (plan 03 3.8).
  TLine = class
  public
    Cards: TObjectList<TCard>;
    IsDivider: Boolean;
    DividerText: string;
    DividerAlign: TDividerAlign;
    IsSearchBox: Boolean;  // { "search": true }: the search box, before typing starts (plan 02 3.6)
    CardFit: TCardFit;     // "cardFit" of a line of cards: how its lower cards fit it (cfDefault: stretched)
    constructor Create;
    destructor Destroy; override;
  end;

  TLines = TObjectList<TLine>;

  ILayout = interface
    ['{6B0B6E2C-3E0B-4E8E-9C61-2D0E54D7A0A1}']
    // The layout's menu (one for every kind of right-click that uses the layout; Kind is not looked at).
    function Lines(const Kind: string): TLines;
    function Source: string;   // the file it came from, or '(built in)'
  end;

// Parses a layout; nil and Error set when it is not valid.
function ParseLayout(const Text, Source: string; out Error: string): ILayout;
// The layout a kind of right-click gets now (plan 05 3.2): settings.json's "kinds", in their order, the first that
// fits Kind and has a layout set ("dialog-file" fits "dialog-file", "file" and "default"); ToWindows when that one is
// "none" (Windows' own menu: Result nil, no error). Without "kinds" the older "layout"; without either the built-in
// base layout. DEXMENU_LAYOUT_FILE (the tests): that file for every kind. nil and Error set when the file cannot be
// used. Each file is read again when it changes.
function CurrentLayout(const Kind: string; out ToWindows: Boolean; out Error: string): ILayout;
// The global settings (settings.json "menu": { "submenus": "next" | "under" | "replace", "onClickOnly": true });
// next and on hover when not set.
function MenuSettings: TMenuSettings;
// A text size within its bounds (MinTextSize - MaxTextSize), to a tenth.
function ClampTextSize(Size: Double): Single;
// The text size kept in settings.json ("menu": { "textSize" }), the other settings left as they are.
procedure SaveTextSize(Size: Single);
// The file CurrentLayout reads for a kind, or '' for the built-in base layout or Windows' menu (ToWindows).
function LayoutFile(const Kind: string; out ToWindows: Boolean): string;

const
  MinTextSize = 0.6;   // the menu's text size (TMenuSettings.TextSize) from 60% to 250%
  MaxTextSize = 2.5;
  // the layout files' form this DLL reads (older forms are read too): 2, the menu one card holding cards (plan 11)
  FormatVersion = 2;
  BaseLayout = '// the base layout: Windows'' menu as cards'#10 +
    '{ "format": 1, "lines": [ { "line": [ { "card": "Remaining", "rules": [ "remaining" ] } ] } ] }';

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs, System.Math, Dexmenu.Json, Dexmenu.Log;

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
  Weight := 1;
end;

destructor TCard.Destroy;
begin
  Rules.Free;
  Menu.Free;
  Look.Free;
  Templates.Free;
  inherited;
end;

function TCard.TemplateFor(Position: Integer; Rule: TRule): TCard;
begin
  Result := nil;
  if (Templates = nil) or (Templates.Count = 0) then
    Exit;
  if TemplatesBy = tbRule then
  begin
    if (Rule <> nil) and (Rule.TemplateIndex >= 0) and (Rule.TemplateIndex < Templates.Count) then
      Exit(Templates[Rule.TemplateIndex]);
    Exit(Templates[0]);
  end;
  Result := Templates[Position mod Templates.Count];
end;

function TCard.Shows: TCardShow;
begin
  Result := Show;
  if Result = csDefault then
    if Menu <> nil then
      Result := csSubmenu
    else
      Result := csItem;
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

function ParseSubmenuMode(const Text: string): TSubmenuMode;
begin
  if Text = 'under' then
    Result := smUnder
  else if Text = 'replace' then
    Result := smReplace
  else if Text = 'next' then
    Result := smNext
  else
    Result := smDefault;
end;

function ParseCardFit(Value: TJSONValue): TCardFit;
begin
  Result := cfDefault;
  if not (Value is TJSONString) then
    Exit;
  if Value.Value = 'stretch' then
    Result := cfStretch
  else if Value.Value = 'top' then
    Result := cfTop
  else if Value.Value = 'center' then
    Result := cfCenter
  else if Value.Value = 'bottom' then
    Result := cfBottom;
end;

// A card's size on its line (plan 03 3.5): weight, minWidth, height, cardFit; a value out of range is ignored.
procedure ParseCardSize(Obj: TJSONObject; Card: TCard);
begin
  if (Obj.GetValue('weight') is TJSONNumber) and (TJSONNumber(Obj.GetValue('weight')).AsDouble > 0) then
    Card.Weight := TJSONNumber(Obj.GetValue('weight')).AsDouble;
  if (Obj.GetValue('minWidth') is TJSONNumber) and (TJSONNumber(Obj.GetValue('minWidth')).AsDouble > 0) then
    Card.MinWidth := TJSONNumber(Obj.GetValue('minWidth')).AsDouble;
  if (Obj.GetValue('height') is TJSONNumber) and (TJSONNumber(Obj.GetValue('height')).AsDouble > 0) then
    Card.Height := TJSONNumber(Obj.GetValue('height')).AsDouble;
  Card.CardFit := ParseCardFit(Obj.GetValue('cardFit'));
  if Obj.GetValue('wrap') is TJSONBool then
    Card.Wrap := TJSONBool(Obj.GetValue('wrap')).AsBoolean;
  if Obj.GetValue('square') is TJSONBool then
    Card.Square := TJSONBool(Obj.GetValue('square')).AsBoolean;
end;

function ParseCount(V: TJSONValue): Integer;
begin
  Result := 0;
  if (V is TJSONNumber) and (TJSONNumber(V).AsDouble >= 1) then
    Result := Trunc(TJSONNumber(V).AsDouble);
end;

// How a card shows what it found or holds, and its limits (plan 11 3.1). False with Error for an unknown "show".
function ParseShow(Obj: TJSONObject; Card: TCard; const Where: string; var Error: string): Boolean;
var
  V: TJSONValue;
begin
  Result := False;
  V := Obj.GetValue('show');
  if V is TJSONString then
    if V.Value = 'item' then Card.Show := csItem
    else if V.Value = 'submenu' then Card.Show := csSubmenu
    else if V.Value = 'row' then Card.Show := csRow
    else if V.Value = 'column' then Card.Show := csColumn
    else
    begin
      Error := Where + ' "' + Card.Title + '": "show" is item, submenu, row or column';
      Exit;
    end;
  Card.PerRow := ParseCount(Obj.GetValue('perRow'));
  Card.Rows := ParseCount(Obj.GetValue('rows'));
  Card.PerColumn := ParseCount(Obj.GetValue('perColumn'));
  Card.Columns := ParseCount(Obj.GetValue('columns'));
  Card.RestOf := roMenu;
  if (Obj.GetValue('rest') is TJSONString) and (Obj.GetValue('rest').Value = 'none') then
    Card.RestOf := roNone;
  Card.ShownWhen := swActionItem;
  if Obj.GetValue('shownWhen') is TJSONString then
    if Obj.GetValue('shownWhen').Value = 'always' then
      Card.ShownWhen := swAlways
    else if Obj.GetValue('shownWhen').Value = 'anyItem' then
      Card.ShownWhen := swAnyItem;
  Card.TitleAsDivider := (Obj.GetValue('titleAs') is TJSONString) and (Obj.GetValue('titleAs').Value = 'divider');
  Result := True;
end;

// A card's extra text and its own look (plan 03 3.6).
procedure ParseCardLook(Obj: TJSONObject; Card: TCard);
const
  Props: array[0..6] of string = ('background', 'foreground', 'border', 'borderWidth', 'radius', 'hover', 'pressed');
var
  P: string;
begin
  if Obj.GetValue('extra') is TJSONString then
    Card.Extra := Obj.GetValue('extra').Value;
  Card.ExtraAbove := (Obj.GetValue('extraAt') is TJSONString) and (Obj.GetValue('extraAt').Value = 'above');
  for P in Props do
    if Obj.GetValue(P) <> nil then
    begin
      if Card.Look = nil then
        Card.Look := TJSONObject.Create;
      Card.Look.AddPair(P, TJSONValue(Obj.GetValue(P).Clone));
    end;
end;

function ParseContent(Value: TJSONValue; const Where: string; Parent: TCard; Lines: TLines; var Error: string): Boolean; forward;

// A card's template (plan 11 3.1): what every inner card made for its found items follows: texts that apply to each
// item, its layout and its style; no rules, no content.
function ParseTemplate(Obj: TJSONObject; Holder: TCard; Index: Integer): TCard;
begin
  Result := TCard.Create;
  Result.Title := 'Template ' + IntToStr(Index + 1);
  Result.Id := Holder.Id + '.template' + IntToStr(Index + 1);
  Result.Parent := Holder;
  ParseCardSize(Obj, Result);
  ParseCardLook(Obj, Result);
  if Obj.GetValue('icon') is TJSONString then
    Result.Icon := Trim(Obj.GetValue('icon').Value);
  if (Obj.GetValue('rename') is TJSONObject) and (TJSONObject(Obj.GetValue('rename')).GetValue('regex') <> nil) then
  begin
    Result.RenameFrom := TJSONObject(Obj.GetValue('rename')).GetValue('regex').Value;
    if TJSONObject(Obj.GetValue('rename')).GetValue('replace') <> nil then
      Result.RenameTo := TJSONObject(Obj.GetValue('rename')).GetValue('replace').Value;
  end;
  if Obj.GetValue('hint') is TJSONString then
    Result.HintText := Obj.GetValue('hint').Value;
end;

function ParseCard(Value: TJSONValue; const Where: string; Parent: TCard; out Card: TCard; var Error: string): Boolean;
var
  Obj: TJSONObject;
  Rules, Menu, Content: TJSONValue;
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
  if Obj.GetValue('note') is TJSONString then
  begin
    Card := TCard.Create;
    Card.IsNote := True;
    Card.NoteText := Obj.GetValue('note').Value;
    if Obj.GetValue('align') is TJSONString then
      if Obj.GetValue('align').Value = 'text' then
        Card.NoteAlign := naText
      else if Obj.GetValue('align').Value = 'center' then
        Card.NoteAlign := naCenter
      else if Obj.GetValue('align').Value = 'right' then
        Card.NoteAlign := naRight;
    Card.Parent := Parent;
    ParseCardSize(Obj, Card);
    Inc(NextCardId);
    if Obj.GetValue('id') is TJSONString then
      Card.Id := Obj.GetValue('id').Value
    else
      Card.Id := 'c' + IntToStr(NextCardId);
    Exit(True);
  end;
  if not (Obj.GetValue('card') is TJSONString) then
  begin
    Error := Where + ': a card needs "card" (its title)';
    Exit;
  end;
  Card := TCard.Create;
  try
    Card.Title := Obj.GetValue('card').Value;
    Card.Parent := Parent;
    ParseCardSize(Obj, Card);
    ParseCardLook(Obj, Card);
    Inc(NextCardId);
    if Obj.GetValue('id') is TJSONString then
      Card.Id := Obj.GetValue('id').Value
    else
      Card.Id := 'c' + IntToStr(NextCardId);
    if Obj.GetValue('title') is TJSONString then
      Card.ShownTitle := Obj.GetValue('title').Value;
    if Obj.GetValue('icon') is TJSONString then
      Card.Icon := Trim(Obj.GetValue('icon').Value);
    if Obj.GetValue('hint') is TJSONString then
      Card.HintText := Obj.GetValue('hint').Value
    else if (Obj.GetValue('hint') is TJSONObject) and (TJSONObject(Obj.GetValue('hint')).GetValue('regex') <> nil) then
    begin
      Card.HintIsRegex := True;
      Card.HintFrom := TJSONObject(Obj.GetValue('hint')).GetValue('regex').Value;
      if TJSONObject(Obj.GetValue('hint')).GetValue('replace') <> nil then
        Card.HintTo := TJSONObject(Obj.GetValue('hint')).GetValue('replace').Value;
    end;
    if Obj.GetValue('submenus') is TJSONString then
      Card.SubmenuMode := ParseSubmenuMode(Obj.GetValue('submenus').Value);
    if Obj.GetValue('skipDuplicates') is TJSONBool then
      Card.SkipDuplicates := TJSONBool(Obj.GetValue('skipDuplicates')).AsBoolean;
    if Obj.GetValue('buttons') is TJSONBool then
      Card.Buttons := TJSONBool(Obj.GetValue('buttons')).AsBoolean;
    if not ParseShow(Obj, Card, Where, Error) then
      Exit;
    if Card.Buttons and (Card.Show = csDefault) then
      Card.Show := csRow;   // format 1's buttons: found items side by side inside it
    if Obj.GetValue('templates') is TJSONArray then
    begin
      Card.Templates := TObjectList<TCard>.Create;
      for Item in TJSONArray(Obj.GetValue('templates')) do
        if Item is TJSONObject then
          Card.Templates.Add(ParseTemplate(TJSONObject(Item), Card, Card.Templates.Count));
    end;
    Card.TemplatesBy := tbPosition;
    if (Obj.GetValue('templatesBy') is TJSONString) and (Obj.GetValue('templatesBy').Value = 'rule') then
      Card.TemplatesBy := tbRule;
    if Obj.GetValue('hidden') is TJSONBool then
      Card.Hidden := TJSONBool(Obj.GetValue('hidden')).AsBoolean;   // not for the remaining card (Dexmenu.Place)
    if (Obj.GetValue('rename') is TJSONObject) and (TJSONObject(Obj.GetValue('rename')).GetValue('regex') <> nil) then
    begin
      Card.RenameFrom := TJSONObject(Obj.GetValue('rename')).GetValue('regex').Value;
      if TJSONObject(Obj.GetValue('rename')).GetValue('replace') <> nil then
        Card.RenameTo := TJSONObject(Obj.GetValue('rename')).GetValue('replace').Value;
    end;
    if Obj.GetValue('own') is TJSONString then
    begin
      // Dexmenu's own item as a card of its own (earlier layouts): read as a card with one rule finding that item,
      // titled with the card's name (docs/plans/executed/12-PLAN-own-rules.md 3.3)
      if (Obj.GetValue('own').Value <> 'windowsMenu') and (Obj.GetValue('own').Value <> 'editMenu') then
      begin
        Error := Where + ' "' + Card.Title + '": "own" is "windowsMenu" or "editMenu"';
        Exit;
      end;
      Rule := TRule.Create;
      Rule.Card := Card;
      Rule.Index := 0;
      Card.Rules.Add(Rule);
      Rule.Kind := rkMatch;
      Rule.Raw := TJSONObject.Create;
      Rule.Raw.AddPair('own', Obj.GetValue('own').Value);
      Rule.Spec := ParseRule(Rule.Raw);
      if Card.ShownTitle = '' then
        Card.ShownTitle := Card.Title;
      Exit(True);
    end;
    Rules := Obj.GetValue('rules');
    Menu := Obj.GetValue('menu');
    Content := Obj.GetValue('content');
    if Ord(Rules <> nil) + Ord(Menu <> nil) + Ord(Content <> nil) > 1 then
    begin
      Error := Where + ' "' + Card.Title + '": a card has either rules or what it holds, not both';
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
          Rule.TemplateIndex := -1;
          if (Rule.Raw.GetValue('template') is TJSONNumber) and (TJSONNumber(Rule.Raw.GetValue('template')).AsInt >= 1) then
            Rule.TemplateIndex := TJSONNumber(Rule.Raw.GetValue('template')).AsInt - 1;
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
    if Content <> nil then
    begin
      // format 2: the cards it holds, under each other unless it says otherwise
      if Card.Show = csDefault then
        Card.Show := csColumn;
      Card.Menu := TLines.Create;
      if not ParseContent(Content, Where + ' > ' + Card.Title, Card, Card.Menu, Error) then
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
  Made: TJSONValue;
  I: Integer;
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
    if TJSONObject(Entry).GetValue('divider') <> nil then
    begin
      Line := TLine.Create;
      Lines.Add(Line);
      Line.IsDivider := True;
      if TJSONObject(Entry).GetValue('divider') is TJSONString then
        Line.DividerText := TJSONObject(Entry).GetValue('divider').Value;
      Line.DividerAlign := daLeft;
      if TJSONObject(Entry).GetValue('align') is TJSONString then
        if TJSONObject(Entry).GetValue('align').Value = 'center' then
          Line.DividerAlign := daCenter
        else if TJSONObject(Entry).GetValue('align').Value = 'right' then
          Line.DividerAlign := daRight;
      Continue;
    end;
    if TJSONObject(Entry).GetValue('search') is TJSONTrue then
    begin
      Line := TLine.Create;
      Lines.Add(Line);
      Line.IsSearchBox := True;
      Continue;
    end;
    if TJSONObject(Entry).GetValue('mostUsed') is TJSONTrue then
    begin
      // the most used row of earlier layouts: read as what replaced it, three cards side by side, each with a used
      // rule (docs/plans/executed/09-PLAN-used-rules.md 6.5)
      Line := TLine.Create;
      Lines.Add(Line);
      for I := 1 to 3 do
      begin
        Made := TJSONObject.ParseJSONValue(Format('{ "card": "Most used %d", "rules": [ { "used": "most", "rank": %d, ' +
          '"states": [ "enabled" ], "also": true, "consume": false } ] }', [I, I]));
        try
          if not ParseCard(Made, Where, Parent, Card, Error) then
            Exit;
          Line.Cards.Add(Card);
        finally
          Made.Free;
        end;
      end;
      Continue;
    end;
    LineCards := TJSONObject(Entry).GetValue('line');
    if LineCards = nil then
      Continue;   // other kinds of line (row, ...) come with later steps
    if not (LineCards is TJSONArray) then
    begin
      Error := Where + ': "line" must be a list of cards';
      Exit;
    end;
    Line := TLine.Create;
    Lines.Add(Line);
    Line.CardFit := ParseCardFit(TJSONObject(Entry).GetValue('cardFit'));
    for CardValue in TJSONArray(LineCards) do
    begin
      if not ParseCard(CardValue, Where, Parent, Card, Error) then
        Exit;
      Line.Cards.Add(Card);
    end;
  end;
  Result := True;
end;

// Format 2's content (plan 11 3.1): cards, dividers and the search box, each a line of its own (a card holding cards
// side by side is a card with "show": "row").
function ParseContent(Value: TJSONValue; const Where: string; Parent: TCard; Lines: TLines; var Error: string): Boolean;
var
  Entry: TJSONValue;
  Line: TLine;
  Card: TCard;
  One: TJSONArray;
begin
  Result := False;
  if not (Value is TJSONArray) then
  begin
    Error := Where + ': "content" must be a list';
    Exit;
  end;
  for Entry in TJSONArray(Value) do
  begin
    if not (Entry is TJSONObject) then
    begin
      Error := Where + ': an entry of "content" must be an object';
      Exit;
    end;
    if (TJSONObject(Entry).GetValue('divider') <> nil) or (TJSONObject(Entry).GetValue('search') <> nil) then
    begin
      // a divider or the search box: as format 1 reads them
      One := TJSONArray.Create(TJSONValue(Entry.Clone));
      try
        if not ParseLines(One, Where, Parent, Lines, Error) then
          Exit;
      finally
        One.Free;
      end;
      Continue;
    end;
    if not ParseCard(Entry, Where, Parent, Card, Error) then
      Exit;
    Line := TLine.Create;
    Lines.Add(Line);
    Line.Cards.Add(Card);
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
  Root, Menu: TJSONValue;
  Layout: TLayout;
  Lines: TLines;
  N, Version: Integer;
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
      Error := Source + ': the layout must be an object';
      Exit;
    end;
    NextCardId := 0;
    Version := 0;
    if TJSONObject(Root).GetValue('format') is TJSONNumber then
      Version := TJSONNumber(TJSONObject(Root).GetValue('format')).AsInt;
    if Version > FormatVersion then
    begin
      Error := Format('%s: a newer form of layout (format %d; this Dexmenu knows %d)', [Source, Version, FormatVersion]);
      Exit;
    end;
    if Version >= 2 then
    begin
      // the menu one card holding the others (plan 11 3.1): its content are the menu's lines
      Menu := TJSONObject(Root).GetValue('menu');
      if not (Menu is TJSONObject) or (TJSONObject(Menu).GetValue('content') = nil) then
      begin
        Error := Source + ': "menu" with its "content" is missing';
        Exit;
      end;
      Lines := TLines.Create;
      Layout.FKinds.Add('default', Lines);
      if not ParseContent(TJSONObject(Menu).GetValue('content'), Source, nil, Lines, Error) then
        Exit;
    end
    else
    begin
      if Version >= 1 then
        Menu := TJSONObject(Root).GetValue('lines')
      else
        Menu := TJSONObject(Root).GetValue('default');   // the older form: its "default" section, the others ignored
      if Menu = nil then
      begin
        if Version >= 1 then
          Error := Source + ': "lines" is missing'
        else
          Error := Source + ': the kind "default" is missing';
        Exit;
      end;
      Lines := TLines.Create;
      Layout.FKinds.Add('default', Lines);
      if not ParseLines(Menu, Source, nil, Lines, Error) then
        Exit;
    end;
    N := CountRemaining(Lines);
    if N <> 1 then
    begin
      Error := Format('%s: exactly one remaining card needed, found %d', [Source, N]);
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

type
  TCached = class
    Stamp: TFileTime;
    Layout: ILayout;
    Error: string;
  end;

var
  Lock: TCriticalSection;
  Cache: TObjectDictionary<string, TCached>;   // per layout file, read again when it changes
  Base: ILayout;

function ClampTextSize(Size: Double): Single;
begin
  Result := Max(MinTextSize, Min(MaxTextSize, Round(Size * 10) / 10));
end;

procedure SaveTextSize(Size: Single);
var
  Path, Text, Error: string;
  Settings: TJSONValue;
  Menu: TJSONValue;
  Lines: TStringList;
begin
  Path := DataFolder + '\settings.json';
  Settings := nil;
  try
    if ReadTextFile(Path, Text) then
      Settings := ParseWithComments(Text, Error);
    if not (Settings is TJSONObject) then
    begin
      if FileExists(Path) then
      begin
        Log('text size not saved: settings.json cannot be read: ' + Error);
        Exit;
      end;
      FreeAndNil(Settings);
      Settings := TJSONObject.Create;
    end;
    Menu := TJSONObject(Settings).GetValue('menu');
    if not (Menu is TJSONObject) then
    begin
      TJSONObject(Settings).RemovePair('menu').Free;
      Menu := TJSONObject.Create;
      TJSONObject(Settings).AddPair('menu', TJSONObject(Menu));
    end;
    TJSONObject(Menu).RemovePair('textSize').Free;
    TJSONObject(Menu).AddPair('textSize', TJSONNumber.Create(ClampTextSize(Size)));
    ForceDirectories(DataFolder);
    Lines := TStringList.Create;
    try
      Lines.Text := Settings.Format(2);
      Lines.SaveToFile(Path + '.tmp', TEncoding.UTF8);
    finally
      Lines.Free;
    end;
    MoveFileEx(PChar(Path + '.tmp'), PChar(Path), MOVEFILE_REPLACE_EXISTING);
  except
    on E: Exception do
      Log('text size not saved: ' + E.Message);
  end;
  Settings.Free;
end;

function MenuSettings: TMenuSettings;
var
  Text, Error: string;
  Settings, Menu, W: TJSONValue;
  Width: TLevelWidth;
begin
  Result.Submenus := smNext;
  Result.OnClickOnly := False;
  Result.SubmenuMark := '';
  Result.ActionMark := '';
  Result.Widths := nil;
  Result.TextSize := 1;
  Result.ThemeLight := 'light';
  Result.ThemeDark := 'dark';
  Result.States := [stEnabled, stDisabled];
  if not ReadTextFile(DataFolder + '\settings.json', Text) then
    Exit;
  Settings := ParseWithComments(Text, Error);
  try
    if not (Settings is TJSONObject) then
      Exit;
    Menu := TJSONObject(Settings).GetValue('menu');
    if not (Menu is TJSONObject) then
      Exit;
    if TJSONObject(Menu).GetValue('submenus') is TJSONString then
      Result.Submenus := ParseSubmenuMode(TJSONObject(Menu).GetValue('submenus').Value);
    if Result.Submenus = smDefault then
      Result.Submenus := smNext;
    if TJSONObject(Menu).GetValue('onClickOnly') is TJSONBool then
      Result.OnClickOnly := TJSONBool(TJSONObject(Menu).GetValue('onClickOnly')).AsBoolean;
    if (TJSONObject(Menu).GetValue('themeLight') is TJSONString) and (TJSONObject(Menu).GetValue('themeLight').Value <> '') then
      Result.ThemeLight := TJSONObject(Menu).GetValue('themeLight').Value;
    if (TJSONObject(Menu).GetValue('themeDark') is TJSONString) and (TJSONObject(Menu).GetValue('themeDark').Value <> '') then
      Result.ThemeDark := TJSONObject(Menu).GetValue('themeDark').Value;
    if TJSONObject(Menu).GetValue('textSize') is TJSONNumber then
      Result.TextSize := ClampTextSize(TJSONNumber(TJSONObject(Menu).GetValue('textSize')).AsDouble);
    if TJSONObject(Menu).GetValue('submenuMark') is TJSONString then
      Result.SubmenuMark := TJSONObject(Menu).GetValue('submenuMark').Value;
    if TJSONObject(Menu).GetValue('actionMark') is TJSONString then
      Result.ActionMark := TJSONObject(Menu).GetValue('actionMark').Value;
    if TJSONObject(Menu).GetValue('states') is TJSONString then
      if TJSONObject(Menu).GetValue('states').Value = 'enabled' then
        Result.States := [stEnabled]
      else if TJSONObject(Menu).GetValue('states').Value = 'disabled' then
        Result.States := [stDisabled];
    if TJSONObject(Menu).GetValue('widths') is TJSONArray then
      for W in TJSONArray(TJSONObject(Menu).GetValue('widths')) do
        if (W is TJSONObject) and (TJSONObject(W).GetValue('min') is TJSONNumber) and (TJSONObject(W).GetValue('max') is TJSONNumber) then
        begin
          Width.MinW := Max(100, TJSONNumber(TJSONObject(W).GetValue('min')).AsDouble);
          Width.MaxW := Max(Width.MinW, TJSONNumber(TJSONObject(W).GetValue('max')).AsDouble);
          Result.Widths := Result.Widths + [Width];
        end;
  finally
    Settings.Free;
  end;
end;

// Whether a kind set in settings.json fits a right-click's kind: itself, the same kind outside a dialog, or default.
function Fits(const SetKind, Kind: string): Boolean;
begin
  Result := SameText(SetKind, Kind) or SameText(SetKind, 'default') or
    (Kind.StartsWith('dialog-') and SameText(SetKind, Copy(Kind, Length('dialog-') + 1, MaxInt)));
end;

function LayoutFile(const Kind: string; out ToWindows: Boolean): string;
var
  Env: array[0..MAX_PATH] of Char;
  Text, Error, Name: string;
  Settings, Kinds, Entry: TJSONValue;
begin
  ToWindows := False;
  if GetEnvironmentVariable('DEXMENU_LAYOUT_FILE', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := '';
  if not ReadTextFile(DataFolder + '\settings.json', Text) then
    Exit;
  Settings := ParseWithComments(Text, Error);
  try
    if not (Settings is TJSONObject) then
      Exit;
    Kinds := TJSONObject(Settings).GetValue('kinds');
    if Kinds is TJSONArray then
    begin
      for Entry in TJSONArray(Kinds) do
      begin
        // not set (no layout): the next kind that fits decides
        if not (Entry is TJSONObject) or not (TJSONObject(Entry).GetValue('kind') is TJSONString) or
          not (TJSONObject(Entry).GetValue('layout') is TJSONString) then
          Continue;
        if not Fits(TJSONObject(Entry).GetValue('kind').Value, Kind) then
          Continue;
        Name := TJSONObject(Entry).GetValue('layout').Value;
        if Name = '' then
          Continue;
        if SameText(Name, 'none') then
        begin
          ToWindows := True;
          Exit;
        end;
        Exit(DataFolder + '\layouts\' + Name + '.json');
      end;
      Exit;   // none fits: the built-in base layout
    end;
    // the older setting: one layout for every kind
    if TJSONObject(Settings).GetValue('layout') is TJSONString then
    begin
      Name := TJSONObject(Settings).GetValue('layout').Value;
      if Name <> '' then
        Result := DataFolder + '\layouts\' + Name + '.json';
    end;
  finally
    Settings.Free;
  end;
end;

// A layout the DLL cannot use for a newer format (plan 05 3.1.1): a note saying so, then the remaining card.
function WarningLayout(const Path: string): ILayout; forward;

function CurrentLayout(const Kind: string; out ToWindows: Boolean; out Error: string): ILayout;
var
  States: TStates;
  Path, Text: string;
  Data: TWin32FileAttributeData;
  C: TCached;
begin
  Error := '';
  Result := nil;
  Path := LayoutFile(Kind, ToWindows);
  if ToWindows then
    Exit;
  States := MenuSettings.States;
  Lock.Enter;
  try
    // a rule's default states changed (the global settings): every layout read again
    if States <> DefaultStates then
    begin
      DefaultStates := States;
      Cache.Clear;
      Base := nil;
    end;
    if (Path = '') or not GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Data) then
    begin
      if Base = nil then
        Base := ParseLayout(BaseLayout, '(built in)', Error);
      Exit(Base);
    end;
    if not Cache.TryGetValue(AnsiLowerCase(Path), C) then
    begin
      C := TCached.Create;
      C.Error := '(not read)';
      Cache.Add(AnsiLowerCase(Path), C);
    end;
    if (C.Error = '(not read)') or (CompareFileTime(Data.ftLastWriteTime, C.Stamp) <> 0) then
    begin
      C.Stamp := Data.ftLastWriteTime;
      C.Layout := nil;
      C.Error := '';
      if not ReadTextFile(Path, Text) then
        C.Error := Path + ': cannot be read'
      else
        C.Layout := ParseLayout(Text, Path, C.Error);
      if C.Layout = nil then
        Log('layout not used: ' + C.Error);
      if (C.Layout = nil) and (Pos('a newer form', C.Error) > 0) then
        C.Layout := WarningLayout(Path);   // plan 05 3.1.1: say so, and every item as a card
    end;
    Error := C.Error;
    if C.Layout <> nil then
      Error := '';
    Result := C.Layout;
  finally
    Lock.Leave;
  end;
end;

function WarningLayout(const Path: string): ILayout;
var
  Root, Note, Rest: TJSONObject;
  Lines, Line1, Line2, Rules: TJSONArray;
  Error: string;
begin
  // { "format": 1, "lines": [ { "line": [ { "note": "..." } ] }, { "line": [ { "card": "Remaining", ... } ] } ] }
  Root := TJSONObject.Create;
  try
    Note := TJSONObject.Create;
    Note.AddPair('note', 'Layout ' + ChangeFileExt(ExtractFileName(Path), '') +
      ' needs updating: open it in Dexmenu''s editor (it was saved by a newer Dexmenu).');
    Rules := TJSONArray.Create;
    Rules.Add('remaining');
    Rest := TJSONObject.Create;
    Rest.AddPair('card', 'Remaining');
    Rest.AddPair('rules', Rules);
    Line1 := TJSONArray.Create;
    Line1.AddElement(Note);
    Line2 := TJSONArray.Create;
    Line2.AddElement(Rest);
    Lines := TJSONArray.Create;
    Lines.AddElement(TJSONObject.Create(TJSONPair.Create('line', Line1)));
    Lines.AddElement(TJSONObject.Create(TJSONPair.Create('line', Line2)));
    Root.AddPair('format', TJSONNumber.Create(1));   // written in format 1's form (lines)
    Root.AddPair('lines', Lines);
    Result := ParseLayout(Root.ToJSON, Path + ' (needs updating)', Error);
  finally
    Root.Free;
  end;
end;

initialization
  Lock := TCriticalSection.Create;
  Cache := TObjectDictionary<string, TCached>.Create([doOwnsValues]);

end.
