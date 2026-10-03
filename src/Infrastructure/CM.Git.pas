unit CM.Git;

{ Acesso minimo ao Git: corre o "git" da linha de comandos (sem janela) e le o resultado.
  So le: nunca altera o repositorio. Sem Git instalado, ou fora de um repositorio, as funcoes
  devolvem vazio / False, e quem as usa limita-se a nao mostrar nada.

  Todos os caminhos devolvidos sao relativos a pasta ARoot (a raiz do projecto, que pode ser uma
  subpasta do repositorio), com '/', como os caminhos das units. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Winapi.Windows, CM.Stats;

type
  TGitCommit = record
    Hash: string;       // abreviado
    Author: string;
    Date: string;       // aaaa-mm-dd
    Subject: string;
  end;

// corre "git -C ARoot AArgs"; devolve True se terminou com codigo 0. AOutput leva o texto (UTF-8)
function RunGit(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer = 20000): Boolean;
function GitAvailable: Boolean;
// o commit actual de ARoot; '' se nao houver Git, repositorio ou commits
function GitHead(const ARoot: string): string;
// os commits do ramo actual com a sua hora, do mais recente para o mais antigo
function GitTimeline(const ARoot: string): TArray<TCommitTime>;
// junta a AChanged os ficheiros diferentes de ARev (incluindo alteracoes ainda por gravar no Git).
// False se ARev nao existe (por exemplo, historia reescrita)
function GitChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
// os (no maximo AMax) commits feitos depois de ARev que tocaram em ARelPath, do mais recente para o mais antigo
function GitCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TGitCommit>;
// "texto" entre aspas, para a linha de comandos
function GitQuote(const AText: string): string;

implementation

var
  GAvailable: Integer = -1;       // -1 = ainda nao se sabe

function GitQuote(const AText: string): string;
begin
  Result := '"' + AText.Replace('"', '\"') + '"';
end;

function RunGit(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer): Boolean;
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
    Cmd := 'git -c core.quotepath=false -C ' + GitQuote(ARoot) + ' ' + AArgs;
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
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
  AOutput := TEncoding.UTF8.GetString(Data);
end;

function GitAvailable: Boolean;
var
  Output: string;
begin
  if GAvailable < 0 then
  begin
    if RunGit(GetCurrentDir, '--version', Output, 5000) and Output.StartsWith('git version') then
      GAvailable := 1
    else
      GAvailable := 0;
  end;
  Result := GAvailable = 1;
end;

function SplitLines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13, '').Split([#10], TStringSplitOptions.ExcludeEmpty);
end;

function GitHead(const ARoot: string): string;
var
  Output: string;
begin
  Result := '';
  if not GitAvailable then
    Exit;
  if RunGit(ARoot, 'rev-parse HEAD', Output) then
    Result := Output.Trim;
  if Length(Result) < 7 then       // sem commits o git escreve um erro, nao um hash
    Result := '';
end;

function GitTimeline(const ARoot: string): TArray<TCommitTime>;
var
  Output, Line: string;
  Parts: TArray<string>;
  List: TList<TCommitTime>;
  C: TCommitTime;
begin
  Result := nil;
  if not GitAvailable then
    Exit;
  if not RunGit(ARoot, 'log --format="%H %ct"', Output, 60000) then
    Exit;
  List := TList<TCommitTime>.Create;
  try
    for Line in SplitLines(Output) do
    begin
      Parts := Line.Trim.Split([' ']);
      if (Length(Parts) = 2) and TryStrToInt64(Parts[1], C.Time) then
      begin
        C.Hash := Parts[0];
        List.Add(C);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function GitChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
var
  Output, Line: string;
begin
  Result := False;
  if not GitAvailable or (ARev = '') then
    Exit;
  if not RunGit(ARoot, 'diff --name-only --relative ' + GitQuote(ARev), Output, 60000) then
    Exit;
  for Line in SplitLines(Output) do
    AChanged.Add(Line.Trim.Replace('\', '/'));
  Result := True;
end;

function GitCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TGitCommit>;
var
  Output, Line: string;
  Parts: TArray<string>;
  List: TList<TGitCommit>;
  C: TGitCommit;
begin
  Result := nil;
  if not GitAvailable or (ARev = '') then
    Exit;
  if not RunGit(ARoot, Format('log -n %d --date=short --format="%%h%%x09%%an%%x09%%ad%%x09%%s" %s..HEAD -- %s',
       [AMax, GitQuote(ARev), GitQuote(ARelPath)]), Output) then
    Exit;
  List := TList<TGitCommit>.Create;
  try
    for Line in SplitLines(Output) do
    begin
      Parts := Line.Split([#9]);
      if Length(Parts) >= 4 then
      begin
        C.Hash := Parts[0];
        C.Author := Parts[1];
        C.Date := Parts[2];
        C.Subject := Parts[3];
        List.Add(C);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
