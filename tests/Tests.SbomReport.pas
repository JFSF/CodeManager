unit Tests.SbomReport;

// Testes do relatorio do SBOM (CM.SbomReport): Markdown e HTML com frases nos quatro idiomas.

interface

uses
  System.SysUtils, System.JSON, System.RegularExpressions, DUnitX.TestFramework, CM.Lang, CM.Sbom, CM.SbomReport;

type
  [TestFixture]
  TSbomReportTests = class
  private
    FSbom: TSbom;
    FPrevious: TLang;
    procedure Add(const AName: string; AOrigin: TSbomOrigin; AConfidence: TSbomConfidence; const AHash: string;
      const AUsedBy: array of string);
    function PhraseTable(const AHtml: string): TJSONObject;
    function Count(const AText, APattern: string): Integer;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MarkdownHasTheSections;
    [Test] procedure MarkdownCountsByOrigin;
    [Test] procedure MarkdownListsTheUnconfirmedComponents;
    [Test] procedure MarkdownSaysWhenEverythingIsConfirmed;
    [Test] procedure MarkdownShowsAShortHash;
    [Test] procedure MarkdownFollowsTheActiveLanguage;
    [Test] procedure HtmlHasCardsTablesAndTheLanguageSwitcher;
    [Test] procedure HtmlHasOneRowPerComponent;
    [Test] procedure HtmlEmbedsEveryPhraseInTheFourLanguages;
    [Test] procedure HtmlPhraseIndexesExist;
    [Test] procedure HtmlTextFollowsTheExportedLanguage;
    [Test] procedure HtmlEscapesNamesAndTheProject;
    [Test] procedure HtmlPhraseTableNeverClosesTheScriptTag;
    [Test] procedure HtmlHasNoLeftoverPlaceholders;
    [Test] procedure ReportFileNameFollowsTheLanguage;
    [Test] procedure EmptySbomStillMakesAReport;
    [Test] procedure LongListsOfUnconfirmedAreShortened;
  end;

implementation

procedure TSbomReportTests.Add(const AName: string; AOrigin: TSbomOrigin; AConfidence: TSbomConfidence; const AHash: string;
  const AUsedBy: array of string);
var
  C: TSbomComponent;
  Created: Boolean;
  I: Integer;
begin
  C := FSbom.Obtain(AName, Created);
  C.Origin := AOrigin;
  C.Confidence := AConfidence;
  C.Hash := AHash;
  if AHash <> '' then
  begin
    C.Path := 'C:\x\' + AName + '.pas';
    C.Evidence := seFile;
  end;
  SetLength(C.UsedBy, Length(AUsedBy));
  for I := 0 to High(AUsedBy) do
    C.UsedBy[I] := AUsedBy[I];
end;

procedure TSbomReportTests.Setup;
begin
  FPrevious := CurrentLang;
  SetLang(lgPt);
  FSbom := TSbom.Create;
  FSbom.Generated := EncodeDate(2026, 10, 6) + EncodeTime(12, 30, 0, 0);
  FSbom.Project.Name := 'Demo';
  FSbom.Project.Version := '1.2.3.4';
  FSbom.Project.Company := 'Acme';
  FSbom.Project.Platform := 'Win64';
  FSbom.Project.Configuration := 'Release';
  FSbom.Project.FrameworkType := 'VCL';
  Add('System.SysUtils', soRtl, scStrong, StringOfChar('a', 64), ['Main', 'Core']);
  Add('Vcl.Forms', soVcl, scMedium, '', ['Main']);
  Add('Chart4D.FMX', soThirdParty, scWeak, '', ['Core']);
  Add('Spring.Collections', soThirdParty, scStrong, StringOfChar('b', 64), ['Core']);
  Add('Main', soProject, scStrong, StringOfChar('c', 64), []);
  FSbom.SortComponents;
end;

procedure TSbomReportTests.TearDown;
begin
  FSbom.Free;
  SetLang(FPrevious);
end;

function TSbomReportTests.Count(const AText, APattern: string): Integer;
begin
  Result := TRegEx.Matches(AText, APattern).Count;
end;

function TSbomReportTests.PhraseTable(const AHtml: string): TJSONObject;
var
  M: TMatch;
begin
  M := TRegEx.Match(AHtml, 'var T=(\{.*?\]\});\(function', [roSingleLine]);
  Assert.IsTrue(M.Success, 'a tabela de frases nao esta na pagina');
  Result := TJSONObject.ParseJSONValue(M.Groups[1].Value) as TJSONObject;
  Assert.IsNotNull(Result);
end;

procedure TSbomReportTests.MarkdownHasTheSections;
var
  Md: string;
begin
  Md := SbomMarkdown(FSbom, 'C:\Proj');
  Assert.Contains(Md, '# Lista de materiais de software (SBOM) — Demo');
  Assert.Contains(Md, '## Resumo');
  Assert.Contains(Md, '## Projeto');
  Assert.Contains(Md, '## Resumo por origem');
  Assert.Contains(Md, '## Componentes');
  Assert.Contains(Md, '## Pontos de atenção');
  Assert.Contains(Md, '## Como ler este relatório');
  Assert.Contains(Md, 'C:\Proj');
  Assert.Contains(Md, '| Versão | 1.2.3.4 |');
  Assert.Contains(Md, '| Empresa | Acme |');
  Assert.Contains(Md, '| Plataforma | Win64 |');
end;

procedure TSbomReportTests.MarkdownCountsByOrigin;
var
  Md: string;
begin
  Md := SbomMarkdown(FSbom, '');
  Assert.Contains(Md, '- Componentes: 5');
  Assert.Contains(Md, '- Com ficheiro encontrado: 3');
  Assert.Contains(Md, '- Da Embarcadero: 2');
  Assert.Contains(Md, '- De terceiros: 2');
  Assert.Contains(Md, '- Do projeto: 1');
  Assert.Contains(Md, '- Por confirmar: 1');
  Assert.Contains(Md, '| RTL da Embarcadero | 1 | 1 |');
  Assert.Contains(Md, '| Terceiros | 2 | 1 |');
end;

procedure TSbomReportTests.MarkdownListsTheUnconfirmedComponents;
var
  Md: string;
begin
  Md := SbomMarkdown(FSbom, '');
  Assert.Contains(Md, '- `Chart4D.FMX` — Core');
  Assert.IsFalse(Md.Contains('Nada a assinalar'));
end;

procedure TSbomReportTests.MarkdownSaysWhenEverythingIsConfirmed;
var
  Md: string;
begin
  FSbom.Find('Chart4D.FMX').Confidence := scMedium;
  Md := SbomMarkdown(FSbom, '');
  Assert.Contains(Md, 'Nada a assinalar: todos os componentes foram confirmados.');
end;

procedure TSbomReportTests.MarkdownShowsAShortHash;
var
  Md: string;
begin
  Md := SbomMarkdown(FSbom, '');
  Assert.Contains(Md, StringOfChar('a', 16) + ' |');
  Assert.IsFalse(Md.Contains(StringOfChar('a', 17)), 'so os primeiros 16 caracteres');
  Assert.Contains(Md, '| — |', 'sem hash, um travessao');
end;

procedure TSbomReportTests.MarkdownFollowsTheActiveLanguage;
begin
  SetLang(lgEn);
  Assert.Contains(SbomMarkdown(FSbom, ''), '# Software bill of materials (SBOM) — Demo');
  Assert.Contains(SbomMarkdown(FSbom, ''), '## Components');
  SetLang(lgDe);
  Assert.Contains(SbomMarkdown(FSbom, ''), '# Software-Stückliste (SBOM) — Demo');
  SetLang(lgFr);
  Assert.Contains(SbomMarkdown(FSbom, ''), '## Composants');
end;

procedure TSbomReportTests.HtmlHasCardsTablesAndTheLanguageSwitcher;
var
  Html: string;
begin
  Html := SbomHtml(FSbom, 'C:\Proj');
  Assert.Contains(Html, '<!doctype html>');
  Assert.Contains(Html, 'lang="pt"');
  Assert.AreEqual(6, Count(Html, '<div class="card">'));
  Assert.AreEqual(4, Count(Html, '<button type="button" data-l="'));
  Assert.Contains(Html, 'data-l="pt" title="Português" class="on">PT</button>');
  Assert.Contains(Html, 'id="flt"');
  Assert.Contains(Html, '<table class="sort" id="all">');
  Assert.Contains(Html, 'SHA-256');
end;

procedure TSbomReportTests.HtmlHasOneRowPerComponent;
var
  Html, Body: string;
begin
  Html := SbomHtml(FSbom, '');
  Body := Copy(Html, Pos('<table class="sort" id="all">', Html), MaxInt);
  Assert.AreEqual(5, Count(Body, '<tr><td class="m">'));
  Assert.Contains(Body, '<td class="m">System.SysUtils</td>');
  Assert.Contains(Body, 'title="' + StringOfChar('a', 64) + '">' + StringOfChar('a', 16) + '</td>');
end;

procedure TSbomReportTests.HtmlEmbedsEveryPhraseInTheFourLanguages;
var
  T: TJSONObject;
  Code: string;
  Len: Integer;
begin
  T := PhraseTable(SbomHtml(FSbom, ''));
  try
    Assert.AreEqual(4, T.Count);
    Len := (T.GetValue('pt') as TJSONArray).Count;
    Assert.IsTrue(Len > 30);
    for Code in LangCodes do
      Assert.AreEqual(Len, (T.GetValue(Code) as TJSONArray).Count, Code);
  finally
    T.Free;
  end;
end;

procedure TSbomReportTests.HtmlPhraseIndexesExist;
var
  Html: string;
  T: TJSONObject;
  M: TMatch;
  Len: Integer;
begin
  Html := SbomHtml(FSbom, '');
  T := PhraseTable(Html);
  try
    Len := (T.GetValue('en') as TJSONArray).Count;
    Assert.IsTrue(Count(Html, 'data-k="') > 30);
    for M in TRegEx.Matches(Html, 'data-k="(\d+)"') do
      Assert.IsTrue(StrToInt(M.Groups[1].Value) < Len, M.Value);
    for M in TRegEx.Matches(Html, 'data-ph="(\d+)"') do
      Assert.IsTrue(StrToInt(M.Groups[1].Value) < Len, M.Value);
  finally
    T.Free;
  end;
end;

procedure TSbomReportTests.HtmlTextFollowsTheExportedLanguage;
var
  Html: string;
  T: TJSONObject;
begin
  SetLang(lgEn);
  Html := SbomHtml(FSbom, '');
  Assert.Contains(Html, 'lang="en"');
  Assert.Contains(Html, '>Components</h2>');
  Assert.Contains(Html, '>Third party</span>');
  Assert.Contains(Html, '>Weak</span>');
  Assert.Contains(Html, 'data-l="en" title="English" class="on">EN</button>');
  T := PhraseTable(Html);
  try
    Assert.IsTrue(Pos('Componentes', T.GetValue('pt').ToString) > 0, 'o portugues tambem la esta');
    Assert.IsTrue(Pos('Komponenten', T.GetValue('de').ToString) > 0);
  finally
    T.Free;
  end;
end;

procedure TSbomReportTests.HtmlEscapesNamesAndTheProject;
var
  Html: string;
begin
  FSbom.Project.Name := 'A<B> & "C"';
  Add('Evil<Unit>', soThirdParty, scWeak, '', ['X&Y']);
  Html := SbomHtml(FSbom, 'C:\a&b');
  Assert.IsFalse(Html.Contains('A<B>'), 'o nome do projecto nunca vai sem escapar');
  Assert.IsFalse(Html.Contains('Evil<Unit>'));
  Assert.Contains(Html, 'Evil&lt;Unit&gt;');
  Assert.Contains(Html, 'X&amp;Y');
  Assert.Contains(Html, 'C:\a&amp;b');
end;

procedure TSbomReportTests.HtmlPhraseTableNeverClosesTheScriptTag;
var
  Html: string;
begin
  FSbom.Project.Name := '</script><b>x';
  Html := SbomHtml(FSbom, '');
  Assert.AreEqual(1, Count(Html, '</script>'), 'so o fecho verdadeiro do script');
end;

procedure TSbomReportTests.HtmlHasNoLeftoverPlaceholders;
begin
  Assert.AreEqual('', TRegEx.Match(SbomHtml(FSbom, ''), '__[A-Z][A-Z_]*__').Value);
end;

procedure TSbomReportTests.ReportFileNameFollowsTheLanguage;
begin
  Assert.AreEqual('meu-projeto-sbom-relatorio.html', SbomReportFileName('Meu Projeto', '.html'));
  SetLang(lgEn);
  Assert.AreEqual('meu-projeto-sbom-report.md', SbomReportFileName('Meu Projeto', '.md'));
  SetLang(lgDe);
  Assert.AreEqual('x-sbom-bericht.html', SbomReportFileName('X', '.html'));
  Assert.AreEqual('projeto-sbom-bericht.md', SbomReportFileName('', '.md'));
end;

procedure TSbomReportTests.EmptySbomStillMakesAReport;
var
  S: TSbom;
begin
  S := TSbom.Create;
  try
    S.Project.Name := 'Vazio';
    Assert.Contains(SbomMarkdown(S, ''), '- Componentes: 0');
    Assert.Contains(SbomHtml(S, ''), '</html>');
  finally
    S.Free;
  end;
end;

procedure TSbomReportTests.LongListsOfUnconfirmedAreShortened;
var
  I, From: Integer;
  Md, Attention: string;
begin
  for I := 1 to 60 do
    Add(Format('Lib.U%.2d', [I]), soThirdParty, scWeak, '', ['Main']);
  Md := SbomMarkdown(FSbom, '');
  From := Pos('## Pontos de atenção', Md);
  Attention := Copy(Md, From, Pos('## Como ler', Md) - From);
  Assert.Contains(Attention, '- `Lib.U01`');
  Assert.IsFalse(Attention.Contains('`Lib.U60`'), 'a lista de atencao corta nos 40');
  Assert.Contains(Attention, '- … 21');
  Assert.Contains(Md, '| `Lib.U60` |', 'a tabela dos componentes leva-os todos');
end;

end.
