unit Tests.Stats;

// Testes de CM.Stats: regras de conclusao (UnitDone/MethodsDoneCount), estatisticas agregadas
// (ComputeStats) e a migracao de marcas antigas (por nome simples) para a chave qualificada
// (MigrateMethodKeys). Os scans sao construidos em memoria (Tests.Helpers.NewScan/MakeUnitInfo/Meth),
// sem tocar em disco: o que se testa aqui e a logica de CM.Stats, nao a extracao do CM.Analyzer.

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Analyzer, CM.Store, CM.Stats, Tests.Helpers;

type
  [TestFixture]
  TUnitDoneTests = class
  public
    [Test] procedure UnitWithMethodsNeedsAllMarked;
    [Test] procedure UnitWithMethodsAndNoStateIsNotDone;
    [Test] procedure UnitWithoutMethodsUsesDoneFlag;
    [Test] procedure UnitWithoutMethodsAndNoStateIsNotDone;
    [Test] procedure MethodsDoneCountIgnoresUnknownNames;
    [Test] procedure MethodsDoneCountWithoutStateIsZero;
  end;

  [TestFixture]
  TComputeStatsTests = class
  public
    [Test] procedure FoldersAndFilesComeFromTheScan;
    [Test] procedure DoneFilesCountsBothKindsOfUnit;
    [Test] procedure MethodTotalsAcrossUnits;
    [Test] procedure CompilaAndSonarCountFilesRegardlessOfDone;
    [Test] procedure CompilaAndSonarCountMethodsIndependently;
    [Test] procedure UnitsWithMethodsIgnoresEmptyUnits;
    [Test] procedure UnitsWithoutStateDoNotRaise;
    [Test] procedure LayersAreGroupedAndSortedCaseInsensitively;
    [Test] procedure LayerDoneCountsPerLayerNotGlobally;
    [Test] procedure EmptyScanHasNoLayers;
  end;

  [TestFixture]
  TMigrateMethodKeysTests = class
  public
    [Test] procedure PlainLegacyMarkMigratesToQualifiedName;
    [Test] procedure NoLegacyMarkMakesNoChange;
    [Test] procedure AlreadyMigratedMarkIsIdempotent;
    [Test] procedure AmbiguousFreeRoutineWithSameSimpleNameIsNotMigrated;
    [Test] procedure OnlyThePlainOverloadInheritsTheLegacyMark;
    [Test] procedure MigrationappliesToEachSetIndependently;
    [Test] procedure UnitsWithoutMethodsAreSkipped;
    [Test] procedure UnitsWithoutStateAreSkipped;
    [Test] procedure FreeRoutinesAreNeverMigrated;
  end;

implementation

{ TUnitDoneTests }

procedure TUnitDoneTests.UnitWithMethodsNeedsAllMarked;
var
  U: TUnitInfo;
  St: TProgressState;
  S: TUnitState;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar'), Meth('TFoo.Baz')]);
  St := TProgressState.Create;
  try
    S := St.Rec('a.pas');
    S.MDone.Add('TFoo.Bar');
    Assert.IsFalse(UnitDone(U, St), 'so um dos dois metodos esta marcado');
    S.MDone.Add('TFoo.Baz');
    Assert.IsTrue(UnitDone(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TUnitDoneTests.UnitWithMethodsAndNoStateIsNotDone;
var
  U: TUnitInfo;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]);
  St := TProgressState.Create;
  try
    Assert.IsFalse(UnitDone(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TUnitDoneTests.UnitWithoutMethodsUsesDoneFlag;
var
  U: TUnitInfo;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.dfm', 'Raiz', []);
  St := TProgressState.Create;
  try
    Assert.IsFalse(UnitDone(U, St));
    St.Rec('a.dfm').Done := True;
    Assert.IsTrue(UnitDone(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TUnitDoneTests.UnitWithoutMethodsAndNoStateIsNotDone;
var
  U: TUnitInfo;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.dfm', 'Raiz', []);
  St := TProgressState.Create;
  try
    Assert.IsFalse(UnitDone(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TUnitDoneTests.MethodsDoneCountIgnoresUnknownNames;
var
  U: TUnitInfo;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('TFoo.Outro');
    Assert.AreEqual(0, MethodsDoneCount(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TUnitDoneTests.MethodsDoneCountWithoutStateIsZero;
var
  U: TUnitInfo;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]);
  St := TProgressState.Create;
  try
    Assert.AreEqual(0, MethodsDoneCount(U, St));
  finally
    St.Free;
    U.Free;
  end;
end;

{ TComputeStatsTests }

procedure TComputeStatsTests.FoldersAndFilesComeFromTheScan;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(5, [MakeUnitInfo('a.pas', 'Raiz', []), MakeUnitInfo('b.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(5, Stats.Folders);
    Assert.AreEqual(2, Stats.Files);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.DoneFilesCountsBothKindsOfUnit;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  // 'a.pas' conclui por metodos, 'b.dfm' conclui pela flag Done
  Scan := NewScan(0, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]),
    MakeUnitInfo('b.dfm', 'Raiz', []),
    MakeUnitInfo('c.pas', 'Raiz', [Meth('TFoo.Baz')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('TFoo.Bar');
    St.Rec('b.dfm').Done := True;
    // 'c.pas' fica por marcar
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(2, Stats.DoneFiles);
    Assert.AreEqual(3, Stats.Files);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.MethodTotalsAcrossUnits;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar'), Meth('TFoo.Baz')]),
    MakeUnitInfo('b.pas', 'Raiz', [Meth('TQux.Run')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('TFoo.Bar');
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(3, Stats.Methods);
    Assert.AreEqual(1, Stats.DoneMethods);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.CompilaAndSonarCountFilesRegardlessOfDone;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Compila := True;
    St.Rec('a.pas').Sonar := True;
    // 'TFoo.Bar' nao esta marcado como revisto: a unit nao esta concluida
    Stats := ComputeStats(Scan, St);
    Assert.IsFalse(UnitDone(Scan.Units[0], St));
    Assert.AreEqual(1, Stats.FilesCompila);
    Assert.AreEqual(1, Stats.FilesSonar);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.CompilaAndSonarCountMethodsIndependently;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
  S: TUnitState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('A'), Meth('B'), Meth('C')])]);
  St := TProgressState.Create;
  try
    S := St.Rec('a.pas');
    S.MCompila.Add('A');
    S.MCompila.Add('B');
    S.MSonar.Add('C');
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(2, Stats.MethodsCompila);
    Assert.AreEqual(1, Stats.MethodsSonar);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.UnitsWithMethodsIgnoresEmptyUnits;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('A')]),
    MakeUnitInfo('a.dfm', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(1, Stats.UnitsWithMethods);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.UnitsWithoutStateDoNotRaise;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('A'), Meth('B')])]);
  St := TProgressState.Create;
  try
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(0, Stats.DoneMethods);
    Assert.AreEqual(0, Stats.FilesCompila);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.LayersAreGroupedAndSortedCaseInsensitively;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [
    MakeUnitInfo('b/x.pas', 'b', []),
    MakeUnitInfo('A/y.pas', 'A', []),
    MakeUnitInfo('c/z.pas', 'c', [])]);
  St := TProgressState.Create;
  try
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual<NativeInt>(3, Length(Stats.Layers));
    Assert.AreEqual('A', Stats.Layers[0].Name);
    Assert.AreEqual('b', Stats.Layers[1].Name);
    Assert.AreEqual('c', Stats.Layers[2].Name);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.LayerDoneCountsPerLayerNotGlobally;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, [
    MakeUnitInfo('Core/a.pas', 'Core', [Meth('A')]),
    MakeUnitInfo('Core/b.pas', 'Core', [Meth('B')]),
    MakeUnitInfo('UI/c.pas', 'UI', [Meth('C')])]);
  St := TProgressState.Create;
  try
    St.Rec('Core/a.pas').MDone.Add('A');
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual(2, Stats.Layers[0].Total, 'Core');
    Assert.AreEqual(1, Stats.Layers[0].Done, 'Core');
    Assert.AreEqual(1, Stats.Layers[1].Total, 'UI');
    Assert.AreEqual(0, Stats.Layers[1].Done, 'UI');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TComputeStatsTests.EmptyScanHasNoLayers;
var
  Scan: TProjectScan;
  St: TProgressState;
  Stats: TStats;
begin
  Scan := NewScan(0, []);
  St := TProgressState.Create;
  try
    Stats := ComputeStats(Scan, St);
    Assert.AreEqual<NativeInt>(0, Length(Stats.Layers));
    Assert.AreEqual(0, Stats.Files);
  finally
    St.Free;
    Scan.Free;
  end;
end;

{ TMigrateMethodKeysTests }

procedure TMigrateMethodKeysTests.PlainLegacyMarkMigratesToQualifiedName;
var
  Scan: TProjectScan;
  St: TProgressState;
  Changed: Boolean;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Resize', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('Resize');
    Changed := MigrateMethodKeys(Scan, St);
    Assert.IsTrue(Changed);
    Assert.IsTrue(St.Find('a.pas').MDone.Contains('TFoo.Resize'));
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('Resize'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.NoLegacyMarkMakesNoChange;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Resize', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    Assert.IsFalse(MigrateMethodKeys(Scan, St));
    St.Rec('a.pas').MDone.Add('TFoo.Resize');   // ja na forma qualificada
    Assert.IsFalse(MigrateMethodKeys(Scan, St));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.AlreadyMigratedMarkIsIdempotent;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Resize', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('Resize');
    Assert.IsTrue(MigrateMethodKeys(Scan, St));
    Assert.IsFalse(MigrateMethodKeys(Scan, St), 'a segunda chamada nao encontra mais nada por migrar');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.AmbiguousFreeRoutineWithSameSimpleNameIsNotMigrated;
var
  Scan: TProjectScan;
  St: TProgressState;
  Changed: Boolean;
begin
  // a unit tem TFoo.Resize e tambem uma rotina livre chamada Resize: a marca antiga e ambigua
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz',
    [Meth('TFoo.Resize', 'TFoo', 'Resize'), Meth('Resize')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('Resize');
    Changed := MigrateMethodKeys(Scan, St);
    Assert.IsFalse(Changed);
    Assert.IsTrue(St.Find('a.pas').MDone.Contains('Resize'), 'fica a marcar a rotina livre');
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('TFoo.Resize'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.OnlyThePlainOverloadInheritsTheLegacyMark;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  // 'TFoo.Resize' (primeiro overload, sem parenteses) e 'TFoo.Resize(Integer)' (o segundo)
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz',
    [Meth('TFoo.Resize', 'TFoo', 'Resize'), Meth('TFoo.Resize(Integer)', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('Resize');
    Assert.IsTrue(MigrateMethodKeys(Scan, St));
    Assert.IsTrue(St.Find('a.pas').MDone.Contains('TFoo.Resize'));
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('TFoo.Resize(Integer)'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.MigrationappliesToEachSetIndependently;
var
  Scan: TProjectScan;
  St: TProgressState;
  S: TUnitState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Resize', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    S := St.Rec('a.pas');
    S.MCompila.Add('Resize');    // so a marca de Compila e antiga
    Assert.IsTrue(MigrateMethodKeys(Scan, St));
    Assert.IsTrue(S.MCompila.Contains('TFoo.Resize'));
    Assert.AreEqual<NativeInt>(0, S.MDone.Count);
    Assert.AreEqual<NativeInt>(0, S.MSonar.Count);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.UnitsWithoutMethodsAreSkipped;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.dfm', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    St.Rec('a.dfm').MDone.Add('Resize');
    Assert.IsFalse(MigrateMethodKeys(Scan, St));
    Assert.IsTrue(St.Find('a.dfm').MDone.Contains('Resize'), 'nada para migrar, mas nada se perde');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.UnitsWithoutStateAreSkipped;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Resize', 'TFoo', 'Resize')])]);
  St := TProgressState.Create;
  try
    Assert.IsFalse(MigrateMethodKeys(Scan, St));
    Assert.IsNull(St.Find('a.pas'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TMigrateMethodKeysTests.FreeRoutinesAreNeverMigrated;
var
  Scan: TProjectScan;
  St: TProgressState;
begin
  // Owner = '' na condicao de MigrateSet: uma rotina livre nunca herda nada (nao ha para onde migrar)
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth('Resize')])]);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('Resize');
    Assert.IsFalse(MigrateMethodKeys(Scan, St));
    Assert.IsTrue(St.Find('a.pas').MDone.Contains('Resize'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitDoneTests);
  TDUnitX.RegisterTestFixture(TComputeStatsTests);
  TDUnitX.RegisterTestFixture(TMigrateMethodKeysTests);

end.
