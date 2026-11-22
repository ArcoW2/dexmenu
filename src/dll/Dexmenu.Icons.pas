unit Dexmenu.Icons;

// The pixels of an item's icon (docs/plans/02-PLAN-own-menu.md 3.8): an item's own bitmap in Windows' menu, or an icon
// from a file a layout card names ("path,index"). As 32-bit BGRA, premultiplied alpha, top-down: what Direct2D draws.

interface

uses
  Winapi.Windows, System.SysUtils, Dexmenu.Tree;

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

// The icons kept for the settings app's preview (plan 02 3.8), which has no bitmaps of its own: every item's bitmap,
// at any depth, saved as <SeenFolder>\icons\<hash of its key>.png (its key: Dexmenu.Usage.UsageKey). An icon saved
// before by this process with the same pixels is not written again.
procedure SaveIcons(Nodes: TNodes);
// A kept icon by the item's key; False when there is none. Read once, then from memory until ForgetKeptIcons.
function KeptIconPixels(const Key: string; out Pixels: TIconPixels): Boolean;
procedure ForgetKeptIcons;
function IconsFolder: string;

implementation

uses
  System.Generics.Collections, System.SyncObjs, System.Classes, System.Hash, System.Math, System.IOUtils,
  Winapi.ShellAPI, Winapi.ActiveX,
  Winapi.Wincodec, Dexmenu.Log, Dexmenu.Seen, Dexmenu.Usage;

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

// ---- the icons kept for the preview -----------------------------------------------------------------------------------

var
  Saved: TDictionary<string, Integer>;      // key -> the pixels' hash this process saved last
  Kept: TDictionary<string, TIconPixels>;   // key -> a kept icon read (Width 0: none there)

function IconsFolder: string;
begin
  Result := SeenFolder + '\icons';
end;

function IconFile(const Key: string): string;
begin
  Result := IconsFolder + '\' + THashMD5.GetHashString(Key) + '.png';
end;

function Factory: IWICImagingFactory;
begin
  if Failed(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER, IWICImagingFactory, Result)) then
    Result := nil;
end;

// Pixels as PNG bytes (PNG holds straight alpha: the premultiplied pixels undone first); nil when WIC fails.
function EncodePng(const WIC: IWICImagingFactory; const Pixels: TIconPixels): TBytes;
var
  Straight: TBytes;
  I, A: Integer;
  Memory: TMemoryStream;
  Stream: IWICStream;
  Encoder: IWICBitmapEncoder;
  Frame: IWICBitmapFrameEncode;
  Props: IPropertyBag2;
  Format: TGUID;
begin
  Result := nil;
  Straight := Copy(Pixels.Bits);
  I := 0;
  while I < Length(Straight) do
  begin
    A := Straight[I + 3];
    if (A > 0) and (A < 255) then
    begin
      Straight[I] := Min(255, Straight[I] * 255 div A);
      Straight[I + 1] := Min(255, Straight[I + 1] * 255 div A);
      Straight[I + 2] := Min(255, Straight[I + 2] * 255 div A);
    end;
    Inc(I, 4);
  end;
  Memory := TMemoryStream.Create;
  try
    if Failed(WIC.CreateStream(Stream)) or Failed(Stream.InitializeFromIStream(TStreamAdapter.Create(Memory) as IStream)) or
      Failed(WIC.CreateEncoder(GUID_ContainerFormatPng, TGUID(nil^), Encoder)) or
      Failed(Encoder.Initialize(Stream, WICBitmapEncoderNoCache)) or Failed(Encoder.CreateNewFrame(Frame, Props)) or
      Failed(Frame.Initialize(nil)) or Failed(Frame.SetSize(Pixels.Width, Pixels.Height)) then
      Exit;
    Format := GUID_WICPixelFormat32bppBGRA;
    if Failed(Frame.SetPixelFormat(Format)) or not IsEqualGUID(Format, GUID_WICPixelFormat32bppBGRA) or
      Failed(Frame.WritePixels(Pixels.Height, Pixels.Width * 4, Length(Straight), @Straight[0])) or
      Failed(Frame.Commit) or Failed(Encoder.Commit) then
      Exit;
    SetLength(Result, Memory.Size);
    if Memory.Size > 0 then
      Move(Memory.Memory^, Result[0], Memory.Size);
  finally
    Memory.Free;
  end;
end;

procedure SaveIcons(Nodes: TNodes);
var
  WIC: IWICImagingFactory;
  Initialized: Boolean;

  procedure Walk(Nodes: TNodes);
  var
    N: TNode;
    Pixels: TIconPixels;
    Key, Path: string;
    Hash, Before: Integer;
    Png, Old: TBytes;
  begin
    for N in Nodes do
    begin
      if N.Children <> nil then
        Walk(N.Children);
      if N.IsSeparator or (N.Name = '') or not BitmapPixels(N.Item.Info.hbmpItem, Pixels) then
        Continue;
      Key := UsageKey(N);
      Hash := THashBobJenkins.GetHashValue(Pixels.Bits[0], Length(Pixels.Bits), Pixels.Width);
      CacheLock.Enter;
      try
        if Saved.TryGetValue(Key, Before) and (Before = Hash) then
          Continue;
      finally
        CacheLock.Leave;
      end;
      if WIC = nil then
        WIC := Factory;
      if WIC = nil then
        Exit;
      Png := EncodePng(WIC, Pixels);
      if Png = nil then
        Continue;
      Path := IconFile(Key);
      Old := nil;
      if FileExists(Path) then
        Old := TFile.ReadAllBytes(Path);
      if (Length(Old) <> Length(Png)) or not CompareMem(@Old[0], @Png[0], Length(Png)) then
      begin
        ForceDirectories(IconsFolder);
        TFile.WriteAllBytes(Path, Png);
      end;
      CacheLock.Enter;
      try
        Saved.AddOrSetValue(Key, Hash);
        Kept.Remove(Key);
      finally
        CacheLock.Leave;
      end;
    end;
  end;

begin
  if Nodes = nil then
    Exit;
  Initialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
  try
    try
      Walk(Nodes);
    except
      on E: Exception do
        Log('icons not kept: ' + E.Message);
    end;
    WIC := nil;
  finally
    if Initialized then
      CoUninitialize;
  end;
end;

function ReadPng(const Path: string; out Pixels: TIconPixels): Boolean;
var
  WIC: IWICImagingFactory;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Source: IWICBitmapSource;
  W, H: UINT;
begin
  Result := False;
  Pixels := Default(TIconPixels);
  WIC := Factory;
  if (WIC = nil) or Failed(WIC.CreateDecoderFromFilename(PChar(Path), TGUID(nil^), GENERIC_READ,
    WICDecodeMetadataCacheOnDemand, Decoder)) or Failed(Decoder.GetFrame(0, Frame)) or
    Failed(WICConvertBitmapSource(GUID_WICPixelFormat32bppPBGRA, Frame, Source)) or Failed(Source.GetSize(W, H)) or
    (W = 0) or (H = 0) or (W > 256) or (H > 256) then
    Exit;
  Pixels.Width := W;
  Pixels.Height := H;
  SetLength(Pixels.Bits, W * H * 4);
  Result := Succeeded(Source.CopyPixels(nil, W * 4, Length(Pixels.Bits), @Pixels.Bits[0]));
end;

function KeptIconPixels(const Key: string; out Pixels: TIconPixels): Boolean;
var
  Initialized: Boolean;
begin
  CacheLock.Enter;
  try
    if Kept.TryGetValue(Key, Pixels) then
      Exit(Pixels.Width > 0);
  finally
    CacheLock.Leave;
  end;
  Result := False;
  Pixels := Default(TIconPixels);
  if FileExists(IconFile(Key)) then
  begin
    Initialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
    try
      try
        Result := ReadPng(IconFile(Key), Pixels);
      except
        on E: Exception do
          Log('kept icon not read: ' + E.Message);
      end;
    finally
      if Initialized then
        CoUninitialize;
    end;
  end;
  if not Result then
    Pixels := Default(TIconPixels);
  CacheLock.Enter;
  try
    Kept.AddOrSetValue(Key, Pixels);
  finally
    CacheLock.Leave;
  end;
end;

procedure ForgetKeptIcons;
begin
  CacheLock.Enter;
  try
    Kept.Clear;
  finally
    CacheLock.Leave;
  end;
end;

initialization
  Cache := TDictionary<string, TIconPixels>.Create;
  CacheLock := TCriticalSection.Create;
  Saved := TDictionary<string, Integer>.Create;
  Kept := TDictionary<string, TIconPixels>.Create;

finalization
  Cache.Free;
  CacheLock.Free;
  Saved.Free;
  Kept.Free;

end.
