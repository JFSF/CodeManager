unit CM.Store;

{ Persistencia: definicoes da aplicacao, perfis de projecto e progresso da checklist.
  O progresso usa o mesmo formato JSON das paginas HTML geradas pelos scripts originais,
  para que o "Exportar/Importar progresso" seja compativel nos dois sentidos. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils, System.JSON,
  System.DateUtils, CM.SafeFile;

type
  TProjectProfile = class
  public
    Id: string;
    Name: string;
    RootPath: string;
    OutputFolder: string;
    ExcludeDirs: string;      // pastas a ignorar, separadas por virgulas; vazio = as predefinidas
    PlanPath: string;         // documento .md com o plano (estrutura e codigo previstos); vazio = sem plano
    Watch: Boolean;           // acompanhar alteracoes na pasta do projecto
    Finalized: Boolean;
    FinalizedAt: string;
    constructor Create;
  end;

  TAppSettings = class
  private
    FProjects: TObjectList<TProjectProfile>;
    FRecovered: Boolean;
  public
    Theme: string;              // 'light' | 'dark' | '' (segue o Windows)
    ActiveProjectId: string;
    OpenAfterExport: Boolean;
    constructor Create;
    destructor Destroy; override;
    function FindProject(const AId: string): TProjectProfile;
    function AddProject: TProjectProfile;
    procedure RemoveProject(AProject: TProjectProfile);
    procedure Load;
    procedure Save;
    property Projects: TObjectList<TProjectProfile> read FProjects;
    // a ultima leitura teve de usar a copia de seguranca (o ficheiro estava danificado)
    property RecoveredFromBackup: Boolean read FRecovered;
  end;

  TUnitState = class
  public
    Done: Boolean;
    Star: Boolean;
    Compila: Boolean;
    Sonar: Boolean;
    Note: string;
    Ts: Int64;
    MDone: THashSet<string>;   // metodos revistos
    MCompila: THashSet<string>;
    MSonar: THashSet<string>;
    constructor Create;
    destructor Destroy; override;
    function IsEmpty: Boolean;
  end;

  TProgressState = class
  private
    FUnits: TObjectDictionary<string, TUnitState>;
    FRecovered: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const APath: string): TUnitState;
    function Rec(const APath: string): TUnitState;
    procedure Clear;
    function ToJSONString: string;
    procedure LoadFromJSONString(const AJson: string);
    // le um ficheiro qualquer (ex.: progresso importado): estrito, sem copias de seguranca
    procedure LoadFromFile(const AFileName: string);
    // le o ficheiro de progresso guardado pela aplicacao; se estiver danificado usa a copia .bak
    procedure LoadStored(const AFileName: string);
    // grava de forma atomica, mantendo a versao anterior em .bak
    procedure SaveToFile(const AFileName: string);
    property RecoveredFromBackup: Boolean read FRecovered;
  end;

function AppDataDir: string;
function ProgressFileFor(const AProjectId: string): string;
function HistoryFileFor(const AProjectId: string): string;
function NowMillis: Int64;

implementation

const
  SettingsFileName = 'settings.json';

function AppDataDir: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, 'CodeManager');
{$IFDEF DEBUG}
  // testes: CODEMANAGER_DATA redirecciona os dados para outra pasta (nunca em Release)
  if GetEnvironmentVariable('CODEMANAGER_DATA') <> '' then
    Result := GetEnvironmentVariable('CODEMANAGER_DATA');
{$ENDIF}
  ForceDirectories(Result);
end;

function ProgressFileFor(const AProjectId: string): string;
begin
  Result := TPath.Combine(AppDataDir, 'progress-' + AProjectId + '.json');
end;

function HistoryFileFor(const AProjectId: string): string;
begin
  Result := TPath.Combine(AppDataDir, 'history-' + AProjectId + '.json');
end;

function NowMillis: Int64;
begin
  Result := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now), True) * 1000;
end;

function JsonBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V := AObj.GetValue(AName);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean
  else
    Result := ADefault;
end;

{ TProjectProfile }

constructor TProjectProfile.Create;
begin
  inherited;
  Id := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '').ToLower;
end;

{ TAppSettings }

constructor TAppSettings.Create;
begin
  inherited;
  FProjects := TObjectList<TProjectProfile>.Create(True);
  OpenAfterExport := True;
end;

destructor TAppSettings.Destroy;
begin
  FProjects.Free;
  inherited;
end;

function TAppSettings.FindProject(const AId: string): TProjectProfile;
var
  P: TProjectProfile;
begin
  for P in FProjects do
    if P.Id = AId then
      Exit(P);
  Result := nil;
end;

function TAppSettings.AddProject: TProjectProfile;
begin
  Result := TProjectProfile.Create;
  FProjects.Add(Result);
end;

procedure TAppSettings.RemoveProject(AProject: TProjectProfile);
begin
  DeleteDataFile(ProgressFileFor(AProject.Id));
  DeleteDataFile(HistoryFileFor(AProject.Id));
  FProjects.Remove(AProject);
end;

procedure TAppSettings.Load;
var
  FileName, Text: string;
  Root, Item: TJSONValue;
  Obj, PObj: TJSONObject;
  Arr: TJSONArray;
  P: TProjectProfile;
begin
  FileName := TPath.Combine(AppDataDir, SettingsFileName);
  FRecovered := False;
  if not DataFileExists(FileName) then
    Exit;
  Text := ReadJsonFile(FileName, FRecovered);
  Root := TJSONObject.ParseJSONValue(Text);
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Exit;
  end;
  try
    Obj := TJSONObject(Root);
    Theme := Obj.GetValue<string>('theme', '');
    ActiveProjectId := Obj.GetValue<string>('activeProject', '');
    OpenAfterExport := JsonBool(Obj, 'openAfterExport', True);
    FProjects.Clear;
    if Obj.TryGetValue<TJSONArray>('projects', Arr) then
      for Item in Arr do
      begin
        if not (Item is TJSONObject) then
          Continue;
        PObj := TJSONObject(Item);
        P := TProjectProfile.Create;
        P.Id := PObj.GetValue<string>('id', P.Id);
        P.Name := PObj.GetValue<string>('name', '');
        P.RootPath := PObj.GetValue<string>('root', '');
        P.OutputFolder := PObj.GetValue<string>('output', '');
        P.ExcludeDirs := PObj.GetValue<string>('exclude', '');
        P.PlanPath := PObj.GetValue<string>('plan', '');
        P.Watch := JsonBool(PObj, 'watch', False);
        P.Finalized := JsonBool(PObj, 'finalized', False);
        P.FinalizedAt := PObj.GetValue<string>('finalizedAt', '');
        FProjects.Add(P);
      end;
  finally
    Root.Free;
  end;
end;

procedure TAppSettings.Save;
var
  Obj, PObj: TJSONObject;
  Arr: TJSONArray;
  P: TProjectProfile;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('theme', Theme);
    Obj.AddPair('activeProject', ActiveProjectId);
    Obj.AddPair('openAfterExport', TJSONBool.Create(OpenAfterExport));
    Arr := TJSONArray.Create;
    for P in FProjects do
    begin
      PObj := TJSONObject.Create;
      PObj.AddPair('id', P.Id);
      PObj.AddPair('name', P.Name);
      PObj.AddPair('root', P.RootPath);
      PObj.AddPair('output', P.OutputFolder);
      PObj.AddPair('exclude', P.ExcludeDirs);
      PObj.AddPair('plan', P.PlanPath);
      PObj.AddPair('watch', TJSONBool.Create(P.Watch));
      PObj.AddPair('finalized', TJSONBool.Create(P.Finalized));
      PObj.AddPair('finalizedAt', P.FinalizedAt);
      Arr.AddElement(PObj);
    end;
    Obj.AddPair('projects', Arr);
    WriteFileAtomic(TPath.Combine(AppDataDir, SettingsFileName), Obj.ToJSON, TEncoding.UTF8);
  finally
    Obj.Free;
  end;
end;

{ TUnitState }

constructor TUnitState.Create;
begin
  inherited;
  MDone := THashSet<string>.Create;
  MCompila := THashSet<string>.Create;
  MSonar := THashSet<string>.Create;
end;

destructor TUnitState.Destroy;
begin
  MDone.Free;
  MCompila.Free;
  MSonar.Free;
  inherited;
end;

function TUnitState.IsEmpty: Boolean;
begin
  Result := not (Done or Star or Compila or Sonar) and (Note = '') and
    (MDone.Count = 0) and (MCompila.Count = 0) and (MSonar.Count = 0);
end;

{ TProgressState }

constructor TProgressState.Create;
begin
  inherited;
  FUnits := TObjectDictionary<string, TUnitState>.Create([doOwnsValues]);
end;

destructor TProgressState.Destroy;
begin
  FUnits.Free;
  inherited;
end;

procedure TProgressState.Clear;
begin
  FUnits.Clear;
end;

function TProgressState.Find(const APath: string): TUnitState;
begin
  if not FUnits.TryGetValue(APath, Result) then
    Result := nil;
end;

function TProgressState.Rec(const APath: string): TUnitState;
begin
  if not FUnits.TryGetValue(APath, Result) then
  begin
    Result := TUnitState.Create;
    FUnits.Add(APath, Result);
  end;
end;

procedure SetToJson(AParent: TJSONObject; const AKey: string; ASet: THashSet<string>);
var
  Obj: TJSONObject;
  S: string;
begin
  if ASet.Count = 0 then
    Exit;
  Obj := TJSONObject.Create;
  for S in ASet do
    Obj.AddPair(S, TJSONBool.Create(True));
  AParent.AddPair(AKey, Obj);
end;

procedure JsonToSet(AParent: TJSONObject; const AKey: string; ASet: THashSet<string>);
var
  Obj: TJSONObject;
  Pair: TJSONPair;
begin
  ASet.Clear;
  if AParent.TryGetValue<TJSONObject>(AKey, Obj) then
    for Pair in Obj do
      if (Pair.JsonValue is TJSONBool) and TJSONBool(Pair.JsonValue).AsBoolean then
        ASet.Add(Pair.JsonString.Value);
end;

function TProgressState.ToJSONString: string;
var
  Root, U: TJSONObject;
  Pair: TPair<string, TUnitState>;
  S: TUnitState;
begin
  Root := TJSONObject.Create;
  try
    for Pair in FUnits do
    begin
      S := Pair.Value;
      if S.IsEmpty then
        Continue;
      U := TJSONObject.Create;
      if S.Done then U.AddPair('done', TJSONBool.Create(True));
      if S.Star then U.AddPair('star', TJSONBool.Create(True));
      if S.Compila then U.AddPair('compila', TJSONBool.Create(True));
      if S.Sonar then U.AddPair('sonar', TJSONBool.Create(True));
      if S.Note <> '' then U.AddPair('note', S.Note);
      if S.Ts <> 0 then U.AddPair('ts', TJSONNumber.Create(S.Ts));
      SetToJson(U, 'm', S.MDone);
      SetToJson(U, 'mc', S.MCompila);
      SetToJson(U, 'mq', S.MSonar);
      Root.AddPair(Pair.Key, U);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure TProgressState.LoadFromJSONString(const AJson: string);
var
  Root: TJSONValue;
  Obj, U: TJSONObject;
  Pair: TJSONPair;
  S: TUnitState;
  Num: TJSONNumber;
begin
  Root := TJSONObject.ParseJSONValue(AJson);
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    raise Exception.Create('formato invalido');
  end;
  try
    Obj := TJSONObject(Root);
    // aceita o ficheiro exportado pelas paginas HTML: { version, exportedAt, state: {...} }
    if Obj.GetValue('state') is TJSONObject then
      Obj := TJSONObject(Obj.GetValue('state'));
    FUnits.Clear;
    for Pair in Obj do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      U := TJSONObject(Pair.JsonValue);
      S := TUnitState.Create;
      S.Done := JsonBool(U, 'done', False);
      S.Star := JsonBool(U, 'star', False);
      S.Compila := JsonBool(U, 'compila', False);
      S.Sonar := JsonBool(U, 'sonar', False);
      S.Note := U.GetValue<string>('note', '');
      if U.TryGetValue<TJSONNumber>('ts', Num) then
        S.Ts := Trunc(Num.AsDouble);
      JsonToSet(U, 'm', S.MDone);
      JsonToSet(U, 'mc', S.MCompila);
      JsonToSet(U, 'mq', S.MSonar);
      FUnits.AddOrSetValue(Pair.JsonString.Value, S);
    end;
  finally
    Root.Free;
  end;
end;

procedure TProgressState.LoadFromFile(const AFileName: string);
begin
  LoadFromJSONString(TFile.ReadAllText(AFileName, TEncoding.UTF8));
end;

procedure TProgressState.LoadStored(const AFileName: string);
begin
  LoadFromJSONString(ReadJsonFile(AFileName, FRecovered));
end;

procedure TProgressState.SaveToFile(const AFileName: string);
begin
  WriteFileAtomic(AFileName, ToJSONString, TEncoding.UTF8);
end;

end.
