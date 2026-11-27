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
    KeyFocus: Boolean;       // the selection moved by the keys (plan 03 3.7): it gets the focus ring; Measure sets False
    MenuCard: TCard;         // the top level's: the layout's menu card, its style over the theme's menu (plan 11 3.9)
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
// The menu's own shadow (plan 03 3.4; the menu card's "shadow"), as a picture to show behind the level: its window
// is Margin pixels larger on each side than the level's. Width 0: no shadow (none set, or a see-through menu).
function RenderShadow(const G: TGeometry; Scale, VisibleHeight: Single; out Margin: Integer): TPicture;
// The menu's shadow shown in its own window (layered, taking no mouse) just behind the level's window Wnd at
// ScreenPos; hidden when there is none.
procedure PresentShadow(ShadowWnd, Wnd: HWND; const ScreenPos: TPoint; const G: TGeometry; Scale, VisibleHeight: Single);
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

var
  NoteFormats: TDictionary<string, IDWriteTextFormat>;   // a note's own font's format, by its font (made once)

// A text format for a font (plan 03 3.6, 3.8): the items' font, a card's smaller extra text, or its own (family, size,
// bold, italic; the items' for what it does not give). Wrap: wrapping, from the top (a note); else one line (a
// divider's label). Made once per font.
function FontFormat(const F: TFontSpec; Wrap: Boolean): IDWriteTextFormat;
var
  Family, Key: string;
  Size: Single;
  Weight: DWRITE_FONT_WEIGHT;
  Style: DWRITE_FONT_STYLE;
  Plain: IDWriteTextFormat;
begin
  if Wrap then
    Plain := NoteFormat
  else
    Plain := NormalFormat;
  Result := Plain;
  if not (F.Extra or F.Own) then
    Exit;
  Family := TextFont;
  Size := FontSize;
  Weight := DWRITE_FONT_WEIGHT_NORMAL;
  Style := DWRITE_FONT_STYLE_NORMAL;
  if F.Extra then
    Size := ExtraSize
  else
  begin
    if F.Family <> '' then
      Family := F.Family;
    if F.Size > 0 then
      Size := F.Size;
    if F.Bold then
      Weight := DWRITE_FONT_WEIGHT_SEMI_BOLD;
    if F.Italic then
      Style := DWRITE_FONT_STYLE_ITALIC;
  end;
  Key := Format('%s|%g|%d|%d|%s', [Family, Size, Ord(Weight), Ord(Style), BoolToStr(Wrap, True)]);
  FactoryLock.Enter;
  try
    if NoteFormats = nil then
      NoteFormats := TDictionary<string, IDWriteTextFormat>.Create;
    if NoteFormats.TryGetValue(Key, Result) then
      Exit;
    if Failed(DWrite.CreateTextFormat(PWideChar(Family), nil, Weight, Style, DWRITE_FONT_STRETCH_NORMAL, Size, 'en-us',
      Result)) then
      Exit(Plain);   // a font that is not there: the items' font
    if Wrap then
    begin
      Result.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
      Result.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
    end
    else
    begin
      Result.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
      Result.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    end;
    NoteFormats.Add(Key, Result);
  finally
    FactoryLock.Leave;
  end;
end;

// A note's text format: its font, wrapping.
function NoteFormatOf(V: TViewCard): IDWriteTextFormat;
begin
  if V.Card = nil then
    Exit(NoteFormat);
  Result := FontFormat(V.Card.Font, True);
end;

// A divider label's text format: its font, one line.
function DividerFormat(D: TLine): IDWriteTextFormat;
begin
  Result := FontFormat(D.DividerFont, False);
end;

// A divider's line width (plan 18 3.1): its "thickness", else 1.
function LineThickness(D: TLine): Single;
begin
  if (D <> nil) and (D.DividerThickness > 0) then
    Result := D.DividerThickness
  else
    Result := 1;
end;

// An upright divider's width (plan 18 3.2): its own "height" (read as its width there), else a plain divider's height.
function UprightWidth(D: TLine): Single;
begin
  if (D <> nil) and (D.DividerHeight > 0) then
    Result := D.DividerHeight
  else
    Result := Max(SeparatorHeight, LineThickness(D) + 8);
end;

// A divider's height: its own, else one with a label (as high as its font needs) or a plain line's.
function DividerHeightOf(D: TLine): Single;
begin
  if (D <> nil) and (D.DividerHeight > 0) then
    Exit(D.DividerHeight);
  if (D = nil) or (D.DividerText = '') then
    Exit(Max(SeparatorHeight, LineThickness(D) + 8));
  Result := DividerTextHeight;
  if D.DividerFont.Own and (D.DividerFont.Size > 0) then
    Result := Max(Result, D.DividerFont.Size * 1.4 + 8);
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
  if (Text = '') or Failed(DWrite.CreateTextLayout(PWideChar(Text), Length(Text), NoteFormatOf(V),
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

// A note's widest line in its font, for the menu's width (the menu still stops at its maximum; the note then wraps).
function NoteWidth(V: TViewCard): Single;
var
  Line: string;
begin
  Result := 0;
  for Line in V.Title.Split([#10]) do
    Result := Max(Result, TextWidth(Line.TrimRight([#13]), NoteFormatOf(V)));
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
  Result := (V.SizeCard <> nil) and V.SizeCard.Wrap and (V.Kind in [vkItem, vkMenu, vkCommand]);
end;

const
  ZeroWidthSpace = #$200B;

// The title laid out wrapping within Width (DIP) and Height (0: as high as it needs); nil when it has none. Access:
// the index of the letter to underline (the access key), -1 none.
// A word wider than a line is broken over lines, not cut: DirectWrite cuts it with "..." instead when the layout has
// a trimming sign (the formats have one). So the title is laid out first without one, and where a line ends inside a
// word a zero-width space is put in, a place to break; then laid out with the sign, which now cuts only a last line
// that does not fit in Height.
function WrappedTitle(const Title: string; Fmt: IDWriteTextFormat; Width, Height: Single;
  Access: Integer = -1): IDWriteTextLayout;
var
  Trimming: TDwriteTrimming;
  Sign: IDWriteInlineObject;
  Plain: IDWriteTextLayout;
  Lines: array of TDwriteLineMetrics;
  Count: Cardinal;
  Text: string;
  I, At: Integer;
  Range: TDwriteTextRange;
begin
  Result := nil;
  if Height <= 0 then
    Height := 10000;
  if Title = '' then
    Exit;
  Text := Title;
  FillChar(Trimming, SizeOf(Trimming), 0);
  if Succeeded(DWrite.CreateTextLayout(PWideChar(Title), Length(Title), Fmt, Max(1, Width), 10000, Plain)) then
  begin
    Plain.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
    Plain.SetTrimming(Trimming, nil);   // none: a long word is broken
    Count := 0;
    Plain.GetLineMetrics(nil, 0, Count);
    if Count > 1 then
    begin
      SetLength(Lines, Count);
      if Succeeded(Plain.GetLineMetrics(@Lines[0], Count, Count)) then
      begin
        // from the end, so the positions before stay where they are
        At := Length(Title);
        for I := Integer(Count) - 1 downto 0 do
        begin
          if (I < Integer(Count) - 1) and (At > 0) and (At < Length(Title)) and (Title[At] > ' ') and
            (Title[At + 1] > ' ') then
          begin
            Insert(ZeroWidthSpace, Text, At + 1);
            if (Access >= At) then
              Inc(Access);
          end;
          At := At - Integer(Lines[I].length);
        end;
      end;
    end;
  end;
  if Failed(DWrite.CreateTextLayout(PWideChar(Text), Length(Text), Fmt, Max(1, Width), Height, Result)) then
    Exit(nil);
  Result.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
  // a title longer than its lines: its last line cut at a word with "..."
  Trimming.granularity := DWRITE_TRIMMING_GRANULARITY_WORD;
  DWrite.CreateEllipsisTrimmingSign(Result, Sign);
  Result.SetTrimming(Trimming, Sign);
  if Access >= 0 then
  begin
    Range.startPosition := Access;
    Range.length := 1;
    Result.SetUnderline(True, Range);
  end;
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
  else if (V.Kind = vkSeparator) and V.Vertical then
    Result := UprightWidth(V.Divider)
  else if (V.Kind = vkSeparator) and (V.Divider <> nil) and (V.Divider.DividerText <> '') then
    Result := TextWidth(V.Divider.DividerText, DividerFormat(V.Divider)) + 48
  else if V.Kind = vkNote then
    Result := NoteWidth(V) + NoteLeft(V) - NotePad
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
  GroupPad = 6;    // a card holding cards with a frame (plan 11 3.4): what it holds and its title from its edges (DIP)
  ButtonGap = 2;   // at least between the cards inside a framed card, across and down

function LayLines(Level: TViewLevel; Left, Top, Width: Single; Collect: Boolean; var Boxes: TArray<TBox>;
  WrapWidth: Single; Framed: Boolean): Single; forward;
function CardMin(V: TViewCard): Single; forward;

// A card holding cards (plan 11 3.4): the room around what it holds, at its sides and at its top (its padding and its
// title, as a title or as a divider), none without a frame.
// A card holding cards whose border is dividers ("border": "divider"): no frame line and no padding; a divider at its
// top ("dividerTop", on unless false), its title as that divider's text, and one at its bottom ("dividerBottom": true).
// Its background and hover look stay.
function DividerBorder(V: TViewCard): Boolean;
begin
  Result := (V.Kind = vkGroup) and V.Framed and (V.Card <> nil) and (V.Card.Look <> nil) and
    (V.Card.Look.GetValue('border') is TJSONString) and (V.Card.Look.GetValue('border').Value = 'divider');
end;

function DividerTop(V: TViewCard): Boolean;
begin
  Result := DividerBorder(V) and not ((V.Card.Look.GetValue('dividerTop') is TJSONBool) and
    not TJSONBool(V.Card.Look.GetValue('dividerTop')).AsBoolean);
end;

// Its bottom divider as set, whether or not it is drawn.
function DividerBottomSet(V: TViewCard): Boolean;
begin
  Result := DividerBorder(V) and (V.Card.Look.GetValue('dividerBottom') is TJSONBool) and
    TJSONBool(V.Card.Look.GetValue('dividerBottom')).AsBoolean;
end;

// Its bottom divider drawn: set, and not left out (MarkBottoms).
function DividerBottom(V: TViewCard): Boolean;
begin
  Result := DividerBottomSet(V) and not V.NoBottomDivider;
end;

function InnerFramed(V: TViewCard): Boolean; forward;

// Whether a line starts with a border of its own: a divider, a framed card holding cards whose border is drawn (flat,
// 3D, or dividers with a top one), or a plain holder whose first line does.
function StartsBordered(Line: TViewLine): Boolean;
var
  C: TViewCard;
  Look: TJSONObject;
begin
  Result := False;
  if (Line = nil) or (Line.Cards.Count = 0) then
    Exit;
  C := Line.Cards[0];
  if C.Kind = vkSeparator then
    Exit(not C.Vertical and ((C.Divider = nil) or not C.Divider.DividerSpacer));   // a spacer is room, no border
  if C.Kind <> vkGroup then
    Exit;
  if DividerBorder(C) then
    Exit(DividerTop(C));
  if C.Framed then
  begin
    Look := nil;
    if C.Card <> nil then
      Look := C.Card.Look;
    // "border": "none" and no 3D border: no line
    Result := not ((Look <> nil) and (Look.GetValue('border') is TJSONString) and (Look.GetValue('border').Value = 'none')
      and not (Look.GetValue('border3d') is TJSONObject));
    Exit;
  end;
  Result := (C.Inner <> nil) and (C.Inner.Lines.Count > 0) and StartsBordered(C.Inner.Lines[0]);
end;

// Whether a line ends with a border of its own: its last card a framed card holding cards whose border is drawn (flat or
// 3D), one with dividers as its border and a bottom divider set, or a plain holder whose last line does.
function EndsBordered(Line: TViewLine): Boolean;
var
  C: TViewCard;
  Look: TJSONObject;
begin
  Result := False;
  if (Line = nil) or (Line.Cards.Count = 0) then
    Exit;
  C := Line.Cards[Line.Cards.Count - 1];
  if C.Kind <> vkGroup then
    Exit;
  if DividerBorder(C) then
    Exit(DividerBottomSet(C));
  if C.Framed then
  begin
    Look := nil;
    if C.Card <> nil then
      Look := C.Card.Look;
    Result := not ((Look <> nil) and (Look.GetValue('border') is TJSONString) and (Look.GetValue('border').Value = 'none')
      and not (Look.GetValue('border3d') is TJSONObject));
    Exit;
  end;
  Result := (C.Inner <> nil) and (C.Inner.Lines.Count > 0) and EndsBordered(C.Inner.Lines[C.Inner.Lines.Count - 1]);
end;

// A plain divider (no title; a layout's or Windows' separator) right after a line that ends with a border left out:
// the border already divides. Inside the cards holding cards too. Runs before MarkBottoms.
procedure DropDividers(Level: TViewLevel);
var
  I: Integer;
  C: TViewCard;
begin
  if Level = nil then
    Exit;
  for I := Level.Lines.Count - 1 downto 1 do
    if (Level.Lines[I].Cards.Count = 1) and (Level.Lines[I].Cards[0].Kind = vkSeparator) and
      ((Level.Lines[I].Cards[0].Divider = nil) or ((Level.Lines[I].Cards[0].Divider.DividerText = '') and
      not Level.Lines[I].Cards[0].Divider.DividerSpacer)) and
      EndsBordered(Level.Lines[I - 1]) then
      Level.Lines.Delete(I);
  for I := 0 to Level.Lines.Count - 1 do
    for C in Level.Lines[I].Cards do
      if C.Kind = vkGroup then
        DropDividers(C.Inner);
end;

// Each group's bottom divider left out where it would double a border or end the menu (NoBottomDivider): when nothing
// follows it or what follows starts with a border. EndBordered: what follows the end of this level counts so (the
// menu's end; a frame's bottom; a drawn bottom divider; else what follows the holder).
procedure MarkBottoms(Level: TViewLevel; EndBordered: Boolean);
var
  I: Integer;
  C: TViewCard;
  AfterIt, InnerEnd: Boolean;
begin
  if Level = nil then
    Exit;
  for I := 0 to Level.Lines.Count - 1 do
  begin
    if I = Level.Lines.Count - 1 then
      AfterIt := EndBordered
    else
      AfterIt := StartsBordered(Level.Lines[I + 1]);
    for C in Level.Lines[I].Cards do
    begin
      if C.Kind <> vkGroup then
        Continue;
      C.NoBottomDivider := DividerBottomSet(C) and AfterIt;
      if InnerFramed(C) or DividerBottom(C) then
        InnerEnd := True
      else
        InnerEnd := AfterIt;
      MarkBottoms(C.Inner, InnerEnd);
    end;
  end;
end;

// The gaps inside it are a frame's (at least ButtonGap) only with a frame line around them.
function InnerFramed(V: TViewCard): Boolean;
begin
  Result := V.Framed and not DividerBorder(V);
end;

function GroupSide(V: TViewCard): Single;
begin
  if InnerFramed(V) then
    Result := GroupPad
  else
    Result := 0;
end;

// Its room below what it holds: a frame's padding, or its bottom divider.
function GroupBottom(V: TViewCard): Single;
begin
  if DividerBottom(V) then
    Result := SeparatorHeight
  else
    Result := GroupSide(V);
end;

function GroupTop(V: TViewCard): Single;
begin
  if DividerBorder(V) then
  begin
    Result := 0;
    if DividerTop(V) then
      if V.BackTitle <> '' then
        Result := DividerTextHeight
      else
        Result := SeparatorHeight;
    Exit;
  end;
  if not V.Framed then
    Exit(0);
  Result := GroupPad;
  if V.BackTitle <> '' then
    if (V.Card <> nil) and V.Card.TitleAsDivider then
      Result := Result + DividerTextHeight
    else
      Result := Result + TitleHeight + ButtonGap;
end;

// The gaps between the cards on a line and between lines (plan 03 3.5): the theme's, none unless it gives them; inside
// a framed card at least ButtonGap.
procedure Gaps(Framed: Boolean; out CardGap, LineGap: Single);
var
  Theme: TTheme;
begin
  Theme := CurrentTheme(TLook.Current.Dark);
  CardGap := Max(0, Theme.Number('card', 'normal', 'gap', 0));
  LineGap := Max(0, Theme.Number('line', 'normal', 'gap', 0));
  if Framed then
  begin
    CardGap := Max(CardGap, ButtonGap);
    LineGap := Max(LineGap, ButtonGap);
  end;
end;

// What a card holding cards needs across: its title, and its widest line (a line that flows: its widest card).
function GroupNeed(V: TViewCard): Single;
var
  Line: TViewLine;
  C: TViewCard;
  Sum, CardGap, LineGap: Single;
begin
  Result := 0;
  if DividerTop(V) and (V.BackTitle <> '') then
    Result := TextWidth(V.BackTitle, NormalFormat) + 48   // as a divider with a label
  else if V.Framed and not DividerBorder(V) and (V.BackTitle <> '') then
    Result := TextWidth(V.BackTitle, BoldFormat) + 8;
  if V.Inner = nil then
    Exit(Result + 2 * GroupSide(V));
  Gaps(InnerFramed(V), CardGap, LineGap);
  for Line in V.Inner.Lines do
  begin
    Sum := 0;
    for C in Line.Cards do
      if Line.Flows then
        Sum := Max(Sum, Max(CardNeed(C), CardMin(C)))
      else
        Sum := Sum + Max(CardNeed(C), CardMin(C)) + CardGap;
    if not Line.Flows and (Line.Cards.Count > 0) then
      Sum := Sum - CardGap;
    Result := Max(Result, Sum);
  end;
  Result := Result + 2 * GroupSide(V);
end;

// The layout card's size settings (plan 03 3.5; an inner card's template's, plan 11); a view card without one
// (Windows' items in a submenu) has the defaults.
function CardMin(V: TViewCard): Single;
begin
  Result := 0;
  if V.SizeCard <> nil then
    Result := V.SizeCard.MinWidth;
end;

function CardWeight(V: TViewCard): Single;
begin
  Result := 1;
  if V.SizeCard <> nil then
    Result := V.SizeCard.Weight;
end;

// A card's own height at a width: a note's wrapped text, a card holding cards what it holds, a fixed height in lines,
// a square card its width, else one line.
function CardHeight(V: TViewCard; Width: Single): Single;
var
  Layout: IDWriteTextLayout;
  M: TDWriteTextMetrics;
  None: TArray<TBox>;
begin
  if (V.Kind = vkSeparator) and V.Vertical then
    Exit(0);   // upright: as high as the cards beside it
  Result := ItemHeight;
  if V.Kind = vkGroup then
  begin
    if V.Inner = nil then
      Exit(GroupTop(V) + GroupBottom(V));
    Exit(GroupTop(V) + LayLines(V.Inner, 0, 0, Max(1, Width - 2 * GroupSide(V)), False, None, -1, InnerFramed(V)) +
      GroupBottom(V));
  end
  else if V.Kind = vkNote then
    Result := NoteHeight(V, Width)
  else if (V.LookCard <> nil) and (V.LookCard.Extra <> '') then
    Result := ItemHeight + ExtraHeight;   // the title and its extra text
  if Wraps(V) and (V.SizeCard.Height <= 0) then
  begin
    // as high as its wrapped title's lines, with a single line's room around them
    Layout := WrappedTitle(V.Title, TitleFormat(V), Width - TextLeft - MarkSpace(V), 0);
    if (Layout <> nil) and Succeeded(Layout.GetMetrics(M)) then
      Result := Result + Max(0, M.height - LineHeight);
  end;
  if (V.SizeCard <> nil) and (V.SizeCard.Height > 0) then
    Result := V.SizeCard.Height * ItemHeight;
  if (V.SizeCard <> nil) and V.SizeCard.Square then
    Result := Width;
end;

function CardFitOf(V: TViewCard; Line: TViewLine): TCardFit;
begin
  Result := cfDefault;
  if V.SizeCard <> nil then
    Result := V.SizeCard.CardFit;
  if Result = cfDefault then
    Result := Line.CardFit;
  if Result = cfDefault then
    Result := cfStretch;
end;

// A level's lines split into rows: a line whose cards do not fit side by side within WrapWidth wraps its last cards
// onto a row of their own below it, in their order. At the menu's top a card counts its minimum width; inside a card
// (an inner line) its content.
// A row that flows (found items without a set number per row, plan 11 3.4): as many per row as its widest card lets
// fit, so its rows are a grid of equal columns.
function FlowPer(Line: TViewLine; Width, CardGap: Single): Integer;
var
  V: TViewCard;
  Widest: Single;
begin
  Widest := 1;
  for V in Line.Cards do
    Widest := Max(Widest, Max(CardNeed(V), CardMin(V)));
  Result := Max(1, Min(Line.Cards.Count, Trunc((Width + CardGap) / (Widest + CardGap))));
end;

procedure SplitRows(Level: TViewLevel; WrapWidth, CardGap: Single; Rows: TList<TArray<TViewCard>>;
  RowLines: TList<TViewLine>);
var
  Line: TViewLine;
  Row: TArray<TViewCard>;
  V: TViewCard;
  SumMin, Size: Single;
  Per: Integer;
begin
  for Line in Level.Lines do
  begin
    Row := nil;
    SumMin := 0;
    if Line.Flows then
    begin
      // a grid: the same number on every row
      Per := FlowPer(Line, WrapWidth, CardGap);
      for V in Line.Cards do
      begin
        Row := Row + [V];
        if Length(Row) = Per then
        begin
          Rows.Add(Row);
          RowLines.Add(Line);
          Row := nil;
        end;
      end;
      if Length(Row) > 0 then
      begin
        Rows.Add(Row);
        RowLines.Add(Line);
      end;
      Continue;
    end;
    for V in Line.Cards do
    begin
      if Line.Inner or ((V.Kind = vkSeparator) and V.Vertical) then
        Size := Max(CardNeed(V), CardMin(V))
      else
        Size := CardMin(V);
      if (Length(Row) > 0) and (SumMin + CardGap + Size > WrapWidth) then
      begin
        Rows.Add(Row);
        RowLines.Add(Line);
        Row := nil;
        SumMin := 0;
      end;
      if Length(Row) > 0 then
        SumMin := SumMin + CardGap;
      SumMin := SumMin + Size;
      Row := Row + [V];
    end;
    if Length(Row) > 0 then
    begin
      Rows.Add(Row);
      RowLines.Add(Line);
    end;
  end;
end;

// A level's lines laid out from Left, Top at a width (DIP): each row's cards side by side sharing the width by their
// weights (a card below its minimum gets it); a row that flows (a row without a set number per row) a grid of equal
// columns over the whole width, as many as its widest card lets fit. Collect: the boxes appended to Boxes, a card holding cards its own box then the
// boxes inside it, recursively. The height used. WrapWidth: where a line wraps (-1: Width).
function LayLines(Level: TViewLevel; Left, Top, Width: Single; Collect: Boolean; var Boxes: TArray<TBox>;
  WrapWidth: Single; Framed: Boolean): Single;
var
  CardGap, LineGap: Single;
  Line: TViewLine;
  Rows: TList<TArray<TViewCard>>;
  Row: TArray<TViewCard>;
  Widths, Floors: TArray<Single>;
  Fixed: TArray<Boolean>;
  V: TViewCard;
  Y, H, X, Avail, FreeWeight, OwnH, CardTop, Sum: Single;
  N, I, J, Per: Integer;
  Changed, First: Boolean;
  Box: TBox;
  Fit: TCardFit;
  RowLines: TList<TViewLine>;
begin
  Gaps(Framed, CardGap, LineGap);
  if WrapWidth < 0 then
    WrapWidth := Width;
  Rows := TList<TArray<TViewCard>>.Create;
  RowLines := TList<TViewLine>.Create;
  try
    SplitRows(Level, WrapWidth, CardGap, Rows, RowLines);
    Y := Top;
    First := True;
    for I := 0 to Rows.Count - 1 do
    begin
      Row := Rows[I];
      Line := RowLines[I];
      N := Length(Row);
      if not First then
        Y := Y + LineGap;
      First := False;
      SetLength(Widths, N);
      SetLength(Fixed, N);
      if Line.Flows then
      begin
        // a row that flows: a grid of equal columns over the whole width, as many as its widest card lets fit; a
        // last row with fewer cards keeps the columns
        Per := FlowPer(Line, WrapWidth, CardGap);
        for J := 0 to N - 1 do
          Widths[J] := Max(0, (Width - CardGap * (Per - 1)) / Per);
      end
      else
      begin
        // the cards share the width by their weights; one whose share is below its minimum gets its minimum, and the
        // others share the rest. A card whose title wraps has its longest word as its minimum too, when the row has
        // room for all of them: else its word would be broken while another card has room to spare.
        SetLength(Floors, N);
        Sum := CardGap * (N - 1);
        for J := 0 to N - 1 do
        begin
          Floors[J] := CardMin(Row[J]);
          if Wraps(Row[J]) or ((Row[J].Kind = vkSeparator) and Row[J].Vertical) then
            Floors[J] := Max(Floors[J], CardNeed(Row[J]));
          Sum := Sum + Floors[J];
        end;
        if Sum > Width then
          for J := 0 to N - 1 do
            Floors[J] := CardMin(Row[J]);
        for J := 0 to N - 1 do
        begin
          // an upright divider takes its own width; the cards share the rest
          Fixed[J] := (Row[J].Kind = vkSeparator) and Row[J].Vertical;
          if Fixed[J] then
            Widths[J] := UprightWidth(Row[J].Divider);
        end;
        repeat
          Changed := False;
          Avail := Width - CardGap * (N - 1);
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
              if Widths[J] < Floors[J] then
              begin
                Widths[J] := Floors[J];
                Fixed[J] := True;
                Changed := True;
              end;
            end;
        until not Changed;
      end;
      // the line as high as its highest card
      if (N = 1) and (Row[0].Kind = vkSeparator) then
      begin
        H := DividerHeightOf(Row[0].Divider);
      end
      else
      begin
        H := 0;
        for J := 0 to N - 1 do
          H := Max(H, CardHeight(Row[J], Widths[J]));
      end;
      X := Left;
      for J := 0 to N - 1 do
      begin
        V := Row[J];
        OwnH := H;
        CardTop := Y;
        if V.Kind <> vkSeparator then
        begin
          // a lower card: stretched to the line, or at its own height at the line's top, centre or bottom
          Fit := CardFitOf(V, Line);
          if Fit <> cfStretch then
          begin
            OwnH := Min(H, CardHeight(V, Widths[J]));
            case Fit of
              cfCenter: CardTop := Y + (H - OwnH) / 2;
              cfBottom: CardTop := Y + H - OwnH;
            end;
          end;
        end;
        if Collect then
        begin
          Box.Card := V;
          Box.Rect := D2D1RectF(X, CardTop, X + Widths[J], CardTop + OwnH);
          // an upright divider reaches over the gaps to the rows above and below, so a grid's read as one line
          if (V.Kind = vkSeparator) and V.Vertical then
          begin
            if I > 0 then
              Box.Rect.top := Box.Rect.top - LineGap / 2;
            if I < Rows.Count - 1 then
              Box.Rect.bottom := Box.Rect.bottom + LineGap / 2;
          end;
          Box.Alone := N = 1;
          Boxes := Boxes + [Box];
          // a card holding cards: the boxes inside it follow its own
          if (V.Kind = vkGroup) and (V.Inner <> nil) then
            LayLines(V.Inner, X + GroupSide(V), CardTop + GroupTop(V), Max(1, Widths[J] - 2 * GroupSide(V)), True, Boxes,
              -1, InnerFramed(V));
        end;
        X := X + Widths[J] + CardGap;
      end;
      Y := Y + H;
    end;
  finally
    RowLines.Free;
    Rows.Free;
  end;
  Result := Y - Top;
end;

function Measure(Level: TViewLevel; Depth: Integer): TGeometry;
var
  LevelMin, LevelMax, CardGap, LineGap, W, Need: Single;
  Rows: TList<TArray<TViewCard>>;
  RowLines: TList<TViewLine>;
  Row: TArray<TViewCard>;
  V: TViewCard;
begin
  EnsureFactories;
  DropDividers(Level);
  MarkBottoms(Level, True);   // nothing follows the level's end
  LevelMin := MinWidth;
  LevelMax := MaxWidth;
  if Length(LevelWidths) > 0 then
  begin
    LevelMin := LevelWidths[Min(Depth, High(LevelWidths))].MinW;
    LevelMax := LevelWidths[Min(Depth, High(LevelWidths))].MaxW;
  end;
  Gaps(False, CardGap, LineGap);
  // the width: the widest row's need (each card at least its minimum width), between the level's minimum and maximum
  Rows := TList<TArray<TViewCard>>.Create;
  RowLines := TList<TViewLine>.Create;
  try
    SplitRows(Level, LevelMax - 2 * OuterPad, CardGap, Rows, RowLines);
    W := LevelMin;
    for Row in Rows do
    begin
      Need := CardGap * (Length(Row) - 1);
      for V in Row do
        Need := Need + Max(CardNeed(V), CardMin(V));
      W := Max(W, Need + 2 * OuterPad);
    end;
    W := Min(W, LevelMax);
  finally
    RowLines.Free;
    Rows.Free;
  end;
  Result.Boxes := nil;
  Result.Width := W;
  Result.Height := OuterPad + LayLines(Level, OuterPad, OuterPad, W - 2 * OuterPad, True, Result.Boxes,
    LevelMax - 2 * OuterPad, False) + OuterPad;
  Result.Pressed := -1;
  Result.KeyFocus := False;
  Result.MenuCard := Level.MenuCard;
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

// The direction the light comes from (plan 03 3.6), as a vector on screen (y down): angle in degrees, 0 from the
// right, 90 from the top, 135 from the top left (the default), 180 from the left.
procedure LightFrom(Angle: Single; out LX, LY: Single);
begin
  LX := Cos(DegToRad(Angle));
  LY := -Sin(DegToRad(Angle));
end;

// A card's shadow (plan 03 3.6; "shadow": { color, distance, angle, blur }): its shape in the colour, moved the distance
// away from the light, under the card; a blur softens its edge over that many DIP (rings of growing size, each adding
// a little of the colour). Drawn inside the menu's clip only: never outside the menu window's background.
const
  MarkGap = 5;    // the editor's selected card outlined this far outside it in the preview (DIP)
  MaxBlur = 16;   // a shadow's blur at most (DIP): one ring per DIP

procedure DrawShadow(T: ID2D1RenderTarget; Theme: TTheme; Own: TJSONObject; const R: TD2D1RectF; Radius: Single);
const
  MaxRings = MaxBlur;
var
  S: TJSONObject;
  C: TRGBA;
  Distance, Blur, LX, LY, DX, DY, E, Alpha: Single;
  Rings, K: Integer;
  Brush: ID2D1SolidColorBrush;
  Box: TD2D1RectF;
begin
  if (Own = nil) or not (Own.GetValue('shadow') is TJSONObject) then
    Exit;
  S := TJSONObject(Own.GetValue('shadow'));
  C := Theme.Color('card', 'normal', 'color', RGBA(0, 0, 0, 0.25), S);
  if C.A <= 0 then
    Exit;
  Distance := Max(0, Theme.Number('card', 'normal', 'distance', 3, S));
  Blur := EnsureRange(Theme.Number('card', 'normal', 'blur', 0, S), 0, MaxBlur);   // at most 16 rings, one DIP apart
  LightFrom(Theme.Number('card', 'normal', 'angle', 135, S), LX, LY);
  DX := -LX * Distance;
  DY := -LY * Distance;
  Rings := Max(1, Min(MaxRings, Ceil(Blur)));
  Alpha := C.A;
  C.A := 1;
  T.CreateSolidColorBrush(ToD2D(C), nil, Brush);
  for K := 0 to Rings - 1 do
  begin
    // the rings drawn from the largest in: after K + 1 of them the colour is (K + 1) / Rings of its own alpha, an
    // even ramp from the outer edge to the shape (each ring the part still missing)
    Brush.SetOpacity(1 - (1 - Alpha * (K + 1) / Rings) / (1 - Alpha * K / Rings));
    // from Blur/2 outside the shape to Blur/2 inside it
    if Rings = 1 then
      E := 0
    else
      E := Blur / 2 - Blur * K / (Rings - 1);
    Box := D2D1RectF(R.left + DX - E, R.top + DY - E, R.right + DX + E, R.bottom + DY + E);
    if (Box.right > Box.left) and (Box.bottom > Box.top) then
      T.FillRoundedRectangle(D2D1RoundedRect(Box, Max(0, Radius + E), Max(0, Radius + E)), Brush);
  end;
end;

// A band inside a rounded box (an inner shadow): the box less the box moved by (OX, OY), its inner edge blurred over
// Blur DIP (rings, each adding what is still missing, as DrawShadow), in the colour C.
procedure InnerBand(T: ID2D1RenderTarget; const R: TD2D1RectF; Radius, OX, OY, Blur: Single; const C: TRGBA);
const
  MaxRings = 16;
var
  Shape, Hole: ID2D1RoundedRectangleGeometry;
  Band: ID2D1PathGeometry;
  Sink: ID2D1GeometrySink;
  Brush: ID2D1SolidColorBrush;
  Identity: TD2DMatrix3x2F;
  Solid: TRGBA;
  Rings, K: Integer;
  E: Single;
begin
  if (C.A <= 0) or Failed(D2D.CreateRoundedRectangleGeometry(D2D1RoundedRect(R, Radius, Radius), Shape)) then
    Exit;
  FillChar(Identity, SizeOf(Identity), 0);
  Identity._11 := 1;
  Identity._22 := 1;
  Solid := C;
  Solid.A := 1;
  T.CreateSolidColorBrush(ToD2D(Solid), nil, Brush);
  Rings := Max(1, Min(MaxRings, Ceil(Blur)));
  for K := 0 to Rings - 1 do
  begin
    // from the widest band (the hole shrunk by Blur/2) to the narrowest (grown by Blur/2): where they all lie, the
    // colour as given; towards the face less and less
    if Rings = 1 then
      E := 0
    else
      E := -Blur / 2 + Blur * K / (Rings - 1);
    if Failed(D2D.CreateRoundedRectangleGeometry(D2D1RoundedRect(D2D1RectF(R.left + OX - E, R.top + OY - E,
      R.right + OX + E, R.bottom + OY + E), Max(0, Radius + E), Max(0, Radius + E)), Hole)) or
      Failed(D2D.CreatePathGeometry(Band)) or Failed(Band.Open(Sink)) then
      Exit;
    Shape.CombineWithGeometry(Hole, D2D1_COMBINE_MODE_EXCLUDE, Identity, 0.25, Sink);
    Sink.Close;
    Brush.SetOpacity(1 - (1 - C.A * (K + 1) / Rings) / (1 - C.A * K / Rings));
    T.FillGeometry(Band, Brush, nil);
  end;
end;

// A card's border (plan 03 3.6): a 3D border ("border3d": { style "outset" | "inset", angle, width, light, shadow })
// as a lit panel, raised or sunk (InnerBand: soft light inside the edges facing the light, soft shadow inside the
// others); else a flat border in its colour ("border"); not set: Fallback (nil: none); "none": none.
procedure DrawBorder(T: ID2D1RenderTarget; Theme: TTheme; const Element, State: string; Own: TJSONObject;
  const R: TD2D1RectF; Radius: Single; Fallback: ID2D1Brush);
var
  B: TJSONObject;
  Style: string;
  W, LX, LY: Single;
  Light, Shade, C: TRGBA;
  Brush: ID2D1SolidColorBrush;
begin
  B := nil;
  if (Own <> nil) and (Own.GetValue('border3d') is TJSONObject) then
    B := TJSONObject(Own.GetValue('border3d'));
  Style := '';
  if (B <> nil) and (B.GetValue('style') is TJSONString) then
    Style := B.GetValue('style').Value;
  if (Style = 'outset') or (Style = 'inset') then
  begin
    // as a lit panel: inside its edges a soft band of light on the side facing the light and a soft band of shadow
    // on the other (sunk: the other way round); each band the shape less itself moved the width away, its inner edge
    // blurred over the width, so it fades into the face and runs round the corners
    W := Max(0.5, Min(Theme.Number('card', 'normal', 'width', 2, B), Min(R.right - R.left, R.bottom - R.top) / 2));
    LightFrom(Theme.Number('card', 'normal', 'angle', 135, B), LX, LY);
    Light := Theme.Color('card', 'normal', 'light', RGBA(255, 255, 255, 0.75), B);
    Shade := Theme.Color('card', 'normal', 'shadow', RGBA(0, 0, 0, 0.5), B);
    if Style = 'inset' then
    begin
      C := Light;
      Light := Shade;
      Shade := C;
    end;
    // the light band on the lit side: the shape less itself moved away from the light; the dark band the reverse
    InnerBand(T, R, Radius, -LX * W, -LY * W, W, Light);
    InnerBand(T, R, Radius, LX * W, LY * W, W, Shade);
    Exit;
  end;
  C := Theme.Color(Element, State, 'border', RGBA(0, 0, 0, -1), Own);
  if C.A > 0 then
  begin
    T.CreateSolidColorBrush(ToD2D(C), nil, Brush);
    T.DrawRoundedRectangle(D2D1RoundedRect(R, Radius, Radius), Brush, Theme.Number(Element, State, 'borderWidth', 1, Own));
  end
  else if (C.A < 0) and (Fallback <> nil) then
    T.DrawRoundedRectangle(D2D1RoundedRect(R, Radius, Radius), Fallback, Theme.Number(Element, State, 'borderWidth', 1, Own));
end;

var
  Images: TDictionary<string, TIconPixels>;   // background images read, by path, time written and size (plan 03 3.4)

const
  MaxImageSide = 2048;   // a background image's longer side at most (pixels); a larger one is scaled down once

// A background image's pixels, read once per version of the file (its path, time written and size); False when it is
// not there or cannot be read.
function ImageOf(const Path: string; out Pixels: TIconPixels): Boolean;
var
  Data: TWin32FileAttributeData;
  Key: string;
begin
  Pixels := Default(TIconPixels);
  if not GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Data) then
    Exit(False);
  Key := Format('%s|%d|%d|%d', [LowerCase(Path), Data.ftLastWriteTime.dwHighDateTime, Data.ftLastWriteTime.dwLowDateTime,
    Data.nFileSizeLow]);
  FactoryLock.Enter;
  try
    if Images = nil then
      Images := TDictionary<string, TIconPixels>.Create;
    if not Images.TryGetValue(Key, Pixels) then
    begin
      if not ImagePixels(Path, MaxImageSide, Pixels) then
        Pixels := Default(TIconPixels);   // kept as not readable: not tried again until the file changes
      Images.AddOrSetValue(Key, Pixels);
    end;
  finally
    FactoryLock.Leave;
  end;
  Result := Pixels.Width > 0;
end;

// A background image (plan 03 3.4): { "image": <file>, "fit", "opacity", "tint", "color" } over a rounded box: its
// "color" under it, the image as "fit" says (stretch: to the whole box, the default; fit: whole inside, its
// proportions kept; center: its own size in the middle; repeatX, repeatY, repeat: tiled from the top left at its own
// size), its "opacity" (0 - 100), its "tint" colour over it. The file: environment variables expanded, a relative
// path from Dexmenu's data folder. A file that cannot be read: only the colour and the tint.
function FillImage(T: ID2D1RenderTarget; Theme: TTheme; Spec: TJSONObject; const R: TD2D1RectF; Radius: Single): Boolean;
var
  Path, Fit: string;
  Expanded: array[0..MAX_PATH] of Char;
  Pixels: TIconPixels;
  Bitmap: ID2D1Bitmap;
  Props: TD2D1BitmapProperties;
  BrushProps: TD2D1BitmapBrushProperties;
  Brush: ID2D1BitmapBrush;
  Solid: ID2D1SolidColorBrush;
  Shape: ID2D1RoundedRectangleGeometry;
  Part: ID2D1RectangleGeometry;
  Region: ID2D1PathGeometry;
  Sink: ID2D1GeometrySink;
  M, Identity: TD2DMatrix3x2F;
  C: TRGBA;
  W, H, IW, IH, SX, SY, OX, OY: Single;
  Area: TD2D1RectF;
  Clip: Boolean;
begin
  Result := True;
  if Spec.GetValue('color') <> nil then
  begin
    C := Theme.Color('card', 'normal', 'color', RGBA(0, 0, 0, 0), Spec);
    if C.A > 0 then
    begin
      T.CreateSolidColorBrush(ToD2D(C), nil, Solid);
      T.FillRoundedRectangle(D2D1RoundedRect(R, Radius, Radius), Solid);
    end;
  end;
  Path := '';
  if Spec.GetValue('image') is TJSONString then
    Path := Trim(Spec.GetValue('image').Value);
  if Path <> '' then
  begin
    if ExpandEnvironmentStrings(PChar(Path), Expanded, Length(Expanded)) > 0 then
      Path := Expanded;
    if ExtractFileDrive(Path) = '' then
      Path := IncludeTrailingPathDelimiter(DataFolder) + Path;
  end;
  if (Path <> '') and ImageOf(Path, Pixels) then
  begin
    Props.pixelFormat := D2D1PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED);
    Props.dpiX := 96;   // a pixel of the image a DIP of the menu
    Props.dpiY := 96;
    W := R.right - R.left;
    H := R.bottom - R.top;
    IW := Pixels.Width;
    IH := Pixels.Height;
    Fit := 'stretch';
    if Spec.GetValue('fit') is TJSONString then
      Fit := Spec.GetValue('fit').Value;
    BrushProps.extendModeX := D2D1_EXTEND_MODE_CLAMP;
    BrushProps.extendModeY := D2D1_EXTEND_MODE_CLAMP;
    BrushProps.interpolationMode := D2D1_BITMAP_INTERPOLATION_MODE_LINEAR;
    SX := 1;
    SY := 1;
    OX := R.left;
    OY := R.top;
    Clip := True;   // only where the image lies (else clamping smears its edge pixels)
    if Fit = 'fit' then
    begin
      SX := Min(W / IW, H / IH);
      SY := SX;
      OX := R.left + (W - IW * SX) / 2;
      OY := R.top + (H - IH * SY) / 2;
    end
    else if Fit = 'center' then
    begin
      OX := R.left + (W - IW) / 2;
      OY := R.top + (H - IH) / 2;
    end
    else if Fit = 'repeatX' then
      BrushProps.extendModeX := D2D1_EXTEND_MODE_WRAP
    else if Fit = 'repeatY' then
      BrushProps.extendModeY := D2D1_EXTEND_MODE_WRAP
    else if Fit = 'repeat' then
    begin
      BrushProps.extendModeX := D2D1_EXTEND_MODE_WRAP;
      BrushProps.extendModeY := D2D1_EXTEND_MODE_WRAP;
      Clip := False;
    end
    else
    begin
      SX := W / IW;   // stretch
      SY := H / IH;
      Clip := False;
    end;
    if Succeeded(T.CreateBitmap(D2D1SizeU(Pixels.Width, Pixels.Height), @Pixels.Bits[0], Pixels.Width * 4, Props, Bitmap)) and
      Succeeded(T.CreateBitmapBrush(Bitmap, @BrushProps, nil, Brush)) and
      Succeeded(D2D.CreateRoundedRectangleGeometry(D2D1RoundedRect(R, Radius, Radius), Shape)) then
    begin
      FillChar(M, SizeOf(M), 0);
      M._11 := SX;
      M._22 := SY;
      M._31 := OX;
      M._32 := OY;
      Brush.SetTransform(M);
      if Spec.GetValue('opacity') is TJSONNumber then
        Brush.SetOpacity(EnsureRange(TJSONNumber(Spec.GetValue('opacity')).AsDouble, 0, 100) / 100);
      if not Clip then
        T.FillGeometry(Shape, Brush, nil)
      else
      begin
        // the box where the image lies: all of it across for repeatX, down for repeatY
        Area := D2D1RectF(OX, OY, OX + IW * SX, OY + IH * SY);
        if BrushProps.extendModeX = D2D1_EXTEND_MODE_WRAP then
        begin
          Area.left := R.left;
          Area.right := R.right;
        end;
        if BrushProps.extendModeY = D2D1_EXTEND_MODE_WRAP then
        begin
          Area.top := R.top;
          Area.bottom := R.bottom;
        end;
        FillChar(Identity, SizeOf(Identity), 0);
        Identity._11 := 1;
        Identity._22 := 1;
        if Succeeded(D2D.CreateRectangleGeometry(Area, Part)) and Succeeded(D2D.CreatePathGeometry(Region)) and
          Succeeded(Region.Open(Sink)) then
        begin
          Shape.CombineWithGeometry(Part, D2D1_COMBINE_MODE_INTERSECT, Identity, 0.25, Sink);
          Sink.Close;
          T.FillGeometry(Region, Brush, nil);
        end;
      end;
    end;
  end;
  if Spec.GetValue('tint') <> nil then
  begin
    C := Theme.Color('card', 'normal', 'tint', RGBA(0, 0, 0, 0), Spec);
    if C.A > 0 then
    begin
      T.CreateSolidColorBrush(ToD2D(C), nil, Solid);
      T.FillRoundedRectangle(D2D1RoundedRect(R, Radius, Radius), Solid);
    end;
  end;
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
  V: TJSONValue;
begin
  // the layout's own background an image (plan 03 3.4): drawn as one
  V := nil;
  if Own <> nil then
    if State = 'normal' then
      V := Own.GetValue('background')
    else if Own.GetValue(State) is TJSONObject then
      V := TJSONObject(Own.GetValue(State)).GetValue('background');
  if (V is TJSONObject) and (TJSONObject(V).GetValue('image') <> nil) then
    Exit(FillImage(T, Theme, TJSONObject(V), R, Radius));
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
procedure DrawDividerText(T: ID2D1RenderTarget; D: TLine; const R: TD2D1RectF; Y: Single; Line, Text: ID2D1SolidColorBrush;
  Fmt: IDWriteTextFormat = nil);
const
  Pad = 8;
  Gap = 6;
var
  W, X: Single;
  Label_: string;
begin
  Label_ := D.DividerText;
  if Fmt = nil then
    Fmt := NormalFormat;
  W := Min(TextWidth(Label_, Fmt), R.right - R.left - 4 * Pad);
  case D.DividerAlign of
    daCenter: X := (R.left + R.right - W) / 2;
    daRight: X := R.right - Pad - W;
  else
    X := R.left + Pad;
  end;
  if (Line <> nil) and (X - Gap > R.left + Pad) then
    T.DrawLine(D2D1PointF(R.left + Pad, Y), D2D1PointF(X - Gap, Y), Line, LineThickness(D));
  if (Line <> nil) and (X + W + Gap < R.right - Pad) then
    T.DrawLine(D2D1PointF(X + W + Gap, Y), D2D1PointF(R.right - Pad, Y), Line, LineThickness(D));
  T.DrawText(PWideChar(Label_), Length(Label_), Fmt, D2D1RectF(X, R.top, X + W + 1, R.bottom), Text,
    D2D1_DRAW_TEXT_OPTIONS_CLIP);
end;

// Whether the menu has no background of its own (plan 03 3.4: see-through; only its cards drawn).
function SeeThrough(Theme: TTheme; MenuOwn: TJSONObject): Boolean;
var
  Stops: TArray<TRGBA>;
  Angle: Single;
begin
  Result := not Theme.Background('menu', 'normal', Stops, Angle, MenuOwn) and
    (Theme.Color('menu', 'normal', 'background', RGBA(0, 0, 0, -1), MenuOwn).A = 0);
end;

procedure DrawLevel(T: ID2D1RenderTarget; const G: TGeometry; Selected: Integer; ScrollY, VisibleHeight: Single;
  const Look: TLook; const Marked: string; Editing: Boolean);
var
  Bg, Border, Text, Dim, Extra, Hover, Sep, LabelBrush, Accent, Stripe: ID2D1SolidColorBrush;
  DivLine, DivText: ID2D1SolidColorBrush;   // a divider's line and label, its own or the theme's
  Outline: ID2D1SolidColorBrush;            // the editor's selected card's outline (the preview)
  MarkId: string;                           // its card's id
  MarkTemplate: Integer;                    // the template selected (its index), or -1: the card itself
  Track, Thumb: Single;                     // the scrollbar of a level taller than shown
  Clear_: Boolean;                 // a see-through menu (no background): each card on an opaque base of its own
  Base: ID2D1SolidColorBrush;      // that base: the theme's card background, opaque
  BaseColor: TRGBA;
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
  GroupState: string;
  TitleLine: TLine;
  MenuOwn: TJSONObject;
begin
  // every colour and radius from the theme for light or dark (plan 03 3.2; Dexmenu.Theme)
  Theme := CurrentTheme(Look.Dark);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('menu', 'normal', 'background', RGBA($F9, $F9, $F9))), nil, Bg);
  // the menu window in the theme's menu look, the layout's menu card's own style over it (plan 11 3.9)
  MenuOwn := nil;
  if G.MenuCard <> nil then
    MenuOwn := G.MenuCard.Look;
  T.CreateSolidColorBrush(ToD2D(Theme.Color('menu', 'normal', 'border', RGBA($D0, $D0, $D0), MenuOwn)), nil, Border);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'normal', 'foreground', RGBA($1B, $1B, $1B))), nil, Text);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'disabled', 'foreground', RGBA($A0, $A0, $A0))), nil, Dim);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'normal', 'extra', RGBA($A0, $A0, $A0))), nil, Extra);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'hover', 'background', RGBA(0, 0, 0, 0.06))), nil, Hover);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('divider', 'normal', 'border', RGBA($E0, $E0, $E0))), nil, Sep);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('divider', 'normal', 'foreground', RGBA($A0, $A0, $A0))), nil, LabelBrush);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'focused', 'border', RGBA($2F, $6F, $D6))), nil, Accent);
  T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'unavailable', 'background', RGBA(0, 0, 0, 0.09))), nil, Stripe);
  MenuRadius := Theme.Number('menu', 'normal', 'radius', WindowRadius, MenuOwn);
  T.Clear(D2D1ColorF(0, 0, 0, 0));
  R := D2D1RectF(0.5, 0.5, G.Width - 0.5, VisibleHeight - 0.5);
  // a see-through menu (plan 03 3.4): no background and no border of its own, only its cards, each made opaque
  Clear_ := SeeThrough(Theme, MenuOwn);
  if Clear_ then
  begin
    BaseColor := Theme.Color('card', 'normal', 'background', Theme.Color('menu', 'normal', 'background', RGBA($F9, $F9, $F9)));
    if BaseColor.A <= 0 then
      BaseColor := RGBA($F9, $F9, $F9);
    BaseColor.A := 1;
    T.CreateSolidColorBrush(ToD2D(BaseColor), nil, Base);
  end
  else
  begin
    if not FillBackground(T, Theme, 'menu', 'normal', R, MenuRadius, MenuOwn) then
      T.FillRoundedRectangle(D2D1RoundedRect(R, MenuRadius, MenuRadius), Bg);
    T.DrawRoundedRectangle(D2D1RoundedRect(R, MenuRadius, MenuRadius), Border, 1);
  end;
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
      // a note: no button (no hover, no mark); its own style (plan 03 3.6): its background, border, shadow and 3D
      // border where it has them; its text in its own colour, else the dim colour, aligned as the layout says
      Own := nil;
      if V.Card <> nil then
        Own := V.Card.Look;
      if (Own <> nil) or Clear_ then
      begin
        CardRadius := Theme.Number('card', 'normal', 'radius', ItemRadius, Own);
        Inner := D2D1RectF(R.left + 2, R.top + 1, R.right - 2, R.bottom - 1);
        DrawShadow(T, Theme, Own, Inner, CardRadius);
        if Clear_ then
          T.FillRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), Base);
        if (Own <> nil) and (Own.GetValue('background') <> nil) then
          FillBackground(T, Theme, 'card', 'normal', Inner, CardRadius, Own, True);
        DrawBorder(T, Theme, 'card', 'normal', Own, Inner, CardRadius, nil);
      end;
      NoteText := NoteLayout(V, R.right - R.left);
      if NoteText <> nil then
      begin
        if (Own <> nil) and (Own.GetValue('foreground') <> nil) then
          T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'normal', 'foreground', RGBA($A0, $A0, $A0), Own)), nil, Brush)
        else
          Brush := Extra;
        T.DrawTextLayout(D2D1PointF(R.left + NoteLeft(V), R.top + NotePad), NoteText, Brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
      end;
      Continue;
    end;
    if V.Kind = vkSeparator then
    begin
      // a divider: its own look over the theme's "divider" (plan 03 3.8): its background, its line's colour ("none":
      // no line), its label's colour and font
      Y := Round((R.top + R.bottom) / 2) + 0.5;
      DivLine := Sep;
      DivText := LabelBrush;
      if (V.Divider <> nil) and (V.Divider.DividerLook <> nil) then
      begin
        Own := V.Divider.DividerLook;
        FillBackground(T, Theme, 'divider', 'normal', D2D1RectF(R.left + 2, R.top, R.right - 2, R.bottom),
          Theme.Number('divider', 'normal', 'radius', 0, Own), Own, True);
        if Own.GetValue('border') <> nil then
        begin
          BorderColor := Theme.Color('divider', 'normal', 'border', RGBA(0, 0, 0, 0), Own);
          if BorderColor.A > 0 then
            T.CreateSolidColorBrush(ToD2D(BorderColor), nil, DivLine)
          else
            DivLine := nil;
        end;
        if Own.GetValue('foreground') <> nil then
          T.CreateSolidColorBrush(ToD2D(Theme.Color('divider', 'normal', 'foreground', RGBA($A0, $A0, $A0), Own)), nil, DivText);
      end;
      if (V.Divider <> nil) and V.Divider.DividerSpacer then
        DivLine := nil;   // a spacer: room (and its text), no line
      if V.Vertical then
      begin
        // upright (plan 18 3.2): a line from its top to its bottom in the middle of its width, no text
        if DivLine <> nil then
          T.DrawLine(D2D1PointF(Round((R.left + R.right) / 2) + 0.5, R.top),
            D2D1PointF(Round((R.left + R.right) / 2) + 0.5, R.bottom), DivLine, LineThickness(V.Divider));
      end
      else if (V.Divider = nil) or (V.Divider.DividerText = '') then
      begin
        if DivLine <> nil then
          T.DrawLine(D2D1PointF(R.left + 8, Y), D2D1PointF(R.right - 8, Y), DivLine, LineThickness(V.Divider));
      end
      else
        DrawDividerText(T, V.Divider, R, Y, DivLine, DivText, DividerFormat(V.Divider));
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
      // a card holding cards (plan 11 3.4): without a frame nothing of its own (what a line or a group was); with
      // one its background and its frame (its border, else the dividers' colour), its own hover look while the mouse
      // is over anything inside it, its title at the top as a title or as a divider; the cards inside it are boxes of
      // their own, drawn after it
      CardRadius := Theme.Number(Element, 'normal', 'radius', ItemRadius, Own);
      Inner := D2D1RectF(R.left + 2, R.top + 1, R.right - 2, R.bottom - 1);
      if Editing and V.Sometimes then
        DrawStripes(T, Inner, Stripe);   // not shown at a right-click (shownWhen)
      if not V.Framed then
        Continue;
      DrawShadow(T, Theme, Own, Inner, CardRadius);
      if Clear_ then
        T.FillRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), Base);
      FillBackground(T, Theme, Element, 'normal', Inner, CardRadius, Own);
      GroupState := 'normal';
      if (Own <> nil) and (Own.GetValue('hover') <> nil) and (Selected >= 0) and (Selected <= High(G.Boxes)) and
        (Selected <> I) and (G.Boxes[Selected].Rect.left >= G.Boxes[I].Rect.left) and
        (G.Boxes[Selected].Rect.right <= G.Boxes[I].Rect.right) and (G.Boxes[Selected].Rect.top >= G.Boxes[I].Rect.top) and
        (G.Boxes[Selected].Rect.bottom <= G.Boxes[I].Rect.bottom) then
      begin
        GroupState := 'hover';
        FillBackground(T, Theme, Element, 'hover', Inner, CardRadius, Own, True);
      end;
      Title := V.Title;
      if DividerBorder(V) then
      begin
        // its border as dividers: one at the top with its title as the text (a plain line without one), one at the
        // bottom when set; in the dividers' look
        if DividerTop(V) then
        begin
          if V.BackTitle <> '' then
          begin
            TitleLine := TLine.Create;
            try
              TitleLine.DividerText := V.BackTitle;
              Y := Round(R.top + DividerTextHeight / 2) + 0.5;
              DrawDividerText(T, TitleLine, D2D1RectF(R.left, R.top, R.right, R.top + DividerTextHeight), Y, Sep,
                LabelBrush);
            finally
              TitleLine.Free;
            end;
          end
          else
          begin
            Y := Round(R.top + SeparatorHeight / 2) + 0.5;
            T.DrawLine(D2D1PointF(R.left + 8, Y), D2D1PointF(R.right - 8, Y), Sep, 1);
          end;
        end;
        if DividerBottom(V) then
        begin
          Y := Round(R.bottom - SeparatorHeight / 2) + 0.5;
          T.DrawLine(D2D1PointF(R.left + 8, Y), D2D1PointF(R.right - 8, Y), Sep, 1);
        end;
        Continue;
      end;
      // its border (or 3D border); none set: the dividers' colour (so the frame shows); "none": no frame line
      DrawBorder(T, Theme, Element, GroupState, Own, Inner, CardRadius, Sep);
      T.CreateSolidColorBrush(ToD2D(Theme.Color(Element, GroupState, 'foreground', RGBA($1B, $1B, $1B), Own)), nil, Brush);
      if (Title <> '') and (V.Card <> nil) and V.Card.TitleAsDivider then
      begin
        // its title as a divider: a line with the text, in the dividers' look
        TitleLine := TLine.Create;
        try
          TitleLine.DividerText := Title;
          Y := Round(R.top + GroupPad + DividerTextHeight / 2) + 0.5;
          DrawDividerText(T, TitleLine, D2D1RectF(R.left + GroupPad, R.top + GroupPad, R.right - GroupPad,
            R.top + GroupPad + DividerTextHeight), Y, Sep, LabelBrush);
        finally
          TitleLine.Free;
        end;
      end
      else if Title <> '' then
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
    if V.Kind in [vkItem, vkMenu, vkCommand, vkBack, vkSearch] then
    begin
      DrawShadow(T, Theme, Own, Inner, CardRadius);
      if Clear_ then
        T.FillRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), Base);
      if V.Kind in [vkItem, vkMenu, vkCommand] then
        FillBackground(T, Theme, Element, 'normal', Inner, CardRadius, Own);
    end;
    if Editing and V.Sometimes then
      DrawStripes(T, Inner, Stripe);
    // hover and pressed over the normal background: the state's own, a pressed card without one as hovered
    if (State = 'pressed') and not FillBackground(T, Theme, Element, 'pressed', Inner, CardRadius, Own, True) then
      State := 'hover';
    if (State = 'hover') and not FillBackground(T, Theme, Element, 'hover', Inner, CardRadius, Own, True) then
      T.FillRoundedRectangle(D2D1RoundedRect(Inner, CardRadius, CardRadius), Hover);
    DrawBorder(T, Theme, Element, State, Own, Inner, CardRadius, nil);
    // the keyboard's card (plan 03 3.7): a focus ring in the theme's focused border, as Windows' focus rectangle
    if G.KeyFocus and (I = Selected) then
      T.DrawRoundedRectangle(D2D1RoundedRect(D2D1RectF(Inner.left + 1, Inner.top + 1, Inner.right - 1, Inner.bottom - 1),
        Max(0, CardRadius - 1), Max(0, CardRadius - 1)), Accent, 2);
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
      TitleLayout := WrappedTitle(Title, Fmt, TitleRight - R.left - TextLeft, TitleBottom - TitleTop, Access);
      if TitleLayout <> nil then
      begin
        // lines centred in their room; more lines than fit: from the top, the last one cut
        if Succeeded(TitleLayout.GetMetrics(Metrics)) and (Metrics.height > TitleBottom - TitleTop + 0.5) then
          TitleLayout.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
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
  // a level taller than it is shown (the work area's height): a thin bar at its right edge, where the shown part is
  // (plan 03 3.4); the wheel and the keys scroll it
  if G.Height > VisibleHeight + 0.5 then
  begin
    Track := VisibleHeight - 2 * OuterPad - 4;
    Thumb := Max(16, Track * VisibleHeight / G.Height);
    Y := OuterPad + 2 + (Track - Thumb) * EnsureRange(ScrollY / (G.Height - VisibleHeight), 0, 1);
    Dim.SetOpacity(0.7);
    T.FillRoundedRectangle(D2D1RoundedRect(D2D1RectF(G.Width - 6, Y, G.Width - 3, Y + Thumb), 1.5, 1.5), Dim);
    Dim.SetOpacity(1);
  end;
  // what is selected in the settings app's editor (the preview only): a card, its own boxes (not the inner cards made
  // for what it found); a template ("<card id>~t<n>"), the inner cards that follow it. A red outline around each, 5 DIP
  // outside it on every side, so it stays clear of the card's own border; drawn after every card, so none covers it
  if Marked <> '' then
  begin
    T.CreateSolidColorBrush(ToD2D(Theme.Color('card', 'marked', 'border', RGBA($E0, $20, $20), nil)), nil, Outline);
    MarkId := Marked;
    MarkTemplate := -1;
    if Pos('~t', Marked) > 0 then
    begin
      MarkId := Copy(Marked, 1, Pos('~t', Marked) - 1);
      MarkTemplate := StrToIntDef(Copy(Marked, Pos('~t', Marked) + 2, MaxInt), -1);
    end;
    for I := 0 to High(G.Boxes) do
    begin
      V := G.Boxes[I].Card;
      if V.CardId <> MarkId then
        Continue;
      if MarkTemplate < 0 then
      begin
        if V.InGroup then
          Continue;   // an inner card: the template's, not the card's own
      end
      else if not V.InGroup or (V.Template = nil) or (V.Card.Templates = nil) or
        (MarkTemplate >= V.Card.Templates.Count) or (V.Template <> V.Card.Templates[MarkTemplate]) then
        Continue;
      R := G.Boxes[I].Rect;
      R.top := R.top - ScrollY;
      R.bottom := R.bottom - ScrollY;
      if (R.bottom < 0) or (R.top > VisibleHeight) then
        Continue;
      Own := nil;
      if V.LookCard <> nil then
        Own := V.LookCard.Look;
      CardRadius := Theme.Number('card', 'normal', 'radius', ItemRadius, Own) + MarkGap;
      T.DrawRoundedRectangle(D2D1RoundedRect(D2D1RectF(R.left + 2 - MarkGap, R.top + 1 - MarkGap, R.right - 2 + MarkGap,
        R.bottom - 1 + MarkGap), CardRadius, CardRadius), Outline, 1.5);
    end;
  end;
end;

// A picture of a size (pixels) and a render target on it at a scale; Target nil when Direct2D failed.
function NewPicture(Width, Height: Integer; Scale: Single; out Target: ID2D1DCRenderTarget): TPicture;
var
  BMI: TBitmapInfo;
  Bits: Pointer;
  ScreenDC: HDC;
  Props: TD2D1RenderTargetProperties;
  Rect: TRect;
begin
  EnsureFactories;
  Result.Width := Max(1, Width);
  Result.Height := Max(1, Height);
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
  end
  else
    Target := nil;
end;

function Render(const G: TGeometry; Selected: Integer; ScrollY, Scale, VisibleHeight: Single;
  const Marked: string; Editing: Boolean): TPicture;
var
  Target: ID2D1DCRenderTarget;
begin
  Result := NewPicture(Ceil(G.Width * Scale), Ceil(VisibleHeight * Scale), Scale, Target);
  if Target <> nil then
  begin
    DrawScale := Scale;
    Target.BeginDraw;
    DrawLevel(Target, G, Selected, ScrollY, VisibleHeight, TLook.Current, Marked, Editing);
    Target.EndDraw;
  end;
end;

function RenderShadow(const G: TGeometry; Scale, VisibleHeight: Single; out Margin: Integer): TPicture;
var
  Theme: TTheme;
  MenuOwn, S: TJSONObject;
  Target: ID2D1DCRenderTarget;
  M, Radius: Single;
begin
  Result := Default(TPicture);
  Margin := 0;
  if (G.MenuCard = nil) or not (G.MenuCard.Look is TJSONObject) then
    Exit;
  MenuOwn := G.MenuCard.Look;
  if not (MenuOwn.GetValue('shadow') is TJSONObject) then
    Exit;
  EnsureFactories;
  Theme := CurrentTheme(TLook.Current.Dark);
  if SeeThrough(Theme, MenuOwn) then
    Exit;   // no window to shade: the cards' own shadows
  S := TJSONObject(MenuOwn.GetValue('shadow'));
  // room for the shadow: its distance and half its blur, a little more
  M := Max(0, Theme.Number('card', 'normal', 'distance', 3, S)) + EnsureRange(Theme.Number('card', 'normal', 'blur', 0, S), 0, MaxBlur) / 2 + 2;
  Margin := Ceil(M * Scale);
  Radius := Theme.Number('menu', 'normal', 'radius', WindowRadius, MenuOwn);
  Result := NewPicture(Ceil(G.Width * Scale) + 2 * Margin, Ceil(VisibleHeight * Scale) + 2 * Margin, Scale, Target);
  if Target = nil then
    Exit;
  Target.BeginDraw;
  Target.Clear(D2D1ColorF(0, 0, 0, 0));
  DrawShadow(Target, Theme, MenuOwn, D2D1RectF(Margin / Scale + 0.5, Margin / Scale + 0.5,
    Margin / Scale + G.Width - 0.5, Margin / Scale + VisibleHeight - 0.5), Radius);
  Target.EndDraw;
end;

function BlendFunction: TBlendFunction; forward;

procedure PresentShadow(ShadowWnd, Wnd: HWND; const ScreenPos: TPoint; const G: TGeometry; Scale, VisibleHeight: Single);
var
  P: TPicture;
  Margin: Integer;
  ScreenDC: HDC;
  Blend: TBlendFunction;
  Pos, Src: TPoint;
  Size: TSize;
begin
  P := RenderShadow(G, Scale, VisibleHeight, Margin);
  if P.Width = 0 then
  begin
    ShowWindow(ShadowWnd, SW_HIDE);
    Exit;
  end;
  ScreenDC := GetDC(0);
  try
    Blend := BlendFunction;
    Pos := Point(ScreenPos.X - Margin, ScreenPos.Y - Margin);
    Src := Point(0, 0);
    Size.cx := P.Width;
    Size.cy := P.Height;
    UpdateLayeredWindow(ShadowWnd, ScreenDC, @Pos, @Size, P.DC, @Src, 0, @Blend, ULW_ALPHA);
    // just behind its level
    SetWindowPos(ShadowWnd, Wnd, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_SHOWWINDOW);
  finally
    ReleaseDC(0, ScreenDC);
    P.Free;
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
