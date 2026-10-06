unit Tests.ClassReport;

// Testes do relatorio das classes e da heranca (CM.ClassReport): Markdown, CSV e nome do ficheiro.

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, CM.Lang, CM.Analyzer, CM.Classes, CM.ClassHierarchy, CM.ClassReport,
  CM.Metrics, Tests.Helpers;

type
  [TestFixture]
  TClassReportTests = class
  private
    FPrevious: TLang;
    FHier: THierarchy;
    FScan: TProjectScan;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MarkdownHasSummaryAndTables;
    [Test] procedure MarkdownMarksMinimumDepths;
    [Test] procedure MarkdownIndentsTheTree;
    [Test] procedure MarkdownFollowsTheActiveLanguage;
    [Test] procedure CsvHasOneLinePerClass;
    [Test] procedure CsvTellsWhetherTheDepthIsExact;
    [Test] procedure DepthTextShowsTheMinimum;
    [Test] procedure FileNameIsASlug;
  end;

implementation

procedure TClassReportTests.Setup;
var
  U: TUnitInfo;
begin
  FPrevious := CurrentLang;
  SetLang(lgPt);
  U := MakeUnitInfo('Core/a.pas', 'Core', [Meth('TBase.Run', 'TBase', 'Run')]);
  U.Classes := ExtractClasses(
    'type TBase = class(TObject) end;' + sLineBreak +
    'type TMid = class(TBase) end;' + sLineBreak +
    'type TLeaf = class(TMid) end;' + sLineBreak +
    'type TOutro = class(TLeaf) end;' + sLineBreak +
    'type TVcl = class(TSomeUnknownControl) end;');
  FScan := NewScan(1, [U]);
  FHier := BuildHierarchy(FScan);
end;

procedure TClassReportTests.TearDown;
begin
  FHier.Free;
  FScan.Free;
  SetLang(FPrevious);
end;

procedure TClassReportTests.MarkdownHasSummaryAndTables;
var
  Md: string;
begin
  Md := ClassesMarkdown(FHier, 'Demo');
  Assert.Contains(Md, '# Classes e herança — Demo');
  Assert.Contains(Md, '## Resumo');
  Assert.Contains(Md, '- Classes: 5');
  Assert.Contains(Md, '## Classes mais profundas');
  Assert.Contains(Md, '## Classes com mais filhas');
  Assert.Contains(Md, '## Árvore de herança');
  Assert.Contains(Md, '`TOutro`');
end;

procedure TClassReportTests.MarkdownMarksMinimumDepths;
var
  Md: string;
begin
  Md := ClassesMarkdown(FHier, 'Demo');
  Assert.Contains(Md, '>=');
  Assert.Contains(Md, 'Com profundidade mínima');
end;

procedure TClassReportTests.MarkdownIndentsTheTree;
var
  Md: string;
begin
  Md := ClassesMarkdown(FHier, 'Demo');
  Assert.Contains(Md, '| `TBase` |');
  Assert.Contains(Md, '| `· TMid` |');
  Assert.Contains(Md, '| `·· TLeaf` |');
end;

procedure TClassReportTests.MarkdownFollowsTheActiveLanguage;
var
  Md: string;
begin
  SetLang(lgEn);
  Md := ClassesMarkdown(FHier, 'Demo');
  Assert.Contains(Md, '## Inheritance tree');
  Assert.Contains(Md, '- Maximum depth:');
  Assert.IsFalse(Md.Contains('Árvore'));
end;

procedure TClassReportTests.CsvHasOneLinePerClass;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := ClassesCsv(FHier);
    Assert.AreEqual<NativeInt>(6, Lines.Count);   // cabecalho + 5 classes
    Assert.Contains(Lines[0], 'Classe');
    Assert.Contains(Lines[0], 'Profundidade');
    Assert.Contains(Lines[1], 'TBase');
  finally
    Lines.Free;
  end;
end;

procedure TClassReportTests.CsvTellsWhetherTheDepthIsExact;
var
  Csv: string;
begin
  Csv := ClassesCsv(FHier);
  Assert.Contains(Csv, 'TVcl');
  Assert.Contains(Csv, 'não');
  Assert.Contains(Csv, 'sim');
end;

procedure TClassReportTests.DepthTextShowsTheMinimum;
begin
  Assert.AreEqual('1', DepthText(FHier.Find('TBase')));
  Assert.AreEqual('>=2', DepthText(FHier.Find('TVcl')));
end;

procedure TClassReportTests.FileNameIsASlug;
begin
  Assert.AreEqual('meu-projeto-classes.md', ClassesFileName('Meu Projeto!', '.md'));
  Assert.AreEqual('projeto-classes.csv', ClassesFileName('', '.csv'));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassReportTests);

end.
