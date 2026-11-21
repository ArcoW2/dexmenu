unit Dexmenu.Seen;

// Seen items (docs/plans/01-PLAN-dexmenu.md 3.6; plan 00 step 4): after each menu Dexmenu showed, the items of that
// right-click written per kind of right-click to <SeenFolder>\<kind>.json, with the submenus that were
// opened (an extension may fill one only then). The settings app's preview shows them: they are made into a real
// Windows menu again (MenuFromSeen), so the preview runs through the same tree, layout and drawing as a right-click.
// For now the file holds the last right-click of a kind; merging what every right-click showed comes later.

interface

uses
  Winapi.Windows, Dexmenu.Tree;

procedure WriteSeen(const Kind: string; Top: TNodes);
// A popup menu built from a seen file's text (its own ids, from 1); 0 and Error set when the text is not valid.
function MenuFromSeen(const Text: string; out Error: string): HMENU;
function SeenFolder: string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, Dexmenu.Log, Dexmenu.Json, Dexmenu.Menus;

// DEXMENU_SEEN_FOLDER (the tests), else %APPDATA%\Dexmenu\seen.
function SeenFolder: string;
var
  Env: array[0..MAX_PATH] of Char;
begin
  if GetEnvironmentVariable('DEXMENU_SEEN_FOLDER', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := RoamingAppData + '\Dexmenu\seen';
end;

function NodesToJson(Nodes: TNodes): TJSONArray;
var
  N: TNode;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for N in Nodes do
  begin
    O := TJSONObject.Create;
    Result.AddElement(O);
    if N.IsSeparator then
    begin
      O.AddPair('separator', TJSONBool.Create(True));
      Continue;
    end;
    O.AddPair('text', N.Item.Text);
    O.AddPair('name', N.Name);
    if not N.Enabled then
      O.AddPair('enabled', TJSONBool.Create(False));
    if N.Checked then
      O.AddPair('checked', TJSONBool.Create(True));
    if N.IsDefault then
      O.AddPair('default', TJSONBool.Create(True));
    if N.SubMenu <> 0 then
    begin
      O.AddPair('submenu', TJSONBool.Create(True));
      if N.Children <> nil then
        O.AddPair('items', NodesToJson(N.Children));
    end;
  end;
end;

procedure WriteSeen(const Kind: string; Top: TNodes);
var
  Root: TJSONObject;
  Lines: TStringList;
  Path: string;
begin
  try
    ForceDirectories(SeenFolder);
    Path := SeenFolder + '\' + Kind + '.json';
    Root := TJSONObject.Create;
    try
      Root.AddPair('kind', Kind);
      Root.AddPair('items', NodesToJson(Top));
      Lines := TStringList.Create;
      try
        Lines.Text := Root.Format(2);
        Lines.SaveToFile(Path + '.tmp', TEncoding.UTF8);
      finally
        Lines.Free;
      end;
    finally
      Root.Free;
    end;
    MoveFileEx(PChar(Path + '.tmp'), PChar(Path), MOVEFILE_REPLACE_EXISTING);
  except
    on E: Exception do
      Log('seen items not written: ' + E.Message);
  end;
end;

function BoolOf(O: TJSONObject; const Name: string; Default: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := O.GetValue(Name);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := Default;
end;

procedure Fill(Menu: HMENU; Items: TJSONArray; var NextId: UINT);
var
  V: TJSONValue;
  O: TJSONObject;
  Item: TItem;
  Sub: HMENU;
begin
  for V in Items do
  begin
    if not (V is TJSONObject) then
      Continue;
    O := TJSONObject(V);
    Item := Default(TItem);
    Item.Info.cbSize := SizeOf(TMenuItemInfoW);
    if BoolOf(O, 'separator', False) then
    begin
      Item.Info.fType := MFT_SEPARATOR;
      InsertAtEnd(Menu, Item);
      Continue;
    end;
    Item.Info.fType := MFT_STRING;
    Item.Info.wID := NextId;
    Inc(NextId);
    if not BoolOf(O, 'enabled', True) then
      Item.Info.fState := Item.Info.fState or MFS_DISABLED;
    if BoolOf(O, 'checked', False) then
      Item.Info.fState := Item.Info.fState or MFS_CHECKED;
    if BoolOf(O, 'default', False) then
      Item.Info.fState := Item.Info.fState or MFS_DEFAULT;
    if O.GetValue('text') is TJSONString then
      Item.Text := O.GetValue('text').Value;
    Item.HasText := Item.Text <> '';
    if BoolOf(O, 'submenu', False) then
    begin
      Sub := CreatePopupMenu;
      if O.GetValue('items') is TJSONArray then
        Fill(Sub, TJSONArray(O.GetValue('items')), NextId);
      Item.Info.hSubMenu := Sub;
    end;
    InsertAtEnd(Menu, Item);
  end;
end;

function MenuFromSeen(const Text: string; out Error: string): HMENU;
var
  Root: TJSONValue;
  NextId: UINT;
begin
  Result := 0;
  Root := ParseWithComments(Text, Error);
  try
    if not (Root is TJSONObject) or not (TJSONObject(Root).GetValue('items') is TJSONArray) then
    begin
      if Error = '' then
        Error := 'seen items: "items" missing';
      Exit;
    end;
    Result := CreatePopupMenu;
    NextId := 1;
    Fill(Result, TJSONArray(TJSONObject(Root).GetValue('items')), NextId);
  finally
    Root.Free;
  end;
end;

end.
