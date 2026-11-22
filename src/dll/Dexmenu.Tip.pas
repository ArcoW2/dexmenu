unit Dexmenu.Tip;

// The hint shown on hover over a card (a card's "hint", or the item's own hint: Dexmenu.Place.ShownHint), in Windows'
// own tooltip control, placed by Dexmenu at the card (a tracking tooltip). Used by the menu (Dexmenu.Menu) and the
// preview (Dexmenu.Preview). The delay before it shows is Windows' hover time.

interface

uses
  Winapi.Windows;

type
  TTip = class
  private
    FWnd: HWND;
    FOwner: HWND;
    FText: string;
    FShown: Boolean;
    procedure Ensure;
  public
    constructor Create(Owner: HWND);
    destructor Destroy; override;
    // Shown with its top left at a screen point (pixels); '' hides it.
    procedure Show(const Text: string; X, Y: Integer);
    procedure Hide;
  end;

// Windows' hover time (ms): the delay before a hint shows.
function HoverTime: UINT;

implementation

uses
  Winapi.Messages, Winapi.CommCtrl;

const
  SPI_GETMOUSEHOVERTIME = $0066;

function HoverTime: UINT;
begin
  Result := 400;
  SystemParametersInfo(SPI_GETMOUSEHOVERTIME, 0, @Result, 0);
end;

constructor TTip.Create(Owner: HWND);
begin
  inherited Create;
  FOwner := Owner;
end;

destructor TTip.Destroy;
begin
  if (FWnd <> 0) and IsWindow(FWnd) then   // gone already when its owner went
    DestroyWindow(FWnd);
  inherited;
end;

function ToolInfo(Owner: HWND; Text: PChar): TToolInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.cbSize := SizeOf(Result);
  Result.uFlags := TTF_TRACK or TTF_ABSOLUTE;
  Result.hwnd := Owner;
  Result.uId := 1;
  Result.lpszText := Text;
end;

procedure TTip.Ensure;
var
  Icc: TInitCommonControlsEx;
  Info: TToolInfo;
begin
  if FWnd <> 0 then
    Exit;
  Icc.dwSize := SizeOf(Icc);
  Icc.dwICC := ICC_WIN95_CLASSES;
  InitCommonControlsEx(Icc);
  FWnd := CreateWindowEx(WS_EX_TOPMOST or WS_EX_TOOLWINDOW, TOOLTIPS_CLASS, nil, WS_POPUP or TTS_NOPREFIX or TTS_ALWAYSTIP,
    0, 0, 0, 0, FOwner, 0, HInstance, nil);
  if FWnd = 0 then
    Exit;
  Info := ToolInfo(FOwner, PChar(''));
  SendMessage(FWnd, TTM_ADDTOOL, 0, LPARAM(@Info));
  SendMessage(FWnd, TTM_SETMAXTIPWIDTH, 0, 420);   // long hints wrap
end;

procedure TTip.Show(const Text: string; X, Y: Integer);
var
  Info: TToolInfo;
begin
  if Text = '' then
  begin
    Hide;
    Exit;
  end;
  Ensure;
  if FWnd = 0 then
    Exit;
  FText := Text;
  Info := ToolInfo(FOwner, PChar(FText));
  SendMessage(FWnd, TTM_UPDATETIPTEXT, 0, LPARAM(@Info));
  SendMessage(FWnd, TTM_TRACKPOSITION, 0, MakeLParam(Word(SmallInt(X)), Word(SmallInt(Y))));
  SendMessage(FWnd, TTM_TRACKACTIVATE, 1, LPARAM(@Info));
  SetWindowPos(FWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  FShown := True;
end;

procedure TTip.Hide;
var
  Info: TToolInfo;
begin
  if (FWnd = 0) or not FShown then
    Exit;
  Info := ToolInfo(FOwner, nil);
  SendMessage(FWnd, TTM_TRACKACTIVATE, 0, LPARAM(@Info));
  FShown := False;
end;

end.
