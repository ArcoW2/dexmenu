unit Dexmenu.Preview;

// The settings app's preview (docs/plans/02-PLAN-own-menu.md 3.8; plan 00 step 4): a child window in the settings
// app that the DLL draws the menu into, from a layout's text and seen items (Dexmenu.Seen), with the same tree,
// placement and drawing as a right-click, so the preview is the result. Live: hover, submenus opening (next to their
// card, as at a right-click), Esc; choosing an item does nothing, there being no program to run it. No hook is set
// in the settings app: the handler never runs there.
//
// Exported (DexmenuShell.dpr), for the settings app:
//   DexmenuPreviewCreate(Parent): the preview window, a child of Parent.
//   DexmenuPreviewSet(Wnd, Layout, Seen, Kind, Error, ErrorChars): what it shows; False and Error filled when the layout
//     or the seen items cannot be used (the preview then shows nothing).
// DEXMENU_DUMP: as Dexmenu.Menu, every shown level and card written after each redraw (positions: client pixels).

interface

uses
  Winapi.Windows;

function DexmenuPreviewCreate(Parent: HWND): HWND; stdcall;
function DexmenuPreviewSet(Wnd: HWND; Layout, Seen, Kind: PWideChar; Error: PWideChar; ErrorChars: Integer): BOOL;
  stdcall;
// The built-in base layout's text into Buffer; the number of characters it needs (with the closing #0).
function DexmenuBaseLayout(Buffer: PWideChar; Chars: Integer): Integer; stdcall;

implementation

uses
  Winapi.Messages, Winapi.D2D1, System.SysUtils, System.Math, System.Classes, System.Generics.Collections,
  Dexmenu.Log, Dexmenu.Layout, Dexmenu.Tree, Dexmenu.Place, Dexmenu.Draw, Dexmenu.Seen;

const
  PreviewClassName = 'DexmenuPreview';
  Margin = 16;   // DIP around the menu in the preview
  HoverTimer = 1;
  SPI_GETMENUSHOWDELAY = $006A;

function GetDpiForWindow(Wnd: HWND): UINT; stdcall; external user32 name 'GetDpiForWindow';

type
  TPreviewLevel = class
  public
    View: TViewLevel;
    Geometry: TGeometry;
    X, Y: Single;          // DIP within the preview
    Selected: Integer;
    Opener: TViewCard;
    destructor Destroy; override;
  end;

  TPreview = class
  public
    Wnd: HWND;
    Layout: ILayout;
    Kind: string;
    Menu: HMENU;
    Top: TNodes;
    Placement: TPlacement;
    Levels: TObjectList<TPreviewLevel>;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Rebuild;
    function Scale: Single;
    procedure Open(LevelIndex, Box: Integer);
    procedure CloseFrom(Index: Integer);
    function LevelAt(X, Y: Single; out Box: Integer): Integer;
    procedure Paint(DC: HDC);
    procedure Dump;
  end;

var
  ClassAtom: ATOM;

destructor TPreviewLevel.Destroy;
begin
  View.Free;
  inherited;
end;

constructor TPreview.Create;
begin
  inherited;
  Levels := TObjectList<TPreviewLevel>.Create;
end;

destructor TPreview.Destroy;
begin
  Clear;
  Levels.Free;
  inherited;
end;

procedure TPreview.Clear;
begin
  Levels.Clear;
  FreeAndNil(Placement);
  FreeAndNil(Top);
  if Menu <> 0 then
    DestroyMenu(Menu);
  Menu := 0;
end;

function TPreview.Scale: Single;
var
  Dpi: UINT;
begin
  Dpi := GetDpiForWindow(Wnd);
  if Dpi = 0 then
    Dpi := 96;
  Result := Dpi / 96;
end;

procedure TPreview.Rebuild;
var
  L: TPreviewLevel;
begin
  Levels.Clear;
  FreeAndNil(Placement);
  FreeAndNil(Top);
  if (Menu = 0) or (Layout = nil) then
    Exit;
  Top := ReadLevel(Menu, '');
  Placement := TPlacement.Create(Layout, Kind, Top);
  L := TPreviewLevel.Create;
  L.View := Placement.TopLevel;
  L.Geometry := Measure(L.View);
  L.X := Margin;
  L.Y := Margin;
  L.Selected := -1;
  Levels.Add(L);
end;

procedure TPreview.CloseFrom(Index: Integer);
begin
  while Levels.Count > Max(Index, 1) do
    Levels.Delete(Levels.Count - 1);
end;

procedure TPreview.Open(LevelIndex, Box: Integer);
var
  Parent, L: TPreviewLevel;
  V: TViewCard;
begin
  Parent := Levels[LevelIndex];
  V := Parent.Geometry.Boxes[Box].Card;
  if not V.HasSubmenu or not V.Enabled then
    Exit;
  if (Levels.Count > LevelIndex + 1) and (Levels[LevelIndex + 1].Opener = V) then
    Exit;
  CloseFrom(LevelIndex + 1);
  L := TPreviewLevel.Create;
  L.Opener := V;
  L.Selected := -1;
  if V.Kind = vkMenu then
    L.View := Placement.MenuLevel(V.Card)
  else
  begin
    ReadChildren(V.Node);
    L.View := Placement.SubmenuLevel(V.Node);
  end;
  L.Geometry := Measure(L.View);
  L.X := Parent.X + Parent.Geometry.Width - 2;
  L.Y := Parent.Y + Parent.Geometry.Boxes[Box].Rect.top - OuterPad;
  Levels.Add(L);
end;

function TPreview.LevelAt(X, Y: Single; out Box: Integer): Integer;
var
  I: Integer;
  L: TPreviewLevel;
begin
  Box := -1;
  for I := Levels.Count - 1 downto 0 do
  begin
    L := Levels[I];
    if (X >= L.X) and (X < L.X + L.Geometry.Width) and (Y >= L.Y) and (Y < L.Y + L.Geometry.Height) then
    begin
      Box := BoxAt(L.Geometry, X - L.X, Y - L.Y, 0);
      Exit(I);
    end;
  end;
  Result := -1;
end;

procedure TPreview.Paint(DC: HDC);
var
  R: TRect;
  MemDC: HDC;
  Bmp, Old: HBITMAP;
  Brush: HBRUSH;
  L: TPreviewLevel;
  P: TPicture;
  S: Single;
begin
  GetClientRect(Wnd, R);
  MemDC := CreateCompatibleDC(DC);
  Bmp := CreateCompatibleBitmap(DC, Max(1, R.Width), Max(1, R.Height));
  Old := SelectObject(MemDC, Bmp);
  try
    if TLook.Current.Dark then
      Brush := CreateSolidBrush(RGB($1F, $1F, $1F))
    else
      Brush := CreateSolidBrush(RGB($EE, $EE, $EE));
    FillRect(MemDC, R, Brush);
    DeleteObject(Brush);
    S := Scale;
    for L in Levels do
    begin
      P := Render(L.Geometry, L.Selected, 0, S, L.Geometry.Height);
      try
        P.PaintOnto(MemDC, Round(L.X * S), Round(L.Y * S));
      finally
        P.Free;
      end;
    end;
    BitBlt(DC, 0, 0, R.Width, R.Height, MemDC, 0, 0, SRCCOPY);
  finally
    SelectObject(MemDC, Old);
    DeleteObject(Bmp);
    DeleteDC(MemDC);
  end;
end;

procedure TPreview.Dump;
var
  Env: array[0..MAX_PATH] of Char;
  Path: string;
  Lines: TStringList;
  I, B: Integer;
  L: TPreviewLevel;
  V: TViewCard;
  R: TD2D1RectF;
  Kind: string;
  Id: UINT;
  S: Single;
begin
  if GetEnvironmentVariable('DEXMENU_DUMP', Env, MAX_PATH) = 0 then
    Exit;
  Path := Env;
  S := Scale;
  Lines := TStringList.Create;
  try
    for I := 0 to Levels.Count - 1 do
    begin
      L := Levels[I];
      Lines.Add(Format('level %d wnd=%d x=%d y=%d w=%d h=%d scale=%s', [I, NativeUInt(Wnd), Round(L.X * S),
        Round(L.Y * S), Ceil(L.Geometry.Width * S), Ceil(L.Geometry.Height * S), FloatToStr(S)]));
      for B := 0 to High(L.Geometry.Boxes) do
      begin
        V := L.Geometry.Boxes[B].Card;
        R := L.Geometry.Boxes[B].Rect;
        Id := 0;
        case V.Kind of
          vkItem: begin Kind := 'item'; Id := V.Node.Id; end;
          vkMenu: Kind := 'menu';
        else
          Kind := 'separator';
        end;
        Lines.Add(Format('card %s id=%u enabled=%d checked=%d default=%d sub=%d selected=%d x=%d y=%d text=%s',
          [Kind, Id, Ord(V.Enabled), Ord(V.Checked), Ord(V.IsDefault), Ord(V.HasSubmenu), Ord(B = L.Selected),
          Round((L.X + (R.left + R.right) / 2) * S), Round((L.Y + (R.top + R.bottom) / 2) * S), V.Title]));
      end;
    end;
    Lines.SaveToFile(Path + '.tmp', TEncoding.UTF8);
    MoveFileEx(PChar(Path + '.tmp'), PChar(Path), MOVEFILE_REPLACE_EXISTING);
  finally
    Lines.Free;
  end;
end;

function PreviewOf(Wnd: HWND): TPreview;
begin
  Result := TPreview(GetWindowLongPtr(Wnd, GWLP_USERDATA));
end;

procedure Redraw(P: TPreview);
begin
  InvalidateRect(P.Wnd, nil, False);
  UpdateWindow(P.Wnd);
  P.Dump;
end;

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  P: TPreview;
  PS: TPaintStruct;
  DC: HDC;
  X, Y, S: Single;
  Index, Box, Delay: Integer;
  L: TPreviewLevel;
  TME: TTrackMouseEvent;
begin
  P := PreviewOf(Wnd);
  if P = nil then
    Exit(DefWindowProc(Wnd, Msg, WP, LP));
  Result := 0;
  try
    case Msg of
      WM_PAINT:
        begin
          DC := BeginPaint(Wnd, PS);
          P.Paint(DC);
          EndPaint(Wnd, PS);
        end;
      WM_ERASEBKGND:
        Result := 1;
      WM_MOUSEMOVE:
        begin
          S := P.Scale;
          X := SmallInt(LP and $FFFF) / S;
          Y := SmallInt((LP shr 16) and $FFFF) / S;
          Index := P.LevelAt(X, Y, Box);
          if Index < 0 then
            Exit;
          L := P.Levels[Index];
          if Box <> L.Selected then
          begin
            L.Selected := Box;
            KillTimer(Wnd, HoverTimer);
            if (Box >= 0) and L.Geometry.Boxes[Box].Card.HasSubmenu then
            begin
              Delay := 400;
              SystemParametersInfo(SPI_GETMENUSHOWDELAY, 0, @Delay, 0);
              SetTimer(Wnd, HoverTimer, Max(Delay, 1), nil);
            end
            else if Box >= 0 then
              P.CloseFrom(Index + 1);
            Redraw(P);
          end;
          TME.cbSize := SizeOf(TME);
          TME.dwFlags := TME_LEAVE;
          TME.hwndTrack := Wnd;
          TME.dwHoverTime := 0;
          TrackMouseEvent(TME);
        end;
      WM_TIMER:
        begin
          KillTimer(Wnd, HoverTimer);
          for Index := P.Levels.Count - 1 downto 0 do
          begin
            L := P.Levels[Index];
            if (L.Selected >= 0) and L.Geometry.Boxes[L.Selected].Card.HasSubmenu then
            begin
              P.Open(Index, L.Selected);
              Redraw(P);
              Break;
            end;
          end;
        end;
      WM_LBUTTONUP:
        begin
          SetFocus(Wnd);
          S := P.Scale;
          Index := P.LevelAt(SmallInt(LP and $FFFF) / S, SmallInt((LP shr 16) and $FFFF) / S, Box);
          if (Index >= 0) and (Box >= 0) and P.Levels[Index].Geometry.Boxes[Box].Card.HasSubmenu then
          begin
            P.Open(Index, Box);
            Redraw(P);
          end;
        end;
      WM_KEYDOWN:
        if WP = VK_ESCAPE then
        begin
          P.CloseFrom(P.Levels.Count - 1);
          Redraw(P);
        end;
      WM_GETDLGCODE:
        Result := DLGC_WANTALLKEYS;
      WM_NCDESTROY:
        begin
          SetWindowLongPtr(Wnd, GWLP_USERDATA, 0);
          P.Free;
          Result := DefWindowProc(Wnd, Msg, WP, LP);
        end;
    else
      Result := DefWindowProc(Wnd, Msg, WP, LP);
    end;
  except
    on E: Exception do
      Log('preview: ' + E.Message);
  end;
end;

function DexmenuPreviewCreate(Parent: HWND): HWND; stdcall;
var
  WC: TWndClassEx;
  P: TPreview;
  R: TRect;
begin
  Result := 0;
  try
    if ClassAtom = 0 then
    begin
      FillChar(WC, SizeOf(WC), 0);
      WC.cbSize := SizeOf(WC);
      WC.lpfnWndProc := @WndProc;
      WC.hInstance := HInstance;
      WC.hCursor := LoadCursor(0, IDC_ARROW);
      WC.lpszClassName := PreviewClassName;
      ClassAtom := RegisterClassEx(WC);
    end;
    GetClientRect(Parent, R);
    Result := CreateWindowEx(0, PreviewClassName, 'Dexmenu preview', WS_CHILD or WS_VISIBLE or WS_CLIPSIBLINGS,
      0, 0, R.Width, R.Height, Parent, 0, HInstance, nil);
    if Result = 0 then
      Exit;
    P := TPreview.Create;
    P.Wnd := Result;
    SetWindowLongPtr(Result, GWLP_USERDATA, LONG_PTR(P));
  except
    on E: Exception do
      Log('preview not made: ' + E.Message);
  end;
end;

function DexmenuPreviewSet(Wnd: HWND; Layout, Seen, Kind: PWideChar; Error: PWideChar; ErrorChars: Integer): BOOL;
  stdcall;
var
  P: TPreview;
  Text, Problem: string;
begin
  Result := False;
  Problem := '';
  try
    P := PreviewOf(Wnd);
    if P = nil then
      Problem := 'not a preview window'
    else
    begin
      P.Clear;
      P.Kind := Kind;
      if P.Kind = '' then
        P.Kind := 'default';
      Text := Layout;
      if Text = '' then
        Text := BaseLayout;
      P.Layout := ParseLayout(Text, 'the layout', Problem);
      if P.Layout <> nil then
      begin
        Text := Seen;
        if Text = '' then
          Text := '{ "items": [] }';
        P.Menu := MenuFromSeen(Text, Problem);
      end;
      if (P.Layout <> nil) and (P.Menu <> 0) then
      begin
        P.Rebuild;
        Result := True;
      end;
      Redraw(P);
    end;
  except
    on E: Exception do
      Problem := E.Message;
  end;
  if (Error <> nil) and (ErrorChars > 0) then
    StrPLCopy(Error, Problem, ErrorChars - 1);
end;

function DexmenuBaseLayout(Buffer: PWideChar; Chars: Integer): Integer; stdcall;
begin
  Result := Length(BaseLayout) + 1;
  if (Buffer <> nil) and (Chars > 0) then
    StrPLCopy(Buffer, BaseLayout, Chars - 1);
end;

end.
