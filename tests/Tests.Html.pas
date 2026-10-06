unit Tests.Html;

// Testes de CM.Html: exportacao das paginas HTML (checklist e mapa). Os modelos vem do recurso
// templates.res embutido no executavel de testes; aqui verifica-se que todos os marcadores __X__
// sao substituidos, que o texto do utilizador e escapado e que o ficheiro sai em UTF-8 sem BOM.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  DUnitX.TestFramework, CM.Lang, CM.Lang.Table, CM.Analyzer, CM.Store, CM.Html, Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  THtmlOutputPathTests = class
  public
    [Test] procedure ChecklistPathUsesSlugOfTheName;
    [Test] procedure MapPathUsesSlugOfTheName;
  end;

  [TestFixture]
  TExportHtmlTests = class
  private
    FDir: TTempDir;
    FScan: TProjectScan;
    FState: TProgressState;
    FProfile: TProjectProfile;
    FPrevLang: TLang;
    function Checklist: string;
    function Map: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ChecklistHasNoLeftoverPlaceholders;
    [Test] procedure MapHasNoLeftoverPlaceholders;
    [Test] procedure ProjectNameIsEscapedForHtml;
    [Test] procedure PortugueseExportKeepsTheTemplateText;
    [Test] procedure EachLanguageTranslatesTheMapPage;
    [Test] procedure EachLanguageTranslatesTheChecklistPage;
    [Test] procedure EveryTemplateSnippetStillExistsInTheTemplates;
    [Test] procedure TranslateHtmlLeavesPortugueseUntouchedAndLongestSnippetsWin;
    [Test] procedure ProjectNameIsEscapedForJavaScript;
    [Test] procedure StorageKeysCarryTheSlug;
    [Test] procedure FilesJsonListsEveryUnit;
    [Test] procedure MethodsJsonListsMethodsAndSkipsEmptyUnits;
    [Test] procedure MethodsJsonCarriesTheMeasuresOfMethodsWithABody;
    [Test] procedure MetricLabelsAreTranslated;
    [Test] procedure ExcludedFoldersAreMentioned;
    [Test] procedure SeedStateCarriesTheProgress;
    [Test] procedure SeedStateNeverClosesTheScriptTag;
    [Test] procedure FinalizedBannerOnlyWhenFinalized;
    [Test] procedure OutputFolderIsCreatedWhenMissing;
    [Test] procedure OutputIsUtf8WithoutBom;
    [Test] procedure ExportOverwritesExistingFile;
  end;

implementation

const
  // com <, &, aspas e barra invertida: exercita ambos os escapes
  NASTY_NAME = 'A<B> & "C" \D';

function ReadOut(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath, TEncoding.UTF8);
end;

{ THtmlOutputPathTests }

procedure THtmlOutputPathTests.ChecklistPathUsesSlugOfTheName;
var
  P: TProjectProfile;
begin
  P := NewProfile('Meu Projeto 2');
  try
    P.OutputFolder := 'C:\Out';
    Assert.AreEqual(TPath.Combine('C:\Out', 'meu-projeto-2-checklist-codigo-fonte.html'), ChecklistOutputPath(P));
  finally
    P.Free;
  end;
end;

procedure THtmlOutputPathTests.MapPathUsesSlugOfTheName;
var
  P: TProjectProfile;
begin
  P := NewProfile('Meu Projeto 2');
  try
    P.OutputFolder := 'C:\Out';
    Assert.AreEqual(TPath.Combine('C:\Out', 'meu-projeto-2-estrutura-codigo.html'), MapOutputPath(P));
  finally
    P.Free;
  end;
end;

{ TExportHtmlTests }

procedure TExportHtmlTests.Setup;
begin
  FPrevLang := CurrentLang;
  SetLang(lgPt);
  FDir := TTempDir.Create;
  FScan := BuildSampleScan;
  FState := TProgressState.Create;
  FProfile := NewProfile('Demo');
  FProfile.OutputFolder := FDir.Path;
end;

procedure TExportHtmlTests.TearDown;
begin
  FProfile.Free;
  FState.Free;
  FScan.Free;
  FDir.Free;
  SetLang(FPrevLang);
end;

function TExportHtmlTests.Checklist: string;
var
  Path: string;
begin
  Path := ChecklistOutputPath(FProfile);
  ExportChecklistHtml(FProfile, FScan, FState, Path);
  Result := ReadOut(Path);
end;

function TExportHtmlTests.Map: string;
var
  Path: string;
begin
  Path := MapOutputPath(FProfile);
  ExportMapHtml(FProfile, FScan, FState, Path);
  Result := ReadOut(Path);
end;

procedure TExportHtmlTests.ChecklistHasNoLeftoverPlaceholders;
begin
  Assert.AreEqual('', TRegEx.Match(Checklist, '__[A-Z][A-Z_]*__').Value);
end;

procedure TExportHtmlTests.MapHasNoLeftoverPlaceholders;
begin
  Assert.AreEqual('', TRegEx.Match(Map, '__[A-Z][A-Z_]*__').Value);
end;

procedure TExportHtmlTests.PortugueseExportKeepsTheTemplateText;
begin
  SetLang(lgPt);
  Assert.IsTrue(Map.Contains('lang="pt-PT"'));
  Assert.IsTrue(Map.Contains('Mapa de Código-Fonte'));
  Assert.IsTrue(Checklist.Contains('Checklist de Código-Fonte'));
end;

procedure TExportHtmlTests.EachLanguageTranslatesTheMapPage;
const
  Titles: array[lgEn..lgDe] of string = ('Source Code Map', 'Carte du code source', 'Quellcode-Karte');
  Codes: array[lgEn..lgDe] of string = ('lang="en"', 'lang="fr"', 'lang="de"');
var
  L: TLang;
  Prev: TLang;
  Html: string;
begin
  Prev := CurrentLang;
  try
    for L := lgEn to lgDe do
    begin
      SetLang(L);
      Html := Map;
      Assert.IsTrue(Html.Contains(Codes[L]), 'lang ' + LangCodes[L]);
      Assert.IsTrue(Html.Contains(Titles[L]), 'titulo ' + LangCodes[L]);
      Assert.IsFalse(Html.Contains('lang="pt-PT"'), 'sem pt-PT em ' + LangCodes[L]);
      Assert.IsFalse(Html.Contains('Mapa de Código-Fonte'), 'sem titulo portugues em ' + LangCodes[L]);
      Assert.IsFalse(Html.Contains('Nenhum resultado'), 'sem mensagens portuguesas em ' + LangCodes[L]);
    end;
  finally
    SetLang(Prev);
  end;
end;

procedure TExportHtmlTests.EachLanguageTranslatesTheChecklistPage;
var
  L: TLang;
  Prev: TLang;
  Html: string;
begin
  Prev := CurrentLang;
  try
    for L := lgEn to lgDe do
    begin
      SetLang(L);
      Html := Checklist;
      Assert.IsTrue(Html.Contains('lang="' + LangCodes[L] + '"'), 'lang ' + LangCodes[L]);
      Assert.IsFalse(Html.Contains('lang="pt-PT"'), LangCodes[L]);
      Assert.IsFalse(Html.Contains('Nenhum ficheiro corresponde'), 'sem mensagens portuguesas em ' + LangCodes[L]);
      Assert.AreEqual('', TRegEx.Match(Html, '__[A-Z][A-Z_]*__').Value, 'marcadores por preencher');
    end;
  finally
    SetLang(Prev);
  end;
end;

// um troco que ja nao existe nos modelos e uma traducao esquecida (ou um texto do modelo que mudou)
procedure TExportHtmlTests.EveryTemplateSnippetStillExistsInTheTemplates;
var
  I: Integer;
  Pt, Missing: string;
begin
  SetLang(lgPt);
  Pt := Map + Checklist;
  Missing := '';
  for I := Low(HtmlRows) to High(HtmlRows) do
    if not HtmlRows[I][0].Contains('__') and not Pt.Contains(HtmlRows[I][0]) then
      Missing := Missing + HtmlRows[I][0].Substring(0, 60) + sLineBreak;
  Assert.AreEqual('', Missing, 'Trocos de translations.tsv (#!html) que ja nao estao nos modelos:');
end;

procedure TExportHtmlTests.TranslateHtmlLeavesPortugueseUntouchedAndLongestSnippetsWin;
begin
  Assert.AreEqual('<b>>Expandir tudo<</b>', TranslateHtmlTo(lgPt, '<b>>Expandir tudo<</b>'));
  Assert.AreEqual('<b>>Expand all<</b>', TranslateHtmlTo(lgEn, '<b>>Expandir tudo<</b>'));
  Assert.IsTrue(HtmlTranslationCount > 50);
end;

procedure TExportHtmlTests.ProjectNameIsEscapedForHtml;
var
  Html: string;
begin
  FProfile.Name := NASTY_NAME;
  Html := Checklist;
  Assert.IsTrue(Html.Contains('A&lt;B&gt; &amp; "C" \D'), 'nome escapado em HTML');
  Assert.IsFalse(Html.Contains('<title>A<B>'), 'o nome cru nao pode aparecer em HTML');
end;

procedure TExportHtmlTests.ProjectNameIsEscapedForJavaScript;
begin
  FProfile.Name := NASTY_NAME;
  // aspas e barras invertidas escapadas para caberem numa string JS entre aspas
  Assert.IsTrue(Checklist.Contains('A<B> & \"C\" \\D'));
end;

procedure TExportHtmlTests.StorageKeysCarryTheSlug;
begin
  FProfile.Name := 'Meu Projeto';
  Assert.IsTrue(Checklist.Contains('checklist-meu-projeto-v1'), 'chave da checklist');
  Assert.IsTrue(Map.Contains('mapa-codigo-meu-projeto-v1'), 'chave do mapa');
end;

procedure TExportHtmlTests.FilesJsonListsEveryUnit;
var
  Html: string;
begin
  Html := Checklist;
  Assert.IsTrue(Html.Contains('["Core/a.pas","Core/b.pas","Core/Sub/c.pas","UI/d.pas","root.pas"]'));
end;

procedure TExportHtmlTests.MethodsJsonListsMethodsAndSkipsEmptyUnits;
var
  Html: string;
begin
  Html := Map;
  Assert.IsTrue(Html.Contains('"Core/a.pas":[{"name":"TA.One"'), 'metodos de a.pas');
  Assert.IsTrue(Html.Contains('"Core/Sub/c.pas":[{"name":"TC.Run"'), 'metodos de c.pas');
  Assert.IsFalse(Html.Contains('"Core/b.pas":['), 'units sem metodos nao entram em METHODS');
  Assert.IsFalse(Html.Contains('"UI/d.pas":['), 'units sem metodos nao entram em METHODS');
end;

procedure TExportHtmlTests.MethodsJsonCarriesTheMeasuresOfMethodsWithABody;
var
  M: TMethodInfo;
  Html: string;
begin
  M := FScan.Units[0].Methods[0];
  FScan.Units[0].Methods[0].Lines := 74;
  FScan.Units[0].Methods[0].Complexity := 18;
  FScan.Units[0].Methods[0].ParamCount := 8;
  FScan.Units[0].Methods[0].Nesting := 2;
  Html := Map;
  Assert.IsTrue(Html.Contains('"sig":"' + M.Sig + '","l":74,"cx":18,"p":8,"n":2,"lv":[2,3,1]}'), 'medidas e niveis');
  Assert.IsTrue(Html.Contains('"sig":"procedure TA.Two;"}'), 'sem corpo, sem medidas');
end;

procedure TExportHtmlTests.MetricLabelsAreTranslated;
begin
  SetLang(lgEn);
  Assert.IsTrue(Map.Contains('"Cyclomatic complexity"'), 'mapa');
  Assert.IsTrue(Checklist.Contains('"Nesting"'), 'checklist');
end;

procedure TExportHtmlTests.ExcludedFoldersAreMentioned;
begin
  Assert.IsTrue(Checklist.Contains('<code>bin</code>, <code>obj</code>'));
end;

procedure TExportHtmlTests.SeedStateCarriesTheProgress;
var
  Html: string;
begin
  FState.Rec('Core/a.pas').Done := True;
  Html := Checklist;
  Assert.IsTrue(Html.Contains('Core/a.pas'), 'o caminho aparece');
  Assert.IsTrue(Html.Contains(FState.ToJSONString.Replace('</', '<\/')), 'o JSON do estado vai embutido');
end;

procedure TExportHtmlTests.SeedStateNeverClosesTheScriptTag;
begin
  // uma nota com "</script>" nao pode terminar o <script> da pagina
  FState.Rec('Core/a.pas').Note := 'x</script><b>y';
  Assert.IsFalse(Checklist.Contains('x</script>'));
  Assert.IsFalse(Map.Contains('x</script>'));
end;

procedure TExportHtmlTests.FinalizedBannerOnlyWhenFinalized;
begin
  Assert.IsFalse(Map.Contains('finalized-banner">'), 'sem banner enquanto aberto');
  FProfile.Finalized := True;
  FProfile.FinalizedAt := '2026-10-02';
  Assert.IsTrue(Map.Contains('PROJECTO FINALIZADO em 2026-10-02'));
end;

procedure TExportHtmlTests.OutputFolderIsCreatedWhenMissing;
var
  Path: string;
begin
  Path := FDir.Full('novo/sub/mapa.html');
  ExportMapHtml(FProfile, FScan, FState, Path);
  Assert.IsTrue(TFile.Exists(Path));
end;

procedure TExportHtmlTests.OutputIsUtf8WithoutBom;
var
  Bytes: TBytes;
begin
  FProfile.Name := 'Ação';
  ExportChecklistHtml(FProfile, FScan, FState, FDir.Full('c.html'));
  Bytes := TFile.ReadAllBytes(FDir.Full('c.html'));
  Assert.IsTrue(Length(Bytes) > 3);
  Assert.IsFalse((Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF), 'sem BOM');
  Assert.IsTrue(ReadOut(FDir.Full('c.html')).Contains('Ação'), 'acentos preservados');
end;

procedure TExportHtmlTests.ExportOverwritesExistingFile;
var
  Path: string;
begin
  Path := FDir.Write('x.html', 'ANTIGO');
  ExportMapHtml(FProfile, FScan, FState, Path);
  Assert.IsFalse(ReadOut(Path).Contains('ANTIGO'));
end;

end.
