unit Dexmenu.Place;

// The layout applied to Windows' items (docs/plans/02-PLAN-own-menu.md 3.3; plan 00 steps 3 and 5).
//
// Cards first: each card's rules take items; where the card stands is where its items show. The rules run in the
// priority list's order (a rule's "priority", lower first; rules without one after, in the layout's order). An item
// goes to the first rule that finds it; an item with a submenu takes its subitems along, except those an earlier rule
// took, which stay there and are left out of its submenu. A rule with "also" shows an item even when an earlier rule
// took it; a rule with "consume": false shows what it found without taking it, so later rules and the remaining card
// can show it too. The remaining card takes every top-level item no rule took (Windows' separators among them) and places
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
  TViewKind = (vkItem, vkMenu, vkSeparator);

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
    function Title: string;
    function Enabled: Boolean;
    function HasSubmenu: Boolean;
    function Checked: Boolean;
    function IsDefault: Boolean;
    // Not always there (TNode.Sometimes).
    function Sometimes: Boolean;
    function CardId: string;
    function RuleIndex: Integer;   // -1: none
  end;

  TViewLine = class
  public
    Cards: TObjectList<TViewCard>;
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
    function Hides(Node: TNode): Boolean;
    constructor Create(const ALayout: ILayout; const AKind: string; ATop: TNodes);
    destructor Destroy; override;
    function TopLevel: TViewLevel;
    function MenuLevel(Card: TCard): TViewLevel;
    function SubmenuLevel(Node: TNode): TViewLevel;
  end;

function KeyOf(Node: TNode): string;
// Whether a kind's layout has a rule that looks inside Windows submenus (scope anywhere, or a path): then a
// right-click opens the submenus an extension fills only when opened, before the rules run (Dexmenu.Menu).
function RulesLookDeeper(const Layout: ILayout; const Kind: string): Boolean;

implementation

uses
  System.SysUtils, System.RegularExpressions, System.Generics.Defaults, Dexmenu.Rules;

function TPlacement.Hides(Node: TNode): Boolean;
begin
  Result := (Empty <> nil) and (Node.SubMenu <> 0) and Empty.ContainsKey(Node.SubMenu);
end;

function KeyOf(Node: TNode): string;
begin
  Result := IntToHex(NativeUInt(Node.Menu), 1) + ':' + IntToStr(Node.Id);
end;

// ---- the view ------------------------------------------------------------------------------------------------------

function TViewCard.Title: string;
begin
  case Kind of
    vkItem:
      begin
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
    vkMenu: Result := True;
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
  Result := (Kind = vkItem) and Node.Sometimes;
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

// No separator at the start or the end of a level, never two in a row.
procedure CleanSeparators(Level: TViewLevel);
var
  I: Integer;
  function IsSep(I: Integer): Boolean;
  begin
    Result := (Level.Lines[I].Cards.Count = 1) and (Level.Lines[I].Cards[0].Kind = vkSeparator);
  end;
begin
  I := 0;
  while I < Level.Lines.Count do
    if IsSep(I) and ((I = 0) or IsSep(I - 1)) then
      Level.Lines.Delete(I)
    else
      Inc(I);
  while (Level.Lines.Count > 0) and IsSep(Level.Lines.Count - 1) do
    Level.Lines.Delete(Level.Lines.Count - 1);
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

function RulesLookDeeper(const Layout: ILayout; const Kind: string): Boolean;
var
  Rules: TList<TRule>;
  R: TRule;
begin
  Result := False;
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

  procedure Visit(Nodes: TNodes; R: TRule);
  var
    N: TNode;
    List: TList<TFound>;
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
        Found.Node := N;
        Found.Rule := R;
        List.Add(Found);
        if R.Spec.Consume and not FTaken.ContainsKey(KeyOf(N)) then
        begin
          FTaken.AddOrSetValue(KeyOf(N), True);
          FDirect.AddOrSetValue(KeyOf(N), True);
          TakeBelow(N);   // its subitems follow it, except those taken already
        end;
      end;
      if (N.Children <> nil) and (R.Spec.Scope <> scTop) then
        Visit(N.Children, R);
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
      Visit(Top, R);
    for I := 0 to Top.Count - 1 do
      if not FTaken.ContainsKey(KeyOf(Top[I])) or Top[I].IsSeparator then
        Remaining.Add(Top[I]);
  finally
    Order.Free;
    Rules.Free;
  end;
end;

// ---- the levels ------------------------------------------------------------------------------------------------

function PlaceLines(P: TPlacement; Lines: TLines): TViewLevel;
var
  Line: TLine;
  Card: TCard;
  Out: TViewLine;
  V: TViewCard;
  N: TNode;
  F: TFound;
  List: TList<TFound>;
begin
  Result := TViewLevel.Create;
  for Line in Lines do
  begin
    Out := nil;
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
        if Card.Menu <> nil then
        begin
          V := TViewCard.Create;
          V.Kind := vkMenu;
          V.Card := Card;
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
          Out := NewLine(Result);
        Out.Cards.Add(V);
      end;
  end;
  CleanSeparators(Result);
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
