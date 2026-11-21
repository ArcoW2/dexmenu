unit Dexmenu.Arrange;

// The spike's arranged Windows menu (docs/plans/01-PLAN-dexmenu.md 3.4, 6.1): Windows' items taken out of its menu,
// laid out by a text layout into a new menu with the same ids, and put back after the show call.
//
// The text layout (DEXMENU_LAYOUT, else %APPDATA%\Dexmenu\layout.txt):
//   # a comment
//   [from LexPen]          a submenu of the user's own, placed where its first item was
//   Edit in LexPen         an item of Windows' menu by its text (no &, no accelerator), * and ? as wildcards
// Top-level items only; a top-level submenu matched by its text moves whole.

interface

uses
  Winapi.Windows, System.Generics.Collections, Dexmenu.Menus;

type
  // A menu shown arranged: what to put back afterwards.
  TArranged = class
  public
    Original: HMENU;
    Shown: HMENU;
    Made: TList<HMENU>;     // the new top menu and the user's submenus
    Items: TList<TItem>;    // Windows' items, in Windows' order
    Emptied: Boolean;       // Windows' items taken out of the original
    constructor Create(AOriginal: HMENU);
    destructor Destroy; override;
  end;

// Windows' menu laid out into a new menu, its items moved there. False: nothing to arrange or an error; Restore then
// puts everything back.
function Arrange(A: TArranged): Boolean;
// Everything as it was: the new menus gone, Windows' items back in the original in their order.
procedure Restore(A: TArranged);

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, Dexmenu.Log;

type
  TGroup = record
    Name: string;
    Patterns: TArray<string>;
  end;

var
  LayoutLock: TRTLCriticalSection;
  Layout: TArray<TGroup>;
  LayoutStamp: TFileTime;

constructor TArranged.Create(AOriginal: HMENU);
begin
  inherited Create;
  Original := AOriginal;
  Made := TList<HMENU>.Create;
  Items := TList<TItem>.Create;
end;

destructor TArranged.Destroy;
begin
  Made.Free;
  Items.Free;
  inherited;
end;

function LayoutPath: string;
var
  Env: array[0..MAX_PATH] of Char;
begin
  if GetEnvironmentVariable('DEXMENU_LAYOUT', Env, MAX_PATH) > 0 then
    Exit(Env);
  Result := RoamingAppData + '\Dexmenu\layout.txt';
end;

// The layout, read again when the file's time stamp changed. No file: no groups (Windows' menu as it is).
function CurrentLayout: TArray<TGroup>;
var
  Path, Line: string;
  Data: TWin32FileAttributeData;
  Lines: TStringList;
  G: Integer;
begin
  Path := LayoutPath;
  EnterCriticalSection(LayoutLock);
  try
    if not GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Data) then
      Layout := nil
    else if CompareFileTime(Data.ftLastWriteTime, LayoutStamp) <> 0 then
    begin
      Layout := nil;
      Lines := TStringList.Create;
      try
        try
          Lines.LoadFromFile(Path, TEncoding.UTF8);
        except
          Lines.Clear;
        end;
        for Line in Lines do
        begin
          if (Trim(Line) = '') or (Trim(Line)[1] = '#') then
            Continue;
          if (Trim(Line)[1] = '[') and (Trim(Line)[Length(Trim(Line))] = ']') then
          begin
            SetLength(Layout, Length(Layout) + 1);
            Layout[High(Layout)].Name := Trim(Copy(Trim(Line), 2, Length(Trim(Line)) - 2));
          end
          else if Length(Layout) > 0 then
          begin
            G := High(Layout);
            SetLength(Layout[G].Patterns, Length(Layout[G].Patterns) + 1);
            Layout[G].Patterns[High(Layout[G].Patterns)] := Trim(Line);
          end;
        end;
      finally
        Lines.Free;
      end;
      LayoutStamp := Data.ftLastWriteTime;
    end;
    Result := Copy(Layout);
  finally
    LeaveCriticalSection(LayoutLock);
  end;
end;

function Matches(Pattern, Text: PChar): Boolean;
begin
  if Pattern^ = #0 then
    Exit(Text^ = #0);
  if Pattern^ = '*' then
    Exit(Matches(Pattern + 1, Text) or ((Text^ <> #0) and Matches(Pattern, Text + 1)));
  if Text^ = #0 then
    Exit(False);
  if (Pattern^ <> '?') and (Pattern^ <> Text^) then   // both lower case (MatchesText)
    Exit(False);
  Result := Matches(Pattern + 1, Text + 1);
end;

function MatchesText(const Pattern, Text: string): Boolean;
begin
  Result := Matches(PChar(LowerCase(Pattern)), PChar(LowerCase(Text)));
end;

// No line at the start or end, never two in a row.
function WithoutStrayLines(const Items: TList<TItem>): TList<TItem>;
var
  Item: TItem;
begin
  Result := TList<TItem>.Create;
  for Item in Items do
  begin
    if IsSeparator(Item) and ((Result.Count = 0) or IsSeparator(Result.Last)) then
      Continue;
    Result.Add(Item);
  end;
  while (Result.Count > 0) and IsSeparator(Result.Last) do
    Result.Delete(Result.Count - 1);
end;

procedure Restore(A: TArranged);
var
  M: HMENU;
  Item: TItem;
begin
  for M in A.Made do
  begin
    Empty(M);
    DestroyMenu(M);
  end;
  A.Made.Clear;
  if not A.Emptied then
    Exit;
  Empty(A.Original);
  for Item in A.Items do
    InsertAtEnd(A.Original, Item);
  A.Emptied := False;
end;

function Arrange(A: TArranged): Boolean;
var
  Read: TArray<TItem>;
  Groups: TArray<TGroup>;
  GroupOf: TArray<Integer>;
  GroupMenu: TArray<HMENU>;
  Any, HasStyle: Boolean;
  I, G: Integer;
  P, Name: string;
  Style: TMenuInfo;
  Top, Clean: TList<TItem>;
  Sub, Item: TItem;

  function Make: HMENU;
  begin
    Result := CreatePopupMenu;
    if Result <> 0 then
    begin
      A.Made.Add(Result);
      if HasStyle then
        SetMenuInfo(Result, Style);
    end;
  end;

begin
  Result := False;
  if not ReadAll(A.Original, Read) then
    Exit;
  A.Items.AddRange(Read);
  Groups := CurrentLayout;
  if Tracing then
    for Item in Read do
      Log(Format('  item id=%u type=0x%x state=0x%x data=%s bitmap=%s text=%s', [Item.Info.wID, Item.Info.fType,
        Item.Info.fState, Hex(Item.Info.dwItemData), Hex(NativeUInt(Item.Info.hbmpItem)),
        BoolToStr(Item.HasText, True)]) + IfThen(Item.HasText, ' "' + NameOf(Item.Text) + '"', ''));

  // Which group each item goes to (-1: stays where it is).
  SetLength(GroupOf, Length(Read));
  Any := False;
  for I := 0 to High(Read) do
  begin
    GroupOf[I] := -1;
    if IsSeparator(Read[I]) or not Read[I].HasText then
      Continue;
    Name := NameOf(Read[I].Text);
    for G := 0 to High(Groups) do
    begin
      for P in Groups[G].Patterns do
        if MatchesText(P, Name) then
        begin
          GroupOf[I] := G;
          Any := True;
          Break;
        end;
      if GroupOf[I] >= 0 then
        Break;
    end;
  end;
  if not Any then
    Exit;

  FillChar(Style, SizeOf(Style), 0);
  Style.cbSize := SizeOf(Style);
  Style.fMask := MIM_STYLE or MIM_MENUDATA or MIM_BACKGROUND or MIM_MAXHEIGHT or MIM_HELPID;
  HasStyle := GetMenuInfo(A.Original, Style);
  A.Shown := Make;
  if A.Shown = 0 then
    Exit;
  SetLength(GroupMenu, Length(Groups));

  // The top level: Windows' order, each group's submenu where its first item was.
  Top := TList<TItem>.Create;
  try
    for I := 0 to High(Read) do
    begin
      G := GroupOf[I];
      if G < 0 then
      begin
        Top.Add(Read[I]);
        Continue;
      end;
      if GroupMenu[G] <> 0 then
        Continue;
      GroupMenu[G] := Make;
      if GroupMenu[G] = 0 then
        Exit;
      Sub := Default(TItem);
      Sub.Info.cbSize := SizeOf(TMenuItemInfoW);
      Sub.Info.fType := MFT_STRING;
      Sub.Info.hSubMenu := GroupMenu[G];
      Sub.Text := Groups[G].Name;
      Sub.HasText := True;
      Top.Add(Sub);
    end;

    Empty(A.Original);   // every item now lives in the new menus only; Restore puts them back
    A.Emptied := True;
    for I := 0 to High(Read) do
      if (GroupOf[I] >= 0) and not InsertAtEnd(GroupMenu[GroupOf[I]], Read[I]) then
        Exit;
    Clean := WithoutStrayLines(Top);
    try
      for Item in Clean do
        if not InsertAtEnd(A.Shown, Item) then
          Exit;
    finally
      Clean.Free;
    end;
  finally
    Top.Free;
  end;
  Result := True;
end;

initialization
  InitializeCriticalSection(LayoutLock);

finalization
  DeleteCriticalSection(LayoutLock);

end.
