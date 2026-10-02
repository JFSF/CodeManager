unit Tests.Html;

// Testes de CM.Html: exportacao das paginas HTML (checklist e mapa). Os modelos vem do recurso
// templates.res embutido no executavel de testes; aqui verifica-se que todos os marcadores __X__
// sao substituidos, que o texto do utilizador e escapado e que o ficheiro sai em UTF-8 sem BOM.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.RegularExpressions,
  DUnitX.TestFramework, CM.Analyzer, CM.Store, CM.Html, Tests.Helpers, Tests.Export.Fixtures;

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
    function Checklist: string;
    function Map: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ChecklistHasNoLeftoverPlaceholders;
    [Test] procedure MapHasNoLeftoverPlaceholders;
    [Test] procedure ProjectNameIsEscapedForHtml;
    [Test] procedure ProjectNameIsEscapedForJavaScript;
    [Test] procedure StorageKeysCarryTheSlug;
    [Test] procedure FilesJsonListsEveryUnit;
    [Test] procedure MethodsJsonListsMethodsAndSkipsEmptyUnits;
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
