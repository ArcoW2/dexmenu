unit Dexmenu.Draw;

// The drawing engine (docs/plans/03-PLAN-menu-look.md 3.1; plan 00 step 3): a level of the menu measured and drawn
// with Direct2D and DirectWrite into a 32-bit image with a transparency per pixel, shown by a layered window
// (UpdateLayeredWindow). Everything in device-independent units (DIP), scaled to the monitor. Step 3 has one built-in
// look, light or dark as Windows' apps are; themes come with step 6.

interface

uses
  Winapi.Windows, Winapi.D2D1, System.Types, Dexmenu.Place, Dexmenu.Layout;

type
  TBox = record
    Card: TViewCard;
    Rect: TD2D1RectF;   // DIP, within the level
    Alone: Boolean;     // alone on its line: drawn as a menu item (the theme's "item"), else as a card (plan 03 3.5)
  end;

  TGeometry = record
    Width, Height: Single;   // DIP, the whole level
    Boxes: TArray<TBox>;
    Pressed: Integer;        // the box the mouse button is down on (the "pressed" state), or -1; Measure sets -1
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

// The level laid out: every card's box. Depth: 0 the top, 1 a first submenu, ... (its width from the global settings).
function Measure(Level: TViewLevel; Depth: Integer = 0): TGeometry;
// The global settings' look for the levels drawn next (plan 02 3.4): the marks and the widths per level.
procedure SetMenuLook(const Settings: TMenuSettings);
// The level drawn and shown in a layered window at a screen position (pixels); Selected: a box index or -1;
// ScrollY: DIP scrolled down; Scale: the monitor's DPI / 96. The window's size is set to the picture's.
procedure Present(Wnd: HWND; const ScreenPos: TPoint; const G: TGeometry; Selected: Integer; ScrollY, Scale: Single;
  VisibleHeight: Single);
// The level drawn into a picture; the caller frees it. Editing (the settings app's preview): items not always there
// (TViewCard.Sometimes) drawn with diagonal stripes; never at a right-click.
function Render(const G: TGeometry; Selected: Integer; ScrollY, Scale, VisibleHeight: Single;
  const Marked: string = ''; Editing: Boolean = False): TPicture;
// The look light or dark as told (the settings app's theme switch, plan 05 3.3): 0 as Windows' apps are, 1 light,
// 2 dark. Only the settings app calls it; a right-click follows Windows.
procedure DexmenuSetTheme(Mode: Integer); stdcall;
// The palette of the theme the preview draws with (DexmenuSetTheme's mode), as TTheme.PaletteText, into Buffer; the
// number of characters it needs (with the #0).
function DexmenuThemePalette(Buffer: PWideChar; Chars: Integer): Integer; stdcall;
// The box at a point (DIP within the level, scroll applied), or -1.
function BoxAt(const G: TGeometry; X, Y, ScrollY: Single): Integer;

const
  // The built-in look's sizes (DIP).
  OuterPad = 4;
  ItemHeight = 30;
  SeparatorHeight = 9;
  DividerTextHeight = 24;   // a divider with a text
  TextLeft = 36;
  MarkWidth = 28;
  MinWidth = 200;
  MaxWidth = 480;
  WindowRadius = 8;
  ItemRadius = 4;
  FontSize = 12;

implementation

uses
  System.SysUtils, System.Math, System.SyncObjs, System.Generics.Collections, System.JSON, Winapi.DxgiFormat, Dexmenu.Log,
  Dexmenu.Icons, Dexmenu.Usage, Dexmenu.Theme;

const
  RRF_RT_REG_DWORD = $00000010;
  CheckGlyph = #$E73E;     // Segoe MDL2 Assets: CheckMark
  ChevronGlyph = #$E76C;   // Segoe MDL2 Assets: ChevronRight
  GlyphFont = 'Segoe MDL2 Assets';
  IconSize = 16;   // an icon's size (DIP), in the slot left of the text
  ShortcutGap = 16;   // between a title and its shortcut
  TextFont = 'Segoe UI';
  TitleHeight = 18;   // a title's line within a card that has an extra text, or with its icon on top (DIP)
  ExtraHeight = 14;   // an extra text's line (plan 03 3.6)
  ExtraSize = 10;     // its font size

function RegGetValueW(Key: HKEY; SubKey, Value: PWideChar; Flags: DWORD; ValueType: PDWORD; Data: Pointer;
  DataSize: PDWORD): LONG; stdcall; external advapi32 name 'RegGetValueW';

var
  FactoryLock: TCriticalSection;
  D2D: ID2D1Factory;
  DWrite: IDWriteFactory;
  NormalFormat, BoldFormat, GlyphFormat: IDWriteTextFormat;
  IconFormat: IDWriteTextFormat;     // a layout card's glyph icon (Segoe Fluent Icons, else Segoe MDL2 Assets)
  ShortcutFormat: IDWriteTextFormat; // an item's shortcut ("Ctrl+X"), at the right
  DrawScale: Single = 1;             // the scale of the level being drawn: a file's icon is read at its pixel size
  NoteFormat: IDWriteTextFormat;   // a note card's text: wraps, from the top (plan 02 3.3)
  ExtraFormat: IDWriteTextFormat;  // a card's extra text, smaller (plan 03 3.6)
  CenterFormat, CenterExtraFormat: IDWriteTextFormat;   // the same centred: a card with its icon on top

var
  ThemeMode: Integer;   // DexmenuSetTheme: 0 as Windows' apps are, 1 light, 2 dark (the settings app's preview)

procedure DexmenuSetTheme(Mode: Integer); stdcall;
begin
  ThemeMode := Mode;
end;

function DexmenuThemePalette(Buffer: PWideChar; Chars: Integer): Integer; stdcall;
var
  Text: string;
begin
  Text := '{}';
  try
    Text := CurrentTheme(TLook.Current.Dark).PaletteText;
  except
    on E: Exception do
      Log('theme palette: ' + E.Message);
  end;
  Result := Length(Text) + 1;
  if (Buffer <> nil) and (Chars > 0) then
    StrPLCopy(Buffer, Text, Chars - 1);
end;

class function TLook.Current: TLook;
var
  Value, Size: DWORD;
begin
  if ThemeMode in [1, 2] then
  begin
    Result.Dark := ThemeMode = 2;
    Exit;
  end;
  Value := 1;
  Size := SizeOf(Value);
  RegGetValueW(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
    'AppsUseLightTheme', RRF_RT_REG_DWORD, nil, @Value, @Size);
  Result.Dark := Value = 0;
end;

// Segoe Fluent Icons (Windows 11) when it is there, else Segoe MDL2 Assets (Windows 10): mostly the same code points.
function IconFont: string;
var
  Fonts: IDWriteFontCollection;
  Index: UINT32;
  Exists: BOOL;
begin
  Result := 'Segoe MDL2 Assets';
  if Succeeded(DWrite.GetSystemFontCollection(Fonts, False)) and
    Succeeded(Fonts.FindFamilyName('Segoe Fluent Icons', Index, Exists)) and Exists then
    Result := 'Segoe Fluent Icons';
end;

// Pixels drawn into a box (DIP), centred, at most IconSize.
procedure DrawPixels(T: ID2D1RenderTarget; const Pixels: TIconPixels; CX, CY: Single);
var
  Bitmap: ID2D1Bitmap;
  Props: TD2D1BitmapProperties;
  W, H: Single;
  Dest: TD2D1RectF;
begin
  Props.pixelFormat := D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED);
  Props.dpiX := 96 * DrawScale;
  Props.dpiY := 96 * DrawScale;
  if Failed(T.CreateBitmap(D2D1SizeU(Pixels.Width, Pixels.Height), @Pixels.Bits[0], Pixels.Width * 4, Props, Bitmap)) then
    Exit;
  W := Min(IconSize, Pixels.Width / DrawScale);
  H := Min(IconSize, Pixels.Height / DrawScale);
  Dest := D2D1RectF(CX - W / 2, CY - H / 2, CX + W / 2, CY + H / 2);
  T.DrawBitmap(Bitmap, @Dest, 1, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, nil);
end;

// The icon in the slot left of a card's text (plan 02 3.8), the first there is: the layout card's own (a glyph, or an
// icon in a file), the item's own bitmap, in the preview the one kept for it; else none.
// Slot: where the icon goes, centred in it.
procedure DrawIcon(T: ID2D1RenderTarget; V: TViewCard; const Slot: TD2D1RectF; Brush: ID2D1SolidColorBrush;
  Editing: Boolean);
var
  Spec, Glyph: string;
  Pixels: TIconPixels;
  CX, CY: Single;
begin
  CX := (Slot.left + Slot.right) / 2;
  CY := (Slot.top + Slot.bottom) / 2;
  Spec := V.IconSpec;
  if IsGlyph(Spec, Glyph) then
  begin
    T.DrawText(PWideChar(Glyph), Length(Glyph), IconFormat, Slot, Brush);
    Exit;
  end;
  if (Spec <> '') and FileIconPixels(Spec, Ceil(IconSize * DrawScale), Pixels) then
  begin
    DrawPixels(T, Pixels, CX, CY);
    Exit;
  end;
  if (V.Kind = vkItem) and (V.Node <> nil) and BitmapPixels(V.Node.Item.Info.hbmpItem, Pixels) then
  begin
    DrawPixels(T, Pixels, CX, CY);
    Exit;
  end;
  // the preview: the icon a right-click or the live menu kept for this item (Dexmenu.Icons)
  if Editing and (V.Kind = vkItem) and (V.Node <> nil) and KeptIconPixels(UsageKey(V.Node), Pixels) then
  begin
    DrawPixels(T, Pixels, CX, CY);
    Exit;
  end;
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
    IconFormat := MakeFormat(IconFont, DWRITE_FONT_WEIGHT_NORMAL, IconSize, True);
    ShortcutFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_NORMAL, FontSize, False);
    ShortcutFormat.SetTextAlignment(DWRITE_TEXT_ALIGNMENT_TRAILING);
    ExtraFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_NORMAL, ExtraSize, False);
    CenterFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_NORMAL, FontSize, True);
    CenterExtraFormat := MakeFormat(TextFont, DWRITE_FONT_WEIGHT_NORMAL, ExtraSize, True);
    DWrite.CreateTextFormat(PWideChar(TextFont), nil, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, FontSize, 'en-us', NoteFormat);
    NoteFormat.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    NoteFormat.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
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

const
  NotePad = 8;   // a note's text from its card's edges (DIP)

// Where a note's text starts within its card: aligned with the items' text, or at the card's edge.
function NoteLeft(V: TViewCard): Single;
begin
  if V.Card.NoteAlign = naText then
    Result := TextLeft
  else
    Result := NotePad;
end;

// A note's text laid out in its box (width), aligned as the layout says; nil when it has no text.
function NoteLayout(V: TViewCard; Width: Single): IDWriteTextLayout;
const
  Align: array[TNoteAlign] of DWRITE_TEXT_ALIGNMENT = (DWRITE_TEXT_ALIGNMENT_LEADING, DWRITE_TEXT_ALIGNMENT_LEADING,
    DWRITE_TEXT_ALIGNMENT_CENTER, DWRITE_TEXT_ALIGNMENT_TRAILING);
var
  Text: string;
begin
  Result := nil;
  Text := V.Title;
  if (Text = '') or Failed(DWrite.CreateTextLayout(PWideChar(Text), Length(Text), NoteFormat,
    Max(1, Width - NoteLeft(V) - NotePad), 10000, Result)) then
    Exit(nil);
  Result.SetTextAlignment(Align[V.Card.NoteAlign]);
end;

// A note's height at a card width: its wrapped text, or one line's height when it has none.
function NoteHeight(V: TViewCard; Width: Single): Single;
var
  Layout: IDWriteTextLayout;
  M: TDWriteTextMetrics;
begin
  Result := ItemHeight;
  Layout := NoteLayout(V, Width);
  if (Layout <> nil) and Succeeded(Layout.GetMetrics(M)) then
    Result := Max(ItemHeight, M.height + 2 * NotePad);
end;

// A note's widest line, for the menu's width (the menu still stops at its maximum; the note then wraps).
function NoteWidth(const Text: string): Single;
var
  Line: string;
begin
  Result := 0;
  for Line in Text.Split([#10]) do
    Result := Max(Result, TextWidth(Line.TrimRight([#13]), NormalFormat));
  Result := Result + 2 * NotePad;
end;

var
  SubmenuMark, ActionMark: string;   // '' : the chevron glyph; none
  LevelWidths: TArray<TLevelWidth>;

procedure SetMenuLook(const Settings: TMenuSettings);
begin
  SubmenuMark := Settings.SubmenuMark;
  ActionMark := Settings.ActionMark;
  LevelWidths := Settings.Widths;
end;

// The room kept at a card's right for its mark; a button in a card with buttons that shows no mark keeps none, so
// more buttons fit side by side.
function MarkSpace(V: TViewCard): Single;
begin
  if V.InGroup and not V.HasSubmenu and ((ActionMark = '') or not (V.Kind in [vkItem, vkCommand])) then
    Result := 8
  else
    Result := MarkWidth;
end;

// A card whose title wraps (its layout card's "wrap", plan 03 3.5): an item, a card with a menu or Dexmenu's own item;
// not a button in a card with buttons.
function Wraps(V: TViewCard): Boolean;
begin
  Result := (V.Card <> nil) and V.Card.Wrap and (V.Kind in [vkItem, vkMenu, vkCommand]) and not V.InGroup;
end;

// The title laid out wrapping within Width (DIP) and Height (0: as high as it needs); nil when it has none.
function WrappedTitle(const Title: string; Fmt: IDWriteTextFormat; Width, Height: Single): IDWriteTextLayout;
var
  Trimming: TDwriteTrimming;
  Sign: IDWriteInlineObject;
begin
  Result := nil;
  if Height <= 0 then
    Height := 10000;
  if (Title = '') or Failed(DWrite.CreateTextLayout(PWideChar(Title), Length(Title), Fmt, Max(1, Width), Height,
    Result)) then
    Exit(nil);
  Result.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
  // a title longer than its lines: its last line cut at a word with "..."
  FillChar(Trimming, SizeOf(Trimming), 0);
  Trimming.granularity := DWRITE_TRIMMING_GRANULARITY_WORD;
  DWrite.CreateEllipsisTrimmingSign(Result, Sign);
  Result.SetTrimming(Trimming, Sign);
end;

// One line of the items' text, high (DIP).
function LineHeight: Single;
var
  Layout: IDWriteTextLayout;
  M: TDWriteTextMetrics;
begin
  Result := 16;
  if Succeeded(DWrite.CreateTextLayout('Ag', 2, NormalFormat, 1000, 1000, Layout)) and
    Succeeded(Layout.GetMetrics(M)) then
    Result := M.height;
end;

function TitleFormat(V: TViewCard): IDWriteTextFormat;
begin
  if V.IsDefault then
    Result := BoldFormat
  else
    Result := NormalFormat;
end;

function GroupNeed(V: TViewCard): Single; forward;

// What a card's content needs across (DIP): the icon slot, its title, a shortcut, the mark; a divider's label; a note;
// a card with buttons its widest button.
function CardNeed(V: TViewCard): Single;
var
  Fmt: IDWriteTextFormat;
  Word: string;
begin
  Result := 0;
  if V.Kind = vkGroup then
    Result := GroupNeed(V)
  else if (V.Kind = vkSeparator) and (V.Divider <> nil) and (V.Divider.DividerText <> '') then
    Result := TextWidth(V.Divider.DividerText, NormalFormat) + 48
  else if V.Kind = vkNote then
    Result := NoteWidth(V.Title) + NoteLeft(V) - NotePad
  else if V.Kind <> vkSeparator then
  begin
    if V.IsDefault then
      Fmt := BoldFormat
    else
      Fmt := NormalFormat;
    if Wraps(V) then
    begin
      // a title that wraps needs its longest word across, not its whole text
      Result := 0;
      for Word in V.Title.Split([' ']) do
        Result := Max(Result, TextWidth(Word, Fmt));
    end
    else
      Result := TextWidth(V.Title, Fmt);
    if V.LookCard <> nil then
      Result := Max(Result, TextWidth(V.LookCard.Extra, ExtraFormat));
    Result := TextLeft + Result + MarkSpace(V) + 8;
    if V.Shortcut <> '' then
      Result := Result + TextWidth(V.Shortcut, ShortcutFormat) + ShortcutGap;
  end;
end;

const
  GroupPad = 6;    // a card with buttons (plan 02 3.3): its buttons and title from its edges (DIP)
  ButtonGap = 2;   // between its buttons, across and down

// A card with buttons laid out at a place: its buttons' boxes, side by side, each as wide as its content (at most the
// card's inner width), wrapping onto the next row; the result is the card's height.
function GroupLayout(V: TViewCard; Left, Top, Width: Single; out Rects: TArray<TD2D1RectF>): Single;
var
  I: Integer;
  X, Y, W, Inner: Single;
begin
  SetLength(Rects, V.Buttons.Count);
  Inner := Max(1, Width - 2 * GroupPad);
  X := 0;
  Y := GroupPad + TitleHeight + ButtonGap;
  for I := 0 to V.Buttons.Count - 1 do
  begin
    W := Min(Inner, CardNeed(V.Buttons[I]));
    if (X > 0) and (X + W > Inner) then
    begin
      X := 0;
      Y := Y + ItemHeight + ButtonGap;
    end;
    Rects[I] := D2D1RectF(Left + GroupPad + X, Top + Y, Left + GroupPad + X + W, Top + Y + ItemHeight);
    X := X + W + ButtonGap;
  end;
  Result := Y + ItemHeight + GroupPad;
end;

function GroupNeed(V: TViewCard): Single;
var
  B: TViewCard;
begin
  Result := TextWidth(V.Title, BoldFormat);
  for B in V.Buttons do
    Result := Max(Result, CardNeed(B));
  Result := Result + 2 * GroupPad;
end;

// The layout card's size settings (plan 03 3.5); a view card without one (Windows' items in a submenu, the most used
// row) has the defaults.
function CardMin(V: TViewCard): Single;
begin
  Result := 0;
  if (V.Card <> nil) and (V.Kind <> vkSeparator) then
    Result := V.Card.MinWidth;
end;

function CardWeight(V: TViewCard): Single;
begin
  Result := 1;
  if (V.Card <> nil) and (V.Kind <> vkSeparator) then
    Result := V.Card.Weight;
end;

// A card's own height at a width: a note's wrapped text, a card with buttons its rows, a fixed height in lines, else
// one line.
function CardHeight(V: TViewCard; Width: Single): Single;
var
  Rects: TArray<TD2D1RectF>;
  Layout: IDWriteTextLayout;
  M: TDWriteTextMetrics;
begin
  Result := ItemHeight;
  if V.Kind = vkGroup then
    Exit(GroupLayout(V, 0, 0, Width, Rects))
  else if V.Kind = vkNote then
    Result := NoteHeight(V, Width)
  else if (V.LookCard <> nil) and (V.LookCard.Extra <> '') then
    Result := ItemHeight + ExtraHeight;   // the title and its extra text
  if Wraps(V) and (V.Card.Height <= 0) then
  begin
    // as high as its wrapped title's lines, with a single line's room around them
    Layout := WrappedTitle(V.Title, TitleFormat(V), Width - TextLeft - MarkSpace(V), 0);
    if (Layout <> nil) and Succeeded(Layout.GetMetrics(M)) then
      Result := Result + Max(0, M.height - LineHeight);
  end;
  if (V.Card <> nil) and (V.Kind <> vkSeparator) and (V.Card.Height > 0) then
    Result := V.Card.Height * ItemHeight;
end;

function CardFitOf(V: TViewCard; Line: TViewLine): TCardFit;
begin
  Result := cfDefault;
  if (V.Card <> nil) and (V.Kind <> vkSeparator) then
    Result := V.Card.CardFit;
  if Result = cfDefault then
    Result := Line.CardFit;
  if Result = cfDefault then
    Result := cfStretch;
end;

function Measure(Level: TViewLevel; Depth: Integer): TGeometry;
var
  LevelMin, LevelMax, CardGap, LineGap: Single;
  Theme: TTheme;
  Line: TViewLine;
  Rows: TList<TArray<TViewCard>>;
  Row: TArray<TViewCard>;
  Widths: TArray<Single>;
  Fixed: TArray<Boolean>;
  V: TViewCard;
  W, Y, H, X, Need, SumMin, Avail, FreeWeight, OwnH, Top: Single;
  N, I, J: Integer;
  Changed, First: Boolean;
  Box: TBox;
  Fit: TCardFit;
  RowLines: TList<TViewLine>;
  Rects: TArray<TD2D1RectF>;
  K: Integer;
begin
  EnsureFactories;
  LevelMin := MinWidth;
  LevelMax := MaxWidth;
  if Length(LevelWidths) > 0 then
  begin
    LevelMin := LevelWidths[Min(Depth, High(LevelWidths))].MinW;
    LevelMax := LevelWidths[Min(Depth, High(LevelWidths))].MaxW;
  end;
  // the gaps between cards on a line and between lines (plan 03 3.5): the theme's, none unless it gives them
  Theme := CurrentTheme(TLook.Current.Dark);
  CardGap := Max(0, Theme.Number('card', 'normal', 'gap', 0));
  LineGap := Max(0, Theme.Number('line', 'normal', 'gap', 0));

  Rows := TList<TArray<TViewCard>>.Create;
  RowLines := TList<TViewLine>.Create;
  try
    // A line whose cards do not fit side by side at their minimum widths within the level's maximum: its last cards
    // wrap onto a line of their own below it, in their order.
    for Line in Level.Lines do
    begin
      Row := nil;
      SumMin := 0;
      for V in Line.Cards do
      begin
        if (Length(Row) > 0) and (SumMin + CardGap + CardMin(V) > LevelMax - 2 * OuterPad) then
        begin
          Rows.Add(Row);
          RowLines.Add(Line);
          Row := nil;
          SumMin := 0;
        end;
        if Length(Row) > 0 then
          SumMin := SumMin + CardGap;
        SumMin := SumMin + CardMin(V);
        Row := Row + [V];
      end;
      if Length(Row) > 0 then
      begin
        Rows.Add(Row);
        RowLines.Add(Line);
      end;
    end;

    // The width: the widest line's need (each card at least its minimum width), between the level's minimum and its
    // maximum.
    W := LevelMin;
    for Row in Rows do
    begin
      Need := CardGap * (Length(Row) - 1);
      for V in Row do
        Need := Need + Max(CardNeed(V), CardMin(V));
      W := Max(W, Need + 2 * OuterPad);
    end;
    W := Min(W, LevelMax);

    Result.Boxes := nil;
    Y := OuterPad;
    First := True;
    for I := 0 to Rows.Count - 1 do
    begin
      Row := Rows[I];
      Line := RowLines[I];
      N := Length(Row);
      if not First then
        Y := Y + LineGap;
      First := False;
      // the cards share the width by their weights; one whose share is below its minimum gets its minimum, and the
      // others share the rest
      SetLength(Widths, N);
      SetLength(Fixed, N);
      for J := 0 to N - 1 do
        Fixed[J] := False;
      repeat
        Changed := False;
        Avail := W - 2 * OuterPad - CardGap * (N - 1);
        FreeWeight := 0;
        for J := 0 to N - 1 do
          if Fixed[J] then
            Avail := Avail - Widths[J]
          else
            FreeWeight := FreeWeight + CardWeight(Row[J]);
        for J := 0 to N - 1 do
          if not Fixed[J] then
          begin
            Widths[J] := Max(0, Avail) * CardWeight(Row[J]) / Max(FreeWeight, 0.0001);
            if Widths[J] < CardMin(Row[J]) then
            begin
              Widths[J] := CardMin(Row[J]);
              Fixed[J] := True;
              Changed := True;
            end;
          end;
      until not Changed;
      // the line as high as its highest card
      if (N = 1) and (Row[0].Kind = vkSeparator) then
      begin
        H := SeparatorHeight;
        if (Row[0].Divider <> nil) and (Row[0].Divider.DividerText <> '') then
          H := DividerTextHeight;
      end
      else
      begin
        H := 0;
        for J := 0 to N - 1 do
          H := Max(H, CardHeight(Row[J], Widths[J]));
      end;
      X := OuterPad;
      for J := 0 to N - 1 do
      begin
        V := Row[J];
        Box.Card := V;
        OwnH := H;
        Top := Y;
        if V.Kind <> vkSeparator then
        begin
          // a lower card: stretched to the line, or at its own height at the line's top, centre or bottom
          Fit := CardFitOf(V, Line);
          if Fit <> cfStretch then
          begin
            OwnH := Min(H, CardHeight(V, Widths[J]));
            case Fit of
              cfCenter: Top := Y + (H - OwnH) / 2;
              cfBottom: Top := Y + H - OwnH;
            end;
          end;
        end;
        Box.Rect := D2D1RectF(X, Top, X + Widths[J], Top + OwnH);
        Box.Alone := N = 1;
        Result.Boxes := Result.Boxes + [Box];
        // a card with buttons: its buttons' boxes follow its own, inside it
        if V.Kind = vkGroup then
        begin
          GroupLayout(V, X, Top, Widths[J], Rects);
          for K := 0 to High(Rects) do
          begin
            Box.Card := V.Buttons[K];
            Box.Rect := Rects[K];
            Box.Alone := False;
            Result.Boxes := Result.Boxes + [Box];
          end;
        end;
        X := X + Widths[J] + CardGap;
      end;
      Y := Y + H;
    end;
  finally
    RowLines.Free;
    Rows.Free;
  end;
  Result.Width := W;
  Result.Height := Y + OuterPad;
  Result.Pressed := -1;
end;

function BoxAt(const G: TGeometry; X, Y, ScrollY: Single): Integer;
var
  I: Integer;
begin
  Y := Y + ScrollY;
  for I := 0 to High(G.Boxes) do
    with G.Boxes[I].Rect do
      if (X >= left) and (X < right) and (Y >= top) and (Y < bottom) and (G.Boxes[I].Card.Kind <> vkGroup) then
        Exit(I);   // a card with buttons is no button itself: its buttons are
  Result := -1;
end;

function ToD2D(const C: TRGBA): TD2D1ColorF;
begin
  Result := D2D1ColorF(C.R, C.G, C.B, C.A);
end;

// A theme's background for an element and state over a rounded box (plan 03 3.4): a colour, or a linear gradient at
// its angle across the box; False (nothing drawn) when the theme gives none.
function FillBackground(T: ID2D1RenderTarget; Theme: TTheme; const Element, State: string; const R: TD2D1RectF;
  Radius: Single; Own: TJSONObject = nil; StateOnly: Boolean = False): Boolean;
var
  Colors: TArray<TRGBA>;
  Angle, CX, CY, DX, DY, Half: Single;
  Stops: TArray<TD2D1GradientStop>;
  I: Integer;
  Collection: ID2D1GradientStopCollection;
  Gradient: ID2D1LinearGradientBrush;
  Solid: ID2D1SolidColorBrush;
  Box: TD2D1RoundedRect;
begin
  Result := Theme.Background(Element, State, Colors, Angle, Own, StateOnly);
  if not Result then
    Exit;
  Box := D2D1RoundedRect(R, Radius, Radius);
  if Length(Colors) = 1 then
  begin
    if Colors[0].A <= 0 then
      Exit(False);
    T.CreateSolidColorBrush(ToD2D(Colors[0]), nil, Solid);
    T.FillRoundedRectangle(Box, Solid);
    Exit;
  end;
  SetLength(Stops, Length(Colors));
  for I := 0 to High(Colors) do
    Stops[I] := D2D1GradientStop(I / High(Colors), ToD2D(Colors[I]));
  // the gradient's line through the box's middle at the angle, long enough to reach its corners
  CX := (R.left + R.right) / 2;
  CY := (R.top + R.bottom) / 2;
  DX := Cos(DegToRad(Angle));
  DY := Sin(DegToRad(Angle));
  Half := (Abs(DX) * (R.right - R.left) + Abs(DY) * (R.bottom - R.top)) / 2;
  if Failed(T.CreateGradientStopCollection(@Stops[0], Length(Stops), D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP,
    Collection)) or Failed(T.CreateLinearGradientBrush(D2D1LinearGradientBrushProperties(
    D2D1PointF(CX - DX * Half, CY - DY * Half), D2D1PointF(CX + DX * Half, CY + DY * Half)), nil, Collection,
    Gradient)) then
    Exit(False);
  T.FillRoundedRectangle(Box, Gradient);
end;

// Diagonal stripes over a box: an item not always there (the preview only).
procedure DrawStripes(T: ID2D1RenderTarget; const R: TD2D1RectF; Brush: ID2D1SolidColorBrush);
const
  Gap = 7;
var
  X: Single;
begin
  T.PushAxisAlignedClip(R, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  X := R.left - (R.bottom - R.top);
  while X < R.right do
  begin
    T.DrawLine(D2D1PointF(X, R.bottom), D2D1PointF(X + (R.bottom - R.top), R.top), Brush, 1.5);
    X := X + Gap;
  end;
  T.PopAxisAlignedClip;
end;

// A divider with a text: the text left, in the middle or right, the line on the rest of the width.
procedure DrawDividerText(T: ID2D1RenderTarget; D: TLine; const R: TD2D1RectF; Y: Single; Line, Text: ID2D1SolidColorBrush);
const
  Pad = 8;
  Gap = 6;
var
  W, X: Single;
  Label_: string;
begin
  Label_ := D.DividerText;
  W := Min(TextWidth(Label_, NormalFormat), R.right - R.left - 4 * Pad);
  case D.DividerAlign of
    daCenter: X := (R.left + R.right - W) / 2;
    daRight: X := R.right - Pad - W;
  else
    X := R.left + Pad;
  end;
  if X - Gap > R.left + Pad then
    T.DrawLine(D2D1PointF(R.left + Pad, Y), D2D1PointF(X - Gap, Y), Line, 1);
  if X + W + Gap < R.right - Pad then
    T.DrawLine(D2D1PointF(X + W + Gap, Y), D2D1PointF(R.right - Pad, Y), Line, 1);
  T.DrawText(PWideChar(Label_), Length(Label_), NormalFormat, D2D1RectF(X, R.top, X + W + 1, R.bottom), Text,
    D2D1_DRAW_TEXT_OPTIONS_CLIP);
end;

procedure DrawLevel(T: ID2D1RenderTarget; const G: TGeometry; Selected: Integer; ScrollY, VisibleHeight: Single;
  const Look: TLook; const Marked: string; Editing: Boolean);
var
  Bg, Border, Text, Dim, Extra, Hover, Sep, LabelBrush, Accent, Stripe: ID2D1SolidColorBrush;
  Theme: TTheme;
  MenuRadius, CardRadius: Single;
  I: Integer;
  R: TD2D1RectF;
  V: TViewCard;
  Title: string;
  NoteText: IDWriteTextLayout;
  Fmt: IDWriteTextFormat;
  Brush: ID2D1SolidColorBrush;
  Y, H, TitleRight, TitleTop, TitleBottom: Single;
  Metrics: TDWriteTextMetrics;
  Shortcut: string;
  Access: Integer;
  TitleLayout: IDWriteTextLayout;
  Range: TDwriteTextRange;
  Own: TJSONObject;
  ExtraText, Element, State: string;
  ExtraAbove: Boolean;
  Inner: TD2D1RectF;
  BorderColor, Foreground: TRGBA;
  CardBorder, ExtraBrush, MarkBrush: ID2D1SolidColorBrush;
begin
  // every colour and radius from the theme for light or dark (plan 03 3.2; Dexmenu.Theme)
  Theme := CurrentTheme(Look.Dark);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('menu', 'normal', 'background', RGBA($F9, $F9, $F9))), nil, Bg);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('menu', 'normal', 'border', RGBA($D0, $D0, $D0))), nil, Border);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'normal', 'foreground', RGBA($1B, $1B, $1B))), nil, Text);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'disabled', 'foreground', RGBA($A0, $A0, $A0))), nil, Dim);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'normal', 'extra', RGBA($A0, $A0, $A0))), nil, Extra);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'hover', 'background', RGBA(0, 0, 0, 0.06))), nil, Hover);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('divider', 'normal', 'border', RGBA($E0, $E0, $E0))), nil, Sep);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('divider', 'normal', 'foreground', RGBA($A0, $A0, $A0))), nil, LabelBrush);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'focused', 'border', RGBA($2F, $6F, $D6))), nil, Accent);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'unavailable', 'background', RGBA(0, 0, 0, 0.09))), nil, Stripe);
  MenuRadius := Theme.Number('menu', 'normal', 'radius', WindowRadius);
  T.Clear(D2D1ColorF(0, 0, 0, 0));
  R := D2D1RectF(0.5, 0.5, G.Width - 0.5, VisibleHeight - 0.5);
  if not FillBackground(T, Theme, 'menu', 'normal', R, MenuRadius) then
    T.FillRoundedRectangle(D2D1RoundedRect(R, MenuRadius, MenuRadius), Bg);
  T.DrawRoundedRectangle(D2D1RoundedRect(R, MenuRadius, MenuRadius), Border, 1);
  T.PushAxisAlignedClip(D2D1RectF(1, OuterPad, G.Width - 1, VisibleHeight - OuterPad), D2D1_ANTIALIAS_MODE_ALIASED);
  for I := 0 to High(G.Boxes) do
  begin
    V := G.Boxes[I].Card;
    R := G.Boxes[I].Rect;
    R.top := R.top - ScrollY;
    R.bottom := R.bottom - ScrollY;
    if (R.bottom < 0) or (R.top > VisibleHeight) then
      Continue;
    if V.Kind = vkNote then
    begin
      // a note: its text in the dim colour, aligned as the layout says; no button (no hover, no mark)
      NoteText := NoteLayout(V, R.right - R.left);
      if NoteText <> nil then
        T.DrawTextLayout(D2D1PointF(R.left + NoteLeft(V), R.top + NotePad), NoteText, Extra, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      Continue;
    end;
    if V.Kind = vkSeparator then
    begin
      Y := Round((R.top + R.bottom) / 2) + 0.5;
      if (V.Divider = nil) or (V.Divider.DividerText = '') then
        T.DrawLine(D2D1PointF(R.left + 8, Y), D2D1PointF(R.right - 8, Y), Sep, 1)
      else
        DrawDividerText(T, V.Divider, R, Y, Sep, LabelBrush);
      Continue;
    end;
    // a card's look (plan 03 3.6, 3.7): the theme's "item" when alone on its line, else its "card"; its own look from
    // the layout over it; the state: disabled, pressed, hover or normal
    Own := nil;
    ExtraText := '';
    ExtraAbove := False;
    if V.LookCard <> nil then
    begin
      Own := V.LookCard.Look;
      ExtraText := V.LookCard.Extra;
      ExtraAbove := V.LookCard.ExtraAbove;
    end;
    if G.Boxes[I].Alone then
      Element := 'item'
    else
      Element := 'card';
    if V.Kind = vkGroup then
    begin
      // a card with buttons (plan 02 3.3): its background and a frame (its border, else the dividers' colour), its
      // title at the top; its buttons are boxes of their own, drawn after it
      CardRadius := Theme.Number(Element, 'normal', 'radius', ItemRadius, Own);
      Inner := D2D1RectF(R.left + 2, R.top + 1, R.right - 2, R.bottom - 1);
      FillBackground(T, Theme, Element, 'normal', Inner, CardRadius, Own);
      BorderColor := Theme.Color(Element, 'normal', 'border', RGBA(0, 0, 0, 0), Own);
      if BorderColor.A > 0 then
        T.CreateSolidColorBrush(ToD2D(BorderColor), nil, CardBorder)
      else
        CardBorder := Sep;
      T.DrawRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), CardBorder,
        Theme.Number(Element, 'normal', 'borderWidth', 1, Own));
      if (Marked <> '') and (V.CardId = Marked) then
        T.DrawRoundedRectangle(D2D1RoundedRect(D2D1RectF(R.left + 1.5, R.top + 1, R.right - 1.5, R.bottom - 1),
          CardRadius, CardRadius), Accent, 1.5);
      T.CreateSolidColorBrush(ToD2D(Theme.Color(Element, 'normal', 'foreground', RGBA($1B, $1B, $1B), Own)), nil, Brush);
      Title := V.Title;
      if Title <> '' then
        T.DrawText(PWideChar(Title), Length(Title), BoldFormat, D2D1RectF(R.left + GroupPad + 4, R.top + GroupPad,
          R.right - GroupPad, R.top + GroupPad + TitleHeight), Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      Continue;
    end;
    if not V.Enabled then
      State := 'disabled'
    else if I = G.Pressed then
      State := 'pressed'
    else if I = Selected then
      State := 'hover'
    else
      State := 'normal';
    CardRadius := Theme.Number(Element, 'normal', 'radius', ItemRadius, Own);
    Inner := D2D1RectF(R.left + 2, R.top + 1, R.right - 2, R.bottom - 1);
    if V.Kind in [vkItem, vkMenu, vkCommand] then
      FillBackground(T, Theme, Element, 'normal', Inner, CardRadius, Own);
    if Editing and V.Sometimes then
      DrawStripes(T, Inner, Stripe);
    // hover and pressed over the normal background: the state's own, a pressed card without one as hovered
    if (State = 'pressed') and not FillBackground(T, Theme, Element, 'pressed', Inner, CardRadius, Own, True) then
      State := 'hover';
    if (State = 'hover') and not FillBackground(T, Theme, Element, 'hover', Inner, CardRadius, Own, True) then
      T.FillRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), Hover);
    BorderColor := Theme.Color(Element, State, 'border', RGBA(0, 0, 0, 0), Own);
    if BorderColor.A > 0 then
    begin
      T.CreateSolidColorBrush(ToD2D(BorderColor), nil, CardBorder);
      T.DrawRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), CardBorder,
        Theme.Number(Element, State, 'borderWidth', 1, Own));
    end;
    // the items of the card selected in the settings app's editor (the preview only)
    if (Marked <> '') and (V.CardId = Marked) then
      T.DrawRoundedRectangle(D2D1RoundedRect(D2D1RectF(R.left + 1.5, R.top + 1, R.right - 1.5, R.bottom - 1),
        CardRadius, CardRadius), Accent, 1.5);
    // the title's colour (a disabled card's from the theme's "disabled"), the mark's in it unless the theme gives one
    if V.Enabled then
      Foreground := Theme.Color(Element, State, 'foreground', RGBA($1B, $1B, $1B), Own)
    else
      Foreground := Theme.Color(Element, 'disabled', 'foreground', RGBA($A0, $A0, $A0), Own);
    T.CreateSolidColorBrush(ToD2D(Foreground), nil, Brush);
    T.CreateSolidColorBrush(ToD2D(Theme.Color(Element, State, 'extra', RGBA($A0, $A0, $A0), Own)), nil, ExtraBrush);
    if V.IsDefault then
      Fmt := BoldFormat
    else
      Fmt := NormalFormat;
    Title := V.Title;
    // a tall or square card: its icon at the top, the title and extra text under it, centred, the mark in the corner
    if (V.Kind in [vkItem, vkMenu, vkCommand]) and (R.bottom - R.top >= R.right - R.left) then
    begin
      Y := R.top + Max(4, (R.bottom - R.top - (IconSize + 8 + TitleHeight + Ord(ExtraText <> '') * ExtraHeight)) / 2);
      if V.Checked then
        T.DrawText(PWideChar(CheckGlyph), 1, GlyphFormat, D2D1RectF(R.left, Y, R.right, Y + IconSize + 8), Brush)
      else
        DrawIcon(T, V, D2D1RectF(R.left, Y, R.right, Y + IconSize + 8), Brush, Editing);
      Y := Y + IconSize + 8;
      if ExtraAbove and (ExtraText <> '') then
      begin
        T.DrawText(PWideChar(ExtraText), Length(ExtraText), CenterExtraFormat, D2D1RectF(R.left + 4, Y, R.right - 4,
          Y + ExtraHeight), ExtraBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
        Y := Y + ExtraHeight;
      end;
      if (Title <> '') and Wraps(V) then
      begin
        // the title's lines under the icon, as many as fit above the extra text below it
        H := R.bottom - 4 - Y - Ord(not ExtraAbove and (ExtraText <> '')) * ExtraHeight;
        TitleLayout := WrappedTitle(Title, CenterFormat, R.right - R.left - 8, Max(TitleHeight, H));
        if TitleLayout <> nil then
        begin
          TitleLayout.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
          T.DrawTextLayout(D2D1PointF(R.left + 4, Y), TitleLayout, Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
          if Succeeded(TitleLayout.GetMetrics(Metrics)) then
            Y := Y + Min(Max(TitleHeight, H), Max(TitleHeight, Metrics.height)) - TitleHeight;
        end;
      end
      else if Title <> '' then
        T.DrawText(PWideChar(Title), Length(Title), CenterFormat, D2D1RectF(R.left + 4, Y, R.right - 4,
          Y + TitleHeight), Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      Y := Y + TitleHeight;
      if not ExtraAbove and (ExtraText <> '') then
        T.DrawText(PWideChar(ExtraText), Length(ExtraText), CenterExtraFormat, D2D1RectF(R.left + 4, Y, R.right - 4,
          Y + ExtraHeight), ExtraBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      if V.HasSubmenu then
        T.DrawText(PWideChar(ChevronGlyph), 1, GlyphFormat, D2D1RectF(R.right - 18, R.top + 2, R.right - 4, R.top + 16),
          Brush);
      Continue;
    end;
    if V.Checked then
      T.DrawText(PWideChar(CheckGlyph), 1, GlyphFormat, D2D1RectF(R.left + 6, R.top, R.left + TextLeft - 6, R.bottom),
        Brush)
    else if V.Kind in [vkItem, vkMenu, vkCommand] then
      DrawIcon(T, V, D2D1RectF(R.left + 6, R.top, R.left + TextLeft - 6, R.bottom), Brush, Editing);
    // the marks (the global settings): a submenu's (the chevron unless one is set), an action's (none unless set)
    T.CreateSolidColorBrush(ToD2D(Theme.Color(Element, State, 'mark', Foreground, Own)), nil, MarkBrush);
    if V.HasSubmenu and (SubmenuMark = '') then
      T.DrawText(PWideChar(ChevronGlyph), 1, GlyphFormat, D2D1RectF(R.right - MarkWidth, R.top, R.right - 6, R.bottom),
        MarkBrush)
    else if V.HasSubmenu then
      T.DrawText(PWideChar(SubmenuMark), Length(SubmenuMark), NormalFormat, D2D1RectF(R.right - MarkWidth + 6, R.top,
        R.right - 4, R.bottom), MarkBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP)
    else if (ActionMark <> '') and (V.Kind in [vkItem, vkCommand]) then
      T.DrawText(PWideChar(ActionMark), Length(ActionMark), NormalFormat, D2D1RectF(R.right - MarkWidth + 6, R.top,
        R.right - 4, R.bottom), MarkBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
    // the title's line, and the extra text's above or below it, the two centred in the card together; a title that
    // wraps: its lines within the card, the extra text's line above or below them
    TitleTop := R.top;
    TitleBottom := R.bottom;
    if Wraps(V) then
    begin
      TitleTop := R.top + (ItemHeight - LineHeight) / 2;
      TitleBottom := Max(TitleTop + LineHeight, R.bottom - (ItemHeight - LineHeight) / 2);
      if ExtraText <> '' then
      begin
        if ExtraAbove then
        begin
          T.DrawText(PWideChar(ExtraText), Length(ExtraText), ExtraFormat, D2D1RectF(R.left + TextLeft, TitleTop,
            R.right - MarkWidth, TitleTop + ExtraHeight), ExtraBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
          TitleTop := TitleTop + ExtraHeight;
        end
        else
        begin
          TitleBottom := Max(TitleTop + LineHeight, TitleBottom - ExtraHeight);
          T.DrawText(PWideChar(ExtraText), Length(ExtraText), ExtraFormat, D2D1RectF(R.left + TextLeft, TitleBottom,
            R.right - MarkWidth, TitleBottom + ExtraHeight), ExtraBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
        end;
      end;
    end
    else if ExtraText <> '' then
    begin
      TitleTop := R.top + (R.bottom - R.top - TitleHeight - ExtraHeight) / 2;
      if ExtraAbove then
      begin
        T.DrawText(PWideChar(ExtraText), Length(ExtraText), ExtraFormat, D2D1RectF(R.left + TextLeft, TitleTop,
          R.right - MarkWidth, TitleTop + ExtraHeight), ExtraBrush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
        TitleTop := TitleTop + ExtraHeight;
      end
      else
        T.DrawText(PWideChar(ExtraText), Length(ExtraText), ExtraFormat, D2D1RectF(R.left + TextLeft,
          TitleTop + TitleHeight, R.right - MarkWidth, TitleTop + TitleHeight + ExtraHeight), ExtraBrush,
          D2D1_DRAW_TEXT_OPTIONS_CLIP);
      TitleBottom := TitleTop + TitleHeight;
    end;
    // the shortcut Windows' text gives ("Ctrl+X"), dim, at the right before the mark; the title stops short of it
    TitleRight := R.right - MarkSpace(V);
    Shortcut := V.Shortcut;
    if Shortcut <> '' then
    begin
      T.DrawText(PWideChar(Shortcut), Length(Shortcut), ShortcutFormat, D2D1RectF(R.left + TextLeft, TitleTop,
        R.right - MarkSpace(V), TitleBottom), Extra, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      TitleRight := Max(R.left + TextLeft, TitleRight - TextWidth(Shortcut, ShortcutFormat) - ShortcutGap);
    end;
    // the access key (the letter Windows' text marks with "&") underlined: that key picks the item
    Access := V.AccessIndex;
    if Wraps(V) then
    begin
      TitleLayout := WrappedTitle(Title, Fmt, TitleRight - R.left - TextLeft, TitleBottom - TitleTop);
      if TitleLayout <> nil then
      begin
        // lines centred in their room; more lines than fit: from the top, the last one cut
        if Succeeded(TitleLayout.GetMetrics(Metrics)) and (Metrics.height > TitleBottom - TitleTop + 0.5) then
          TitleLayout.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
        if Access >= 0 then
        begin
          Range.startPosition := Access;
          Range.length := 1;
          TitleLayout.SetUnderline(True, Range);
        end;
        T.DrawTextLayout(D2D1PointF(R.left + TextLeft, TitleTop), TitleLayout, Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      end;
    end
    else if (Title <> '') and (Access >= 0) and Succeeded(DWrite.CreateTextLayout(PWideChar(Title), Length(Title), Fmt,
      Max(1, TitleRight - R.left - TextLeft), TitleBottom - TitleTop, TitleLayout)) then
    begin
      Range.startPosition := Access;
      Range.length := 1;
      TitleLayout.SetUnderline(True, Range);
      T.DrawTextLayout(D2D1PointF(R.left + TextLeft, TitleTop), TitleLayout, Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
    end
    else if Title <> '' then
      T.DrawText(PWideChar(Title), Length(Title), Fmt, D2D1RectF(R.left + TextLeft, TitleTop, TitleRight,
        TitleBottom), Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
  end;
  T.PopAxisAlignedClip;
end;

function Render(const G: TGeometry; Selected: Integer; ScrollY, Scale, VisibleHeight: Single;
  const Marked: string; Editing: Boolean): TPicture;
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
    DrawScale := Scale;
    Target.BeginDraw;
    DrawLevel(Target, G, Selected, ScrollY, VisibleHeight, TLook.Current, Marked, Editing);
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
  Pointer(IconFormat) := nil;
  Pointer(ShortcutFormat) := nil;
  Pointer(NoteFormat) := nil;
  Pointer(ExtraFormat) := nil;
  Pointer(CenterFormat) := nil;
  Pointer(CenterExtraFormat) := nil;
  Pointer(DWrite) := nil;
  Pointer(D2D) := nil;

end.
