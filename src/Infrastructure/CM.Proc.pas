unit CM.Proc;

{ Corre um programa da linha de comandos sem janela e le o que ele escreve (saida e erros, em UTF-8).
  Serve as integracoes com o Git, o Subversion e o Mercurial, que so leem. Nunca espera mais do que o
  tempo dado: passado esse tempo o programa e terminado e o resultado e False. }

interface

uses
  System.SysUtils, Winapi.Windows;

// "texto" entre aspas, para a linha de comandos
function QuoteArg(const AText: string): string;
// o texto escrito por um programa: UTF-8 e, se os bytes nao forem UTF-8 valido (o Mercurial escreve os nomes de ficheiros
// na pagina de codigo do Windows), essa pagina de codigo
function DecodeOutput(const AData: TBytes): string;
// corre ACmdLine (programa e argumentos) na pasta AWorkDir ('' = a actual); True se terminou com codigo 0
function RunProcess(const ACmdLine, AWorkDir: string; out AOutput: string; ATimeoutMs: Integer = 20000): Boolean;

implementation

function QuoteArg(const AText: string): string;
begin
  Result := '"' + AText.Replace('"', '\"') + '"';
end;

function DecodeOutput(const AData: TBytes): string;
begin
  try
    Result := TEncoding.UTF8.GetString(AData);
  except
    on EEncodingError do
      Result := TEncoding.ANSI.GetString(AData);
  end;
end;

function RunProcess(const ACmdLine, AWorkDir: string; out AOutput: string; ATimeoutMs: Integer): Boolean;
var
  SA: TSecurityAttributes;
  RdPipe, WrPipe, NulIn: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
  Buf: array[0..8191] of Byte;
  Data: TBytes;
  Avail, Got, Code: DWORD;
  Started: UInt64;
  Finished: Boolean;
  WorkDirPtr: PChar;

  procedure Drain;
  begin
    while PeekNamedPipe(RdPipe, nil, 0, nil, @Avail, nil) and (Avail > 0) do
      if ReadFile(RdPipe, Buf, SizeOf(Buf), Got, nil) and (Got > 0) then
      begin
        SetLength(Data, Length(Data) + Integer(Got));
        Move(Buf, Data[Length(Data) - Integer(Got)], Got);
      end
      else
        Break;
  end;

begin
  AOutput := '';
  Result := False;
  if AWorkDir = '' then
    WorkDirPtr := nil
  else
    WorkDirPtr := PChar(AWorkDir);
  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := nil;
  SA.bInheritHandle := True;
  if not CreatePipe(RdPipe, WrPipe, @SA, 0) then
    Exit;
  SetHandleInformation(RdPipe, HANDLE_FLAG_INHERIT, 0);
  NulIn := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @SA, OPEN_EXISTING, 0, 0);
  try
    ZeroMemory(@SI, SizeOf(SI));
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    SI.wShowWindow := SW_HIDE;
    SI.hStdInput := NulIn;
    SI.hStdOutput := WrPipe;
    SI.hStdError := WrPipe;
    ZeroMemory(@PI, SizeOf(PI));
    Cmd := ACmdLine;
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, WorkDirPtr, SI, PI) then
      Exit;
    CloseHandle(WrPipe);
    WrPipe := 0;
    try
      Started := GetTickCount64;
      Finished := False;
      repeat
        Drain;
        Finished := WaitForSingleObject(PI.hProcess, 15) = WAIT_OBJECT_0;
      until Finished or (GetTickCount64 - Started > UInt64(ATimeoutMs));
      if not Finished then
        TerminateProcess(PI.hProcess, 1);
      Drain;
      Code := 1;
      GetExitCodeProcess(PI.hProcess, Code);
      Result := Finished and (Code = 0);
    finally
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
    end;
  finally
    if WrPipe <> 0 then
      CloseHandle(WrPipe);
    CloseHandle(RdPipe);
    if NulIn <> INVALID_HANDLE_VALUE then
      CloseHandle(NulIn);
  end;
  AOutput := DecodeOutput(Data);
end;

end.
