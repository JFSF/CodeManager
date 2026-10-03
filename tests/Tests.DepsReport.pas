unit Tests.DepsReport;
// Testes do relatorio de dependencias (Markdown e HTML com SVG).

interface

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions, DUnitX.TestFramework, CM.Lang, CM.Deps, CM.DepsReport;

type
  [TestFixture]
  TDepsReportTests = class
  private
    FPrevious: TLang;
    FGraph: TDepGraph;
    function Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean = False): TDepInput;
    function Count(const AText, APattern: string): Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MarkdownHasSummaryTablesAndCycles;
    [Test] procedure MarkdownEscapesTableCells;
    [Test] procedure HtmlHasOneNodePerUnitAndOnePathPerLink;
    [Test] procedure HtmlEscapesNamesAndTheProject;
    [Test] procedure HtmlMarksCycleLinks;
    [Test] procedure ReportFollowsTheActiveLanguage;
    [Test] procedure EmptyGraphStillProducesAReport;
    [Test] procedure DefaultFileNameUsesTheProjectSlug;
    [Test] procedure SavesTheReportAsUtf8;
  end;

implementation

function TDepsReportTests.Inp(const AName, ALayer: string; const AIface, AImpl: array of string;
  AProgram: Boolean): TDepInput;
var
  I: Integer;
begin
  Result := Default(TDepInput);
  Result.Name := AName;
  Result.Path := ALayer + '/' + AName + '.pas';
  Result.Layer := ALayer;
  Result.IsProgram := AProgram;
  Result.Methods := 3;
  Result.Lines := 40;
  Result.MaxComplexity := 7;
  SetLength(Result.InterfaceUses, Length(AIface));
  for I := 0 to High(AIface) do
    Result.InterfaceUses[I] := AIface[I];
  SetLength(Result.ImplUses, Length(AImpl));
  for I := 0 to High(AImpl) do
    Result.ImplUses[I] := AImpl[I];
end;

function TDepsReportTests.Count(const AText, APattern: string): Integer;
begin
  Result := TRegEx.Matches(AText, APattern).Count;
end;

procedure TDepsReportTests.Setup;
begin
  FPrevious := CurrentLang;
  SetLang(lgPt);
  FGraph := BuildDepGraph([
    Inp('App', 'Raiz', ['Forms', 'UI.Main'], [], True),
    Inp('UI.Main', 'UI', ['Core.A'], ['Core.B', 'System.SysUtils']),
    Inp('Core.A', 'Core', [], ['Core.B']),
    Inp('Core.B', 'Core', [], ['Core.A'])]);
end;

procedure TDepsReportTests.TearDown;
begin
  FGraph.Free;
  SetLang(FPrevious);
end;

procedure TDepsReportTests.MarkdownHasSummaryTablesAndCycles;
var
  Md: string;
begin
  Md := DepsMarkdown(FGraph, 'Meu Projeto');
  Assert.Contains(Md, '# Dependências entre units — Meu Projeto');
  Assert.Contains(Md, '- Units: 4');
  Assert.Contains(Md, '- Ciclos: 1');
  Assert.Contains(Md, 'Core.A, Core.B');
  Assert.Contains(Md, '## Mais usadas');
  Assert.Contains(Md, '| `Core.B` | Core | 2 |');
  Assert.Contains(Md, '## Ligações entre camadas');
  Assert.Contains(Md, '| UI | Core | 2 |');
  Assert.Contains(Md, '## Todas as units');
  Assert.Contains(Md, '`System.SysUtils`');
end;

procedure TDepsReportTests.MarkdownEscapesTableCells;
var
  G: TDepGraph;
  Md: string;
begin
  G := BuildDepGraph([Inp('A', 'La|yer', ['B'], []), Inp('B', 'Other', [], [])]);
  try
    Md := DepsMarkdown(G, 'P');
    Assert.Contains(Md, 'La\|yer');
  finally
    G.Free;
  end;
end;

procedure TDepsReportTests.HtmlHasOneNodePerUnitAndOnePathPerLink;
var
  Html: string;
begin
  Html := DepsHtml(FGraph, 'Proj', 'C:\raiz');
  Assert.IsTrue(Html.StartsWith('<!doctype html>'));
  Assert.Contains(Html, '<svg id="g"');
  Assert.AreEqual<Integer>(FGraph.Nodes.Count, Count(Html, '<g class="node" data-i="'));
  Assert.AreEqual<Integer>(FGraph.Edges.Count, Count(Html, '<path class="edge'));
  Assert.Contains(Html, '</html>');
  Assert.Contains(Html, 'lang="pt"');
  // cada camada na legenda
  Assert.Contains(Html, '>Core</span>');
  Assert.Contains(Html, '>UI</span>');
end;

procedure TDepsReportTests.HtmlEscapesNamesAndTheProject;
var
  G: TDepGraph;
  Html: string;
begin
  G := BuildDepGraph([Inp('A<b>', 'X&Y', [], [])]);
  try
    Html := DepsHtml(G, '<script>alert(1)</script>', 'C:\a&b');
    Assert.DoesNotContain(Html, '<script>alert(1)</script>');
    Assert.Contains(Html, '&lt;script&gt;alert(1)&lt;/script&gt;');
    Assert.Contains(Html, 'A&lt;b&gt;');
    Assert.Contains(Html, 'X&amp;Y');
    Assert.Contains(Html, 'C:\a&amp;b');
  finally
    G.Free;
  end;
end;

procedure TDepsReportTests.HtmlMarksCycleLinks;
var
  Html: string;
begin
  Html := DepsHtml(FGraph, 'Proj', '');
  Assert.AreEqual(2, Count(Html, '<path class="edge cyc'), 'Core.A <-> Core.B');
  Assert.Contains(Html, 'tag red');
end;

procedure TDepsReportTests.ReportFollowsTheActiveLanguage;
var
  Html, Md: string;
begin
  SetLang(lgEn);
  Md := DepsMarkdown(FGraph, 'P');
  Html := DepsHtml(FGraph, 'P', '');
  Assert.Contains(Md, '# Dependencies between units — P');
  Assert.Contains(Md, '## Most used');
  Assert.Contains(Html, 'lang="en"');
  Assert.Contains(Html, 'Dependency map');
  SetLang(lgDe);
  Assert.Contains(DepsMarkdown(FGraph, 'P'), '# Abhängigkeiten zwischen Units — P');
  SetLang(lgFr);
  Assert.Contains(DepsMarkdown(FGraph, 'P'), '# Dépendances entre unités — P');
end;

procedure TDepsReportTests.EmptyGraphStillProducesAReport;
var
  G: TDepGraph;
  Html, Md: string;
begin
  G := BuildDepGraph([]);
  try
    Md := DepsMarkdown(G, 'Vazio');
    Html := DepsHtml(G, 'Vazio', '');
    Assert.Contains(Md, '- Units: 0');
    Assert.Contains(Html, '<svg id="g"');
    Assert.Contains(Html, '</html>');
  finally
    G.Free;
  end;
end;

procedure TDepsReportTests.DefaultFileNameUsesTheProjectSlug;
begin
  Assert.AreEqual('meu-projeto-dependencias.html', DepsDefaultFileName('Meu Projeto', '.html'));
  SetLang(lgEn);
  Assert.AreEqual('meu-projeto-dependencies.md', DepsDefaultFileName('Meu Projeto', '.md'));
end;

procedure TDepsReportTests.SavesTheReportAsUtf8;
var
  Dir, F, Back: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'cm-depsrep-' + TGUID.NewGuid.ToString.Substring(1, 8));
  F := TPath.Combine(TPath.Combine(Dir, 'sub'), 'r.md');
  try
    SaveDepsReport(F, 'Ligações — ação');
    Back := TFile.ReadAllText(F, TEncoding.UTF8);
    Assert.AreEqual('Ligações — ação', Back);
  finally
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDepsReportTests);

end.
