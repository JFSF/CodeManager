unit Tests.Export.Structure;

// Testes da maquinaria partilhada por todos os formatos de CM.Export: FlattenStructure (a lista
// plana pastas>ficheiros>metodos, pela mesma ordem da vista Mapa), RowProgress (o estado de cada
// linha), ExportHeaderLines e BuildTreeLines/IsLastSibling (os conectores da arvore ASCII).

interface

uses
  System.SysUtils, System.RegularExpressions, DUnitX.TestFramework,
  CM.Analyzer, CM.Store, CM.Export, Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  TExportNamingTests = class
  public
    [Test] procedure FormatNamesAreHumanReadable;
    [Test] procedure FormatExtensionsMatchTheFormat;
    [Test] procedure DefaultFileNameSlugsTheProjectName;
  end;

  [TestFixture]
  TFlattenStructureTests = class
  public
    [Test] procedure FoldersComeBeforeFilesAlphabeticallyAtEachLevel;
    [Test] procedure SortingDoesNotDependOnInsertionOrder;
    [Test] procedure RootFilesAreLastAndAtLevelZero;
    [Test] procedure MethodRowsFollowTheirFileWhenRequested;
    [Test] procedure MethodRowsAreOmittedByDefault;
    [Test] procedure FileCountPerFolderIsRecursive;
    [Test] procedure MIndexIsMinusOneExceptOnMethodRows;
    [Test] procedure NonMethodRowsCarryTheOwningUnit;
    [Test] procedure DirRowsHaveNoUnit;
    [Test] procedure EmptyScanProducesNoRows;
  end;

  [TestFixture]
  TRowProgressTests = class
  public
    [Test] procedure DirRowIsAlwaysDefault;
    [Test] procedure FileRowDoneComesFromUnitDone;
    [Test] procedure FileRowWithoutStateIsAllDefault;
    [Test] procedure FileRowReadsStarCompilaSonarAndNoteFromState;
    [Test] procedure MethodRowReadsItsOwnMarksOnly;
    [Test] procedure MethodRowIgnoresTheFilesStarAndNote;
    [Test] procedure MethodRowWithoutStateIsAllFalse;
  end;

  [TestFixture]
  THeaderLinesTests = class
  public
    [Test] procedure FirstLineIsTheRootPath;
    [Test] procedure SecondLineIsAGeneratedAtTimestamp;
    [Test] procedure ThirdLineUsesSingularForOne;
    [Test] procedure ThirdLineUsesPluralForZeroAndMany;
    [Test] procedure ProgressLineIsOmittedByDefault;
    [Test] procedure ProgressLineShowsDoneCounts;
  end;

  [TestFixture]
  TBuildTreeLinesTests = class
  public
    [Test] procedure RowsMatchFlattenStructureOrder;
    [Test] procedure ConnectorsMarkTheLastSiblingOfEachFolder;
    [Test] procedure GuidesAccumulateForNestedNonLastAncestors;
    [Test] procedure DoneMarksAppearOnlyWhenProgressIsRequested;
    [Test] procedure DirRowsNeverGetADoneMark;
    [Test] procedure FileTextShowsMethodCountWhenMethodsAreOmitted;
    [Test] procedure FileTextOmitsMethodCountWhenMethodsAreIncluded;
    [Test] procedure ProgressTagsAppearInOrder;
    [Test] procedure NoteWithEmbeddedLineBreaksIsFlattened;
  end;

implementation

function RowsSummary(const ARows: TArray<TExportRow>): string;
const
  KindLetter: array[TExportRowKind] of Char = ('D', 'F', 'M');
var
  I: Integer;
  Items: TArray<string>;
begin
  SetLength(Items, Length(ARows));
  for I := 0 to High(ARows) do
    Items[I] := KindLetter[ARows[I].Kind] + IntToStr(ARows[I].Level) + ':' + ARows[I].Name;
  Result := Join(Items);
end;

function FindRow(const ARows: TArray<TExportRow>; AKind: TExportRowKind; const AName: string): TExportRow;
var
  R: TExportRow;
begin
  for R in ARows do
    if (R.Kind = AKind) and (R.Name = AName) then
      Exit(R);
  raise Exception.CreateFmt('linha nao encontrada: %s', [AName]);
end;

{ TExportNamingTests }

procedure TExportNamingTests.FormatNamesAreHumanReadable;
begin
  Assert.AreEqual('Markdown', ExportFormatName(efMarkdown));
  Assert.AreEqual('Texto (árvore)', ExportFormatName(efText));
  Assert.AreEqual('CSV (Excel)', ExportFormatName(efCsv));
  Assert.AreEqual('JSON', ExportFormatName(efJson));
end;

procedure TExportNamingTests.FormatExtensionsMatchTheFormat;
begin
  Assert.AreEqual('.md', ExportFormatExt(efMarkdown));
  Assert.AreEqual('.txt', ExportFormatExt(efText));
  Assert.AreEqual('.csv', ExportFormatExt(efCsv));
  Assert.AreEqual('.json', ExportFormatExt(efJson));
end;

procedure TExportNamingTests.DefaultFileNameSlugsTheProjectName;
var
  P: TProjectProfile;
begin
  P := NewProfile('Meu Projeto!');
  try
    Assert.AreEqual('meu-projeto-estrutura.md', ExportDefaultFileName(P, efMarkdown));
    Assert.AreEqual('meu-projeto-estrutura.csv', ExportDefaultFileName(P, efCsv));
  finally
    P.Free;
  end;
end;

{ TFlattenStructureTests }

procedure TFlattenStructureTests.FoldersComeBeforeFilesAlphabeticallyAtEachLevel;
var
  Scan: TProjectScan;
begin
  Scan := BuildSampleScan;
  try
    Assert.AreEqual('D0:Core|D1:Sub|F2:c.pas|F1:a.pas|F1:b.pas|D0:UI|F1:d.pas|F0:root.pas',
      RowsSummary(FlattenStructure(Scan, False)));
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.SortingDoesNotDependOnInsertionOrder;
var
  Scan: TProjectScan;
begin
  // as units entram por ordem propositadamente baralhada (Zeta antes de Alpha, z.pas antes de
  // a.pas): FlattenStructure tem de ordenar de qualquer forma, nao aproveitar a ordem de entrada
  Scan := NewScan(2, [
    MakeUnitInfo('Zeta/z.pas', 'Zeta', []),
    MakeUnitInfo('Alpha/a.pas', 'Alpha', []),
    MakeUnitInfo('z.pas', 'Raiz', []),
    MakeUnitInfo('a.pas', 'Raiz', [])]);
  try
    Assert.AreEqual('D0:Alpha|F1:a.pas|D0:Zeta|F1:z.pas|F0:a.pas|F0:z.pas',
      RowsSummary(FlattenStructure(Scan, False)));
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.RootFilesAreLastAndAtLevelZero;
var
  Scan: TProjectScan;
  Row: TExportRow;
begin
  Scan := BuildSampleScan;
  try
    Row := FindRow(FlattenStructure(Scan, False), xkFile, 'root.pas');
    Assert.AreEqual(0, Row.Level);
    Assert.AreEqual('', Row.U.Dir);
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.MethodRowsFollowTheirFileWhenRequested;
var
  Scan: TProjectScan;
begin
  Scan := BuildSampleScan;
  try
    Assert.AreEqual(
      'D0:Core|D1:Sub|F2:c.pas|M3:TC.Run|F1:a.pas|M2:TA.One|M2:TA.Two|F1:b.pas|D0:UI|F1:d.pas|F0:root.pas',
      RowsSummary(FlattenStructure(Scan, True)));
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.MethodRowsAreOmittedByDefault;
var
  Scan: TProjectScan;
  R: TExportRow;
begin
  Scan := BuildSampleScan;
  try
    for R in FlattenStructure(Scan, False) do
      Assert.IsFalse(R.Kind = xkMethod);
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.FileCountPerFolderIsRecursive;
var
  Scan: TProjectScan;
  Rows: TArray<TExportRow>;
begin
  Scan := BuildSampleScan;
  try
    Rows := FlattenStructure(Scan, False);
    Assert.AreEqual(3, FindRow(Rows, xkDir, 'Core').FileCount);
    Assert.AreEqual(1, FindRow(Rows, xkDir, 'Sub').FileCount);
    Assert.AreEqual(1, FindRow(Rows, xkDir, 'UI').FileCount);
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.MIndexIsMinusOneExceptOnMethodRows;
var
  Scan: TProjectScan;
  Rows: TArray<TExportRow>;
begin
  Scan := BuildSampleScan;
  try
    Rows := FlattenStructure(Scan, True);
    Assert.AreEqual(0, FindRow(Rows, xkMethod, 'TA.One').MIndex);
    Assert.AreEqual(1, FindRow(Rows, xkMethod, 'TA.Two').MIndex);
    Assert.AreEqual(-1, FindRow(Rows, xkFile, 'a.pas').MIndex);
    Assert.AreEqual(-1, FindRow(Rows, xkDir, 'Core').MIndex);
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.NonMethodRowsCarryTheOwningUnit;
var
  Scan: TProjectScan;
  Rows: TArray<TExportRow>;
  FileRow, MethodRow: TExportRow;
begin
  Scan := BuildSampleScan;
  try
    Rows := FlattenStructure(Scan, True);
    FileRow := FindRow(Rows, xkFile, 'a.pas');
    MethodRow := FindRow(Rows, xkMethod, 'TA.One');
    Assert.IsNotNull(FileRow.U);
    Assert.AreEqual(FileRow.U, MethodRow.U, 'a linha de metodo aponta para o mesmo TUnitInfo');
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.DirRowsHaveNoUnit;
var
  Scan: TProjectScan;
begin
  Scan := BuildSampleScan;
  try
    Assert.IsNull(FindRow(FlattenStructure(Scan, False), xkDir, 'Core').U);
  finally
    Scan.Free;
  end;
end;

procedure TFlattenStructureTests.EmptyScanProducesNoRows;
var
  Scan: TProjectScan;
begin
  Scan := NewScan(0, []);
  try
    Assert.AreEqual<NativeInt>(0, Length(FlattenStructure(Scan, True)));
  finally
    Scan.Free;
  end;
end;

{ TRowProgressTests }

procedure TRowProgressTests.DirRowIsAlwaysDefault;
var
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  Row := Default(TExportRow);
  Row.Kind := xkDir;
  Row.U := nil;
  St := TProgressState.Create;
  try
    St.Rec('qualquer-caminho').Star := True;   // nao deve interferir: Row.U = nil e' o que conta
    P := RowProgress(Row, St);
    Assert.IsFalse(P.Done);
    Assert.IsFalse(P.Star);
    Assert.IsFalse(P.Compila);
    Assert.IsFalse(P.Sonar);
    Assert.AreEqual('', P.Note);
  finally
    St.Free;
  end;
end;

procedure TRowProgressTests.FileRowDoneComesFromUnitDone;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar'), Meth('TFoo.Baz')]);
  Row := Default(TExportRow);
  Row.Kind := xkFile;
  Row.U := U;
  St := TProgressState.Create;
  try
    Assert.IsFalse(RowProgress(Row, St).Done);
    St.Rec('a.pas').MDone.Add('TFoo.Bar');
    Assert.IsFalse(RowProgress(Row, St).Done, 'so um dos dois metodos');
    St.Rec('a.pas').MDone.Add('TFoo.Baz');
    Assert.IsTrue(RowProgress(Row, St).Done);
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TRowProgressTests.FileRowWithoutStateIsAllDefault;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', []);
  Row := Default(TExportRow);
  Row.Kind := xkFile;
  Row.U := U;
  St := TProgressState.Create;
  try
    P := RowProgress(Row, St);
    Assert.IsFalse(P.Done);
    Assert.IsFalse(P.Star);
    Assert.IsFalse(P.Compila);
    Assert.IsFalse(P.Sonar);
    Assert.AreEqual('', P.Note);
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TRowProgressTests.FileRowReadsStarCompilaSonarAndNoteFromState;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', []);
  Row := Default(TExportRow);
  Row.Kind := xkFile;
  Row.U := U;
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Star := True;
    St.Rec('a.pas').Compila := True;
    St.Rec('a.pas').Sonar := True;
    St.Rec('a.pas').Note := 'nota';
    P := RowProgress(Row, St);
    Assert.IsTrue(P.Star);
    Assert.IsTrue(P.Compila);
    Assert.IsTrue(P.Sonar);
    Assert.AreEqual('nota', P.Note);
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TRowProgressTests.MethodRowReadsItsOwnMarksOnly;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar'), Meth('TFoo.Baz')]);
  Row := Default(TExportRow);
  Row.Kind := xkMethod;
  Row.U := U;
  Row.MIndex := 0;   // TFoo.Bar
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add('TFoo.Bar');
    St.Rec('a.pas').MCompila.Add('TFoo.Baz');   // do outro metodo: nao deve contar aqui
    P := RowProgress(Row, St);
    Assert.IsTrue(P.Done);
    Assert.IsFalse(P.Compila);
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TRowProgressTests.MethodRowIgnoresTheFilesStarAndNote;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]);
  Row := Default(TExportRow);
  Row.Kind := xkMethod;
  Row.U := U;
  Row.MIndex := 0;
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Star := True;
    St.Rec('a.pas').Note := 'nota do ficheiro';
    P := RowProgress(Row, St);
    Assert.IsFalse(P.Star, 'metodos nao tem prioridade propria');
    Assert.AreEqual('', P.Note, 'metodos nao tem nota propria');
  finally
    St.Free;
    U.Free;
  end;
end;

procedure TRowProgressTests.MethodRowWithoutStateIsAllFalse;
var
  U: TUnitInfo;
  Row: TExportRow;
  St: TProgressState;
  P: TRowProgress;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar')]);
  Row := Default(TExportRow);
  Row.Kind := xkMethod;
  Row.U := U;
  Row.MIndex := 0;
  St := TProgressState.Create;
  try
    P := RowProgress(Row, St);
    Assert.IsFalse(P.Done);
    Assert.IsFalse(P.Compila);
    Assert.IsFalse(P.Sonar);
  finally
    St.Free;
    U.Free;
  end;
end;

{ THeaderLinesTests }

procedure THeaderLinesTests.FirstLineIsTheRootPath;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual('Pasta raiz: C:\Proj', ExportHeaderLines(Scan, St, Opt)[0]);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure THeaderLinesTests.SecondLineIsAGeneratedAtTimestamp;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Assert.IsTrue(TRegEx.IsMatch(ExportHeaderLines(Scan, St, Opt)[1],
      '^Gerado em: \d{4}-\d{2}-\d{2} \d{2}:\d{2}$'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure THeaderLinesTests.ThirdLineUsesSingularForOne;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('X')])]);
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual('1 pasta, 1 ficheiro, 1 método', ExportHeaderLines(Scan, St, Opt)[2]);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure THeaderLinesTests.ThirdLineUsesPluralForZeroAndMany;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := NewScan(0, []);
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual('0 pastas, 0 ficheiros, 0 métodos', ExportHeaderLines(Scan, St, Opt)[2]);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure THeaderLinesTests.ProgressLineIsOmittedByDefault;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := False;
    Assert.AreEqual<NativeInt>(3, Length(ExportHeaderLines(Scan, St, Opt)));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure THeaderLinesTests.ProgressLineShowsDoneCounts;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    // contagens de ficheiros e de metodos deliberadamente diferentes (2 vs 1), para nao passar
    // por coincidencia se os dois campos do Format forem trocados
    St.Rec('root.pas').Done := True;
    St.Rec('Core/b.pas').Done := True;
    St.Rec('Core/a.pas').MDone.Add('TA.One');
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Assert.AreEqual<NativeInt>(4, Length(ExportHeaderLines(Scan, St, Opt)));
    Assert.AreEqual('Progresso: 2/5 ficheiros concluídos, 1/3 métodos revistos',
      ExportHeaderLines(Scan, St, Opt)[3]);
  finally
    St.Free;
    Scan.Free;
  end;
end;

{ TBuildTreeLinesTests }

procedure TBuildTreeLinesTests.RowsMatchFlattenStructureOrder;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Lines: TArray<TTreeLine>;
  Flat: TArray<TExportRow>;
  I: Integer;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Lines := BuildTreeLines(Scan, St, Opt);
    Flat := FlattenStructure(Scan, False);
    Assert.AreEqual<NativeInt>(Length(Flat), Length(Lines));
    for I := 0 to High(Flat) do
      Assert.AreEqual(Flat[I].Name, Lines[I].Row.Name);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.ConnectorsMarkTheLastSiblingOfEachFolder;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Lines: TArray<TTreeLine>;

  function PrefixFor(const AName: string): string;
  var
    L: TTreeLine;
  begin
    for L in Lines do
      if L.Row.Name = AName then
        Exit(L.Prefix);
    raise Exception.CreateFmt('nao encontrado: %s', [AName]);
  end;

begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Lines := BuildTreeLines(Scan, St, Opt);
    // traçado a mao a partir do algoritmo (ver IsLastSibling/BuildTreeLines em CM.Export):
    // Core, Sub e UI nao sao os ultimos das suas pastas; b.pas, d.pas, c.pas e root.pas sao
    Assert.AreEqual('+-- ', PrefixFor('Core'));
    Assert.AreEqual('|   +-- ', PrefixFor('Sub'));
    Assert.AreEqual('|   |   \-- ', PrefixFor('c.pas'));
    Assert.AreEqual('|   +-- ', PrefixFor('a.pas'));
    Assert.AreEqual('|   \-- ', PrefixFor('b.pas'));
    Assert.AreEqual('+-- ', PrefixFor('UI'));
    Assert.AreEqual('|   \-- ', PrefixFor('d.pas'));
    Assert.AreEqual('\-- ', PrefixFor('root.pas'));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.GuidesAccumulateForNestedNonLastAncestors;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Lines: TArray<TTreeLine>;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Lines := BuildTreeLines(Scan, St, Opt);
    for L in Lines do
      if L.Row.Name = 'c.pas' then
      begin
        // Core (nivel 0) e Sub (nivel 1) nao sao os ultimos das suas pastas: ambos com '|   '
        Assert.AreEqual('|   |   \-- ', L.Prefix);
        Assert.AreEqual('|   |           ', L.ContPrefix);
        Exit;
      end;
    Assert.Fail('c.pas nao encontrado');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.DoneMarksAppearOnlyWhenProgressIsRequested;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    St.Rec('root.pas').Done := True;
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := False;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'root.pas' then
        Assert.AreEqual('root.pas', L.Text);

    Opt.IncludeProgress := True;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'root.pas' then
        Assert.AreEqual('[x] root.pas', L.Text);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.DirRowsNeverGetADoneMark;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'Core' then
        Assert.AreEqual('Core/', L.Text, 'pastas nunca levam [x]/[ ]');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.FileTextShowsMethodCountWhenMethodsAreOmitted;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := False;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'a.pas' then
        Assert.AreEqual('a.pas  (2 métodos)', L.Text);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.FileTextOmitsMethodCountWhenMethodsAreIncluded;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'a.pas' then
        Assert.AreEqual('a.pas', L.Text);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.ProgressTagsAppearInOrder;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    St.Rec('root.pas').Compila := True;
    St.Rec('root.pas').Sonar := True;
    St.Rec('root.pas').Star := True;
    St.Rec('root.pas').Note := 'a rever';
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'root.pas' then
        Assert.AreEqual('[ ] root.pas [Compila] [Sonar] (prioritário)  -- nota: a rever', L.Text);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTreeLinesTests.NoteWithEmbeddedLineBreaksIsFlattened;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  L: TTreeLine;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    St.Rec('root.pas').Note := 'linha 1' + #13#10 + 'linha 2' + #10 + 'linha 3';
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    for L in BuildTreeLines(Scan, St, Opt) do
      if L.Row.Name = 'root.pas' then
      begin
        Assert.AreEqual('[ ] root.pas  -- nota: linha 1 linha 2 linha 3', L.Text);
        Assert.IsFalse(L.Text.Contains(#13) or L.Text.Contains(#10));
      end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExportNamingTests);
  TDUnitX.RegisterTestFixture(TFlattenStructureTests);
  TDUnitX.RegisterTestFixture(TRowProgressTests);
  TDUnitX.RegisterTestFixture(THeaderLinesTests);
  TDUnitX.RegisterTestFixture(TBuildTreeLinesTests);

end.
