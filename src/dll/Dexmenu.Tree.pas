unit Dexmenu.Tree;

// Windows' menu as a tree of items (docs/plans/02-PLAN-own-menu.md 3.2): each item with its text, name, path, id,
// state and submenu. A submenu's items are read when it is opened (an extension may fill it only then). Windows'
// items stay in Windows' menu; the tree only reads them.

interface

uses
  Winapi.Windows, System.Generics.Collections, Dexmenu.Menus;

type
  TNode = class
  public
    Menu: HMENU;              // the menu it sits in
    Item: TItem;
    Name: string;             // the text without & and accelerator
    Path: string;             // the submenus it sits in, 'A > B'; '' at the top
    Children: TObjectList<TNode>;   // a submenu's items once read; nil before
    destructor Destroy; override;
    function Id: UINT;
    function IsSeparator: Boolean;
    function SubMenu: HMENU;
    function Enabled: Boolean;
    function Checked: Boolean;
    function IsDefault: Boolean;
    // Not in every right-click of its kind (the seen items, Dexmenu.Seen): only in the settings app's preview.
    function Sometimes: Boolean;
  end;

  TNodes = TObjectList<TNode>;

const
  // The item data the preview's menu (Dexmenu.Seen.MenuFromSeen) gives an item marked "sometimes".
  SometimesData = NativeUInt($D3C5E7E5);

// The items of a menu, one level; Path is the path of the submenu they are in.
function ReadLevel(Menu: HMENU; const Path: string): TNodes;
// A node's submenu read (again).
procedure ReadChildren(Node: TNode);

implementation

uses
  System.SysUtils;

destructor TNode.Destroy;
begin
  Children.Free;
  inherited;
end;

function TNode.Id: UINT;
begin
  Result := Item.Info.wID;
end;

function TNode.IsSeparator: Boolean;
begin
  Result := Dexmenu.Menus.IsSeparator(Item);
end;

function TNode.SubMenu: HMENU;
begin
  Result := Item.Info.hSubMenu;
end;

function TNode.Enabled: Boolean;
begin
  Result := Item.Info.fState and MFS_DISABLED = 0;
end;

function TNode.Checked: Boolean;
begin
  Result := Item.Info.fState and MFS_CHECKED <> 0;
end;

function TNode.IsDefault: Boolean;
begin
  Result := Item.Info.fState and MFS_DEFAULT <> 0;
end;

function TNode.Sometimes: Boolean;
begin
  Result := Item.Info.dwItemData = SometimesData;
end;

function ReadLevel(Menu: HMENU; const Path: string): TNodes;
var
  Items: TArray<TItem>;
  I: Integer;
  Node: TNode;
begin
  Result := TNodes.Create;
  if not ReadAll(Menu, Items) then
    Exit;
  for I := 0 to High(Items) do
  begin
    Node := TNode.Create;
    Node.Menu := Menu;
    Node.Item := Items[I];
    if Items[I].HasText then
      Node.Name := NameOf(Items[I].Text);
    Node.Path := Path;
    Result.Add(Node);
  end;
end;

procedure ReadChildren(Node: TNode);
var
  Path: string;
begin
  FreeAndNil(Node.Children);
  if Node.SubMenu = 0 then
    Exit;
  if Node.Path = '' then
    Path := Node.Name
  else
    Path := Node.Path + ' > ' + Node.Name;
  Node.Children := ReadLevel(Node.SubMenu, Path);
end;

end.
