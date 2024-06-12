unit Utilwmi;

{$MODE OBJFPC}{$H+}{$HINTS ON}

{$IF FPC_FULLVERSION > 29999}  // FPC > 2.9.9
  {$INFO "Use new WMI"}
{$ELSE}
  {$INFO "Use old WMI"}
  {$DEFINE USE_OLD_WMI}
{$ENDIF}

// Enable this define if wanting to use ShowMessage() to inform about an
// exception.
// Please realize that using unit Dialogs can 'clash', as both Freevision and
// lazarus have a unit with the same name.
{$DEFINE USE_DIALOG}

interface

uses
  Classes,
  contnrs;

function GetWMIInfo(
  const WMIClass: String;
  const WMIPropertyNames: Array of String;
  const Condition: String = ''
): TFPObjectList;

implementation

uses
  {$IFDEF USE_DIALOG}
  Dialogs,
  {$ENDIF}
  Variants,
  ActiveX,
  ComObj,
  SysUtils;

function VarArrayToStr(Value: Variant): String;
var
  i: Integer;
begin
  Result := '[';
  for i := VarArrayLowBound(Value, 1) to VarArrayHighBound(Value, 1) do
  begin
    if Result <> '[' then Result := Result + ',';
    if not VarIsNull(Value[i]) then
    begin
      if VarIsArray(Value[i]) then
        Result := Result + VarArrayToStr(Value[i])
      else
        Result := Result + VarToStr(Value[i])
    end
    else
      Result := Result + '<null>';
  end;
  Result := Result + ']';
end;

function GetWMIInfo(const WMIClass: string; const WMIPropertyNames: Array of String;
  const Condition: string = ''): TFPObjectList;
const
  wbemFlagForwardOnly = $00000020;
var
  FSWbemLocator: Variant;
  objWMIService: Variant;
  colWMI: Variant;
  oEnumWMI: IEnumvariant;
  nrValue: LongWord;
  {$IFDEF USE_OLD_WMI}
  objWMI: Variant;                     // FPC < 3.0 requires WMIobj to be an variant, not an OleVariant
  nr: PLongWord;                       // FPC < 3.0 requires IEnumvariant.next to supply a pointer to a longword for # returned values
  {$ELSE}
  objWMI: OLEVariant;                  // FPC 3.0 requires WMIobj to be an olevariant, not a variant
  nr: LongWord absolute nrValue;       // FPC 3.0 requires IEnumvariant.next to supply a longword variable for # returned values
  {$ENDIF}
  WMIproperties: String;
  WMIProp: TStringList;
  Request: String;
  PropertyName: String;
  PropertyStrVal: String;
  i: integer;
begin
  {$IFDEF USE_OLD_WMI}
  nr := @nrValue;
  {$ENDIF}
  // Prepare the search query
  WMIProperties := '';
  for i := low(WMIPropertyNames) to High(WMIPropertyNames) do
    WMIProperties := WMIProperties + WMIPropertyNames[i] + ',';
  Delete(WMIProperties, length(WMIProperties), 1);
  // Let FPObjectList take care of freeing the objects
  Result := TFPObjectList.Create(True);
  try
    CoInitialize(nil);
    try
      FSWbemLocator := CreateOleObject('WbemScripting.SWbemLocator');
      objWMIService := FSWbemLocator.ConnectServer('localhost', 'root\CIMV2', '', '');
      if Condition = '' then
        Request := Format('SELECT %s FROM %s', [WMIProperties, WMIClass])
      else
        Request := Format('SELECT %s FROM %s %s', [WMIProperties, WMIClass, Condition]);
      // Start Request
      colWMI := objWMIService.ExecQuery(WideString(Request), 'WQL', wbemFlagForwardOnly);
      // Enum for requested results
      oEnumWMI := IUnknown(colWMI._NewEnum) as IEnumVariant;
      // Enumerate results from query, one by one
      while oEnumWMI.Next(1, objWMI, nr) = 0 do
      begin
        // Store all property name/value pairs for this enum to TStringList.
        WMIProp := TStringList.Create;
        for i := low(WMIPropertyNames) to High(WMIPropertyNames) do
        begin
          PropertyName := WMIPropertyNames[i];
          If not VarIsNull(objWMI.Properties_.Item(WideString(PropertyName)).value) then
          begin
            if VarIsArray(objWMI.Properties_.Item(WideString(PropertyName)).value) then
              PropertyStrVal := VarArrayToStr(objWMI.Properties_.Item(WideString(PropertyName)).value)
            else
              PropertyStrVal := VarToStr(objWMI.Properties_.Item(WideString(PropertyName)).value)
          end
          else
            PropertyStrVal := '<null>';
          WMIProp.Add(PropertyName + '=' + PropertyStrVal);
        end;
        // Add properties from this enum to FPObjectList as TStringList
        Result.Add(WMIProp);
      end;
    finally
      CoUninitialize;
    end;
  except
    {$IFDEF USE_DIALOG}
    on e: Exception do
      ShowMessage('Error WMI with ' + Request + #13#10 + 'Error: ' + e.Message);
    {$ELSE}
    // Replace Raise with more appropriate exception if wanted.
    on e: Exception do Raise;
    {$ENDIF}
  end;
end;

end.

