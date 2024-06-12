program Project1;

uses
  Forms, Interfaces,
  Unit1 in 'Unit1.pas' {ScreenSaverForm};

{$R *.res}

begin
  Application.Title:='jscreen';
  Application.Scaled:=True;
  Application.Initialize;
  Application.MainFormOnTaskbar := False;
  CreateFormsForAllMonitors;
  Application.Run;
end.
