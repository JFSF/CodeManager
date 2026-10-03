unit CM.SonarModel;

{ O que o SonarQube diz sobre os ficheiros do projecto, em memoria: problemas abertos e linhas por ficheiro
  e o estado da quality gate. Quem vai buscar os dados e o CM.Sonar (Infrastructure); aqui so ha o modelo, a
  associacao entre os caminhos do Sonar e os das units e a sincronizacao da marca "S" - tudo sem rede.

  O Sonar guarda os caminhos relativos a raiz do projecto la ('src/Core/CM.Analyzer.pas'), que nao tem de
  ser a pasta que o CodeManager analisa ('Core/CM.Analyzer.pas' se a raiz for "src"): associam-se pelo
  fim do caminho. }

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections, System.Generics.Defaults, CM.Analyzer, CM.Store;

type
  TSonarSeverity = (ssInfo, ssMinor, ssMajor, ssCritical, ssBlocker);

  TSonarFile = record
    Path: string;             // como o Sonar o conhece
    Issues: Integer;          // problemas abertos
    Worst: TSonarSeverity;    // a pior gravidade (so conta com Issues > 0)
    Lines: Integer;           // linhas de codigo
    // medidas do ficheiro (HasMeasures = a ultima consulta trouxe-as); Coverage e DupDensity < 0 = sem valor
    HasMeasures: Boolean;
    Coverage: Double;         // % de cobertura de testes
    DupDensity: Double;       // % de linhas duplicadas
    DebtMin: Integer;         // divida tecnica, em minutos
    Complexity: Integer;      // complexidade ciclomatica do ficheiro
    Cognitive: Integer;       // complexidade cognitiva
    Bugs, Vulns, Smells, Hotspots: Integer;   // contagens por tipo (medidas do Sonar)
  end;

  // um problema aberto numa linha (para a pagina Codigo)
  TSonarIssue = record
    Line: Integer;            // 0 = sem linha (problema do ficheiro)
    Severity: TSonarSeverity;
    Kind: string;             // 'BUG' | 'VULNERABILITY' | 'CODE_SMELL' ('' = desconhecido)
    Rule: string;
    Message: string;
  end;

  // um security hotspot por rever
  TSonarHotspot = record
    Line: Integer;
    Probability: string;      // 'HIGH' | 'MEDIUM' | 'LOW'
    Message: string;
  end;

  // classificacoes A..E do Sonar: 1 = A ... 5 = E; 0 = desconhecida
  TSonarProject = record
    Known: Boolean;           // a ultima consulta trouxe as medidas do projecto
    Lines: Integer;
    Coverage: Double;         // < 0 = sem valor
    DupDensity: Double;       // < 0 = sem valor
    DebtMin: Integer;
    Bugs, Vulns, Smells, Hotspots: Integer;
    Complexity, Cognitive: Integer;
    ReliabilityRating, SecurityRating, MaintainabilityRating, ReviewRating: Integer;
  end;

  TSonarSnapshot = class
  private
    FFiles: TDictionary<string, TSonarFile>;      // caminho do Sonar em minusculas
    FIssueList: TDictionary<string, TList<TSonarIssue>>;      // idem: o detalhe dos problemas
    FHotspotList: TDictionary<string, TList<TSonarHotspot>>;
    FResolved: TDictionary<string, string>;       // caminho da unit (minusculas) -> chave em FFiles ('' = nao existe)
    function ResolveKey(const AUnitPath: string): string;
  public
    ProjectKey: string;
    GateStatus: string;       // 'OK', 'WARN', 'ERROR', 'NONE' (sem gate) ou '' (desconhecido)
    TotalIssues: Integer;
    Project: TSonarProject;   // medidas do projecto inteiro
    FetchedAt: TDateTime;
    constructor Create;
    destructor Destroy; override;
    // o ficheiro foi analisado pelo Sonar (mesmo que nao tenha problemas)
    procedure AddFile(const APath: string; ALines: Integer);
    procedure AddIssue(const APath: string; ASeverity: TSonarSeverity); overload;
    // como AddIssue, e guarda o detalhe (linha, tipo, regra, mensagem) para a pagina Codigo
    procedure AddIssue(const APath: string; const AIssue: TSonarIssue); overload;
    procedure AddHotspot(const APath: string; const AHotspot: TSonarHotspot);
    // medidas de um ficheiro: o Sonar guarda-as sem o ficheiro ter problemas, por isso cria-o se for preciso
    procedure SetFileMeasures(const APath: string; const AMeasures: TSonarFile);
    // o que se sabe de uma unit; vazio se o Sonar a nao conhece. Ordenados por linha
    function IssuesOf(const AUnitPath: string): TArray<TSonarIssue>;
    function HotspotsOf(const AUnitPath: string): TArray<TSonarHotspot>;
    function HotspotCount: Integer;
    // a informacao do Sonar para uma unit (caminho relativo ao projecto analisado, com '/')
    function Find(const AUnitPath: string; out AInfo: TSonarFile): Boolean;
    function FileCount: Integer;
  end;

  TSonarSync = record
    Marked: Integer;          // ficheiros que passaram a ter "S" (sem problemas abertos)
    Cleared: Integer;         // ficheiros que perderam o "S" (tem problemas abertos)
  end;

// uma linha "legenda: valor" para mostrar; Good = vale a pena destacar (por exemplo, uma classificacao A)
type
  TSonarLine = record
    Caption, Value: string;
    Good: Boolean;
  end;

function SeverityFromText(const AText: string): TSonarSeverity;
// as medidas do projecto como linhas para mostrar (vazio sem medidas)
function SonarProjectLines(const AProject: TSonarProject): TArray<TSonarLine>;
// 'cobertura 85% · duplicação 3,2% · dívida 3h' para a dica de um ficheiro ('' sem medidas)
function SonarFileText(const AFile: TSonarFile): string;
// um TSonarFile / TSonarProject sem medidas (as % ficam em -1: "sem valor")
function NewSonarFile(const APath: string): TSonarFile;
function NewSonarProject: TSonarProject;
// 'A'..'E' para a classificacao 1..5 ('' se 0)
function RatingLetter(ARating: Integer): string;
// '2d 3h', '45min', '1h 20min' para minutos (a convencao do Sonar: 1 dia = 8 horas)
function DebtText(AMinutes: Integer): string;
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

function NewSonarFile(const APath: string): TSonarFile;
begin
  Result := Default(TSonarFile);
  Result.Path := APath;
  Result.Coverage := -1;
  Result.DupDensity := -1;
end;

function NewSonarProject: TSonarProject;
begin
  Result := Default(TSonarProject);
  Result.Coverage := -1;
  Result.DupDensity := -1;
end;

function RatingLetter(ARating: Integer): string;
begin
  if (ARating >= 1) and (ARating <= 5) then
    Result := Chr(Ord('A') + ARating - 1)
  else
    Result := '';
end;

function DebtText(AMinutes: Integer): string;
const
  PerHour = 60;
  PerDay = 8 * 60;
var
  D, H, M: Integer;
begin
  if AMinutes <= 0 then
    Exit('0');
  D := AMinutes div PerDay;
  H := (AMinutes mod PerDay) div PerHour;
  M := AMinutes mod PerHour;
  Result := '';
  if D > 0 then
    Result := IntToStr(D) + 'd';
  if H > 0 then
    Result := Trim(Result + ' ' + IntToStr(H) + 'h');
  // com dias so interessam dias e horas; sem eles, as horas e os minutos
  if (D = 0) and (M > 0) then
    Result := Trim(Result + ' ' + IntToStr(M) + 'min');
  if Result = '' then
    Result := IntToStr(M) + 'min';
end;

function PercentOf(AValue: Double): string;
begin
  Result := FormatFloat('0.#', AValue) + '%';
end;

function SonarProjectLines(const AProject: TSonarProject): TArray<TSonarLine>;
var
  List: TList<TSonarLine>;

  procedure Add(const ACaption, AValue: string; AGood: Boolean = False);
  var
    L: TSonarLine;
  begin
    L.Caption := ACaption;
    L.Value := AValue;
    L.Good := AGood;
    List.Add(L);
  end;

  function Rate(ARating: Integer): string;
  begin
    Result := RatingLetter(ARating);
    if Result = '' then
      Result := '—';
  end;

begin
  Result := nil;
  if not AProject.Known then
    Exit;
  List := TList<TSonarLine>.Create;
  try
    Add(Tr('Linhas de código'), FormatFloat('#,##0', AProject.Lines));
    if AProject.Coverage >= 0 then
      Add(Tr('Cobertura de testes'), PercentOf(AProject.Coverage), AProject.Coverage >= 80)
    else
      Add(Tr('Cobertura de testes'), '—');
    if AProject.DupDensity >= 0 then
      Add(Tr('Duplicação'), PercentOf(AProject.DupDensity), AProject.DupDensity <= 3)
    else
      Add(Tr('Duplicação'), '—');
    Add(Tr('Dívida técnica'), DebtText(AProject.DebtMin));
    Add(Tr('Bugs'), IntToStr(AProject.Bugs), AProject.Bugs = 0);
    Add(Tr('Vulnerabilidades'), IntToStr(AProject.Vulns), AProject.Vulns = 0);
    Add(Tr('Code smells'), IntToStr(AProject.Smells));
    Add(Tr('Security hotspots'), IntToStr(AProject.Hotspots), AProject.Hotspots = 0);
    Add(Tr('Fiabilidade'), Rate(AProject.ReliabilityRating), AProject.ReliabilityRating = 1);
    Add(Tr('Segurança'), Rate(AProject.SecurityRating), AProject.SecurityRating = 1);
    Add(Tr('Manutenção'), Rate(AProject.MaintainabilityRating), AProject.MaintainabilityRating = 1);
    Add(Tr('Revisão de hotspots'), Rate(AProject.ReviewRating), AProject.ReviewRating = 1);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SonarFileText(const AFile: TSonarFile): string;
begin
  Result := '';
  if not AFile.HasMeasures then
    Exit;
  if AFile.Coverage >= 0 then
    Result := Tr('cobertura ') + PercentOf(AFile.Coverage);
  if AFile.DupDensity >= 0 then
    Result := Result + IfThen(Result = '', '', ' · ') + Tr('duplicação ') + PercentOf(AFile.DupDensity);
  if AFile.DebtMin > 0 then
    Result := Result + IfThen(Result = '', '', ' · ') + Tr('dívida ') + DebtText(AFile.DebtMin);
  if AFile.Cognitive > 0 then
    Result := Result + IfThen(Result = '', '', ' · ') + Tr('complexidade cognitiva ') + IntToStr(AFile.Cognitive);
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
  FIssueList := TObjectDictionary<string, TList<TSonarIssue>>.Create([doOwnsValues]);
  FHotspotList := TObjectDictionary<string, TList<TSonarHotspot>>.Create([doOwnsValues]);
  Project := NewSonarProject;
end;

destructor TSonarSnapshot.Destroy;
begin
  FHotspotList.Free;
  FIssueList.Free;
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
    F := NewSonarFile(APath);
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
    F := NewSonarFile(APath);
  if (F.Issues = 0) or (ASeverity > F.Worst) then
    F.Worst := ASeverity;
  Inc(F.Issues);
  Inc(TotalIssues);
  FFiles.AddOrSetValue(Key, F);
  FResolved.Clear;
end;

procedure TSonarSnapshot.AddIssue(const APath: string; const AIssue: TSonarIssue);
var
  Key: string;
  List: TList<TSonarIssue>;
begin
  AddIssue(APath, AIssue.Severity);
  Key := NormalizePath(APath);
  if not FIssueList.TryGetValue(Key, List) then
  begin
    List := TList<TSonarIssue>.Create;
    FIssueList.Add(Key, List);
  end;
  List.Add(AIssue);
end;

procedure TSonarSnapshot.AddHotspot(const APath: string; const AHotspot: TSonarHotspot);
var
  Key: string;
  List: TList<TSonarHotspot>;
  F: TSonarFile;
begin
  Key := NormalizePath(APath);
  if not FFiles.TryGetValue(Key, F) then
  begin
    FFiles.Add(Key, NewSonarFile(APath));
    FResolved.Clear;
  end;
  if not FHotspotList.TryGetValue(Key, List) then
  begin
    List := TList<TSonarHotspot>.Create;
    FHotspotList.Add(Key, List);
  end;
  List.Add(AHotspot);
end;

procedure TSonarSnapshot.SetFileMeasures(const APath: string; const AMeasures: TSonarFile);
var
  Key: string;
  F: TSonarFile;
begin
  Key := NormalizePath(APath);
  if not FFiles.TryGetValue(Key, F) then
    F := NewSonarFile(APath);
  // so as medidas: os problemas e a pior gravidade contam-se a parte, a partir da lista de problemas
  F.HasMeasures := True;
  F.Lines := AMeasures.Lines;
  F.Coverage := AMeasures.Coverage;
  F.DupDensity := AMeasures.DupDensity;
  F.DebtMin := AMeasures.DebtMin;
  F.Complexity := AMeasures.Complexity;
  F.Cognitive := AMeasures.Cognitive;
  F.Bugs := AMeasures.Bugs;
  F.Vulns := AMeasures.Vulns;
  F.Smells := AMeasures.Smells;
  F.Hotspots := AMeasures.Hotspots;
  FFiles.AddOrSetValue(Key, F);
  FResolved.Clear;
end;

function TSonarSnapshot.IssuesOf(const AUnitPath: string): TArray<TSonarIssue>;
var
  Key: string;
  List: TList<TSonarIssue>;
begin
  Result := nil;
  Key := ResolveKey(AUnitPath);
  if (Key = '') or not FIssueList.TryGetValue(Key, List) then
    Exit;
  Result := List.ToArray;
  TArray.Sort<TSonarIssue>(Result, TComparer<TSonarIssue>.Construct(
    function(const A, B: TSonarIssue): Integer
    begin
      Result := A.Line - B.Line;
      if Result = 0 then
        Result := Ord(B.Severity) - Ord(A.Severity);
    end));
end;

function TSonarSnapshot.HotspotsOf(const AUnitPath: string): TArray<TSonarHotspot>;
var
  Key: string;
  List: TList<TSonarHotspot>;
begin
  Result := nil;
  Key := ResolveKey(AUnitPath);
  if (Key = '') or not FHotspotList.TryGetValue(Key, List) then
    Exit;
  Result := List.ToArray;
  TArray.Sort<TSonarHotspot>(Result, TComparer<TSonarHotspot>.Construct(
    function(const A, B: TSonarHotspot): Integer
    begin
      Result := A.Line - B.Line;
    end));
end;

function TSonarSnapshot.HotspotCount: Integer;
var
  List: TList<TSonarHotspot>;
begin
  Result := 0;
  for List in FHotspotList.Values do
    Inc(Result, List.Count);
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
