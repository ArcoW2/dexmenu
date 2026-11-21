program DexmenuUnitTests;

// Unit tests of the DLL's units that need no Windows menu (plan 00 step 2 on): comments in JSON, the layout file.
// Prints PASS / FAIL per check; exit code = the number of failures. Run by tests\run-tests.ps1.

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.IOUtils,
  Dexmenu.Json in '..\..\src\dll\Dexmenu.Json.pas',
  Dexmenu.Log in '..\..\src\dll\Dexmenu.Log.pas',
  Dexmenu.Layout in '..\..\src\dll\Dexmenu.Layout.pas';

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

begin
  TestComments;
  TestLayouts;
  TestCurrent;
  if Failures = 0 then
    Writeln('OK')
  else
    Writeln(Failures, ' FAILED');
  ExitCode := Failures;
end.
