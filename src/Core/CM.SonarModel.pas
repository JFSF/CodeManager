unit CM.SonarModel;

{ O que o SonarQube diz sobre os ficheiros do projecto, em memoria: problemas abertos e linhas por ficheiro
  e o estado da quality gate. Quem vai buscar os dados e o CM.Sonar (Infrastructure); aqui so ha o modelo, a
  associacao entre os caminhos do Sonar e os das units e a sincronizacao da marca "S" - tudo sem rede.

  O Sonar guarda os caminhos relativos a raiz do projecto la ('src/Core/CM.Analyzer.pas'), que nao tem de
  ser a pasta que o CodeManager analisa ('Core/CM.Analyzer.pas' se a raiz for "src"): associam-se pelo
  fim do caminho. }

interface

uses
  System.SysUtils, System.Generics.Collections, CM.Analyzer, CM.Store;

type
  TSonarSeverity = (ssInfo, ssMinor, ssMajor, ssCritical, ssBlocker);

  TSonarFile = record
    Path: string;             // como o Sonar o conhece
    Issues: Integer;          // problemas abertos
    Worst: TSonarSeverity;    // a pior gravidade (so conta com Issues > 0)
    Lines: Integer;           // linhas de codigo
  end;

  TSonarSnapshot = class
  private
    FFiles: TDictionary<string, TSonarFile>;      // caminho do Sonar em minusculas
    FResolved: TDictionary<string, string>;       // caminho da unit (minusculas) -> chave em FFiles ('' = nao existe)
    function ResolveKey(const AUnitPath: string): string;
  public
    ProjectKey: string;
    GateStatus: string;       // 'OK', 'WARN', 'ERROR', 'NONE' (sem gate) ou '' (desconhecido)
    TotalIssues: Integer;
    FetchedAt: TDateTime;
    constructor Create;
    destructor Destroy; override;
    // o ficheiro foi analisado pelo Sonar (mesmo que nao tenha problemas)
    procedure AddFile(const APath: string; ALines: Integer);
    procedure AddIssue(const APath: string; ASeverity: TSonarSeverity);
    // a informacao do Sonar para uma unit (caminho relativo ao projecto analisado, com '/')
    function Find(const AUnitPath: string; out AInfo: TSonarFile): Boolean;
    function FileCount: Integer;
  end;

  TSonarSync = record
    Marked: Integer;          // ficheiros que passaram a ter "S" (sem problemas abertos)
    Cleared: Integer;         // ficheiros que perderam o "S" (tem problemas abertos)
  end;

function SeverityFromText(const AText: string): TSonarSeverity;
function SeverityText(ASeverity: TSonarSeverity): string;
// poe "S" nos ficheiros analisados sem problemas e tira-o aos que tem problemas; os que o Sonar nao conhece ficam como estao
function SyncSonarFlags(AScan: TProjectScan; AState: TProgressState; ASnapshot: TSonarSnapshot): TSonarSync;

implementation


uses
  CM.Lang;
function SeverityFromText(const AText: string): TSonarSeverity;
begin
  if SameText(AText, 'BLOCKER') then Result := ssBlocker
  else if SameText(AText, 'CRITICAL') then Result := ssCritical
  else if SameText(AText, 'MAJOR') then Result := ssMajor
  else if SameText(AText, 'MINOR') then Result := ssMinor
  else Result := ssInfo;
end;

function SeverityText(ASeverity: TSonarSeverity): string;
begin
  case ASeverity of
    ssBlocker: Result := Tr('bloqueante');
    ssCritical: Result := Tr('crítica');
    ssMajor: Result := Tr('maior');
    ssMinor: Result := Tr('menor');
  else
    Result := Tr('informativa');
  end;
end;

function NormalizePath(const APath: string): string;
begin
  Result := LowerCase(APath.Replace('\', '/'));
  while Result.StartsWith('./') do
    Result := Copy(Result, 3, MaxInt);
end;

{ TSonarSnapshot }

constructor TSonarSnapshot.Create;
begin
  inherited;
  FFiles := TDictionary<string, TSonarFile>.Create;
  FResolved := TDictionary<string, string>.Create;
end;

destructor TSonarSnapshot.Destroy;
begin
  FResolved.Free;
  FFiles.Free;
  inherited;
end;

function TSonarSnapshot.FileCount: Integer;
begin
  Result := FFiles.Count;
end;

procedure TSonarSnapshot.AddFile(const APath: string; ALines: Integer);
var
  Key: string;
  F: TSonarFile;
begin
  Key := NormalizePath(APath);
  if not FFiles.TryGetValue(Key, F) then
  begin
    F := Default(TSonarFile);
    F.Path := APath;
  end;
  F.Lines := ALines;
  FFiles.AddOrSetValue(Key, F);
  FResolved.Clear;
end;

procedure TSonarSnapshot.AddIssue(const APath: string; ASeverity: TSonarSeverity);
var
  Key: string;
  F: TSonarFile;
begin
  Key := NormalizePath(APath);
  if not FFiles.TryGetValue(Key, F) then
  begin
    F := Default(TSonarFile);
    F.Path := APath;
  end;
  if (F.Issues = 0) or (ASeverity > F.Worst) then
    F.Worst := ASeverity;
  Inc(F.Issues);
  Inc(TotalIssues);
  FFiles.AddOrSetValue(Key, F);
  FResolved.Clear;
end;

// exacto primeiro; depois pelo fim do caminho (nos dois sentidos), preferindo o mais longo
function TSonarSnapshot.ResolveKey(const AUnitPath: string): string;
var
  U, K, Best: string;
begin
  U := NormalizePath(AUnitPath);
  if FFiles.ContainsKey(U) then
    Exit(U);
  Best := '';
  for K in FFiles.Keys do
    if (K.EndsWith('/' + U) or U.EndsWith('/' + K)) and (Length(K) > Length(Best)) then
      Best := K;
  Result := Best;
end;

function TSonarSnapshot.Find(const AUnitPath: string; out AInfo: TSonarFile): Boolean;
var
  U, Key: string;
begin
  U := NormalizePath(AUnitPath);
  if not FResolved.TryGetValue(U, Key) then
  begin
    Key := ResolveKey(AUnitPath);
    FResolved.Add(U, Key);
  end;
  Result := (Key <> '') and FFiles.TryGetValue(Key, AInfo);
end;

function SyncSonarFlags(AScan: TProjectScan; AState: TProgressState; ASnapshot: TSonarSnapshot): TSonarSync;
var
  U: TUnitInfo;
  Info: TSonarFile;
  S: TUnitState;
  Want: Boolean;
begin
  Result := Default(TSonarSync);
  if (AScan = nil) or (AState = nil) or (ASnapshot = nil) then
    Exit;
  for U in AScan.Units do
    if ASnapshot.Find(U.Path, Info) then
    begin
      Want := Info.Issues = 0;
      S := AState.Find(U.Path);
      if (S <> nil) and (S.Sonar = Want) then
        Continue;
      if (S = nil) and not Want then
        Continue;                  // sem registo e sem "S": nada a tirar
      S := AState.Rec(U.Path);
      S.Sonar := Want;
      if Want then Inc(Result.Marked) else Inc(Result.Cleared);
    end;
end;

end.
