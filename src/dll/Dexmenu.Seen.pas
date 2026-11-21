unit Dexmenu.Seen;

// Seen items (docs/plans/01-PLAN-dexmenu.md 3.6; plan 00 step 4): after each menu Dexmenu showed, the items of that
// right-click written per kind of right-click to <SeenFolder>\<kind>.json, with the submenus that were
// opened (an extension may fill one only then). The settings app's preview shows them: they are made into a real
// Windows menu again (MenuFromSeen), so the preview runs through the same tree, layout and drawing as a right-click.
//
// The file is merged, not replaced: every item any right-click of that kind showed stays in it, so items an extension
// hides for some selections can be placed too (plan 02 3.8). An item that was not there every time is marked
// "sometimes": an item of an earlier right-click missing from this one, one of this right-click missing from earlier
// ones, and one Windows' menu lost while it was shown (Explorer deletes the items it hides after the show). Items are
// matched per level by name; a submenu not opened this time keeps what was seen in it before. The preview draws the
// "sometimes" items striped (Dexmenu.Draw, the preview only).

interface

uses
  Winapi.Windows, System.JSON, Dexmenu.Tree;

// The items of a menu as written to the seen file.
function SeenJson(Top: TNodes): TJSONArray;
// Old and New merged into a new array (neither freed): New's items in New's order, Old's items missing from New
// inserted after the item they followed in Old, marked "sometimes"; MarkNew: New's items missing from Old marked too
// (only where Old had items at that level).
function MergeSeen(Old, New: TJSONArray; MarkNew: Boolean): TJSONArray;
// Items merged into <SeenFolder>\<kind>.json (the caller frees Items).
procedure WriteSeen(const Kind: string; Items: TJSONArray);
// A popup menu built from a seen file's text (its own ids, from 1); 0 and Error set when the text is not valid.
// "sometimes" items get SometimesData as their item data (TNode.Sometimes).
function MenuFromSeen(const Text: string; out Error: string): HMENU;
function SeenFolder: string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, Dexmenu.Log, Dexmenu.Json, Dexmenu.Menus;

// DEXMENU_SEEN_FOLDER (the tests), else %APPDATA%\Dexmenu\seen.
function SeenFolder: string;
var
  Env: array[0..MAX_PATH] of Char;
begin
  if GetEnvironmentVariable('DEXMENU_SEEN_FOLDER', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := RoamingAppData + '\Dexmenu\seen';
end;

function SeenJson(Top: TNodes): TJSONArray;
var
  N: TNode;
  O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for N in Top do
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
        O.AddPair('items', SeenJson(N.Children));
    end;
  end;
end;

function BoolOf(O: TJSONObject; const Name: string; Default: Boolean): Boolean; forward;

function IsSeparatorJson(V: TJSONValue): Boolean;
begin
  Result := (V is TJSONObject) and BoolOf(TJSONObject(V), 'separator', False);
end;

function NameJson(V: TJSONValue): string;
var
  N: TJSONValue;
begin
  N := TJSONObject(V).GetValue('name');
  if N is TJSONString then
    Result := N.Value
  else
    Result := '';
end;

procedure MarkSometimes(O: TJSONObject);
begin
  if O.GetValue('sometimes') = nil then
    O.AddPair('sometimes', TJSONBool.Create(True));
end;

// The key of each item of a level, its name and which of that name it is (a level may hold two of one name).
function Keys(Items: TJSONArray): TArray<string>;
var
  Count: TDictionary<string, Integer>;
  I, N: Integer;
  Name: string;
begin
  SetLength(Result, 0);
  if Items = nil then
    Exit;
  SetLength(Result, Items.Count);
  Count := TDictionary<string, Integer>.Create;
  try
    for I := 0 to Items.Count - 1 do
    begin
      if not (Items.Items[I] is TJSONObject) or IsSeparatorJson(Items.Items[I]) then
        Continue;
      Name := NameJson(Items.Items[I]);
      if not Count.TryGetValue(Name, N) then
        N := 0;
      Count.AddOrSetValue(Name, N + 1);
      Result[I] := Name + #9 + IntToStr(N);
    end;
  finally
    Count.Free;
  end;
end;

function MergeSeen(Old, New: TJSONArray; MarkNew: Boolean): TJSONArray;
var
  OldKeys, NewKeys: TArray<string>;
  OldByKey: TDictionary<string, TJSONObject>;
  NewByKey: TDictionary<string, TJSONObject>;
  List: TList<TJSONObject>;
  OldHasItems: Boolean;
  I, InsertAt: Integer;
  C, M: TJSONObject;
  OldSub, NewSub: TJSONValue;
  Merged: TJSONArray;
begin
  Result := TJSONArray.Create;
  OldKeys := Keys(Old);
  NewKeys := Keys(New);
  OldByKey := TDictionary<string, TJSONObject>.Create;
  NewByKey := TDictionary<string, TJSONObject>.Create;
  List := TList<TJSONObject>.Create;
  try
    OldHasItems := False;
    if Old <> nil then
      for I := 0 to Old.Count - 1 do
        if OldKeys[I] <> '' then
        begin
          OldByKey.AddOrSetValue(OldKeys[I], TJSONObject(Old.Items[I]));
          OldHasItems := True;
        end;
    // New's items, in New's order, with what Old knew of them
    if New <> nil then
      for I := 0 to New.Count - 1 do
      begin
        if not (New.Items[I] is TJSONObject) then
          Continue;
        C := TJSONObject(New.Items[I].Clone);
        List.Add(C);
        if NewKeys[I] = '' then
          Continue;   // a separator
        NewByKey.AddOrSetValue(NewKeys[I], C);
        if not OldByKey.TryGetValue(NewKeys[I], M) then
        begin
          if MarkNew and OldHasItems then
            MarkSometimes(C);
          Continue;
        end;
        if BoolOf(M, 'sometimes', False) then
          MarkSometimes(C);
        OldSub := M.GetValue('items');
        NewSub := C.GetValue('items');
        if not (OldSub is TJSONArray) or not BoolOf(C, 'submenu', False) then
          Continue;
        if NewSub is TJSONArray then
        begin
          Merged := MergeSeen(TJSONArray(OldSub), TJSONArray(NewSub), MarkNew);
          C.RemovePair('items').Free;
          C.AddPair('items', Merged);
        end
        else
          C.AddPair('items', TJSONArray(OldSub.Clone));   // not opened this time: what was seen in it before
      end;
    // Old's items missing from New, after the item they followed
    InsertAt := 0;
    if Old <> nil then
      for I := 0 to Old.Count - 1 do
      begin
        if OldKeys[I] = '' then
          Continue;
        if NewByKey.TryGetValue(OldKeys[I], C) then
          InsertAt := List.IndexOf(C) + 1
        else
        begin
          // after a separator in Old: after the separator here too, with the items it followed
          if (I > 0) and IsSeparatorJson(Old.Items[I - 1]) then
            while (InsertAt < List.Count) and IsSeparatorJson(List[InsertAt]) do
              Inc(InsertAt);
          C := TJSONObject(Old.Items[I].Clone);
          MarkSometimes(C);
          List.Insert(InsertAt, C);
          Inc(InsertAt);
        end;
      end;
    for C in List do
      Result.AddElement(C);
  finally
    List.Free;
    NewByKey.Free;
    OldByKey.Free;
  end;
end;

procedure WriteSeen(const Kind: string; Items: TJSONArray);
var
  Root: TJSONObject;
  Before: TJSONValue;
  OldItems: TJSONArray;
  Lines: TStringList;
  Path, Error: string;
begin
  try
    ForceDirectories(SeenFolder);
    Path := SeenFolder + '\' + Kind + '.json';
    Before := nil;
    if FileExists(Path) then
      Before := ParseWithComments(TFile.ReadAllText(Path, TEncoding.UTF8), Error);
    Root := TJSONObject.Create;
    try
      OldItems := nil;
      if (Before is TJSONObject) and (TJSONObject(Before).GetValue('items') is TJSONArray) then
        OldItems := TJSONArray(TJSONObject(Before).GetValue('items'));
      Root.AddPair('kind', Kind);
      Root.AddPair('items', MergeSeen(OldItems, Items, True));
      Lines := TStringList.Create;
      try
        Lines.Text := Root.Format(2);
        Lines.SaveToFile(Path + '.tmp', TEncoding.UTF8);
      finally
        Lines.Free;
      end;
    finally
      Root.Free;
      Before.Free;
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
    if BoolOf(O, 'sometimes', False) then
      Item.Info.dwItemData := SometimesData;
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
