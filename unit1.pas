unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, UniqueInstance, MultiMon;

const
  WH_MOUSE_LL = 14;
  WH_KEYBOARD_LL = 13;

type
  TTextPosition = record
    Char: WideChar;
    X, Y: Integer;
    FallingSpeed: Integer;
  end;

  { TScreenSaverForm }

  TScreenSaverForm = class(TForm)
    Timer1: TTimer;
    TerminationTimer: TTimer;
    UniqueInstance1: TUniqueInstance;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure TerminationTimerTimer(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormDestroy(Sender: TObject);
    procedure UniqueInstance1OtherInstance(Sender: TObject;
      ParamCount: Integer; const Parameters: array of String);
  private
    HebrewText: WideString;
    TextStreams: array of array of TTextPosition;
    MouseMoved: Boolean;
    InitialMouseX, InitialMouseY: Integer;
    FormIndex: Integer;
    procedure InitializeTextStreams;
    procedure UpdateTextPositions;
    procedure CheckMouseMovement(X, Y: Integer);
    procedure HideMouseCursor;
    procedure SetupTerminationTimer;
  protected
    procedure WndProc(var Msg: TMessage); override;
  public
    constructor Create(AOwner: TComponent; AFormIndex: Integer); reintroduce;
    { Public declarations }
  end;

procedure CreateFormsForAllMonitors;

var
  FormsList: array of TScreenSaverForm;
  ScreenWidths, ScreenHeights: array of Integer;
  hMouseHook: HHOOK;
  hKeyboardHook: HHOOK;

implementation

{$R *.lfm}

const
  BaseFallSpeed = 5;
  TextColor = TColor($00FF00); // Lime green color
  NumStreams = 30; // Number of text streams
  MouseSensitivity = 10; // Sensitivity threshold for mouse movement (in pixels)

function MouseHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if (nCode >= 0) and ((wParam = WM_MOUSEMOVE) or (wParam = WM_LBUTTONDOWN) or (wParam = WM_RBUTTONDOWN) or (wParam = WM_MBUTTONDOWN) or (wParam = WM_XBUTTONDOWN)) then
  begin
    Application.Terminate;
  end;
  Result := CallNextHookEx(hMouseHook, nCode, wParam, lParam);
end;

function KeyboardHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if (nCode >= 0) and ((wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN)) then
  begin
    Application.Terminate;
  end;
  Result := CallNextHookEx(hKeyboardHook, nCode, wParam, lParam);
end;

procedure CreateFormsForAllMonitors;
var
  I: Integer;
  MonitorInfo: TMonitorInfo;
  Form: TScreenSaverForm;
  dm: TDeviceMode;
  dd: TDisplayDevice;
begin
  SetLength(FormsList, Screen.MonitorCount);
  SetLength(ScreenWidths, Screen.MonitorCount);
  SetLength(ScreenHeights, Screen.MonitorCount);

  for I := 0 to Screen.MonitorCount - 1 do
  begin
    MonitorInfo.cbSize := SizeOf(TMonitorInfo);
    GetMonitorInfo(Screen.Monitors[I].Handle, @MonitorInfo);

    ZeroMemory(@dd, SizeOf(dd));
    dd.cb := SizeOf(dd);
    EnumDisplayDevices(nil, I, @dd, 0);

    // Get display settings for the monitor
    ZeroMemory(@dm, SizeOf(dm));
    dm.dmSize := SizeOf(dm);
    if EnumDisplaySettings(dd.DeviceName, ENUM_CURRENT_SETTINGS, @dm) then
    begin
      ScreenWidths[I] := dm.dmPelsWidth;
      ScreenHeights[I] := dm.dmPelsHeight;

      // Debugging output to verify dimensions
      OutputDebugString(PChar(Format('Monitor %d: Width=%d, Height=%d', [I, ScreenWidths[I], ScreenHeights[I]])));

      Form := TScreenSaverForm.Create(Application, I);
      Form.Left := MonitorInfo.rcMonitor.Left;
      Form.Top := MonitorInfo.rcMonitor.Top;
      Form.Width := ScreenWidths[I];
      Form.Height := ScreenHeights[I];

      FormsList[I] := Form;
      Form.Show;
    end;
  end;
end;

constructor TScreenSaverForm.Create(AOwner: TComponent; AFormIndex: Integer);
begin
  inherited Create(AOwner);
  FormIndex := AFormIndex;
  BorderStyle := bsNone;
  WindowState := wsMaximized;
end;

procedure TScreenSaverForm.FormCreate(Sender: TObject);
var
  MousePos: TPoint;
  ParentWnd: HWND;
begin
  // Check for /s parameter to start the screensaver
  if (ParamCount > 0) and (ParamStr(1) = '/s') then
  begin
    // Hide the mouse cursor
    HideMouseCursor;

    // Load Hebrew-supporting font
    Font.Charset := HEBREW_CHARSET;
    Font.Name := 'Tahoma'; // Tahoma supports Hebrew characters
    Font.Size := 24; // Set a reasonable font size

    // Initialize text streams
    Randomize;
    HebrewText := WideString(#$05D9#$05E9#$05D5#$05E2); // Unicode values for י, ש, ו, ע
    InitializeTextStreams;

    // Set up timer and form properties
    Timer1.Interval := 30;
    Timer1.Enabled := True;
    ControlStyle := ControlStyle + [csOpaque]; // For flicker reduction

    // Get the initial mouse position
    GetCursorPos(MousePos);
    InitialMouseX := MousePos.X;
    InitialMouseY := MousePos.Y;

    // Set the form background color
    Color := clBlack;

    // Initial paint (to display the initial text)
    Invalidate;
    BringToFront; // Ensure form is on top

    // Set global hooks
    hMouseHook := SetWindowsHookEx(WH_MOUSE_LL, @MouseHookProc, HInstance, 0);
    hKeyboardHook := SetWindowsHookEx(WH_KEYBOARD_LL, @KeyboardHookProc, HInstance, 0);

    // Ensure the form is on top of everything
    SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
    SetForegroundWindow(Handle);
  end
  else if (ParamCount > 1) and (ParamStr(1) = '/p') then
  begin
    // Preview mode using specified window handle
    ParentWnd := StrToInt(ParamStr(2));
    windows.SetParent(Handle, ParentWnd);

    // Adjust form style for preview
    BorderStyle := bsNone;
    Align := alClient;

    // Initialize text streams
    Randomize;
    HebrewText := WideString(#$05D9#$05E9#$05D5#$05E2); // Unicode values for י, ש, ו, ע
    InitializeTextStreams;

    // Set up timer and form properties
    Timer1.Interval := 30;
    Timer1.Enabled := True;
    ControlStyle := ControlStyle + [csOpaque]; // For flicker reduction

    // Set the form background color
    Color := clBlack;

    // Initial paint (to display the initial text)
    Invalidate;
    BringToFront; // Ensure form is on top

    // Check for /p parameter and set up termination timer
    SetupTerminationTimer;
  end
  else if (ParamCount > 0) and (ParamStr(1) = '/c') then
  begin
    // Terminate the application for configuration parameter
    Application.Terminate;
  end
  else
  begin
    Application.Terminate;
  end;
end;





procedure TScreenSaverForm.SetupTerminationTimer;
begin
  TerminationTimer := TTimer.Create(Self);
  TerminationTimer.Interval := 10000; // 10 seconds
  TerminationTimer.OnTimer := @TerminationTimerTimer;
  TerminationTimer.Enabled := True;
end;

procedure TScreenSaverForm.TerminationTimerTimer(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TScreenSaverForm.FormDestroy(Sender: TObject);
begin
  if hMouseHook <> 0 then
    UnhookWindowsHookEx(hMouseHook);
  if hKeyboardHook <> 0 then
    UnhookWindowsHookEx(hKeyboardHook);
end;

procedure TScreenSaverForm.UniqueInstance1OtherInstance(Sender: TObject;
  ParamCount: Integer; const Parameters: array of String);
begin
  Application.Terminate;
end;

procedure TScreenSaverForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
  if (ParamCount > 0) and (ParamStr(1) = '/s') then
  begin
    Application.Terminate;
end;

end;

procedure TScreenSaverForm.FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  Application.Terminate;
end;

procedure TScreenSaverForm.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  CheckMouseMovement(X, Y);
end;

procedure TScreenSaverForm.CheckMouseMovement(X, Y: Integer);
var
  CurrentMousePos: TPoint;
begin
  GetCursorPos(CurrentMousePos);
  if (Abs(CurrentMousePos.X - InitialMouseX) > MouseSensitivity) or
     (Abs(CurrentMousePos.Y - InitialMouseY) > MouseSensitivity) then
  begin
    if not MouseMoved then
    begin
      MouseMoved := True;
      Application.Terminate;
    end;
  end;
end;

procedure TScreenSaverForm.HideMouseCursor;
begin
  ShowCursor(False);
end;

procedure TScreenSaverForm.InitializeTextStreams;
var
  i, j: Integer;
begin
  SetLength(TextStreams, NumStreams);
  for i := 0 to High(TextStreams) do
  begin
    SetLength(TextStreams[i], Length(HebrewText));
    for j := 0 to High(TextStreams[i]) do
    begin
      TextStreams[i][j].Char := HebrewText[j + 1];
      // Adjust X position to ensure characters are fully visible
      TextStreams[i][j].X := Random(ScreenWidths[FormIndex] - Canvas.TextWidth(HebrewText[j + 1]));
      TextStreams[i][j].Y := -Random(ScreenHeights[FormIndex]); // Random Y position above the screen
      TextStreams[i][j].FallingSpeed := BaseFallSpeed + Random(3);
    end;
  end;
end;
  procedure TScreenSaverForm.UpdateTextPositions;
var
  i, j: Integer;
begin
  for i := 0 to High(TextStreams) do
  begin
    for j := 0 to High(TextStreams[i]) do
    begin
      // Update the Y position by adding the falling speed
      TextStreams[i][j].Y := TextStreams[i][j].Y + TextStreams[i][j].FallingSpeed;

      // If the character goes below the screen height, reset its position
      if TextStreams[i][j].Y > ScreenHeights[FormIndex] then
      begin
        // Set a new random X position within the screen width, accounting for character width
        TextStreams[i][j].X := Random(ScreenWidths[FormIndex] - Canvas.TextWidth(TextStreams[i][j].Char));
        // Reset the Y position to start above the screen
        TextStreams[i][j].Y := -Random(100); // Reset Y position above the screen by up to 100 pixels
      end;
    end;
  end;
end;

procedure TScreenSaverForm.Timer1Timer(Sender: TObject);
begin
  UpdateTextPositions;
  Invalidate;
end;

procedure TScreenSaverForm.FormPaint(Sender: TObject);
var
  i, j: Integer;
begin
  // Set the background mode to transparent
  SetBkMode(Canvas.Handle, TRANSPARENT);

  // Draw the falling text
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := TextColor; // Set falling text color to lime green

  for i := 0 to High(TextStreams) do
  begin
    for j := 0 to High(TextStreams[i]) do
    begin
      Canvas.TextOut(TextStreams[i][j].X, TextStreams[i][j].Y, TextStreams[i][j].Char);
    end;
  end;
end;

procedure TScreenSaverForm.WndProc(var Msg: TMessage);
begin
  inherited;
  if Msg.Msg = WM_ACTIVATE then
  begin
    SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
    SetForegroundWindow(Handle);
  end;
end;

end.




