unit Tests.Lang;
// Testes do idioma: a tabela de traducoes esta completa e coerente, e todo o texto marcado
// com Tr()/TrF()/TrCount() no codigo existe na tabela (le o texto dos .pas; nao compila nada).

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.RegularExpressions, System.StrUtils, DUnitX.TestFramework, CM.Lang, CM.Lang.Table;

type
  [TestFixture]
  TLangTests = class
  private
    FPrevious: TLang;
    function FindSrcDir: string;
    function Specifiers(const AText: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PortugueseIsTheDefaultAndReturnsTheKey;
    [Test] procedure UnknownTextFallsBackToThePortugueseKey;
    [Test] procedure TranslatesWhenTheLanguageChanges;
    [Test] procedure TrFFormatsTheTranslatedText;
    [Test] procedure TrCountUsesSingularAndPlural;
    [Test] procedure LangFromCodeAcceptsLocaleNames;
    [Test] procedure TranslateAllListsEveryDistinctVariant;
    [Test] procedure EveryRowIsTranslatedIntoAllLanguages;
    [Test] procedure FormatSpecifiersMatchThePortugueseKey;
    [Test] procedure EveryMarkedTextInTheSourceIsInTheTable;
    [Test] procedure MonthNamesFollowTheLanguage;
    [Test] procedure EveryLanguageHasALocaleNameForTheChartAxes;
    [Test] procedure SourceFilesWithAccentsStartWithAUtf8Bom;
  end;

implementation

procedure TLangTests.Setup;
begin
  FPrevious := CurrentLang;
  SetLang(lgPt);
end;

procedure TLangTests.TearDown;
begin
  SetLang(FPrevious);
end;

function TLangTests.FindSrcDir: string;
var
  Dir, Cand: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  while Dir <> '' do
  begin
    Cand := TPath.Combine(Dir, 'src');
    if TDirectory.Exists(TPath.Combine(Cand, 'Core')) then
      Exit(Cand);
    if TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir)) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir));
  end;
  Result := '';
end;

// os marcadores de formato (%d, %s, %.0f, %0:s...) pela ordem em que aparecem; %% nao conta
function TLangTests.Specifiers(const AText: string): string;
var
  M: TMatch;
begin
  Result := '';
  for M in TRegEx.Matches(AText.Replace('%%', ''), '%(\d+:)?[-0-9.]*[dsfx]') do
    Result := Result + M.Value + ' ';
end;

procedure TLangTests.PortugueseIsTheDefaultAndReturnsTheKey;
begin
  Assert.AreEqual(lgPt, CurrentLang);
  Assert.AreEqual('Mapa de código', Tr('Mapa de código'));
end;

procedure TLangTests.UnknownTextFallsBackToThePortugueseKey;
begin
  SetLang(lgEn);
  Assert.AreEqual('texto que nao esta na tabela', Tr('texto que nao esta na tabela'));
end;

procedure TLangTests.TranslatesWhenTheLanguageChanges;
begin
  SetLang(lgEn);
  Assert.AreEqual('Code map', Tr('Mapa de código'));
  SetLang(lgFr);
  Assert.AreEqual('Carte du code', Tr('Mapa de código'));
  SetLang(lgDe);
  Assert.AreEqual('Codekarte', Tr('Mapa de código'));
  SetLang(lgPt);
  Assert.AreEqual('Mapa de código', Tr('Mapa de código'));
end;

procedure TLangTests.TrFFormatsTheTranslatedText;
begin
  Assert.AreEqual('1 / 2 ficheiros', TrF('%d / %d ficheiros', [1, 2]));
  SetLang(lgEn);
  Assert.AreEqual('1 / 2 files', TrF('%d / %d ficheiros', [1, 2]));
end;

procedure TLangTests.TrCountUsesSingularAndPlural;
begin
  Assert.AreEqual('1 método', TrCount(1, 'método', 'métodos'));
  Assert.AreEqual('3 métodos', TrCount(3, 'método', 'métodos'));
  SetLang(lgEn);
  Assert.AreEqual('1 method', TrCount(1, 'método', 'métodos'));
  Assert.AreEqual('0 methods', TrCount(0, 'método', 'métodos'));
end;

procedure TLangTests.LangFromCodeAcceptsLocaleNames;
begin
  Assert.AreEqual(lgFr, LangFromCode('fr', lgPt));
  Assert.AreEqual(lgFr, LangFromCode('FR-CA', lgPt));
  Assert.AreEqual(lgDe, LangFromCode(' de_DE ', lgPt));
  Assert.AreEqual(lgEn, LangFromCode('en-GB', lgPt));
  Assert.AreEqual(lgPt, LangFromCode('pt-PT', lgEn));
  Assert.AreEqual(lgEn, LangFromCode('', lgEn));
  Assert.AreEqual(lgDe, LangFromCode('xx', lgDe));
end;

procedure TLangTests.TranslateAllListsEveryDistinctVariant;
var
  V: TArray<string>;
begin
  V := TranslateAll(' [Compila]');
  Assert.AreEqual<Integer>(4, Length(V));
  Assert.AreEqual(' [Compila]', V[0]);
  Assert.IsTrue(MatchStr(' [Builds]', V));
  // sem traducao: so o original
  Assert.AreEqual<Integer>(1, Length(TranslateAll('texto que nao esta na tabela')));
end;

procedure TLangTests.EveryRowIsTranslatedIntoAllLanguages;
var
  I, L: Integer;
  Empty: TStringBuilder;
begin
  Assert.IsTrue(TranslationCount > 100);
  Empty := TStringBuilder.Create;
  try
    for I := Low(LangRows) to High(LangRows) do
      for L := 0 to 3 do
        if LangRows[I][L] = '' then
          Empty.AppendLine(Format('%s [coluna %d]', [LangRows[I][0], L]));
    Assert.AreEqual('', Empty.ToString, 'Linhas com colunas vazias em translations.tsv:');
  finally
    Empty.Free;
  end;
end;

procedure TLangTests.FormatSpecifiersMatchThePortugueseKey;
var
  I, L: Integer;
  Bad: TStringBuilder;
begin
  Bad := TStringBuilder.Create;
  try
    for I := Low(LangRows) to High(LangRows) do
      for L := 1 to 3 do
        if Specifiers(LangRows[I][L]) <> Specifiers(LangRows[I][0]) then
          Bad.AppendLine(Format('%s [%s]', [LangRows[I][0], LangCodes[TLang(L)]]));
    Assert.AreEqual('', Bad.ToString, 'Marcadores de formato diferentes do original:');
  finally
    Bad.Free;
  end;
end;

procedure TLangTests.EveryMarkedTextInTheSourceIsInTheTable;
var
  Src, F, Key: string;
  Known: TDictionary<string, Boolean>;
  M: TMatch;
  Missing: TStringBuilder;
  Text: string;

  procedure Check(const AQuoted: string);
  begin
    Key := AQuoted.Replace('''''', '''');
    if not Known.ContainsKey(Key) then
      Missing.AppendLine(TPath.GetFileName(F) + ': ' + Key);
  end;

var
  I: Integer;
begin
  Src := FindSrcDir;
  Assert.AreNotEqual('', Src, 'Pasta src\ nao encontrada');
  Known := TDictionary<string, Boolean>.Create;
  Missing := TStringBuilder.Create;
  try
    for I := Low(LangRows) to High(LangRows) do
      Known.AddOrSetValue(LangRows[I][0], True);
    for F in TDirectory.GetFiles(Src, '*.pas', TSearchOption.soAllDirectories) do
    begin
      if F.EndsWith('CM.Lang.pas') or F.EndsWith('CM.Lang.Table.pas') then
        Continue;
      Text := TFile.ReadAllText(F);
      for M in TRegEx.Matches(Text, '\bTrF?\(\s*''((?:[^'']|'''')*)''') do
        Check(M.Groups[1].Value);
      for M in TRegEx.Matches(Text, '\bTrCount\([^,]+,\s*''((?:[^'']|'''')*)'',\s*''((?:[^'']|'''')*)''') do
      begin
        Check(M.Groups[1].Value);
        Check(M.Groups[2].Value);
      end;
    end;
    Assert.AreEqual('', Missing.ToString, 'Textos marcados com Tr() que faltam em translations.tsv:');
  finally
    Missing.Free;
    Known.Free;
  end;
end;

procedure TLangTests.EveryLanguageHasALocaleNameForTheChartAxes;
var
  L: TLang;
begin
  // o eixo de datas do Painel usa este nome: tem de ser o do idioma (e nao um fixo em portugues)
  for L := Low(TLang) to High(TLang) do
    Assert.IsTrue(LangLocales[L].StartsWith(LangCodes[L] + '-'), 'locale de ' + LangCodes[L] + ': ' + LangLocales[L]);
end;

procedure TLangTests.MonthNamesFollowTheLanguage;
begin
  SetLang(lgEn);
  Assert.AreEqual('Oct', FormatDateTime('mmm', EncodeDate(2026, 10, 3)));
  SetLang(lgFr);
  Assert.AreEqual('oct.', FormatDateTime('mmm', EncodeDate(2026, 10, 3)));
  SetLang(lgDe);
  Assert.AreEqual('Okt', FormatDateTime('mmm', EncodeDate(2026, 10, 3)));
  SetLang(lgPt);
  Assert.AreEqual('out', FormatDateTime('mmm', EncodeDate(2026, 10, 3)));
end;

// o Delphi le como ANSI um .pas UTF-8 sem BOM: os acentos das chaves Tr() deixavam de coincidir com a tabela
procedure TLangTests.SourceFilesWithAccentsStartWithAUtf8Bom;
var
  Src, F: string;
  Bytes: TBytes;
  I: Integer;
  HasHigh: Boolean;
  Bad: TStringBuilder;
begin
  Src := FindSrcDir;
  Assert.AreNotEqual('', Src, 'Pasta src\ nao encontrada');
  Bad := TStringBuilder.Create;
  try
    for F in TDirectory.GetFiles(Src, '*.pas', TSearchOption.soAllDirectories) do
    begin
      Bytes := TFile.ReadAllBytes(F);
      HasHigh := False;
      for I := 0 to High(Bytes) do
        if Bytes[I] >= $80 then
        begin
          HasHigh := True;
          Break;
        end;
      if HasHigh and not ((Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF)) then
        Bad.AppendLine(TPath.GetFileName(F));
    end;
    Assert.AreEqual('', Bad.ToString, 'Ficheiros com acentos mas sem BOM UTF-8:');
  finally
    Bad.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLangTests);

end.
