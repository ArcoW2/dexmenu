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
  // vkGroup: a card showing what it found as buttons inside it (Buttons; plan 02 3.3), itself no button
  TViewKind = (vkItem, vkMenu, vkSeparator, vkNote, vkBack, vkCommand, vkSearch, vkGroup);
  TCommand = (ccNone, ccWindowsMenu, ccEditMenu);

  TFound = record
    Node: TNode;
    Rule: TRule;
  end;

  TViewCard = class
  public
    Kind: TViewKind;
    Node: TNode;        // vkItem, vkSeparator: Windows' item (not owned)
    Card: TCard;        // the layout's card: that placed the item (vkItem), with the menu (vkMenu)
    Rule: TRule;        // vkItem: the rule that found it; nil for the remaining card's items
    Several: Boolean;   // vkItem: one of several items its card found (the card's title is not its)
    EmptyMenu: Boolean; // vkMenu: its menu shows nothing here (the preview only; a right-click leaves it out)
    Divider: TLine;     // vkSeparator from the layout (a divider, its text and alignment); nil for Windows' separators
    BackTitle: string;  // vkBack: "<<" and what it goes back from; vkCommand, vkSearch, vkGroup: its text
    Buttons: TObjectList<TViewCard>;   // vkGroup: its buttons, in their order (owned)
    InGroup: Boolean;   // a button in a vkGroup card: the theme's look, not its card's
    ShownText: string;  // vkItem: a title in place of its own (a search hit: with its path); '' none
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
    destructor Destroy; override;
  end;

  TViewLine = class
  public
    Cards: TObjectList<TViewCard>;
    CardFit: TCardFit;   // the layout line's: how its lower cards fit it (plan 03 3.5)
    constructor Create;
    destructor Destroy; override;
  end;

  TViewLevel = class
  public
    Lines: TObjectList<TViewLine>;
    constructor Create;
    destructor Destroy; override;
    function CardCount: Integer;
  end;

  TPlacement = class
  private
    FDirect: TDictionary<string, Boolean>;   // keys of items a rule took directly
    FTaken: TDictionary<string, Boolean>;    // keys of items taken (directly, or with an item above them)
    FFound: TObjectDictionary<TCard, TList<TFound>>;
    procedure Evaluate;
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
    // The use counts of this kind (Dexmenu.Usage; not owned, may be nil) and how many the most used row shows.
    Usage: TDictionary<string, Integer>;
    MostUsedCount: Integer;
    function Hides(Node: TNode): Boolean;
    constructor Create(const ALayout: ILayout; const AKind: string; ATop: TNodes);
    destructor Destroy; override;
    function TopLevel: TViewLevel;
    function MenuLevel(Card: TCard): TViewLevel;
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
// Whether a kind's layout has a most used row (plan 02 3.9), at any level.
function HasMostUsed(const Layout: ILayout; const Kind: string): Boolean;
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
  Dexmenu.Usage;

function TPlacement.Hides(Node: TNode): Boolean;
begin
  Result := (Empty <> nil) and (Node.SubMenu <> 0) and Empty.ContainsKey(Node.SubMenu);
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
  Buttons.Free;
  inherited;
end;

function TViewCard.LookCard: TCard;
begin
  Result := nil;
  if (Card <> nil) and not InGroup and ((Kind in [vkMenu, vkCommand, vkNote, vkGroup]) or
    ((Kind = vkItem) and not Card.IsRemaining)) then
    Result := Card;
end;

function TViewCard.IconSpec: string;
begin
  Result := '';
  if (Card = nil) or InGroup then
    Exit;
  if (Kind in [vkMenu, vkCommand]) or ((Kind = vkItem) and not Card.IsRemaining) then
    Result := Card.Icon;
end;

function TViewCard.Title: string;
begin
  case Kind of
    vkItem:
      begin
        if ShownText <> '' then
          Exit(ShownText);
        if (Card <> nil) and (Card.ShownTitle <> '') and not Card.IsRemaining and not Several then
          Exit(Card.ShownTitle);
        Result := Node.Name;
        if (Card <> nil) and (Card.RenameFrom <> '') then
          try
            Result := TRegEx.Replace(Result, Card.RenameFrom, Card.RenameTo);
          except
            // a rename that does not compile: the item's own text
          end;
      end;
    vkNote: Result := Card.NoteText;
    vkBack, vkCommand, vkSearch, vkGroup: Result := BackTitle;
    vkMenu:
      if Card.ShownTitle <> '' then
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
  Result := ((Kind = vkItem) and Node.Sometimes) or ((Kind = vkMenu) and EmptyMenu);
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
  inherited Create;
  Layout := ALayout;
  Kind := AKind;
  Top := ATop;
  MostUsedCount := 3;
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
      Result := TRegEx.Replace(Regular, V.Card.HintFrom, V.Card.HintTo);
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
          if Card.Buttons or HasButtons(Card.Menu) then
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
      if R.Spec.Scope <> scTop then
        Exit(True);
  finally
    Rules.Free;
  end;
end;

function HasMostUsed(const Layout: ILayout; const Kind: string): Boolean;

  function Look(Lines: TLines): Boolean;
  var
    Line: TLine;
    Card: TCard;
  begin
    Result := False;
    if Lines <> nil then
      for Line in Lines do
      begin
        if Line.IsMostUsed then
          Exit(True);
        for Card in Line.Cards do
          if Look(Card.Menu) then
            Exit(True);
      end;
  end;

begin
  Result := Look(Layout.Lines(Kind));
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

  procedure Visit(Nodes: TNodes; R: TRule; Names: TDictionary<string, Boolean>);
  var
    N: TNode;
    List: TList<TFound>;
    F: TFound;
    Twice: Boolean;
  begin
    for N in Nodes do
    begin
      if Accepts(R, N) and (not FTaken.ContainsKey(KeyOf(N)) or R.Spec.Also) then
      begin
        if not FFound.TryGetValue(R.Card, List) then
        begin
          List := TList<TFound>.Create;
          FFound.Add(R.Card, List);
        end;
        // a second item of a name this rule (skipDuplicates) or its card (skipDuplicates) already has: taken, not shown
        Twice := R.Spec.SkipDuplicates and Names.ContainsKey(AnsiLowerCase(N.Name));
        if not Twice and R.Card.SkipDuplicates then
          for F in List do
            if SameText(F.Node.Name, N.Name) then
              Twice := True;
        Names.AddOrSetValue(AnsiLowerCase(N.Name), True);
        Found.Node := N;
        Found.Rule := R;
        if not Twice then
          List.Add(Found);
        if R.Spec.Consume and not FTaken.ContainsKey(KeyOf(N)) then
        begin
          FTaken.AddOrSetValue(KeyOf(N), True);
          FDirect.AddOrSetValue(KeyOf(N), True);
          TakeBelow(N);   // its subitems follow it, except those taken already
        end;
      end;
      if (N.Children <> nil) and (R.Spec.Scope <> scTop) then
        Visit(N.Children, R, Names);
    end;
  end;

begin
  Rules := TList<TRule>.Create;
  Order := TDictionary<TRule, Integer>.Create;
  try
    CollectRules(Layout.Lines(Kind), Rules);
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
    begin
      Names := TDictionary<string, Boolean>.Create;
      try
        Visit(Top, R, Names);
      finally
        Names.Free;
      end;
    end;
    for I := 0 to Top.Count - 1 do
      if not FTaken.ContainsKey(KeyOf(Top[I])) or Top[I].IsSeparator then
        Remaining.Add(Top[I]);
  finally
    Order.Free;
    Rules.Free;
  end;
end;

// ---- the levels ------------------------------------------------------------------------------------------------

procedure AddMostUsed(P: TPlacement; Level: TViewLevel); forward;

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
  B: TViewCard;
  SubLine: TViewLine;
  Unfolded: TNode;
  Shown: Integer;
begin
  Result := TViewLevel.Create;
  for Line in Lines do
  begin
    Out := nil;
    if Line.IsMostUsed then
    begin
      AddMostUsed(P, Result);
      Continue;
    end;
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
          V := TViewCard.Create;
          V.Kind := vkNote;
          V.Card := Card;
        end
        else if Card.Own <> '' then
        begin
          V := TViewCard.Create;   // Dexmenu's own item, where the layout puts it
          V.Kind := vkCommand;
          V.Command := CommandOf(Card.Own);
          V.BackTitle := Card.Title;
          V.Card := Card;
        end
        else if Card.Buttons then
        begin
          // what it found as buttons inside it (plan 02 3.3): a found submenu unfolded into its items
          if not P.FFound.TryGetValue(Card, List) then
            Continue;
          V := TViewCard.Create;
          V.Kind := vkGroup;
          V.Card := Card;
          V.Buttons := TObjectList<TViewCard>.Create;
          Unfolded := nil;
          Shown := 0;
          for F in List do
          begin
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
                    V.Buttons.Add(B);
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
              V.Buttons.Add(B);
            end;
          end;
          if V.Buttons.Count = 0 then
          begin
            V.Free;
            Continue;
          end;
          if Card.ShownTitle <> '' then
            V.BackTitle := Card.ShownTitle
          else if (Shown = 1) and (Unfolded <> nil) then
            V.BackTitle := Unfolded.Name
          else
            V.BackTitle := Card.Title;
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
            if not P.Hides(F.Node) then
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

// The most used row (plan 02 3.9): the items of this menu chosen most, at any depth, side by side, most first; only
// enabled items with a submenu of their own left out; an item may also show at its own place.
procedure AddMostUsed(P: TPlacement; Level: TViewLevel);
var
  Found: TList<TPair<TNode, Integer>>;
  Keys: TDictionary<string, Boolean>;
  Line: TViewLine;
  V: TViewCard;
  I: Integer;

  procedure Walk(Nodes: TNodes);
  var
    N: TNode;
    Count: Integer;
  begin
    for N in Nodes do
    begin
      if N.IsSeparator or P.Hides(N) then
        Continue;
      if N.Children <> nil then
        Walk(N.Children);
      if (N.SubMenu = 0) and N.Enabled and (N.Name <> '') and P.Usage.TryGetValue(UsageKey(N), Count) and (Count > 0) and
        not Keys.ContainsKey(UsageKey(N)) then
      begin
        Keys.Add(UsageKey(N), True);
        Found.Add(TPair<TNode, Integer>.Create(N, Count));
      end;
    end;
  end;

begin
  if (P.Usage = nil) or (P.Usage.Count = 0) or (P.MostUsedCount <= 0) then
    Exit;
  Found := TList<TPair<TNode, Integer>>.Create;
  Keys := TDictionary<string, Boolean>.Create;
  try
    if UsageGoesDeeper(P.Usage) then
      ReadAllChildren(P.Top);   // an item chosen in a submenu: its submenu read
    Walk(P.Top);
    Found.Sort(TComparer<TPair<TNode, Integer>>.Construct(
      function(const A, B: TPair<TNode, Integer>): Integer
      begin
        Result := B.Value - A.Value;
        if Result = 0 then
          Result := CompareText(UsageKey(A.Key), UsageKey(B.Key));
      end));
    if Found.Count = 0 then
      Exit;
    Line := TViewLine.Create;
    Level.Lines.Add(Line);
    for I := 0 to Min(Found.Count, P.MostUsedCount) - 1 do
    begin
      V := TViewCard.Create;
      V.Kind := vkItem;
      V.Node := Found[I].Key;
      Line.Cards.Add(V);
    end;
  finally
    Keys.Free;
    Found.Free;
  end;
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
begin
  Result := PlaceLines(Self, Layout.Lines(Kind));
end;

function TPlacement.MenuLevel(Card: TCard): TViewLevel;
begin
  Result := PlaceLines(Self, Card.Menu);
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
