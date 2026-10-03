unit Tests.Plan;

// Testes de CM.Plan: leitura tolerante do documento Markdown (ParsePlan) e cruzamento do plano com
// a analise do codigo (MergePlan). Os documentos sao textos em memoria; o cruzamento usa scans
// construidos em memoria (Tests.Helpers), sem tocar em disco.

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, CM.Analyzer, CM.Store, CM.Export, CM.Plan,
  Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  TParsePlanTests = class
  private
    FScan: TProjectScan;
    FWarnings: TArray<string>;
    procedure Parse(const AText: string);
    function Paths: string;
    function Names(const APath: string): string;
    function Find(const APath: string): TUnitInfo;
  public
    [TearDown] procedure TearDown;
    [Test] procedure HeadingWithPathAndPascalBlock;
    [Test] procedure PathInTheFenceInfoString;
    [Test] procedure PathInTheFirstLineComment;
    [Test] procedure UnitNameFallsBackToTheLastFolderHeading;
    [Test] procedure BlockWithoutAnyPathIsIgnoredWithAWarning;
    [Test] procedure ParagraphBetweenHeadingAndBlockKeepsTheFile;
    [Test] procedure UnitNameDifferentFromTheCurrentFileCreatesAnotherFile;
    [Test] procedure ExplicitHeadingPathWinsOverTheUnitName;
    [Test] procedure ProseBulletsThatMentionAFileAreNotFiles;
    [Test] procedure BulletWithAnnotationIsStillAFile;
    [Test] procedure SnippetWithoutInterfaceKeywordIsRead;
    [Test] procedure AsciiTreeListsTheFiles;
    [Test] procedure TopFolderOfATreeIsKeptAsWritten;
    [Test] procedure IndentOnlyTree;
    [Test] procedure HeadingFollowedByMethodBullets;
    [Test] procedure NestedBulletsFromThePathsOfFolders;
    [Test] procedure TaskListBulletsAreAccepted;
    [Test] procedure BackslashPathsAreNormalised;
    [Test] procedure RepeatedMentionsOfAFileAreMerged;
    [Test] procedure UnclosedFenceIsStillRead;
    [Test] procedure OtherFileTypesInTreesAreIgnored;
    [Test] procedure EmptyDocumentWarns;
    [Test] procedure ResultIsSortedByPath;
    [Test] procedure LayerIsTheImmediateFolder;
    [Test] procedure ExportedMarkdownRoundTrips;
  end;

  [TestFixture]
  TMergePlanTests = class
  private
    FCode, FPlan, FMerged: TProjectScan;
    FSummary: TPlanSummary;
    procedure Merge;
    function Find(const APath: string): TUnitInfo;
  public
    [TearDown] procedure TearDown;
    [Test] procedure SamePathIsImplementedAndKeepsCodeMethods;
    [Test] procedure MethodsOnlyInTheCodeAreExtra;
    [Test] procedure MethodsOnlyInThePlanAreAppendedAsPlanned;
    [Test] procedure PlanFileWithoutMethodsDoesNotJudgeTheCodeMethods;
    [Test] procedure FileOnlyInThePlanIsPlanned;
    [Test] procedure FileOnlyInTheCodeIsExtra;
    [Test] procedure MovedFileIsMatchedByFileName;
    [Test] procedure AmbiguousFileNamesAreNotMatched;
    [Test] procedure PathsAreComparedIgnoringCase;
    [Test] procedure ProjectNameFolderInThePlanIsIgnoredWhenTheCodeLacksIt;
    [Test] procedure RealTopFolderIsKept;
    [Test] procedure ProjectNameFolderOnlyInSomePathsIsStrippedAndDuplicatesMerge;
    [Test] procedure MethodMatchedBySimpleNameWhenUnique;
    [Test] procedure MethodsWithTheSameSimpleNameAreNotGuessed;
    [Test] procedure SummaryCountsFilesAndMethods;
    [Test] procedure CoverageIsPercentageOfThePlan;
    [Test] procedure CoverageIsZeroForAnEmptyPlan;
    [Test] procedure LayerCoverageCountsFilesPerLayer;
    [Test] procedure LayerCoverageIsEmptyWithoutAView;
    [Test] procedure LayerCoverageIgnoresUnitsWithoutPlanStatus;
    [Test] procedure CodeScanIsNotModified;
    [Test] procedure MergedScanIsRecountedAndSorted;
    [Test] procedure MethodStatusOutOfRangeIsNone;
  end;

implementation

// caminhos por ordem alfabetica, para comparar sem depender da ordem dos fixtures
function SortedPaths(AScan: TProjectScan): string;
var
  L: TStringList;
  U: TUnitInfo;
begin
  L := TStringList.Create;
  try
    for U in AScan.Units do
      L.Add(U.Path);
    L.Sort;
    L.Delimiter := '|';
    L.StrictDelimiter := True;
    Result := L.DelimitedText;
  finally
    L.Free;
  end;
end;

function Join(const ALines: array of string): string;
var
  S: string;
begin
  Result := '';
  for S in ALines do
    Result := Result + S + sLineBreak;
end;

{ TParsePlanTests }

procedure TParsePlanTests.TearDown;
begin
  FreeAndNil(FScan);
end;

procedure TParsePlanTests.Parse(const AText: string);
begin
  FreeAndNil(FScan);
  FScan := ParsePlan(AText, FWarnings);
end;

function TParsePlanTests.Paths: string;
begin
  Result := UnitPaths(FScan);
end;

function TParsePlanTests.Find(const APath: string): TUnitInfo;
var
  U: TUnitInfo;
begin
  for U in FScan.Units do
    if U.Path = APath then
      Exit(U);
  Result := nil;
end;

function TParsePlanTests.Names(const APath: string): string;
var
  U: TUnitInfo;
begin
  U := Find(APath);
  if U = nil then
    Exit('(sem unit)');
  Result := NamesOf(U.Methods);
end;

procedure TParsePlanTests.HeadingWithPathAndPascalBlock;
begin
  Parse(Join([
    '# Plano',
    '',
    '## src/Core/CM.A.pas',
    '',
    '```pascal',
    'unit CM.A;',
    'interface',
    'function Foo(X: Integer): string;',
    'procedure Bar;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Core/CM.A.pas', Paths);
  Assert.AreEqual('Foo|Bar', Names('src/Core/CM.A.pas'));
  Assert.AreEqual(0, Integer(Length(FWarnings)));
end;

procedure TParsePlanTests.PathInTheFenceInfoString;
begin
  Parse(Join([
    '```pascal src/UI/CM.X.pas',
    'procedure Run;',
    '```']));
  Assert.AreEqual('src/UI/CM.X.pas', Paths);
  Assert.AreEqual('Run', Names('src/UI/CM.X.pas'));
end;

procedure TParsePlanTests.PathInTheFirstLineComment;
begin
  Parse(Join([
    '```pascal',
    '// src/Services/CM.S.pas',
    'unit CM.S;',
    'interface',
    'procedure Go;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Services/CM.S.pas', Paths);
  Assert.AreEqual('Go', Names('src/Services/CM.S.pas'));
end;

procedure TParsePlanTests.UnitNameFallsBackToTheLastFolderHeading;
begin
  Parse(Join([
    '### src/Core/',
    '',
    '```pascal',
    'unit CM.Z;',
    'interface',
    'procedure Z;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Core/CM.Z.pas', Paths);
end;

procedure TParsePlanTests.BlockWithoutAnyPathIsIgnoredWithAWarning;
begin
  Parse(Join([
    'Um exemplo:',
    '',
    '```pascal',
    'var X: Integer;',
    'procedure Solta;',
    '```']));
  Assert.AreEqual(0, Integer(FScan.Units.Count));
  Assert.IsTrue(Length(FWarnings) >= 1);
  Assert.IsTrue(FWarnings[0].Contains('Linha 3'), 'o aviso indica a linha do bloco');
end;

procedure TParsePlanTests.ParagraphBetweenHeadingAndBlockKeepsTheFile;
begin
  Parse(Join([
    '## src/Services/CM.Pdf.pas',
    '',
    'Exportação direta para PDF, sem passar pela impressora.',
    '',
    '```pascal',
    'unit CM.Pdf;',
    'interface',
    'procedure Exportar;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Services/CM.Pdf.pas', Paths, 'um so ficheiro, na pasta do titulo');
  Assert.AreEqual('Exportar', Names('src/Services/CM.Pdf.pas'));
end;

procedure TParsePlanTests.UnitNameDifferentFromTheCurrentFileCreatesAnotherFile;
begin
  // o segundo bloco nao tem titulo: a unit CM.B nao e o ficheiro anterior (CM.A)
  Parse(Join([
    '### src/Core/',
    '## src/Core/CM.A.pas',
    '```pascal',
    'unit CM.A;',
    'interface',
    'procedure DoA;',
    'implementation',
    'end.',
    '```',
    '',
    '```pascal',
    'unit CM.B;',
    'interface',
    'procedure DoB;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Core/CM.A.pas|src/Core/CM.B.pas', Paths);
  Assert.AreEqual('DoA', Names('src/Core/CM.A.pas'));
  Assert.AreEqual('DoB', Names('src/Core/CM.B.pas'));
end;

procedure TParsePlanTests.ExplicitHeadingPathWinsOverTheUnitName;
begin
  Parse(Join([
    '## src/Core/CM.A.pas',
    '```pascal',
    'unit CM.Outro;',
    'interface',
    'procedure Run;',
    'implementation',
    'end.',
    '```']));
  Assert.AreEqual('src/Core/CM.A.pas', Paths);
end;

procedure TParsePlanTests.ProseBulletsThatMentionAFileAreNotFiles;
begin
  Parse(Join([
    '- `src/Infrastructure/CM.Resources.pas` existe no código mas não está no plano;',
    '- O ficheiro `src/Core/CM.X.pas` e importante',
    '- `src/Core/CM.Real.pas`']));
  Assert.AreEqual('src/Core/CM.Real.pas', Paths);
end;

procedure TParsePlanTests.BulletWithAnnotationIsStillAFile;
begin
  Parse(Join([
    '- `src/A.pas` — leitura do plano',
    '- `src/B.pas` # nota',
    '- `src/C.pas` (novo)',
    '- `src/D.pas`: parser']));
  Assert.AreEqual('src/A.pas|src/B.pas|src/C.pas|src/D.pas', Paths);
end;

procedure TParsePlanTests.SnippetWithoutInterfaceKeywordIsRead;
begin
  Parse(Join([
    '## src/CM.B.pas',
    '```pascal',
    'function Calc(A, B: Integer): Integer;',
    'procedure TFoo.Run;',
    '```']));
  Assert.AreEqual('Calc|TFoo.Run', Names('src/CM.B.pas'));
end;

procedure TParsePlanTests.AsciiTreeListsTheFiles;
begin
  Parse(Join([
    '```text',
    'src/',
    '├── Core/',
    '│   ├── CM.Analyzer.pas   # analise',
    '│   └── CM.Store.pas',
    '└── UI/',
    '    └── CM.MainForm.pas',
    '```']));
  Assert.AreEqual('src/Core/CM.Analyzer.pas|src/Core/CM.Store.pas|src/UI/CM.MainForm.pas', Paths);
end;

procedure TParsePlanTests.TopFolderOfATreeIsKeptAsWritten;
begin
  Parse(Join([
    '```',
    'CodeManager/',
    '├── src/',
    '│   └── CM.A.pas',
    '└── CM.dpr',
    '```']));
  Assert.AreEqual('CodeManager/CM.dpr|CodeManager/src/CM.A.pas', Paths);
end;

procedure TParsePlanTests.IndentOnlyTree;
begin
  Parse(Join([
    '```',
    'src/',
    '  Core/',
    '    A.pas',
    '  UI/',
    '    B.pas',
    '```']));
  Assert.AreEqual('src/Core/A.pas|src/UI/B.pas', Paths);
end;

procedure TParsePlanTests.HeadingFollowedByMethodBullets;
begin
  Parse(Join([
    '## src/CM.B.pas',
    '- `procedure Run;`',
    '- function Calc(A, B: Integer): Integer',
    '',
    '## src/CM.C.pas',
    '- `procedure Other;`']));
  Assert.AreEqual('src/CM.B.pas|src/CM.C.pas', Paths);
  Assert.AreEqual('Run|Calc', Names('src/CM.B.pas'));
  Assert.AreEqual('Other', Names('src/CM.C.pas'));
end;

procedure TParsePlanTests.NestedBulletsFromThePathsOfFolders;
begin
  Parse(Join([
    '- **`src/`** _(2 ficheiros)_',
    '  - **`Core/`** _(1 ficheiro)_',
    '    - `CM.A.pas`',
    '      - `function Foo(X: Integer): string;`',
    '  - **`UI/`** _(1 ficheiro)_',
    '    - `CM.B.pas`',
    '      - `procedure TB.Show;`']));
  Assert.AreEqual('src/Core/CM.A.pas|src/UI/CM.B.pas', Paths);
  Assert.AreEqual('Foo', Names('src/Core/CM.A.pas'));
  Assert.AreEqual('TB.Show', Names('src/UI/CM.B.pas'));
end;

procedure TParsePlanTests.TaskListBulletsAreAccepted;
begin
  Parse(Join([
    '- **`Core/`**',
    '  - [ ] `CM.A.pas` [Compila] ★ — nota: rever',
    '  - [x] `CM.B.pas`']));
  Assert.AreEqual('Core/CM.A.pas|Core/CM.B.pas', Paths);
end;

procedure TParsePlanTests.BackslashPathsAreNormalised;
begin
  Parse(Join([
    '## src\Core\CM.A.pas',
    '- `procedure Run;`']));
  Assert.AreEqual('src/Core/CM.A.pas', Paths);
end;

procedure TParsePlanTests.RepeatedMentionsOfAFileAreMerged;
begin
  Parse(Join([
    '## src/Core/CM.A.pas',
    '- `procedure One;`',
    '',
    '```pascal src/core/cm.a.pas',
    'procedure Two;',
    '```']));
  Assert.AreEqual(1, Integer(FScan.Units.Count), 'o mesmo ficheiro, ignorando maiusculas');
  Assert.AreEqual('One|Two', Names(FScan.Units[0].Path));
end;

procedure TParsePlanTests.UnclosedFenceIsStillRead;
begin
  Parse(Join([
    '## src/CM.A.pas',
    '```pascal',
    'procedure Aberto;']));
  Assert.AreEqual('Aberto', Names('src/CM.A.pas'));
end;

procedure TParsePlanTests.OtherFileTypesInTreesAreIgnored;
begin
  Parse(Join([
    '```',
    'src/',
    '├── A.pas',
    '├── logo.png',
    '└── notas.md',
    '```']));
  Assert.AreEqual('src/A.pas', Paths);
end;

procedure TParsePlanTests.EmptyDocumentWarns;
begin
  Parse('Apenas texto sem ficheiros.');
  Assert.AreEqual(0, Integer(FScan.Units.Count));
  Assert.IsTrue(Length(FWarnings) >= 1);
end;

procedure TParsePlanTests.ResultIsSortedByPath;
begin
  Parse(Join([
    '## src/Z.pas',
    '## src/A.pas',
    '## lib/M.pas']));
  Assert.AreEqual('lib/M.pas|src/A.pas|src/Z.pas', Paths);
end;

procedure TParsePlanTests.LayerIsTheImmediateFolder;
begin
  Parse('## src/Core/CM.A.pas');
  Assert.AreEqual('Core', Find('src/Core/CM.A.pas').Layer);
  Assert.AreEqual('src/Core', Find('src/Core/CM.A.pas').Dir);
  Assert.AreEqual(2, FScan.Folders);
end;

procedure TParsePlanTests.ExportedMarkdownRoundTrips;
var
  Code: TProjectScan;
  State: TProgressState;
  Profile: TProjectProfile;
  Opt: TExportOptions;
  Md: string;
begin
  // o plano pode ser o proprio Markdown que a aplicacao exporta
  Code := BuildSampleScan;
  State := TProgressState.Create;
  Profile := NewProfile('Demo');
  try
    Opt.IncludeMethods := True;
    Opt.IncludeProgress := False;
    Md := BuildMarkdown(Profile, Code, State, Opt);
    Parse(Md);
    Assert.AreEqual(SortedPaths(Code), SortedPaths(FScan));
    Assert.AreEqual('TA.One|TA.Two', Names('Core/a.pas'));
    Assert.AreEqual('TC.Run', Names('Core/Sub/c.pas'));
    Assert.AreEqual(Code.TotalMethods, FScan.TotalMethods);
  finally
    Profile.Free;
    State.Free;
    Code.Free;
  end;
end;

{ TMergePlanTests }

procedure TMergePlanTests.TearDown;
begin
  FreeAndNil(FMerged);
  FreeAndNil(FPlan);
  FreeAndNil(FCode);
end;

procedure TMergePlanTests.Merge;
begin
  FreeAndNil(FMerged);
  FMerged := MergePlan(FCode, FPlan, FSummary);
end;

function TMergePlanTests.Find(const APath: string): TUnitInfo;
var
  U: TUnitInfo;
begin
  for U in FMerged.Units do
    if U.Path = APath then
      Exit(U);
  Result := nil;
end;

procedure TMergePlanTests.SamePathIsImplementedAndKeepsCodeMethods;
begin
  FPlan := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Two')])]);
  FCode := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Two')])]);
  Merge;
  Assert.AreEqual(1, Integer(FMerged.Units.Count));
  Assert.IsTrue(Find('Core/a.pas').PlanStatus = psImplemented);
  Assert.IsTrue(Find('Core/a.pas').MethodStatus(0) = psImplemented);
  Assert.IsTrue(Find('Core/a.pas').MethodStatus(1) = psImplemented);
end;

procedure TMergePlanTests.MethodsOnlyInTheCodeAreExtra;
begin
  FPlan := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One')])]);
  FCode := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Three')])]);
  Merge;
  Assert.AreEqual('One|Three', NamesOf(Find('Core/a.pas').Methods));
  Assert.IsTrue(Find('Core/a.pas').MethodStatus(1) = psExtra);
end;

procedure TMergePlanTests.MethodsOnlyInThePlanAreAppendedAsPlanned;
begin
  FPlan := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Falta')])]);
  FCode := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Extra')])]);
  Merge;
  Assert.AreEqual('One|Extra|Falta', NamesOf(Find('Core/a.pas').Methods));
  Assert.IsTrue(Find('Core/a.pas').MethodStatus(2) = psPlanned);
end;

procedure TMergePlanTests.PlanFileWithoutMethodsDoesNotJudgeTheCodeMethods;
begin
  // o plano so diz que o ficheiro existe (ex.: veio de uma arvore): os metodos do codigo nao sao "extra"
  FPlan := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [])]);
  FCode := NewScan(1, [MakeUnitInfo('Core/a.pas', 'Core', [Meth('One'), Meth('Two')])]);
  Merge;
  Assert.IsTrue(Find('Core/a.pas').PlanStatus = psImplemented);
  Assert.IsTrue(Find('Core/a.pas').MethodStatus(0) = psNone);
  Assert.AreEqual(0, FSummary.ExtraMethods);
  Assert.AreEqual(0, FSummary.PlannedMethods);
  Assert.AreEqual(2, Integer(Length(Find('Core/a.pas').Methods)));
end;

procedure TMergePlanTests.FileOnlyInThePlanIsPlanned;
begin
  FPlan := NewScan(1, [MakeUnitInfo('Core/novo.pas', 'Core', [Meth('A'), Meth('B')])]);
  FCode := NewScan(0, []);
  Merge;
  Assert.IsTrue(Find('Core/novo.pas').PlanStatus = psPlanned);
  Assert.IsTrue(Find('Core/novo.pas').MethodStatus(0) = psPlanned);
  Assert.IsTrue(Find('Core/novo.pas').MethodStatus(1) = psPlanned);
end;

procedure TMergePlanTests.FileOnlyInTheCodeIsExtra;
begin
  FPlan := NewScan(0, []);
  FCode := NewScan(1, [MakeUnitInfo('Core/solto.pas', 'Core', [Meth('A')])]);
  Merge;
  Assert.IsTrue(Find('Core/solto.pas').PlanStatus = psExtra);
  Assert.IsTrue(Find('Core/solto.pas').MethodStatus(0) = psExtra);
end;

procedure TMergePlanTests.MovedFileIsMatchedByFileName;
begin
  FPlan := NewScan(1, [MakeUnitInfo('src/old/x.pas', 'old', [Meth('One')])]);
  FCode := NewScan(1, [MakeUnitInfo('src/new/x.pas', 'new', [Meth('One')])]);
  Merge;
  Assert.AreEqual(1, Integer(FMerged.Units.Count));
  Assert.AreEqual('src/new/x.pas', FMerged.Units[0].Path);
  Assert.IsTrue(FMerged.Units[0].PlanStatus = psImplemented);
  Assert.AreEqual('src/old/x.pas', FMerged.Units[0].PlannedPath);
  Assert.AreEqual(1, FSummary.ImplementedFiles);
end;

procedure TMergePlanTests.AmbiguousFileNamesAreNotMatched;
begin
  FPlan := NewScan(2, [MakeUnitInfo('a/x.pas', 'a', []), MakeUnitInfo('b/x.pas', 'b', [])]);
  FCode := NewScan(2, [MakeUnitInfo('c/x.pas', 'c', []), MakeUnitInfo('d/x.pas', 'd', [])]);
  Merge;
  Assert.AreEqual(0, FSummary.ImplementedFiles);
  Assert.AreEqual(2, FSummary.MissingFiles);
  Assert.AreEqual(2, FSummary.ExtraFiles);
end;

procedure TMergePlanTests.PathsAreComparedIgnoringCase;
begin
  FPlan := NewScan(1, [MakeUnitInfo('Core/A.pas', 'Core', [])]);
  FCode := NewScan(1, [MakeUnitInfo('core/a.pas', 'core', [])]);
  Merge;
  Assert.AreEqual(1, FSummary.ImplementedFiles);
  Assert.AreEqual(1, Integer(FMerged.Units.Count));
end;

procedure TMergePlanTests.ProjectNameFolderInThePlanIsIgnoredWhenTheCodeLacksIt;
begin
  FPlan := NewScan(2, [MakeUnitInfo('MeuProjeto/src/A.pas', 'src', [Meth('One')]),
    MakeUnitInfo('MeuProjeto/src/B.pas', 'src', [])]);
  FCode := NewScan(1, [MakeUnitInfo('src/A.pas', 'src', [Meth('One')])]);
  Merge;
  Assert.AreEqual(1, FSummary.ImplementedFiles);
  Assert.AreEqual(1, FSummary.MissingFiles);
  Assert.AreEqual(0, FSummary.ExtraFiles);
  Assert.AreEqual('src/A.pas|src/B.pas', UnitPaths(FMerged), 'caminhos do plano ja sem o nome do projecto');
end;

procedure TMergePlanTests.RealTopFolderIsKept;
begin
  // "src" existe no codigo: nao e o nome do projecto
  FPlan := NewScan(1, [MakeUnitInfo('src/A.pas', 'src', []), MakeUnitInfo('src/B.pas', 'src', [])]);
  FCode := NewScan(1, [MakeUnitInfo('src/A.pas', 'src', [])]);
  Merge;
  Assert.AreEqual('src/A.pas|src/B.pas', UnitPaths(FMerged));
  Assert.AreEqual(1, FSummary.ImplementedFiles);
end;

procedure TMergePlanTests.ProjectNameFolderOnlyInSomePathsIsStrippedAndDuplicatesMerge;
begin
  // uma arvore com raiz "Proj/" e titulos relativos a raiz descrevem o mesmo ficheiro
  FPlan := NewScan(2, [MakeUnitInfo('Proj/src/A.pas', 'src', [Meth('One')]),
    MakeUnitInfo('src/A.pas', 'src', [Meth('Two')]),
    MakeUnitInfo('Proj/src/B.pas', 'src', [])]);
  FCode := NewScan(1, [MakeUnitInfo('src/A.pas', 'src', [Meth('One'), Meth('Two')])]);
  Merge;
  Assert.AreEqual(2, FSummary.PlannedFiles, 'A.pas e B.pas (os dois A.pas juntaram-se)');
  Assert.AreEqual(1, FSummary.ImplementedFiles);
  Assert.AreEqual(1, FSummary.MissingFiles);
  Assert.AreEqual(2, FSummary.ImplementedMethods, 'One e Two, vindos das duas mencoes');
  Assert.AreEqual(0, FSummary.ExtraFiles);
end;

procedure TMergePlanTests.MethodMatchedBySimpleNameWhenUnique;
begin
  FPlan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar(Integer)', 'TFoo', 'Bar')])]);
  FCode := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TFoo.Bar', 'TFoo', 'Bar')])]);
  Merge;
  Assert.AreEqual(1, Integer(Length(Find('a.pas').Methods)));
  Assert.IsTrue(Find('a.pas').MethodStatus(0) = psImplemented);
end;

procedure TMergePlanTests.MethodsWithTheSameSimpleNameAreNotGuessed;
begin
  // dois "Run" no codigo e um no plano: nao se adivinha qual e qual
  FPlan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('TX.Run', 'TX', 'Run')])]);
  FCode := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz',
    [Meth('TA.Run', 'TA', 'Run'), Meth('TB.Run', 'TB', 'Run')])]);
  Merge;
  Assert.AreEqual(1, FSummary.MissingMethods);
  Assert.AreEqual(2, FSummary.ExtraMethods);
  Assert.AreEqual(0, FSummary.ImplementedMethods);
end;

procedure TMergePlanTests.SummaryCountsFilesAndMethods;
begin
  FPlan := NewScan(1, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Two'), Meth('Falta')]),
    MakeUnitInfo('b.pas', 'Raiz', [Meth('X'), Meth('Y')]),
    MakeUnitInfo('c.pas', 'Raiz', [])]);
  FCode := NewScan(1, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Two'), Meth('Extra')]),
    MakeUnitInfo('d.pas', 'Raiz', [Meth('Z')])]);
  Merge;
  Assert.AreEqual(3, FSummary.PlannedFiles);
  Assert.AreEqual(1, FSummary.ImplementedFiles);
  Assert.AreEqual(2, FSummary.MissingFiles);
  Assert.AreEqual(1, FSummary.ExtraFiles);
  Assert.AreEqual(5, FSummary.PlannedMethods);
  Assert.AreEqual(2, FSummary.ImplementedMethods);
  Assert.AreEqual(3, FSummary.MissingMethods, 'Falta, X e Y');
  Assert.AreEqual(1, FSummary.ExtraMethods, 'so conta em ficheiros que existem nos dois lados');
end;

procedure TMergePlanTests.CoverageIsPercentageOfThePlan;
begin
  FPlan := NewScan(1, [
    MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Two')]),
    MakeUnitInfo('b.pas', 'Raiz', [Meth('X'), Meth('Y')])]);
  FCode := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('One')])]);
  Merge;
  Assert.AreEqual(50.0, FSummary.FilesCoverage, 0.0001);
  Assert.AreEqual(25.0, FSummary.MethodsCoverage, 0.0001);
end;

procedure TMergePlanTests.CoverageIsZeroForAnEmptyPlan;
begin
  FPlan := NewScan(0, []);
  FCode := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('One')])]);
  Merge;
  Assert.AreEqual(0.0, FSummary.FilesCoverage, 0.0001);
  Assert.AreEqual(0.0, FSummary.MethodsCoverage, 0.0001);
end;

procedure TMergePlanTests.CodeScanIsNotModified;
begin
  FPlan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Falta')])]);
  FCode := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [Meth('One')])]);
  Merge;
  Assert.AreEqual(1, Integer(FCode.Units.Count));
  Assert.AreEqual(1, Integer(Length(FCode.Units[0].Methods)), 'a analise do codigo fica como estava');
  Assert.IsTrue(FCode.Units[0].PlanStatus = psNone);
  Assert.AreEqual(0, Integer(Length(FCode.Units[0].MethodPlan)));
  Assert.IsTrue(FMerged.Units[0] <> FCode.Units[0], 'a vista tem copias das units');
end;

procedure TMergePlanTests.MergedScanIsRecountedAndSorted;
begin
  FPlan := NewScan(1, [MakeUnitInfo('z/b.pas', 'z', [Meth('B1'), Meth('B2')])]);
  FCode := NewScan(1, [MakeUnitInfo('a/a.pas', 'a', [Meth('A1')])]);
  Merge;
  Assert.AreEqual('a/a.pas|z/b.pas', UnitPaths(FMerged));
  Assert.AreEqual(3, FMerged.TotalMethods);
  Assert.AreEqual(2, FMerged.UnitsWithMethods);
  Assert.AreEqual(2, FMerged.Folders);
end;

procedure TMergePlanTests.LayerCoverageCountsFilesPerLayer;
var
  L: TArray<TPlanLayerCoverage>;
begin
  FPlan := NewScan(1, [
    MakeUnitInfo('Core/a.pas', 'Core', []),
    MakeUnitInfo('Core/b.pas', 'Core', []),
    MakeUnitInfo('Core/c.pas', 'Core', []),
    MakeUnitInfo('UI/d.pas', 'UI', [])]);
  FCode := NewScan(1, [
    MakeUnitInfo('Core/a.pas', 'Core', []),
    MakeUnitInfo('Core/x.pas', 'Core', []),
    MakeUnitInfo('UI/d.pas', 'UI', [])]);
  Merge;
  L := PlanLayerCoverage(FMerged);
  Assert.AreEqual(2, Integer(Length(L)));
  Assert.AreEqual('Core', L[0].Layer, 'por ordem de camada');
  Assert.AreEqual(1, L[0].Implemented);
  Assert.AreEqual(2, L[0].Missing, 'b e c');
  Assert.AreEqual(1, L[0].Extra, 'x');
  Assert.AreEqual(3, L[0].Planned);
  Assert.AreEqual(100 / 3, L[0].Coverage, 0.001);
  Assert.AreEqual('UI', L[1].Layer);
  Assert.AreEqual(100.0, L[1].Coverage, 0.001);
end;

procedure TMergePlanTests.LayerCoverageIsEmptyWithoutAView;
var
  L: TPlanLayerCoverage;
begin
  Assert.AreEqual(0, Integer(Length(PlanLayerCoverage(nil))));
  L := Default(TPlanLayerCoverage);
  Assert.AreEqual(0.0, L.Coverage, 0.001, 'sem nada planeado');
end;

procedure TMergePlanTests.LayerCoverageIgnoresUnitsWithoutPlanStatus;
var
  Scan: TProjectScan;
begin
  Scan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [])]);   // vista sem plano: PlanStatus = psNone
  try
    Assert.AreEqual(0, Integer(Length(PlanLayerCoverage(Scan))));
  finally
    Scan.Free;
  end;
end;

procedure TMergePlanTests.MethodStatusOutOfRangeIsNone;
var
  U: TUnitInfo;
begin
  U := MakeUnitInfo('a.pas', 'Raiz', [Meth('One')]);
  try
    Assert.IsTrue(U.MethodStatus(0) = psNone, 'sem plano');
    Assert.IsTrue(U.MethodStatus(-1) = psNone);
    Assert.IsTrue(U.MethodStatus(99) = psNone);
  finally
    U.Free;
  end;
end;

end.
