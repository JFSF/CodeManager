unit CM.Stats;

{ Regras de progresso e estatisticas, calculadas a partir da analise (TProjectScan) e do
  progresso guardado (TProgressState). Uma unit com metodos so fica concluida quando todos
  os seus metodos estao marcados (tal como na checklist HTML). }

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, CM.Analyzer, CM.Store;

type
  // estado de revisao de um ficheiro ou metodo (exclusivos). "Feito" e a marca de sempre; os outros
  // dois guardam-se em campos proprios e as paginas HTML ignoram-nos
  TReviewState = (rsPending, rsInReview, rsNeedsChange, rsDone);
  TReviewCounts = array[TReviewState] of Integer;

  // um commit e a sua hora (segundos Unix); o historico do Git, do mais recente para o mais antigo
  TCommitTime = record
    Hash: string;
    Time: Int64;
  end;

  TLayerStat = record
    Name: string;
    Done: Integer;
    Total: Integer;
  end;

  TStats = record
    Folders, Files, DoneFiles: Integer;
    Methods, DoneMethods, UnitsWithMethods: Integer;
    FilesCompila, FilesSonar: Integer;
    MethodsCompila, MethodsSonar: Integer;
    FilesByReview, MethodsByReview: TReviewCounts;
    Layers: TArray<TLayerStat>;
  end;

function UnitDone(AUnit: TUnitInfo; AState: TProgressState): Boolean;
// estado de revisao de um metodo (AState pode ser nil) e de um ficheiro: com metodos, "feito" quando todos o
// estao, "precisa de alteracao" se algum precisa, "em revisao" se algum esta ou ja ha parte feita
function ReviewOfMethod(AState: TUnitState; const AName: string): TReviewState;
function ReviewOfUnit(AUnit: TUnitInfo; AState: TProgressState): TReviewState;
// pendente -> em revisao -> precisa de alteracao -> pendente; um "feito" reabre-se como "precisa de alteracao"
function NextReview(AValue: TReviewState): TReviewState;
function ReviewText(AValue: TReviewState): string;
// ' [Em revisão]' / ' [Precisa de alteração]' para os estados que a caixa [ ] / [x] nao distingue; vazio nos outros
function ReviewTag(AValue: TReviewState): string;
// o commit mais recente feito ate ATime (segundos Unix); '' se nenhum. ATimeline: do mais recente para o mais antigo
function CommitAt(const ATimeline: TArray<TCommitTime>; ATime: Int64): string;
// ficheiros revistos (qualquer estado menos "por rever") que estao em AChanged (caminhos relativos)
function StaleReviews(AScan: TProjectScan; AState: TProgressState; AChanged: THashSet<string>): TArray<TUnitInfo>;
// volta o ficheiro e os seus metodos a "por rever" (mantem Compila, Sonar, prioridade e nota)
procedure ResetReview(AState: TUnitState);
// para os ficheiros revistos sem commit registado, deduz-o da hora da conclusao (Ts, em ms); devolve quantos
function BackfillRevisions(AScan: TProjectScan; AState: TProgressState; const ATimeline: TArray<TCommitTime>): Integer;
// poe o metodo no estado dado (limpa os outros) e recalcula o "feito" do ficheiro
procedure SetMethodReview(AUnit: TUnitInfo; AState: TUnitState; const AName: string; AValue: TReviewState);
// o mesmo para um ficheiro sem metodos
procedure SetFileReview(AState: TUnitState; AValue: TReviewState);
function MethodsDoneCount(AUnit: TUnitInfo; AState: TProgressState): Integer;
function ComputeStats(AScan: TProjectScan; AState: TProgressState): TStats;
// O progresso antigo identificava os metodos so pelo nome ('Resize'); agora a chave e qualificada
// ('TFoo.Resize'). Passa as marcas antigas para a chave nova. Devolve True se alterou o progresso.
function MigrateMethodKeys(AScan: TProjectScan; AState: TProgressState): Boolean;

implementation


uses
  CM.Lang;
function MethodsDoneCount(AUnit: TUnitInfo; AState: TProgressState): Integer;
var
  S: TUnitState;
  M: TMethodInfo;
begin
  Result := 0;
  S := AState.Find(AUnit.Path);
  if S = nil then
    Exit;
  for M in AUnit.Methods do
    if S.MDone.Contains(M.Name) then
      Inc(Result);
end;

function UnitDone(AUnit: TUnitInfo; AState: TProgressState): Boolean;
var
  S: TUnitState;
begin
  if Length(AUnit.Methods) > 0 then
    Exit(MethodsDoneCount(AUnit, AState) = Length(AUnit.Methods));
  S := AState.Find(AUnit.Path);
  Result := (S <> nil) and S.Done;
end;

function ReviewOfMethod(AState: TUnitState; const AName: string): TReviewState;
begin
  Result := rsPending;
  if AState = nil then
    Exit;
  if AState.MDone.Contains(AName) then
    Result := rsDone
  else if AState.MFix.Contains(AName) then
    Result := rsNeedsChange
  else if AState.MWip.Contains(AName) then
    Result := rsInReview;
end;

function ReviewOfUnit(AUnit: TUnitInfo; AState: TProgressState): TReviewState;
var
  S: TUnitState;
  M: TMethodInfo;
  Done, Fix, Wip: Integer;
begin
  S := AState.Find(AUnit.Path);
  if Length(AUnit.Methods) = 0 then
  begin
    if S = nil then Exit(rsPending);
    if S.Done then Exit(rsDone);
    if S.Fix then Exit(rsNeedsChange);
    if S.Wip then Exit(rsInReview);
    Exit(rsPending);
  end;
  Done := 0;
  Fix := 0;
  Wip := 0;
  for M in AUnit.Methods do
    case ReviewOfMethod(S, M.Name) of
      rsDone: Inc(Done);
      rsNeedsChange: Inc(Fix);
      rsInReview: Inc(Wip);
    end;
  if Done = Length(AUnit.Methods) then
    Result := rsDone
  else if Fix > 0 then
    Result := rsNeedsChange
  else if (Wip > 0) or (Done > 0) then
    Result := rsInReview
  else
    Result := rsPending;
end;

function NextReview(AValue: TReviewState): TReviewState;
begin
  case AValue of
    rsPending: Result := rsInReview;
    rsInReview: Result := rsNeedsChange;
    rsNeedsChange: Result := rsPending;
  else
    Result := rsNeedsChange;     // reabre um "feito"
  end;
end;

function ReviewText(AValue: TReviewState): string;
begin
  case AValue of
    rsInReview: Result := Tr('Em revisão');
    rsNeedsChange: Result := Tr('Precisa de alteração');
    rsDone: Result := Tr('Concluído');
  else
    Result := Tr('Por rever');
  end;
end;

function CommitAt(const ATimeline: TArray<TCommitTime>; ATime: Int64): string;
var
  C: TCommitTime;
begin
  for C in ATimeline do
    if C.Time <= ATime then
      Exit(C.Hash);
  Result := '';
end;

function StaleReviews(AScan: TProjectScan; AState: TProgressState; AChanged: THashSet<string>): TArray<TUnitInfo>;
var
  U: TUnitInfo;
  List: TList<TUnitInfo>;
begin
  List := TList<TUnitInfo>.Create;
  try
    for U in AScan.Units do
      if AChanged.Contains(U.Path) and (ReviewOfUnit(U, AState) <> rsPending) then
        List.Add(U);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure ResetReview(AState: TUnitState);
begin
  AState.Done := False;
  AState.Wip := False;
  AState.Fix := False;
  AState.MDone.Clear;
  AState.MWip.Clear;
  AState.MFix.Clear;
  AState.Ts := 0;
  AState.Rev := '';
end;

function BackfillRevisions(AScan: TProjectScan; AState: TProgressState; const ATimeline: TArray<TCommitTime>): Integer;
var
  U: TUnitInfo;
  S: TUnitState;
  Hash: string;
begin
  Result := 0;
  for U in AScan.Units do
  begin
    S := AState.Find(U.Path);
    if (S = nil) or (S.Rev <> '') or (S.Ts <= 0) or (ReviewOfUnit(U, AState) = rsPending) then
      Continue;
    Hash := CommitAt(ATimeline, S.Ts div 1000);
    if Hash <> '' then
    begin
      S.Rev := Hash;
      Inc(Result);
    end;
  end;
end;

function ReviewTag(AValue: TReviewState): string;
begin
  if AValue in [rsInReview, rsNeedsChange] then
    Result := ' [' + ReviewText(AValue) + ']'
  else
    Result := '';
end;

procedure SetMethodReview(AUnit: TUnitInfo; AState: TUnitState; const AName: string; AValue: TReviewState);
var
  M: TMethodInfo;
  WasDone, AllDone: Boolean;
begin
  WasDone := AState.MDone.Contains(AName);
  AState.MDone.Remove(AName);
  AState.MWip.Remove(AName);
  AState.MFix.Remove(AName);
  case AValue of
    rsDone: AState.MDone.Add(AName);
    rsInReview: AState.MWip.Add(AName);
    rsNeedsChange: AState.MFix.Add(AName);
  end;
  AllDone := Length(AUnit.Methods) > 0;
  for M in AUnit.Methods do
    if not AState.MDone.Contains(M.Name) then
      AllDone := False;
  AState.Done := AllDone;
  if (AValue = rsDone) or WasDone then
    AState.Ts := NowMillis;
end;

procedure SetFileReview(AState: TUnitState; AValue: TReviewState);
begin
  AState.Done := AValue = rsDone;
  AState.Wip := AValue = rsInReview;
  AState.Fix := AValue = rsNeedsChange;
  AState.Ts := NowMillis;
end;

function ComputeStats(AScan: TProjectScan; AState: TProgressState): TStats;
var
  U: TUnitInfo;
  S: TUnitState;
  M: TMethodInfo;
  Idx: Integer;
  Index: TDictionary<string, Integer>;
  L: TLayerStat;
  Layers: TList<TLayerStat>;
begin
  Result := Default(TStats);
  Result.Folders := AScan.Folders;
  Result.Files := AScan.Units.Count;
  Index := TDictionary<string, Integer>.Create;
  Layers := TList<TLayerStat>.Create;
  try
    for U in AScan.Units do
    begin
      S := AState.Find(U.Path);
      if not Index.TryGetValue(U.Layer, Idx) then
      begin
        L.Name := U.Layer;
        L.Done := 0;
        L.Total := 0;
        Idx := Layers.Add(L);
        Index.Add(U.Layer, Idx);
      end;
      L := Layers[Idx];
      Inc(L.Total);
      Inc(Result.FilesByReview[ReviewOfUnit(U, AState)]);
      if UnitDone(U, AState) then
      begin
        Inc(Result.DoneFiles);
        Inc(L.Done);
      end;
      Layers[Idx] := L;

      if S <> nil then
      begin
        if S.Compila then Inc(Result.FilesCompila);
        if S.Sonar then Inc(Result.FilesSonar);
      end;
      if Length(U.Methods) > 0 then
        Inc(Result.UnitsWithMethods);
      Inc(Result.Methods, Length(U.Methods));
      for M in U.Methods do
        Inc(Result.MethodsByReview[ReviewOfMethod(S, M.Name)]);
      if S <> nil then
        for M in U.Methods do
        begin
          if S.MDone.Contains(M.Name) then Inc(Result.DoneMethods);
          if S.MCompila.Contains(M.Name) then Inc(Result.MethodsCompila);
          if S.MSonar.Contains(M.Name) then Inc(Result.MethodsSonar);
        end;
    end;
    Layers.Sort(TComparer<TLayerStat>.Construct(
      function(const A, B: TLayerStat): Integer
      begin
        Result := CompareText(A.Name, B.Name);
      end));
    Result.Layers := Layers.ToArray;
  finally
    Layers.Free;
    Index.Free;
  end;
end;

procedure MigrateSet(AUnit: TUnitInfo; ASet: THashSet<string>; var AChanged: Boolean);
var
  Current, Legacy: THashSet<string>;
  M: TMethodInfo;
  ToAdd: TList<string>;
  K: string;
begin
  if ASet.Count = 0 then
    Exit;
  Current := THashSet<string>.Create;
  Legacy := THashSet<string>.Create;
  ToAdd := TList<string>.Create;
  try
    for M in AUnit.Methods do
      Current.Add(M.Name);
    for M in AUnit.Methods do
      // so o metodo com o nome "simples" (sem overload) herda a marca do nome antigo
      // (e so se a unit nao tiver tambem uma rotina livre com esse nome: a marca seria dela)
      if (M.Owner <> '') and (Pos('(', M.Name) = 0) and ASet.Contains(M.Simple) and
         not ASet.Contains(M.Name) and not Current.Contains(M.Simple) then
      begin
        ToAdd.Add(M.Name);
        Legacy.Add(M.Simple);
      end;
    for K in ToAdd do
      ASet.Add(K);
    for K in Legacy do
      ASet.Remove(K);
    if ToAdd.Count > 0 then
      AChanged := True;
  finally
    ToAdd.Free;
    Legacy.Free;
    Current.Free;
  end;
end;

function MigrateMethodKeys(AScan: TProjectScan; AState: TProgressState): Boolean;
var
  U: TUnitInfo;
  S: TUnitState;
begin
  Result := False;
  for U in AScan.Units do
  begin
    if Length(U.Methods) = 0 then
      Continue;
    S := AState.Find(U.Path);
    if S = nil then
      Continue;
    MigrateSet(U, S.MDone, Result);
    MigrateSet(U, S.MCompila, Result);
    MigrateSet(U, S.MSonar, Result);
  end;
end;

end.
