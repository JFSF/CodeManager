unit CM.Watcher;

{ Vigia de uma pasta (e subpastas) com ReadDirectoryChangesW, numa thread propria.
  A thread so regista os caminhos alterados (relativos, com '/') e avisa a thread principal com um
  sinal; quem usa chama TakeChanges quando quiser (normalmente depois de uma pequena espera, porque
  o IDE grava um ficheiro varias vezes seguidas). Nao le nem analisa ficheiros. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections, Winapi.Windows;

type
  TFolderWatcher = class(TThread)
  private
    FRoot: string;
    FLock: TCriticalSection;
    FPending: THashSet<string>;
    FOverflow: Boolean;
    FSignaled: Boolean;
    FStop: THandle;
    FOnSignal: TNotifyEvent;
    procedure AddChange(const ARel: string);
    procedure RaiseOverflow;
    procedure Signal;
    procedure ParseBuffer(ABuffer: Pointer);
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: string; AOnSignal: TNotifyEvent);
    destructor Destroy; override;
    // devolve (e esquece) o que mudou desde a ultima chamada; AOverflow = houve perda de
    // eventos e convem comparar a pasta inteira
    procedure TakeChanges(out APaths: TArray<string>; out AOverflow: Boolean);
  end;

implementation

type
  // FILE_NOTIFY_INFORMATION
  PNotifyInfo = ^TNotifyInfo;
  TNotifyInfo = record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

const
  BufferSize = 64 * 1024;
  NotifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
    FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_SIZE;

constructor TFolderWatcher.Create(const ARoot: string; AOnSignal: TNotifyEvent);
begin
  FRoot := ExcludeTrailingPathDelimiter(ARoot);
  FOnSignal := AOnSignal;
  FLock := TCriticalSection.Create;
  FPending := THashSet<string>.Create;
  FStop := CreateEvent(nil, True, False, nil);
  inherited Create(False);
end;

destructor TFolderWatcher.Destroy;
begin
  Terminate;
  SetEvent(FStop);
  WaitFor;
  // sinais ainda na fila da thread principal nao podem correr depois de o objecto morrer
  TThread.RemoveQueuedEvents(Self);
  CloseHandle(FStop);
  FPending.Free;
  FLock.Free;
  inherited;
end;

procedure TFolderWatcher.Signal;
var
  Need: Boolean;
begin
  FLock.Enter;
  try
    Need := not FSignaled;
    FSignaled := True;
  finally
    FLock.Leave;
  end;
  if Need then
    TThread.Queue(Self,
      procedure
      begin
        if Assigned(FOnSignal) then
          FOnSignal(Self);
      end);
end;

procedure TFolderWatcher.AddChange(const ARel: string);
begin
  FLock.Enter;
  try
    FPending.Add(ARel.Replace('\', '/'));
  finally
    FLock.Leave;
  end;
end;

procedure TFolderWatcher.RaiseOverflow;
begin
  FLock.Enter;
  try
    FOverflow := True;
  finally
    FLock.Leave;
  end;
end;

procedure TFolderWatcher.ParseBuffer(ABuffer: Pointer);
var
  P: PByte;
  Info: PNotifyInfo;
  Name: string;
begin
  P := ABuffer;
  while True do
  begin
    Info := PNotifyInfo(P);
    SetString(Name, PWideChar(@Info^.FileName), Info^.FileNameLength div SizeOf(WideChar));
    if Name <> '' then
      AddChange(Name);
    if Info^.NextEntryOffset = 0 then
      Break;
    Inc(P, Info^.NextEntryOffset);
  end;
end;

procedure TFolderWatcher.Execute;
var
  Dir, Ev: THandle;
  Buffer: array of DWORD;      // DWORD para o alinhamento que a API exige
  Ov: TOverlapped;
  Bytes: DWORD;
  Handles: array[0..1] of THandle;
begin
  Dir := CreateFile(PChar(FRoot), FILE_LIST_DIRECTORY,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if Dir = INVALID_HANDLE_VALUE then
    Exit;
  Ev := CreateEvent(nil, True, False, nil);
  SetLength(Buffer, BufferSize div SizeOf(DWORD));
  try
    while not Terminated do
    begin
      FillChar(Ov, SizeOf(Ov), 0);
      Ov.hEvent := Ev;
      ResetEvent(Ev);
      Bytes := 0;
      if not ReadDirectoryChangesW(Dir, @Buffer[0], BufferSize, True, NotifyFilter, @Bytes, @Ov, nil) then
        Break;
      Handles[0] := Ev;
      Handles[1] := FStop;
      if WaitForMultipleObjects(2, @Handles[0], False, INFINITE) = WAIT_OBJECT_0 then
      begin
        if not GetOverlappedResult(Dir, Ov, Bytes, False) then
          Break;
        if Bytes = 0 then
          RaiseOverflow            // o buffer encheu: perderam-se eventos
        else
          ParseBuffer(@Buffer[0]);
        Signal;
      end
      else
      begin
        CancelIo(Dir);
        GetOverlappedResult(Dir, Ov, Bytes, True);   // espera o fim antes de largar o buffer
        Break;
      end;
    end;
  finally
    CloseHandle(Ev);
    CloseHandle(Dir);
  end;
end;

procedure TFolderWatcher.TakeChanges(out APaths: TArray<string>; out AOverflow: Boolean);
begin
  FLock.Enter;
  try
    APaths := FPending.ToArray;
    FPending.Clear;
    AOverflow := FOverflow;
    FOverflow := False;
    FSignaled := False;
  finally
    FLock.Leave;
  end;
end;

end.
