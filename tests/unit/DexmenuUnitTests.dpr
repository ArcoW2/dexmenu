program DexmenuUnitTests;

// Unit tests of the DLL's units (plan 00 step 2 on): comments in JSON, the layout file, and the rules applied to a
// Windows menu built here (plan 02 3.12).
// Prints PASS / FAIL per check; exit code = the number of failures. Run by tests\run-tests.ps1.

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, System.Generics.Collections, System.Math,
  Dexmenu.Json in '..\..\src\dll\Dexmenu.Json.pas',
  Dexmenu.Log in '..\..\src\dll\Dexmenu.Log.pas',
  Dexmenu.Rules in '..\..\src\dll\Dexmenu.Rules.pas',
  Dexmenu.Layout in '..\..\src\dll\Dexmenu.Layout.pas',
  Dexmenu.Menus in '..\..\src\dll\Dexmenu.Menus.pas',
  Dexmenu.Tree in '..\..\src\dll\Dexmenu.Tree.pas',
  Dexmenu.Place in '..\..\src\dll\Dexmenu.Place.pas',
  Dexmenu.Seen in '..\..\src\dll\Dexmenu.Seen.pas',
  Dexmenu.Usage in '..\..\src\dll\Dexmenu.Usage.pas',
  Dexmenu.Icons in '..\..\src\dll\Dexmenu.Icons.pas',
  Dexmenu.Theme in '..\..\src\dll\Dexmenu.Theme.pas',
  Dexmenu.Draw in '..\..\src\dll\Dexmenu.Draw.pas',
  Winapi.D2D1, System.JSON;

var
  Failures: Integer = 0;

procedure Check(Ok: Boolean; const What: string);
begin
  if Ok then
    Writeln('PASS ', What)
  else
  begin
    Writeln('FAIL ', What);
    Inc(Failures);
  end;
end;

function Valid(const Text: string): Boolean;
var
  Error: string;
begin
  Result := ParseLayout(Text, 'test', Error) <> nil;
end;

function ErrorOf(const Text: string): string;
begin
  if ParseLayout(Text, 'test', Result) <> nil then
    Result := '';
end;

procedure TestComments;
begin
  Check(WithoutComments('{ "a": 1 } // gone') = '{ "a": 1 } ', 'a comment after JSON taken out');
  Check(WithoutComments('// gone'#10'{ }') = #10'{ }', 'a comment line taken out, the line end kept');
  Check(WithoutComments('{ "r": "^https://x" }') = '{ "r": "^https://x" }', '// inside a string kept');
  Check(WithoutComments('{ "r": "a\"//b" } // c') = '{ "r": "a\"//b" } ', 'an escaped quote does not end the string');
end;

procedure TestLayouts;
const
  Remaining = '{ "card": "Rest", "rules": [ "remaining" ] }';
var
  NoteLayout: ILayout;
  NoteError: string;
  When: TDateTime;
begin
  Check(Valid(BaseLayout), 'the built-in base layout is valid');
  Check(Valid('{ "default": [ { "line": [ ' + Remaining + ' ] } ] }'), 'one remaining card at the root');
  Check(Valid('{ "default": [ { "line": [ { "card": "More", "menu": [ { "line": [ ' + Remaining + ' ] } ] } ] } ] }'),
    'the remaining card inside a card with a menu');
  Check(Pos('exactly one remaining card', ErrorOf('{ "default": [ { "line": [ { "card": "A", "rules": [] } ] } ] }')) > 0,
    'no remaining card: invalid');
  Check(Pos('found 2', ErrorOf('{ "default": [ { "line": [ ' + Remaining + ', ' + Remaining + ' ] } ] }')) > 0,
    'two remaining cards: invalid');
  Check(Pos('not both', ErrorOf('{ "default": [ { "line": [ { "card": "A", "rules": [ "remaining" ], "menu": [] } ] } ] }')) > 0,
    'rules and a menu on one card: invalid');
  Check(Pos('"default" is missing', ErrorOf('{ "folder": [ { "line": [ ' + Remaining + ' ] } ] }')) > 0,
    'no default kind: invalid');
  Check(ErrorOf('{ "default": [ ') <> '', 'broken JSON: invalid');
  Check(Valid('// a comment'#10'{ "default": [ { "line": [ ' + Remaining + ' ] } ] } // and one more'),
    'comments in a layout');
  // the current form: one menu, "lines" (plan 05 3.1)
  Check(Valid('{ "format": 1, "lines": [ { "line": [ ' + Remaining + ' ] } ] }'), 'format 1: one menu in "lines"');
  Check(Pos('"lines" is missing', ErrorOf('{ "format": 1, "default": [ { "line": [ ' + Remaining + ' ] } ] }')) > 0,
    'format 1 without "lines": invalid');
  Check(Pos('newer form', ErrorOf('{ "format": 99, "lines": [ { "line": [ ' + Remaining + ' ] } ] }')) > 0,
    'a newer format than the DLL knows: not used, the reason says so');
  Check(Valid('{ "default": [ { "line": [ ' + Remaining + ' ] } ], "folder": [ { "line": [ { "card": "Broken" } ] } ] }'),
    'the older form: read by its default menu, its other kinds'' sections ignored');
  NoteLayout := ParseLayout('{ "format": 1, "lines": [ { "line": [ { "note": "a", "align": "text" }, { "note": "b", "align": "right" }, ' +
    '{ "note": "c" } ] }, { "line": [ ' + Remaining + ' ] } ] }', 'test', NoteError);
  Check((NoteLayout <> nil) and (NoteLayout.Lines('')[0].Cards[0].NoteAlign = naText) and
    (NoteLayout.Lines('')[0].Cards[1].NoteAlign = naRight) and (NoteLayout.Lines('')[0].Cards[2].NoteAlign = naLeft),
    'a note''s alignment read: text, right; left when not given');
  // a note's font and style; a card's 3D border and shadow kept in its look (plan 03 3.6)
  NoteLayout := ParseLayout('{ "format": 1, "lines": [ { "line": [ { "note": "a", "font": "extra" }, ' +
    '{ "note": "b", "font": { "family": "Georgia", "size": 13, "italic": true }, "background": "#ffeecc" }, { "note": "c" }, ' +
    '{ "card": "D", "rules": [ { "name": { "equals": "x" } } ], "border3d": { "style": "inset" }, "shadow": { "blur": 4 } } ] }, ' +
    '{ "line": [ ' + Remaining + ' ] } ] }', 'test', NoteError);
  Check((NoteLayout <> nil) and NoteLayout.Lines('')[0].Cards[0].Font.Extra and not NoteLayout.Lines('')[0].Cards[0].Font.Own and
    NoteLayout.Lines('')[0].Cards[1].Font.Own and (NoteLayout.Lines('')[0].Cards[1].Font.Family = 'Georgia') and
    (NoteLayout.Lines('')[0].Cards[1].Font.Size = 13) and NoteLayout.Lines('')[0].Cards[1].Font.Italic and
    not NoteLayout.Lines('')[0].Cards[1].Font.Bold and (NoteLayout.Lines('')[0].Cards[1].Look <> nil) and
    not NoteLayout.Lines('')[0].Cards[2].Font.Extra and not NoteLayout.Lines('')[0].Cards[2].Font.Own,
    'a note''s font read: the extra text, its own (family, size, italic), the items'' when not given; its style kept');
  Check((NoteLayout <> nil) and (NoteLayout.Lines('')[0].Cards[3].Look <> nil) and
    (NoteLayout.Lines('')[0].Cards[3].Look.GetValue('border3d') <> nil) and (NoteLayout.Lines('')[0].Cards[3].Look.GetValue('shadow') <> nil),
    'a card''s 3D border and shadow kept in its look');
  // a divider's own look (plan 03 3.8)
  NoteLayout := ParseLayout('{ "format": 1, "lines": [ { "divider": "A", "height": 30, "border": "none", "foreground": "#ff0000", ' +
    '"font": { "size": 14, "bold": true } }, { "divider": "" }, { "line": [ ' + Remaining + ' ] } ] }', 'test', NoteError);
  Check((NoteLayout <> nil) and (NoteLayout.Lines('')[0].DividerHeight = 30) and (NoteLayout.Lines('')[0].DividerLook <> nil) and
    (NoteLayout.Lines('')[0].DividerLook.GetValue('border') <> nil) and NoteLayout.Lines('')[0].DividerFont.Own and
    (NoteLayout.Lines('')[0].DividerFont.Size = 14) and NoteLayout.Lines('')[0].DividerFont.Bold and
    (NoteLayout.Lines('')[1].DividerHeight = 0) and (NoteLayout.Lines('')[1].DividerLook = nil) and
    not NoteLayout.Lines('')[1].DividerFont.Own, 'a divider''s own height, colours and font read; none when not given');
  // a note's date and time placeholders (plan 03 3.6), at a fixed moment
  When := EncodeDate(2026, 11, 23) + EncodeTime(14, 5, 9, 0);
  Check(FillNote('{date:yyyy-MM-dd} {time:HH:mm}', When) = '2026-11-23 14:05', 'a note: {date:...} and {time:...} in Windows'' pictures');
  Check(FillNote('{time:HH:mm:ss}', When) = '14:05:09', '... with seconds');
  Check((FillNote('{date}', When) <> '') and (Pos('{', FillNote('{date}', When)) = 0) and (FillNote('{time}', When) <> '') and
    (Pos('{', FillNote('{time}', When)) = 0), '{date} and {time}: the short formats');
  Check(FillNote('a {{b}} c', When) = 'a {b} c', '{{ and }}: a brace');
  Check(FillNote('{other} and {date', When) = '{other} and {date', 'an unknown placeholder, a brace not closed: as typed');
  Check(FillNote('no braces', When) = 'no braces', 'a note without placeholders: as it is');
end;

procedure TestCurrent;
var
  Path, Error: string;
  L: ILayout;
  Stamp: TDateTime;
  ToWindows: Boolean;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-layout.json');
  SetEnvironmentVariable('DEXMENU_LAYOUT_FILE', PChar(Path));
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and (L.Source = '(built in)'), 'no layout file: the built-in base layout');

  TFile.WriteAllText(Path, '{ "default": [ { "line": [ { "card": "First", "rules": [ "remaining" ] } ] } ] }');
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and (L.Lines('default')[0].Cards[0].Title = 'First'), 'the layout file read');
  Check((L <> nil) and (L.Lines('folder') = L.Lines('default')), 'one menu for every kind');

  Stamp := TFile.GetLastWriteTime(Path);
  TFile.WriteAllText(Path, '{ "default": [ { "line": [ { "card": "Second", "rules": [ "remaining" ] } ] } ] }');
  TFile.SetLastWriteTime(Path, Stamp + 1 / 86400);
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and (L.Lines('default')[0].Cards[0].Title = 'Second'), 'read again when the file changed');

  TFile.WriteAllText(Path, '{ "default": [ ');
  TFile.SetLastWriteTime(Path, Stamp + 2 / 86400);
  L := CurrentLayout('file', ToWindows, Error);
  Check((L = nil) and (Error <> ''), 'a broken file: no layout, a reason (the menu is then Windows'' own)');
  TFile.Delete(Path);
  SetEnvironmentVariable('DEXMENU_LAYOUT_FILE', nil);
end;

// Which layout a kind of right-click gets (plan 05 3.2): settings.json's "kinds" in their order, in a data folder of
// the test's own (DEXMENU_DATA).
procedure TestKinds;
var
  Data, Layouts: string;
  L: ILayout;
  Error: string;
  ToWindows: Boolean;

  function Title(const Kind: string): string;
  begin
    L := CurrentLayout(Kind, ToWindows, Error);
    if ToWindows then
      Result := '(windows)'
    else if L = nil then
      Result := '(error) ' + Error
    else
      Result := L.Lines('')[0].Cards[0].Title;
  end;

  procedure Layout(const Name: string);
  begin
    TFile.WriteAllText(TPath.Combine(Layouts, Name + '.json'), '{ "format": 1, "lines": [ { "line": [ { "card": "' +
      Name + '", "rules": [ "remaining" ] } ] } ] }');
  end;

begin
  Data := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-data');
  Layouts := TPath.Combine(Data, 'layouts');
  TDirectory.CreateDirectory(Layouts);
  SetEnvironmentVariable('DEXMENU_DATA', PChar(Data));
  Layout('Files');
  Layout('Dialog');
  Layout('Default');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "kinds": [ ' +
    '{ "kind": "dialog-file", "layout": "Dialog" }, { "kind": "dialog-folder" }, { "kind": "file", "layout": "Files" }, ' +
    '{ "kind": "drive", "layout": "none" }, { "kind": "default", "layout": "Default" } ] }');
  Check(Title('file') = 'Files', 'a kind set: its layout');
  Check(Title('folder') = 'Default', 'a kind not listed: default''s');
  Check(Title('dialog-file') = 'Dialog', 'a file in a dialog: the dialog kind first in the order');
  Check(Title('dialog-folder') = 'Default', 'a dialog kind not set: the next that fits (default)');
  Check(Title('drive') = '(windows)', 'none: Windows'' own menu');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "kinds": [ ' +
    '{ "kind": "file", "layout": "Files" }, { "kind": "dialog-file", "layout": "Dialog" }, { "kind": "default", "layout": "Default" } ] }');
  Check(Title('dialog-file') = 'Files', 'the order decides: file before dialog-file, so a file in a dialog gets Files');
  // a layout of a newer format: a note with the warning, then every item as cards (plan 05 3.1.1)
  TFile.WriteAllText(TPath.Combine(Layouts, 'Newer.json'), '{ "format": 99, "lines": [] }');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "kinds": [ { "kind": "default", "layout": "Newer" } ] }');
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and L.Lines('')[0].Cards[0].IsNote and (Pos('needs updating', L.Lines('')[0].Cards[0].NoteText) > 0) and
    L.Lines('')[1].Cards[0].IsRemaining, 'a newer format: a note with the warning, then the remaining card');
  // the global menu settings (plan 02 3.4): how submenus open, on a click only
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "menu": { "submenus": "replace", "onClickOnly": true } }');
  Check((MenuSettings.Submenus = smReplace) and MenuSettings.OnClickOnly, 'the menu settings read: replace, on a click only');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ }');
  Check((MenuSettings.Submenus = smNext) and not MenuSettings.OnClickOnly, 'no menu settings: next to the card, on hover');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "menu": { "submenuMark": ">", "actionMark": "-", "states": "enabled", ' +
    '"widths": [ { "min": 240, "max": 520 }, { "min": 180, "max": 360 } ] } }');
  with MenuSettings do
    Check((SubmenuMark = '>') and (ActionMark = '-') and (States = [stEnabled]) and (Length(Widths) = 2) and
      (Widths[0].MinW = 240) and (Widths[1].MaxW = 360), 'marks, a rule''s default states and the widths per level read');
  Check(MenuSettings.TextSize = 1, 'no text size: 1');
  SaveTextSize(1.34);
  Check((Abs(MenuSettings.TextSize - 1.3) < 0.001) and (MenuSettings.SubmenuMark = '>') and (MenuSettings.States = [stEnabled]),
    'the text size saved (to a tenth), the other settings kept');
  SaveTextSize(9);
  Check(Abs(MenuSettings.TextSize - MaxTextSize) < 0.001, 'the text size within its bounds');
  L := CurrentLayout('file', ToWindows, Error);
  TFile.WriteAllText(TPath.Combine(Layouts, 'Rules.json'), '{ "format": 1, "lines": [ { "line": [ { "card": "A", "rules": [ ' +
    '{ "name": { "equals": "x" } } ] } ] }, { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "kinds": [ { "kind": "default", "layout": "Rules" } ], ' +
    '"menu": { "states": "enabled" } }');
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and (L.Lines('')[0].Cards[0].Rules[0].Spec.States = [stEnabled]), 'a rule without states takes the default (enabled)');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "kinds": [ { "kind": "default", "layout": "Rules" } ] }');
  L := CurrentLayout('file', ToWindows, Error);
  Check((L <> nil) and (L.Lines('')[0].Cards[0].Rules[0].Spec.States = [stEnabled, stDisabled]),
    'the default changed: the layout read again (both)');
  TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "layout": "Files" }');
  Check(Title('folder') = 'Files', 'the older setting ("layout"): that layout for every kind');
  TDirectory.Delete(Data, True);
  SetEnvironmentVariable('DEXMENU_DATA', nil);
end;


// ---- the rules on a menu made here (plan 02 3.12) ----------------------------------------------------------------

var
  NextId: UINT = 1;

procedure Add(Menu: HMENU; const Text: string; Disabled: Boolean = False; Sub: HMENU = 0; IsDefault: Boolean = False);
var
  Item: TItem;
begin
  Item := Default(TItem);
  Item.Info.cbSize := SizeOf(TMenuItemInfoW);
  if Text = '-' then
    Item.Info.fType := MFT_SEPARATOR
  else
  begin
    Item.Info.fType := MFT_STRING;
    Item.Info.wID := NextId;
    Inc(NextId);
    Item.Text := Text;
    Item.HasText := True;
    if Disabled then
      Item.Info.fState := MFS_DISABLED;
    if IsDefault then
      Item.Info.fState := Item.Info.fState or MFS_DEFAULT;
    Item.Info.hSubMenu := Sub;
  end;
  InsertAtEnd(Menu, Item);
end;

// Open, Open with > (Notepad, Paint), -, Edit in LexPen, View in LexPen, Disabled thing (disabled),
// 7-Zip > (Add to archive..., Extract here, CRC SHA > (CRC-32, SHA-256)), -, Cut, Copy, Delete, Properties
function TestMenu: HMENU;
var
  OpenWith, Zip, Crc: HMENU;
begin
  OpenWith := CreatePopupMenu;
  Add(OpenWith, 'Notepad');
  Add(OpenWith, 'Paint');
  Crc := CreatePopupMenu;
  Add(Crc, 'CRC-32');
  Add(Crc, 'SHA-256');
  Zip := CreatePopupMenu;
  Add(Zip, '&Add to archive...');
  Add(Zip, 'E&xtract here');
  Add(Zip, 'CRC SHA', False, Crc);
  Result := CreatePopupMenu;
  Add(Result, '&Open', False, 0, True);
  Add(Result, 'Open &with', False, OpenWith);
  Add(Result, '-');
  Add(Result, 'Edit in LexPen');
  Add(Result, 'View in LexPen');
  Add(Result, 'Disabled thing', True);
  Add(Result, '7-Zip', False, Zip);
  Add(Result, '-');
  Add(Result, 'Cu&t');
  Add(Result, '&Copy'#9'Ctrl+C');
  Add(Result, '&Delete');
  Add(Result, 'P&roperties');
end;

// A level as text: lines with ' / ', cards in a line with ' | '; I: an item, M: a card with a menu, '-': a separator.
function Describe(Level: TViewLevel): string;
var
  L: TViewLine;
  V: TViewCard;
  Line: string;
begin
  Result := '';
  for L in Level.Lines do
  begin
    Line := '';
    for V in L.Cards do
    begin
      if Line <> '' then
        Line := Line + ' | ';
      case V.Kind of
        vkSeparator: if V.Divider <> nil then Line := Line + 'D:' + V.Divider.DividerText else Line := Line + '-';
        vkNote: Line := Line + 'N:' + V.Title;
        vkItem: Line := Line + 'I:' + V.Title;
        vkMenu: Line := Line + 'M:' + V.Title;
        vkCommand: Line := Line + 'C:' + V.Title;
        vkSearch: Line := Line + 'S:' + V.Title;
      else
        Line := Line + '-';
      end;
    end;
    if Result <> '' then
      Result := Result + ' / ';
    Result := Result + Line;
  end;
end;

type
  TLevelOf = reference to function(P: TPlacement): TViewLevel;

// The layout's default lines given as JSON text (the lines only); what TopLevel (or Pick) shows. A layout needs its one
// remaining card: lines without it get a card "(rest)" with a menu holding it, left out of the result.
function Shows(const Lines: string; const Pick: TLevelOf = nil): string;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error: string;
  P: TPlacement;
  Level: TViewLevel;
  Text: string;
begin
  Text := Lines;
  if Pos('"remaining"', Text) = 0 then
    Text := Copy(Text, 1, LastDelimiter(']', Text) - 1) + ', { "line": [ { "card": "(rest)", "menu": [ ' +
      '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] } ] } ]';
  Layout := ParseLayout('{ "default": ' + Text + ' }', 'test', Error);
  if Layout = nil then
    Exit('LAYOUT: ' + Error);
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    if Assigned(Pick) then
      Level := Pick(P)
    else
      Level := P.TopLevel;
    try
      Result := Describe(Level);
      Result := StringReplace(StringReplace(Result, ' / M:(rest)', '', []), 'M:(rest)', '', []);
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

const
  Rest = '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] }';
  RestMenu = '{ "line": [ { "card": "R", "menu": [ { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] } ] }';
  AllRest = 'I:Open / I:Open with / - / I:Edit in LexPen / I:View in LexPen / I:Disabled thing / I:7-Zip / - / I:Cut / I:Copy / I:Delete / I:Properties';

function Card(const Name, Rules: string; const Extra: string = ''): string;
begin
  Result := '{ "line": [ { "card": "' + Name + '"' + Extra + ', "rules": [ ' + Rules + ' ] } ] }';
end;

procedure Expect(const Got, Want, What: string);
begin
  Check(Got = Want, What);
  if Got <> Want then
  begin
    Writeln('     got:  ', Got);
    Writeln('     want: ', Want);
  end;
end;

// The submenu of the first top-level card titled Title.
function SubmenuOf(const Title: string): TLevelOf;
begin
  Result :=
    function(P: TPlacement): TViewLevel
    var
      Top: TViewLevel;
      L: TViewLine;
      V: TViewCard;
    begin
      Result := nil;
      Top := P.TopLevel;
      try
        for L in Top.Lines do
          for V in L.Cards do
            if (Result = nil) and (V.Title = Title) then
              case V.Kind of
                vkItem: begin ReadChildren(V.Node); Result := P.SubmenuLevel(V.Node); end;
                vkMenu: Result := P.MenuLevel(V.Card);
              end;
      finally
        Top.Free;
      end;
      if Result = nil then
        Result := TViewLevel.Create;
    end;
end;

// A Windows submenu found empty even when opened (Dexmenu.Menu at a right-click): its item is not shown; without that
// list (the preview) it is.
procedure TestEmptySubmenu;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error: string;
  P: TPlacement;
  Level: TViewLevel;
  Empty: TDictionary<HMENU, Boolean>;
begin
  Layout := ParseLayout('{ "default": [ ' + '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] }' + ' ] }', 'test', Error);
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  Empty := TDictionary<HMENU, Boolean>.Create;
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Empty.Add(GetSubMenu(Menu, 1), True);   // Open with's
    P.Empty := Empty;
    Level := P.TopLevel;
    try
      Check(Pos('Open with', Describe(Level)) = 0, 'an empty submenu''s item not shown at a right-click');
    finally
      Level.Free;
    end;
    P.Empty := nil;
    Level := P.TopLevel;
    try
      Check(Pos('I:Open with', Describe(Level)) > 0, '... shown without the list (the preview)');
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Empty.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// A card with a menu whose cards find nothing: left out at a right-click; in the preview shown, marked (striped).
procedure TestEmptyMenuCard;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error: string;
  P: TPlacement;
  Level: TViewLevel;
begin
  Layout := ParseLayout('{ "default": [ { "line": [ { "card": "Meta", "menu": [ { "line": [ { "card": "X", "rules": [ ' +
    '{ "name": { "equals": "No such item" } } ] } ] } ] } ] }, { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }',
    'test', Error);
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Level := P.TopLevel;
    try
      Check((Level.Lines[0].Cards[0].Kind = vkMenu) and Level.Lines[0].Cards[0].Sometimes,
        'a card with a menu showing nothing: in the preview shown, striped');
    finally
      Level.Free;
    end;
    P.AtRightClick := True;
    Level := P.TopLevel;
    try
      Check(Pos('M:Meta', Describe(Level)) = 0, '... left out at a right-click');
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// How a submenu opens (plan 02 3.7): a card's own "submenus" before the global setting; "<<" on top of a replacing
// level.
// The use counts (plan 02 3.9); a most used row of an earlier layout read as three used-rule cards (plan 09 6.5).
procedure TestUsage;
var
  Data, Error: string;
  I: Integer;
  U: TDictionary<string, Integer>;
  T: TDictionary<string, string>;
  Layout: ILayout;
  Menu: HMENU;
  Top: TNodes;
  P: TPlacement;
  Level: TViewLevel;
  Counts: TDictionary<string, Integer>;
begin
  Data := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-usage');
  if TDirectory.Exists(Data) then
    TDirectory.Delete(Data, True);
  SetEnvironmentVariable('DEXMENU_DATA', PChar(Data));
  for I := 1 to 3 do
    CountChoice('file', 'Copy');
  for I := 1 to 2 do
    CountChoice('file', '7-Zip > Add to archive...');
  CountChoice('file', 'Delete');
  CountChoice('file', 'Cut');
  for I := 1 to 9 do
    CountChoice('file', 'Disabled thing');
  for I := 1 to 5 do
    CountChoice('folder', 'Cut');
  U := ReadUsage('file');
  T := ReadLastUse('file');
  Layout := nil;
  P := nil;
  Top := nil;
  Menu := 0;
  try
    Check((U.Count = 5) and (U['Copy'] = 3) and (U['7-Zip > Add to archive...'] = 2) and (U['Cut'] = 1),
      'choices counted per item and kind of right-click');
    Check(ReadUsage('none-such').Count = 0, 'a kind without counts: none');
    Layout := ParseLayout('{ "default": [ { "mostUsed": true }, { "divider": true }, ' +
      '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
    Menu := TestMenu;
    Top := ReadLevel(Menu, '');
    P := TPlacement.Create(Layout, 'default', Top, U, T);
    Level := P.TopLevel;
    try
      Check(Copy(Describe(Level), 1, Length('I:Copy | I:Add to archive... | I:Cut / D: / I:Open')) =
        'I:Copy | I:Add to archive... | I:Cut / D: / I:Open',
        'an earlier layout''s most used row: three cards side by side, most first, a submenu''s item too, a disabled one left out');
    finally
      Level.Free;
    end;
    P.Free;
    P := TPlacement.Create(Layout, 'default', Top);
    Level := P.TopLevel;
    try
      Check(Copy(Describe(Level), 1, Length('I:Open')) = 'I:Open', 'no counts: nothing in its place, its divider not shown first');
    finally
      Level.Free;
    end;
    Check(UsesUsage(Layout, 'default') and UsageGoesDeeper(U), 'the layout uses the counts; a count inside a submenu');
    P.Free;
    P := nil;
    Layout := ParseLayout('{ "default": [ { "line": [ { "id": "x", "card": "X", "rules": [ { "name": { "equals": "Cut" } } ] }, ' +
      '{ "id": "z", "card": "Z", "rules": [ { "name": { "equals": "7-Zip" } } ] } ] }, ' +
      '{ "line": [ { "id": "r", "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
    P := TPlacement.Create(Layout, 'default', Top);
    P.Usage := U;
    Counts := P.CardCounts;
    try
      Check((Counts.Count = 3) and (Counts['x'] = 1) and (Counts['z'] = 2) and (Counts['r'] = 13),
        'the counts per card: its items, with what is in their submenus; the remaining card the rest');
    finally
      Counts.Free;
    end;
  finally
    P.Free;
    Top.Free;
    if Menu <> 0 then
      DestroyMenu(Menu);
    U.Free;
    T.Free;
    TDirectory.Delete(Data, True);
    SetEnvironmentVariable('DEXMENU_DATA', nil);
  end;
end;

// Used rules (docs/plans/executed/09-PLAN-used-rules.md): a rule finding the most used or most recently used items by rank; the
// time of last use kept with each choice.
procedure TestUsedRules;
var
  Data, Error: string;
  U: TDictionary<string, Integer>;
  T: TDictionary<string, string>;
  Menu: HMENU;
  Top: TNodes;

  function RuleValid(const Text: string): Boolean;
  var
    V: TJSONValue;
  begin
    V := TJSONObject.ParseJSONValue(Text);
    try
      Result := ParseRule(TJSONObject(V)).Valid;
    finally
      V.Free;
    end;
  end;

  // The top level of a layout of the given lines followed by the remaining card, with the counts and times above.
  function Placed(const Lines: string; WithUsage: Boolean = True): string;
  var
    Layout: ILayout;
    P: TPlacement;
    Level: TViewLevel;
  begin
    Layout := ParseLayout('{ "default": [ ' + Lines + ', { "divider": "rest" }, ' +
      '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
    if Layout = nil then
      Exit('layout: ' + Error);
    if WithUsage then
      P := TPlacement.Create(Layout, 'default', Top, U, T)
    else
      P := TPlacement.Create(Layout, 'default', Top);
    try
      Level := P.TopLevel;
      try
        Result := Describe(Level);
        if Pos(' / D:rest', Result) > 0 then
          Result := Copy(Result, 1, Pos(' / D:rest', Result) - 1)
        else
          Result := '';
      finally
        Level.Free;
      end;
    finally
      P.Free;
    end;
  end;

  function Card(const Name, Rule: string): string;
  begin
    Result := '{ "card": "' + Name + '", "rules": [ ' + Rule + ' ] }';
  end;

  function Line(const Cards: string): string;
  begin
    Result := '{ "line": [ ' + Cards + ' ] }';
  end;

const
  Enabled = '"states": [ "enabled" ]';
begin
  Check(RuleValid('{ "used": "most" }') and RuleValid('{ "used": "recent", "rank": 2 }') and
    RuleValid('{ "used": "most", "rank": "2" }') and RuleValid('{ "used": "most", "rank": "1-3" }') and
    RuleValid('{ "used": "most", "rank": "3-1" }') and RuleValid('{ "used": "most", "rank": " 2 - 5 " }'),
    'a used rule: no rank, a number, a text with one, a range, a range from high to low');
  Check(not RuleValid('{ "used": "most", "rank": 0 }') and not RuleValid('{ "used": "most", "rank": -1 }') and
    not RuleValid('{ "used": "most", "rank": "0-3" }') and not RuleValid('{ "used": "most", "rank": "3-0" }') and
    not RuleValid('{ "used": "most", "rank": "x" }') and not RuleValid('{ "used": "most", "rank": 1.5 }') and
    not RuleValid('{ "used": "most", "rank": "1,x" }') and not RuleValid('{ "used": "most", "rank": "0,1" }') and
    not RuleValid('{ "used": "most", "rank": "1,,2" }') and RuleValid('{ "used": "most", "rank": "1-2, 5-6, 8" }') and
    not RuleValid('{ "used": "often" }') and not RuleValid('{ "used": "most", "name": { "equals": "Cut" } }'),
    'a wrong used rule: a rank of 0 or lower, text, a fraction; an unknown kind; both name and used');
  Check(RuleValid('{ "used": "most", "scope": "anywhere", "path": { "contains": "x" }, "caseSensitive": true }'),
    'a used rule: scope, path and caseSensitive have no function (not an error)');

  // enabled: Copy 5, Cut 3 (23rd), Delete 3 (22nd), 7-Zip > Add to archive... 2 (23rd, the latest), Properties 1 (no
  // time); Disabled thing 9 (disabled); Gone 4 (not in this menu)
  U := TDictionary<string, Integer>.Create;
  T := TDictionary<string, string>.Create;
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  try
    U.Add('Copy', 5);
    U.Add('Cut', 3);
    U.Add('Delete', 3);
    U.Add('7-Zip > Add to archive...', 2);
    U.Add('Properties', 1);
    U.Add('Disabled thing', 9);
    U.Add('Gone', 4);
    T.Add('Copy', '2026-11-20T08:00:00.000Z');
    T.Add('Cut', '2026-11-23T10:00:00.000Z');
    T.Add('Delete', '2026-11-22T10:00:00.000Z');
    T.Add('7-Zip > Add to archive...', '2026-11-23T12:00:00.000Z');
    T.Add('Disabled thing', '2026-11-24T10:00:00.000Z');
    T.Add('Gone', '2026-11-25T10:00:00.000Z');
    Check(Placed(Line(Card('A', '{ "used": "most", ' + Enabled + ' }'))) =
      'I:Copy / I:Cut / I:Delete / I:Add to archive... / I:Properties',
      'most used, no rank: all, by count, a tie by the last use, an item in a submenu too, one not in the menu left out');
    Check(Placed(Line(Card('A', '{ "used": "most" }'))) =
      'I:Disabled thing / I:Copy / I:Cut / I:Delete / I:Add to archive... / I:Properties',
      'most used in the default states: the disabled item too');
    Check(Placed(Line(Card('A', '{ "used": "recent", "rank": "1-3", ' + Enabled + ' }'))) =
      'I:Add to archive... / I:Cut / I:Delete', 'most recent 1-3');
    Check(Placed(Line(Card('A', '{ "used": "recent", ' + Enabled + ' }'))) =
      'I:Add to archive... / I:Cut / I:Delete / I:Copy / I:Properties', 'most recent: an item without a time last');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": 3, ' + Enabled + ' }'))) = 'I:Delete', 'most used 3: the third');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "2-1", ' + Enabled + ' }'))) = 'I:Cut / I:Copy',
      'a range from high to low: the same items in reverse order');
    // ranks as a set, as pages to print
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "1,3,5", ' + Enabled + ' }'))) = 'I:Copy / I:Delete / I:Properties',
      'a set of ranks: 1,3,5');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "2,4", ' + Enabled + ' }'))) = 'I:Cut / I:Add to archive...',
      '... 2,4');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "1-2,5-6", ' + Enabled + ' }'))) = 'I:Copy / I:Cut / I:Properties',
      'ranges in a set: 1-2,5-6 (6 past the items)');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "3-1,5", ' + Enabled + ' }'))) = 'I:Delete / I:Cut / I:Copy / I:Properties',
      'a reversed range in a set, in the order written');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "7-2", ' + Enabled + ' }'))) =
      'I:Properties / I:Add to archive... / I:Delete / I:Cut', 'a reversed range partly past the items');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "4-9", ' + Enabled + ' }'))) =
      'I:Add to archive... / I:Properties', 'a range partly past the items');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": 6, ' + Enabled + ' }'))) = '',
      'a rank past the items: nothing found, the card not shown');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": 0 }'))) = '', 'a wrong rank: nothing found');
    Check(Placed(Line(Card('A', '{ "used": "most", "rank": "1-2", ' + Enabled + ' }') + ', ' +
      Card('B', '{ "used": "most", "rank": "1-3", ' + Enabled + ' }'))) = 'I:Copy / I:Cut / I:Delete',
      'ranks do not shift when an earlier rule took an item: 1-3 after 1-2 adds only the third');
    Check(Placed(Line(Card('X', '{ "name": { "equals": "Copy" } }')) + ', ' +
      Line(Card('A', '{ "used": "most", "rank": 1, ' + Enabled + ' }'))) = 'I:Copy',
      'the first ranked taken by an earlier rule: not shown again');
    Check(Placed(Line(Card('X', '{ "name": { "equals": "Copy" } }')) + ', ' +
      Line(Card('A', '{ "used": "most", "rank": 1, "also": true, ' + Enabled + ' }'))) = 'I:Copy / I:Copy',
      '... with also: shown again');
    Check(Pos('I:Copy', Copy(Placed(Line(Card('A', '{ "used": "most", "rank": 1, "consume": false, ' + Enabled +
      ' }')) + ', { "line": [ ' + Card('X', '{ "name": { "equals": "Copy" } }') + ' ] }'), 8, MaxInt)) > 0,
      'consume false: a later rule finds the item too');
    Check(Placed(Line(Card('A', '{ "used": "most" }')), False) = '', 'no use counts: a used rule finds nothing');
    Check(UsesUsage(ParseLayout('{ "default": [ ' + Line(Card('A', '{ "used": "recent" }')) + ', ' +
      Line(Card('Rest', '"remaining"')) + ' ] }', 'test', Error), 'default') and
      not UsesUsage(ParseLayout('{ "default": [ ' + Line(Card('A', '{ "name": { "equals": "Cut" } }')) + ', ' +
      Line(Card('Rest', '"remaining"')) + ' ] }', 'test', Error), 'default'),
      'a layout with a used rule uses the counts; one without does not');
  finally
    Top.Free;
    DestroyMenu(Menu);
    T.Free;
    U.Free;
  end;

  // the time of last use, written with each choice
  Data := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-used');
  if TDirectory.Exists(Data) then
    TDirectory.Delete(Data, True);
  TDirectory.CreateDirectory(Data);
  SetEnvironmentVariable('DEXMENU_DATA', PChar(Data));
  try
    TFile.WriteAllText(TPath.Combine(Data, 'usage.json'), '{ "format": 1, "kinds": { "file": { "Copy": 2 } } }');
    T := ReadLastUse('file');
    U := ReadUsage('file');
    try
      Check((T.Count = 0) and (U['Copy'] = 2), 'an older usage.json without times: the counts read, no times');
    finally
      T.Free;
      U.Free;
    end;
    CountChoice('file', 'Copy');
    T := ReadLastUse('file');
    U := ReadUsage('file');
    try
      Check((U['Copy'] = 3) and T.ContainsKey('Copy') and (Length(T['Copy']) = 24) and T['Copy'].EndsWith('Z') and
        (T['Copy'] <= UsageTimeNow), 'a choice: counted, and its time of last use kept (UTC)');
    finally
      T.Free;
      U.Free;
    end;
    T := ReadLastUse('folder');
    try
      Check(T.Count = 0, 'times per kind of right-click');
    finally
      T.Free;
    end;
  finally
    TDirectory.Delete(Data, True);
    SetEnvironmentVariable('DEXMENU_DATA', nil);
  end;
end;

// Icons (plan 02 3.8): a glyph by its code point, an icon in a file, a menu item's bitmap.
procedure TestIcons;
var
  Glyph: string;
  P: TIconPixels;
  BMI: TBitmapInfo;
  Bits: Pointer;
  Bmp: HBITMAP;
  I: Integer;
  AnyClear, AnyShown: Boolean;
begin
  Check(IsGlyph('E70F', Glyph) and (Glyph = #$E70F), 'a glyph by its code point in hex');
  Check(not IsGlyph('shell32.dll,4', Glyph) and not IsGlyph('', Glyph), 'a file and nothing are no glyph');
  Check(FileIconPixels('%SystemRoot%\System32\shell32.dll,4', 16, P) and (P.Width = 16) and (P.Height = 16),
    'an icon in a file, %variables% expanded, at the size asked');
  AnyClear := False;
  AnyShown := False;
  I := 3;
  while I < Length(P.Bits) do
  begin
    if P.Bits[I] = 0 then AnyClear := True;
    if P.Bits[I] = 255 then AnyShown := True;
    Inc(I, 4);
  end;
  Check(AnyClear and AnyShown, '... with its transparency');
  Check(not FileIconPixels('C:\no such file.dll,0', 16, P), 'a file that is not there: no icon');
  Check(not BitmapPixels(HBITMAP(-1), P) and not BitmapPixels(HBITMAP(8), P), 'HBMMENU_ values are no bitmap');
  FillChar(BMI, SizeOf(BMI), 0);
  BMI.bmiHeader.biSize := SizeOf(BMI.bmiHeader);
  BMI.bmiHeader.biWidth := 4;
  BMI.bmiHeader.biHeight := -4;
  BMI.bmiHeader.biPlanes := 1;
  BMI.bmiHeader.biBitCount := 32;
  Bmp := CreateDIBSection(0, BMI, DIB_RGB_COLORS, Bits, 0, 0);
  try
    FillChar(Bits^, 4 * 4 * 4, $80);
    for I := 0 to 15 do
      PByte(NativeUInt(Bits) + NativeUInt(I * 4 + 3))^ := 0;   // no alpha at all
    AnyShown := BitmapPixels(Bmp, P);
    Check(AnyShown and (P.Width = 4) and (P.Bits[3] = 255) and (P.Bits[0] = $80),
      'a bitmap without alpha: opaque, its colours kept (its handle may be below zero: sign-extended)');
  finally
    DeleteObject(Bmp);
  end;
end;

// Icons kept for the preview (plan 02 3.8): an item's bitmap saved as PNG by its key, read back with its pixels.
procedure TestKeptIcons;
var
  Folder: string;
  BMI: TBitmapInfo;
  Bits: Pointer;
  Bmp: HBITMAP;
  Menu: HMENU;
  Info: TMenuItemInfo;
  Top: TNodes;
  P: TIconPixels;
  I: Integer;
  Same: Boolean;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-seen');
  if TDirectory.Exists(Folder) then
    TDirectory.Delete(Folder, True);
  SetEnvironmentVariable('DEXMENU_SEEN_FOLDER', PChar(Folder));
  FillChar(BMI, SizeOf(BMI), 0);
  BMI.bmiHeader.biSize := SizeOf(BMI.bmiHeader);
  BMI.bmiHeader.biWidth := 16;
  BMI.bmiHeader.biHeight := -16;
  BMI.bmiHeader.biPlanes := 1;
  BMI.bmiHeader.biBitCount := 32;
  Bmp := CreateDIBSection(0, BMI, DIB_RGB_COLORS, Bits, 0, 0);
  Menu := CreatePopupMenu;
  Top := nil;
  try
    for I := 0 to 255 do   // left half opaque red, right half clear
      if I mod 16 < 8 then
        PCardinal(NativeUInt(Bits) + NativeUInt(I * 4))^ := $FFFF0000
      else
        PCardinal(NativeUInt(Bits) + NativeUInt(I * 4))^ := 0;
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    Info.fMask := MIIM_STRING or MIIM_ID or MIIM_BITMAP;
    Info.wID := 7;
    Info.dwTypeData := 'Edit in LexPen';
    Info.hbmpItem := Bmp;
    InsertMenuItem(Menu, 0, True, Info);
    Top := ReadLevel(Menu, '');
    SaveIcons(Top);
    Check(Length(TDirectory.GetFiles(TPath.Combine(Folder, 'icons'), '*.png')) = 1, 'an item''s bitmap kept as a PNG');
    ForgetKeptIcons;
    Same := KeptIconPixels('Edit in LexPen', P) and (P.Width = 16) and (P.Height = 16) and (Length(P.Bits) = 16 * 16 * 4);
    if Same then
      for I := 0 to 255 do
        if PCardinal(@P.Bits[I * 4])^ <> PCardinal(NativeUInt(Bits) + NativeUInt(I * 4))^ then
          Same := False;
    Check(Same, '... read back by its key with the same pixels');
    Check(not KeptIconPixels('No such item', P), 'an item without a kept icon: none');
  finally
    Top.Free;
    DestroyMenu(Menu);
    DeleteObject(Bmp);
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
    SetEnvironmentVariable('DEXMENU_SEEN_FOLDER', nil);
  end;
end;

// The access key and the shortcut of an item (plan 02 3.6): "Cu&t" underlines its t; a text after a tab is shown.
procedure TestAccessAndShortcut;
var
  Menu: HMENU;
  Top: TNodes;
  N: TNode;
  V: TViewCard;
  C: TCard;
  CutIndex, CopyIndex: Integer;
  CopyShortcut, CutShortcut: string;
begin
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  V := TViewCard.Create;
  C := TCard.Create;
  try
    V.Kind := vkItem;
    CutIndex := -2;
    CopyIndex := -2;
    for N in Top do
    begin
      V.Node := N;
      if N.Name = 'Cut' then
      begin
        CutIndex := V.AccessIndex;
        CutShortcut := V.Shortcut;
      end;
      if N.Name = 'Copy' then
      begin
        CopyIndex := V.AccessIndex;
        CopyShortcut := V.Shortcut;
      end;
    end;
    Check((CutIndex = 2) and (CutShortcut = ''), 'Cu&t: its t is the access key, no shortcut');
    Check((CopyIndex = 0) and (CopyShortcut = 'Ctrl+C'), '&Copy<tab>Ctrl+C: C the access key, Ctrl+C the shortcut');
    C.ShownTitle := 'Duplicate';
    V.Card := C;
    Check(V.AccessIndex = -1, 'a title of the layout''s own: no access key underlined');
  finally
    V.Card := nil;
    C.Free;
    V.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// The search (plan 02 3.6): items at any depth whose name holds the text, titled with their path; a regex.
procedure TestSearch;
var
  Layout: ILayout;
  Error: string;
  Menu: HMENU;
  Top: TNodes;
  P: TPlacement;

  function Search(const Text: string): string;
  var
    Level: TViewLevel;
  begin
    Level := P.SearchLevel(Text);
    try
      Result := Describe(Level);
    finally
      Level.Free;
    end;
  end;

begin
  Layout := ParseLayout('{ "default": [ { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Expect(Search('add'), 'S:Search: add / I:7-Zip > Add to archive...', 'a submenu''s item found, titled with its path');
    Expect(Search('C'), 'S:Search: C / I:7-Zip > Add to archive... / I:7-Zip > Extract here / I:7-Zip > CRC SHA > CRC-32 / ' +
      'I:Cut / I:Copy', 'case ignored; items with a submenu (7-Zip, CRC SHA) left out');
    Expect(Search('/^(cut|copy)$'), 'S:Search: /^(cut|copy)$ / I:Cut / I:Copy', 'a leading / : a regex');
    Expect(Search('/('), 'S:Search: /( / S:No item found', 'a regex not yet whole: nothing found, no error');
    Expect(Search('zzz'), 'S:Search: zzz / S:No item found', 'nothing found: said so');
    Expect(Shows('[ { "search": true }, ' + Rest + ' ]'), 'S:Search... / ' + AllRest, 'a layout''s search box where it stands');
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// Themes (plan 03 3.2, 3.3): colours, the intensity mix, a theme on a base, the theme chosen in the settings.
procedure TestThemes;
var
  C: TRGBA;
  T: TTheme;
  Error, Data: string;
  Lookup: TFunc<string, string>;
  Stops: TArray<TRGBA>;
  Angle: Single;
  Own, None, NoBorder: TJSONObject;

  function Near(const A: TRGBA; R, G, B: Integer; Alpha: Single = 1): Boolean;
  begin
    Result := (Abs(A.R * 255 - R) <= 1) and (Abs(A.G * 255 - G) <= 1) and (Abs(A.B * 255 - B) <= 1) and
      (Abs(A.A - Alpha) < 0.01);
  end;

begin
  Check(ParseColor('#f00', C) and Near(C, 255, 0, 0), '#rgb');
  Check(ParseColor('#161c27', C) and Near(C, $16, $1C, $27), '#rrggbb');
  Check(ParseColor('#ff000080', C) and Near(C, 255, 0, 0, 128 / 255), '#rrggbbaa');
  Check(ParseColor('rgba(106, 168, 255, .18)', C) and Near(C, 106, 168, 255, 0.18), 'rgba()');
  Check(not ParseColor('surface', C) and not ParseColor('#12345', C), 'a name or a bad colour is no colour');
  Check(Near(Intensity(RGBA(0, 0, 0), RGBA($C0, $20, $20), 0), 0, 0, 0) and
    Near(Intensity(RGBA(0, 0, 0), RGBA($C0, $20, $20), 100), $C0, $20, $20) and
    Near(Intensity(RGBA(0, 0, 0), RGBA($C0, $20, $20), 150), 224, 144, 144) and
    Near(Intensity(RGBA(0, 0, 0), RGBA($C0, $20, $20), 200), 255, 255, 255),
    'intensity on black: 0 black, 100 the colour, 150 rose, 200 white (the base inverted)');
  Check(Near(Intensity(RGBA(255, 255, 255), RGBA($20, $60, $C0), 200), 0, 0, 0) and
    Near(Intensity(RGBA(255, 255, 255), RGBA(0, 0, 0), 50), 128, 128, 128),
    'intensity on white: 200 black, 50 halfway');
  Lookup := function(Name: string): string
    begin
      if Name = 'dark' then
        Result := '{ "name": "dark", "palette": { "basecolor": "#000000", "text": "#ffffff", "accent": "#0000ff" }, ' +
          '"card": { "normal": { "foreground": "text", "radius": 4 }, "hover": { "background": "accent" } } }'
      else
        Result := '';
    end;
  T := ThemeFromText('{ "palette": { "basecolor": "#000000", "a": "#ff0000" }, "menu": { "normal": { "background": ' +
    '{ "gradient": [ "a", { "color": "a", "intensity": 0 }, "#0000ff" ], "angle": 0 } } } }', Lookup, Error);
  try
    Check(T.Background('menu', 'normal', Stops, Angle) and (Length(Stops) = 3) and Near(Stops[0], 255, 0, 0) and
      Near(Stops[1], 0, 0, 0) and Near(Stops[2], 0, 0, 255) and (Angle = 0), 'a gradient: its colours resolved, its angle');
    Check(not T.Background('card', 'normal', Stops, Angle), 'no background given: none');
  finally
    T.Free;
  end;
  T := ThemeFromText('// on dark' + #10 + '{ "name": "Red", "base": "dark", "palette": { "text": "#ff0000" }, ' +
    '"card": { "normal": { "background": { "color": "text", "intensity": 150, "opacity": 40 } }, ' +
    '"disabled": { "foreground": "nosuch" } } }', Lookup, Error);
  try
    Check((T <> nil) and (T.Name = 'Red'), 'a theme on a base read: ' + Error);
    if T <> nil then
    begin
      Check(Near(T.Color('card', 'normal', 'foreground', RGBA(0, 0, 0)), 255, 0, 0),
        'a palette change recolours what uses it (the base''s foreground: text, now red)');
      Check(Near(T.Color('card', 'hover', 'background', RGBA(0, 0, 0)), 0, 0, 255), 'the base''s own value kept');
      Check(Near(T.Color('card', 'normal', 'background', RGBA(0, 0, 0)), 255, 128, 128, 0.4),
        'intensity 150 over black and opacity 40: rose, 40% see-through');
      Check(Near(T.Color('card', 'focused', 'foreground', RGBA(1, 2, 3)), 255, 0, 0), 'a state not given: normal''s');
      Check(Near(T.Color('card', 'disabled', 'foreground', RGBA(1, 2, 3)), 1, 2, 3) and (Pos('nosuch', T.Problems) > 0),
        'an unknown palette name: the default used, the problem noted');
      Check(T.Number('card', 'hover', 'radius', 0) = 4, 'a number from normal');
      Check(T.Background('card', 'normal', Stops, Angle) and (Length(Stops) = 1) and Near(Stops[0], 255, 128, 128, 0.4),
        'a colour background: one colour');
    end;
  finally
    T.Free;
  end;
  // a card alone on its line ("item") takes what it does not give from "card"; a card's own look over the theme's
  // (plan 03 3.5 - 3.7)
  T := ThemeFromText('{ "base": "dark", "item": { "normal": { "foreground": "#00ff00" } }, ' +
    '"card": { "normal": { "background": "#111111" } } }', Lookup, Error);
  Own := TJSONObject.ParseJSONValue('{ "background": "#ff0000", "hover": { "foreground": "#0000ff" } }') as TJSONObject;
  None := TJSONObject.ParseJSONValue('{ "background": "none" }') as TJSONObject;
  NoBorder := TJSONObject.ParseJSONValue('{ "border": "none" }') as TJSONObject;
  try
    Check(Near(T.Color('item', 'normal', 'foreground', RGBA(0, 0, 0)), 0, 255, 0) and
      Near(T.Color('item', 'hover', 'background', RGBA(0, 0, 0)), 0, 0, 255) and (T.Number('item', 'normal', 'radius', 0) = 4),
      'an item: its own value, else the card''s (hover background, radius)');
    Check(Near(T.Color('card', 'normal', 'background', RGBA(0, 0, 0), Own), 255, 0, 0) and
      Near(T.Color('card', 'hover', 'background', RGBA(0, 0, 0), Own), 0, 0, 255) and
      Near(T.Color('card', 'hover', 'foreground', RGBA(0, 0, 0), Own), 0, 0, 255) and
      Near(T.Color('card', 'normal', 'foreground', RGBA(0, 0, 0), Own), 255, 255, 255),
      'a card''s own look: its background over the theme''s, the theme''s hover over its normal, its own hover first');
    Check(T.Background('card', 'hover', Stops, Angle, nil, True) and not T.Background('card', 'pressed', Stops, Angle, nil, True),
      'a state''s own background only: hover given, pressed not');
    Check(not T.Background('card', 'normal', Stops, Angle, None), 'a card''s background "none": none drawn');
    Check((T.Color('card', 'normal', 'border', RGBA(0, 0, 0, -1), None).A < 0) and
      (T.Color('card', 'normal', 'border', RGBA(0, 0, 0, -1), TJSONObject(None)).A < 0),
      'a border not set: the default (told apart from none)');
    Check(T.Color('card', 'normal', 'border', RGBA(0, 0, 0, -1), NoBorder).A = 0, 'a border "none": no colour (no line drawn)');
  finally
    NoBorder.Free;
    None.Free;
    Own.Free;
    T.Free;
  end;
  // a card's own colour without "color": the theme's own colour there, adjusted (plan 03 3.6)
  T := ThemeFromText('{ "palette": { "basecolor": "#000000", "a": "#ff000080" }, "card": { "normal": { ' +
    '"background": "a", "foreground": "#0000ff" }, "hover": { "background": { "gradient": [ "#ffffff", "#00ff00" ] } } } }',
    Lookup, Error);
  Own := TJSONObject.ParseJSONValue('{ "background": { "intensity": 50 }, "foreground": { "opacity": 40 }, ' +
    '"hover": { "background": { "intensity": 50, "opacity": 100 } } }') as TJSONObject;
  try
    Check(Near(T.Color('card', 'normal', 'background', RGBA(0, 0, 0), Own), 128, 0, 0, 128 / 255),
      'the theme''s colour with an intensity: mixed towards the base colour, its own alpha kept');
    Check(Near(T.Color('card', 'normal', 'foreground', RGBA(0, 0, 0), Own), 0, 0, 255, 0.4),
      'the theme''s colour with an opacity: overruled');
    Check(T.Background('card', 'normal', Stops, Angle, Own) and (Length(Stops) = 1) and Near(Stops[0], 128, 0, 0, 128 / 255),
      'the theme''s background with an intensity');
    Check(T.Background('card', 'hover', Stops, Angle, Own, True) and (Length(Stops) = 2) and Near(Stops[0], 128, 128, 128) and
      Near(Stops[1], 0, 128, 0), 'the theme''s gradient with an intensity: each of its colours');
  finally
    Own.Free;
    T.Free;
  end;
  // the theme the settings name, from the user's themes folder
  Data := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-themes');
  if TDirectory.Exists(Data) then
    TDirectory.Delete(Data, True);
  TDirectory.CreateDirectory(TPath.Combine(Data, 'themes'));
  SetEnvironmentVariable('DEXMENU_DATA', PChar(Data));
  try
    TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "menu": { "themeDark": "Mine" } }');
    TFile.WriteAllText(TPath.Combine(TPath.Combine(Data, 'themes'), 'Mine.json'),
      '{ "name": "Mine", "base": "dark", "palette": { "text": "#00ff00" } }');
    Check(Near(CurrentTheme(True).Color('card', 'normal', 'foreground', RGBA(0, 0, 0)), 0, 255, 0),
      'the dark theme the settings name, from the user''s themes folder, on the built-in dark');
    Check(Near(CurrentTheme(False).Color('card', 'normal', 'foreground', RGBA(0, 0, 0)), $1B, $1B, $1B),
      'light not named: the built-in light');
    for var Shipped in ['light-parchment', 'dark-parchment', 'light-sky', 'dark-ocean', 'light-seafoam', 'dark-forest'] do
    begin
      TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "menu": { "themeLight": "' + Shipped + '" } }');
      Check((CurrentTheme(False).Name = Shipped) and (CurrentTheme(False).Problems = '') and
        (CurrentTheme(False).Color('card', 'normal', 'background', RGBA(0, 0, 0, 0)).A = 1),
        'the shipped theme ' + Shipped + ': read without problems, its cards with a background');
    end;
    TFile.WriteAllText(TPath.Combine(Data, 'settings.json'), '{ "menu": { "themeDark": "Gone" } }');
    Check(Near(CurrentTheme(True).Color('card', 'normal', 'foreground', RGBA(0, 0, 0)), 255, 255, 255),
      'a theme that is not there: the built-in dark');
  finally
    TDirectory.Delete(Data, True);
    SetEnvironmentVariable('DEXMENU_DATA', nil);
  end;
end;

procedure TestSubmenuModes;
var
  C: TCard;
  V: TViewCard;
  Settings: TMenuSettings;
  Level: TViewLevel;
begin
  C := TCard.Create;
  V := TViewCard.Create;
  Level := TViewLevel.Create;
  try
    C.Title := 'Tools';
    V.Kind := vkMenu;
    V.Card := C;
    Settings.Submenus := smUnder;
    Settings.OnClickOnly := False;
    Check(SubmenuModeOf(V, Settings) = smUnder, 'a card without its own: the global setting');
    C.SubmenuMode := smReplace;
    Check(SubmenuModeOf(V, Settings) = smReplace, 'a card''s own "submenus" overrules it');
    AddBackLine(Level, V);
    Check((Level.Lines.Count = 1) and (Level.Lines[0].Cards[0].Kind = vkBack) and (Level.Lines[0].Cards[0].Title = '<<  Tools') and
      Level.Lines[0].Cards[0].Enabled, '"<<" at the top of a replacing level, naming what it goes back from');
  finally
    Level.Free;
    V.Free;
    C.Free;
  end;
end;

procedure TestRules;
begin
  Expect(Shows('[ ' + Rest + ' ]'), AllRest, 'the remaining card alone: Windows'' menu as cards');
  Expect(Shows('[ ' + Card('LexPen', '{ "name": { "contains": "LexPen" } }') + ', ' + Rest + ' ]'),
    'I:Edit in LexPen / I:View in LexPen / I:Open / I:Open with / - / I:Disabled thing / I:7-Zip / - / I:Cut / I:Copy / I:Delete / I:Properties',
    'contains: two found, each placed where the card stands, in Windows'' order; the rest after them');
  Expect(Shows('[ ' + Card('LexPen', '{ "name": { "contains": "LexPen" } }', ', "title": "Mine"') + ' ]'),
    'I:Edit in LexPen / I:View in LexPen', 'several found: the card''s title is not theirs');
  Expect(Shows('[ { "line": [ { "card": "A", "rules": [ { "name": { "any": [ "Cut", "Copy" ] } } ] }, ' +
    '{ "card": "B", "rules": [ { "name": { "equals": "Delete" } } ] } ] } ]'), 'I:Cut / I:Copy / I:Delete',
    'several found by a card beside another: each on a line of its own, the other card after them');
  Expect(Shows('[ ' + Rest + ', ' + Card('Cut', '{ "name": { "equals": "Cut" } }') + ' ]'),
    'I:Open / I:Open with / - / I:Edit in LexPen / I:View in LexPen / I:Disabled thing / I:7-Zip / - / I:Copy / I:Delete / I:Properties / I:Cut',
    'equals, one found: the item itself, where its card stands (after the rest here)');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "cut" }, "caseSensitive": true }') + ', ' + Rest + ' ]'), AllRest,
    'case sensitive: "cut" finds nothing, the card is not shown');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "CUT" } }') + ' ]'), 'I:Cut', 'case insensitive by default');
  Expect(Shows('[ ' + Card('X', '{ "name": { "startsWith": "open" } }') + ' ]'), 'I:Open / I:Open with', 'startsWith');
  Expect(Shows('[ ' + Card('X', '{ "name": { "endsWith": "lexpen" } }') + ' ]'), 'I:Edit in LexPen / I:View in LexPen', 'endsWith');
  Expect(Shows('[ ' + Card('X', '{ "name": { "wildcard": "*in LexP?n" } }') + ' ]'), 'I:Edit in LexPen / I:View in LexPen', 'wildcard');
  Expect(Shows('[ ' + Card('X', '{ "name": { "regex": "^(Cut|Copy)$" } }') + ' ]'), 'I:Cut / I:Copy', 'regex');
  Expect(Shows('[ ' + Card('X', '{ "name": { "any": [ "Delete", "Cut" ] } }') + ' ]'), 'I:Cut / I:Delete',
    'any: one of a list, in Windows'' order');
  Expect(Shows('[ ' + Card('X', '{ "name": { "contains": "thing" }, "states": [ "enabled" ] }') + ' ]'), '',
    'states enabled: a disabled item not taken');
  Expect(Shows('[ ' + Card('X', '{ "name": { "contains": "thing" }, "states": [ "disabled" ] }') + ' ]'), 'I:Disabled thing',
    'states disabled: taken');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Extract here" } }') + ' ]'), '', 'scope top (default): not found deeper');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Extract here" }, "scope": "anywhere" }') + ', ' + Rest + ' ]'),
    'I:Extract here / ' + AllRest, 'scope anywhere: found in a submenu');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Extract here" }, "scope": "anywhere" }') + ', ' + Rest + ' ]',
    SubmenuOf('7-Zip')), 'I:Add to archive... / I:CRC SHA', 'a submenu shows what is left after a rule took an item');
  Expect(Shows('[ ' + Card('Zip', '{ "name": { "wildcard": "*" }, "path": { "equals": "7-Zip" } }') + ' ]'),
    'I:Add to archive... / I:Extract here / I:CRC SHA', 'path: the items in a submenu');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Cut" }, "scope": "top", "path": { "equals": "7-Zip" } }') + ' ]'), '',
    'a scope and a path: invalid, finds nothing');
  Check(not ParseRule(TJSONObject(TJSONObject.ParseJSONValue('{ "name": { "regex": "(" } }'))).Valid,
    'a regex that does not compile: invalid');

  // a found item takes its subitems; the priority list decides who gets an item
  Expect(Shows('[ ' + Card('Seven', '{ "name": { "equals": "7-Zip" }, "priority": 2 }') + ', ' +
    Card('Extract', '{ "name": { "equals": "Extract here" }, "scope": "anywhere", "priority": 1 }') + ' ]'),
    'I:7-Zip / I:Extract here', 'a deeper item''s rule first: both cards show');
  Expect(Shows('[ ' + Card('Seven', '{ "name": { "equals": "7-Zip" }, "priority": 2 }') + ', ' +
    Card('Extract', '{ "name": { "equals": "Extract here" }, "scope": "anywhere", "priority": 1 }') + ' ]', SubmenuOf('7-Zip')),
    'I:Add to archive... / I:CRC SHA', '... and the parent''s submenu keeps the rest');
  Expect(Shows('[ ' + Card('Seven', '{ "name": { "equals": "7-Zip" }, "priority": 1 }') + ', ' +
    Card('Extract', '{ "name": { "equals": "Extract here" }, "scope": "anywhere", "priority": 2 }') + ' ]'),
    'I:7-Zip', 'the parent''s rule first: it takes all its subitems, the later rule finds none');
  Expect(Shows('[ ' + Card('Seven', '{ "name": { "equals": "7-Zip" }, "priority": 1 }') + ', ' +
    Card('Extract', '{ "name": { "equals": "Extract here" }, "scope": "anywhere", "priority": 2 }') + ' ]', SubmenuOf('7-Zip')),
    'I:Add to archive... / I:Extract here / I:CRC SHA', '... with all of them in its submenu');
  Expect(Shows('[ ' + Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] }, "priority": 1 }') + ', ' +
    Card('Fav', '{ "name": { "equals": "Cut" }, "also": true, "priority": 2 }') + ' ]'), 'I:Cut / I:Copy / I:Cut',
    'also: shown in a second card too');
  Expect(Shows('[ ' + Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] }, "priority": 1 }') + ', ' +
    Card('Fav', '{ "name": { "equals": "Cut" }, "priority": 2 }') + ' ]'), 'I:Cut / I:Copy',
    'without also: a later rule does not get an item already taken');
  Expect(Shows('[ ' + Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] }, "consume": false, "priority": 1 }') + ', ' +
    Card('Fav', '{ "name": { "equals": "Cut" }, "priority": 2 }') + ' ]'), 'I:Cut / I:Copy / I:Cut',
    'consume false: a later rule gets the item too');
  Expect(Shows('[ ' + Card('Fav', '{ "name": { "equals": "Cut" }, "consume": false }') + ', ' + Rest + ' ]'),
    'I:Cut / ' + AllRest, 'consume false: the remaining card shows it too');
  Expect(Shows('[ ' + Card('Seven', '{ "name": { "equals": "7-Zip" }, "consume": false, "priority": 1 }') + ', ' +
    Card('Extract', '{ "name": { "equals": "Extract here" }, "scope": "anywhere", "priority": 2 }') + ' ]'),
    'I:7-Zip / I:Extract here', 'consume false: its subitems stay free too');
  Expect(Shows('[ ' + Card('Fav', '{ "name": { "equals": "Cut" } }') + ', ' +
    Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] } }') + ' ]'), 'I:Cut / I:Copy',
    'without priorities: the layout''s order (the first card gets Cut; the second holds only Copy)');

  // cards with a menu, the remaining card anywhere, titles
  Expect(Shows('[ ' + Card('LexPen', '{ "name": { "contains": "LexPen" } }') +
    ', { "line": [ { "card": "More", "menu": [ ' + Rest + ' ] } ] } ]'), 'I:Edit in LexPen / I:View in LexPen / M:More',
    'the remaining card inside a card with a menu: the rest there');
  Expect(Shows('[ ' + Card('LexPen', '{ "name": { "contains": "LexPen" } }') +
    ', { "line": [ { "card": "More", "menu": [ ' + Rest + ' ] } ] } ]', SubmenuOf('More')),
    'I:Open / I:Open with / - / I:Disabled thing / I:7-Zip / - / I:Cut / I:Copy / I:Delete / I:Properties',
    '... its submenu holds the rest');
  Expect(Shows('[ { "line": [ { "card": "Edit", "menu": [ ' + Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] } }') +
    ' ] } ] } ]', SubmenuOf('Edit')), 'I:Cut / I:Copy', 'a card with a menu holding a card with rules');
  Expect(Shows('[ { "line": [ { "card": "Open...", "menu": [ ' +
    Card('Open with', '{ "name": { "wildcard": "*" }, "path": { "equals": "Open with" } }') + ', ' +
    Card('Clip', '{ "name": { "equals": "Cut" } }') + ' ] } ] } ]', SubmenuOf('Open...')), 'I:Notepad / I:Paint / I:Cut',
    'a card with a menu: what a card found (an unknown number) at its place, beside a card of its own');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Cut" } }', ', "rename": { "regex": "^Cu", "replace": "Ku" }') + ' ]'),
    'I:Kut', 'rename: a regex replace on the item''s text');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Cut" } }', ', "title": "Snip"') + ' ]'), 'I:Snip',
    'title: a card''s own title for its one item');
  Expect(Shows('[ ' + Card('Nothing', '{ "name": { "equals": "No such item" } }') + ', ' + Rest + ' ]'), AllRest,
    'found none: the card is not shown');
  Expect(Shows('[ ' + Card('Skip', '{ "name": { "contains": "LexPen" } }', ', "hidden": true') + ', ' + Rest + ' ]'),
    'I:Open / I:Open with / - / I:Disabled thing / I:7-Zip / - / I:Cut / I:Copy / I:Delete / I:Properties',
    'hidden: its items show nowhere, not in the remaining card either');
  Expect(Shows('[ { "line": [ { "card": "More", "hidden": true, "menu": [ ' + Card('Clip', '{ "name": { "any": [ "Cut", "Copy" ] } }') +
    ' ] } ] }, ' + Rest + ' ]'), 'I:Open / I:Open with / - / I:Edit in LexPen / I:View in LexPen / I:Disabled thing / I:7-Zip / - / I:Delete / I:Properties',
    'a hidden card with a menu: the rules in it still take their items');
  Expect(Shows('[ { "line": [ { "card": "Rest", "hidden": true, "rules": [ "remaining" ] } ] } ]'), AllRest,
    'the remaining card cannot be hidden');
  // note cards (plan 02 3.3): placed where they stand, beside other cards too; no button
  // Dexmenu's own items (plan 02 3.6, 3.11): cards where the layout puts them, nowhere else
  Expect(Shows('[ { "line": [ { "note": "About" }, { "card": "Edit it...", "own": "editMenu" }, ' +
    '{ "card": "Windows", "own": "windowsMenu" } ] } ]'), 'N:About | C:Edit it... | C:Windows',
    'Dexmenu''s own items as cards, titled by the layout');
  // Dexmenu's own items found by rules (plan 12): in any card, among other items, as buttons; tagged as commands
  Expect(Shows('[ ' + Card('Ed', '{ "own": "editMenu" }') + ' ]'), 'C:Edit menu...', 'an own rule: Dexmenu''s item, its own text');
  Expect(Shows('[ ' + Card('Ed', '{ "own": "editMenu" }', ', "title": "Change this menu"') + ' ]'), 'C:Change this menu',
    'an own rule: the card''s title on it');
  Expect(Shows('[ ' + Card('Mix', '{ "name": { "equals": "Cut" }, "priority": 1 }, { "own": "windowsMenu", "priority": 2 }') + ' ]'),
    'I:Cut / C:Windows'' menu', 'an own rule beside a rule by name: several found, in the priority order');
  Expect(Shows('[ ' + Card('Mix', '{ "name": { "equals": "Cut" }, "priority": 2 }, { "own": "windowsMenu", "priority": 1 }') + ' ]'),
    'C:Windows'' menu / I:Cut', '... the other way round');
  Expect(Shows('[ ' + Card('Two', '{ "own": "editMenu" }, { "own": "editMenu" }') + ' ]'), 'C:Edit menu... / C:Edit menu...',
    'two rules with the same tag: the item twice');
  Expect(Shows('[ ' + Card('Bad', '{ "own": "somethingElse" }') + ' ]'), '', 'an unknown tag: the rule invalid, nothing found');
  Expect(Shows('[ ' + Card('Bad', '{ "own": "editMenu", "name": { "equals": "Cut" } }') + ' ]'), '',
    'an own rule with a name too: invalid');
  Expect(Shows('[ { "line": [ { "card": "X", "own": "nothing" } ] } ]'), 'LAYOUT: test "X": "own" is "windowsMenu" or "editMenu"',
    'an unknown own item: the layout refused');
  Expect(Shows('[ { "line": [ { "note": "Pick one" } ] }, { "line": [ { "card": "X", "rules": [ { "name": { "equals": "Cut" } } ] }, ' +
    '{ "note": "" } ] } ]'), 'N:Pick one / I:Cut | N:', 'notes: a text on a line of its own, an empty one beside a card');
  // dividers from the layout: kept where they are (also first); a Windows separator next to one goes
  Expect(Shows('[ { "divider": "Programs", "align": "left" }, ' + Card('X', '{ "name": { "equals": "Cut" } }') +
    ', { "divider": true }, ' + Card('Y', '{ "name": { "equals": "Copy" } }') + ' ]'), 'D:Programs / I:Cut / D: / I:Copy',
    'dividers, with a text and without, where the layout has them');
  Expect(Shows('[ ' + Card('X', '{ "name": { "equals": "Open" } }') + ', { "divider": "Rest" }, ' + Rest + ' ]'),
    'I:Open / D:Rest / I:Open with / - / I:Edit in LexPen / I:View in LexPen / I:Disabled thing / I:7-Zip / - / I:Cut / I:Copy / I:Delete / I:Properties',
    'a divider before the remaining items; no Windows separator right after it');
  // (the remaining card first, in a menu, so the helper adds none at the end)
  Expect(Shows('[ { "divider": true }, ' + RestMenu + ', ' + Card('X', '{ "name": { "equals": "Cut" } }') + ', { "divider": true }, { "divider": true }, ' +
    Card('Y', '{ "name": { "equals": "Copy" } }') + ', { "divider": true } ]'), 'M:R / I:Cut / D: / I:Copy',
    'a divider without text: not first, not last, not right after another');
  Expect(Shows('[ { "divider": "A" }, { "divider": "B" }, ' + Card('X', '{ "name": { "equals": "Cut" } }') + ', { "divider": "C" }, ' +
    '{ "divider": true }, ' + Card('Y', '{ "name": { "equals": "Copy" } }') + ' ]'), 'D:B / I:Cut / D:C / I:Copy',
    'a divider with text followed at once by another with text: not shown; one without text after it: not shown');
  Expect(Shows('[ ' + RestMenu + ', ' + Card('X', '{ "name": { "equals": "Cut" } }') + ', { "divider": true }, ' +
    Card('Nothing', '{ "name": { "equals": "No such item" } }') + ' ]'), 'M:R / I:Cut',
    'a divider left last because the card after it found nothing: not shown');
  Expect(Shows('[ ' + RestMenu + ', ' + Card('X', '{ "name": { "equals": "Cut" } }') + ', { "divider": "Gone" }, ' +
    Card('H', '{ "name": { "equals": "Copy" } }', ', "hidden": true') + ', { "divider": true } ]'), 'M:R / I:Cut',
    'a hidden card is not shown, so it is no item after a divider: both dividers end up last and go');
end;

// The seen items merged (Dexmenu.Seen): names, '*' for "sometimes", a submenu's items in [ ], '-' a separator.
function Items(const Text: string): TJSONArray;
begin
  Result := TJSONObject.ParseJSONValue(Text) as TJSONArray;
end;

function Shown(A: TJSONArray): string;
var
  V: TJSONValue;
  O: TJSONObject;
begin
  Result := '';
  for V in A do
  begin
    O := TJSONObject(V);
    if Result <> '' then
      Result := Result + ',';
    if O.GetValue('separator') <> nil then
    begin
      Result := Result + '-';
      Continue;
    end;
    Result := Result + O.GetValue('name').Value;
    if O.GetValue('sometimes') <> nil then
      Result := Result + '*';
    if O.GetValue('items') is TJSONArray then
      Result := Result + '[' + Shown(TJSONArray(O.GetValue('items'))) + ']';
  end;
end;

function Merged(const Old, New: string; MarkNew: Boolean): string;
var
  O, N, M: TJSONArray;
begin
  O := nil;
  if Old <> '' then
    O := Items(Old);
  N := Items(New);
  M := MergeSeen(O, N, MarkNew);
  try
    Result := Shown(M);
  finally
    M.Free;
    N.Free;
    O.Free;
  end;
end;

// Skip duplicates: a menu with two items of one name (Windows 11's newer and older copy of a program's item).
function ShowsOnDuplicates(const Lines: string): string;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error: string;
  P: TPlacement;
  Level: TViewLevel;
begin
  Layout := ParseLayout('{ "default": ' + Lines + ' }', 'test', Error);
  if Layout = nil then
    Exit('LAYOUT: ' + Error);
  Menu := CreatePopupMenu;
  Add(Menu, 'Rename with PowerRename');
  Add(Menu, 'Unlock');
  Add(Menu, 'Rename with Pow&erRename');
  Add(Menu, 'Unlock');
  Add(Menu, 'Other');
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Level := P.TopLevel;
    try
      Result := Describe(Level);
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

procedure TestDuplicates;
const
  RestLine = '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] }';
begin
  Expect(ShowsOnDuplicates('[ ' + Card('PR', '{ "name": { "contains": "PowerRename" } }') + ', ' + RestLine + ' ]'),
    'I:Rename with PowerRename / I:Rename with PowerRename / I:Unlock / I:Unlock / I:Other', 'without skipDuplicates: both copies');
  Expect(ShowsOnDuplicates('[ ' + Card('PR', '{ "name": { "contains": "PowerRename" }, "skipDuplicates": true }') + ', ' + RestLine + ' ]'),
    'I:Rename with PowerRename / I:Unlock / I:Unlock / I:Other', 'skipDuplicates on a rule: one copy; the other not in the rest either');
  Expect(ShowsOnDuplicates('[ ' + Card('Two', '{ "name": { "contains": "PowerRename" } }, { "name": { "equals": "Unlock" } }',
    ', "skipDuplicates": true') + ', ' + RestLine + ' ]'), 'I:Rename with PowerRename / I:Unlock / I:Other',
    'skipDuplicates on a card: one per name over all its rules');
end;

// A card's hint: its text in place of the item's own, or a regex on the item's own (added to).
procedure TestHints;
var
  V: TViewCard;
  C: TCard;
begin
  C := TCard.Create;
  V := TViewCard.Create;
  try
    V.Kind := vkItem;
    V.Card := C;
    Check(ShownHint(V, 'Own') = 'Own', 'no hint on the card: the item''s own');
    C.HintText := 'Mine';
    Check(ShownHint(V, 'Own') = 'Mine', 'a text hint in place of the item''s own');
    C.HintText := '';
    C.HintIsRegex := True;
    C.HintFrom := '^(.*)$';
    C.HintTo := '$1 (via LexPen)';
    Check(ShownHint(V, 'Own') = 'Own (via LexPen)', 'a regex hint added to the item''s own: ' + ShownHint(V, 'Own'));
  finally
    V.Free;
    C.Free;
  end;
end;

procedure TestSeen;
const
  ABC = '[ {"name":"A"}, {"name":"B"}, {"separator":true}, {"name":"C"} ]';
  ACD = '[ {"name":"A"}, {"name":"C"}, {"name":"D"} ]';
var
  Menu: HMENU;
  Error: string;
  Top: TNodes;
  Last: TJSONObject;
  Hints: TJSONArray;
  HintMap: TDictionary<string, string>;
begin
  Check(Merged(ABC, ACD, True) = 'A,B*,C,D*', 'merged: an old item missing now kept after the one it followed, ' +
    'a new one marked: ' + Merged(ABC, ACD, True));
  Check(Merged(ABC, ACD, False) = 'A,B*,C,D', 'within one right-click: only what was lost is marked: ' +
    Merged(ABC, ACD, False));
  Check(Merged('[ {"name":"A"}, {"separator":true}, {"name":"B"} ]', '[ {"name":"A"}, {"separator":true}, {"name":"C"} ]',
    True) = 'A,-,B*,C*', 'an old item after a separator stays after it: ' + Merged('[ {"name":"A"}, {"separator":true}, ' +
    '{"name":"B"} ]', '[ {"name":"A"}, {"separator":true}, {"name":"C"} ]', True));
  Check(Merged('', ABC, True) = 'A,B,-,C', 'nothing seen before: nothing marked: ' + Merged('', ABC, True));
  Check(Merged('[ {"name":"A","sometimes":true} ]', '[ {"name":"A"} ]', True) = 'A*', 'once not there, always marked');
  Check(Merged('[ {"name":"S","submenu":true,"items":[ {"name":"x"}, {"name":"y"} ]} ]',
    '[ {"name":"S","submenu":true} ]', True) = 'S[x,y]', 'a submenu not opened this time keeps what was seen in it');
  Check(Merged('[ {"name":"S","submenu":true,"items":[ {"name":"x"}, {"name":"y"} ]} ]',
    '[ {"name":"S","submenu":true,"items":[ {"name":"x"} ]} ]', True) = 'S[x,y*]', 'a submenu''s items merged too');
  Check(Merged('[ {"name":"Open"}, {"name":"Open"} ]', '[ {"name":"Open"} ]', True) = 'Open,Open*',
    'two items of one name: matched one to one');
  // hints: kept by a later right-click that has none; read back by submenu path and name
  Hints := MergeSeen(Items('[ {"name":"Cut","hint":"Removes it"} ]'), Items('[ {"name":"Cut"} ]'), True);
  try
    Check(Hints.ToJSON.Contains('"hint":"Removes it"'), 'a hint kept when a right-click has none');
  finally
    Hints.Free;
  end;
  HintMap := HintsOf('{ "items": [ {"name":"Cut","hint":"Removes it"}, {"name":"7-Zip","submenu":true,"items":[ ' +
    '{"name":"Add to archive...","hint":"Packs it"} ]} ] }');
  try
    Check((HintMap.Count = 2) and (HintMap[#9'Cut'] = 'Removes it') and (HintMap['7-Zip'#9'Add to archive...'] = 'Packs it'),
      'hints read back by submenu path and name');
  finally
    HintMap.Free;
  end;
  Last := TJSONObject.ParseJSONValue(RightClickJson('several', 'C:\x', ['C:\x\a.txt', 'C:\x\b'])) as TJSONObject;
  try
    Check((Last.GetValue('kind').Value = 'several') and (Last.GetValue('folder').Value = 'C:\x') and
      (TJSONArray(Last.GetValue('items')).Count = 2) and (TJSONArray(Last.GetValue('items')).Items[1].Value = 'C:\x\b'),
      'the last right-click as text: kind, folder, items');
  finally
    Last.Free;
  end;
  Menu := MenuFromSeen('{ "items": [ {"text":"A","name":"A"}, {"text":"B","name":"B","sometimes":true} ] }', Error);
  Top := ReadLevel(Menu, '');
  try
    Check((Top.Count = 2) and not Top[0].Sometimes and Top[1].Sometimes, 'the preview''s menu: "sometimes" read back');
  finally
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// The boxes of the note cards a layout's first lines place (plan 03 3.5), measured as the menu measures them; the
// remaining card is added at the end and its items left out. The menu's width: Width.
function NoteBoxes(const Lines: string; out Width: Single): TArray<TD2D1RectF>;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error: string;
  P: TPlacement;
  Level: TViewLevel;
  G: TGeometry;
  B: TBox;
begin
  Result := nil;
  Width := 0;
  Layout := ParseLayout('{ "format": 1, "lines": ' + Copy(Lines, 1, LastDelimiter(']', Lines) - 1) +
    ', { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
  if Layout = nil then
    Exit;
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Level := P.TopLevel;
    try
      G := Measure(Level);
      Width := G.Width;
      for B in G.Boxes do
        if B.Card.Kind = vkNote then
          Result := Result + [B.Rect];
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

function Near(A, B: Single): Boolean;
begin
  Result := Abs(A - B) < 0.01;
end;

procedure TestLinesAndCards;
var
  R: TArray<TD2D1RectF>;
  W: Single;
begin
  R := NoteBoxes('[ { "line": [ { "note": "a" }, { "note": "b", "weight": 3 } ] } ]', W);
  Check((Length(R) = 2) and Near((R[1].right - R[1].left), 3 * (R[0].right - R[0].left)) and
    Near(R[1].right - R[0].left, W - 2 * OuterPad), 'weights: the line''s width shared 1 : 3');
  R := NoteBoxes('[ { "line": [ { "note": "a", "minWidth": 150 }, { "note": "b" } ] } ]', W);
  Check((Length(R) = 2) and Near(R[0].right - R[0].left, Max(150, (W - 2 * OuterPad) / 2)) and
    Near(R[1].right - R[0].left, W - 2 * OuterPad), 'a minimum width kept, the other card takes the rest');
  R := NoteBoxes('[ { "line": [ { "note": "a", "minWidth": 200 }, { "note": "b", "minWidth": 200 }, ' +
    '{ "note": "c", "minWidth": 200 } ] } ]', W);
  Check((Length(R) = 3) and Near(R[0].top, R[1].top) and (R[2].top >= R[0].bottom) and Near(R[2].left, OuterPad) and
    (W >= 400 + 2 * OuterPad) and (W <= MaxWidth), 'a line too wide at its minimum widths: the level grows, the last card wraps');
  R := NoteBoxes('[ { "line": [ { "note": "a", "height": 2 }, { "note": "b", "cardFit": "center" }, { "note": "c" } ] } ]', W);
  Check((Length(R) = 3) and Near(R[0].bottom - R[0].top, 2 * ItemHeight) and
    Near(R[1].top - R[0].top, (R[0].bottom - R[0].top - (R[1].bottom - R[1].top)) / 2) and
    (R[1].bottom - R[1].top < 2 * ItemHeight) and Near(R[2].bottom - R[2].top, 2 * ItemHeight),
    'a fixed height of two lines; a card centred at its own height; another stretched to the line');
  R := NoteBoxes('[ { "line": [ { "note": "a", "height": 3 }, { "note": "b" }, { "note": "c", "cardFit": "top" } ], ' +
    '"cardFit": "bottom" } ]', W);
  Check((Length(R) = 3) and Near(R[1].bottom, R[0].bottom) and (R[1].top > R[0].top) and Near(R[2].top, R[0].top) and
    (R[2].bottom < R[0].bottom), 'the line''s fit (bottom), a card overruling it (top)');
  R := NoteBoxes('[ { "line": [ { "card": "Copy", "extra": "to the clipboard", "rules": [ { "name": { "equals": "Copy" } } ] }, ' +
    '{ "note": "a" } ] } ]', W);
  Check((Length(R) = 1) and Near(R[0].bottom - R[0].top, ItemHeight + 14),
    'a card with an extra text: its line one extra line higher');
  // a title that wraps (plan 03 3.5): a narrow card beside a wide note, the note stretched to the line's height
  R := NoteBoxes('[ { "line": [ { "card": "Copy", "title": "A rather long title that needs several lines here", ' +
    '"rules": [ { "name": { "equals": "Copy" } } ] }, { "note": "a", "weight": 4 } ] } ]', W);
  Check((Length(R) = 1) and (R[0].bottom - R[0].top < ItemHeight + 4), 'a long title without wrap: one line, cut');
  R := NoteBoxes('[ { "line": [ { "card": "Copy", "title": "A rather long title that needs several lines here", ' +
    '"wrap": true, "rules": [ { "name": { "equals": "Copy" } } ] }, { "note": "a", "weight": 4 } ] } ]', W);
  Check((Length(R) = 1) and (R[0].bottom - R[0].top > ItemHeight + 20), 'a long title that wraps: the card as high as its lines');
  R := NoteBoxes('[ { "line": [ { "card": "Copy", "title": "A rather long title that needs several lines here", ' +
    '"wrap": true, "height": 2, "rules": [ { "name": { "equals": "Copy" } } ] }, { "note": "a", "weight": 4 } ] } ]', W);
  Check((Length(R) = 1) and Near(R[0].bottom - R[0].top, 2 * ItemHeight), '... with a height: within its lines');
  R := NoteBoxes('[ { "line": [ { "card": "Copy", "title": "Short", "wrap": true, ' +
    '"rules": [ { "name": { "equals": "Copy" } } ] }, { "note": "a", "weight": 4 } ] } ]', W);
  Check((Length(R) = 1) and (R[0].bottom - R[0].top < ItemHeight + 4), 'a short title that wraps: one line, as any');
end;

// Items as buttons in a card (plan 02 3.3): a found submenu unfolded, its title the item's; found items without one
// buttons themselves, the card's title; the buttons inside their card, side by side; hit tests reach the buttons only.
// A card holding cards (plan 11): what shows inside it, line after line.
function InnerOf(V: TViewCard): TArray<TViewCard>;
var
  L: TViewLine;
  C: TViewCard;
begin
  Result := nil;
  if V.Inner <> nil then
    for L in V.Inner.Lines do
      for C in L.Cards do
        Result := Result + [C];
end;

// Cards holding content (docs/plans/executed/11-PLAN-cards-hold-content.md): format 2; holders in a row and a column, with
// limits and the rest in "More" or left out; shownWhen; templates by position and by rule; found items in a submenu;
// square; the holder's boxes inside.
procedure TestHolders;
const
  Rest = '{ "card": "Rest", "rules": [ "remaining" ] }';
var
  Menu: HMENU;
  Top: TNodes;
  Error: string;
  Layout: ILayout;
  Tops: TDictionary<Integer, Integer>;
  Titles_: string;

  // the top level of a format 2 layout with this content (and the remaining card), at a right-click or in the preview
  function Level(const Content: string; out P: TPlacement; AtRightClick: Boolean = True): TViewLevel;
  var
    Layout: ILayout;
  begin
    Result := nil;
    P := nil;
    Layout := ParseLayout('{ "format": 2, "menu": { "content": [ ' + Content + ', ' + Rest + ' ] } }', 'test', Error);
    if Layout = nil then
      Exit;
    P := TPlacement.Create(Layout, 'default', Top);
    P.AtRightClick := AtRightClick;
    Result := P.TopLevel;
  end;

  function Titles(const Cards: TArray<TViewCard>): string;
  var
    C: TViewCard;
  begin
    Result := '';
    for C in Cards do
      Result := Result + C.Title + ';';
  end;

  function Card(const Name, Rule: string; const More: string = ''): string;
  begin
    Result := '{ "card": "' + Name + '", "rules": [ ' + Rule + ' ]' + More + ' }';
  end;

var
  P: TPlacement;
  L, Sub: TViewLevel;
  V: TViewCard;
  G: TGeometry;
  I, Box: Integer;
  Inside: Boolean;
  Pic: TPicture;
  Plain, Ring: COLORREF;
begin
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  try
    // a row holder without a style: what a line was; its cards side by side inside it, drawn as nothing itself
    L := Level('{ "card": "Row", "show": "row", "content": [ ' + Card('Cut', '{ "name": { "equals": "Cut" } }') + ', ' +
      Card('Copy', '{ "name": { "equals": "Copy" } }') + ' ] }', P);
    try
      Check((L <> nil) and (L.Lines[0].Cards[0].Kind = vkGroup) and not L.Lines[0].Cards[0].Framed and
        (Titles(InnerOf(L.Lines[0].Cards[0])) = 'Cut;Copy;') and (L.Lines[0].Cards[0].Inner.Lines.Count = 1),
        'format 2: a row holder without a style, its cards side by side, no frame: ' + Error);
      G := Measure(L);
      Box := -1;
      for I := 0 to High(G.Boxes) do
        if G.Boxes[I].Card = L.Lines[0].Cards[0] then
          Box := I;
      Inside := (Box >= 0) and (Box + 2 <= High(G.Boxes)) and (G.Boxes[Box + 1].Rect.top >= G.Boxes[Box].Rect.top) and
        (G.Boxes[Box + 2].Rect.left > G.Boxes[Box + 1].Rect.left) and (G.Boxes[Box + 2].Rect.right <= G.Boxes[Box].Rect.right + 0.5);
      Check(Inside, 'its cards'' boxes follow its own, side by side inside it: ' + IntToStr(Box) + ' ' +
        Format('%.0f,%.0f,%.0f,%.0f / %.0f,%.0f,%.0f,%.0f / %.0f,%.0f,%.0f,%.0f', [G.Boxes[Box].Rect.left, G.Boxes[Box].Rect.top,
        G.Boxes[Box].Rect.right, G.Boxes[Box].Rect.bottom, G.Boxes[Box + 1].Rect.left, G.Boxes[Box + 1].Rect.top,
        G.Boxes[Box + 1].Rect.right, G.Boxes[Box + 1].Rect.bottom, G.Boxes[Box + 2].Rect.left, G.Boxes[Box + 2].Rect.top,
        G.Boxes[Box + 2].Rect.right, G.Boxes[Box + 2].Rect.bottom]));
    finally
      L.Free;
      P.Free;
    end;
    // a styled holder with a title: framed
    L := Level('{ "card": "Box", "title": "Edit", "background": "#ff0000", "content": [ ' +
      Card('Cut', '{ "name": { "equals": "Cut" } }') + ' ] }', P);
    try
      Check((L <> nil) and L.Lines[0].Cards[0].Framed and (L.Lines[0].Cards[0].Title = 'Edit'),
        'a holder with a style and a title: its frame and title (a column by default)');
    finally
      L.Free;
      P.Free;
    end;
    // found items inside a card in a row: templates by position, cycling
    L := Level(Card('Lex', '{ "name": { "endsWith": "in LexPen" } }', ', "show": "row", "templates": [ ' +
      '{ "background": "#ff0000" }, { "background": "#00ff00", "rename": { "regex": " in LexPen", "replace": "" } } ]'), P);
    try
      V := L.Lines[0].Cards[0];
      Check((V.Kind = vkGroup) and V.Framed and (Titles(InnerOf(V)) = 'Edit in LexPen;View;') and
        (InnerOf(V)[0].LookCard = V.Card.Templates[0]) and (InnerOf(V)[1].LookCard = V.Card.Templates[1]),
        'found items inside a card: each its template by position (the second renamed by its own): ' + Titles(InnerOf(V)));
    finally
      L.Free;
      P.Free;
    end;
    // templates by rule
    L := Level(Card('T', '{ "name": { "equals": "Cut" }, "template": 2 }, { "name": { "equals": "Copy" } }',
      ', "show": "row", "templatesBy": "rule", "templates": [ { "radius": 1 }, { "radius": 2 } ]'), P);
    try
      V := L.Lines[0].Cards[0];
      Check((Titles(InnerOf(V)) = 'Cut;Copy;') and (InnerOf(V)[0].LookCard = V.Card.Templates[1]) and
        (InnerOf(V)[1].LookCard = V.Card.Templates[0]), 'templates by rule: a rule''s own, else the first');
    finally
      L.Free;
      P.Free;
    end;
    // limits: a row 1 per row, 1 row: the last place "More" with the rest; rest none: left out
    L := Level(Card('Lex', '{ "name": { "endsWith": "in LexPen" } }', ', "show": "row", "perRow": 1, "rows": 1'), P);
    try
      V := InnerOf(L.Lines[0].Cards[0])[0];
      Check(V.IsMore and V.HasSubmenu and (V.Title = 'More'), 'more found than fit: the last place "More"');
      Sub := P.LevelOf(V);
      try
        Check(Describe(Sub) = 'I:Edit in LexPen / I:View in LexPen', '"More" opens the rest: ' + Describe(Sub));
      finally
        Sub.Free;
      end;
    finally
      L.Free;
      P.Free;
    end;
    L := Level(Card('Lex', '{ "name": { "endsWith": "in LexPen" } }', ', "show": "row", "perRow": 1, "rows": 1, "rest": "none"'), P);
    try
      Check(Titles(InnerOf(L.Lines[0].Cards[0])) = 'Edit in LexPen;', 'rest none: the rest left out');
    finally
      L.Free;
      P.Free;
    end;
    // a column with 2 per column: filled column by column
    L := Level(Card('Col', '{ "name": { "any": [ "Cut", "Copy", "Delete" ] } }', ', "show": "column", "perColumn": 2'), P);
    try
      V := L.Lines[0].Cards[0];
      Check((V.Inner.Lines.Count = 2) and (V.Inner.Lines[0].Cards.Count = 2) and (V.Inner.Lines[0].Cards[1].Title = 'Delete') and
        (V.Inner.Lines[1].Cards[0].Title = 'Copy'), 'a column of 2 per column: the third in the second column');
    finally
      L.Free;
      P.Free;
    end;
    // found items as a submenu
    L := Level(Card('Lex', '{ "name": { "endsWith": "in LexPen" } }', ', "show": "submenu"'), P);
    try
      V := L.Lines[0].Cards[0];
      Sub := P.LevelOf(V);
      try
        Check((V.Kind = vkMenu) and (V.Title = 'Lex') and (Describe(Sub) = 'I:Edit in LexPen / I:View in LexPen'),
          'found items as a submenu: the card its title, the items in it');
      finally
        Sub.Free;
      end;
    finally
      L.Free;
      P.Free;
    end;
    // shownWhen: a holder of only a note, left out at a right-click (action items only), shown with anyItem
    L := Level('{ "card": "Notes", "content": [ { "note": "about" } ] }', P);
    try
      Check((L.Lines.Count > 0) and (L.Lines[0].Cards[0].Kind <> vkGroup), 'a holder of only a note: left out (action items only)');
    finally
      L.Free;
      P.Free;
    end;
    L := Level('{ "card": "Notes", "shownWhen": "anyItem", "content": [ { "note": "about" } ] }', P);
    try
      Check(L.Lines[0].Cards[0].Kind = vkGroup, '... shown with anyItem');
    finally
      L.Free;
      P.Free;
    end;
    L := Level('{ "card": "Notes", "content": [ { "note": "about" } ] }', P, False);
    try
      Check((L.Lines[0].Cards[0].Kind = vkGroup) and L.Lines[0].Cards[0].Sometimes, '... in the preview shown, striped');
    finally
      L.Free;
      P.Free;
    end;
    // square: a template's inner cards as high as wide
    L := Level(Card('Sq', '{ "name": { "equals": "Cut" } }', ', "show": "row", "perRow": 2, "templates": [ { "square": true } ]'), P);
    try
      G := Measure(L);
      Inside := False;
      for I := 0 to High(G.Boxes) do
        if G.Boxes[I].Card.InGroup then
          Inside := Abs((G.Boxes[I].Rect.bottom - G.Boxes[I].Rect.top) - (G.Boxes[I].Rect.right - G.Boxes[I].Rect.left)) < 1;
      Check(Inside, 'a square template: its inner card as high as wide');
    finally
      L.Free;
      P.Free;
    end;
    // the menu as a card (plan 11 3.9): its cards in columns of 2, its own style and submenus default
    Layout := ParseLayout('{ "format": 2, "menu": { "id": "menu", "card": "Menu", "show": "column", "perColumn": 2, ' +
      '"background": "#102030", "submenus": "under", "content": [ ' + Card('Cut', '{ "name": { "equals": "Cut" } }') + ', ' +
      Card('Copy', '{ "name": { "equals": "Copy" } }') + ', ' + Card('Del', '{ "name": { "equals": "Delete" } }') + ', ' + Rest + ' ] } }',
      'test', Error);
    Check((Layout <> nil) and (Layout.MenuCard.PerColumn = 2) and (Layout.MenuCard.Look <> nil) and
      (Layout.MenuCard.SubmenuMode = smUnder), 'the menu card read: its columns, its style, its submenus: ' + Error);
    if Layout <> nil then
    begin
      P := TPlacement.Create(Layout, 'default', Top);
      L := P.TopLevel;
      try
        Check((L.MenuCard = Layout.MenuCard) and (L.Lines.Count = 2) and (L.Lines[0].Cards[0].Title = 'Cut') and
          (L.Lines[1].Cards[0].Title = 'Copy') and (L.Lines[0].Cards[1].Title = 'Delete'),
          'the menu''s cards in columns of 2, filled column by column: ' + Describe(L));
        G := Measure(L);
        Check(G.MenuCard = Layout.MenuCard, 'the menu window drawn in the menu card''s style');
      finally
        L.Free;
        P.Free;
      end;
    end;
    // a row that flows fills its card's width
    L := Level(Card('Four', '{ "name": { "any": [ "Edit in LexPen", "View in LexPen", "Properties", "Disabled thing" ] } }',
      ', "show": "row", "templates": [ { "wrap": true } ]'), P);
    try
      G := Measure(L);
      Box := -1;
      for I := 0 to High(G.Boxes) do
        if G.Boxes[I].Card = L.Lines[0].Cards[0] then
          Box := I;
      Check((Box >= 0) and (Abs(G.Boxes[Box + 4].Rect.right - (G.Boxes[Box].Rect.right - 6)) < 1),
        'the flowing row filled to its card''s width (less its padding)');
    finally
      L.Free;
      P.Free;
    end;
    // the keys' focus ring (plan 03 3.7): drawn on the selected card only while the keys moved it
    L := Level(Card('Cut', '{ "name": { "equals": "Cut" } }'), P);
    try
      G := Measure(L);
      Box := -1;
      for I := 0 to High(G.Boxes) do
        if (Box < 0) and (G.Boxes[I].Card.Kind = vkItem) then
          Box := I;
      Pic := Render(G, Box, 0, 1, G.Height);
      try
        Plain := GetPixel(Pic.DC, Round(G.Boxes[Box].Rect.left + 3), Round((G.Boxes[Box].Rect.top + G.Boxes[Box].Rect.bottom) / 2));
      finally
        Pic.Free;
      end;
      G.KeyFocus := True;
      Pic := Render(G, Box, 0, 1, G.Height);
      try
        Ring := GetPixel(Pic.DC, Round(G.Boxes[Box].Rect.left + 3), Round((G.Boxes[Box].Rect.top + G.Boxes[Box].Rect.bottom) / 2));
      finally
        Pic.Free;
      end;
      Check((Box >= 0) and (Ring <> Plain), Format('the keys'' focus ring on the selected card (%.6x, without it %.6x)', [Ring, Plain]));
    finally
      L.Free;
      P.Free;
    end;
    // six found items flowing: a grid, the same number on every row (not 3, 2, 1 by their text)
    L := Level(Card('Six', '{ "name": { "any": [ "Cut", "Copy", "Delete", "Properties", "Edit in LexPen", "View in LexPen" ] } }',
      ', "show": "row"'), P);
    try
      G := Measure(L);
      Titles_ := '';
      Tops := TDictionary<Integer, Integer>.Create;
      try
        for I := 0 to High(G.Boxes) do
          if G.Boxes[I].Card.InGroup then
          begin
            Box := Round(G.Boxes[I].Rect.top);
            if Tops.ContainsKey(Box) then Tops[Box] := Tops[Box] + 1 else Tops.Add(Box, 1);
          end;
        Inside := True;
        for Box in Tops.Values do
          Inside := Inside and (6 mod Box = 0) and (Box = 6 div Tops.Count);
        Check(Inside and (Tops.Count >= 1), Format('six flowing: %d rows of the same number', [Tops.Count]));
      finally
        Tops.Free;
      end;
    finally
      L.Free;
      P.Free;
    end;
    // errors
    Check(Pos('"show"', ErrorOf('{ "format": 2, "menu": { "content": [ { "card": "X", "show": "grid", "rules": [] }, ' + Rest + ' ] } }')) > 0,
      'an unknown show: the layout refused');
    Check(Pos('not both', ErrorOf('{ "format": 2, "menu": { "content": [ { "card": "X", "rules": [], "content": [] }, ' + Rest + ' ] } }')) > 0,
      'rules and content together: the layout refused');
    Check(Pos('"menu"', ErrorOf('{ "format": 2, "lines": [] }')) > 0, 'format 2 without its menu: refused');
  finally
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// Dexmenu's own items found by rules (plan 12): tagged with what the DLL starts; a button in a card with buttons; an own
// card of an earlier layout read as a card with an own rule.
procedure TestOwnRules;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error, Titles: string;
  P: TPlacement;
  Level: TViewLevel;
  B: TViewCard;
begin
  Layout := ParseLayout('{ "format": 1, "lines": [ { "line": [ ' +
    '{ "card": "LexPen", "buttons": true, "rules": [ { "name": { "endsWith": "in LexPen" } }, { "own": "editMenu" } ] } ] }, ' +
    '{ "line": [ { "card": "Back", "own": "windowsMenu" } ] }, ' +
    '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
  Check(Layout <> nil, 'a layout with own rules and an own card read: ' + Error);
  if Layout = nil then
    Exit;
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Level := P.TopLevel;
    try
      Check((Level.Lines.Count >= 2) and (Level.Lines[0].Cards[0].Kind = vkGroup), 'the buttons card: ' + Describe(Level));
      if (Level.Lines.Count < 2) or (Level.Lines[0].Cards[0].Kind <> vkGroup) then
        Exit;
      Titles := '';
      for B in InnerOf(Level.Lines[0].Cards[0]) do
        Titles := Titles + B.Title + ';';
      B := InnerOf(Level.Lines[0].Cards[0])[High(InnerOf(Level.Lines[0].Cards[0]))];
      Check((Titles = 'Edit in LexPen;View in LexPen;Edit menu...;') and (B.Kind = vkCommand) and (B.Command = ccEditMenu) and B.Enabled,
        'an own rule in a card with buttons: Dexmenu''s item a button, tagged editMenu: ' + Titles);
      B := Level.Lines[1].Cards[0];
      Check((B.Kind = vkCommand) and (B.Command = ccWindowsMenu) and (B.Title = 'Back') and (B.Rule <> nil),
        'an own card of an earlier layout: a card with an own rule, its name its title, tagged windowsMenu');
      Check(Pos('Edit menu', Describe(Level)) = 0, 'an own item is no item of Windows'': not among the remaining items');
      Check((InnerOf(Level.Lines[0].Cards[0])[High(InnerOf(Level.Lines[0].Cards[0]))].IconSpec = 'E70F') and
        (Level.Lines[1].Cards[0].IconSpec = 'E700'), 'Dexmenu''s own items: an icon of their own where the layout gives none');
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

procedure TestButtons;
var
  Menu: HMENU;
  Top: TNodes;
  Layout: ILayout;
  Error, Titles: string;
  P: TPlacement;
  Level: TViewLevel;
  G: TGeometry;
  Zip, Lex: TViewCard;
  I, ZipBox, Inside: Integer;
  B: TViewCard;
  Within: Boolean;
begin
  Layout := ParseLayout('{ "format": 1, "lines": [ { "line": [ ' +
    '{ "card": "Archive", "buttons": true, "rules": [ { "name": { "equals": "7-Zip" } } ] }, ' +
    '{ "card": "LexPen", "buttons": true, "rules": [ { "name": { "endsWith": "in LexPen" } } ] } ] }, ' +
    '{ "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] }', 'test', Error);
  Check(Layout <> nil, 'a layout with buttons cards read: ' + Error);
  if Layout = nil then
    Exit;
  Check(RulesLookDeeper(Layout, 'default'), 'a layout with a buttons card opens the submenus filled when opened');
  Menu := TestMenu;
  Top := ReadLevel(Menu, '');
  P := TPlacement.Create(Layout, 'default', Top);
  try
    Level := P.TopLevel;
    try
      Zip := nil;
      Lex := nil;
      if (Level.Lines.Count > 0) and (Level.Lines[0].Cards.Count = 2) then
      begin
        Zip := Level.Lines[0].Cards[0];
        Lex := Level.Lines[0].Cards[1];
      end;
      Check((Zip <> nil) and (Zip.Kind = vkGroup) and (Lex.Kind = vkGroup), 'the two buttons cards side by side: ' +
        Describe(Level));
      if (Zip = nil) or (Zip.Kind <> vkGroup) or (Lex.Kind <> vkGroup) then
        Exit;
      Titles := '';
      for B in InnerOf(Zip) do
        Titles := Titles + B.Title + ';';
      Check((Zip.Title = '') and (Titles = 'Add to archive...;Extract here;CRC SHA;'),
        '7-Zip unfolded into its items; no title of its own, none shown (not its name): ' + Zip.Title + ' ' + Titles);
      Check((Length(InnerOf(Zip)) = 3) and InnerOf(Zip)[2].HasSubmenu and not InnerOf(Zip)[0].HasSubmenu,
        'a button with a submenu of its own opens it');
      Titles := '';
      for B in InnerOf(Lex) do
        Titles := Titles + B.Title + ';';
      Check((Lex.Title = '') and (Titles = 'Edit in LexPen;View in LexPen;'),
        'found items without a submenu: each a button, the card''s title: ' + Lex.Title + ' ' + Titles);
      Check(not Zip.Enabled and (Zip.LookCard <> nil) and (InnerOf(Zip)[0].LookCard = nil),
        'the card is no button; its buttons take the theme''s look, not the card''s');
      G := Measure(Level);
      ZipBox := -1;
      for I := 0 to High(G.Boxes) do
        if G.Boxes[I].Card = Zip then
          ZipBox := I;
      Within := (ZipBox >= 0) and (ZipBox + 3 <= High(G.Boxes));
      if Within then
        for I := ZipBox + 1 to ZipBox + 3 do
          Within := Within and (G.Boxes[I].Card = InnerOf(Zip)[I - ZipBox - 1]) and
            (G.Boxes[I].Rect.left >= G.Boxes[ZipBox].Rect.left) and (G.Boxes[I].Rect.right <= G.Boxes[ZipBox].Rect.right) and
            (G.Boxes[I].Rect.top > G.Boxes[ZipBox].Rect.top) and (G.Boxes[I].Rect.bottom <= G.Boxes[ZipBox].Rect.bottom);
      Check(Within, 'the buttons'' boxes follow their card''s, inside it');
      if not Within then
        Exit;
      Inside := BoxAt(G, (G.Boxes[ZipBox + 1].Rect.left + G.Boxes[ZipBox + 1].Rect.right) / 2,
        (G.Boxes[ZipBox + 1].Rect.top + G.Boxes[ZipBox + 1].Rect.bottom) / 2, 0);
      Check(Inside = ZipBox + 1, 'a point on a button hits the button');
      Check(BoxAt(G, G.Boxes[ZipBox].Rect.left + 2, G.Boxes[ZipBox].Rect.top + 2, 0) = -1,
        'a point on the card''s own edge (around its buttons) hits nothing');
    finally
      Level.Free;
    end;
  finally
    P.Free;
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

// DexmenuUnitTests --compare <old layout> <new layout> <kind>... (plan 11 3.7): the menu of a kind's seen items (the
// preview's menu) placed and measured with both layouts, every box compared: kind, title, place and size. For the
// conversion to format 2, which must show the same menu. Exit code: the number of kinds that differ.
function CompareLayouts: Integer;
var
  OldText, NewText, Error, Kind, A, B: string;
  OldLayout, NewLayout: ILayout;
  K: Integer;

  function Picture(Layout: ILayout; const Kind: string; AtRightClick: Boolean): string;
  var
    Menu: HMENU;
    Top: TNodes;
    P: TPlacement;
    Level: TViewLevel;
    G: TGeometry;
    Box: TBox;
    E: string;
  begin
    Result := '';
    Menu := MenuFromSeen(ReadSeenText(Kind), E);
    if Menu = 0 then
      Exit('no seen items: ' + E);
    Top := ReadLevel(Menu, '');
    P := TPlacement.Create(Layout, 'default', Top);
    P.AtRightClick := AtRightClick;
    try
      Level := P.TopLevel;
      try
        G := Measure(Level);
        Result := Format('width %.1f height %.1f', [G.Width, G.Height]) + #13#10;
        for Box in G.Boxes do
          if (Box.Card.Kind <> vkGroup) or Box.Card.Framed then
            Result := Result + Format('%d %s %.1f %.1f %.1f %.1f %s', [Ord(Box.Card.Kind), Box.Card.Title, Box.Rect.left,
              Box.Rect.top, Box.Rect.right, Box.Rect.bottom, BoolToStr(Box.Alone, True)]) + #13#10;
      finally
        Level.Free;
      end;
    finally
      P.Free;
      Top.Free;
      DestroyMenu(Menu);
    end;
  end;

begin
  Result := 0;
  OldText := TFile.ReadAllText(ParamStr(2));
  NewText := TFile.ReadAllText(ParamStr(3));
  OldLayout := ParseLayout(OldText, ParamStr(2), Error);
  if OldLayout = nil then
  begin
    Writeln('old layout not read: ', Error);
    Exit(1);
  end;
  NewLayout := ParseLayout(NewText, ParamStr(3), Error);
  if NewLayout = nil then
  begin
    Writeln('new layout not read: ', Error);
    Exit(1);
  end;
  for K := 4 to ParamCount do
  begin
    Kind := ParamStr(K);
    A := Picture(OldLayout, Kind, False) + Picture(OldLayout, Kind, True);
    B := Picture(NewLayout, Kind, False) + Picture(NewLayout, Kind, True);
    if A = B then
      Writeln('SAME ', Kind, ': ', Length(A.Split([#13#10])) - 2, ' boxes')
    else
    begin
      Inc(Result);
      Writeln('DIFFERENT ', Kind);
      // the two pictures in the temp folder (never beside the layouts)
      TFile.WriteAllText(TPath.Combine(TPath.GetTempPath, ChangeFileExt(ExtractFileName(ParamStr(3)), '') + '.' + Kind + '.old.txt'), A);
      TFile.WriteAllText(TPath.Combine(TPath.GetTempPath, ChangeFileExt(ExtractFileName(ParamStr(3)), '') + '.' + Kind + '.new.txt'), B);
      Writeln('  the two pictures: ', TPath.GetTempPath);
    end;
  end;
end;

begin
  if ParamStr(1) = '--compare' then
  begin
    ExitCode := CompareLayouts;
    Exit;
  end;
  TestComments;
  TestLayouts;
  TestCurrent;
  TestKinds;
  TestRules;
  TestEmptySubmenu;
  TestEmptyMenuCard;
  TestHints;
  TestDuplicates;
  TestUsage;
  TestUsedRules;
  TestIcons;
  TestKeptIcons;
  TestAccessAndShortcut;
  TestSearch;
  TestThemes;
  TestSubmenuModes;
  TestSeen;
  TestLinesAndCards;
  TestButtons;
  TestOwnRules;
  TestHolders;
  if Failures = 0 then
    Writeln('OK')
  else
    Writeln(Failures, ' FAILED');
  ExitCode := Failures;
end.
