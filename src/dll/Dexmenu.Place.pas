unit Dexmenu.Place;

// The layout applied to Windows' items (docs/plans/02-PLAN-own-menu.md 3.3; plan 00 step 3): a level of the menu is
// lines of cards. The remaining card takes every top-level item no other rule took and places each, with its
// subitems, at its own place as a card of its own on its own line (Windows' separators kept as thin lines). A card
// with a menu is a card that opens its own lines. A Windows submenu opened from a card is its items as cards, one per
// line. Cards with match rules come with step 5: until then they find nothing and are not shown.

interface

uses
  System.Generics.Collections, Dexmenu.Tree, Dexmenu.Layout;

type
  TViewKind = (vkItem, vkMenu, vkSeparator);

  TViewCard = class
  public
    Kind: TViewKind;
    Node: TNode;      // vkItem: Windows' item (not owned)
    Card: TCard;      // vkMenu: the layout's card; vkItem: the card that placed it (not owned)
    function Title: string;
    function Enabled: Boolean;
    function HasSubmenu: Boolean;
    function Checked: Boolean;
    function IsDefault: Boolean;
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

  // What a menu shows: the layout and Windows' top-level items, and which of them are left for the remaining card.
  TPlacement = class
  public
    Layout: ILayout;
    Kind: string;
    Top: TNodes;            // not owned
    Remaining: TList<TNode>;
    constructor Create(const ALayout: ILayout; const AKind: string; ATop: TNodes);
    destructor Destroy; override;
    function TopLevel: TViewLevel;
    function MenuLevel(Card: TCard): TViewLevel;
    function SubmenuLevel(Node: TNode): TViewLevel;
  end;

implementation

uses
  System.SysUtils;

function TViewCard.Title: string;
begin
  case Kind of
    vkItem: Result := Node.Name;
    vkMenu: Result := Card.Title;
  else
    Result := '';
  end;
end;

function TViewCard.Enabled: Boolean;
begin
  Result := (Kind = vkMenu) or ((Kind = vkItem) and Node.Enabled);
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

procedure AddNodeLine(Level: TViewLevel; Node: TNode; Card: TCard);
var
  Line: TViewLine;
  V: TViewCard;
begin
  if not Node.IsSeparator and (Node.Name = '') and (Node.SubMenu = 0) then
    Exit;   // an item without text (a bitmap of its own): not shown until icons (step 7)
  Line := TViewLine.Create;
  Level.Lines.Add(Line);
  V := TViewCard.Create;
  V.Node := Node;
  V.Card := Card;
  if Node.IsSeparator then
    V.Kind := vkSeparator
  else
    V.Kind := vkItem;
  Line.Cards.Add(V);
end;

constructor TPlacement.Create(const ALayout: ILayout; const AKind: string; ATop: TNodes);
var
  N: TNode;
begin
  inherited Create;
  Layout := ALayout;
  Kind := AKind;
  Top := ATop;
  Remaining := TList<TNode>.Create;
  for N in Top do   // step 3: no match rules yet, so every top-level item is left for the remaining card
    Remaining.Add(N);
end;

destructor TPlacement.Destroy;
begin
  Remaining.Free;
  inherited;
end;

function PlaceLines(P: TPlacement; Lines: TLines): TViewLevel;
var
  Line: TLine;
  Card: TCard;
  Out: TViewLine;
  V: TViewCard;
  N: TNode;
begin
  Result := TViewLevel.Create;
  for Line in Lines do
  begin
    Out := nil;
    for Card in Line.Cards do
      if Card.IsRemaining then
      begin
        Out := nil;   // the remaining items each take a line of their own
        for N in P.Remaining do
          AddNodeLine(Result, N, Card);
      end
      else if Card.Menu <> nil then
      begin
        if Out = nil then
        begin
          Out := TViewLine.Create;
          Result.Lines.Add(Out);
        end;
        V := TViewCard.Create;
        V.Kind := vkMenu;
        V.Card := Card;
        Out.Cards.Add(V);
      end;
      // a card with match rules: step 5
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
      AddNodeLine(Result, N, nil);
  CleanSeparators(Result);
end;

end.
