unit Dexmenu.Draw;

// The drawing engine (docs/plans/03-PLAN-menu-look.md 3.1; plan 00 step 3): a level of the menu measured and drawn
// with Direct2D and DirectWrite into a 32-bit image with a transparency per pixel, shown by a layered window
// (UpdateLayeredWindow). Everything in device-independent units (DIP), scaled to the monitor. Step 3 has one built-in
// look, light or dark as Windows' apps are; themes come with step 6.

interface

uses
  Winapi.Windows, Winapi.D2D1, System.Types, Dexmenu.Place;

type
  TBox = record
    Card: TViewCard;
    Rect: TD2D1RectF;   // DIP, within the level
  end;

  TGeometry = record
    Width, Height: Single;   // DIP, the whole level
    Boxes: TArray<TBox>;
  end;

  TLook = record
    Dark: Boolean;
    class function Current: TLook; static;
  end;

  // A level drawn into a 32-bit image with a transparency per pixel (premultiplied).
  TPicture = record
    DC: HDC;
    Bitmap, Old: HBITMAP;
    Width, Height: Integer;   // pixels
    procedure PaintOnto(Target: HDC; X, Y: Integer);
    procedure Free;
  end;

// The level laid out: every card's box.
function Measure(Level: TViewLevel): TGeometry;
// The level drawn and shown in a layered window at a screen position (pixels); Selected: a box index or -1;
// ScrollY: DIP scrolled down; Scale: the monitor's DPI / 96. The window's size is set to the picture's.
procedure Present(Wnd: HWND; const ScreenPos: TPoint; const G: TGeometry; Selected: Integer; ScrollY, Scale: Single;
  VisibleHeight: Single);
// The level drawn into a picture; the caller frees it.
function Render(const G: TGeometry; Selected: Integer; ScrollY, Scale, VisibleHeight: Single): TPicture;
// The box at a point (DIP within the level, scroll applied), or -1.
function BoxAt(const G: TGeometry; X, Y, ScrollY: Single): Integer;

const
  // The built-in look's sizes (DIP).
  OuterPad = 4;
  ItemHeight = 30;
  SeparatorHeight = 9;
  TextLeft = 36;
  MarkWidth = 28;
  MinWidth = 200;
  MaxWidth = 480;
  WindowRadius = 8;
  ItemRadius = 4;
  FontSize = 12;

implementation

uses
  System.SysUtils, System.Math, System.SyncObjs, Winapi.DxgiFormat, Dexmenu.Log;

const
  RRF_RT_REG_DWORD = $00000010;
  CheckGlyph = #$E73E;     // Segoe MDL2 Assets: CheckMark
  ChevronGlyph = #$E76C;   // Segoe MDL2 Assets: ChevronRight
  GlyphFont = 'Segoe MDL2 Assets';
  TextFont = 'Segoe UI';

function RegGetValueW(Key: HKEY; SubKey, Value: PWideChar; Flags: DWORD; ValueType: PDWORD; Data: Pointer;
  DataSize: PDWORD): LONG; stdcall; external advapi32 name 'RegGetValueW';

var
  FactoryLock: TCriticalSection;
  D2D: ID2D1Factory;
  DWrite: IDWriteFactory;
  NormalFormat, BoldFormat, GlyphFormat: IDWriteTextFormat;

class function TLook.Current: TLook;
var
  Value, Size: DWORD;
begin
  Value := 1;
  Size := SizeOf(Value);
  RegGetValueW(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
    'AppsUseLightTheme', RRF_RT_REG_DWORD, nil, @Value, @Size);
  Result.Dark := Value = 0;
end;

function MakeFormat(const Family: string; Weight: DWRITE_FONT_WEIGHT; Size: Single; Center: Boolean): IDWriteTextFormat;
var
  Trimming: TDwriteTrimming;
  Sign: IDWriteInlineObject;
begin
  DWrite.CreateTextFormat(PWideChar(Family), nil, Weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, Size,
    'en-us', Result);
  Result.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  Result.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
  if Center then
    Result.SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
  FillChar(Trimming, SizeOf(Trimming), 0);
  Trimming.granularity := DWRITE_TRIMMING_GRANULARITY_CHARACTER;
  DWrite.CreateEllipsisTrimmingSign(Result, Sign);
  Result.SetTrimming(Trimming, Sign);
end;

procedure EnsureFactories;
var
  Unk: IUnknown;
begin
  FactoryLock.Enter;
  try
    if D2D <> nil then
      Exit;
    D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED, IID_ID2D1Factory, nil, D2D);
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, IID_IDWriteFactory, Unk);
    DWrite := Unk as IDWriteFactory;
    NormalFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_NORMAL, FontSize, False);
    BoldFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_SEMI_BOLD, FontSize, False);
    GlyphFormat := MakeFormat(GlyphFont, DWRITE_FONT_WEIGHT_NORMAL, 10, True);
  finally
    FactoryLock.Leave;
  end;
end;

function TextWidth(const Text: string; Format: IDWriteTextFormat): Single;
var
  Layout: IDWriteTextLayout;
  M: TDWriteTextMetrics;
begin
  Result := 0;
  if (Text = '') or Failed(DWrite.CreateTextLayout(PWideChar(Text), Length(Text), Format, 10000, 100, Layout)) then
    Exit;
  if Succeeded(Layout.GetMetrics(M)) then
    Result := M.widthIncludingTrailingWhitespace;
end;

function Measure(Level: TViewLevel): TGeometry;
var
  Line: TViewLine;
  V: TViewCard;
  W, Y, H, X, CardW, Need: Single;
  N, I: Integer;
  Box: TBox;
  Fmt: IDWriteTextFormat;
begin
  EnsureFactories;
  // The width: the widest line's need, between the minimum and the maximum.
  W := MinWidth;
  for Line in Level.Lines do
  begin
    Need := 0;
    for V in Line.Cards do
      if V.Kind <> vkSeparator then
      begin
        if V.IsDefault then
          Fmt := BoldFormat
        else
          Fmt := NormalFormat;
        Need := Need + TextLeft + TextWidth(V.Title, Fmt) + MarkWidth + 8;
      end;
    W := Max(W, Need + 2 * OuterPad);
  end;
  W := Min(W, MaxWidth);

  Result.Boxes := nil;
  Y := OuterPad;
  for Line in Level.Lines do
  begin
    N := Line.Cards.Count;
    if N = 0 then
      Continue;
    if (N = 1) and (Line.Cards[0].Kind = vkSeparator) then
      H := SeparatorHeight
    else
      H := ItemHeight;
    CardW := (W - 2 * OuterPad) / N;
    X := OuterPad;
    for I := 0 to N - 1 do
    begin
      Box.Card := Line.Cards[I];
      Box.Rect := D2D1RectF(X, Y, X + CardW, Y + H);
      Result.Boxes := Result.Boxes + [Box];
      X := X + CardW;
    end;
    Y := Y + H;
  end;
  Result.Width := W;
  Result.Height := Y + OuterPad;
end;

function BoxAt(const G: TGeometry; X, Y, ScrollY: Single): Integer;
var
  I: Integer;
begin
  Y := Y + ScrollY;
  for I := 0 to High(G.Boxes) do
    with G.Boxes[I].Rect do
      if (X >= left) and (X < right) and (Y >= top) and (Y < bottom) then
        Exit(I);
  Result := -1;
end;

function Color(R, G, B: Byte; A: Single = 1): TD2D1ColorF;
begin
  Result := D2D1ColorF(R / 255, G / 255, B / 255, A);
end;

procedure DrawLevel(T: ID2D1RenderTarget; const G: TGeometry; Selected: Integer; ScrollY, VisibleHeight: Single;
  const Look: TLook);
var
  Bg, Border, Text, Dim, Hover, Sep: ID2D1SolidColorBrush;
  I: Integer;
  R: TD2D1RectF;
  V: TViewCard;
  Title: string;
  Fmt: IDWriteTextFormat;
  Brush: ID2D1SolidColorBrush;
  Y: Single;
begin
  if Look.Dark then
  begin
    T.CreateSolidColorBrush(Color($2B, $2B, $2B), nil, Bg);
    T.CreateSolidColorBrush(Color($45, $45, $45), nil, Border);
    T.CreateSolidColorBrush(Color($FF, $FF, $FF), nil, Text);
    T.CreateSolidColorBrush(Color($80, $80, $80), nil, Dim);
    T.CreateSolidColorBrush(Color($FF, $FF, $FF, 0.08), nil, Hover);
    T.CreateSolidColorBrush(Color($45, $45, $45), nil, Sep);
  end
  else
  begin
    T.CreateSolidColorBrush(Color($F9, $F9, $F9), nil, Bg);
    T.CreateSolidColorBrush(Color($D0, $D0, $D0), nil, Border);
    T.CreateSolidColorBrush(Color($1B, $1B, $1B), nil, Text);
    T.CreateSolidColorBrush(Color($A0, $A0, $A0), nil, Dim);
    T.CreateSolidColorBrush(Color($00, $00, $00, 0.06), nil, Hover);
    T.CreateSolidColorBrush(Color($E0, $E0, $E0), nil, Sep);
  end;
  T.Clear(D2D1ColorF(0, 0, 0, 0));
  R := D2D1RectF(0.5, 0.5, G.Width - 0.5, VisibleHeight - 0.5);
  T.FillRoundedRectangle(D2D1RoundedRect(R, WindowRadius, WindowRadius), Bg);
  T.DrawRoundedRectangle(D2D1RoundedRect(R, WindowRadius, WindowRadius), Border, 1);
  T.PushAxisAlignedClip(D2D1RectF(1, OuterPad, G.Width - 1, VisibleHeight - OuterPad), D2D1_ANTIALIAS_MODE_ALIASED);
  for I := 0 to High(G.Boxes) do
  begin
    V := G.Boxes[I].Card;
    R := G.Boxes[I].Rect;
    R.top := R.top - ScrollY;
    R.bottom := R.bottom - ScrollY;
    if (R.bottom < 0) or (R.top > VisibleHeight) then
      Continue;
    if V.Kind = vkSeparator then
    begin
      Y := Round((R.top + R.bottom) / 2) + 0.5;
      T.DrawLine(D2D1PointF(R.left + 8, Y), D2D1PointF(R.right - 8, Y), Sep, 1);
      Continue;
    end;
    if (I = Selected) and V.Enabled then
      T.FillRoundedRectangle(D2D1RoundedRect(D2D1RectF(R.left + 2, R.top + 1, R.right - 2, R.bottom - 1),
        ItemRadius, ItemRadius), Hover);
    if V.Enabled then
      Brush := Text
    else
      Brush := Dim;
    if V.Checked then
      T.DrawText(PWideChar(CheckGlyph), 1, GlyphFormat, D2D1RectF(R.left + 6, R.top, R.left + TextLeft - 6, R.bottom),
        Brush);
    if V.HasSubmenu then
      T.DrawText(PWideChar(ChevronGlyph), 1, GlyphFormat, D2D1RectF(R.right - MarkWidth, R.top, R.right - 6, R.bottom),
        Brush);
    if V.IsDefault then
      Fmt := BoldFormat
    else
      Fmt := NormalFormat;
    Title := V.Title;
    if Title <> '' then
      T.DrawText(PWideChar(Title), Length(Title), Fmt, D2D1RectF(R.left + TextLeft, R.top, R.right - MarkWidth,
        R.bottom), Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
  end;
  T.PopAxisAlignedClip;
end;

function Render(const G: TGeometry; Selected: Integer; ScrollY, Scale, VisibleHeight: Single): TPicture;
var
  BMI: TBitmapInfo;
  Bits: Pointer;
  ScreenDC: HDC;
  Props: TD2D1RenderTargetProperties;
  Target: ID2D1DCRenderTarget;
  Rect: TRect;
begin
  EnsureFactories;
  Result.Width := Max(1, Ceil(G.Width * Scale));
  Result.Height := Max(1, Ceil(VisibleHeight * Scale));
  FillChar(BMI, SizeOf(BMI), 0);
  BMI.bmiHeader.biSize := SizeOf(BMI.bmiHeader);
  BMI.bmiHeader.biWidth := Result.Width;
  BMI.bmiHeader.biHeight := -Result.Height;
  BMI.bmiHeader.biPlanes := 1;
  BMI.bmiHeader.biBitCount := 32;
  ScreenDC := GetDC(0);
  Result.DC := CreateCompatibleDC(ScreenDC);
  ReleaseDC(0, ScreenDC);
  Result.Bitmap := CreateDIBSection(Result.DC, BMI, DIB_RGB_COLORS, Bits, 0, 0);
  Result.Old := SelectObject(Result.DC, Result.Bitmap);
  Props := D2D1RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_DEFAULT,
    D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96 * Scale, 96 * Scale);
  if Succeeded(D2D.CreateDCRenderTarget(Props, Target)) then
  begin
    Rect := System.Types.Rect(0, 0, Result.Width, Result.Height);
    Target.BindDC(Result.DC, Rect);
    Target.BeginDraw;
    DrawLevel(Target, G, Selected, ScrollY, VisibleHeight, TLook.Current);
    Target.EndDraw;
  end;
end;

procedure TPicture.Free;
begin
  SelectObject(DC, Old);
  DeleteObject(Bitmap);
  DeleteDC(DC);
end;

function BlendFunction: TBlendFunction;
begin
  Result.BlendOp := AC_SRC_OVER;
  Result.BlendFlags := 0;
  Result.SourceConstantAlpha := 255;
  Result.AlphaFormat := AC_SRC_ALPHA;
end;

procedure TPicture.PaintOnto(Target: HDC; X, Y: Integer);
begin
  Winapi.Windows.AlphaBlend(Target, X, Y, Width, Height, DC, 0, 0, Width, Height, BlendFunction);
end;

procedure Present(Wnd: HWND; const ScreenPos: TPoint; const G: TGeometry; Selected: Integer; ScrollY, Scale: Single;
  VisibleHeight: Single);
var
  P: TPicture;
  ScreenDC: HDC;
  Blend: TBlendFunction;
  Pos, Src: TPoint;
  Size: TSize;
begin
  P := Render(G, Selected, ScrollY, Scale, VisibleHeight);
  ScreenDC := GetDC(0);
  try
    Blend := BlendFunction;
    Pos := ScreenPos;
    Src := Point(0, 0);
    Size.cx := P.Width;
    Size.cy := P.Height;
    UpdateLayeredWindow(Wnd, ScreenDC, @Pos, @Size, P.DC, @Src, 0, @Blend, ULW_ALPHA);
  finally
    ReleaseDC(0, ScreenDC);
    P.Free;
  end;
end;

initialization
  FactoryLock := TCriticalSection.Create;

finalization
  // The DLL is pinned and only unloads at process exit, when Direct2D and DirectWrite may be gone already: their
  // objects are left, not released.
  Pointer(NormalFormat) := nil;
  Pointer(BoldFormat) := nil;
  Pointer(GlyphFormat) := nil;
  Pointer(DWrite) := nil;
  Pointer(D2D) := nil;

end.
