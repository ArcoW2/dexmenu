unit Dexmenu.Menus;

// Windows' menu items read and written as a whole: type, state, id, submenu, item data, bitmap, check marks and the
// text (also of owner-drawn items: Explorer's full menu makes every item owner-drawn before showing it, and the text
// stays with the item apart from its type; docs/plans/01-PLAN-dexmenu.md 6.2).

interface

uses
  Winapi.Windows;

type
  TItem = record
    Info: TMenuItemInfoW;   // dwTypeData and cch not kept
    Text: string;
    HasText: Boolean;
  end;

const
  ItemMask = MIIM_FTYPE or MIIM_STATE or MIIM_ID or MIIM_SUBMENU or MIIM_DATA or MIIM_BITMAP or MIIM_CHECKMARKS;

// One item, by position or by its id (searched in submenus too, as Windows does).
function ReadItem(Menu: HMENU; At: UINT; ByPosition: Boolean; out Item: TItem): Boolean;
function ReadAll(Menu: HMENU; out Items: TArray<TItem>): Boolean;
function InsertAtEnd(Menu: HMENU; const Item: TItem): Boolean;
function IsSeparator(const Item: TItem): Boolean;
// Every item taken out; submenus are not destroyed.
procedure Empty(Menu: HMENU);
// The name of an item: its text without the & of its key letter and without the accelerator after a tab.
function NameOf(const Text: string): string;

implementation

uses
  System.SysUtils;

function ReadItem(Menu: HMENU; At: UINT; ByPosition: Boolean; out Item: TItem): Boolean;
begin
  Item := Default(TItem);
  Item.Info.cbSize := SizeOf(TMenuItemInfoW);
  Item.Info.fMask := ItemMask or MIIM_STRING;
  Item.Info.dwTypeData := nil;
  if not GetMenuItemInfoW(Menu, At, ByPosition, Item.Info) then
    Exit(False);
  if (Item.Info.fType and (MFT_SEPARATOR or MFT_BITMAP) = 0) and (Item.Info.cch > 0) then
  begin
    SetLength(Item.Text, Item.Info.cch);   // a Delphi string has room for the closing #0 after its last char
    Item.Info.cch := Item.Info.cch + 1;
    Item.Info.dwTypeData := PChar(Item.Text);
    if not GetMenuItemInfoW(Menu, At, ByPosition, Item.Info) then
      Exit(False);
    SetLength(Item.Text, StrLen(PChar(Item.Text)));
    Item.HasText := True;
  end;
  Item.Info.dwTypeData := nil;
  Item.Info.cch := 0;
  Result := True;
end;

function ReadAll(Menu: HMENU; out Items: TArray<TItem>): Boolean;
var
  Count, I: Integer;
begin
  Items := nil;
  Count := GetMenuItemCount(Menu);
  if Count < 0 then
    Exit(False);
  SetLength(Items, Count);
  for I := 0 to Count - 1 do
    if not ReadItem(Menu, I, True, Items[I]) then
      Exit(False);
  Result := True;
end;

function InsertAtEnd(Menu: HMENU; const Item: TItem): Boolean;
var
  Info: TMenuItemInfoW;
begin
  Info := Item.Info;
  Info.cbSize := SizeOf(TMenuItemInfoW);
  Info.fMask := ItemMask;
  Info.dwTypeData := nil;
  if Item.HasText then
  begin
    Info.fMask := Info.fMask or MIIM_STRING;
    Info.dwTypeData := PChar(Item.Text);
  end;
  Result := InsertMenuItemW(Menu, GetMenuItemCount(Menu), True, Info);
end;

function IsSeparator(const Item: TItem): Boolean;
begin
  Result := Item.Info.fType and MFT_SEPARATOR <> 0;
end;

procedure Empty(Menu: HMENU);
begin
  while GetMenuItemCount(Menu) > 0 do
    RemoveMenu(Menu, 0, MF_BYPOSITION);
end;

function NameOf(const Text: string): string;
var
  I: Integer;
begin
  Result := '';
  I := 1;
  while (I <= Length(Text)) and (Text[I] <> #9) do
  begin
    if (Text[I] = '&') and (I < Length(Text)) and (Text[I + 1] <> '&') then
    begin
      Inc(I);
      Continue;
    end;
    if Text[I] = '&' then
      Inc(I);
    if I <= Length(Text) then
      Result := Result + Text[I];
    Inc(I);
  end;
  Result := Trim(Result);
end;

end.
