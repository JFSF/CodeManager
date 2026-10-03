unit Tests.AppInfo;

// Testes de CM.AppInfo (versoes, nome do Delphi, texto de diagnostico) e de CM.SysInfo (o que se le ao sistema).

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.AppInfo, CM.SysInfo;

type
  [TestFixture]
  TAppInfoTests = class
  public
    [Test] procedure ParsesTheUsualVersionForms;
    [Test] procedure MissingPartsCountAsZero;
    [Test] procedure RejectsGarbage;
    [Test] procedure VersionTextHonoursTheNumberOfParts;
    [Test] procedure ComparesPartByPart;
    [Test] procedure DelphiNamesOfTheKnownCompilers;
    [Test] procedure UnknownCompilersAreStillNamed;
    [Test] procedure AboutTextListsOneInfoPerLine;
    [Test] procedure AboutTextSaysYesOrNoForTheTools;
    [Test] procedure TheAddressesPointToTheRepository;
  end;

  [TestFixture]
  TSysInfoTests = class
  public
    [Test] procedure PlatformIsOneOfTheTwo;
    [Test] procedure CompilerNamesDelphiAndTheVersion;
    [Test] procedure SystemTextIsNotEmpty;
    [Test] procedure CollectedInfoCarriesTheCallersFields;
    [Test] procedure CollectedBuildDateLooksLikeADate;
    [Test] procedure ExeVersionIsEmptyOrFourNumbers;
  end;

implementation

procedure TAppInfoTests.ParsesTheUsualVersionForms;
var
  V: TAppVersion;
begin
  V := ParseAppVersion('1.2.3.4');
  Assert.IsTrue(V.Valid);
  Assert.AreEqual(1, V.Major);
  Assert.AreEqual(2, V.Minor);
  Assert.AreEqual(3, V.Release);
  Assert.AreEqual(4, V.Build);
  V := ParseAppVersion('  v2.10.0  ');
  Assert.IsTrue(V.Valid);
  Assert.AreEqual(2, V.Major);
  Assert.AreEqual(10, V.Minor);
end;

procedure TAppInfoTests.MissingPartsCountAsZero;
var
  V: TAppVersion;
begin
  V := ParseAppVersion('3');
  Assert.IsTrue(V.Valid);
  Assert.AreEqual(3, V.Major);
  Assert.AreEqual(0, V.Minor);
  Assert.AreEqual(0, V.Build);
  Assert.AreEqual('3.0.0', VersionToText(V));
end;

procedure TAppInfoTests.RejectsGarbage;
begin
  Assert.IsFalse(ParseAppVersion('').Valid);
  Assert.IsFalse(ParseAppVersion('abc').Valid);
  Assert.IsFalse(ParseAppVersion('1.x.3').Valid);
  Assert.IsFalse(ParseAppVersion('1.2.3.4.5').Valid);
  Assert.IsFalse(ParseAppVersion('-1.0').Valid);
  Assert.IsFalse(ParseAppVersion('1..2').Valid);
end;

procedure TAppInfoTests.VersionTextHonoursTheNumberOfParts;
var
  V: TAppVersion;
begin
  V := ParseAppVersion('1.2.3.4');
  Assert.AreEqual('1', VersionToText(V, 1));
  Assert.AreEqual('1.2', VersionToText(V, 2));
  Assert.AreEqual('1.2.3', VersionToText(V));
  Assert.AreEqual('1.2.3.4', VersionToText(V, 4));
  Assert.AreEqual('1.2.3.4', VersionToText(V, 9), 'no maximo quatro');
  Assert.AreEqual('1', VersionToText(V, 0), 'no minimo uma');
end;

procedure TAppInfoTests.ComparesPartByPart;
begin
  Assert.IsTrue(CompareVersions(ParseAppVersion('1.0.1'), ParseAppVersion('1.0.0')) > 0);
  Assert.IsTrue(CompareVersions(ParseAppVersion('1.9.0'), ParseAppVersion('1.10.0')) < 0, 'numerico, nao alfabetico');
  Assert.AreEqual(0, CompareVersions(ParseAppVersion('1.0'), ParseAppVersion('1.0.0.0')));
  Assert.IsTrue(CompareVersions(ParseAppVersion('2.0'), ParseAppVersion('1.99.99.99')) > 0);
  Assert.IsTrue(CompareVersions(ParseAppVersion('1.0.0.1'), ParseAppVersion('1.0.0.0')) > 0);
end;

procedure TAppInfoTests.DelphiNamesOfTheKnownCompilers;
begin
  Assert.AreEqual('Delphi 13', DelphiName(37.0));
  Assert.AreEqual('Delphi 12', DelphiName(36.0));
  Assert.AreEqual('Delphi 11', DelphiName(35.0));
  Assert.AreEqual('Delphi 10.4', DelphiName(34.0));
end;

procedure TAppInfoTests.UnknownCompilersAreStillNamed;
begin
  Assert.AreEqual('Delphi (compilador 99.0)', DelphiName(99.0));
  Assert.AreEqual('Delphi (compilador 12.0)', DelphiName(12.0));
end;

function SampleInfo: TAboutInfo;
begin
  Result := Default(TAboutInfo);
  Result.Version := '1.0.0';
  Result.BuildKind := 'Release';
  Result.PlatformName := 'Win64';
  Result.BuildDate := '2026-10-03 14:22';
  Result.Compiler := 'Delphi 13 (VER370)';
  Result.SystemName := 'Windows 11';
  Result.Language := 'pt';
  Result.Theme := 'claro';
  Result.DataDir := 'C:\Users\x\AppData\Roaming\CodeManager';
  Result.GitAvailable := True;
  Result.SvnAvailable := False;
end;

procedure TAppInfoTests.AboutTextListsOneInfoPerLine;
var
  Lines: TArray<string>;
begin
  Lines := BuildAboutText(SampleInfo).Replace(#13, '').Split([#10]);
  Assert.AreEqual<NativeInt>(8, Length(Lines));
  Assert.AreEqual('CodeManager 1.0.0 (Release, Win64)', Lines[0]);
  Assert.AreEqual('Compilado: 2026-10-03 14:22', Lines[1]);
  Assert.AreEqual('Compilador: Delphi 13 (VER370)', Lines[2]);
  Assert.AreEqual('Sistema: Windows 11', Lines[3]);
  Assert.AreEqual('Idioma: pt', Lines[4]);
  Assert.AreEqual('Tema: claro', Lines[5]);
  Assert.IsTrue(Lines[6].StartsWith('Dados: '));
end;

procedure TAppInfoTests.AboutTextSaysYesOrNoForTheTools;
var
  I: TAboutInfo;
begin
  I := SampleInfo;
  Assert.IsTrue(BuildAboutText(I).EndsWith('Git: sim · Subversion: não'));
  I.GitAvailable := False;
  I.SvnAvailable := True;
  Assert.IsTrue(BuildAboutText(I).EndsWith('Git: não · Subversion: sim'));
end;

procedure TAppInfoTests.TheAddressesPointToTheRepository;
begin
  Assert.IsTrue(RepoUrl.StartsWith('https://github.com/'));
  Assert.IsTrue(ReleasesUrl.StartsWith(RepoUrl));
  Assert.IsTrue(IssuesUrl.StartsWith(RepoUrl));
  Assert.IsTrue(ChangelogUrl.EndsWith('CHANGELOG.md'));
end;

{ TSysInfoTests }

procedure TSysInfoTests.PlatformIsOneOfTheTwo;
begin
  Assert.IsTrue((PlatformText = 'Win64') or (PlatformText = 'Win32'));
end;

procedure TSysInfoTests.CompilerNamesDelphiAndTheVersion;
begin
  Assert.IsTrue(CompilerText.StartsWith('Delphi'));
  Assert.IsTrue(CompilerText.Contains('(VER'));
end;

procedure TSysInfoTests.SystemTextIsNotEmpty;
begin
  Assert.IsTrue(SystemText <> '');
  Assert.IsTrue(SystemText.Contains('Windows'));
end;

procedure TSysInfoTests.CollectedInfoCarriesTheCallersFields;
var
  I: TAboutInfo;
begin
  I := CollectAboutInfo('fr', 'escuro', 'C:\dados');
  Assert.AreEqual('fr', I.Language);
  Assert.AreEqual('escuro', I.Theme);
  Assert.AreEqual('C:\dados', I.DataDir);
  Assert.AreEqual(PlatformText, I.PlatformName);
  Assert.IsTrue((I.BuildKind = 'Debug') or (I.BuildKind = 'Release'));
end;

procedure TSysInfoTests.CollectedBuildDateLooksLikeADate;
var
  I: TAboutInfo;
begin
  I := CollectAboutInfo('pt', 'claro', '');
  Assert.IsTrue((I.BuildDate = '?') or (Length(I.BuildDate) = 16), 'aaaa-mm-dd hh:nn');
end;

procedure TSysInfoTests.ExeVersionIsEmptyOrFourNumbers;
var
  S: string;
begin
  S := ExeVersionText;
  if S = '' then
    Exit;                          // o executavel dos testes pode nao ter recurso de versao
  Assert.IsTrue(ParseAppVersion(S).Valid, S);
  Assert.AreEqual<NativeInt>(4, Length(S.Split(['.'])));
end;

initialization
  TDUnitX.RegisterTestFixture(TAppInfoTests);
  TDUnitX.RegisterTestFixture(TSysInfoTests);

end.
