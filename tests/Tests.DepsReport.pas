unit Tests.DepsReport;
// Testes do relatorio de dependencias (Markdown e HTML com SVG).

interface

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions, System.JSON, DUnitX.TestFramework, CM.Lang, CM.Deps,
  CM.DepsReport;

type
  [TestFixture]
  TDepsReportTests = class
  private
    FPrevious: TLang;
    FGraph: TDepGraph;
    function Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean = False): TDepInput;
    function Count(const AText, APattern: string): Integer;
    // o objecto T (frases nos quatro idiomas) embutido na pagina
    function PhraseTable(const AHtml: string): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MarkdownHasSummaryTablesAndCycles;
    [Test] procedure MarkdownEscapesTableCells;
    [Test] procedure HtmlHasOneNodePerUnitAndOnePathPerLink;
    [Test] procedure HtmlEscapesNamesAndTheProject;
    [Test] procedure HtmlMarksCycleLinks;
    [Test] procedure ReportFollowsTheActiveLanguage;
    [Test] procedure PageEmbedsEveryPhraseInTheFourLanguages;
    [Test] procedure EveryPhraseIndexInThePageExists;
    [Test] procedure VisibleTextIsTheExportedLanguageAndTheTableHasTheOthers;
    [Test] procedure LanguageButtonsMarkTheExportedLanguage;
    [Test] procedure NodeLabelsCarryTheirNumbersForTheSwitcher;
    [Test] procedure FormatPhrasesKeepTheirPlaceholdersInEveryLanguage;
    [Test] procedure TitleAndHeadingCanBeRebuiltInAnotherLanguage;
    [Test] procedure PhraseTableNeverClosesTheScriptTag;
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

function TDepsReportTests.PhraseTable(const AHtml: string): TJSONObject;
var
  M: TMatch;
begin
  M := TRegEx.Match(AHtml, 'var T=(\{.*?\]\});\(function', [roSingleLine]);
  Assert.IsTrue(M.Success, 'a tabela de frases nao esta na pagina');
  Result := TJSONObject.ParseJSONValue(M.Groups[1].Value) as TJSONObject;
  Assert.IsNotNull(Result, 'a tabela de frases nao e JSON valido');
end;

procedure TDepsReportTests.PageEmbedsEveryPhraseInTheFourLanguages;
var
  T: TJSONObject;
  Code: string;
  Len: Integer;
begin
  T := PhraseTable(DepsHtml(FGraph, 'P', ''));
  try
    Assert.AreEqual<Integer>(4, T.Count);
    Len := (T.GetValue('pt') as TJSONArray).Count;
    Assert.IsTrue(Len > 20, 'todas as frases da pagina');
    for Code in LangCodes do
      Assert.AreEqual(Len, (T.GetValue(Code) as TJSONArray).Count, 'mesmo numero de frases em ' + Code);
  finally
    T.Free;
  end;
end;

procedure TDepsReportTests.EveryPhraseIndexInThePageExists;
var
  Html: string;
  T: TJSONObject;
  M: TMatch;
  Len: Integer;
begin
  Html := DepsHtml(FGraph, 'P', '');
  T := PhraseTable(Html);
  try
    Len := (T.GetValue('en') as TJSONArray).Count;
    Assert.IsTrue(Count(Html, 'data-k="') > 30, 'muitos elementos traduziveis');
    for M in TRegEx.Matches(Html, 'data-k="(\d+)"') do
      Assert.IsTrue(StrToInt(M.Groups[1].Value) < Len, 'indice fora da tabela: ' + M.Value);
    for M in TRegEx.Matches(Html, 'data-ph="(\d+)"') do
      Assert.IsTrue(StrToInt(M.Groups[1].Value) < Len, 'indice do placeholder fora da tabela');
  finally
    T.Free;
  end;
end;

function ArrayHas(AArray: TJSONArray; const AText: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to AArray.Count - 1 do
    if (AArray.Items[I] as TJSONString).Value = AText then
      Exit(True);
  Result := False;
end;

procedure TDepsReportTests.VisibleTextIsTheExportedLanguageAndTheTableHasTheOthers;
var
  Html: string;
  T: TJSONObject;
begin
  SetLang(lgDe);
  Html := DepsHtml(FGraph, 'P', '');
  Assert.Contains(Html, 'lang="de"');
  Assert.Contains(Html, '>Zyklen</h2>', 'o texto visivel esta em alemao');
  T := PhraseTable(Html);
  try
    Assert.IsTrue(ArrayHas(T.GetValue('pt') as TJSONArray, 'Ciclos'));
    Assert.IsTrue(ArrayHas(T.GetValue('en') as TJSONArray, 'Cycles'));
    Assert.IsTrue(ArrayHas(T.GetValue('fr') as TJSONArray, 'Cycles'));
    Assert.IsTrue(ArrayHas(T.GetValue('de') as TJSONArray, 'Zyklen'));
  finally
    T.Free;
  end;
end;

procedure TDepsReportTests.LanguageButtonsMarkTheExportedLanguage;
var
  Html: string;
begin
  SetLang(lgFr);
  Html := DepsHtml(FGraph, 'P', '');
  Assert.AreEqual(4, Count(Html, '<button type="button" data-l="'));
  Assert.AreEqual(1, Count(Html, ' class="on"'));
  Assert.Contains(Html, 'data-l="fr" title="Français" class="on">FR</button>');
  Assert.Contains(Html, 'data-l="pt" title="Português">PT</button>');
end;

procedure TDepsReportTests.NodeLabelsCarryTheirNumbersForTheSwitcher;
var
  Html: string;
begin
  Html := DepsHtml(FGraph, 'P', '');
  // cada unit tem um <title> e um texto com "usa %d · usada por %d": o idioma novo refaz a frase com estes numeros
  Assert.AreEqual(8, Count(Html, ' data-a="'));
  Assert.IsTrue(TRegEx.IsMatch(Html, '<text class="sub" x="[0-9.]+" y="[0-9.]+" data-k="\d+" data-a="\d+,\d+">usa \d+ · usada por \d+</text>'));
end;

procedure TDepsReportTests.FormatPhrasesKeepTheirPlaceholdersInEveryLanguage;
var
  Html, Code: string;
  T: TJSONObject;
  Idx, I: Integer;
  Arr: TJSONArray;
begin
  Html := DepsHtml(FGraph, 'P', '');
  T := PhraseTable(Html);
  try
    Idx := -1;
    Arr := T.GetValue('pt') as TJSONArray;
    for I := 0 to Arr.Count - 1 do
      if (Arr.Items[I] as TJSONString).Value = 'usa %d · usada por %d' then
        Idx := I;
    Assert.IsTrue(Idx >= 0, 'a frase com numeros esta na tabela');
    for Code in LangCodes do
      Assert.AreEqual(2, TRegEx.Matches(((T.GetValue(Code) as TJSONArray).Items[Idx] as TJSONString).Value, '%(\d+:)?d').Count,
        'dois numeros em ' + Code);
  finally
    T.Free;
  end;
end;

procedure TDepsReportTests.TitleAndHeadingCanBeRebuiltInAnotherLanguage;
var
  Html: string;
begin
  Html := DepsHtml(FGraph, 'Meu <Proj>', 'C:\raiz');
  // o titulo e o cabecalho juntam o nome do projecto (que nao se traduz) a frase traduzida
  Assert.Contains(Html, 'data-pre="Meu &lt;Proj&gt; — ">');
  Assert.Contains(Html, 'data-suf=" — Meu &lt;Proj&gt;">');
  Assert.IsFalse(Html.Contains('Meu <Proj>'), 'o nome nunca vai sem escapar');
end;

procedure TDepsReportTests.PhraseTableNeverClosesTheScriptTag;
var
  Html, Tbl: string;
  M: TMatch;
begin
  Html := DepsHtml(FGraph, '</script><b>x', '');
  M := TRegEx.Match(Html, 'var T=(\{.*?\]\});\(function', [roSingleLine]);
  Assert.IsTrue(M.Success);
  Tbl := M.Groups[1].Value;
  Assert.IsFalse(Tbl.Contains('<'), 'a tabela nao leva nenhum "<"');
  Assert.AreEqual(1, Count(Html, '</script>'), 'so o fecho verdadeiro do script');
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
