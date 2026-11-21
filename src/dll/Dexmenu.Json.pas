unit Dexmenu.Json;

// JSON with comments (docs/plans/02-PLAN-own-menu.md 3.5): `//` to the end of the line is a comment, except inside a
// string, so a regex or a path holding `//` is kept.

interface

uses
  System.JSON;

function WithoutComments(const Text: string): string;
// The text parsed as JSON after its comments are taken out; nil and Error set when it is not valid JSON.
function ParseWithComments(const Text: string; out Error: string): TJSONValue;
function ReadTextFile(const Path: string; out Text: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes;

function WithoutComments(const Text: string): string;
var
  B: TStringBuilder;
  I: Integer;
  InString: Boolean;
begin
  B := TStringBuilder.Create(Length(Text));
  try
    InString := False;
    I := 1;
    while I <= Length(Text) do
    begin
      if InString then
      begin
        B.Append(Text[I]);
        if (Text[I] = '\') and (I < Length(Text)) then
        begin
          Inc(I);
          B.Append(Text[I]);
        end
        else if Text[I] = '"' then
          InString := False;
      end
      else if Text[I] = '"' then
      begin
        InString := True;
        B.Append(Text[I]);
      end
      else if (Text[I] = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
      begin
        while (I <= Length(Text)) and (Text[I] <> #10) and (Text[I] <> #13) do
          Inc(I);
        Continue;
      end
      else
        B.Append(Text[I]);
      Inc(I);
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function ParseWithComments(const Text: string; out Error: string): TJSONValue;
begin
  Error := '';
  try
    Result := TJSONObject.ParseJSONValue(WithoutComments(Text), False, True);
  except
    on E: Exception do
    begin
      Error := E.Message;
      Result := nil;
    end;
  end;
  if (Result = nil) and (Error = '') then
    Error := 'not valid JSON';
end;

function ReadTextFile(const Path: string; out Text: string): Boolean;
var
  Lines: TStringList;
begin
  Text := '';
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
      Text := Lines.Text;
      Result := True;
    except
      Result := False;
    end;
  finally
    Lines.Free;
  end;
end;

end.
