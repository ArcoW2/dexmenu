unit Dexmenu.Place;

// The layout applied to Windows' items (docs/plans/executed/02-PLAN-own-menu.md 3.3; plan 00 steps 3 and 5).
//
// Cards first: each card's rules take items; where the card stands is where its items show. The rules run in the
// priority list's order (a rule's "priority", lower first; rules without one after, in the layout's order). An item
// goes to the first rule that finds it; an item with a submenu takes its subitems along, except those an earlier rule
// took, which stay there and are left out of its submenu. A rule with "also" shows an item even when an earlier rule
// took it; a rule with "consume": false shows what it found without taking it, so later rules and the remaining card
// can show it too. "skipDuplicates" (on a rule, or on a card for all its rules) shows one item per name; the others
// are taken all the same, so they show nowhere. The remaining card takes every top-level item no rule took (Windows' separators among them) and places
// each, with its subitems, as a card of its own on its own line where it stands.
//
// A card with rules places what it found where it stands, as the remaining card does: each found item a card of its
// own on its own line, in the order found (one item: the card's title, when it has one, is the item's); found none:
// nothing. So a card with a menu holds an unknown number of found items beside cards of its own. A card with a menu
// opens its lines. A hidden card ("hidden": true) shows nothing, while its rules (and those in its menu) still take
// their items: a way to leave items out, even of the remaining card. The remaining card cannot be hidden. A Windows submenu opened from a card shows its items,
// less those a rule took directly.
//
// Items are keyed by the menu they sit in and their id, not by object: a submenu's items are read again when it opens.

interface

uses
  Winapi.Windows, System.Generics.Collections, Dexmenu.Tree, Dexmenu.Layout;

type
  // vkNote: a note card (Card), no button; vkBack: "<<" at the top of a submenu that replaced its menu (plan 02 3.7)
  // vkCommand: Dexmenu's own item at the end of the menu ("Windows' menu", "Edit menu...", plan 02 3.6, 3.11)
  // vkSearch: the search's own line ("Search: ..."), a text, nothing to choose (plan 02 3.6)
  // vkGroup: a card showing cards inside it (Inner; docs/plans/executed/11-PLAN-cards-hold-content.md): the cards it holds, or
  // inner cards for what its rules found; itself no button
  TViewKind = (vkItem, vkMenu, vkSeparator, vkNote, vkBack, vkCommand, vkSearch, vkGroup);
  TCommand = (ccNone, ccWindowsMenu, ccEditMenu);

  TFound = record
    Node: TNode;        // nil for Dexmenu's own item
    Rule: TRule;
    Own: TCommand;      // Dexmenu's own item an own rule found (plan 12), its tag; ccNone for Windows' items
  end;

  TViewLevel = class;

  TViewCard = class
  public
    Kind: TViewKind;
    Node: TNode;        // vkItem, vkSeparator: Windows' item (not owned)
    Card: TCard;        // the layout's card: that placed the item (vkItem), with the menu (vkMenu)
    Rule: TRule;        // vkItem: the rule that found it; nil for the remaining card's items
    Several: Boolean;   // vkItem: one of several items its card found (the card's title is not its)
    EmptyMenu: Boolean; // vkMenu: its menu shows nothing here (the preview only; a right-click leaves it out)
    Divider: TLine;     // vkSeparator from the layout (a divider, its text and alignment); nil for Windows' separators
    // vkSeparator standing upright between cards side by side (in a row, or between a grid's columns; plan 18 3.2,
    // 3.3): as high as its line, no text
    Vertical: Boolean;
    BackTitle: string;  // vkBack: "<<" and what it goes back from; vkCommand, vkSearch, vkGroup: its text
    Inner: TViewLevel;  // vkGroup: what shows inside it, lines of cards measured as a level's (owned)
    Framed: Boolean;    // vkGroup: its box and title drawn (a style or a title of its own, or found items inside it)
    // vkGroup with dividers as its border: its bottom divider left out, as nothing follows it or what follows has a
    // border of its own (set by Dexmenu.Draw before measuring)
    NoBottomDivider: Boolean;
    // an inner card made for an item its card (a vkGroup's, or a card showing them in a submenu) found: in the look
    // of its template (Template; nil: the theme's card), not the card's own
    InGroup: Boolean;
    Template: TCard;    // an inner card: the card's template it follows (not owned), picked by its place or rule
    // vkMenu "More": the rest of what a row or column could not hold, from MoreFrom on, as its submenu (plan 11 3.1)
    IsMore: Boolean;
    MoreFrom: Integer;
    ShownText: string;  // vkItem: a title in place of its own (a search hit: with its path); '' none
    NoteFilled: Boolean;   // vkNote: its text filled (FillNote) once, into NoteShown, so measure and draw agree
    NoteShown: string;
    Command: TCommand;  // vkCommand: which
    function Title: string;
    // The layout card's own icon ("icon") where it is this card's: a card with a menu, or the items a card places
    // (not the remaining card's: each its own); '' otherwise.
    function IconSpec: string;
    // The layout card whose look and extra text it shows (plan 03 3.6): the card itself for a card with a menu, a
    // note, Dexmenu's own item and the items a card places; nil for the remaining card's items (each its own) and
    // items without a card.
    function LookCard: TCard;
    // The access key in the title: the index (0-based) of the letter Windows' text marks with "&", when the title is
    // the item's own text; -1 otherwise.
    function AccessIndex: Integer;
    // The shortcut Windows' text gives after a tab ("Ctrl+X"); '' for none.
    function Shortcut: string;
    function Enabled: Boolean;
    function HasSubmenu: Boolean;
    function Checked: Boolean;
    function IsDefault: Boolean;
    // Not always there (TNode.Sometimes).
    function Sometimes: Boolean;
    function CardId: string;
    function RuleIndex: Integer;   // -1: none
    // The layout card whose size settings it has (weight, minWidth, height, wrap, cardFit, square): an inner card its
    // card's template, else its layout card; nil for none.
    function SizeCard: TCard;
    destructor Destroy; override;
  end;

  TViewLine = class
  public
    Cards: TObjectList<TViewCard>;
    CardFit: TCardFit;   // the layout line's: how its lower cards fit it (plan 03 3.5)
    // a line inside a card (plan 11 3.4): its cards wrap onto the next line where their content does not fit (a
    // level's top lines wrap only at their minimum widths)
    Inner: Boolean;
    // a row without a set number per row: each card as wide as its content, from the left, wrapping where they do
    // not fit (as format 1's buttons)
    Flows: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  TViewLevel = class
  public
    Lines: TObjectList<TViewLine>;
    // the top level: the layout's menu card (plan 11 3.9), whose style the menu window is drawn in (not owned); a
    // card's submenu: its "submenuStyle" (nil none: the theme's menu); nil for Windows' own submenus
    MenuCard: TCard;
    // the card whose theme the level is drawn in (docs/plans/15-PLAN-card-themes.md 3.3): a card's submenu that
    // card, a Windows submenu its opener's (set by the menu and the preview); nil the top: the main card's
    ThemeCard: TCard;
    constructor Create;
    destructor Destroy; override;
    function CardCount: Integer;
  end;

  TPlacement = class
  private
    FDirect: TDictionary<string, Boolean>;   // keys of items a rule took directly
    FTaken: TDictionary<string, Boolean>;    // keys of items taken (directly, or with an item above them)
    FFound: TObjectDictionary<TCard, TList<TFound>>;
    FEvaluated: Boolean;   // the rules have run: a submenu they emptied can be told
    procedure Evaluate;
    // Each card's found items in the order its rules and the card ask for (docs/plans/executed/17-PLAN-order.md).
    procedure SortFound;
  public
    Layout: ILayout;
    Kind: string;
    Top: TNodes;            // not owned
    Remaining: TList<TNode>;
    // Windows submenus found empty even when opened (Dexmenu.Menu, a right-click only; not owned, may be nil): their
    // items are not shown. The preview has none, so it shows them.
    Empty: TDictionary<HMENU, Boolean>;
    // A right-click (Dexmenu.Menu): a card with a menu that shows nothing is left out; else (the preview) it shows,
    // striped.
    AtRightClick: Boolean;
    // The use counts of this kind (Dexmenu.Usage; not owned, may be nil), for used rules and the cards' counts.
    Usage: TDictionary<string, Integer>;
    // The times of last use of this kind (Dexmenu.Usage; not owned, may be nil), for used rules.
    LastUse: TDictionary<string, string>;
    // The items' last-seen times by Dexmenu.Seen.HintKey (the preview's seen items; not owned, may be nil: a
    // right-click, where every item is there now), for a rule's "latest".
    SeenTimes: TDictionary<string, string>;
    // An item not shown: its Windows submenu holds nothing even when opened (Empty), or every item in it was taken by
    // a rule into another card, so it would open an empty submenu.
    function Hides(Node: TNode): Boolean;
    constructor Create(const ALayout: ILayout; const AKind: string; ATop: TNodes); overload;
    // With the use counts and times known before the rules are evaluated: used rules rank by them
    // (docs/plans/executed/09-PLAN-used-rules.md).
    constructor Create(const ALayout: ILayout; const AKind: string; ATop: TNodes; AUsage: TDictionary<string, Integer>;
      ALastUse: TDictionary<string, string>; ASeenTimes: TDictionary<string, string> = nil); overload;
    destructor Destroy; override;
    function TopLevel: TViewLevel;
    function MenuLevel(Card: TCard): TViewLevel;
    // The level a card opens (plan 11): a card with a menu its menu; a card showing what it found in a submenu those
    // items, each a line in its template's look; "More" the rest of its holder's row or column.
    function LevelOf(V: TViewCard): TViewLevel;
    function SubmenuLevel(Node: TNode): TViewLevel;
    // The search (plan 02 3.6): a line with the text, then every item of Windows' menu at any depth whose name holds
    // the text (case ignored; a leading "/" makes the rest a regex), each on a line of its own, titled with its path;
    // an item with a submenu, a hidden one and a duplicate left out.
    function SearchLevel(const Text: string): TViewLevel;
    // The stored use counts (Usage) per layout card, by its id: the sum over the items it got, each with the items in
    // its submenu; the remaining card's over the remaining items. Cards without counts left out. The caller frees it.
    function CardCounts: TDictionary<string, Integer>;
  end;

function KeyOf(Node: TNode): string;
// Whether a kind's layout has a rule that looks inside Windows submenus (scope anywhere, or a path): then a
// right-click opens the submenus an extension fills only when opened, before the rules run (Dexmenu.Menu).
function RulesLookDeeper(const Layout: ILayout; const Kind: string): Boolean;
// Whether a kind's layout uses the use counts: a used rule (docs/plans/executed/09-PLAN-used-rules.md).
function UsesUsage(const Layout: ILayout; const Kind: string): Boolean;
// The hint shown on hover over a card: its layout card's hint (a text, or a regex on the item's own hint), else the
// item's own hint (Regular: from the seen items, Dexmenu.Seen.HintsOf); '' for none.
function ShownHint(V: TViewCard; const Regular: string): string;
// How the submenu of a card opens (plan 02 3.7): its layout card's own "submenus", else the global setting.
function SubmenuModeOf(V: TViewCard; const Settings: TMenuSettings): TSubmenuMode;
// "<<" at the top of a level that replaced its menu: back to the menu it replaced.
procedure AddBackLine(Level: TViewLevel; Opener: TViewCard);

implementation

uses
  System.SysUtils, System.StrUtils, System.Math, System.RegularExpressions, System.Generics.Defaults, Dexmenu.Rules,
  Dexmenu.Usage, Dexmenu.Seen;

function TPlacement.Hides(Node: TNode): Boolean;
var
  C: TNode;
  Any: Boolean;
begin
  if (Node = nil) or (Node.SubMenu = 0) then
    Exit(False);
  if (Empty <> nil) and Empty.ContainsKey(Node.SubMenu) then
    Exit(True);
  // emptied by the rules: read, with items, none of them left to show in it (as SubmenuLevel leaves them out)
  if not FEvaluated or (Node.Children = nil) then
    Exit(False);
  Any := False;
  for C in Node.Children do
  begin
    if C.IsSeparator then
      Continue;
    Any := True;
    if not FDirect.ContainsKey(KeyOf(C)) and not Hides(C) then
      Exit(False);
  end;
  Result := Any;
end;

function SubmenuModeOf(V: TViewCard; const Settings: TMenuSettings): TSubmenuMode;
begin
  Result := Settings.Submenus;
  if (V <> nil) and (V.Card <> nil) and (V.Card.SubmenuMode <> smDefault) then
    Result := V.Card.SubmenuMode;
end;

procedure AddBackLine(Level: TViewLevel; Opener: TViewCard);
var
  Line: TViewLine;
  V: TViewCard;
begin
  V := TViewCard.Create;
  V.Kind := vkBack;
  V.BackTitle := '<<  ' + Opener.Title;
  Line := TViewLine.Create;
  Line.Cards.Add(V);
  Level.Lines.Insert(0, Line);
end;

function CommandOf(const Own: string): TCommand;
begin
  if Own = 'windowsMenu' then
    Result := ccWindowsMenu
  else if Own = 'editMenu' then
    Result := ccEditMenu
  else
    Result := ccNone;
end;

function KeyOf(Node: TNode): string;
begin
  Result := IntToHex(NativeUInt(Node.Menu), 1) + ':' + IntToStr(Node.Id);
end;

// ---- the view ------------------------------------------------------------------------------------------------------

function TViewCard.AccessIndex: Integer;
var
  T, Name: string;
  I, At: Integer;
begin
  Result := -1;
  if (Kind <> vkItem) or (Node = nil) or not Node.Item.HasText or (Title <> Node.Name) then
    Exit;
  T := Node.Item.Text;
  Name := '';
  At := -1;
  I := 1;
  while (I <= Length(T)) and (T[I] <> #9) do
  begin
    if (T[I] = '&') and (I < Length(T)) and (T[I + 1] <> '&') then
    begin
      if At < 0 then
        At := Length(Name);
      Inc(I);
      Continue;
    end;
    if T[I] = '&' then
      Inc(I);
    if I <= Length(T) then
      Name := Name + T[I];
    Inc(I);
  end;
  if At < 0 then
    Exit;
  At := At - (Length(Name) - Length(TrimLeft(Name)));   // the name is trimmed (Dexmenu.Menus.NameOf)
  if (At >= 0) and (At < Length(Title)) then
    Result := At;
end;

function TViewCard.Shortcut: string;
var
  P: Integer;
begin
  Result := '';
  if (Kind <> vkItem) or (Node = nil) or not Node.Item.HasText then
    Exit;
  P := Pos(#9, Node.Item.Text);
  if P > 0 then
    Result := Trim(Copy(Node.Item.Text, P + 1, MaxInt));
end;

destructor TViewCard.Destroy;
begin
  Inner.Free;
  inherited;
end;

function TViewCard.LookCard: TCard;
begin
  Result := nil;
  if (Card <> nil) and InGroup then
    Exit(Template);   // an inner card: its template (nil: the theme's card)
  if IsMore then
    Exit;
  if (Card <> nil) and ((Kind in [vkMenu, vkCommand, vkNote, vkGroup]) or
    ((Kind = vkItem) and not Card.IsRemaining)) then
    Result := Card;
end;

function TViewCard.SizeCard: TCard;
begin
  Result := nil;
  if (Card = nil) or (Kind = vkSeparator) or IsMore then
    Exit;
  if InGroup then
    Exit(Template);
  Result := Card;
end;

function TViewCard.IconSpec: string;

  // Dexmenu's own items: an icon of their own where the layout gives none (plan 03 3.8; Segoe Fluent Icons)
  function OwnIcon: string;
  begin
    Result := '';
    if Kind = vkCommand then
      case Command of
        ccEditMenu: Result := 'E70F';      // Edit: a pencil
        ccWindowsMenu: Result := 'E700';   // GlobalNavigationButton: a menu's three lines
      end;
  end;

begin
  Result := '';
  if (Card <> nil) and InGroup then
  begin
    if Template <> nil then
      Result := Template.Icon;
    if Result = '' then
      Result := OwnIcon;
    Exit;
  end;
  if (Card = nil) or IsMore then
    Exit;
  if (Kind in [vkMenu, vkCommand]) or ((Kind = vkItem) and not Card.IsRemaining) then
    Result := Card.Icon;
  if Result = '' then
    Result := OwnIcon;
end;

function TViewCard.Title: string;
var
  Named: TCard;
begin
  case Kind of
    vkItem:
      begin
        if ShownText <> '' then
          Exit(ShownText);
        if (Card <> nil) and (Card.ShownTitle <> '') and not Card.IsRemaining and not Several then
          Exit(Card.ShownTitle);
        Result := Node.Name;
        // the card's rename on it; an inner card its card's template's, else (no template, or one without a rename)
        // its card's own
        Named := Card;
        if InGroup and (Template <> nil) and (Template.RenameFrom <> '') then
          Named := Template;
        if (Named <> nil) and (Named.RenameFrom <> '') then
          try
            Result := RegexReplace(Result, Named.RenameFrom, Named.RenameTo);
          except
            // a rename that does not compile: the item's own text
          end;
      end;
    vkNote:
      begin
        // its placeholders filled once, when first shown (the menu opening)
        if not NoteFilled then
        begin
          NoteShown := FillNote(Card.NoteText, Now);
          NoteFilled := True;
        end;
        Result := NoteShown;
      end;
    vkCommand:
      begin
        // Dexmenu's own item: the card's title for it alone, else its own; the card's rename on it (plan 12 3.1)
        if (Card <> nil) and (Card.ShownTitle <> '') and not Several then
          Exit(Card.ShownTitle);
        Result := BackTitle;
        if (Card <> nil) and (Card.RenameFrom <> '') then
          try
            Result := RegexReplace(Result, Card.RenameFrom, Card.RenameTo);
          except
            // a rename that does not compile: its own text
          end;
      end;
    vkBack, vkSearch, vkGroup: Result := BackTitle;
    vkMenu:
      if IsMore then
        Result := BackTitle
      else if Card.ShownTitle <> '' then
        Result := Card.ShownTitle
      else
        Result := Card.Title;
  else
    Result := '';
  end;
end;

function TViewCard.Enabled: Boolean;
begin
  case Kind of
    vkItem: Result := Node.Enabled;
    vkMenu, vkBack, vkCommand: Result := True;
  else
    Result := False;
  end;
end;

function TViewCard.HasSubmenu: Boolean;
begin
  Result := (Kind = vkMenu) or ((Kind = vkItem) and (Node.SubMenu <> 0));
end;

function TViewCard.Checked: Boolean;
begin
  Result := (Kind = vkItem) and Node.Checked;
end;

function TViewCard.IsDefault: Boolean;
begin
  Result := (Kind = vkItem) and Node.IsDefault;
end;

function TViewCard.Sometimes: Boolean;
begin
  Result := ((Kind = vkItem) and Node.Sometimes) or ((Kind in [vkMenu, vkGroup]) and EmptyMenu);
end;

function TViewCard.CardId: string;
begin
  if Card = nil then
    Result := ''
  else
    Result := Card.Id;
end;

function TViewCard.RuleIndex: Integer;
begin
  if Rule = nil then
    Result := -1
  else
    Result := Rule.Index;
end;

constructor TViewLine.Create;
begin
  inherited;
  Cards := TObjectList<TViewCard>.Create;
end;

destructor TViewLine.Destroy;
begin
  Cards.Free;
  inherited;
end;

constructor TViewLevel.Create;
begin
  inherited;
  Lines := TObjectList<TViewLine>.Create;
end;

destructor TViewLevel.Destroy;
begin
  Lines.Free;
  inherited;
end;

function TViewLevel.CardCount: Integer;
var
  L: TViewLine;
begin
  Result := 0;
  for L in Lines do
    Inc(Result, L.Cards.Count);
end;

// No Windows separator at the start or the end of a level, never two separators in a row: a Windows separator next to
// another separator or a layout's divider goes. A layout's divider goes at the end of a level; one without text also
// at the start or right after another separator; one with text also when another with text follows it at once.
procedure CleanSeparators(Level: TViewLevel);
var
  I, Before: Integer;
  function IsSep(I: Integer): Boolean;
  begin
    Result := (I >= 0) and (I < Level.Lines.Count) and (Level.Lines[I].Cards.Count = 1) and
      (Level.Lines[I].Cards[0].Kind = vkSeparator);
  end;
  function IsWindows(I: Integer): Boolean;
  begin
    Result := IsSep(I) and (Level.Lines[I].Cards[0].Divider = nil);
  end;
  function IsTexted(I: Integer): Boolean;
  begin
    Result := IsSep(I) and not IsWindows(I) and (Level.Lines[I].Cards[0].Divider.DividerText <> '');
  end;
  function IsPlain(I: Integer): Boolean;
  begin
    Result := IsSep(I) and not IsWindows(I) and (Level.Lines[I].Cards[0].Divider.DividerText = '');
  end;
begin
  repeat
    Before := Level.Lines.Count;
    I := 0;
    while I < Level.Lines.Count do
      if IsWindows(I) and ((I = 0) or IsSep(I - 1) or (IsSep(I + 1) and not IsWindows(I + 1))) then
        Level.Lines.Delete(I)
      else
        Inc(I);
    while (Level.Lines.Count > 0) and IsWindows(Level.Lines.Count - 1) do
      Level.Lines.Delete(Level.Lines.Count - 1);
    I := 0;
    while I < Level.Lines.Count do
      if (IsSep(I) and (I = Level.Lines.Count - 1)) or (IsPlain(I) and ((I = 0) or IsSep(I - 1))) or
        (IsTexted(I) and IsTexted(I + 1)) then
        Level.Lines.Delete(I)
      else
        Inc(I);
  until Level.Lines.Count = Before;
end;

function NewLine(Level: TViewLevel): TViewLine;
begin
  Result := TViewLine.Create;
  Level.Lines.Add(Result);
end;

// An item of Windows' menu as a card of its own on its own line.
procedure AddNodeLine(Level: TViewLevel; Node: TNode; Card: TCard; Rule: TRule; Several: Boolean = False);
var
  V: TViewCard;
begin
  if not Node.IsSeparator and (Node.Name = '') and (Node.SubMenu = 0) then
    Exit;   // an item without text (a bitmap of its own): not shown until icons (step 7)
  V := TViewCard.Create;
  V.Node := Node;
  V.Card := Card;
  V.Rule := Rule;
  V.Several := Several;
  if Node.IsSeparator then
    V.Kind := vkSeparator
  else
    V.Kind := vkItem;
  NewLine(Level).Cards.Add(V);
end;

// ---- the rules -----------------------------------------------------------------------------------------------------

constructor TPlacement.Create(const ALayout: ILayout; const AKind: string; ATop: TNodes);
begin
  Create(ALayout, AKind, ATop, nil, nil);
end;

constructor TPlacement.Create(const ALayout: ILayout; const AKind: string; ATop: TNodes;
  AUsage: TDictionary<string, Integer>; ALastUse: TDictionary<string, string>; ASeenTimes: TDictionary<string, string>);
begin
  inherited Create;
  Usage := AUsage;
  LastUse := ALastUse;
  SeenTimes := ASeenTimes;
  Layout := ALayout;
  Kind := AKind;
  Top := ATop;
  Remaining := TList<TNode>.Create;
  FDirect := TDictionary<string, Boolean>.Create;
  FTaken := TDictionary<string, Boolean>.Create;
  FFound := TObjectDictionary<TCard, TList<TFound>>.Create([doOwnsValues]);
  Evaluate;
end;

destructor TPlacement.Destroy;
begin
  FFound.Free;
  FTaken.Free;
  FDirect.Free;
  Remaining.Free;
  inherited;
end;

procedure CollectRules(Lines: TLines; Rules: TList<TRule>);
var
  Line: TLine;
  Card: TCard;
  R: TRule;
begin
  for Line in Lines do
    for Card in Line.Cards do
    begin
      for R in Card.Rules do
        if (R.Kind = rkMatch) and R.Spec.Valid then
          Rules.Add(R);
      if Card.Menu <> nil then
        CollectRules(Card.Menu, Rules);
    end;
end;

function ShownHint(V: TViewCard; const Regular: string): string;
begin
  Result := Regular;
  if (V = nil) or (V.Card = nil) then
    Exit;
  if V.Card.HintIsRegex then
    try
      Result := RegexReplace(Regular, V.Card.HintFrom, V.Card.HintTo);
    except
      // a regex that does not compile: the item's own hint
    end
  else if V.Card.HintText <> '' then
    Result := V.Card.HintText;
end;

function RulesLookDeeper(const Layout: ILayout; const Kind: string): Boolean;
var
  Rules: TList<TRule>;
  R: TRule;

  // a card showing its items as buttons unfolds the submenus it finds (plan 02 3.3)
  function HasButtons(Lines: TLines): Boolean;
  var
    Line: TLine;
    Card: TCard;
  begin
    Result := False;
    if Lines <> nil then
      for Line in Lines do
        for Card in Line.Cards do
          if ((Card.Menu = nil) and (Card.Shows in [csRow, csColumn])) or HasButtons(Card.Menu) then
            Exit(True);
  end;

begin
  Result := HasButtons(Layout.Lines(Kind));
  if Result then
    Exit;
  Rules := TList<TRule>.Create;
  try
    CollectRules(Layout.Lines(Kind), Rules);
    for R in Rules do
      if (R.Spec.Scope <> scTop) and not R.Spec.Exclude then
        Exit(True);
  finally
    Rules.Free;
  end;
end;

function UsesUsage(const Layout: ILayout; const Kind: string): Boolean;
var
  Rules: TList<TRule>;
  R: TRule;
begin
  Result := False;
  Rules := TList<TRule>.Create;
  try
    CollectRules(Layout.Lines(Kind), Rules);
    for R in Rules do
      if R.Spec.Used <> ukNone then
        Exit(True);
  finally
    Rules.Free;
  end;
end;

// Every submenu's items read (as far as Windows' menu has them before it opens), for rules that look deeper.
procedure ReadAllChildren(Nodes: TNodes);
var
  N: TNode;
begin
  for N in Nodes do
    if (N.SubMenu <> 0) and not N.IsSeparator then
    begin
      if N.Children = nil then
        ReadChildren(N);
      ReadAllChildren(N.Children);
    end;
end;

type
  // An item a used rule ranks: its count and time of last use ('' none) read once
  TUsedItem = record
    Node: TNode;
    Count: Integer;
    Time: string;
  end;

function Accepts(R: TRule; Node: TNode): Boolean;
begin
  Result := False;
  if Node.IsSeparator or (Node.Name = '') then
    Exit;
  if Node.Enabled and not (stEnabled in R.Spec.States) then
    Exit;
  if not Node.Enabled and not (stDisabled in R.Spec.States) then
    Exit;
  case R.Spec.Scope of
    scTop: if Node.Path <> '' then Exit;
    scPath: if (Node.Path = '') or not R.Spec.Path.Test(Node.Path, R.Spec.CaseSensitive) then Exit;
  end;
  Result := R.Spec.Name.Test(Node.Name, R.Spec.CaseSensitive);
end;

procedure TPlacement.Evaluate;
var
  Names: TDictionary<string, Boolean>;
  Rules: TList<TRule>;
  Excludes: TObjectDictionary<TCard, TList<TRule>>;   // a card's exclude rules
  Order: TDictionary<TRule, Integer>;
  R: TRule;
  I: Integer;
  Found: TFound;

  procedure TakeBelow(Node: TNode);
  var
    C: TNode;
  begin
    if Node.Children <> nil then
      for C in Node.Children do
      begin
        if not FTaken.ContainsKey(KeyOf(C)) then
          FTaken.AddOrSetValue(KeyOf(C), True);
        TakeBelow(C);
      end;
  end;

  // Whether an exclude rule of R's card before R (in the card's own order of its rules, as the editor shows them)
  // accepts N: then R does not take it.
  function Excluded(R: TRule; N: TNode): Boolean;
  var
    List: TList<TRule>;
    X: TRule;
  begin
    Result := False;
    if Excludes.TryGetValue(R.Card, List) then
      for X in List do
        if (X.Index < R.Index) and Accepts(X, N) then
          Exit(True);
  end;

  // N found by R: shown in R's card (unless a duplicate, or Show False: one "latest" leaves out), taken with its
  // subitems when R consumes; one an exclude rule before R on its card accepts: neither (it stays free)
  procedure Take(N: TNode; R: TRule; Names: TDictionary<string, Boolean>; Show: Boolean = True);
  var
    List: TList<TFound>;
    F: TFound;
    Twice: Boolean;
  begin
    if Excluded(R, N) then
      Exit;
    if not FFound.TryGetValue(R.Card, List) then
    begin
      List := TList<TFound>.Create;
      FFound.Add(R.Card, List);
    end;
    // a second item of a name this rule (skipDuplicates) or its card (skipDuplicates) already has: taken, not shown
    Twice := R.Spec.SkipDuplicates and Names.ContainsKey(AnsiLowerCase(N.Name));
    if not Twice and R.Card.SkipDuplicates then
      for F in List do
        if (F.Node <> nil) and SameText(F.Node.Name, N.Name) then
          Twice := True;
    Names.AddOrSetValue(AnsiLowerCase(N.Name), True);
    Found.Node := N;
    Found.Rule := R;
    Found.Own := ccNone;
    if not Twice and Show then
      List.Add(Found);
    if R.Spec.Consume and not FTaken.ContainsKey(KeyOf(N)) then
    begin
      FTaken.AddOrSetValue(KeyOf(N), True);
      FDirect.AddOrSetValue(KeyOf(N), True);
      TakeBelow(N);   // its subitems follow it, except those taken already
    end;
  end;

  procedure Visit(Nodes: TNodes; R: TRule; Names: TDictionary<string, Boolean>);
  var
    N: TNode;
  begin
    for N in Nodes do
    begin
      if Accepts(R, N) and (not FTaken.ContainsKey(KeyOf(N)) or R.Spec.Also) then
        Take(N, R, Names);
      if (N.Children <> nil) and (R.Spec.Scope <> scTop) then
        Visit(N.Children, R, Names);
    end;
  end;

  // A rule with "latest": what it finds as Visit would, in the menu's order; only the R.Spec.Latest seen most
  // recently (SeenTimes; none, or no time: the oldest; a tie: the menu's order) shown, the others taken all the same.
  procedure VisitLatest(R: TRule; Names: TDictionary<string, Boolean>);
  var
    Found: TList<TNode>;
    Order: TList<Integer>;
    Shown: TDictionary<TNode, Boolean>;
    Times: TArray<string>;
    I: Integer;

    procedure Collect(Nodes: TNodes);
    var
      N: TNode;
    begin
      for N in Nodes do
      begin
        if Accepts(R, N) and (not FTaken.ContainsKey(KeyOf(N)) or R.Spec.Also) and not Excluded(R, N) then
          Found.Add(N);
        if (N.Children <> nil) and (R.Spec.Scope <> scTop) then
          Collect(N.Children);
      end;
    end;

  begin
    Found := TList<TNode>.Create;
    Order := TList<Integer>.Create;
    Shown := TDictionary<TNode, Boolean>.Create;
    try
      Collect(Top);
      SetLength(Times, Found.Count);
      for I := 0 to Found.Count - 1 do
      begin
        Order.Add(I);
        if (SeenTimes = nil) or not SeenTimes.TryGetValue(HintKey(Found[I]), Times[I]) then
          Times[I] := '';
      end;
      Order.Sort(TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          Result := -CompareStr(Times[A], Times[B]);
          if Result = 0 then
            Result := A - B;
        end));
      for I := 0 to Min(R.Spec.Latest, Order.Count) - 1 do
        Shown.Add(Found[Order[I]], True);
      // taken in the menu's order; one an earlier one took with its subitems stays taken
      for I := 0 to Found.Count - 1 do
        if not FTaken.ContainsKey(KeyOf(Found[I])) or R.Spec.Also then
          Take(Found[I], R, Names, Shown.ContainsKey(Found[I]));
    finally
      Shown.Free;
      Order.Free;
      Found.Free;
    end;
  end;

  // An own rule (plan 12 3.1): Dexmenu's own item, once, in the rule's card; it takes nothing of Windows'
  procedure TakeOwn(R: TRule);
  var
    List: TList<TFound>;
    F: TFound;
  begin
    if not FFound.TryGetValue(R.Card, List) then
    begin
      List := TList<TFound>.Create;
      FFound.Add(R.Card, List);
    end;
    F.Node := nil;
    F.Rule := R;
    F.Own := CommandOf(R.Spec.Own);
    List.Add(F);
  end;

  // A used rule (docs/plans/executed/09-PLAN-used-rules.md 3.1): the items of this menu with a use, at any depth, in its states,
  // ranked (most: by count, a tie by the last use; recent: by the last use, those without one after, by count); the
  // ranks counted whether or not another rule took the item, then the ranks asked for taken in their order.
  procedure TakeUsed(R: TRule; Names: TDictionary<string, Boolean>);
  var
    Used: TList<TUsedItem>;
    Keys: TDictionary<string, Boolean>;
    I, First, Last: Integer;
    Part: TRankRange;
    Recent: Boolean;

    procedure Walk(Nodes: TNodes);
    var
      N: TNode;
      Item: TUsedItem;
    begin
      for N in Nodes do
      begin
        if N.IsSeparator or Hides(N) then
          Continue;
        if N.Children <> nil then
          Walk(N.Children);
        if (N.Name = '') or Keys.ContainsKey(UsageKey(N)) or (N.Enabled and not (stEnabled in R.Spec.States)) or
          (not N.Enabled and not (stDisabled in R.Spec.States)) then
          Continue;
        Item.Node := N;
        if not Usage.TryGetValue(UsageKey(N), Item.Count) or (Item.Count <= 0) then
          Continue;
        if (LastUse = nil) or not LastUse.TryGetValue(UsageKey(N), Item.Time) then
          Item.Time := '';
        Keys.Add(UsageKey(N), True);
        Used.Add(Item);
      end;
    end;

    procedure TakeRank(Rank: Integer);
    var
      N: TNode;
    begin
      N := Used[Rank - 1].Node;
      if not FTaken.ContainsKey(KeyOf(N)) or R.Spec.Also then
        Take(N, R, Names);
    end;

  begin
    if (Usage = nil) or (Usage.Count = 0) then
      Exit;   // nothing used yet: the rule finds nothing
    Recent := R.Spec.Used = ukRecent;
    Used := TList<TUsedItem>.Create;
    Keys := TDictionary<string, Boolean>.Create;
    try
      Walk(Top);
      Used.Sort(TComparer<TUsedItem>.Construct(
        function(const A, B: TUsedItem): Integer
        begin
          if Recent then
          begin
            Result := -CompareStr(A.Time, B.Time);
            if Result = 0 then
              Result := B.Count - A.Count;
          end
          else
          begin
            Result := B.Count - A.Count;
            if Result = 0 then
              Result := -CompareStr(A.Time, B.Time);
          end;
          if Result = 0 then
            Result := CompareText(UsageKey(A.Node), UsageKey(B.Node));
        end));
      // the ranks asked for, in the order written: each range in its direction; none: all of them
      if Length(R.Spec.Ranks) = 0 then
        for I := 1 to Used.Count do
          TakeRank(I)
      else
        for Part in R.Spec.Ranks do
        begin
          First := Part.From;
          Last := Part.To_;
          if First <= Last then
          begin
            for I := First to Min(Last, Used.Count) do
              TakeRank(I);
          end
          else
            for I := Min(First, Used.Count) downto Last do
              TakeRank(I);
        end;
    finally
      Keys.Free;
      Used.Free;
    end;
  end;

begin
  Rules := TList<TRule>.Create;
  Order := TDictionary<TRule, Integer>.Create;
  Excludes := TObjectDictionary<TCard, TList<TRule>>.Create([doOwnsValues]);
  try
    CollectRules(Layout.Lines(Kind), Rules);
    // exclude rules find nothing: kept per card, out of the priority list
    for I := Rules.Count - 1 downto 0 do
      if Rules[I].Spec.Exclude then
      begin
        if not Excludes.ContainsKey(Rules[I].Card) then
          Excludes.Add(Rules[I].Card, TList<TRule>.Create);
        Excludes[Rules[I].Card].Add(Rules[I]);
        Rules.Delete(I);
      end;
    for I := 0 to Rules.Count - 1 do
      Order.Add(Rules[I], I);
    // the priority list: a rule's priority first (lower first), then the layout's order
    Rules.Sort(TComparer<TRule>.Construct(
      function(const A, B: TRule): Integer
      var
        PA, PB: Integer;
      begin
        PA := A.Spec.Priority;
        PB := B.Spec.Priority;
        if PA < 0 then PA := MaxInt;
        if PB < 0 then PB := MaxInt;
        if PA <> PB then
          Exit(PA - PB);   // both within Integer: no overflow for real priorities
        Result := Order[A] - Order[B];
      end));
    for R in Rules do
      if R.Spec.Scope <> scTop then
      begin
        ReadAllChildren(Top);
        Break;
      end;
    for R in Rules do
      if (R.Spec.Used <> ukNone) and UsageGoesDeeper(Usage) then
      begin
        ReadAllChildren(Top);   // an item used in a submenu: its submenu read
        Break;
      end;
    for R in Rules do
    begin
      Names := TDictionary<string, Boolean>.Create;
      try
        if R.Spec.Own <> '' then
          TakeOwn(R)
        else if R.Spec.Used <> ukNone then
          TakeUsed(R, Names)
        else if R.Spec.Latest > 0 then
          VisitLatest(R, Names)
        else
          Visit(Top, R, Names);
      finally
        Names.Free;
      end;
    end;
    for I := 0 to Top.Count - 1 do
      if not FTaken.ContainsKey(KeyOf(Top[I])) or Top[I].IsSeparator then
        Remaining.Add(Top[I]);
    FEvaluated := True;
    SortFound;
  finally
    Excludes.Free;
    Order.Free;
    Rules.Free;
  end;
end;

// The text a found item shows by default, for the order by name: its name with the rename it gets (TViewCard.Title):
// inside its card or in a submenu its template's (the one its rule names, else the first), else (no template, or one
// without a rename) its card's; Dexmenu's own items their own text.
function SortName(const F: TFound; Card: TCard): string;
var
  Named: TCard;
begin
  if F.Node = nil then
  begin
    if F.Own = ccWindowsMenu then
      Exit('Windows'' menu');
    Exit('Edit menu...');
  end;
  Result := F.Node.Name;
  Named := Card;
  if (Card.Menu = nil) and (Card.Shows in [csRow, csColumn, csSubmenu]) and (Card.TemplateFor(0, F.Rule) <> nil) and
    (Card.TemplateFor(0, F.Rule).RenameFrom <> '') then
    Named := Card.TemplateFor(0, F.Rule);
  if (Named <> nil) and (Named.RenameFrom <> '') then
    try
      Result := RegexReplace(Result, Named.RenameFrom, Named.RenameTo);
    except
      // a rename that does not compile: the item's own text
    end;
end;

procedure TPlacement.SortFound;
type
  TKeyed = record
    F: TFound;
    Seq: Integer;     // its place as found: ties keep it
    Count: Integer;   // its use count, 0 never used
    Time: string;     // its last use, '' never used
    Name: string;     // as shown
  end;
var
  Pair: TPair<TCard, TList<TFound>>;
  Card: TCard;
  List: TList<TFound>;
  Items: TList<TKeyed>;
  Groups: TList<TRule>;
  K: TKeyed;
  I, G: Integer;
  Part: TList<TKeyed>;

  function Keyed(const F: TFound; Seq: Integer; Card: TCard): TKeyed;
  begin
    Result.F := F;
    Result.Seq := Seq;
    Result.Count := 0;
    Result.Time := '';
    if F.Node <> nil then
    begin
      if (Usage = nil) or not Usage.TryGetValue(UsageKey(F.Node), Result.Count) then
        Result.Count := 0;
      if (LastUse = nil) or not LastUse.TryGetValue(UsageKey(F.Node), Result.Time) then
        Result.Time := '';
    end;
    Result.Name := SortName(F, Card);
  end;

  // the items sorted by Order (obFound: as they are), the whole order reversed when Descending; ties as found
  procedure SortBy(L: TList<TKeyed>; Order: TOrderBy; Descending: Boolean);
  var
    J: Integer;
  begin
    for J := 0 to L.Count - 1 do
    begin
      K := L[J];
      K.Seq := J;   // the order it has now: ties keep it
      L[J] := K;
    end;
    if Order <> obFound then
      L.Sort(TComparer<TKeyed>.Construct(
        function(const A, B: TKeyed): Integer
        begin
          case Order of
            obRecent: Result := -CompareStr(A.Time, B.Time);
            obUsed: Result := B.Count - A.Count;
          else
            Result := AnsiCompareText(A.Name, B.Name);
          end;
          if Result = 0 then
            Result := A.Seq - B.Seq;
        end));
    if Descending then
      L.Reverse;
  end;

begin
  for Pair in FFound do
  begin
    Card := Pair.Key;
    List := Pair.Value;
    if (List.Count < 2) or Card.IsRemaining then
      Continue;
    Items := TList<TKeyed>.Create;
    Groups := TList<TRule>.Create;
    Part := TList<TKeyed>.Create;
    try
      // each rule's items together, in the order the rules ran, each sorted by its rule's order
      for I := 0 to List.Count - 1 do
        if not Groups.Contains(List[I].Rule) then
          Groups.Add(List[I].Rule);
      for G := 0 to Groups.Count - 1 do
      begin
        Part.Clear;
        for I := 0 to List.Count - 1 do
          if List[I].Rule = Groups[G] then
            Part.Add(Keyed(List[I], I, Card));
        if Groups[G] <> nil then
          SortBy(Part, Groups[G].Spec.Order, Groups[G].Spec.Descending);
        Items.AddRange(Part);
      end;
      // then the card's own order over all of them
      if Card.Order <> obFound then
        SortBy(Items, Card.Order, Card.Descending);
      List.Clear;
      for K in Items do
        List.Add(K.F);
    finally
      Part.Free;
      Groups.Free;
      Items.Free;
    end;
  end;
end;

// ---- the levels ------------------------------------------------------------------------------------------------

// Dexmenu's own item an own rule found (plan 12 3.2): a card that, chosen, has the DLL start what its tag names
// (Command); its text Dexmenu's own, the card's title and rename on it (TViewCard.Title). Several: one of several the
// card found.
function OwnView(const F: TFound; Card: TCard; Several: Boolean): TViewCard;
begin
  Result := TViewCard.Create;
  Result.Kind := vkCommand;
  Result.Command := F.Own;
  if F.Own = ccWindowsMenu then
    Result.BackTitle := 'Windows'' menu'
  else
    Result.BackTitle := 'Edit menu...';
  Result.Card := Card;
  Result.Rule := F.Rule;
  Result.Several := Several;
end;

function PlaceLines(P: TPlacement; Lines: TLines): TViewLevel; forward;

// The inner cards for what a card's rules found (plan 11 3.1): each a card in the card's template's look, an own rule's
// Dexmenu item too; a found item with a submenu unfolded into its items (as format 1's buttons did), separators
// dropped. Unfolded: the item unfolded when it was the only one found, else nil. The caller owns the list and its cards.
function FoundCards(P: TPlacement; Card: TCard; out Unfolded: TNode): TObjectList<TViewCard>;
var
  List: TList<TFound>;
  F: TFound;
  B: TViewCard;
  Inner: TViewLevel;
  SubLine: TViewLine;
  Shown: Integer;
begin
  Result := TObjectList<TViewCard>.Create(False);
  Unfolded := nil;
  Shown := 0;
  if not P.FFound.TryGetValue(Card, List) then
    Exit;
  for F in List do
  begin
    if F.Node = nil then
    begin
      Inc(Shown);
      B := OwnView(F, Card, True);
      B.InGroup := True;
      Result.Add(B);
      Continue;
    end;
    if P.Hides(F.Node) or F.Node.IsSeparator then
      Continue;
    Inc(Shown);
    if F.Node.SubMenu <> 0 then
    begin
      Unfolded := F.Node;
      if F.Node.Children = nil then
        ReadChildren(F.Node);
      Inner := P.SubmenuLevel(F.Node);
      try
        for SubLine in Inner.Lines do
          while SubLine.Cards.Count > 0 do
          begin
            B := SubLine.Cards.Extract(SubLine.Cards[0]);
            if B.Kind = vkSeparator then
            begin
              B.Free;
              Continue;
            end;
            B.Card := Card;
            B.Rule := F.Rule;
            B.Several := True;
            B.InGroup := True;
            Result.Add(B);
          end;
      finally
        Inner.Free;
      end;
    end
    else if F.Node.Name <> '' then
    begin
      B := TViewCard.Create;
      B.Kind := vkItem;
      B.Node := F.Node;
      B.Card := Card;
      B.Rule := F.Rule;
      B.Several := True;
      B.InGroup := True;
      Result.Add(B);
    end;
  end;
  if Shown <> 1 then
    Unfolded := nil;
  // each its template: by its place, or by the rule that found it (plan 11 3.1)
  for Shown := 0 to Result.Count - 1 do
    Result[Shown].Template := Card.TemplateFor(Shown, Result[Shown].Rule);
end;

// The cards a card holds (its content, placed) as one list in their order, for a row or a column with limits:
// dividers, the search box and the separators placing leaves dropped. The caller owns the list and its cards.
function HeldCards(P: TPlacement; Card: TCard; KeepDividers: Boolean = False): TObjectList<TViewCard>;
var
  Level: TViewLevel;
  Line: TViewLine;
begin
  Result := TObjectList<TViewCard>.Create(False);
  Level := PlaceLines(P, Card.Menu);
  try
    // KeepDividers (Arrange): the layout's dividers kept in their place among the cards (plan 18)
    for Line in Level.Lines do
      while Line.Cards.Count > 0 do
        if (Line.Cards[0].Kind = vkSearch) or ((Line.Cards[0].Kind = vkSeparator) and
          (not KeepDividers or (Line.Cards[0].Divider = nil))) then
          Line.Cards.Delete(0)
        else
          Result.Add(Line.Cards.Extract(Line.Cards[0]));
  finally
    Level.Free;
  end;
end;

// How many of a holder's cards show at most (plan 11 3.1): a row's perRow x rows, a column's perColumn x columns;
// 0: all of them.
function Capacity(Card: TCard): Integer;
begin
  Result := 0;
  if (Card.Shows = csRow) and (Card.PerRow > 0) and (Card.Rows > 0) then
    Result := Card.PerRow * Card.Rows
  else if (Card.Shows = csColumn) and (Card.PerColumn > 0) and (Card.Columns > 0) then
    Result := Card.PerColumn * Card.Columns;
end;

// Cards arranged as a card shows them (plan 11 3.1, 3.4), into lines measured as a level's: a row perRow to a line
// (not set: one line; found items flow, each as wide as its content, wrapping where they do not fit; held cards share
// the width as a line's cards do); a column one to a line, or with perColumn a grid filled column
// by column (the columns sharing the width). Beyond the capacity: the last place a "More" card holding the rest as its
// submenu, or (rest "none") the rest left out. Takes the cards over (the list is freed, its cards owned by the level).
// A divider's view card: for each place a grid's divider is drawn (plan 18 3.3).
function DividerCopy(Of_: TLine; Vertical: Boolean): TViewCard;
begin
  Result := TViewCard.Create;
  Result.Kind := vkSeparator;
  Result.Divider := Of_;
  Result.Vertical := Vertical;
end;

// The first divider among a holder's cards (not the search box), from the layout: a grid's (plan 18 3.3). Read from
// the layout, as placing them drops a divider at the start or the end; nil none.
function FirstDivider(Card: TCard): TLine;
var
  Line: TLine;
begin
  Result := nil;
  if Card.Menu <> nil then
    for Line in Card.Menu do
      if Line.IsDivider and not Line.IsSearchBox then
        Exit(Line);
end;

function Arrange(Card: TCard; Cards: TObjectList<TViewCard>; Found: Boolean): TViewLevel;
var
  Cap, I, Per, Lines, L, J: Integer;
  More: TViewCard;
  Line, Sep: TViewLine;
  Dividers: TObjectList<TViewCard>;   // the layout's dividers among the cards, taken out (owned until placed)
  Places: TList<Integer>;             // each one's place: how many cards stood before it
  Grid: TLine;                        // a grid's divider (the first): drawn between its columns or rows
begin
  Result := TViewLevel.Create;
  Dividers := TObjectList<TViewCard>.Create(True);
  Places := TList<Integer>.Create;
  Grid := nil;
  try
    // the dividers out first: the counts, the capacity and "More" are the cards' (plan 18 3.2, 3.3)
    I := 0;
    while I < Cards.Count do
      if Cards[I].Kind = vkSeparator then
      begin
        Places.Add(I);
        Dividers.Add(Cards.Extract(Cards[I]));
      end
      else
        Inc(I);
    Cap := Capacity(Card);
    More := nil;
    if (Cap > 0) and (Cards.Count > Cap) then
    begin
      if Card.RestOf = roMenu then
      begin
        More := TViewCard.Create;   // the last place: "More", the rest as its submenu
        More.Kind := vkMenu;
        More.Card := Card;
        More.IsMore := True;
        More.MoreFrom := Cap - 1;
        More.BackTitle := 'More';
        Dec(Cap);
      end;
      for I := Cards.Count - 1 downto Cap do
        Cards[I].Free;
      Cards.Count := Cap;
      if More <> nil then
        Cards.Add(More);
    end;
    if Cards.Count = 0 then
      Exit;
    if Card.Shows = csRow then
    begin
      Per := Card.PerRow;
      if Per <= 0 then
        Per := Cards.Count;
      for I := 0 to Cards.Count - 1 do
      begin
        if I mod Per = 0 then
        begin
          Line := TViewLine.Create;
          Line.CardFit := Card.CardFit;
          Line.Inner := Found;
          Line.Flows := Found and (Card.PerRow <= 0);
          Result.Lines.Add(Line);
        end;
        Result.Lines.Last.Cards.Add(Cards[I]);
      end;
      if (Card.PerRow <= 0) and (Result.Lines.Count = 1) then
      begin
        // one row: each divider upright in its place among the cards (not before the first or after the last)
        for J := Dividers.Count - 1 downto 0 do
          if (Places[J] > 0) and (Places[J] < Result.Lines[0].Cards.Count) then
          begin
            Dividers[J].Vertical := True;
            Result.Lines[0].Cards.Insert(Places[J], Dividers.Extract(Dividers[J]));
          end;
      end
      else if FirstDivider(Card) <> nil then
      begin
        // a grid by rows: its first divider between every two rows
        Grid := FirstDivider(Card);
        for L := Result.Lines.Count - 1 downto 1 do
        begin
          Sep := TViewLine.Create;
          Sep.Cards.Add(DividerCopy(Grid, False));
          Result.Lines.Insert(L, Sep);
        end;
      end;
    end
    else
    begin
      Per := Card.PerColumn;
      if (Per <= 0) or (Per >= Cards.Count) then
        Lines := Cards.Count
      else
        Lines := Per;
      for L := 0 to Lines - 1 do
      begin
        Line := TViewLine.Create;
        Line.CardFit := Card.CardFit;
        Line.Inner := Found;
        Result.Lines.Add(Line);
      end;
      // column by column: line L holds the L-th card of each column
      for I := 0 to Cards.Count - 1 do
        Result.Lines[I mod Lines].Cards.Add(Cards[I]);
      if (Lines < Cards.Count) and (FirstDivider(Card) <> nil) then
      begin
        // a grid by columns: its first divider upright between every two columns, in each line
        Grid := FirstDivider(Card);
        for Line in Result.Lines do
          for J := Line.Cards.Count - 1 downto 1 do
            Line.Cards.Insert(J, DividerCopy(Grid, True));
      end
      else if Lines = Cards.Count then
      begin
        // one column: each divider a line of its own in its place
        for J := Dividers.Count - 1 downto 0 do
          if (Places[J] > 0) and (Places[J] < Result.Lines.Count) then
          begin
            Sep := TViewLine.Create;
            Sep.Cards.Add(Dividers.Extract(Dividers[J]));
            Result.Lines.Insert(Places[J], Sep);
          end;
      end;
    end;
  finally
    Places.Free;
    Dividers.Free;   // those not placed
    Cards.Free;
  end;
end;

// Whether what shows inside a holder lets it show (plan 11 3.3, from plan 07): an action item (something that does
// something when chosen), anything, or always. Dividers never count.
function HolderShows(Card: TCard; Level: TViewLevel): Boolean;

  function Counts(Level: TViewLevel; AnyItem: Boolean): Boolean;
  var
    Line: TViewLine;
    V: TViewCard;
  begin
    Result := False;
    for Line in Level.Lines do
      for V in Line.Cards do
        case V.Kind of
          vkItem: if V.Enabled or AnyItem then Exit(True);
          vkCommand: Exit(True);
          vkMenu: if not V.EmptyMenu or AnyItem then Exit(True);
          vkNote: if AnyItem then Exit(True);
          vkGroup: if not V.EmptyMenu and (V.Inner <> nil) and Counts(V.Inner, AnyItem) then Exit(True);
        end;
  end;

begin
  case Card.ShownWhen of
    swAlways: Result := True;
    swAnyItem: Result := Counts(Level, True);
  else
    Result := Counts(Level, False);
  end;
end;

// Whether a level holds any card, a divider or the search box not counted.
function HasCards(Level: TViewLevel): Boolean;
var
  L: TViewLine;
  V: TViewCard;
begin
  Result := False;
  for L in Level.Lines do
    for V in L.Cards do
      if not (V.Kind in [vkSeparator, vkSearch]) then
        Exit(True);
end;

// A card holding cards shown inside it (plan 11 3.1, 3.3): what it holds placed and arranged as it says; nil when it
// is not shown (by shownWhen, at a right-click; the preview shows it striped).
function HolderView(P: TPlacement; Card: TCard): TViewCard;
var
  Inner: TViewLevel;
begin
  Result := nil;
  if (Card.Shows = csColumn) and (Card.PerColumn = 0) and (Capacity(Card) = 0) then
    Inner := PlaceLines(P, Card.Menu)   // under each other as placed: its dividers kept
  else
    Inner := Arrange(Card, HeldCards(P, Card, True), False);
  // nothing in it but dividers (its cards found nothing): left out, also in the preview, as a line of such cards was
  if not HasCards(Inner) then
  begin
    Inner.Free;
    Exit;
  end;
  if not HolderShows(Card, Inner) and P.AtRightClick then
  begin
    Inner.Free;
    Exit;
  end;
  Result := TViewCard.Create;
  Result.Kind := vkGroup;
  Result.Card := Card;
  Result.Inner := Inner;
  Result.EmptyMenu := not HolderShows(Card, Inner);
  Result.Framed := (Card.Look <> nil) or (Card.ShownTitle <> '');
  Result.BackTitle := Card.ShownTitle;
end;

// What a card's rules found shown inside it as inner cards (plan 11 3.1): nil when it found nothing. Framed; its title
// above them only when it has one ("title"; its name is not shown).
function FoundView(P: TPlacement; Card: TCard): TViewCard;
var
  Cards: TObjectList<TViewCard>;
  Unfolded: TNode;
begin
  Result := nil;
  Cards := FoundCards(P, Card, Unfolded);
  if Cards.Count = 0 then
  begin
    Cards.Free;
    Exit;
  end;
  Result := TViewCard.Create;
  Result.Kind := vkGroup;
  Result.Card := Card;
  Result.Inner := Arrange(Card, Cards, True);
  Result.Framed := True;
  Result.BackTitle := Card.ShownTitle;
end;

function PlaceLines(P: TPlacement; Lines: TLines): TViewLevel;
var
  Line: TLine;
  Card: TCard;
  Out: TViewLine;
  V: TViewCard;
  N: TNode;
  F: TFound;
  List: TList<TFound>;
  Inner: TViewLevel;
  Nothing: Boolean;
  Filled: string;
begin
  Result := TViewLevel.Create;
  for Line in Lines do
  begin
    Out := nil;
    if Line.IsSearchBox then
    begin
      // the layout's search box: a line saying where typing goes; typing shows the search (SearchLevel)
      V := TViewCard.Create;
      V.Kind := vkSearch;
      V.BackTitle := 'Search...';
      NewLine(Result).Cards.Add(V);
      Continue;
    end;
    if Line.IsDivider then
    begin
      V := TViewCard.Create;
      V.Kind := vkSeparator;
      V.Divider := Line;
      NewLine(Result).Cards.Add(V);
      Continue;
    end;
    for Card in Line.Cards do
      if Card.Hidden and not Card.IsRemaining then
        Continue
      else if Card.IsRemaining then
      begin
        Out := nil;   // the remaining items each take a line of their own
        for N in P.Remaining do
          if not P.Hides(N) then
            AddNodeLine(Result, N, Card, nil);
      end
      else
      begin
        V := nil;
        if Card.IsNote then
        begin
          // its placeholders filled now (the menu opening); empty and set to hide: left out (plan 14 3.1)
          Filled := FillNote(Card.NoteText, Now);
          if Card.NoteHideEmpty and (Trim(Filled) = '') then
            Continue;
          V := TViewCard.Create;
          V.Kind := vkNote;
          V.Card := Card;
          V.NoteShown := Filled;
          V.NoteFilled := True;
        end
        else if (Card.Menu <> nil) and (Card.Shows in [csRow, csColumn]) then
        begin
          // a card holding cards inside it (plan 11 3.1, 3.3): what a line or a group was, or a card of its own look
          V := HolderView(P, Card);
          if V = nil then
            Continue;
        end
        else if (Card.Menu = nil) and (Card.Shows in [csRow, csColumn]) then
        begin
          // what its rules found as inner cards inside it (plan 11 3.1; format 1's buttons)
          V := FoundView(P, Card);
          if V = nil then
            Continue;
        end
        else if (Card.Menu = nil) and (Card.Shows = csSubmenu) then
        begin
          // what its rules found as its submenu, in its template's look
          if not P.FFound.TryGetValue(Card, List) or (List.Count = 0) then
            Continue;
          V := TViewCard.Create;
          V.Kind := vkMenu;
          V.Card := Card;
        end
        else if Card.Menu <> nil then
        begin
          Inner := PlaceLines(P, Card.Menu);   // what its menu would show: nothing, and it is not worth a card
          try
            Nothing := Inner.CardCount = 0;
          finally
            Inner.Free;
          end;
          if Nothing and P.AtRightClick then
            Continue;
          V := TViewCard.Create;
          V.Kind := vkMenu;
          V.Card := Card;
          V.EmptyMenu := Nothing;
        end
        else if P.FFound.TryGetValue(Card, List) and (List.Count = 1) and (List[0].Node = nil) then
          V := OwnView(List[0], Card, False)   // Dexmenu's own item, the card's one item
        else if P.FFound.TryGetValue(Card, List) and (List.Count = 1) and not P.Hides(List[0].Node) then
        begin
          V := TViewCard.Create;
          V.Kind := vkItem;
          V.Node := List[0].Node;
          V.Card := Card;
          V.Rule := List[0].Rule;
        end
        else if P.FFound.TryGetValue(Card, List) and (List.Count > 1) then
        begin
          Out := nil;   // several found: each takes a line of its own, as the remaining card's items
          for F in List do
            if F.Node = nil then
              NewLine(Result).Cards.Add(OwnView(F, Card, True))
            else if not P.Hides(F.Node) then
              AddNodeLine(Result, F.Node, Card, F.Rule, True);
          Continue;
        end;
        if V = nil then
          Continue;   // found nothing: not shown
        if Out = nil then
        begin
          Out := NewLine(Result);
          Out.CardFit := Line.CardFit;
        end;
        Out.Cards.Add(V);
      end;
  end;
  CleanSeparators(Result);
end;

function TPlacement.CardCounts: TDictionary<string, Integer>;
var
  Pair: TPair<TCard, TList<TFound>>;
  F: TFound;
  N: TNode;
  Sum: Integer;
  Rest: TCard;

  // an item's count with the counts of the items in its submenu
  function Total(Node: TNode): Integer;
  var
    Key: string;
    P: TPair<string, Integer>;
  begin
    Result := 0;
    Key := UsageKey(Node);
    for P in Usage do
      if (P.Key = Key) or P.Key.StartsWith(Key + ' > ') then
        Inc(Result, P.Value);
  end;

  function FindRest(Lines: TLines): TCard;
  var
    Line: TLine;
    Card: TCard;
  begin
    Result := nil;
    if Lines <> nil then
      for Line in Lines do
        for Card in Line.Cards do
        begin
          if Card.IsRemaining then
            Exit(Card);
          Result := FindRest(Card.Menu);
          if Result <> nil then
            Exit;
        end;
  end;

begin
  Result := TDictionary<string, Integer>.Create;
  if (Usage = nil) or (Usage.Count = 0) then
    Exit;
  for Pair in FFound do
  begin
    Sum := 0;
    for F in Pair.Value do
      if F.Node <> nil then
        Inc(Sum, Total(F.Node));
    if Sum > 0 then
      Result.AddOrSetValue(Pair.Key.Id, Sum);
  end;
  Rest := FindRest(Layout.Lines(Kind));
  if Rest <> nil then
  begin
    Sum := 0;
    for N in Remaining do
      Inc(Sum, Total(N));
    if Sum > 0 then
      Result.AddOrSetValue(Rest.Id, Sum);
  end;
end;

function TPlacement.SearchLevel(const Text: string): TViewLevel;
var
  Keys: TDictionary<string, Boolean>;
  Regex: TRegEx;
  IsRegex, RegexOk: Boolean;
  Hits: Integer;

  procedure AddLine(Kind: TViewKind; const Title: string; Node: TNode);
  var
    Line: TViewLine;
    V: TViewCard;
  begin
    V := TViewCard.Create;
    V.Kind := Kind;
    V.BackTitle := Title;
    V.Node := Node;
    Line := TViewLine.Create;
    Line.Cards.Add(V);
    Result.Lines.Add(Line);
  end;

  function Matches(const Name: string): Boolean;
  begin
    if IsRegex then
    begin
      Result := False;
      if RegexOk then
        try
          Result := Regex.IsMatch(Name);   // compiled on first use: a regex still being typed fails here
        except
          RegexOk := False;
        end;
    end
    else
      Result := ContainsText(Name, Text);
  end;

  procedure Walk(Nodes: TNodes);
  var
    N: TNode;
  begin
    for N in Nodes do
    begin
      if N.IsSeparator or Hides(N) then
        Continue;
      if N.Children <> nil then
        Walk(N.Children);
      if (N.SubMenu <> 0) or (N.Name = '') or Keys.ContainsKey(UsageKey(N)) or not Matches(N.Name) then
        Continue;
      Keys.Add(UsageKey(N), True);
      AddLine(vkItem, '', N);
      if N.Path <> '' then
        Result.Lines.Last.Cards[0].ShownText := N.Path + ' > ' + N.Name;
      Inc(Hits);
    end;
  end;

begin
  Result := TViewLevel.Create;
  AddLine(vkSearch, 'Search: ' + Text, nil);
  IsRegex := Text.StartsWith('/');
  RegexOk := False;
  if IsRegex then
    try
      Regex := TRegEx.Create(Copy(Text, 2, MaxInt), [roIgnoreCase]);
      RegexOk := Length(Text) > 1;
    except
      RegexOk := False;   // a regex still being typed: no hits until it is whole
    end;
  ReadAllChildren(Top);
  Hits := 0;
  Keys := TDictionary<string, Boolean>.Create;
  try
    Walk(Top);
  finally
    Keys.Free;
  end;
  if Hits = 0 then
    AddLine(vkSearch, 'No item found', nil);
end;

function TPlacement.TopLevel: TViewLevel;
var
  Root: TCard;
begin
  // the menu card (plan 11 3.9): its cards under each other as placed, or arranged as it says (side by side, or in
  // columns of a set number)
  Root := Layout.MenuCard;
  if (Root.Shows = csRow) or (Root.PerColumn > 0) or (Capacity(Root) > 0) then
    Result := Arrange(Root, HeldCards(Self, Root, True), False)
  else
    Result := PlaceLines(Self, Layout.Lines(Kind));
  Result.MenuCard := Root;
end;

function TPlacement.MenuLevel(Card: TCard): TViewLevel;
begin
  Result := PlaceLines(Self, Card.Menu);
  Result.MenuCard := Card.SubmenuStyle;   // its submenu's own style over the theme's menu, as the menu card's
  Result.ThemeCard := Card;               // and in its theme (plan 15 3.3)
end;

function TPlacement.LevelOf(V: TViewCard): TViewLevel;
var
  Cards: TObjectList<TViewCard>;
  Unfolded: TNode;
  I: Integer;
  Line: TViewLine;
begin
  if not V.IsMore and (V.Card.Menu <> nil) then
    Exit(MenuLevel(V.Card));
  // its found items (a card showing them in a submenu), or the rest of a holder's from MoreFrom on
  if V.Card.Menu <> nil then
    Cards := HeldCards(Self, V.Card)
  else
    Cards := FoundCards(Self, V.Card, Unfolded);
  Result := TViewLevel.Create;
  try
    for I := 0 to Cards.Count - 1 do
      if not V.IsMore or (I >= V.MoreFrom) then
      begin
        Line := TViewLine.Create;
        Line.Cards.Add(Cards[I]);
        Result.Lines.Add(Line);
      end
      else
        Cards[I].Free;
  finally
    Cards.Free;
  end;
  Result.MenuCard := V.Card.SubmenuStyle;   // the submenu of its found items, or a "More": its card's submenu style
  Result.ThemeCard := V.Card;                // and in its theme (plan 15 3.3)
end;

function TPlacement.SubmenuLevel(Node: TNode): TViewLevel;
var
  N: TNode;
begin
  Result := TViewLevel.Create;
  if Node.Children <> nil then
    for N in Node.Children do
      if not FDirect.ContainsKey(KeyOf(N)) and not Hides(N) then
        AddNodeLine(Result, N, nil, nil);
  CleanSeparators(Result);
end;

end.
