unit Dexmenu.Menu;

// Dexmenu's own menu (docs/plans/executed/02-PLAN-own-menu.md 3.1, 3.6, 3.7; plan 00 step 3): shown in place of Windows' menu
// on the caught show call, as a window per level (the top level, an open submenu next to its card). Windows' items
// stay in Windows' menu; the chosen item's id is handed back as Windows' menu would (returned with TPM_RETURNCMD,
// else posted as WM_COMMAND to the owner window), so the program runs it as always.
//
// As Windows' menu, it sends the owner WM_ENTERMENULOOP, WM_INITMENUPOPUP for the top menu and for each Windows
// submenu when it opens (an extension fills Send to, Open with then), WM_UNINITMENUPOPUP and WM_EXITMENULOOP; not with
// TPM_NONOTIFY. Changes the program makes on its menu while it is shown (Explorer sets Explorer commands' states
// then) make the menu read Windows' items again and redraw.
//
// For the tests: DEXMENU_DUMP names a file that gets every shown level and card after each redraw.

interface

uses
  Winapi.Windows, Winapi.Messages, System.Types, System.Generics.Collections, System.JSON, Dexmenu.Tree, Dexmenu.Place,
  Dexmenu.Layout, Dexmenu.Draw, Dexmenu.Tip;

type
  TMenuSession = class;

  TLevelWindow = class
  public
    Session: TMenuSession;
    Index: Integer;
    Wnd: HWND;
    View: TViewLevel;
    Geometry: TGeometry;
    Pos: TPoint;         // screen pixels
    Scale: Single;
    Selected: Integer;   // box index or -1
    ScrollY: Single;     // DIP
    VisibleHeight: Single;
    Opener: TViewCard;   // the card in the level above that opened it; nil at the top
    Replaces: Boolean;   // opened in place of the level above (that one hidden until this one closes; "<<" back)
    ShadowWnd: HWND;     // the menu's own shadow (plan 03 3.4): a window behind it taking no mouse; 0 until needed
    destructor Destroy; override;
    procedure Redraw;
    // Its shadow drawn and shown behind it while it is shown, hidden while it is not.
    procedure UpdateShadow;
    function BoxOfCard(V: TViewCard): Integer;
  end;

  TMenuSession = class
  private
    FOriginal: HMENU;
    FOwner: HWND;
    FFlags: UINT;
    FLayout: ILayout;
    FKind: string;
    FTop: TNodes;
    FSeen: TJSONArray;    // every item seen while shown, also those Windows' menu lost (Dexmenu.Seen)
    FEmpty: TDictionary<HMENU, Boolean>;     // Windows submenus empty even when opened: their items not shown
    FChecked: TDictionary<HMENU, Boolean>;   // submenus looked at for that
    FEarly: TList<HMENU>;    // submenus opened before the user opened them (FindEmpty): open until the menu closes
    FDeep: Boolean;          // the layout's rules look inside submenus (RulesLookDeeper)
    FHints: TDictionary<string, string>;   // the items' own hints, from the seen items (Dexmenu.Seen.HintsOf)
    FUsage: TDictionary<string, Integer>;  // this kind's use counts (Dexmenu.Usage), for used rules
    FLastUse: TDictionary<string, string>; // this kind's times of last use, for used rules (plan 09)
    FChosenKey: string;                    // the chosen item's use count key; '' when none was chosen
    FTextSize: Single;                     // the menu's size (Ctrl+scroll; settings.json menu.textSize)
    FTextSizeChanged: Boolean;             // Ctrl+scroll changed it: kept once the menu closed (Dexmenu.Hook)
    FSearch: string;                       // what is typed into the search (plan 02 3.6); '' : no search
    FTip: TTip;
    FTipLevel: TLevelWindow; // the level and box a hint waits for (TipTimer) or shows for
    FTipBox: Integer;
    FPlacement: TPlacement;
    FLevels: TObjectList<TLevelWindow>;
    FDone: Boolean;
    FChosen: UINT;
    FRefreshPosted: Boolean;
    FHoverTimerLevel: Integer;
    FLastMouse: TPoint;   // the mouse's last screen position: a move that is no move keeps the keys' focus ring
    FSettings: TMenuSettings;   // the global settings (settings.json "menu"), read when the menu shows
    FCommand: TCommand;         // Dexmenu's own item chosen ("Windows' menu", "Edit menu..."); ccNone else
    function OpensOnHover(V: TViewCard): Boolean;
    procedure HoverTip(L: TLevelWindow; Box: Integer);
    procedure ShowTip(L: TLevelWindow);
    procedure HideTip;
    function Notify: Boolean;
    function MakeWindow(Index: Integer; Activate: Boolean): HWND;
    procedure PlaceTop(X, Y: Integer; Params: PTPMParams);
    procedure CloseFrom(Index: Integer);
    procedure Cancel;
    procedure Choose(V: TViewCard);
    procedure Open(LevelIndex, Box: Integer; SelectFirst: Boolean);
    procedure MoveSelection(L: TLevelWindow; Delta: Integer);
    procedure KeyDown(Key: WPARAM);
    // Ctrl+scroll: the menu larger (Delta > 0) or smaller; its submenus closed, the menu drawn again where it is
    procedure ChangeTextSize(Delta: Integer);
    procedure CharKey(Ch: Char);
    // The top level shows the search for FSearch, or its own lines again when FSearch is ''.
    procedure ShowSearch;
    procedure Refresh;
    procedure KeepSeen;
    procedure FindEmpty(Nodes: TNodes);
    procedure Dump;
    function IsOurs(Wnd: HWND): Boolean;
  public
    constructor Create(Original: HMENU; Owner: HWND; Flags: UINT; const Layout: ILayout; const Kind: string);
    destructor Destroy; override;
    // Shows the menu and returns as TrackPopupMenuEx would.
    function Run(X, Y: Integer; Params: PTPMParams): BOOL;
    // A change was made to a menu while this one is shown (the hooks): read again and redraw, once.
    procedure Changed(Menu: HMENU);
    function Owns(Menu: HMENU): Boolean;
    // Closed by another right-click while shown (Dexmenu.Hook): cancelled and its windows hidden now, before the new
    // menu shows inside its message loop; the loop ends once that one is closed.
    procedure Dismiss;
    property Original: HMENU read FOriginal;
    // Dexmenu's own item chosen, when one was (the menu then returned no choice)
    property Command: TCommand read FCommand;
    // The chosen item's use count key (Dexmenu.Usage.UsageKey); '' when no item was chosen
    property ChosenKey: string read FChosenKey;
    property TextSize: Single read FTextSize;
    property TextSizeChanged: Boolean read FTextSizeChanged;
    // Whether a search is being typed (a space then goes into it)
    function IsSearching: Boolean;
  end;

threadvar
  ActiveSession: TMenuSession;

implementation

uses
  System.SysUtils, System.Math, System.Classes, Winapi.D2D1, Winapi.MultiMon, Dexmenu.Log, Dexmenu.Seen, Dexmenu.Usage, Dexmenu.Icons;

const
  MenuClassName = 'DexmenuMenu';
  WM_DEXMENU_REFRESH = WM_APP + $D3;
  HoverTimer = 1;
  TipTimer = 2;
  SPI_GETMENUSHOWDELAY = $006A;

function GetDpiForWindow(Wnd: HWND): UINT; stdcall; external user32 name 'GetDpiForWindow';

var
  ClassAtom: ATOM;

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall; forward;

procedure EnsureClass;
var
  WC: TWndClassEx;
begin
  if ClassAtom <> 0 then
    Exit;
  FillChar(WC, SizeOf(WC), 0);
  WC.cbSize := SizeOf(WC);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.lpszClassName := MenuClassName;
  ClassAtom := RegisterClassEx(WC);
end;

function LevelOf(Wnd: HWND): TLevelWindow;
begin
  Result := TLevelWindow(GetWindowLongPtr(Wnd, GWLP_USERDATA));
end;

// ---- a level -------------------------------------------------------------------------------------------------------

destructor TLevelWindow.Destroy;
begin
  if ShadowWnd <> 0 then
    DestroyWindow(ShadowWnd);
  if Wnd <> 0 then
  begin
    SetWindowLongPtr(Wnd, GWLP_USERDATA, 0);
    DestroyWindow(Wnd);
  end;
  View.Free;
  inherited;
end;

procedure TLevelWindow.Redraw;
begin
  Present(Wnd, Pos, Geometry, Selected, ScrollY, Scale, VisibleHeight);
  UpdateShadow;
  Session.Dump;
end;

procedure TLevelWindow.UpdateShadow;
begin
  if (Wnd = 0) or not IsWindowVisible(Wnd) then
  begin
    if ShadowWnd <> 0 then
      ShowWindow(ShadowWnd, SW_HIDE);
    Exit;
  end;
  if ShadowWnd = 0 then
    // owned by the level, so it goes with it; layered and transparent to the mouse, never active
    ShadowWnd := CreateWindowEx(WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_TOPMOST or WS_EX_TOOLWINDOW or
      WS_EX_NOACTIVATE, 'Static', '', WS_POPUP, 0, 0, 1, 1, Wnd, 0, HInstance, nil);
  if ShadowWnd <> 0 then
    PresentShadow(ShadowWnd, Wnd, Pos, Geometry, Scale, VisibleHeight);
end;

function TLevelWindow.BoxOfCard(V: TViewCard): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Geometry.Boxes) do
    if Geometry.Boxes[I].Card = V then
      Exit(I);
  Result := -1;
end;

// ---- the session -----------------------------------------------------------------------------------------------------

constructor TMenuSession.Create(Original: HMENU; Owner: HWND; Flags: UINT; const Layout: ILayout;
  const Kind: string);
begin
  inherited Create;
  FKind := Kind;
  FOriginal := Original;
  FOwner := Owner;
  FFlags := Flags;
  FLayout := Layout;
  FLevels := TObjectList<TLevelWindow>.Create;
  FEmpty := TDictionary<HMENU, Boolean>.Create;
  FChecked := TDictionary<HMENU, Boolean>.Create;
  FEarly := TList<HMENU>.Create;
end;

destructor TMenuSession.Destroy;
begin
  FLevels.Free;        // the views first: they point into the nodes
  FPlacement.Free;
  FTop.Free;
  FSeen.Free;
  FEmpty.Free;
  FChecked.Free;
  FEarly.Free;
  FTip.Free;
  FHints.Free;
  FUsage.Free;
  FLastUse.Free;
  inherited;
end;

function TMenuSession.Notify: Boolean;
begin
  Result := FFlags and TPM_NONOTIFY = 0;
end;

function TMenuSession.IsOurs(Wnd: HWND): Boolean;
var
  L: TLevelWindow;
begin
  for L in FLevels do
    if L.Wnd = Wnd then
      Exit(True);
  Result := False;
end;

function TMenuSession.Owns(Menu: HMENU): Boolean;
  function InNodes(Nodes: TNodes): Boolean;
  var
    N: TNode;
  begin
    if Nodes <> nil then
      for N in Nodes do
        if (N.SubMenu = Menu) or InNodes(N.Children) then
          Exit(True);
    Result := False;
  end;
begin
  Result := (Menu = FOriginal) or InNodes(FTop);
end;

function TMenuSession.MakeWindow(Index: Integer; Activate: Boolean): HWND;
var
  ExStyle: DWORD;
  OwnerWnd: HWND;
begin
  EnsureClass;
  ExStyle := WS_EX_LAYERED or WS_EX_TOPMOST or WS_EX_TOOLWINDOW;
  if not Activate then
    ExStyle := ExStyle or WS_EX_NOACTIVATE;
  if Index = 0 then
    OwnerWnd := FOwner
  else
    OwnerWnd := FLevels[0].Wnd;
  Result := CreateWindowEx(ExStyle, MenuClassName, 'Dexmenu', WS_POPUP, 0, 0, 1, 1, OwnerWnd, 0, HInstance, nil);
end;

// The level's size and its place on the screen: as Windows' menu, at the point with the alignment flags, flipped at
// the work area's edges, as tall as the work area at most (then it scrolls).
procedure FitOnScreen(L: TLevelWindow; X, Y: Integer; AlignRight, AlignBottom: Boolean; FlipX: Integer);
var
  Mon: HMONITOR;
  Info: TMonitorInfo;
  W, H: Integer;
  Work: TRect;
begin
  Mon := MonitorFromPoint(Point(X, Y), MONITOR_DEFAULTTONEAREST);
  Info.cbSize := SizeOf(Info);
  GetMonitorInfo(Mon, @Info);
  Work := Info.rcWork;
  L.VisibleHeight := Min(L.Geometry.Height, (Work.Height) / L.Scale);
  W := Ceil(L.Geometry.Width * L.Scale);
  H := Ceil(L.VisibleHeight * L.Scale);
  if AlignRight then
    X := X - W;
  if AlignBottom then
    Y := Y - H;
  if X + W > Work.Right then
    X := Max(Work.Left, FlipX - W);
  if X < Work.Left then
    X := Work.Left;
  if Y + H > Work.Bottom then
    Y := Max(Work.Top, Work.Bottom - H);
  if Y < Work.Top then
    Y := Work.Top;
  L.Pos := Point(X, Y);
end;

procedure TMenuSession.PlaceTop(X, Y: Integer; Params: PTPMParams);
var
  L: TLevelWindow;
  Dpi: UINT;
begin
  L := FLevels[0];
  SetWindowPos(L.Wnd, 0, X, Y, 1, 1, SWP_NOZORDER or SWP_NOACTIVATE);
  Dpi := GetDpiForWindow(L.Wnd);
  if Dpi = 0 then
    Dpi := 96;
  L.Scale := Dpi / 96 * FTextSize;
  L.Geometry := Measure(L.View);
  if FFlags and TPM_CENTERALIGN <> 0 then
    X := X - Ceil(L.Geometry.Width * L.Scale) div 2;
  if FFlags and TPM_VCENTERALIGN <> 0 then
    Y := Y - Ceil(L.Geometry.Height * L.Scale) div 2;
  FitOnScreen(L, X, Y, FFlags and TPM_RIGHTALIGN <> 0, FFlags and TPM_BOTTOMALIGN <> 0, X);
end;

function TMenuSession.Run(X, Y: Integer; Params: PTPMParams): BOOL;
var
  Msg: TMsg;
  L: TLevelWindow;
  I: Integer;
  Quit: Boolean;
  QuitCode: WPARAM;
begin
  Result := False;
  if Notify then
  begin
    SendMessage(FOwner, WM_ENTERMENULOOP, 1, 0);
    SendMessage(FOwner, WM_INITMENUPOPUP, WPARAM(FOriginal), MakeLParam(0, 0));
  end;
  FTop := ReadLevel(FOriginal, '');
  FSettings := MenuSettings;
  if FLayout.MenuCard.SubmenuMode <> smDefault then
    FSettings.Submenus := FLayout.MenuCard.SubmenuMode;   // the layout's own (its menu card's) over the general one
  FTextSize := FSettings.TextSize;
  SetMenuLook(FSettings);
  FHints := HintsOf(ReadSeenText(FKind));
  FUsage := ReadUsage(FKind);
  FLastUse := ReadLastUse(FKind);
  // the rules look inside submenus, or a used rule may hold an item of one: those filled only
  // when opened are opened now
  FDeep := RulesLookDeeper(FLayout, FKind) or (UsesUsage(FLayout, FKind) and UsageGoesDeeper(FUsage));
  FindEmpty(FTop);
  if Notify and ProbingIcons then
    ProbeOwnerDrawn(FOwner, FTop);   // Explorer's own icons: the probe (plan 02 3.8), off unless switched on
  FPlacement := TPlacement.Create(FLayout, FKind, FTop, FUsage, FLastUse);
  FPlacement.Empty := FEmpty;
  FPlacement.AtRightClick := True;
  FPlacement.Usage := FUsage;

  L := TLevelWindow.Create;
  L.Session := Self;
  L.Index := 0;
  L.Selected := -1;
  L.View := FPlacement.TopLevel;
  FLevels.Add(L);
  L.Wnd := MakeWindow(0, True);
  SetWindowLongPtr(L.Wnd, GWLP_USERDATA, LONG_PTR(L));
  FTip := TTip.Create(L.Wnd);
  PlaceTop(X, Y, Params);
  L.Redraw;
  ShowWindow(L.Wnd, SW_SHOW);
  L.UpdateShadow;
  SetForegroundWindow(L.Wnd);
  SetFocus(L.Wnd);

  ActiveSession := Self;
  Quit := False;
  QuitCode := 0;
  try
    while not FDone do
    begin
      if not GetMessage(Msg, 0, 0, 0) then
      begin
        Quit := True;
        QuitCode := Msg.wParam;
        Break;
      end;
      TranslateMessage(Msg);
      DispatchMessage(Msg);
      if (FOwner <> 0) and not IsWindow(FOwner) then
        Break;
    end;
  finally
    ActiveSession := nil;
  end;

  HideTip;
  FLevels.Clear;   // the windows gone
  if Notify then
    for I := FEarly.Count - 1 downto 0 do   // the submenus opened early close with the menu
      SendMessage(FOwner, WM_UNINITMENUPOPUP, WPARAM(FEarly[I]), 0);
  KeepSeen;
  WriteSeen(FKind, FSeen);   // for the settings app's preview (Dexmenu.Seen)
  SaveIcons(FTop);           // the items' icons too (Dexmenu.Icons)
  if Notify then
  begin
    SendMessage(FOwner, WM_UNINITMENUPOPUP, WPARAM(FOriginal), 0);
    SendMessage(FOwner, WM_EXITMENULOOP, 1, 0);
  end;
  if Quit then
    PostQuitMessage(Integer(QuitCode));
  if FChosen = 0 then
    Exit(False);
  if FFlags and TPM_RETURNCMD <> 0 then
    Result := BOOL(FChosen)
  else
  begin
    PostMessage(FOwner, WM_COMMAND, FChosen, 0);
    Result := True;
  end;
end;

procedure TMenuSession.ChangeTextSize(Delta: Integer);
var
  Size: Single;
  L: TLevelWindow;
  Dpi: UINT;
begin
  if Delta = 0 then
    Exit;
  Size := ClampTextSize(FTextSize + Sign(Delta) * 0.1);
  if Size = FTextSize then
    Exit;
  FTextSize := Size;
  FTextSizeChanged := True;
  HideTip;
  CloseFrom(1);
  L := FLevels[0];
  Dpi := GetDpiForWindow(L.Wnd);
  if Dpi = 0 then
    Dpi := 96;
  L.Scale := Dpi / 96 * FTextSize;
  FitOnScreen(L, L.Pos.X, L.Pos.Y, False, False, L.Pos.X);
  L.ScrollY := Min(L.ScrollY, Max(0, L.Geometry.Height - L.VisibleHeight));
  L.Redraw;
end;

procedure TMenuSession.CloseFrom(Index: Integer);
var
  I: Integer;
  L: TLevelWindow;
begin
  for I := FLevels.Count - 1 downto Max(Index, 1) do
  begin
    L := FLevels[I];
    if L = FTipLevel then
      HideTip;
    // one opened early stays open until the menu closes (Run)
    if Notify and (L.Opener <> nil) and (L.Opener.Kind = vkItem) and not FEarly.Contains(L.Opener.Node.SubMenu) then
      SendMessage(FOwner, WM_UNINITMENUPOPUP, WPARAM(L.Opener.Node.SubMenu), 0);
    if L.Replaces then
    begin
      // the level it replaced shows again, and is active again when this one was
      ShowWindow(FLevels[I - 1].Wnd, SW_SHOWNOACTIVATE);
      FLevels[I - 1].Redraw;
      if GetActiveWindow = L.Wnd then
        SetActiveWindow(FLevels[I - 1].Wnd);
    end;
    FLevels.Delete(I);
  end;
end;

// Submenus open on hover unless only on a click is set, or they open in place of the menu (plan 02 3.7).
function TMenuSession.OpensOnHover(V: TViewCard): Boolean;
begin
  Result := not FSettings.OnClickOnly and (SubmenuModeOf(V, FSettings) <> smReplace);
end;

procedure TMenuSession.Cancel;
begin
  FChosen := 0;
  FDone := True;
end;

procedure TMenuSession.Dismiss;
var
  L: TLevelWindow;
begin
  Cancel;
  HideTip;
  for L in FLevels do
  begin
    if L.ShadowWnd <> 0 then
      ShowWindow(L.ShadowWnd, SW_HIDE);
    if L.Wnd <> 0 then
      ShowWindow(L.Wnd, SW_HIDE);
  end;
end;

procedure TMenuSession.Choose(V: TViewCard);
begin
  if (V <> nil) and (V.Kind = vkCommand) then
  begin
    FCommand := V.Command;   // done by the show call once this menu is closed (Dexmenu.Hook)
    FChosen := 0;
    FDone := True;
    Exit;
  end;
  if (V = nil) or (V.Kind <> vkItem) or not V.Enabled or V.HasSubmenu then
    Exit;
  FChosen := V.Node.Id;
  FChosenKey := UsageKey(V.Node);
  FDone := True;
end;

procedure TMenuSession.Open(LevelIndex, Box: Integer; SelectFirst: Boolean);
var
  Mode: TSubmenuMode;
  Parent, L: TLevelWindow;
  V: TViewCard;
  R: TD2D1RectF;
  X, Y, Index: Integer;
  Dpi: UINT;
begin
  Parent := FLevels[LevelIndex];
  if (Box < 0) or (Box > High(Parent.Geometry.Boxes)) then
    Exit;
  V := Parent.Geometry.Boxes[Box].Card;
  if not V.HasSubmenu or not V.Enabled then
    Exit;
  if (FLevels.Count > LevelIndex + 1) and (FLevels[LevelIndex + 1].Opener = V) then
    Exit;   // already open
  CloseFrom(LevelIndex + 1);

  L := TLevelWindow.Create;
  L.Session := Self;
  L.Index := LevelIndex + 1;
  L.Selected := -1;
  L.Opener := V;
  if V.Kind = vkMenu then
    L.View := FPlacement.LevelOf(V)
  else
  begin
    if Notify and not FEarly.Contains(V.Node.SubMenu) then   // one opened early is open already
    begin
      // the submenu's position in its menu, as Windows' menu sends it
      Index := 0;
      while (Index < GetMenuItemCount(V.Node.Menu)) and (GetSubMenu(V.Node.Menu, Index) <> V.Node.SubMenu) do
        Inc(Index);
      SendMessage(FOwner, WM_INITMENUPOPUP, WPARAM(V.Node.SubMenu), MakeLParam(Index, 0));
    end;
    ReadChildren(V.Node);
    FindEmpty(V.Node.Children);
    L.View := FPlacement.SubmenuLevel(V.Node);
  end;
  Mode := SubmenuModeOf(V, FSettings);
  L.Replaces := Mode = smReplace;
  if L.Replaces then
    AddBackLine(L.View, V);
  FLevels.Add(L);
  L.Wnd := MakeWindow(L.Index, L.Replaces);   // one in place of the menu takes the activation over (below)
  SetWindowLongPtr(L.Wnd, GWLP_USERDATA, LONG_PTR(L));

  // where it opens (plan 02 3.7): next to its card, under it (over the lines below), or in place of the menu
  R := Parent.Geometry.Boxes[Box].Rect;
  case Mode of
    smUnder:
      begin
        X := Parent.Pos.X + Round((R.left + 16) * Parent.Scale);
        Y := Parent.Pos.Y + Round((R.bottom - Parent.ScrollY) * Parent.Scale);
      end;
    smReplace:
      begin
        X := Parent.Pos.X;
        Y := Parent.Pos.Y;
      end;
  else
    X := Parent.Pos.X + Round(R.right * Parent.Scale) - 2;
    Y := Parent.Pos.Y + Round((R.top - Parent.ScrollY - OuterPad) * Parent.Scale);
  end;
  SetWindowPos(L.Wnd, 0, X, Y, 1, 1, SWP_NOZORDER or SWP_NOACTIVATE);
  Dpi := GetDpiForWindow(L.Wnd);
  if Dpi = 0 then
    Dpi := 96;
  L.Scale := Dpi / 96 * FTextSize;
  L.Geometry := Measure(L.View, L.Index);
  FitOnScreen(L, X, Y, False, False, Parent.Pos.X + Round(R.left * Parent.Scale) + 2);
  if SelectFirst then
    MoveSelection(L, 1);
  L.Redraw;
  ShowWindow(L.Wnd, SW_SHOWNOACTIVATE);
  L.UpdateShadow;
  if L.Replaces then
  begin
    // hiding the active level would hand the activation outside the menu, and that closes it (WM_ACTIVATE): the
    // level in its place is made active first
    if GetActiveWindow = Parent.Wnd then
      SetActiveWindow(L.Wnd);
    ShowWindow(Parent.Wnd, SW_HIDE);
    Parent.UpdateShadow;
  end;
end;

procedure TMenuSession.MoveSelection(L: TLevelWindow; Delta: Integer);
var
  N, I, Start: Integer;
  V: TViewCard;
begin
  N := Length(L.Geometry.Boxes);
  if N = 0 then
    Exit;
  Start := L.Selected;
  if Start < 0 then
    if Delta > 0 then
      Start := -1
    else
      Start := N;
  I := Start;
  repeat
    I := (I + Delta + N) mod N;
    V := L.Geometry.Boxes[I].Card;
    if (V.Kind <> vkSeparator) and V.Enabled then
    begin
      L.Selected := I;
      L.Geometry.KeyFocus := True;   // chosen by the keys: the focus ring, until the mouse moves from here
      GetCursorPos(FLastMouse);
      // keep the selection in view
      with L.Geometry.Boxes[I].Rect do
      begin
        if top - L.ScrollY < OuterPad then
          L.ScrollY := Max(0, top - OuterPad);
        if bottom - L.ScrollY > L.VisibleHeight - OuterPad then
          L.ScrollY := bottom - L.VisibleHeight + OuterPad;
      end;
      Exit;
    end;
  until I = Start;
end;

procedure TMenuSession.KeyDown(Key: WPARAM);
var
  L: TLevelWindow;
  V: TViewCard;
begin
  L := FLevels.Last;
  V := nil;
  if (L.Selected >= 0) and (L.Selected <= High(L.Geometry.Boxes)) then
    V := L.Geometry.Boxes[L.Selected].Card;
  // the search: Backspace takes a letter off, Esc ends it; a space is typed (WM_CHAR), not a choice
  if FSearch <> '' then
    case Key of
      VK_BACK:
        begin
          Delete(FSearch, Length(FSearch), 1);
          ShowSearch;
          Exit;
        end;
      VK_ESCAPE:
        begin
          FSearch := '';
          ShowSearch;
          Exit;
        end;
      VK_SPACE:
        Exit;
    end;
  case Key of
    VK_DOWN, VK_UP:
      begin
        if Key = VK_DOWN then
          MoveSelection(L, 1)
        else
          MoveSelection(L, -1);
        L.Redraw;
      end;
    VK_HOME, VK_END:
      begin
        L.Selected := -1;
        if Key = VK_HOME then
          MoveSelection(L, 1)
        else
          MoveSelection(L, -1);
        L.Redraw;
      end;
    VK_RIGHT:
      if (V <> nil) and V.HasSubmenu then
        Open(L.Index, L.Selected, True);
    VK_RETURN, VK_SPACE:
      if (V <> nil) and (V.Kind = vkBack) then
        CloseFrom(L.Index)
      else if V <> nil then
        if V.HasSubmenu then
          Open(L.Index, L.Selected, True)
        else
          Choose(V);
    VK_LEFT:
      if L.Index > 0 then
        CloseFrom(L.Index);
    VK_ESCAPE:
      if L.Index > 0 then
        CloseFrom(L.Index)
      else
        Cancel;
    VK_MENU, VK_F10:
      Cancel;
  end;
end;

// The & letter of an item: the character after a single &.
function KeyLetter(V: TViewCard): Char;
var
  T: string;
  I: Integer;
begin
  Result := #0;
  if (V.Kind <> vkItem) or not V.Node.Item.HasText then
    Exit;
  T := V.Node.Item.Text;
  I := 1;
  while I < Length(T) do
  begin
    if T[I] = '&' then
    begin
      if T[I + 1] <> '&' then
        Exit(UpCase(T[I + 1]));
      Inc(I);
    end;
    Inc(I);
  end;
end;

function TMenuSession.IsSearching: Boolean;
begin
  Result := FSearch <> '';
end;

procedure TMenuSession.ShowSearch;
var
  L: TLevelWindow;
  Old: TViewLevel;
begin
  CloseFrom(1);
  HideTip;
  L := FLevels[0];
  Old := L.View;
  if FSearch = '' then
    L.View := FPlacement.TopLevel
  else
    L.View := FPlacement.SearchLevel(FSearch);
  Old.Free;
  L.Geometry := Measure(L.View, 0);
  L.ScrollY := 0;
  L.Selected := -1;
  if FSearch <> '' then
    MoveSelection(L, 1);   // the first hit: Enter runs it
  FitOnScreen(L, L.Pos.X, L.Pos.Y, False, False, L.Pos.X);
  L.Redraw;
end;

procedure TMenuSession.CharKey(Ch: Char);
var
  L: TLevelWindow;
  I, First, Count, Start: Integer;
begin
  // typing into the search already begun
  if FSearch <> '' then
  begin
    FSearch := FSearch + Ch;
    ShowSearch;
    Exit;
  end;
  L := FLevels.Last;
  if Ch = ' ' then
    Exit;
  Ch := UpCase(Ch);
  Count := 0;
  First := -1;
  Start := L.Selected;
  for I := 0 to High(L.Geometry.Boxes) do
    if L.Geometry.Boxes[I].Card.Enabled and (KeyLetter(L.Geometry.Boxes[I].Card) = Ch) then
    begin
      Inc(Count);
      if (First < 0) or ((First <= Start) and (I > Start)) then
        First := I;
    end;
  if First < 0 then
  begin
    // no item of the open level has this access key: the letter starts the search (plan 02 3.6)
    FSearch := Ch;
    ShowSearch;
    Exit;
  end;
  L.Selected := First;
  L.Redraw;
  if Count = 1 then
    if L.Geometry.Boxes[First].Card.HasSubmenu then
      Open(L.Index, First, True)
    else
      Choose(L.Geometry.Boxes[First].Card);
end;

procedure TMenuSession.Changed(Menu: HMENU);
begin
  if FRefreshPosted or (FLevels.Count = 0) or not Owns(Menu) then
    Exit;
  FRefreshPosted := True;
  PostMessage(FLevels[0].Wnd, WM_DEXMENU_REFRESH, 0, 0);
end;

// The Windows submenus of these items that an extension fills only when opened (no items yet) are opened now, as
// Windows' menu does on hover (WM_INITMENUPOPUP), and stay open until the menu closes; one with items is never opened
// early. One that holds nothing even then (Bash's on a DLL): its item is not shown. When the layout's rules look
// inside submenus (FDeep), the levels below are opened too, before the rules run, so a rule with a path or scope
// anywhere finds what the extension puts there (Send to's targets). Each submenu is looked at once per right-click.
procedure TMenuSession.FindEmpty(Nodes: TNodes);
var
  N, C: TNode;
  Index: Integer;
  HasItem: Boolean;
begin
  if Nodes = nil then
    Exit;
  for N in Nodes do
  begin
    if (N.SubMenu = 0) or N.IsSeparator or FChecked.ContainsKey(N.SubMenu) then
      Continue;
    FChecked.Add(N.SubMenu, True);
    if GetMenuItemCount(N.SubMenu) = 0 then
    begin
      Index := 0;
      while (Index < GetMenuItemCount(N.Menu)) and (GetSubMenu(N.Menu, Index) <> N.SubMenu) do
        Inc(Index);
      if Notify then
      begin
        SendMessage(FOwner, WM_INITMENUPOPUP, WPARAM(N.SubMenu), MakeLParam(Index, 0));
        FEarly.Add(N.SubMenu);
      end;
      ReadChildren(N);
      HasItem := False;
      for C in N.Children do
        if not C.IsSeparator and ((C.Name <> '') or (C.SubMenu <> 0)) then
          HasItem := True;
      if not HasItem then
      begin
        FEmpty.AddOrSetValue(N.SubMenu, True);
        if Tracing then
          Log(Format('submenu %s of "%s" empty: not shown', [Hex(N.SubMenu), N.Name]));
      end
      else if Tracing then
        Log(Format('submenu %s of "%s" opened early: %d items', [Hex(N.SubMenu), N.Name, N.Children.Count]));
    end;
    if FDeep then
    begin
      if N.Children = nil then
        ReadChildren(N);
      FindEmpty(N.Children);
    end;
  end;
end;

// The hint of the card under the mouse (ShownHint), after Windows' hover time, just below the card.
procedure TMenuSession.HoverTip(L: TLevelWindow; Box: Integer);
begin
  HideTip;
  FTipLevel := L;
  FTipBox := Box;
  if Box >= 0 then
    SetTimer(L.Wnd, TipTimer, HoverTime, nil);
end;

procedure TMenuSession.ShowTip(L: TLevelWindow);
var
  V: TViewCard;
  R: TD2D1RectF;
  Regular: string;
begin
  KillTimer(L.Wnd, TipTimer);
  if (FTip = nil) or (L <> FTipLevel) or (FTipBox < 0) or (FTipBox > High(L.Geometry.Boxes)) then
    Exit;
  V := L.Geometry.Boxes[FTipBox].Card;
  Regular := '';
  if (V.Kind = vkItem) and (FHints <> nil) then
    FHints.TryGetValue(HintKey(V.Node), Regular);
  R := L.Geometry.Boxes[FTipBox].Rect;
  FTip.Show(ShownHint(V, Regular), L.Pos.X + Round((R.left + 8) * L.Scale),
    L.Pos.Y + Round((R.bottom - L.ScrollY + 2) * L.Scale));
end;

procedure TMenuSession.HideTip;
begin
  if FTipLevel <> nil then
    KillTimer(FTipLevel.Wnd, TipTimer);
  FTipLevel := nil;
  if FTip <> nil then
    FTip.Hide;
end;

// What the menu holds now merged into what it held before in this right-click: an item Windows' menu lost while shown
// (Explorer deletes the items it hides after the show) is kept, marked "sometimes".
procedure TMenuSession.KeepSeen;
var
  Now, Merged: TJSONArray;
begin
  Now := SeenJson(FTop);
  try
    Merged := MergeSeen(FSeen, Now, False);
  finally
    Now.Free;
  end;
  FSeen.Free;
  FSeen := Merged;
end;

// Windows' items read again after a change, every open level placed again; a level whose opener is gone closes.
procedure TMenuSession.Refresh;
var
  NewTop: TNodes;
  NewPlacement: TPlacement;
  I, B: Integer;
  L, Parent: TLevelWindow;
  OldViews: TObjectList<TViewLevel>;
  SelectedId, OpenerId: UINT;
  OpenerCard: TCard;
  OpenerMore: Boolean;   // the opener a holder's "More" (plan 11): not the holder's own card
  V, Found: TViewCard;
  Box: TBox;
begin
  FRefreshPosted := False;
  if FLevels.Count = 0 then
    Exit;
  NewTop := ReadLevel(FOriginal, '');
  FindEmpty(NewTop);
  NewPlacement := TPlacement.Create(FLayout, FKind, NewTop, FUsage, FLastUse);
  NewPlacement.Empty := FEmpty;
  NewPlacement.AtRightClick := True;
  NewPlacement.Usage := FUsage;
  OldViews := TObjectList<TViewLevel>.Create;
  try
    for I := 0 to FLevels.Count - 1 do
    begin
      L := FLevels[I];
      SelectedId := 0;
      if (L.Selected >= 0) and (L.Selected <= High(L.Geometry.Boxes)) and
        (L.Geometry.Boxes[L.Selected].Card.Kind = vkItem) then
        SelectedId := L.Geometry.Boxes[L.Selected].Card.Node.Id;
      OldViews.Add(L.View);
      if I = 0 then
        L.View := NewPlacement.TopLevel
      else
      begin
        // the opener in the new level above, by its id or its layout card
        Parent := FLevels[I - 1];
        OpenerId := 0;
        OpenerCard := nil;
        OpenerMore := L.Opener.IsMore;
        if L.Opener.Kind = vkItem then
          OpenerId := L.Opener.Node.Id
        else
          OpenerCard := L.Opener.Card;
        Found := nil;
        for Box in Parent.Geometry.Boxes do
        begin
          V := Box.Card;
          if ((OpenerCard <> nil) and (V.Kind = vkMenu) and (V.Card.Id = OpenerCard.Id) and (V.IsMore = OpenerMore)) or
            ((OpenerCard = nil) and (V.Kind = vkItem) and (V.Node.Id = OpenerId) and (V.Node.SubMenu <> 0)) then
            Found := V;
        end;
        if Found = nil then
        begin
          L.View := TViewLevel.Create;   // closed below
          L.Opener := nil;
        end
        else
        begin
          L.Opener := Found;
          if Found.Kind = vkMenu then
            L.View := NewPlacement.LevelOf(Found)
          else
          begin
            ReadChildren(Found.Node);
            FindEmpty(Found.Node.Children);
            L.View := NewPlacement.SubmenuLevel(Found.Node);
          end;
          if L.Replaces then
            AddBackLine(L.View, Found);
        end;
      end;
      L.Geometry := Measure(L.View, I);
      L.Selected := -1;
      if SelectedId <> 0 then
        for B := 0 to High(L.Geometry.Boxes) do
          if (L.Geometry.Boxes[B].Card.Kind = vkItem) and (L.Geometry.Boxes[B].Card.Node.Id = SelectedId) then
            L.Selected := B;
      if (I > 0) and (L.Opener = nil) then
      begin
        CloseFrom(I);
        Break;
      end;
    end;
    KeepSeen;
    FPlacement.Free;
    FTop.Free;
    FPlacement := NewPlacement;
    FTop := NewTop;
  finally
    OldViews.Free;
  end;
  for L in FLevels do
  begin
    FitOnScreen(L, L.Pos.X, L.Pos.Y, False, False, L.Pos.X);
    L.ScrollY := Min(L.ScrollY, Max(0, L.Geometry.Height - L.VisibleHeight));
    L.Redraw;
  end;
  if FSearch <> '' then
    ShowSearch;   // the search shown again on the new items
end;

procedure TMenuSession.Dump;
var
  Path, Tmp: string;
  Env: array[0..MAX_PATH] of Char;
  Lines: TStringList;
  L: TLevelWindow;
  B: Integer;
  V: TViewCard;
  R: TD2D1RectF;
  Kind: string;
  Id: UINT;
begin
  if GetEnvironmentVariable('DEXMENU_DUMP', Env, MAX_PATH) = 0 then
    Exit;
  Path := Env;
  Lines := TStringList.Create;
  try
    for L in FLevels do
    begin
      Lines.Add(Format('level %d wnd=%d x=%d y=%d w=%d h=%d scale=%s', [L.Index, NativeUInt(L.Wnd), L.Pos.X, L.Pos.Y,
        Ceil(L.Geometry.Width * L.Scale), Ceil(L.VisibleHeight * L.Scale), FloatToStr(L.Scale)]));
      for B := 0 to High(L.Geometry.Boxes) do
      begin
        V := L.Geometry.Boxes[B].Card;
        R := L.Geometry.Boxes[B].Rect;
        Id := 0;
        case V.Kind of
          vkItem: begin Kind := 'item'; Id := V.Node.Id; end;
          vkMenu: Kind := 'menu';
          vkNote: Kind := 'note';
          vkBack: Kind := 'back';
          vkCommand: Kind := 'command';
          vkGroup: Kind := 'group';
        else
          Kind := 'separator';
        end;
        Lines.Add(Format('card %s id=%u enabled=%d checked=%d default=%d sub=%d selected=%d placed=%s/%d x=%d y=%d text=%s',
          [Kind, Id, Ord(V.Enabled), Ord(V.Checked), Ord(V.IsDefault), Ord(V.HasSubmenu), Ord(B = L.Selected), V.CardId, V.RuleIndex,
          L.Pos.X + Round(((R.left + R.right) / 2) * L.Scale),
          L.Pos.Y + Round(((R.top + R.bottom) / 2 - L.ScrollY) * L.Scale), V.Title]));
      end;
    end;
    Tmp := Path + '.tmp';
    Lines.SaveToFile(Tmp, TEncoding.UTF8);
    MoveFileEx(PChar(Tmp), PChar(Path), MOVEFILE_REPLACE_EXISTING);
  finally
    Lines.Free;
  end;
end;

// ---- the window procedure ------------------------------------------------------------------------------------------

function WndProc(Wnd: HWND; Msg: UINT; WP: WPARAM; LP: LPARAM): LRESULT; stdcall;
var
  L: TLevelWindow;
  S: TMenuSession;
  Box, Delay, I: Integer;
  X, Y: Single;
  TME: TTrackMouseEvent;
  V: TViewCard;
  Moved: TPoint;
begin
  L := LevelOf(Wnd);
  if L = nil then
    Exit(DefWindowProc(Wnd, Msg, WP, LP));
  S := L.Session;
  if S.FDone and (Msg <> WM_PAINT) then
    Exit(DefWindowProc(Wnd, Msg, WP, LP));   // closed (another menu may show inside its loop, Dismiss): no timer, no refresh
  Result := 0;
  case Msg of
    WM_MOUSEACTIVATE:
      Exit(MA_NOACTIVATE);
    WM_MOUSEMOVE:
      begin
        // the mouse really moved: the keys' focus ring goes
        GetCursorPos(Moved);
        if (Moved.X <> S.FLastMouse.X) or (Moved.Y <> S.FLastMouse.Y) then
        begin
          S.FLastMouse := Moved;
          for I := 0 to S.FLevels.Count - 1 do
            if S.FLevels[I].Geometry.KeyFocus then
            begin
              S.FLevels[I].Geometry.KeyFocus := False;
              S.FLevels[I].Redraw;
            end;
        end;
        X := SmallInt(LP and $FFFF) / L.Scale;
        Y := SmallInt((LP shr 16) and $FFFF) / L.Scale;
        Box := BoxAt(L.Geometry, X, Y, L.ScrollY);
        // in a submenu: a change waiting in a level above is off, and the cards that opened it stay selected
        if (S.FHoverTimerLevel >= 0) and (S.FHoverTimerLevel < L.Index) then
        begin
          KillTimer(S.FLevels[S.FHoverTimerLevel].Wnd, HoverTimer);
          S.FHoverTimerLevel := -1;
        end;
        for I := 0 to L.Index - 1 do
          if S.FLevels[I].Selected <> S.FLevels[I].BoxOfCard(S.FLevels[I + 1].Opener) then
          begin
            S.FLevels[I].Selected := S.FLevels[I].BoxOfCard(S.FLevels[I + 1].Opener);
            S.FLevels[I].Redraw;
          end;
        if Box <> L.Selected then
        begin
          L.Selected := Box;
          if Box <> L.Geometry.Pressed then
            L.Geometry.Pressed := -1;   // the button held, moved off the card: no longer pressed
          L.Redraw;
          S.HoverTip(L, Box);
          KillTimer(Wnd, HoverTimer);
          // a submenu opens after the delay, and an open one closes only after it, so the mouse can cross another
          // card on its way to the open submenu
          if (Box >= 0) and ((L.Geometry.Boxes[Box].Card.HasSubmenu and S.OpensOnHover(L.Geometry.Boxes[Box].Card)) or
            (S.FLevels.Count > L.Index + 1)) then
          begin
            Delay := 400;
            SystemParametersInfo(SPI_GETMENUSHOWDELAY, 0, @Delay, 0);
            S.FHoverTimerLevel := L.Index;
            SetTimer(Wnd, HoverTimer, Max(Delay, 1), nil);
          end;
        end;
        TME.cbSize := SizeOf(TME);
        TME.dwFlags := TME_LEAVE;
        TME.hwndTrack := Wnd;
        TME.dwHoverTime := 0;
        TrackMouseEvent(TME);
      end;
    WM_MOUSELEAVE:
      begin
      if L = S.FTipLevel then
        S.HideTip;
      if (S.FLevels.Count <= L.Index + 1) and (L.Selected >= 0) then
      begin
        L.Selected := -1;
        L.Redraw;
      end;
      end;
    WM_TIMER:
      if WP = TipTimer then
        S.ShowTip(L)
      else if WP = HoverTimer then
      begin
        KillTimer(Wnd, HoverTimer);
        S.FHoverTimerLevel := -1;
        if (L.Selected >= 0) and L.Geometry.Boxes[L.Selected].Card.HasSubmenu and
          S.OpensOnHover(L.Geometry.Boxes[L.Selected].Card) then
          S.Open(L.Index, L.Selected, False)
        else if (L.Selected >= 0) and (S.FLevels.Count > L.Index + 1) then
          S.CloseFrom(L.Index + 1);
      end;
    WM_LBUTTONDOWN:
      begin
        // the card under the button drawn pressed until it is let go (plan 03 3.7)
        Box := BoxAt(L.Geometry, SmallInt(LP and $FFFF) / L.Scale, SmallInt((LP shr 16) and $FFFF) / L.Scale, L.ScrollY);
        if (Box >= 0) and L.Geometry.Boxes[Box].Card.Enabled and (L.Geometry.Boxes[Box].Card.Kind <> vkNote) then
        begin
          L.Geometry.Pressed := Box;
          L.Redraw;
        end;
      end;
    WM_LBUTTONUP:
      begin
        if L.Geometry.Pressed >= 0 then
        begin
          L.Geometry.Pressed := -1;
          L.Redraw;
        end;
        X := SmallInt(LP and $FFFF) / L.Scale;
        Y := SmallInt((LP shr 16) and $FFFF) / L.Scale;
        Box := BoxAt(L.Geometry, X, Y, L.ScrollY);
        if Box >= 0 then
        begin
          V := L.Geometry.Boxes[Box].Card;
          if V.Kind = vkBack then
            S.CloseFrom(L.Index)   // "<<": back to the menu this one replaced
          else if V.HasSubmenu and (S.FLevels.Count > L.Index + 1) and (S.FLevels[L.Index + 1].Opener = V) then
            S.CloseFrom(L.Index + 1)   // a click on the card of an open submenu closes it
          else if V.HasSubmenu then
            S.Open(L.Index, Box, False)
          else
            S.Choose(V);
        end;
      end;
    WM_MOUSEWHEEL:
      if WP and MK_CONTROL <> 0 then
        S.ChangeTextSize(SmallInt(WP shr 16))
      else
      begin
        L.ScrollY := Max(0, Min(L.Geometry.Height - L.VisibleHeight,
          L.ScrollY - SmallInt(WP shr 16) / WHEEL_DELTA * ItemHeight * 3));
        L.Redraw;
      end;
    WM_KEYDOWN, WM_SYSKEYDOWN:
      S.KeyDown(WP);
    WM_CHAR:
      if (WP > 32) or ((WP = 32) and S.IsSearching) then
        S.CharKey(Char(WP));
    WM_ACTIVATE:
      if (WP and $FFFF = WA_INACTIVE) and not S.IsOurs(HWND(LP)) then
        S.Cancel;
    WM_CANCELMODE:
      S.Cancel;
    WM_DEXMENU_REFRESH:
      S.Refresh;
  else
    Result := DefWindowProc(Wnd, Msg, WP, LP);
  end;
end;

end.
