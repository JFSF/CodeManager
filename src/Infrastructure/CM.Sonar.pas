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
// acrescenta a ASnap os ficheiros de uma pagina de /api/measures/component_tree; devolve quantos; ATotal = paging.total
function ParseMeasuresPage(const AJson: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
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
  Root, Issue, Impact: TJSONObject;
  Issues, Impacts: TJSONArray;
  Path, Sev: string;
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
      ASnap.AddIssue(Path, ImpactToSeverity(Sev));
      Inc(Result);
    end;
  finally
    V.Free;
  end;
end;

function ParseMeasuresPage(const AJson: string; ASnap: TSonarSnapshot; out ATotal: Integer): Integer;
var
  V, Item, M: TJSONValue;
  Root, Comp: TJSONObject;
  Comps, Measures: TJSONArray;
  Path: string;
  Lines: Integer;
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
      Lines := 0;
      if Comp.TryGetValue<TJSONArray>('measures', Measures) then
        for M in Measures do
          if (M is TJSONObject) and (TJSONObject(M).GetValue<string>('metric', '') = 'ncloc') then
            Lines := StrToIntDef(TJSONObject(M).GetValue<string>('value', '0'), 0);
      ASnap.AddFile(Path, Lines);
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
    0: Result := 'Não foi possível ligar a ' + NormalizeSonarUrl(AConfig.Url) + '. ' + AFail;
    401: Result := 'O servidor recusou o token (ou exige um token). Confirma-o nas definições.';
    403: Result := 'O token não tem permissão para ler este projeto. Usa um token de utilizador (My Account › Security › ' +
      'User Token), não o de análise do sonar-scanner, de uma conta com a permissão «Browse» no projeto.';
    404: Result := 'Não encontrei o projeto «' + AConfig.ProjectKey + '» neste servidor.';
  else
    Result := Format('O servidor respondeu com o erro %d.', [AStatus]);
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
    Exit('O servidor ainda não tem projetos analisados: corre primeiro o sonar-scanner (ci.bat sonar).');
  Result := 'Chaves que existem: ' + string.Join(', ', Copy(Keys, 0, 5)) + IfThen(Length(Keys) > 5, ', …', '') + '.';
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
    AMessage := 'Indica o endereço do servidor.';
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
    AMessage := 'Ligado ao SonarQube ' + Version + '. Falta indicar a chave do projeto.';
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
  AMessage := 'Ligado ao SonarQube ' + Version + ': projeto «' + AConfig.ProjectKey + '» encontrado.';
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
      Status := HttpGet(AConfig, Format('/api/measures/component_tree?component=%s&metricKeys=ncloc&qualifiers=FIL,UTS&ps=%d&p=%d',
        [Enc(AConfig.ProjectKey), PageSize, Page]), Body, Fail);
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

    // 3) a quality gate (opcional: sem permissao ou sem gate fica desconhecida)
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
    Result := 'Indica o endereço do servidor.'
  else if Trim(AConfig.ProjectKey) = '' then
    Result := 'Indica a chave do projeto no SonarQube.'
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
