unit Tests.Analyzer.Scan;

// Testes do varrimento de pastas e da reanalise incremental (ScanProject, RescanFile,
// ReconcileScan) e das funcoes auxiliares de texto do CM.Analyzer.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  DUnitX.TestFramework, CM.Analyzer, Tests.Helpers;

type
  [TestFixture]
  TAnalyzerHelperTests = class
  public
    [Test] procedure ParseExcludeDirsEmptyGivesDefaults;
    [Test] procedure ParseExcludeDirsAcceptsAllSeparators;
    [Test] procedure ParseExcludeDirsIgnoresBlanks;
    [Test] procedure ExcludedDirsTextRoundTrips;
    [Test] procedure DefaultExcludeListIsACopy;
    [Test] procedure SlugOfNormalises;
    [Test] procedure SlugOfEmptyFallsBack;
    [Test] procedure IsSourceFileByExtension;
    [Test] procedure UnitInfoBaseNameAndExt;
  end;

  [TestFixture]
  TScanProjectTests = class
  private
    FDir: TTempDir;
    FScan: TProjectScan;
    procedure Populate;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FindsSourcesSortedByPath;
    [Test] procedure SkipsExcludedFoldersAndOtherExtensions;
    [Test] procedure CustomExcludeListReplacesDefaults;
    [Test] procedure ExcludeMatchIsCaseInsensitive;
    [Test] procedure PathDirFileNameAndLayer;
    [Test] procedure CountsFoldersMethodsAndUnitsWithMethods;
    [Test] procedure FoldersIncludeParentsOfNestedCode;
    [Test] procedure MissingRootRaises;
    [Test] procedure RootWithoutSourcesRaises;
    [Test] procedure ReportsProgress;
    [Test] procedure MethodsAreExtractedPerUnit;
  end;

  [TestFixture]
  TRescanTests = class
  private
    FDir: TTempDir;
    FScan: TProjectScan;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure UnchangedFileIsNone;
    [Test] procedure NewFileIsAddedInSortedPosition;
    [Test] procedure AddedFileReportsAllMethodsAsNew;
    [Test] procedure ChangedFileReportsOnlyNewOrAlteredMethods;
    [Test] procedure ChangedSignatureCountsAsAltered;
    [Test] procedure RemovedMethodChangesWithoutNewMethods;
    [Test] procedure DeletedFileIsRemoved;
    [Test] procedure UnknownMissingFileIsNone;
    [Test] procedure NewFileInsideExcludedFolderIsIgnored;
    [Test] procedure NewFileWithOtherExtensionIsIgnored;
    [Test] procedure TotalsAreRecountedAfterChanges;
    [Test] procedure RelativePathLookupIsCaseInsensitive;
    [Test] procedure ReconcilePicksUpCreatedAndDeletedFiles;
    [Test] procedure ReconcileWithoutChangesReportsNothing;
    [Test] procedure ReconcileHandlesRenamedFolder;
  end;

implementation

function RaisesOnScan(const ARoot: string): Boolean;
begin
  Result := False;
  try
    ScanProject(ARoot, nil).Free;
  except
    on Exception do
      Result := True;
  end;
end;

function UnitWith(const AMethods: array of string): string;
var
  Body: string;
  M: string;
begin
  Body := '';
  for M in AMethods do
    Body := Body + 'procedure ' + M + '; begin end;' + #13#10;
  Result := WrapUnit('', Body);
end;

{ TAnalyzerHelperTests }

procedure TAnalyzerHelperTests.ParseExcludeDirsEmptyGivesDefaults;
begin
  Assert.AreEqual(Join(DefaultExcludeList), Join(ParseExcludeDirs('')));
  Assert.AreEqual(Join(DefaultExcludeList), Join(ParseExcludeDirs('  ,;  ')));
end;

procedure TAnalyzerHelperTests.ParseExcludeDirsAcceptsAllSeparators;
begin
  Assert.AreEqual('a|b|c|d', Join(ParseExcludeDirs('a, b;c' + #13#10 + 'd')));
end;

procedure TAnalyzerHelperTests.ParseExcludeDirsIgnoresBlanks;
begin
  Assert.AreEqual('x|y', Join(ParseExcludeDirs(' x ,, ; y ,')));
end;

procedure TAnalyzerHelperTests.ExcludedDirsTextRoundTrips;
var
  Original: TArray<string>;
begin
  Original := ['foo', 'bar', 'baz'];
  Assert.AreEqual('foo, bar, baz', ExcludedDirsText(Original));
  Assert.AreEqual(Join(Original), Join(ParseExcludeDirs(ExcludedDirsText(Original))));
  Assert.AreEqual(Join(DefaultExcludeList), Join(ParseExcludeDirs(ExcludedDirsText)));
end;

procedure TAnalyzerHelperTests.DefaultExcludeListIsACopy;
var
  A, B: TArray<string>;
begin
  A := DefaultExcludeList;
  A[0] := 'changed';
  B := DefaultExcludeList;
  Assert.AreEqual('.git', B[0]);
end;

procedure TAnalyzerHelperTests.SlugOfNormalises;
begin
  Assert.AreEqual('meu-projeto', SlugOf('Meu Projeto!'));
  Assert.AreEqual('a-b-c', SlugOf('  A___B   C  '));
  Assert.AreEqual('abc123', SlugOf('ABC123'));
  Assert.AreEqual('x', SlugOf('--x--'));
end;

procedure TAnalyzerHelperTests.SlugOfEmptyFallsBack;
begin
  Assert.AreEqual('projecto', SlugOf(''));
  Assert.AreEqual('projecto', SlugOf('!!!'));
end;

procedure TAnalyzerHelperTests.IsSourceFileByExtension;
begin
  Assert.IsTrue(IsSourceFile('a.pas'));
  Assert.IsTrue(IsSourceFile('A.PAS'));
  Assert.IsTrue(IsSourceFile('Proj.dpr'));
  Assert.IsTrue(IsSourceFile('Pack.dpk'));
  Assert.IsFalse(IsSourceFile('a.dfm'));
  Assert.IsFalse(IsSourceFile('a.txt'));
  Assert.IsFalse(IsSourceFile('a.pas.bak'));
  Assert.IsFalse(IsSourceFile('pas'));
end;

procedure TAnalyzerHelperTests.UnitInfoBaseNameAndExt;
var
  U: TUnitInfo;
begin
  U := TUnitInfo.Create;
  try
    U.FileName := 'CM.Analyzer.pas';
    Assert.AreEqual('.pas', U.Ext);
    Assert.AreEqual('CM.Analyzer', U.BaseName);
  finally
    U.Free;
  end;
end;

{ TScanProjectTests }

procedure TScanProjectTests.Populate;
begin
  FDir.Write('root.pas', UnitWith(['R1', 'R2']));
  FDir.Write('Core/a.pas', UnitWith(['A1']));
  FDir.Write('Core/Sub/b.pas', UnitWith([]));
  FDir.Write('bin/skip.pas', UnitWith(['Skipped']));
  FDir.Write('Core/__history/old.pas', UnitWith(['Old']));
  FDir.Write('readme.txt', 'procedure Nope;');
  FDir.Write('Core/form.dfm', 'object X');
end;

procedure TScanProjectTests.Setup;
begin
  FDir := TTempDir.Create;
  Populate;
  FScan := ScanProject(FDir.Path, nil);
end;

procedure TScanProjectTests.TearDown;
begin
  FScan.Free;
  FDir.Free;
end;

procedure TScanProjectTests.FindsSourcesSortedByPath;
begin
  Assert.AreEqual('Core/a.pas|Core/Sub/b.pas|root.pas', UnitPaths(FScan));
end;

procedure TScanProjectTests.SkipsExcludedFoldersAndOtherExtensions;
begin
  // bin e __history estao nas pastas ignoradas por omissao; .txt/.dfm nao sao fontes
  Assert.AreEqual<NativeInt>(3, FScan.Units.Count);
end;

procedure TScanProjectTests.CustomExcludeListReplacesDefaults;
var
  Scan: TProjectScan;
begin
  Scan := ScanProject(FDir.Path, ['Core']);
  try
    // 'Core' ignorada; 'bin' ja nao esta na lista, por isso entra
    Assert.AreEqual('bin/skip.pas|root.pas', UnitPaths(Scan));
    Assert.AreEqual('Core', Join(Scan.ExcludeDirs));
  finally
    Scan.Free;
  end;
end;

procedure TScanProjectTests.ExcludeMatchIsCaseInsensitive;
var
  Scan: TProjectScan;
begin
  Scan := ScanProject(FDir.Path, ['CORE', 'BIN', '__HISTORY']);
  try
    Assert.AreEqual('root.pas', UnitPaths(Scan));
  finally
    Scan.Free;
  end;
end;

procedure TScanProjectTests.PathDirFileNameAndLayer;
var
  Root, A, B: TUnitInfo;
begin
  A := FScan.Units[0];
  B := FScan.Units[1];
  Root := FScan.Units[2];

  Assert.AreEqual('', Root.Dir);
  Assert.AreEqual('root.pas', Root.FileName);
  Assert.AreEqual('Raiz', Root.Layer);

  Assert.AreEqual('Core', A.Dir);
  Assert.AreEqual('a.pas', A.FileName);
  Assert.AreEqual('Core', A.Layer);

  Assert.AreEqual('Core/Sub', B.Dir);
  Assert.AreEqual('Sub', B.Layer, 'a camada e a pasta imediata');
end;

procedure TScanProjectTests.CountsFoldersMethodsAndUnitsWithMethods;
begin
  Assert.AreEqual(3, FScan.TotalMethods);        // R1, R2, A1
  Assert.AreEqual(2, FScan.UnitsWithMethods);    // b.pas nao tem metodos
end;

procedure TScanProjectTests.FoldersIncludeParentsOfNestedCode;
var
  Nested: TTempDir;
  Scan: TProjectScan;
begin
  // Core (pai de Core/Sub) e Core/Sub contam ambas; a raiz nao
  Assert.AreEqual(2, FScan.Folders);

  // pais sem codigo proprio tambem contam: Deep, Deep/One e Deep/One/Two
  Nested := TTempDir.Create;
  try
    Nested.Write('Deep/One/Two/x.pas', UnitWith(['X']));
    Scan := ScanProject(Nested.Path, nil);
    try
      Assert.AreEqual(3, Scan.Folders);
    finally
      Scan.Free;
    end;
  finally
    Nested.Free;
  end;
end;

procedure TScanProjectTests.MissingRootRaises;
begin
  Assert.IsTrue(RaisesOnScan(FDir.Full('nao-existe')));
end;

procedure TScanProjectTests.RootWithoutSourcesRaises;
var
  Empty: TTempDir;
begin
  Empty := TTempDir.Create;
  try
    Empty.Write('notes.txt', 'x');
    Assert.IsTrue(RaisesOnScan(Empty.Path));
  finally
    Empty.Free;
  end;
end;

procedure TScanProjectTests.ReportsProgress;
var
  Scan: TProjectScan;
  LastDone, LastTotal, Calls: Integer;
begin
  LastDone := 0;
  LastTotal := 0;
  Calls := 0;
  Scan := ScanProject(FDir.Path, nil,
    procedure(const Msg: string; Done, Total: Integer)
    begin
      Inc(Calls);
      LastDone := Done;
      LastTotal := Total;
    end);
  try
    Assert.IsTrue(Calls >= 4, 'uma chamada inicial + uma por unit');
    Assert.AreEqual(3, LastDone);
    Assert.AreEqual(3, LastTotal);
  finally
    Scan.Free;
  end;
end;

procedure TScanProjectTests.MethodsAreExtractedPerUnit;
begin
  Assert.AreEqual('A1', NamesOf(FScan.Units[0].Methods));
  Assert.AreEqual('', NamesOf(FScan.Units[1].Methods));
  Assert.AreEqual('R1|R2', NamesOf(FScan.Units[2].Methods));
end;

{ TRescanTests }

procedure TRescanTests.Setup;
begin
  FDir := TTempDir.Create;
  FDir.Write('a.pas', UnitWith(['A1', 'A2']));
  FDir.Write('c.pas', UnitWith(['C1']));
  FDir.Write('Sub/x.pas', UnitWith(['X1']));
  FScan := ScanProject(FDir.Path, nil);
end;

procedure TRescanTests.TearDown;
begin
  FScan.Free;
  FDir.Free;
end;

procedure TRescanTests.UnchangedFileIsNone;
begin
  Assert.AreEqual(Ord(rcNone), Ord(RescanFile(FScan, 'a.pas')));
  Assert.AreEqual<NativeInt>(3, FScan.Units.Count);
end;

procedure TRescanTests.NewFileIsAddedInSortedPosition;
begin
  FDir.Write('b.pas', UnitWith(['B1']));
  Assert.AreEqual(Ord(rcAdded), Ord(RescanFile(FScan, 'b.pas')));
  Assert.AreEqual('a.pas|b.pas|c.pas|Sub/x.pas', UnitPaths(FScan));
end;

procedure TRescanTests.AddedFileReportsAllMethodsAsNew;
var
  Change: TScanChange;
begin
  FDir.Write('b.pas', UnitWith(['B1', 'B2']));
  Assert.AreEqual(Ord(rcAdded), Ord(RescanFile(FScan, 'b.pas', Change)));
  Assert.AreEqual('b.pas', Change.Path);
  Assert.AreEqual('B1|B2', Join(Change.NewMethods));
end;

procedure TRescanTests.ChangedFileReportsOnlyNewOrAlteredMethods;
var
  Change: TScanChange;
begin
  FDir.Write('a.pas', UnitWith(['A1', 'A2', 'A3']));
  Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(FScan, 'a.pas', Change)));
  Assert.AreEqual('A3', Join(Change.NewMethods));
  Assert.AreEqual('A1|A2|A3', NamesOf(FScan.Units[0].Methods));
end;

procedure TRescanTests.ChangedSignatureCountsAsAltered;
var
  Change: TScanChange;
begin
  FDir.Write('a.pas', UnitWith(['A1(X: Integer)', 'A2']));
  Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(FScan, 'a.pas', Change)));
  Assert.AreEqual('A1', Join(Change.NewMethods), 'mesmo nome, assinatura diferente');
end;

procedure TRescanTests.RemovedMethodChangesWithoutNewMethods;
var
  Change: TScanChange;
begin
  FDir.Write('a.pas', UnitWith(['A1']));
  Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(FScan, 'a.pas', Change)));
  Assert.AreEqual<NativeInt>(0, Length(Change.NewMethods));
  Assert.AreEqual('A1', NamesOf(FScan.Units[0].Methods));
end;

procedure TRescanTests.DeletedFileIsRemoved;
begin
  FDir.Delete('c.pas');
  Assert.AreEqual(Ord(rcRemoved), Ord(RescanFile(FScan, 'c.pas')));
  Assert.AreEqual('a.pas|Sub/x.pas', UnitPaths(FScan));
end;

procedure TRescanTests.UnknownMissingFileIsNone;
begin
  Assert.AreEqual(Ord(rcNone), Ord(RescanFile(FScan, 'ghost.pas')));
  Assert.AreEqual<NativeInt>(3, FScan.Units.Count);
end;

procedure TRescanTests.NewFileInsideExcludedFolderIsIgnored;
begin
  FDir.Write('bin/gen.pas', UnitWith(['G1']));
  Assert.AreEqual(Ord(rcNone), Ord(RescanFile(FScan, 'bin/gen.pas')));
  Assert.IsTrue(IsPathExcluded(FScan, 'bin/gen.pas'));
  Assert.IsFalse(IsPathExcluded(FScan, 'Sub/x.pas'));
  Assert.IsFalse(IsPathExcluded(FScan, 'bin.pas'), 'so as pastas contam, nao o nome do ficheiro');
end;

procedure TRescanTests.NewFileWithOtherExtensionIsIgnored;
begin
  FDir.Write('notes.txt', 'procedure X;');
  Assert.AreEqual(Ord(rcNone), Ord(RescanFile(FScan, 'notes.txt')));
end;

procedure TRescanTests.TotalsAreRecountedAfterChanges;
begin
  Assert.AreEqual(4, FScan.TotalMethods);
  FDir.Write('a.pas', UnitWith(['A1']));
  RescanFile(FScan, 'a.pas');
  Assert.AreEqual(3, FScan.TotalMethods);
  FDir.Delete('Sub/x.pas');
  RescanFile(FScan, 'Sub/x.pas');
  Assert.AreEqual(2, FScan.TotalMethods);
  Assert.AreEqual(0, FScan.Folders, 'a pasta Sub ja nao tem codigo');
end;

procedure TRescanTests.RelativePathLookupIsCaseInsensitive;
begin
  FDir.Write('a.pas', UnitWith(['A1']));
  // o Windows nao distingue maiusculas: o vigia pode entregar o caminho com outra capitalizacao
  Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(FScan, 'A.PAS')));
  Assert.AreEqual<NativeInt>(3, FScan.Units.Count, 'nao deve criar uma unit duplicada');
end;

procedure TRescanTests.ReconcilePicksUpCreatedAndDeletedFiles;
var
  Changes: TList<TScanChange>;
begin
  FDir.Write('new.pas', UnitWith(['N1']));
  FDir.Delete('c.pas');
  Changes := TList<TScanChange>.Create;
  try
    ReconcileScan(FScan, Changes);
    Assert.AreEqual<NativeInt>(2, Changes.Count);
    Assert.AreEqual(Ord(rcRemoved), Ord(Changes[0].Kind), 'as remocoes vem primeiro');
    Assert.AreEqual('c.pas', Changes[0].Path);
    Assert.AreEqual(Ord(rcAdded), Ord(Changes[1].Kind));
    Assert.AreEqual('new.pas', Changes[1].Path);
    Assert.AreEqual('a.pas|new.pas|Sub/x.pas', UnitPaths(FScan));
  finally
    Changes.Free;
  end;
end;

procedure TRescanTests.ReconcileWithoutChangesReportsNothing;
var
  Changes: TList<TScanChange>;
begin
  Changes := TList<TScanChange>.Create;
  try
    ReconcileScan(FScan, Changes);
    Assert.AreEqual<NativeInt>(0, Changes.Count);
  finally
    Changes.Free;
  end;
end;

procedure TRescanTests.ReconcileHandlesRenamedFolder;
var
  Changes: TList<TScanChange>;
begin
  TDirectory.Move(FDir.Full('Sub'), FDir.Full('Renamed'));
  Changes := TList<TScanChange>.Create;
  try
    ReconcileScan(FScan, Changes);
    Assert.AreEqual<NativeInt>(2, Changes.Count);
    Assert.AreEqual('a.pas|c.pas|Renamed/x.pas', UnitPaths(FScan));
  finally
    Changes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalyzerHelperTests);
  TDUnitX.RegisterTestFixture(TScanProjectTests);
  TDUnitX.RegisterTestFixture(TRescanTests);

end.
