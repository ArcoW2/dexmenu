program DexmenuUnitTests;

// Unit tests of the DLL's units (plan 00 step 2 on): comments in JSON, the layout file, and the rules applied to a
// Windows menu built here (plan 02 3.12).
// Prints PASS / FAIL per check; exit code = the number of failures. Run by tests\run-tests.ps1.

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.IOUtils,
  Dexmenu.Json in '..\..\src\dll\Dexmenu.Json.pas',
  Dexmenu.Log in '..\..\src\dll\Dexmenu.Log.pas',
  Dexmenu.Rules in '..\..\src\dll\Dexmenu.Rules.pas',
  Dexmenu.Layout in '..\..\src\dll\Dexmenu.Layout.pas',
  Dexmenu.Menus in '..\..\src\dll\Dexmenu.Menus.pas',
  Dexmenu.Tree in '..\..\src\dll\Dexmenu.Tree.pas',
  Dexmenu.Place in '..\..\src\dll\Dexmenu.Place.pas',
  Dexmenu.Seen in '..\..\src\dll\Dexmenu.Seen.pas',
  System.JSON;

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
end;

procedure TestCurrent;
var
  Path, Error: string;
  L: ILayout;
  Stamp: TDateTime;
begin
  Path := TPath.Combine(TPath.GetTempPath, 'dexmenu-unit-layout.json');
  SetEnvironmentVariable('DEXMENU_LAYOUT_FILE', PChar(Path));
  if TFile.Exists(Path) then
    TFile.Delete(Path);
  L := CurrentLayout(Error);
  Check((L <> nil) and (L.Source = '(built in)'), 'no layout file: the built-in base layout');

  TFile.WriteAllText(Path, '{ "default": [ { "line": [ { "card": "First", "rules": [ "remaining" ] } ] } ] }');
  L := CurrentLayout(Error);
  Check((L <> nil) and (L.Lines('default')[0].Cards[0].Title = 'First'), 'the layout file read');
  Check((L <> nil) and (L.Lines('folder') = L.Lines('default')), 'a kind without lines of its own uses default');

  Stamp := TFile.GetLastWriteTime(Path);
  TFile.WriteAllText(Path, '{ "default": [ { "line": [ { "card": "Second", "rules": [ "remaining" ] } ] } ] }');
  TFile.SetLastWriteTime(Path, Stamp + 1 / 86400);
  L := CurrentLayout(Error);
  Check((L <> nil) and (L.Lines('default')[0].Cards[0].Title = 'Second'), 'read again when the file changed');

  TFile.WriteAllText(Path, '{ "default": [ ');
  TFile.SetLastWriteTime(Path, Stamp + 2 / 86400);
  L := CurrentLayout(Error);
  Check((L = nil) and (Error <> ''), 'a broken file: no layout, a reason (the menu is then Windows'' own)');
  TFile.Delete(Path);
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
  Add(Result, '&Copy');
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
        vkItem: Line := Line + 'I:' + V.Title;
        vkMenu: Line := Line + 'M:' + V.Title;
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

procedure TestSeen;
const
  ABC = '[ {"name":"A"}, {"name":"B"}, {"separator":true}, {"name":"C"} ]';
  ACD = '[ {"name":"A"}, {"name":"C"}, {"name":"D"} ]';
var
  Menu: HMENU;
  Error: string;
  Top: TNodes;
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
  Menu := MenuFromSeen('{ "items": [ {"text":"A","name":"A"}, {"text":"B","name":"B","sometimes":true} ] }', Error);
  Top := ReadLevel(Menu, '');
  try
    Check((Top.Count = 2) and not Top[0].Sometimes and Top[1].Sometimes, 'the preview''s menu: "sometimes" read back');
  finally
    Top.Free;
    DestroyMenu(Menu);
  end;
end;

begin
  TestComments;
  TestLayouts;
  TestCurrent;
  TestRules;
  TestSeen;
  if Failures = 0 then
    Writeln('OK')
  else
    Writeln(Failures, ' FAILED');
  ExitCode := Failures;
end.
