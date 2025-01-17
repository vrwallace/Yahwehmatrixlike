unit Unit1;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, UniqueInstance, MultiMon, Winsock,utilwmi,contnrs;

  const
  DISPLAY_DEVICE_ACTIVE = $00000001;
  DISPLAY_DEVICE_MIRRORING_DRIVER = $00000008;

type
  TDisplayDevice = record
    cb: DWORD;
    DeviceName: array[0..31] of Char;
    DeviceString: array[0..127] of Char;
    StateFlags: DWORD;
    DeviceID: array[0..127] of Char;
    DeviceKey: array[0..127] of Char;
  end;

const
  WH_MOUSE_LL = 14;
  WH_KEYBOARD_LL = 13;
  IP_SUCCESS = 0;
  IP_BUF_TOO_SMALL = 11001;
  IP_REQ_TIMED_OUT = 11010;
  TH32CS_SNAPPROCESS = $00000002;
  WM_DISPLAYCHANGE = $007E;

type
  TTextPosition = record
    Char: WideChar;
    X, Y: Integer;
    FallingSpeed: Integer;
  end;

  ICMP_ECHO_REPLY = packed record
    Address: DWORD;
    Status: DWORD;
    RoundTripTime: DWORD;
    DataSize: WORD;
    Reserved: WORD;
    Data: Pointer;
    Options: record
      Ttl: BYTE;
      Tos: BYTE;
      Flags: BYTE;
      OptionsSize: BYTE;
      OptionsData: Pointer;
    end;
  end;
  PICMP_ECHO_REPLY = ^ICMP_ECHO_REPLY;

  { TSystemInfoThread }

  TSystemInfoThread = class(TThread)
  private
    FOwner: TForm;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TForm);
  end;

  { TScreenSaverForm }

  TScreenSaverForm = class(TForm)
    Timer1: TTimer;
    TerminationTimer: TTimer;
    Timer2: TTimer;
    MonitorCountTimer: TTimer;
    UniqueInstance1: TUniqueInstance;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure TerminationTimerTimer(Sender: TObject);
    procedure MonitorCountTimerTimer(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormDestroy(Sender: TObject);
    procedure Timer2Timer(Sender: TObject);
    procedure UniqueInstance1OtherInstance(Sender: TObject;
      ParamCount: Integer; const Parameters: array of String);


  private
    HebrewText: WideString;
    TextStreams: array of array of TTextPosition;
    MouseMoved: Boolean;
    InitialMouseX, InitialMouseY: Integer;
    FormIndex: Integer;
    CpuUtilization: Integer;
    MemoryUtilization: Integer;
    DiskSpace: Int64;
    PrevIdleTime: Int64;
    PrevKernelTime: Int64;
    PrevUserTime: Int64;
    InfoX, InfoY: Integer;
    FTotalPhysicalMemory: Int64;
    FAvailablePhysicalMemory: Int64;
    FUsedDiskSpace: Int64;
    FPingTime: Integer;
    FSystemUptime: Int64;
    InitialMonitorCount: Integer;
    function GetCPUUsage: Integer;
    function GetPingTime(const IPAddress: string): Integer; // Ensure the parameter name matches
    procedure GetSystemInfo;
    function RetrieveSystemTimes(var IdleTime, KernelTime, UserTime: Int64): Boolean;

    procedure InitializeTextStreams;
    procedure UpdateTextPositions;
    procedure CheckMouseMovement(X, Y: Integer);
    procedure HideMouseCursor;
    procedure SetupTerminationTimer;
    procedure UpdateUI;

  protected
    procedure WndProc(var Msg: TMessage); override;
  public
    constructor Create(AOwner: TComponent; AFormIndex: Integer); reintroduce;
  end;

  function GetKernelSystemTimes(var lpIdleTime, lpKernelTime, lpUserTime: TFileTime): BOOL; stdcall; external 'kernel32.dll' name 'GetSystemTimes';
  function IcmpCreateFile: THandle; stdcall; external 'icmp.dll' name 'IcmpCreateFile';
  function IcmpCloseHandle(IcmpHandle: THandle): BOOL; stdcall; external 'icmp.dll' name 'IcmpCloseHandle';
  function IcmpSendEcho(IcmpHandle: THandle; DestinationAddress: DWORD; RequestData: Pointer;
    RequestSize: WORD; RequestOptions: Pointer; ReplyBuffer: Pointer;
    ReplySize: DWORD; Timeout: DWORD): DWORD; stdcall; external 'icmp.dll' name 'IcmpSendEcho';


procedure CreateFormsForAllMonitors;
function FormatUptime(Uptime: Int64): string;
function GetCurrentDateTimeFormatted: string;

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
  InfoTextSpacing = 40; // Vertical spacing between info texts

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
begin
  SetLength(FormsList, Screen.MonitorCount);
  SetLength(ScreenWidths, Screen.MonitorCount);
  SetLength(ScreenHeights, Screen.MonitorCount);

  for I := 0 to Screen.MonitorCount - 1 do
  begin
    MonitorInfo.cbSize := SizeOf(TMonitorInfo);
    GetMonitorInfo(Screen.Monitors[I].Handle, @MonitorInfo);

    ScreenWidths[I] := MonitorInfo.rcMonitor.Right - MonitorInfo.rcMonitor.Left;
    ScreenHeights[I] := MonitorInfo.rcMonitor.Bottom - MonitorInfo.rcMonitor.Top;

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

{ TSystemInfoThread }

constructor TSystemInfoThread.Create(AOwner: TForm);
begin
  inherited Create(True);
  FOwner := AOwner;
  FreeOnTerminate := True;
end;

procedure TSystemInfoThread.Execute;
var
  Form: TScreenSaverForm;
begin
  Form := TScreenSaverForm(FOwner);
  Form.GetSystemInfo;
  Synchronize(@Form.UpdateUI);
end;

constructor TScreenSaverForm.Create(AOwner: TComponent; AFormIndex: Integer);
begin
  inherited Create(AOwner);
  FormIndex := AFormIndex;
  BorderStyle := bsNone;
  WindowState := wsMaximized;
end;

procedure TScreenSaverForm.GetSystemInfo;
var
  MemoryStatus: TMemoryStatus;
  FreeBytesAvailable, TotalNumberOfBytes, TotalNumberOfFreeBytes: Int64;
  CpuUsage: Integer;
  PingTime: Integer;
  TotalPhysicalMemory, AvailablePhysicalMemory: Int64;
  UsedDiskSpace: Int64;
  SystemUptime: Int64;
begin
  // Initialize local variables
  FreeBytesAvailable := 0;
  TotalNumberOfBytes := 0;
  TotalNumberOfFreeBytes := 0;

  // Get CPU utilization
  CpuUsage := GetCPUUsage;
  CpuUtilization := CpuUsage;

  // Get memory utilization
  MemoryStatus.dwLength := SizeOf(MemoryStatus);
  GlobalMemoryStatus(MemoryStatus);
  MemoryUtilization := MemoryStatus.dwMemoryLoad;
  TotalPhysicalMemory := MemoryStatus.dwTotalPhys div (1024 * 1024); // Convert to MB
  AvailablePhysicalMemory := MemoryStatus.dwAvailPhys div (1024 * 1024); // Convert to MB

  // Get disk space
  if GetDiskFreeSpaceEx('C:\', FreeBytesAvailable, TotalNumberOfBytes, @TotalNumberOfFreeBytes) then
  begin
    DiskSpace := TotalNumberOfFreeBytes div (1024 * 1024 * 1024); // Convert to GB
    UsedDiskSpace := (TotalNumberOfBytes - TotalNumberOfFreeBytes) div (1024 * 1024 * 1024); // Convert to GB
  end
  else
  begin
    DiskSpace := 0; // Set to 0 if unable to retrieve disk space
    UsedDiskSpace := 0;
  end;

  // Get ping time
  PingTime := GetPingTime('8.8.8.8');

  // Get system uptime
  SystemUptime := GetTickCount64 div 1000; // Convert to seconds

  // Store the values in class variables for later display
  FTotalPhysicalMemory := TotalPhysicalMemory;
  FAvailablePhysicalMemory := AvailablePhysicalMemory;
  FUsedDiskSpace := UsedDiskSpace;
  FPingTime := PingTime;
  FSystemUptime := SystemUptime;
end;


{function TScreenSaverForm.GetCPUUsage: Integer;
var
  IdleTime, KernelTime, UserTime: Int64;
  SystemTime, Usage: Integer;
begin
  Result := 0;  // Default result
  if RetrieveSystemTimes(IdleTime, KernelTime, UserTime) then
  begin
    SystemTime := (KernelTime + UserTime) - (PrevKernelTime + PrevUserTime);
    if SystemTime <> 0 then
    begin
      Usage := Round(100 - ((IdleTime - PrevIdleTime) / SystemTime) * 100);
      if (Usage > 100) or (Usage < 0) then
      begin
        Result := 0; // Invalid reading
      end
      else
      begin
        Result := Usage;
      end;
    end;
    // Update previous times for next calculation
    PrevIdleTime := IdleTime;
    PrevKernelTime := KernelTime;
    PrevUserTime := UserTime;
  end;
end;}

function TScreenSaverForm.GetCPUUsage: Integer;
var
  IdleTime, KernelTime, UserTime: Int64;
  SystemTime, Usage: Int64;
begin
  Result := 0;  // Default result

  // Ensure PrevIdleTime, PrevKernelTime, and PrevUserTime are initialized
  if (PrevIdleTime = 0) and (PrevKernelTime = 0) and (PrevUserTime = 0) then
  begin
    if RetrieveSystemTimes(IdleTime, KernelTime, UserTime) then
    begin
      PrevIdleTime := IdleTime;
      PrevKernelTime := KernelTime;
      PrevUserTime := UserTime;
    end;
    Exit;  // Exit the function on first call
  end;

  // Check if RetrieveSystemTimes is successful
  if RetrieveSystemTimes(IdleTime, KernelTime, UserTime) then
  begin
    // Calculate the total system time since the last call
    SystemTime := (KernelTime + UserTime) - (PrevKernelTime + PrevUserTime);

    // Diagnostic output
    OutputDebugString(PChar(Format('IdleTime: %d, KernelTime: %d, UserTime: %d', [IdleTime, KernelTime, UserTime])));
    OutputDebugString(PChar(Format('PrevIdleTime: %d, PrevKernelTime: %d, PrevUserTime: %d', [PrevIdleTime, PrevKernelTime, PrevUserTime])));
    OutputDebugString(PChar(Format('SystemTime: %d', [SystemTime])));

    // Avoid division by zero
    if SystemTime > 0 then
    begin
      // Calculate CPU usage
      Usage := 100 - ((IdleTime - PrevIdleTime) * 100 div SystemTime);

      // Diagnostic output
      OutputDebugString(PChar(Format('Calculated Usage: %d', [Usage])));

      // Validate the result
      if (Usage >= 0) and (Usage <= 100) then
      begin
        Result := Usage;
      end;
    end;

    // Update previous times for next calculation
    PrevIdleTime := IdleTime;
    PrevKernelTime := KernelTime;
    PrevUserTime := UserTime;
  end;
end;





   { function TScreenSaverForm.GetCPUUsage: Integer;
var
  WMIResult: TFPObjectList;
  PropNamesCPU: array[0..0] of string = ('PercentProcessorTime');
  UsageStr: string;
  Usage: Integer;
begin
  Result := 0;  // Default result

  try
    // Retrieve CPU usage using WMI
    WMIResult := GetWMIInfo('Win32_PerfFormattedData_PerfOS_Processor', PropNamesCPU, 'WHERE Name="_Total"');
    if WMIResult.Count > 0 then
    begin
      UsageStr := TStringList(WMIResult[0]).Values['PercentProcessorTime'];
      if TryStrToInt(UsageStr, Usage) then
      begin
        Result := Usage;
      end;
    end;

    // Clean up
    WMIResult.Free;

  except
    on E: Exception do
    begin
      // Handle any exceptions
      Result := 0;
    end;
  end;
end;}






function TScreenSaverForm.GetPingTime(const IPAddress: string): Integer;
var
  IcmpHandle: THandle;
  ReplyBuffer: array[0..255] of Byte; // Increased buffer size for safety
  EchoReply: PICMP_ECHO_REPLY;
  IpAddr: DWORD;
  ReplyCount: DWORD;
begin
  Result := -1;  // Default result if ping fails
  IcmpHandle := IcmpCreateFile;
  if IcmpHandle = INVALID_HANDLE_VALUE then
  begin
    //ShowMessage('IcmpCreateFile failed: ' + SysErrorMessage(GetLastError));
    Exit;
  end;

  try
    IpAddr := inet_addr(PAnsiChar(AnsiString(IPAddress)));
    if IpAddr = INADDR_NONE then
    begin
      //ShowMessage('Invalid IP address');
      Exit;
    end;

    // Ensure the reply buffer is correctly set up
    FillChar(ReplyBuffer, SizeOf(ReplyBuffer), 0);
    EchoReply := PICMP_ECHO_REPLY(@ReplyBuffer);
    EchoReply^.DataSize := SizeOf(ReplyBuffer) - SizeOf(ICMP_ECHO_REPLY);
    EchoReply^.Data := @ReplyBuffer[SizeOf(ICMP_ECHO_REPLY)];

    ReplyCount := IcmpSendEcho(IcmpHandle, IpAddr, nil, 0, nil, @ReplyBuffer, SizeOf(ReplyBuffer), 1000);
    if ReplyCount = 0 then
    begin
      //ShowMessage('IcmpSendEcho failed: ' + SysErrorMessage(GetLastError));
      Exit;
    end;

    if EchoReply^.Status = IP_SUCCESS then
      Result := EchoReply^.RoundTripTime
    else
      begin
     // ShowMessage('Ping failed with status: ' + IntToStr(EchoReply^.Status));
        end;
  finally
    IcmpCloseHandle(IcmpHandle);
  end;
end;


function TScreenSaverForm.RetrieveSystemTimes(var IdleTime, KernelTime, UserTime: Int64): Boolean;
var
  IdleTimeFileTime, KernelTimeFileTime, UserTimeFileTime: TFileTime;
begin
  Result := False;
  IdleTime := 0;
  KernelTime := 0;
  UserTime := 0;
  if SysUtils.Win32Platform = VER_PLATFORM_WIN32_NT then
  begin
    if GetKernelSystemTimes(IdleTimeFileTime, KernelTimeFileTime, UserTimeFileTime) then
    begin
      IdleTime := Int64(IdleTimeFileTime.dwLowDateTime) or (Int64(IdleTimeFileTime.dwHighDateTime) shl 32);
      KernelTime := Int64(KernelTimeFileTime.dwLowDateTime) or (Int64(KernelTimeFileTime.dwHighDateTime) shl 32);
      UserTime := Int64(UserTimeFileTime.dwLowDateTime) or (Int64(UserTimeFileTime.dwHighDateTime) shl 32);
      Result := True;
    end;
  end;
end;


procedure TScreenSaverForm.FormCreate(Sender: TObject);
var
  WSAData: TWSAData;
  MousePos: TPoint;
  ParentWnd: HWND;
begin
  // Initialize previous times for CPU usage calculation
  PrevIdleTime := 0;
  PrevKernelTime := 0;
  PrevUserTime := 0;

  // Initialize Winsock
  if WSAStartup(MAKEWORD(2, 2), WSAData) <> 0 then
  begin
    //ShowMessage('WSAStartup failed');
    Application.Terminate;
    Exit;
  end;


  // Retrieve the initial system times
  if not RetrieveSystemTimes(PrevIdleTime, PrevKernelTime, PrevUserTime) then
  begin
    // Handle the error if the initial times cannot be retrieved
    //ShowMessage('Error retrieving initial system times');
    Application.Terminate;
    Exit;
  end;

  InitialMonitorCount := Screen.MonitorCount;
  MonitorCountTimer := TTimer.Create(Self);
  MonitorCountTimer.Interval := 1000; // Check every 1 second
  MonitorCountTimer.OnTimer := @MonitorCountTimerTimer;
  MonitorCountTimer.Enabled := True;
    Color := clBlack;
  // Check for /s parameter to start the screensaver
  if (ParamCount > 0) and (ParamStr(1) = '/s') then
  begin
    uniqueinstance1.Enabled:=true;
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
    Timer2.Enabled := True;
    Timer2.Interval := 10000;
    Timer2Timer(nil);

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
    uniqueinstance1.Enabled:=false;
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
    Timer2.Interval := 10000;
    Timer2.Enabled := True;
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
    uniqueinstance1.Enabled:=false;
    // Terminate the application for configuration parameter
  // Showmessage('This screen saver does not have any configurable settings.');
    Application.Terminate;
  end
  else
  begin
    Application.Terminate;
  end;
end;
 procedure TScreenSaverForm.MonitorCountTimerTimer(Sender: TObject);
var
  I: Integer;
  MonitorCountText: string;
  DisplayDevice: TDisplayDevice;
  ActiveMonitorCount: Integer;
begin
  // Count the number of active monitors
  ActiveMonitorCount := 0;
  ZeroMemory(@DisplayDevice, SizeOf(DisplayDevice));
  DisplayDevice.cb := SizeOf(DisplayDevice);
  I := 0;
  while EnumDisplayDevices(nil, I, @DisplayDevice, 0) do
  begin
    if (DisplayDevice.StateFlags and DISPLAY_DEVICE_ACTIVE <> 0) and
       (DisplayDevice.StateFlags and DISPLAY_DEVICE_MIRRORING_DRIVER = 0) then
    begin
      Inc(ActiveMonitorCount);
    end;
    Inc(I);
  end;

  OutputDebugString(PChar('Active Monitor Count: ' + IntToStr(ActiveMonitorCount)));
  OutputDebugString(PChar('Initial Monitor Count: ' + IntToStr(InitialMonitorCount)));

  if ActiveMonitorCount <> InitialMonitorCount then
  begin
    OutputDebugString('Active monitor count changed. Terminating screen saver.');
    Application.Terminate;
  end;

  // Create the monitor count text
  {MonitorCountText := 'Initial Monitors: ' + IntToStr(InitialMonitorCount) + '  Active Monitors: ' + IntToStr(ActiveMonitorCount);

  // Draw the monitor count text on each screen saver form
  for I := 0 to Length(FormsList) - 1 do
  begin
    with FormsList[I] do
    begin
      Canvas.Font.Color := clLime;
      Canvas.Font.Size := 20;
      Canvas.TextOut(50, 50, MonitorCountText);
    end;
  end; }
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

  // Clean up Winsock
  WSACleanup;
    MonitorCountTimer.Free;
end;

procedure TScreenSaverForm.Timer2Timer(Sender: TObject);
begin
  TSystemInfoThread.Create(Self).Start;
end;

procedure TScreenSaverForm.UniqueInstance1OtherInstance(Sender: TObject;
  ParamCount: Integer; const Parameters: array of String);
begin
  if (ParamCount > 0) and (ParamStr(1) = '/s') then
  begin
    Application.Terminate;
  end;
end;

procedure TScreenSaverForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
  Application.Terminate;
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

procedure TScreenSaverForm.UpdateUI;
var
  MaxInfoX, MaxInfoY: Integer;
  InfoWidth, InfoHeight: Integer;
  TotalInfoHeight: Integer;
  LongestText: string;
  FormattedUptime, CurrentDateTime: string;
begin
  Canvas.Font.Size := 24; // Ensure the font size matches the size used in FormPaint

  // Determine the longest text for calculating box width
  FormattedUptime := FormatUptime(FSystemUptime);
  CurrentDateTime := GetCurrentDateTimeFormatted;
  LongestText := 'Total Physical Memory: 99999 MB';
  if Canvas.TextWidth('System Uptime: ' + FormattedUptime) > Canvas.TextWidth(LongestText) then
    LongestText := 'System Uptime: ' + FormattedUptime;
  if Canvas.TextWidth('Current Date and Time: ' + CurrentDateTime) > Canvas.TextWidth(LongestText) then
    LongestText := 'Current Date and Time: ' + CurrentDateTime;

  // Calculate the approximate width of the longest text line
  InfoWidth := Canvas.TextWidth(LongestText) + 150; // Add more padding for safety
  // Calculate the height of a single line of text
  InfoHeight := Canvas.TextHeight('W');
  // Calculate the total height needed for all text lines with spacing
  TotalInfoHeight := 10 * (InfoHeight + InfoTextSpacing) + 20; // 9 lines of text + 1 line for vonwallace.com + box title + margins

  // Calculate maximum X and Y positions to ensure the text stays within the screen
  MaxInfoX := ScreenWidths[FormIndex] - InfoWidth - 20; // 20 is an arbitrary margin
  MaxInfoY := ScreenHeights[FormIndex] - TotalInfoHeight - 20; // 20 is an arbitrary margin

  // Ensure there's some margin
  InfoX := Random(MaxInfoX + 1);
  InfoY := Random(MaxInfoY + 1);
  Invalidate;
end;







procedure TScreenSaverForm.FormPaint(Sender: TObject);
var
  i, j: Integer;
  InfoHeight, BoxWidth, BoxHeight: Integer;
  InfoRect: TRect;
  FormattedUptime, CurrentDateTime: string;
  LongestText: string;
  FontSize: Integer;
  LineSpacing: Integer;
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

  // Determine the longest text for calculating box width
  FormattedUptime := FormatUptime(FSystemUptime);
  CurrentDateTime := GetCurrentDateTimeFormatted;
  LongestText := 'Total Physical Memory: 99999 MB';
  if Canvas.TextWidth('System Uptime: ' + FormattedUptime) > Canvas.TextWidth(LongestText) then
    LongestText := 'System Uptime: ' + FormattedUptime;
  if Canvas.TextWidth('Current Date and Time: ' + CurrentDateTime) > Canvas.TextWidth(LongestText) then
    LongestText := 'Current Date and Time: ' + CurrentDateTime;

  // Dynamically calculate font size and line spacing based on screen height
  FontSize := Round(ScreenHeights[FormIndex] * 0.03); // Adjust the multiplier as needed
  LineSpacing := Round(FontSize * 0.4); // Adjust the multiplier as needed

  // Ensure the font size and line spacing are within reasonable limits
  if FontSize < 10 then
    FontSize := 10;
  if FontSize > 24 then
    FontSize := 24;
  if LineSpacing < 2 then
    LineSpacing := 2;
  if LineSpacing > 8 then
    LineSpacing := 8;

  Canvas.Font.Size := FontSize;

  // Calculate dimensions of the information box
  InfoHeight := Canvas.TextHeight('W'); // Approximate height of a line of text
  BoxWidth := Canvas.TextWidth(LongestText) + 40;
  BoxHeight := 11 * (InfoHeight + LineSpacing) + 20;

  // Calculate the maximum positions to ensure the box stays within screen bounds
  if InfoX + BoxWidth > ScreenWidths[FormIndex] then
    InfoX := ScreenWidths[FormIndex] - BoxWidth - 20;
  if InfoY + BoxHeight > ScreenHeights[FormIndex] then
    InfoY := ScreenHeights[FormIndex] - BoxHeight - 20;

  // Draw the information box
  InfoRect := Rect(InfoX, InfoY, InfoX + BoxWidth, InfoY + BoxHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := TextColor;
  Canvas.Rectangle(InfoRect);

  // Draw the system information text inside the box
  Canvas.Font.Color := TextColor; // Set text color to white for visibility

  // Set the font to bold for the title
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(InfoX + 10, InfoY + 10, 'System Information');

  // Set the font to normal for the rest of the information
  Canvas.Font.Style := [];
  Canvas.TextOut(InfoX + 10, InfoY + 10 + InfoHeight + LineSpacing, 'CPU Utilization: ' + IntToStr(CpuUtilization) + '%');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 2 * (InfoHeight + LineSpacing), 'Memory Utilization: ' + IntToStr(MemoryUtilization) + '%');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 3 * (InfoHeight + LineSpacing), 'Disk Space Free: ' + IntToStr(DiskSpace) + ' GB');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 4 * (InfoHeight + LineSpacing), 'Disk Space Used: ' + IntToStr(FUsedDiskSpace) + ' GB');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 5 * (InfoHeight + LineSpacing), 'Total Physical Memory: ' + IntToStr(FTotalPhysicalMemory) + ' MB');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 6 * (InfoHeight + LineSpacing), 'Available Physical Memory: ' + IntToStr(FAvailablePhysicalMemory) + ' MB');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 7 * (InfoHeight + LineSpacing), 'Ping Time: ' + IntToStr(FPingTime) + ' ms');
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 8 * (InfoHeight + LineSpacing), 'System Uptime: ' + FormattedUptime);
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 9 * (InfoHeight + LineSpacing), 'Current Date and Time: ' + CurrentDateTime);

  // Set the font to bold for the vonwallace.com text
  Canvas.Font.Style := [fsBold];
  Canvas.TextOut(InfoX + 10, InfoY + 10 + 10 * (InfoHeight + LineSpacing), 'vonwallace.com');
end;










procedure TScreenSaverForm.WndProc(var Msg: TMessage);
begin
  inherited;
  if Msg.Msg = WM_ACTIVATE then
  begin
    SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
    SetForegroundWindow(Handle);
  end;
  //else if Msg.Msg = WM_DISPLAYCHANGE then
  //begin
   // Application.Terminate;
  //end;
end;
function FormatUptime(Uptime: Int64): string;
var
  Days, Hours, Minutes, Seconds: Int64;
begin
  Seconds := Uptime mod 60;
  Uptime := Uptime div 60;
  Minutes := Uptime mod 60;
  Uptime := Uptime div 60;
  Hours := Uptime mod 24;
  Days := Uptime div 24;

  Result := Format('%dd %dh %dm %ds', [Days, Hours, Minutes, Seconds]);
end;
  function GetCurrentDateTimeFormatted: string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
end;

end.



