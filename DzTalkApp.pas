{------------------------------------------------------------------------------
TDzTalkApp component
Developed by Rodrigo Depin� Dalpiaz (digao dalpiaz)
Non visual component to communicate between applications

https://github.com/digao-dalpiaz/DzTalkApp

Please, read the documentation at GitHub link.
------------------------------------------------------------------------------}

{Send Record:
 > DzTalkApp.Send(ID, @Record, SizeOf(Record));

 Receive Record (OnMessage):
 > Record := TRecord(P^);

 Warning: always use "packed record" !!!

 // -------------------------------------------

 Send Double:
 > DzTalkApp.Send(ID, @Dbl, SizeOf(Dbl));

 Receive Double (OnMessage):
 > Dbl := Double(P^);
}

unit DzTalkApp;

interface

uses System.Classes, Winapi.Windows, Winapi.Messages, System.SysUtils;

type
  TOnMessage = procedure(Sender: TObject; From: HWND; ID: Word; P: Pointer; Size: Cardinal;
    var Result: Integer) of object;

  TDzTalkApp = class(TComponent)
  private
    WinHandle: HWND; //Handle of VIRTUAL Window created by component

    FAutoActivate: Boolean; //auto-activate on component Loaded
    FAutoFind: Boolean; //auto-find destination Window on Send
    FMyWindowName: String;
    FDestWindowName: String;
    FSynchronous: Boolean; //stay locked until other app release OnMessage event

    FActive: Boolean;
    FToHandle: HWND; //Destination Window Handle

    FOnMessage: TOnMessage;

    LastFrom: HWND; //last received handle
    LastData: Pointer; //last data pointer
    LastSize: Cardinal; //last size of data
    LastResult: Integer;

    procedure WndProc(var Msg: TMessage);
    procedure Msg_CopyData(var D: TWMCopyData);

    procedure IntEnv(ID: Word; P: Pointer; Size: Cardinal);
    procedure SetMyWindowName(const Value: String);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Enable;
    procedure Disable;

    procedure FindDestWindow;

    procedure Send(ID: Word); overload;
    procedure Send(ID: Word; N: Integer); overload;
    procedure Send(ID: Word; A: AnsiString); overload;
    procedure Send(ID: Word; P: Pointer; Size: Cardinal); overload;
    procedure Send(ID: Word; S: TMemoryStream); overload;

    function AsString: AnsiString; //read received message as String
    function AsInteger: Integer; //read received message as Integer
    procedure AsStream(Stm: TStream); //read received message as Stream

    property Active: Boolean read FActive;
    property ToHandle: HWND read FToHandle write FToHandle;

    function GetResult: Integer;
  published
    property AutoActivate: Boolean read FAutoActivate write FAutoActivate default False;
    property AutoFind: Boolean read FAutoFind write FAutoFind default False;
    property MyWindowName: String read FMyWindowName write SetMyWindowName;
    property DestWindowName: String read FDestWindowName write FDestWindowName;
    property Synchronous: Boolean read FSynchronous write FSynchronous default False;

    property OnMessage: TOnMessage read FOnMessage write FOnMessage;
  end;

  EDzTalkAppWndNotFound = class(Exception);

procedure Register;

implementation

uses Vcl.Forms;

procedure Register;
begin
  RegisterComponents('Digao', [TDzTalkApp]);
end;

const CONST_WM = WM_COPYDATA; {!}

constructor TDzTalkApp.Create(AOwner: TComponent);
begin
  inherited;

  FActive := False;
end;

destructor TDzTalkApp.Destroy;
begin
  if FActive then Disable;

  inherited;
end;

procedure TDzTalkApp.Loaded;
begin
  inherited;

  if not (csDesigning in ComponentState) then
    if FAutoActivate then Enable;
end;

procedure TDzTalkApp.Enable;
begin
  if FActive then
    raise Exception.Create('TalkApp already active');

  if FMyWindowName='' then
    raise Exception.Create('Window name is blank');

  WinHandle := AllocateHWND(WndProc);
  SetWindowText(WinHandle, PChar(FMyWindowName));

  FActive := True;
end;

procedure TDzTalkApp.Disable;
begin
  if not FActive then
    raise Exception.Create('TalkApp is not active');

  DeallocateHWnd(WinHandle);

  FActive := False;
end;

procedure TDzTalkApp.SetMyWindowName(const Value: String);
begin
  if Value<>FMyWindowName then
  begin
    if FActive then
      raise Exception.Create('Can''t change window name while handle is active');

    FMyWindowName := Value;
  end;
end;

procedure TDzTalkApp.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = CONST_WM then //CopyData message
  begin
    if not FSynchronous then ReplyMessage(Msg.Result);

    try
      Msg_CopyData( TWMCopyData(Msg) );
    except
      Application.HandleException(Self);
    end;

    //Msg.Result := 0;
  end
    else
      Msg.Result := DefWindowProc(WinHandle, Msg.Msg, Msg.WParam, Msg.LParam);
end;

procedure TDzTalkApp.Msg_CopyData(var D: TWMCopyData);
var Res: Integer;
begin
  LastFrom := D.From;
  LastData := D.CopyDataStruct.lpData;
  LastSize := D.CopyDataStruct.cbData;

  Res := 0;
  if Assigned(FOnMessage) then
    FOnMessage(Self, D.From,
      D.CopyDataStruct.dwData, D.CopyDataStruct.lpData, D.CopyDataStruct.cbData, Res);

  D.Result := Res;
end;

procedure TDzTalkApp.IntEnv(ID: Word; P: Pointer; Size: Cardinal);
var D: TCopyDataStruct;
begin
  D.dwData := ID;
  D.cbData := Size;
  D.lpData := P;

  LastResult :=
    SendMessage(FToHandle, CONST_WM, WinHandle, Integer(@D));
end;

procedure TDzTalkApp.Send(ID: Word);
begin
  Send(ID, nil, 0);
end;

procedure TDzTalkApp.Send(ID: Word; N: Integer);
begin
  Send(ID, @N, SizeOf(N));
end;

procedure TDzTalkApp.Send(ID: Word; A: AnsiString);
begin
  Send(ID, PAnsiChar(A), Length(A)+1);
end;

procedure TDzTalkApp.Send(ID: Word; S: TMemoryStream);
begin
  Send(ID, S.Memory, S.Size);
end;

procedure TDzTalkApp.Send(ID: Word; P: Pointer; Size: Cardinal);
begin
  if not FActive then
    raise Exception.Create('TalkApp is not active to send');

  if FAutoFind then FindDestWindow;

  IntEnv(ID, P, Size);
end;

procedure TDzTalkApp.FindDestWindow;
var H: HWND;
begin
  if FDestWindowName='' then
    raise Exception.Create('Destination window name is blank');

  H := FindWindow(nil, PChar(FDestWindowName));

  if H<>0 then
    FToHandle := H
  else
    raise EDzTalkAppWndNotFound.Create('Destination app window not found');
end;

function TDzTalkApp.AsString: AnsiString;
begin
  Result := PAnsiChar(LastData);
end;

function TDzTalkApp.AsInteger: Integer;
begin
  Result := Integer(LastData^);
end;

procedure TDzTalkApp.AsStream(Stm: TStream);
begin
  Stm.Write(LastData^, LastSize);
end;

function TDzTalkApp.GetResult: Integer;
begin
  Result := LastResult;
end;

end.
