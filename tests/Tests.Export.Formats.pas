unit Tests.Export.Formats;

// Testes do conteudo gerado por cada formato de CM.Export: Markdown, TXT (arvore ASCII), CSV
// (incluindo o escape de campos, `CsvField`/`CsvLine`) e JSON (a arvore aninhada).

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Generics.Collections, DUnitX.TestFramework,
  CM.Analyzer, CM.Store, CM.Export, Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  TBuildMarkdownTests = class
  public
    [Test] procedure TitleUsesTheProjectName;
    [Test] procedure FolderLinesShowFileCountInPortuguese;
    [Test] procedure FileLinesShowMethodCountOnlyWhenMethodsAreOmitted;
    [Test] procedure MethodLinesShowTheSignature;
    [Test] procedure IndentationIsTwoSpacesPerLevel;
    [Test] procedure ProgressMarksAppearInOrderWhenRequested;
    [Test] procedure NoProgressMarksWhenNotRequested;
  end;

  [TestFixture]
  TBuildTextTests = class
  public
    [Test] procedure FirstLineIsTheTitle;
    [Test] procedure HeaderLinesAppearVerbatimAfterTheTitle;
    [Test] procedure RootFolderLineUsesTheProjectName;
    [Test] procedure TreeLinesAreThePrefixFollowedByTheText;
  end;

  [TestFixture]
  TCsvFieldTests = class
  public
    [Test] procedure PlainTextIsUnchanged;
    [Test] procedure EmptyTextIsUnchanged;
    [Test] procedure LeadingFormulaCharactersGetAnApostrophe;
    [Test] procedure PlusAndAtAlsoGetAnApostrophe;
    [Test] procedure SemicolonTriggersQuoting;
    [Test] procedure DoubleQuoteIsEscapedAndTriggersQuoting;
    [Test] procedure NewlinesTriggerQuoting;
    [Test] procedure FormulaGuardAndQuotingCombine;
  end;

  [TestFixture]
  TCsvLineTests = class
  public
    [Test] procedure FieldsAreJoinedBySemicolon;
    [Test] procedure LineEndsWithCrLf;
    [Test] procedure SingleFieldHasNoSeparator;
  end;

  [TestFixture]
  TBuildCsvTests = class
  public
    [Test] procedure HeaderHasTenColumnsWithoutProgress;
    [Test] procedure HeaderHasFifteenColumnsWithProgress;
    [Test] procedure MethodRowsCarryLinesAndComplexity;
    [Test] procedure FolderRowsAreSkipped;
    [Test] procedure FileRowFieldsWithoutProgress;
    [Test] procedure MethodRowFieldsWithoutProgress;
    [Test] procedure FileRowFieldsWithProgress;
    [Test] procedure MethodRowFieldsLeaveStarAndNoteBlank;
  end;

  [TestFixture]
  TBuildJsonTests = class
  public
    [Test] procedure ResultParsesAsAnObject;
    [Test] procedure RootFieldsMatchTheProfileAndScan;
    [Test] procedure ExcludedFoldersListsTheScansExcludeDirs;
    [Test] procedure TotalsComeFromTheScan;
    [Test] procedure ProgressBlockIsOmittedByDefault;
    [Test] procedure ProgressBlockShowsDoneCounts;
    [Test] procedure FolderNodesNestTheirChildren;
    [Test] procedure FileNodesHaveNoMethodsArrayWhenMethodsAreOmitted;
    [Test] procedure FileNodesNestTheirMethodsWhenRequested;
    [Test] procedure MethodNodesHaveNoStarOrNote;
    [Test] procedure MethodNodesCarryMeasuresOnlyWhenMeasured;
    [Test] procedure FileNodesHaveStarAndNoteWhenProgressIsRequested;
    [Test] procedure RootLevelFilesAppearDirectlyUnderTheTree;
  end;

implementation

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Split([#10]);
end;

function ContainsLine(const AText, ALine: string): Boolean;
var
  L: string;
begin
  for L in Lines(AText) do
    if L = ALine then
      Exit(True);
  Result := False;
end;

{ TBuildMarkdownTests }

procedure TBuildMarkdownTests.TitleUsesTheProjectName;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('Projeto X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual('# Estrutura do código — Projeto X', Lines(BuildMarkdown(P, Scan, St, Opt))[0]);
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.FolderLinesShowFileCountInPortuguese;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Md: string;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Md := BuildMarkdown(P, Scan, St, Opt);
    Assert.IsTrue(ContainsLine(Md, '- **`Core/`** _(3 ficheiros)_'));
    Assert.IsTrue(ContainsLine(Md, '  - **`Sub/`** _(1 ficheiro)_'));
    Assert.IsTrue(ContainsLine(Md, '- **`UI/`** _(1 ficheiro)_'));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.FileLinesShowMethodCountOnlyWhenMethodsAreOmitted;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Md: string;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := False;
    Md := BuildMarkdown(P, Scan, St, Opt);
    Assert.IsTrue(ContainsLine(Md, '  - `a.pas` _(2 métodos)_'));
    Assert.IsTrue(ContainsLine(Md, '    - `c.pas` _(1 método)_'));
    Assert.IsTrue(ContainsLine(Md, '  - `b.pas`'), 'sem metodos, sem sufixo');

    Opt.IncludeMethods := True;
    Md := BuildMarkdown(P, Scan, St, Opt);
    Assert.IsTrue(ContainsLine(Md, '  - `a.pas`'), 'com metodos incluidos, o ficheiro nao repete a contagem');
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.MethodLinesShowTheSignature;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Md: string;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Md := BuildMarkdown(P, Scan, St, Opt);
    Assert.IsTrue(ContainsLine(Md, '    - `procedure TA.One;`'));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.IndentationIsTwoSpacesPerLevel;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Md: string;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Md := BuildMarkdown(P, Scan, St, Opt);
    Assert.IsTrue(ContainsLine(Md, '- **`Core/`** _(3 ficheiros)_'), 'nivel 0: sem indentacao');
    Assert.IsTrue(ContainsLine(Md, '  - **`Sub/`** _(1 ficheiro)_'), 'nivel 1: 2 espacos');
    Assert.IsTrue(ContainsLine(Md, '    - `c.pas` _(1 método)_'), 'nivel 2: 4 espacos');
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.ProgressMarksAppearInOrderWhenRequested;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    St.Rec('root.pas').Compila := True;
    St.Rec('root.pas').Sonar := True;
    St.Rec('root.pas').Star := True;
    St.Rec('root.pas').Note := 'a rever';
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Assert.IsTrue(ContainsLine(BuildMarkdown(P, Scan, St, Opt),
      '- [ ] `root.pas` [Compila] [Sonar] ★ — nota: a rever'));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildMarkdownTests.NoProgressMarksWhenNotRequested;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    St.Rec('root.pas').Compila := True;
    St.Rec('root.pas').Star := True;
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := False;
    Assert.IsTrue(ContainsLine(BuildMarkdown(P, Scan, St, Opt), '- `root.pas`'));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

{ TBuildTextTests }

procedure TBuildTextTests.FirstLineIsTheTitle;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  P := NewProfile('Projeto X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual('Estrutura do código — Projeto X', Lines(BuildText(P, Scan, St, Opt))[0]);
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTextTests.HeaderLinesAppearVerbatimAfterTheTitle;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Header, Body: TArray<string>;
  I: Integer;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Header := ExportHeaderLines(Scan, St, Opt);
    Body := Lines(BuildText(P, Scan, St, Opt));
    for I := 0 to High(Header) do
      Assert.AreEqual(Header[I], Body[I + 1]);
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTextTests.RootFolderLineUsesTheProjectName;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Header, Body: TArray<string>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('Projeto X');
  try
    Opt := Default(TExportOptions);
    Header := ExportHeaderLines(Scan, St, Opt);
    Body := Lines(BuildText(P, Scan, St, Opt));
    // linha 0: titulo; 1..Length(Header): cabecalho; a seguir uma linha em branco; depois 'Nome/'
    Assert.AreEqual('', Body[Length(Header) + 1]);
    Assert.AreEqual('Projeto X/', Body[Length(Header) + 2]);
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildTextTests.TreeLinesAreThePrefixFollowedByTheText;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Header, Body: TArray<string>;
  TreeLines: TArray<TTreeLine>;
  Offset, I: Integer;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Header := ExportHeaderLines(Scan, St, Opt);
    Body := Lines(BuildText(P, Scan, St, Opt));
    TreeLines := BuildTreeLines(Scan, St, Opt);
    Offset := Length(Header) + 3;   // titulo + cabecalho + linha em branco + 'X/'
    for I := 0 to High(TreeLines) do
      Assert.AreEqual(TreeLines[I].Prefix + TreeLines[I].Text, Body[Offset + I]);
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

{ TCsvFieldTests }

procedure TCsvFieldTests.PlainTextIsUnchanged;
begin
  Assert.AreEqual('abc', CsvField('abc'));
end;

procedure TCsvFieldTests.EmptyTextIsUnchanged;
begin
  Assert.AreEqual('', CsvField(''));
end;

procedure TCsvFieldTests.LeadingFormulaCharactersGetAnApostrophe;
begin
  Assert.AreEqual('''=SUM(A1)', CsvField('=SUM(A1)'));
  Assert.AreEqual('''-1', CsvField('-1'), 'ate um numero negativo leva apostrofo (guarda contra formula)');
end;

procedure TCsvFieldTests.PlusAndAtAlsoGetAnApostrophe;
begin
  Assert.AreEqual('''+1', CsvField('+1'));
  Assert.AreEqual('''@name', CsvField('@name'));
end;

procedure TCsvFieldTests.SemicolonTriggersQuoting;
begin
  Assert.AreEqual('"a;b"', CsvField('a;b'));
end;

procedure TCsvFieldTests.DoubleQuoteIsEscapedAndTriggersQuoting;
begin
  Assert.AreEqual('"a""b"', CsvField('a"b'));
end;

procedure TCsvFieldTests.NewlinesTriggerQuoting;
begin
  Assert.AreEqual('"a' + #13#10 + 'b"', CsvField('a' + #13#10 + 'b'));
  Assert.AreEqual('"a' + #10 + 'b"', CsvField('a' + #10 + 'b'));
end;

procedure TCsvFieldTests.FormulaGuardAndQuotingCombine;
begin
  // primeiro leva o apostrofo (guarda de formula), so depois e' que a presenca de ';' o poe entre aspas
  Assert.AreEqual('"''=a;b"', CsvField('=a;b'));
end;

{ TCsvLineTests }

procedure TCsvLineTests.FieldsAreJoinedBySemicolon;
begin
  Assert.AreEqual('a;b;c' + #13#10, CsvLine(['a', 'b', 'c']));
end;

procedure TCsvLineTests.LineEndsWithCrLf;
begin
  Assert.IsTrue(CsvLine(['a']).EndsWith(#13#10));
end;

procedure TCsvLineTests.SingleFieldHasNoSeparator;
begin
  Assert.AreEqual('a' + #13#10, CsvLine(['a']));
end;

{ TBuildCsvTests }

function CsvRows(const AText: string): TArray<TArray<string>>;
var
  Raw: TArray<string>;
  I: Integer;
begin
  Raw := AText.Split([#13#10]);
  if (Length(Raw) > 0) and (Raw[High(Raw)] = '') then
    SetLength(Raw, Length(Raw) - 1);
  SetLength(Result, Length(Raw));
  for I := 0 to High(Raw) do
    Result[I] := Raw[I].Split([';']);
end;

// devolve a primeira linha que tenha AValue nalgum campo ('Ficheiro' identifica uma linha de
// ficheiro pelo nome; 'Método' precisa do nome qualificado, que so aparece na coluna 'Método')
function FindCsvRow(const ARows: TArray<TArray<string>>; const AValue: string): TArray<string>;
var
  Row: TArray<string>;
  Field: string;
begin
  for Row in ARows do
    for Field in Row do
      if Field = AValue then
        Exit(Row);
  raise Exception.CreateFmt('linha nao encontrada com o valor %s nalgum campo', [AValue]);
end;

procedure TBuildCsvTests.HeaderHasTenColumnsWithoutProgress;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Rows: TArray<TArray<string>>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Rows := CsvRows(BuildCsv(Scan, St, Opt));
    Assert.AreEqual<NativeInt>(10, Length(Rows[0]));
    Assert.AreEqual('Nível;Pasta;Ficheiro;Camada;Classe;Método;Tipo;Assinatura;Linhas;Complexidade',
      string.Join(';', Rows[0]));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.HeaderHasFifteenColumnsWithProgress;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Rows: TArray<TArray<string>>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Rows := CsvRows(BuildCsv(Scan, St, Opt));
    Assert.AreEqual<NativeInt>(15, Length(Rows[0]));
    Assert.AreEqual('Concluído;Compila;Sonar;Prioritário;Nota', string.Join(';', Copy(Rows[0], 10, 5)));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.MethodRowsCarryLinesAndComplexity;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Rows: TArray<TArray<string>>;
  Row: TArray<string>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Scan.Units[0].Methods[0].Lines := 12;
    Scan.Units[0].Methods[0].Complexity := 3;
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Rows := CsvRows(BuildCsv(Scan, St, Opt));
    Row := FindCsvRow(Rows, 'TA.One');
    Assert.AreEqual('12', Row[High(Row) - 1]);      // a assinatura tem ';' e o CsvRows divide por ele
    Assert.AreEqual('3', Row[High(Row)]);
    Row := FindCsvRow(Rows, 'TA.Two');
    Assert.AreEqual('', Row[High(Row) - 1], 'sem corpo medido');
    Assert.AreEqual('', Row[High(Row)]);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.FolderRowsAreSkipped;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Rows: TArray<TArray<string>>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Rows := CsvRows(BuildCsv(Scan, St, Opt));
    // cabecalho + 5 ficheiros + 3 metodos = 9 linhas
    Assert.AreEqual<NativeInt>(9, Length(Rows));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.FileRowFieldsWithoutProgress;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Row: TArray<string>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Row := FindCsvRow(CsvRows(BuildCsv(Scan, St, Opt)), 'a.pas');
    Assert.AreEqual('Ficheiro;Core;a.pas;Core;;;;;;', string.Join(';', Row));
  finally
    St.Free;
    Scan.Free;
  end;
end;

// Row vem de um split ingenuo por ';' (CsvRows nao entende aspas), por isso torna a juntar-se
// exactamente ao texto original (split+join e' identidade); comparar contra CsvLine(Expected)
// evita ter de escapar aspas a mao (a assinatura termina em ';', logo CsvField poe-a entre aspas).
function RawLineOf(const ARow: TArray<string>): string;
begin
  Result := string.Join(';', ARow);
end;

procedure TBuildCsvTests.MethodRowFieldsWithoutProgress;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Row: TArray<string>;
  Expected: string;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Row := FindCsvRow(CsvRows(BuildCsv(Scan, St, Opt)), 'TA.One');
    Expected := CsvLine(['Método', 'Core', 'a.pas', 'Core', 'TA', 'TA.One', 'procedure', 'procedure TA.One;', '', '']);
    Assert.AreEqual(Expected.TrimRight([#13, #10]), RawLineOf(Row));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.FileRowFieldsWithProgress;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Row: TArray<string>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    St.Rec('root.pas').Done := True;
    St.Rec('root.pas').Star := True;
    St.Rec('root.pas').Note := 'nota';
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Row := FindCsvRow(CsvRows(BuildCsv(Scan, St, Opt)), 'root.pas');
    Assert.AreEqual('Ficheiro;;root.pas;Raiz;;;;;;;Sim;Não;Não;Sim;nota', string.Join(';', Row));
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildCsvTests.MethodRowFieldsLeaveStarAndNoteBlank;
var
  Scan: TProjectScan;
  St: TProgressState;
  Opt: TExportOptions;
  Row: TArray<string>;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  try
    St.Rec('Core/a.pas').MDone.Add('TA.One');
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Opt.IncludeProgress := True;
    Row := FindCsvRow(CsvRows(BuildCsv(Scan, St, Opt)), 'TA.One');
    Assert.AreEqual(
      CsvLine(['Método', 'Core', 'a.pas', 'Core', 'TA', 'TA.One', 'procedure', 'procedure TA.One;', '', '',
        'Sim', 'Não', 'Não', '', '']).TrimRight([#13, #10]),
      RawLineOf(Row));
  finally
    St.Free;
    Scan.Free;
  end;
end;

{ TBuildJsonTests }

function ParseObj(const AJson: string): TJSONObject;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AJson);
  Assert.IsTrue(V is TJSONObject, 'a saida deve ser um objecto JSON valido');
  Result := TJSONObject(V);
end;

function FindChildNode(AArr: TJSONArray; const AName: string): TJSONObject;
var
  I: Integer;
  Obj: TJSONObject;
begin
  for I := 0 to AArr.Count - 1 do
  begin
    Obj := TJSONObject(AArr.Items[I]);
    if Obj.GetValue<string>('name') = AName then
      Exit(Obj);
  end;
  raise Exception.CreateFmt('no nao encontrado: %s', [AName]);
end;

procedure TBuildJsonTests.ResultParsesAsAnObject;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Assert.IsNotNull(Root);
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.RootFieldsMatchTheProfileAndScan;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('Projeto X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Opt.IncludeProgress := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Assert.AreEqual('Projeto X', Root.GetValue<string>('project'));
      Assert.AreEqual('C:\Proj', Root.GetValue<string>('root'));
      Assert.IsTrue(Root.GetValue<Boolean>('includesMethods'));
      Assert.IsTrue(Root.GetValue<Boolean>('includesProgress'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.ExcludedFoldersListsTheScansExcludeDirs;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root: TJSONObject;
  Arr: TJSONArray;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Arr := Root.GetValue<TJSONArray>('excludedFolders');
      Assert.AreEqual(2, Arr.Count);
      Assert.AreEqual('bin', Arr.Items[0].Value);
      Assert.AreEqual('obj', Arr.Items[1].Value);
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.TotalsComeFromTheScan;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Totals: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Totals := Root.GetValue<TJSONObject>('totals');
      Assert.AreEqual(3, Totals.GetValue<Integer>('folders'));
      Assert.AreEqual(5, Totals.GetValue<Integer>('files'));
      Assert.AreEqual(3, Totals.GetValue<Integer>('methods'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.ProgressBlockIsOmittedByDefault;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := False;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Assert.IsNull(Root.GetValue('progress'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.ProgressBlockShowsDoneCounts;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Prog: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    St.Rec('root.pas').Done := True;
    St.Rec('Core/a.pas').MDone.Add('TA.One');
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Prog := Root.GetValue<TJSONObject>('progress');
      Assert.AreEqual(1, Prog.GetValue<Integer>('doneFiles'));
      Assert.AreEqual(1, Prog.GetValue<Integer>('doneMethods'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.FolderNodesNestTheirChildren;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Core, Sub: TJSONObject;
  Tree, CoreChildren, SubChildren: TJSONArray;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Tree := Root.GetValue<TJSONArray>('tree');
      Core := FindChildNode(Tree, 'Core');
      Assert.AreEqual('folder', Core.GetValue<string>('type'));
      Assert.AreEqual(3, Core.GetValue<Integer>('files'));
      CoreChildren := Core.GetValue<TJSONArray>('children');
      Sub := FindChildNode(CoreChildren, 'Sub');
      Assert.AreEqual('folder', Sub.GetValue<string>('type'));
      SubChildren := Sub.GetValue<TJSONArray>('children');
      Assert.AreEqual(1, SubChildren.Count);
      Assert.AreEqual('c.pas', TJSONObject(SubChildren.Items[0]).GetValue<string>('name'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.FileNodesHaveNoMethodsArrayWhenMethodsAreOmitted;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Core, AFile: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := False;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Core := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'Core');
      AFile := FindChildNode(Core.GetValue<TJSONArray>('children'), 'a.pas');
      Assert.AreEqual('file', AFile.GetValue<string>('type'));
      Assert.AreEqual(2, AFile.GetValue<Integer>('methodCount'));
      Assert.IsNull(AFile.GetValue('methods'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.FileNodesNestTheirMethodsWhenRequested;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Core, AFile: TJSONObject;
  Methods: TJSONArray;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Core := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'Core');
      AFile := FindChildNode(Core.GetValue<TJSONArray>('children'), 'a.pas');
      Methods := AFile.GetValue<TJSONArray>('methods');
      Assert.AreEqual(2, Methods.Count);
      Assert.AreEqual('TA.One', TJSONObject(Methods.Items[0]).GetValue<string>('name'));
      Assert.AreEqual('TA', TJSONObject(Methods.Items[0]).GetValue<string>('owner'));
      Assert.AreEqual('procedure', TJSONObject(Methods.Items[0]).GetValue<string>('kind'));
      Assert.AreEqual('procedure TA.One;', TJSONObject(Methods.Items[0]).GetValue<string>('signature'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.MethodNodesCarryMeasuresOnlyWhenMeasured;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Core, AFile, M1, M2: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Scan.Units[0].Methods[0].Lines := 12;
    Scan.Units[0].Methods[0].Complexity := 3;
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Core := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'Core');
      AFile := FindChildNode(Core.GetValue<TJSONArray>('children'), 'a.pas');
      M1 := TJSONObject(AFile.GetValue<TJSONArray>('methods').Items[0]);
      M2 := TJSONObject(AFile.GetValue<TJSONArray>('methods').Items[1]);
      Assert.AreEqual(12, M1.GetValue<Integer>('lines'));
      Assert.AreEqual(3, M1.GetValue<Integer>('complexity'));
      Assert.IsNull(M2.GetValue('lines'), 'sem corpo medido');
      Assert.IsNull(M2.GetValue('complexity'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.MethodNodesHaveNoStarOrNote;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, Core, AFile, Method: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Opt.IncludeMethods := True;
    Opt.IncludeProgress := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      Core := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'Core');
      AFile := FindChildNode(Core.GetValue<TJSONArray>('children'), 'a.pas');
      Method := TJSONObject(AFile.GetValue<TJSONArray>('methods').Items[0]);
      Assert.IsNotNull(Method.GetValue('done'));
      Assert.IsNull(Method.GetValue('star'));
      Assert.IsNull(Method.GetValue('note'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.FileNodesHaveStarAndNoteWhenProgressIsRequested;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root, AFile: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    St.Rec('root.pas').Star := True;
    St.Rec('root.pas').Note := 'nota';
    Opt := Default(TExportOptions);
    Opt.IncludeProgress := True;
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      AFile := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'root.pas');
      Assert.IsTrue(AFile.GetValue<Boolean>('star'));
      Assert.AreEqual('nota', AFile.GetValue<string>('note'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildJsonTests.RootLevelFilesAppearDirectlyUnderTheTree;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
  Root: TJSONObject;
  RootFile: TJSONObject;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Root := ParseObj(BuildJson(P, Scan, St, Opt));
    try
      RootFile := FindChildNode(Root.GetValue<TJSONArray>('tree'), 'root.pas');
      Assert.AreEqual('file', RootFile.GetValue<string>('type'));
    finally
      Root.Free;
    end;
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildMarkdownTests);
  TDUnitX.RegisterTestFixture(TBuildTextTests);
  TDUnitX.RegisterTestFixture(TCsvFieldTests);
  TDUnitX.RegisterTestFixture(TCsvLineTests);
  TDUnitX.RegisterTestFixture(TBuildCsvTests);
  TDUnitX.RegisterTestFixture(TBuildJsonTests);

end.
