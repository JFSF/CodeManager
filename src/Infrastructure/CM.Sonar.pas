unit CM.Sonar;

{ Cliente (so de leitura) da API Web do SonarQube. Nada aqui e obrigatorio: cada utilizador decide se usa o
  Sonar e como (servidor, token, chave do projecto) e, sem isso, estas funcoes nem chegam a ser chamadas.

  Vai buscar, por projecto: os ficheiros analisados (com as linhas de codigo), os problemas abertos por ficheiro
  (com a gravidade) e o estado da quality gate. O token vai no cabecalho Authorization e nunca em URLs nem logs.

  Os analisadores das respostas (ParseXxx) sao puros e testam-se sem rede. }

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.StrUtils, System.JSON, System.NetEncoding, System.Net.HttpClient,
  System.Net.URLClient, CM.SonarModel;

type
  TSonarConfig = record
    Url: string;              // 'http://localhost:5000'
    Token: string;            // token de utilizador do SonarQube ('' = acesso anonimo)
    ProjectKey: string;
  end;

// 'localhost:5000/' -> 'http://localhost:5000'; vazio continua vazio
function NormalizeSonarUrl(const AUrl: string): string;
// estado da quality gate ('OK', 'WARN', 'ERROR', 'NONE') de /api/qualitygates/project_status; '' se nao se entende
function ParseGateStatus(const AJson: string): string;
// as chaves dos projectos de /api/components/search (para ajudar quando a chave indicada nao existe)
function ParseProjectKeys(const AJson: string): TArray<string>;
// acrescenta a ASnap os problemas de uma pagina de /api/issues/search; devolve quantos; ATotal = paging.total
function ParseIssuesPage(const AJson, AProjectKey: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
// acrescenta a ASnap os ficheiros de uma pagina de /api/measures/component_tree (com as medidas de cada um);
// devolve quantos; ATotal = paging.total
function ParseMeasuresPage(const AJson: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
// as medidas do projecto inteiro de /api/measures/component; False se a resposta nao as traz
function ParseProjectMeasures(const AJson: string; ASnap: TSonarSnapshot): Boolean;
// acrescenta a ASnap os security hotspots de uma pagina de /api/hotspots/search; devolve quantos; ATotal = paging.total
function ParseHotspotsPage(const AJson, AProjectKey: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;

const
  // as medidas pedidas ao Sonar (no maximo 15 por pedido)
  FileMetricKeys = 'ncloc,coverage,duplicated_lines_density,sqale_index,complexity,cognitive_complexity,' +
    'bugs,vulnerabilities,code_smells,security_hotspots';
  ProjectMetricKeys = FileMetricKeys + ',reliability_rating,security_rating,sqale_rating,security_review_rating';

type
  // um pedido em segundo plano. A interface consulta Done (por exemplo num temporizador) e depois le o
  // resultado; a thread nunca toca nos objectos da janela. Se ninguem recolher o resultado, liberta-se sozinho
  ISonarJob = interface
    ['{3B5E7C1A-9D24-4F6B-8A31-5C7D2E90F4B6}']
    function GetDone: Boolean;
    function GetSuccess: Boolean;
    function GetMessage: string;
    // passa a propriedade do snapshot para quem chama (so uma vez; nil num teste de ligacao ou numa falha)
    function TakeSnapshot: TSonarSnapshot;
    property Done: Boolean read GetDone;
    property Success: Boolean read GetSuccess;
    property Message: string read GetMessage;     // o erro, ou o resultado do teste
  end;

// o que ainda e preciso fazer para ligar: '' se esta tudo; senao o que falta (em portugues)
function SonarMissing(const AConfig: TSonarConfig): string;
function StartSonarFetch(const AConfig: TSonarConfig): ISonarJob;
function StartSonarTest(const AConfig: TSonarConfig): ISonarJob;

// verifica o servidor, o token e a chave do projecto; AMessage explica o resultado (em portugues)
function SonarTest(const AConfig: TSonarConfig; out AMessage: string): Boolean;
// vai buscar tudo; o resultado (ASnapshot) e de quem chama. AError explica a falha (em portugues)
function SonarFetch(const AConfig: TSonarConfig; out ASnapshot: TSonarSnapshot; out AError: string): Boolean;

implementation


uses
  CM.Lang;
const
  PageSize = 500;
  MaxPages = 20;               // a API do Sonar nao devolve mais de 10 000 resultados por pesquisa

function NormalizeSonarUrl(const AUrl: string): string;
begin
  Result := Trim(AUrl);
  if Result = '' then
    Exit;
  if not (Result.StartsWith('http://', True) or Result.StartsWith('https://', True)) then
    Result := 'http://' + Result;
  while Result.EndsWith('/') do
    Result := Copy(Result, 1, Length(Result) - 1);
end;

function ImpactToSeverity(const AText: string): TSonarSeverity;
begin
  // as versoes recentes descrevem o impacto como HIGH/MEDIUM/LOW
  if SameText(AText, 'HIGH') then Result := ssCritical
  else if SameText(AText, 'MEDIUM') then Result := ssMajor
  else if SameText(AText, 'LOW') then Result := ssMinor
  else Result := SeverityFromText(AText);
end;

function PagingTotal(ARoot: TJSONObject): Integer;
var
  Paging: TJSONObject;
begin
  Result := 0;
  if ARoot.TryGetValue<TJSONObject>('paging', Paging) then
    Result := Paging.GetValue<Integer>('total', 0)
  else
    Result := ARoot.GetValue<Integer>('total', 0);
end;

function ParseGateStatus(const AJson: string): string;
var
  V: TJSONValue;
  Status: TJSONObject;
begin
  Result := '';
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if (V is TJSONObject) and TJSONObject(V).TryGetValue<TJSONObject>('projectStatus', Status) then
      Result := UpperCase(Status.GetValue<string>('status', ''));
  finally
    V.Free;
  end;
end;

// 'Chave:src/Core/a.pas' -> 'src/Core/a.pas'; '' se for o proprio projecto ou outro componente
function ComponentPath(const AComponent, AProjectKey: string): string;
begin
  Result := AComponent;
  if (AProjectKey <> '') and Result.StartsWith(AProjectKey + ':') then
    Result := Copy(Result, Length(AProjectKey) + 2, MaxInt)
  else if Pos(':', Result) > 0 then
    Result := Copy(Result, Pos(':', Result) + 1, MaxInt)
  else
    Result := '';
end;

function ParseProjectKeys(const AJson: string): TArray<string>;
var
  V, Item: TJSONValue;
  Comps: TJSONArray;
  List: TStringList;
begin
  Result := nil;
  V := TJSONObject.ParseJSONValue(AJson);
  List := TStringList.Create;
  try
    if (V is TJSONObject) and TJSONObject(V).TryGetValue<TJSONArray>('components', Comps) then
      for Item in Comps do
        if (Item is TJSONObject) and (TJSONObject(Item).GetValue<string>('key', '') <> '') then
          List.Add(TJSONObject(Item).GetValue<string>('key', ''));
    Result := List.ToStringArray;
  finally
    List.Free;
    V.Free;
  end;
end;

function ParseIssuesPage(const AJson, AProjectKey: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
var
  V, Item: TJSONValue;
  Root, Issue, Impact, Range: TJSONObject;
  Issues, Impacts: TJSONArray;
  Path, Sev: string;
  Detail: TSonarIssue;
begin
  Result := 0;
  ATotal := 0;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if not (V is TJSONObject) then
      Exit;
    Root := TJSONObject(V);
    ATotal := PagingTotal(Root);
    if not Root.TryGetValue<TJSONArray>('issues', Issues) then
      Exit;
    for Item in Issues do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Issue := TJSONObject(Item);
      Path := ComponentPath(Issue.GetValue<string>('component', ''), AProjectKey);
      if Path = '' then
        Continue;
      Sev := Issue.GetValue<string>('severity', '');
      if (Sev = '') and Issue.TryGetValue<TJSONArray>('impacts', Impacts) and (Impacts.Count > 0) and
         (Impacts.Items[0] is TJSONObject) then
      begin
        Impact := TJSONObject(Impacts.Items[0]);
        Sev := Impact.GetValue<string>('severity', '');
      end;
      Detail := Default(TSonarIssue);
      Detail.Severity := ImpactToSeverity(Sev);
      Detail.Line := Issue.GetValue<Integer>('line', 0);
      if (Detail.Line = 0) and Issue.TryGetValue<TJSONObject>('textRange', Range) then
        Detail.Line := Range.GetValue<Integer>('startLine', 0);
      Detail.Kind := Issue.GetValue<string>('type', '');
      Detail.Rule := Issue.GetValue<string>('rule', '');
      Detail.Message := Issue.GetValue<string>('message', '');
      ASnap.AddIssue(Path, Detail);
      Inc(Result);
    end;
  finally
    V.Free;
  end;
end;

function ToFloat(const AText: string; ADefault: Double): Double;
begin
  Result := StrToFloatDef(AText, ADefault, TFormatSettings.Invariant);
end;

// o Sonar escreve as classificacoes como '1.0'..'5.0'
function ToRating(const AText: string): Integer;
begin
  Result := Round(ToFloat(AText, 0));
  if (Result < 1) or (Result > 5) then
    Result := 0;
end;

procedure ApplyFileMetric(var AFile: TSonarFile; const AMetric, AValue: string);
begin
  if AMetric = 'ncloc' then AFile.Lines := Round(ToFloat(AValue, 0))
  else if AMetric = 'coverage' then AFile.Coverage := ToFloat(AValue, -1)
  else if AMetric = 'duplicated_lines_density' then AFile.DupDensity := ToFloat(AValue, -1)
  else if AMetric = 'sqale_index' then AFile.DebtMin := Round(ToFloat(AValue, 0))
  else if AMetric = 'complexity' then AFile.Complexity := Round(ToFloat(AValue, 0))
  else if AMetric = 'cognitive_complexity' then AFile.Cognitive := Round(ToFloat(AValue, 0))
  else if AMetric = 'bugs' then AFile.Bugs := Round(ToFloat(AValue, 0))
  else if AMetric = 'vulnerabilities' then AFile.Vulns := Round(ToFloat(AValue, 0))
  else if AMetric = 'code_smells' then AFile.Smells := Round(ToFloat(AValue, 0))
  else if AMetric = 'security_hotspots' then AFile.Hotspots := Round(ToFloat(AValue, 0));
end;

procedure ApplyProjectMetric(var AProject: TSonarProject; const AMetric, AValue: string);
begin
  if AMetric = 'ncloc' then AProject.Lines := Round(ToFloat(AValue, 0))
  else if AMetric = 'coverage' then AProject.Coverage := ToFloat(AValue, -1)
  else if AMetric = 'duplicated_lines_density' then AProject.DupDensity := ToFloat(AValue, -1)
  else if AMetric = 'sqale_index' then AProject.DebtMin := Round(ToFloat(AValue, 0))
  else if AMetric = 'complexity' then AProject.Complexity := Round(ToFloat(AValue, 0))
  else if AMetric = 'cognitive_complexity' then AProject.Cognitive := Round(ToFloat(AValue, 0))
  else if AMetric = 'bugs' then AProject.Bugs := Round(ToFloat(AValue, 0))
  else if AMetric = 'vulnerabilities' then AProject.Vulns := Round(ToFloat(AValue, 0))
  else if AMetric = 'code_smells' then AProject.Smells := Round(ToFloat(AValue, 0))
  else if AMetric = 'security_hotspots' then AProject.Hotspots := Round(ToFloat(AValue, 0))
  else if AMetric = 'reliability_rating' then AProject.ReliabilityRating := ToRating(AValue)
  else if AMetric = 'security_rating' then AProject.SecurityRating := ToRating(AValue)
  else if AMetric = 'sqale_rating' then AProject.MaintainabilityRating := ToRating(AValue)
  else if AMetric = 'security_review_rating' then AProject.ReviewRating := ToRating(AValue);
end;

function ParseMeasuresPage(const AJson: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
var
  V, Item, M: TJSONValue;
  Root, Comp: TJSONObject;
  Comps, Measures: TJSONArray;
  Path: string;
  F: TSonarFile;
begin
  Result := 0;
  ATotal := 0;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if not (V is TJSONObject) then
      Exit;
    Root := TJSONObject(V);
    ATotal := PagingTotal(Root);
    if not Root.TryGetValue<TJSONArray>('components', Comps) then
      Exit;
    for Item in Comps do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Comp := TJSONObject(Item);
      Path := Comp.GetValue<string>('path', '');
      if Path = '' then
        Continue;
      F := NewSonarFile(Path);
      if Comp.TryGetValue<TJSONArray>('measures', Measures) then
        for M in Measures do
          if M is TJSONObject then
            ApplyFileMetric(F, TJSONObject(M).GetValue<string>('metric', ''), TJSONObject(M).GetValue<string>('value', ''));
      ASnap.AddFile(Path, F.Lines);
      ASnap.SetFileMeasures(Path, F);
      Inc(Result);
    end;
  finally
    V.Free;
  end;
end;

function ParseProjectMeasures(const AJson: string; ASnap: TSonarSnapshot): Boolean;
var
  V, M: TJSONValue;
  Comp: TJSONObject;
  Measures: TJSONArray;
  P: TSonarProject;
begin
  Result := False;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if not (V is TJSONObject) or not TJSONObject(V).TryGetValue<TJSONObject>('component', Comp) or
       not Comp.TryGetValue<TJSONArray>('measures', Measures) then
      Exit;
    P := NewSonarProject;
    for M in Measures do
      if M is TJSONObject then
        ApplyProjectMetric(P, TJSONObject(M).GetValue<string>('metric', ''), TJSONObject(M).GetValue<string>('value', ''));
    P.Known := Measures.Count > 0;
    ASnap.Project := P;
    Result := P.Known;
  finally
    V.Free;
  end;
end;

function ParseHotspotsPage(const AJson, AProjectKey: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
var
  V, Item: TJSONValue;
  Root, H: TJSONObject;
  Hotspots: TJSONArray;
  Path: string;
  Spot: TSonarHotspot;
begin
  Result := 0;
  ATotal := 0;
  V := TJSONObject.ParseJSONValue(AJson);
  try
    if not (V is TJSONObject) then
      Exit;
    Root := TJSONObject(V);
    ATotal := PagingTotal(Root);
    if not Root.TryGetValue<TJSONArray>('hotspots', Hotspots) then
      Exit;
    for Item in Hotspots do
    begin
      if not (Item is TJSONObject) then
        Continue;
      H := TJSONObject(Item);
      Path := ComponentPath(H.GetValue<string>('component', ''), AProjectKey);
      if Path = '' then
        Continue;
      Spot := Default(TSonarHotspot);
      Spot.Line := H.GetValue<Integer>('line', 0);
      Spot.Probability := UpperCase(H.GetValue<string>('vulnerabilityProbability', ''));
      Spot.Message := H.GetValue<string>('message', '');
      ASnap.AddHotspot(Path, Spot);
      Inc(Result);
    end;
  finally
    V.Free;
  end;
end;

{ ---------------------------------------------------------------- HTTP }

// GET autenticado; devolve o codigo HTTP (0 = nao foi possivel ligar) e o corpo. AFail leva o motivo da falha de ligacao
function HttpGet(const AConfig: TSonarConfig; const APath: string; out ABody, AFail: string): Integer;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
begin
  ABody := '';
  AFail := '';
  Result := 0;
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 5000;
    Client.ResponseTimeout := 30000;
    if AConfig.Token <> '' then
      Client.CustomHeaders['Authorization'] := 'Basic ' + TNetEncoding.Base64String.Encode(AConfig.Token + ':');
    try
      Response := Client.Get(NormalizeSonarUrl(AConfig.Url) + APath);
      Result := Response.StatusCode;
      ABody := Response.ContentAsString(TEncoding.UTF8);
    except
      on E: Exception do
        AFail := E.Message;
    end;
  finally
    Client.Free;
  end;
end;

function Enc(const AText: string): string;
begin
  Result := TNetEncoding.URL.Encode(AText);
end;

// texto em portugues para um codigo HTTP que nao e 200
function StatusMessage(AStatus: Integer; const AFail: string; const AConfig: TSonarConfig): string;
begin
  case AStatus of
    0: Result := Tr('Não foi possível ligar a ') + NormalizeSonarUrl(AConfig.Url) + '. ' + AFail;
    401: Result := Tr('O servidor recusou o token (ou exige um token). Confirma-o nas definições.');
    403: Result := Tr('O token não tem permissão para ler este projeto. Usa um token de utilizador (My Account › Security › ') +
      Tr('User Token), não o de análise do sonar-scanner, de uma conta com a permissão «Browse» no projeto.');
    404: Result := Tr('Não encontrei o projeto «') + AConfig.ProjectKey + Tr('» neste servidor.');
  else
    Result := Format(Tr('O servidor respondeu com o erro %d.'), [AStatus]);
  end;
end;

// ajuda quando a chave nao existe: que projectos tem o servidor (ate 5)
function AvailableKeysHint(const AConfig: TSonarConfig): string;
var
  Body, Fail: string;
  Keys: TArray<string>;
begin
  if HttpGet(AConfig, '/api/components/search?qualifiers=TRK&ps=6', Body, Fail) <> 200 then
    Exit('');
  Keys := ParseProjectKeys(Body);
  if Length(Keys) = 0 then
    Exit(Tr('O servidor ainda não tem projetos analisados: corre primeiro o sonar-scanner (ci.bat sonar).'));
  Result := Tr('Chaves que existem: ') + string.Join(', ', Copy(Keys, 0, 5)) + IfThen(Length(Keys) > 5, ', …', '') + '.';
end;

function SonarTest(const AConfig: TSonarConfig; out AMessage: string): Boolean;
var
  Body, Fail, Version: string;
  Status: Integer;
  V: TJSONValue;
begin
  Result := False;
  if NormalizeSonarUrl(AConfig.Url) = '' then
  begin
    AMessage := Tr('Indica o endereço do servidor.');
    Exit;
  end;
  Status := HttpGet(AConfig, '/api/system/status', Body, Fail);
  if Status <> 200 then
  begin
    AMessage := StatusMessage(Status, Fail, AConfig);
    Exit;
  end;
  Version := '';
  V := TJSONObject.ParseJSONValue(Body);
  try
    if V is TJSONObject then
      Version := TJSONObject(V).GetValue<string>('version', '');
  finally
    V.Free;
  end;
  if AConfig.ProjectKey = '' then
  begin
    AMessage := Tr('Ligado ao SonarQube ') + Version + Tr('. Falta indicar a chave do projeto.');
    Exit;
  end;
  Status := HttpGet(AConfig, '/api/components/show?component=' + Enc(AConfig.ProjectKey), Body, Fail);
  if Status <> 200 then
  begin
    AMessage := StatusMessage(Status, Fail, AConfig);
    if Status = 404 then
      AMessage := AMessage + ' ' + AvailableKeysHint(AConfig);
    Exit;
  end;
  AMessage := Tr('Ligado ao SonarQube ') + Version + Tr(': projeto «') + AConfig.ProjectKey + Tr('» encontrado.');
  Result := True;
end;

function SonarFetch(const AConfig: TSonarConfig; out ASnapshot: TSonarSnapshot; out AError: string): Boolean;
var
  Body, Fail: string;
  Status, Page, Total, Got, Seen: Integer;
begin
  Result := False;
  AError := '';
  ASnapshot := TSonarSnapshot.Create;
  ASnapshot.ProjectKey := AConfig.ProjectKey;
  try
    // 1) os ficheiros analisados (e as suas linhas)
    Page := 1;
    Seen := 0;
    repeat
      Status := HttpGet(AConfig, Format('/api/measures/component_tree?component=%s&metricKeys=%s&qualifiers=FIL,UTS&ps=%d&p=%d',
        [Enc(AConfig.ProjectKey), FileMetricKeys, PageSize, Page]), Body, Fail);
      if Status <> 200 then
      begin
        AError := StatusMessage(Status, Fail, AConfig);
        Exit;
      end;
      Got := ParseMeasuresPage(Body, ASnapshot, Total);
      Inc(Seen, Got);
      Inc(Page);
    until (Got = 0) or (Seen >= Total) or (Page > MaxPages);

    // 2) os problemas abertos
    Page := 1;
    Seen := 0;
    repeat
      Status := HttpGet(AConfig, Format('/api/issues/search?componentKeys=%s&resolved=false&ps=%d&p=%d',
        [Enc(AConfig.ProjectKey), PageSize, Page]), Body, Fail);
      if Status <> 200 then
      begin
        AError := StatusMessage(Status, Fail, AConfig);
        Exit;
      end;
      Got := ParseIssuesPage(Body, AConfig.ProjectKey, ASnapshot, Total);
      Inc(Seen, PageSize);
      Inc(Page);
    until (Got = 0) or (Seen >= Total) or (Page > MaxPages);

    // 3) as medidas do projecto e os security hotspots (opcionais: uma versao antiga ou sem permissao fica sem eles)
    Status := HttpGet(AConfig, Format('/api/measures/component?component=%s&metricKeys=%s',
      [Enc(AConfig.ProjectKey), ProjectMetricKeys]), Body, Fail);
    if Status = 200 then
      ParseProjectMeasures(Body, ASnapshot);
    Page := 1;
    Seen := 0;
    repeat
      Status := HttpGet(AConfig, Format('/api/hotspots/search?projectKey=%s&status=TO_REVIEW&ps=%d&p=%d',
        [Enc(AConfig.ProjectKey), PageSize, Page]), Body, Fail);
      if Status <> 200 then
        Break;
      Got := ParseHotspotsPage(Body, AConfig.ProjectKey, ASnapshot, Total);
      Inc(Seen, PageSize);
      Inc(Page);
    until (Got = 0) or (Seen >= Total) or (Page > MaxPages);

    // 4) a quality gate (opcional: sem permissao ou sem gate fica desconhecida)
    Status := HttpGet(AConfig, '/api/qualitygates/project_status?projectKey=' + Enc(AConfig.ProjectKey), Body, Fail);
    if Status = 200 then
      ASnapshot.GateStatus := ParseGateStatus(Body);
    ASnapshot.FetchedAt := Now;
    Result := True;
  finally
    if not Result then
      FreeAndNil(ASnapshot);
  end;
end;

{ ---------------------------------------------------------------- segundo plano }

type
  TSonarJob = class(TInterfacedObject, ISonarJob)
  private
    FLock: TCriticalSection;
    FDone, FSuccess: Boolean;
    FMessage: string;
    FSnapshot: TSonarSnapshot;
    function GetDone: Boolean;
    function GetSuccess: Boolean;
    function GetMessage: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Complete(ASuccess: Boolean; const AMessage: string; ASnapshot: TSonarSnapshot);
    function TakeSnapshot: TSonarSnapshot;
  end;

constructor TSonarJob.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
end;

destructor TSonarJob.Destroy;
begin
  FSnapshot.Free;           // ninguem o recolheu
  FLock.Free;
  inherited;
end;

procedure TSonarJob.Complete(ASuccess: Boolean; const AMessage: string; ASnapshot: TSonarSnapshot);
begin
  FLock.Enter;
  try
    FSuccess := ASuccess;
    FMessage := AMessage;
    FSnapshot := ASnapshot;
    FDone := True;
  finally
    FLock.Leave;
  end;
end;

function TSonarJob.GetDone: Boolean;
begin
  FLock.Enter;
  try
    Result := FDone;
  finally
    FLock.Leave;
  end;
end;

function TSonarJob.GetSuccess: Boolean;
begin
  FLock.Enter;
  try
    Result := FSuccess;
  finally
    FLock.Leave;
  end;
end;

function TSonarJob.GetMessage: string;
begin
  FLock.Enter;
  try
    Result := FMessage;
  finally
    FLock.Leave;
  end;
end;

function TSonarJob.TakeSnapshot: TSonarSnapshot;
begin
  FLock.Enter;
  try
    Result := FSnapshot;
    FSnapshot := nil;
  finally
    FLock.Leave;
  end;
end;

function SonarMissing(const AConfig: TSonarConfig): string;
begin
  if NormalizeSonarUrl(AConfig.Url) = '' then
    Result := Tr('Indica o endereço do servidor.')
  else if Trim(AConfig.ProjectKey) = '' then
    Result := Tr('Indica a chave do projeto no SonarQube.')
  else
    Result := '';
end;

function StartSonarFetch(const AConfig: TSonarConfig): ISonarJob;
var
  Ref: ISonarJob;
  Config: TSonarConfig;
begin
  Ref := TSonarJob.Create;       // a thread guarda a sua propria referencia: o objecto vive ate ela acabar
  Result := Ref;
  Config := AConfig;
  TThread.CreateAnonymousThread(
    procedure
    var
      Snap: TSonarSnapshot;
      Err: string;
      Ok: Boolean;
    begin
      Snap := nil;
      try
        Ok := SonarFetch(Config, Snap, Err);
      except
        on E: Exception do
        begin
          Ok := False;
          Err := E.Message;
          FreeAndNil(Snap);
        end;
      end;
      (Ref as TSonarJob).Complete(Ok, Err, Snap);
    end).Start;
end;

function StartSonarTest(const AConfig: TSonarConfig): ISonarJob;
var
  Ref: ISonarJob;
  Config: TSonarConfig;
begin
  Ref := TSonarJob.Create;       // a thread guarda a sua propria referencia: o objecto vive ate ela acabar
  Result := Ref;
  Config := AConfig;
  TThread.CreateAnonymousThread(
    procedure
    var
      Msg: string;
      Ok: Boolean;
    begin
      try
        Ok := SonarTest(Config, Msg);
      except
        on E: Exception do
        begin
          Ok := False;
          Msg := E.Message;
        end;
      end;
      (Ref as TSonarJob).Complete(Ok, Msg, nil);
    end).Start;
end;

end.
