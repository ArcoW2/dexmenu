unit Dexmenu.Icons;

// The pixels of an item's icon (docs/plans/02-PLAN-own-menu.md 3.8): an item's own bitmap in Windows' menu, or an icon
// from a file a layout card names ("path,index"). As 32-bit BGRA, premultiplied alpha, top-down: what Direct2D draws.

interface

uses
  Winapi.Windows, System.SysUtils;

type
  TIconPixels = record
    Width, Height: Integer;
    Bits: TBytes;
  end;

// A menu item's bitmap (MENUITEMINFO.hbmpItem); False for none or for the HBMMENU_ values (drawn by Windows or the
// owner, not a bitmap).
function BitmapPixels(Bitmap: HBITMAP; out Pixels: TIconPixels): Boolean;
// An icon in a file, "path,index" (the path may hold %variables%; index 0 when left out), at Size pixels; cached.
function FileIconPixels(const Spec: string; Size: Integer; out Pixels: TIconPixels): Boolean;
// Whether a card's icon is a glyph: its code point in hex, "E8C8"; the character is returned.
function IsGlyph(const Spec: string; out Glyph: string): Boolean;

implementation

uses
  System.Generics.Collections, System.SyncObjs, Winapi.ShellAPI, Dexmenu.Log;

const
  // HBMMENU_CALLBACK (-1) and HBMMENU_SYSTEM (1) to HBMMENU_POPUP_MINIMIZE (11) are no bitmap. Only these: a real
  // bitmap's handle is sign-extended on 64-bit Windows, so it may be below zero too.
  LastMenuConstant = 11;

var
  Cache: TDictionary<string, TIconPixels>;
  CacheLock: TCriticalSection;

function IsGlyph(const Spec: string; out Glyph: string): Boolean;
var
  Code: Integer;
begin
  Result := (Length(Spec) in [4, 5]) and TryStrToInt('$' + Spec, Code) and (Code > $20);
  if Result then
    Glyph := Char(Code)   // the icon fonts' glyphs are in the private use area, one UTF-16 unit
  else
    Glyph := '';
end;

// The bits of a bitmap as 32-bit top-down BGRA; False when it cannot be read.
function ReadBits(Bitmap: HBITMAP; out Pixels: TIconPixels): Boolean;
var
  Info: Winapi.Windows.TBitmap;
  BMI: TBitmapInfo;
  DC: HDC;
begin
  Result := False;
  if GetObject(Bitmap, SizeOf(Info), @Info) = 0 then
    Exit;
  if (Info.bmWidth <= 0) or (Info.bmHeight <= 0) or (Info.bmWidth > 256) or (Info.bmHeight > 256) then
    Exit;
  Pixels.Width := Info.bmWidth;
  Pixels.Height := Info.bmHeight;
  SetLength(Pixels.Bits, Pixels.Width * Pixels.Height * 4);
  FillChar(BMI, SizeOf(BMI), 0);
  BMI.bmiHeader.biSize := SizeOf(BMI.bmiHeader);
  BMI.bmiHeader.biWidth := Pixels.Width;
  BMI.bmiHeader.biHeight := -Pixels.Height;
  BMI.bmiHeader.biPlanes := 1;
  BMI.bmiHeader.biBitCount := 32;
  BMI.bmiHeader.biCompression := BI_RGB;
  DC := GetDC(0);
  try
    Result := GetDIBits(DC, Bitmap, 0, Pixels.Height, @Pixels.Bits[0], BMI, DIB_RGB_COLORS) = Pixels.Height;
  finally
    ReleaseDC(0, DC);
  end;
end;

// Alpha made usable: none at all (a bitmap without alpha) is opaque; colours above their alpha (not premultiplied)
// are premultiplied.
procedure FixAlpha(var Pixels: TIconPixels);
var
  I, A: Integer;
  AnyAlpha, Straight: Boolean;
begin
  AnyAlpha := False;
  Straight := False;
  I := 0;
  while I < Length(Pixels.Bits) do
  begin
    A := Pixels.Bits[I + 3];
    if A <> 0 then
      AnyAlpha := True;
    if (Pixels.Bits[I] > A) or (Pixels.Bits[I + 1] > A) or (Pixels.Bits[I + 2] > A) then
      Straight := True;
    Inc(I, 4);
  end;
  I := 0;
  while I < Length(Pixels.Bits) do
  begin
    if not AnyAlpha then
      Pixels.Bits[I + 3] := 255
    else if Straight then
    begin
      A := Pixels.Bits[I + 3];
      Pixels.Bits[I] := Pixels.Bits[I] * A div 255;
      Pixels.Bits[I + 1] := Pixels.Bits[I + 1] * A div 255;
      Pixels.Bits[I + 2] := Pixels.Bits[I + 2] * A div 255;
    end;
    Inc(I, 4);
  end;
end;

function BitmapPixels(Bitmap: HBITMAP; out Pixels: TIconPixels): Boolean;
begin
  Result := ((NativeInt(Bitmap) < -1) or (NativeInt(Bitmap) > LastMenuConstant)) and ReadBits(Bitmap, Pixels);
  if Result then
    FixAlpha(Pixels);
end;

function IconPixels(Icon: HICON; out Pixels: TIconPixels): Boolean;
var
  Info: TIconInfo;
  Mask: TIconPixels;
  I: Integer;
  AnyAlpha: Boolean;
begin
  Result := False;
  if not GetIconInfo(Icon, Info) then
    Exit;
  try
    if (Info.hbmColor = 0) or not ReadBits(Info.hbmColor, Pixels) then
      Exit;
    AnyAlpha := False;
    I := 3;
    while I < Length(Pixels.Bits) do
    begin
      if Pixels.Bits[I] <> 0 then
        AnyAlpha := True;
      Inc(I, 4);
    end;
    // an icon without alpha: its mask says what shows (white: transparent)
    if not AnyAlpha and ReadBits(Info.hbmMask, Mask) and (Mask.Width = Pixels.Width) and
      (Mask.Height >= Pixels.Height) then
    begin
      I := 0;
      while I < Length(Pixels.Bits) do
      begin
        if Mask.Bits[I] = 0 then
          Pixels.Bits[I + 3] := 255
        else
        begin
          Pixels.Bits[I] := 0;
          Pixels.Bits[I + 1] := 0;
          Pixels.Bits[I + 2] := 0;
          Pixels.Bits[I + 3] := 0;
        end;
        Inc(I, 4);
      end;
    end
    else
      FixAlpha(Pixels);
    Result := True;
  finally
    if Info.hbmColor <> 0 then
      DeleteObject(Info.hbmColor);
    if Info.hbmMask <> 0 then
      DeleteObject(Info.hbmMask);
  end;
end;

function SHDefExtractIconW(pszIconFile: PWideChar; iIndex: Integer; uFlags: UINT; var phiconLarge: HICON;
  phiconSmall: PHandle; nIconSize: UINT): HRESULT; stdcall; external shell32 name 'SHDefExtractIconW';

function FileIconPixels(const Spec: string; Size: Integer; out Pixels: TIconPixels): Boolean;
var
  Key, Path: string;
  Comma, Index: Integer;
  Expanded: array[0..MAX_PATH] of Char;
  Icon: HICON;
begin
  Key := Spec + '|' + IntToStr(Size);
  CacheLock.Enter;
  try
    if Cache.TryGetValue(Key, Pixels) then
      Exit(Pixels.Width > 0);
  finally
    CacheLock.Leave;
  end;
  Result := False;
  Pixels := Default(TIconPixels);
  Path := Spec;
  Index := 0;
  Comma := LastDelimiter(',', Spec);
  if (Comma > 0) and TryStrToInt(Trim(Copy(Spec, Comma + 1, MaxInt)), Index) then
    Path := Trim(Copy(Spec, 1, Comma - 1));
  Path := Path.DeQuotedString('"');
  if ExpandEnvironmentStrings(PChar(Path), Expanded, Length(Expanded)) > 0 then
    Path := Expanded;
  Icon := 0;
  try
    if Succeeded(SHDefExtractIconW(PChar(Path), Index, 0, Icon, nil, Size)) and (Icon <> 0) then
      Result := IconPixels(Icon, Pixels);
  except
    on E: Exception do
      Log('icon ' + Spec + ': ' + E.Message);
  end;
  if Icon <> 0 then
    DestroyIcon(Icon);
  if not Result then
    Pixels := Default(TIconPixels);
  CacheLock.Enter;
  try
    Cache.AddOrSetValue(Key, Pixels);   // a file without the icon is not asked again
  finally
    CacheLock.Leave;
  end;
end;

initialization
  Cache := TDictionary<string, TIconPixels>.Create;
  CacheLock := TCriticalSection.Create;

finalization
  Cache.Free;
  CacheLock.Free;

end.
