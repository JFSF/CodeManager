unit CM.Stats;

{ Regras de progresso e estatisticas, calculadas a partir da analise (TProjectScan) e do
  progresso guardado (TProgressState). Uma unit com metodos so fica concluida quando todos
  os seus metodos estao marcados (tal como na checklist HTML). }

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, CM.Analyzer, CM.Store;

type
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
    Layers: TArray<TLayerStat>;
  end;

function UnitDone(AUnit: TUnitInfo; AState: TProgressState): Boolean;
function MethodsDoneCount(AUnit: TUnitInfo; AState: TProgressState): Integer;
function ComputeStats(AScan: TProjectScan; AState: TProgressState): TStats;
// O progresso antigo identificava os metodos so pelo nome ('Resize'); agora a chave e qualificada
// ('TFoo.Resize'). Passa as marcas antigas para a chave nova. Devolve True se alterou o progresso.
function MigrateMethodKeys(AScan: TProjectScan; AState: TProgressState): Boolean;

implementation

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
