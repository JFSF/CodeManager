unit Tests.Dproj;

// Testes da leitura do .dproj (CM.Dproj).

interface

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, Winapi.Windows, DUnitX.TestFramework, CM.Dproj,
  Tests.Helpers;

type
  [TestFixture]
  TDprojTests = class
  private
    function Sample: string;
    function Parse(const AConfig, APlatform: string): TDprojInfo;
  public
    [Test] procedure ReadsNameVersionAndKind;
    [Test] procedure PicksReleaseAndWin64WhenAsked;
    [Test] procedure DefaultsToTheFileOwnConfigAndPlatform;
    [Test] procedure ReadsTheVersionInformation;
    [Test] procedure SearchPathsJoinTheGroupsInOrder;
    [Test] procedure ConfigurationSpecificPathsOnlyAppearForThatConfiguration;
    [Test] procedure VariablesAreExpanded;
    [Test] procedure UnknownVariablesStayAsTheyAre;
    [Test] procedure SearchPathsHaveNoEmptyEntriesNorRepeats;
    [Test] procedure NamespacesAreRead;
    [Test] procedure MapFileModeFollowsTheConfiguration;
    [Test] procedure ListsTheConfigurationsAndPlatforms;
    [Test] procedure APackageIsDetected;
    [Test] procedure PropertiesDefinedByTheProjectExpandVariables;
    [Test] procedure AnEnvironmentVariableOverridesTheProjectDefault;
    [Test] procedure EmptyTextIsNotFound;
    [Test] procedure XmlEntitiesAreDecoded;
    [Test] procedure FindsTheDprojInTheFolderOrAbove;
    [Test] procedure PrefersTheDprojWithTheGivenName;
    [Test] procedure NoDprojMeansEmpty;
    [Test] procedure LoadsAFileFromDisk;
  end;

implementation

const
  Crlf = #13#10;

function TDprojTests.Sample: string;
begin
  Result :=
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + Crlf +
    '  <PropertyGroup>' + Crlf +
    '    <ProjectVersion>20.3</ProjectVersion>' + Crlf +
    '    <FrameworkType>FMX</FrameworkType>' + Crlf +
    '    <MainSource>Demo.dpr</MainSource>' + Crlf +
    '    <Base>True</Base>' + Crlf +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + Crlf +
    '    <Platform Condition="''$(Platform)''==''''">Win64</Platform>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">' + Crlf +
    '    <Base>true</Base>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''">' + Crlf +
    '    <Cfg_1>true</Cfg_1>' + Crlf +
    '    <Base>true</Base>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_2)''!=''''">' + Crlf +
    '    <Cfg_2>true</Cfg_2>' + Crlf +
    '    <Base>true</Base>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + Crlf +
    '    <DCC_Namespace>System;Xml;Data;FMX;$(DCC_Namespace)</DCC_Namespace>' + Crlf +
    '    <DCC_UnitSearchPath>src\Core;src\UI;$(CM_TEST_LIBDIR)\Source;..\Shared;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + Crlf +
    '    <DCC_ExeOutput>.\out\bin\$(Platform)\$(Config)</DCC_ExeOutput>' + Crlf +
    '    <VerInfo_Keys>CompanyName=Acme;FileDescription=Demo &amp; co;FileVersion=1.2.3.4;LegalCopyright=(c) Acme</VerInfo_Keys>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Base_Win64)''!=''''">' + Crlf +
    '    <DCC_Namespace>Data.Win;$(DCC_Namespace)</DCC_Namespace>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Cfg_1)''!=''''">' + Crlf +
    '    <DCC_MapFile>0</DCC_MapFile>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <PropertyGroup Condition="''$(Cfg_2)''!=''''">' + Crlf +
    '    <DCC_MapFile>3</DCC_MapFile>' + Crlf +
    '    <DCC_UnitSearchPath>src\Core;src\Release;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + Crlf +
    '  </PropertyGroup>' + Crlf +
    '  <ItemGroup>' + Crlf +
    '    <BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' + Crlf +
    '    <BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' + Crlf +
    '    <BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration>' + Crlf +
    '  </ItemGroup>' + Crlf +
    '  <ProjectExtensions><Delphi.Personality><Platforms>' + Crlf +
    '    <Platform value="Win32">False</Platform>' + Crlf +
    '    <Platform value="Win64">True</Platform>' + Crlf +
    '  </Platforms></Delphi.Personality></ProjectExtensions>' + Crlf +
    '</Project>';
end;

function TDprojTests.Parse(const AConfig, APlatform: string): TDprojInfo;
var
  Vars: TDictionary<string, string>;
begin
  Vars := TDictionary<string, string>.Create;
  try
    Vars.Add('cm_test_libdir', 'C:\Libs\Chart');
    ParseDproj(Sample, 'C:\Proj\Demo.dproj', AConfig, APlatform, Vars, Result);
  finally
    Vars.Free;
  end;
end;

procedure TDprojTests.ReadsNameVersionAndKind;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.IsTrue(D.Found);
  Assert.AreEqual('Demo', D.ProjectName);
  Assert.AreEqual('20.3', D.ProjectVersion);
  Assert.AreEqual('FMX', D.FrameworkType);
  Assert.AreEqual('Demo.dpr', D.MainSource);
  Assert.IsFalse(D.IsPackage);
end;

procedure TDprojTests.PicksReleaseAndWin64WhenAsked;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.AreEqual('Release', D.Config);
  Assert.AreEqual('Win64', D.Platform);
  Assert.AreEqual('.\out\bin\Win64\Release', D.ExeOutput);
end;

procedure TDprojTests.DefaultsToTheFileOwnConfigAndPlatform;
var
  D: TDprojInfo;
begin
  D := Parse('', '');
  // o ficheiro diz Debug, mas para o SBOM interessa a versao que se entrega: prefere Release quando existe
  Assert.AreEqual('Release', D.Config);
  Assert.AreEqual('Win64', D.Platform);
end;

procedure TDprojTests.ReadsTheVersionInformation;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.AreEqual('1.2.3.4', D.FileVersion);
  Assert.AreEqual('Demo & co', D.Description);
  Assert.AreEqual('Acme', D.Company);
  Assert.AreEqual('(c) Acme', D.Copyright);
end;

procedure TDprojTests.SearchPathsJoinTheGroupsInOrder;
var
  D: TDprojInfo;
begin
  D := Parse('Debug', 'Win64');
  Assert.AreEqual<NativeInt>(4, Length(D.UnitSearchPath));
  Assert.AreEqual('src\Core', D.UnitSearchPath[0]);
  Assert.AreEqual('src\UI', D.UnitSearchPath[1]);
  Assert.AreEqual('C:\Libs\Chart\Source', D.UnitSearchPath[2], 'a variavel do ambiente e expandida');
  Assert.AreEqual('..\Shared', D.UnitSearchPath[3]);
end;

procedure TDprojTests.ConfigurationSpecificPathsOnlyAppearForThatConfiguration;
var
  Debug, Release: TDprojInfo;
  P: string;
  InDebug, InRelease: Boolean;
begin
  Debug := Parse('Debug', 'Win64');
  Release := Parse('Release', 'Win64');
  InDebug := False;
  InRelease := False;
  for P in Debug.UnitSearchPath do
    if P = 'src\Release' then
      InDebug := True;
  for P in Release.UnitSearchPath do
    if P = 'src\Release' then
      InRelease := True;
  Assert.IsFalse(InDebug);
  Assert.IsTrue(InRelease);
end;

procedure TDprojTests.VariablesAreExpanded;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.IsFalse(D.UnitSearchPath[2].Contains('$('), D.UnitSearchPath[2]);
  Assert.IsFalse(D.ExeOutput.Contains('$('), D.ExeOutput);
end;

procedure TDprojTests.UnknownVariablesStayAsTheyAre;
var
  D: TDprojInfo;
  Xml: string;
begin
  Xml := StringReplace(Sample, '$(CM_TEST_LIBDIR)', '$(CM_VARIAVEL_QUE_NAO_EXISTE)', []);
  ParseDproj(Xml, 'C:\Proj\Demo.dproj', 'Debug', 'Win64', nil, D);
  Assert.AreEqual('$(CM_VARIAVEL_QUE_NAO_EXISTE)\Source', D.UnitSearchPath[2]);
end;

procedure TDprojTests.SearchPathsHaveNoEmptyEntriesNorRepeats;
var
  D: TDprojInfo;
  Xml: string;
begin
  Xml := StringReplace(Sample, 'src\Core;src\UI;', 'src\Core;;src\Core;SRC\CORE;src\UI;', []);
  ParseDproj(Xml, 'C:\Proj\Demo.dproj', 'Debug', 'Win64', nil, D);
  Assert.AreEqual<NativeInt>(4, Length(D.UnitSearchPath));
  Assert.AreEqual('src\Core', D.UnitSearchPath[0]);
  Assert.AreEqual('src\UI', D.UnitSearchPath[1]);
end;

procedure TDprojTests.NamespacesAreRead;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.AreEqual<NativeInt>(5, Length(D.Namespaces));
  Assert.AreEqual('Data.Win', D.Namespaces[0], 'o grupo da plataforma vem antes (leva o valor anterior)');
  Assert.AreEqual('System', D.Namespaces[1]);
  Assert.AreEqual('FMX', D.Namespaces[4]);
end;

procedure TDprojTests.MapFileModeFollowsTheConfiguration;
begin
  Assert.AreEqual(0, Parse('Debug', 'Win64').MapFileMode);
  Assert.AreEqual(3, Parse('Release', 'Win64').MapFileMode);
end;

procedure TDprojTests.ListsTheConfigurationsAndPlatforms;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.AreEqual<NativeInt>(2, Length(D.Configs), 'sem a "Base"');
  Assert.AreEqual('Debug', D.Configs[0]);
  Assert.AreEqual('Release', D.Configs[1]);
  Assert.AreEqual<NativeInt>(1, Length(D.Platforms), 'so as activas');
  Assert.AreEqual('Win64', D.Platforms[0]);
end;

procedure TDprojTests.APackageIsDetected;
var
  D: TDprojInfo;
begin
  ParseDproj(StringReplace(Sample, 'Demo.dpr', 'Demo.dpk', []), 'C:\Proj\Demo.dproj', 'Release', 'Win64', nil, D);
  Assert.IsTrue(D.IsPackage);
end;

procedure TDprojTests.PropertiesDefinedByTheProjectExpandVariables;
var
  D: TDprojInfo;
  Vars: TDictionary<string, string>;
  Xml: string;
begin
  // <CmTestLib Condition="'$(CmTestLib)'==''">$(CM_TEST_HOME)\Libs</CmTestLib> e depois $(CmTestLib)\Source no caminho de procura
  Xml := StringReplace(Sample, '<Base>True</Base>',
    '<Base>True</Base><CmTestLib Condition="''$(CmTestLib)''==''''">$(CM_TEST_HOME)\Libs</CmTestLib>', []);
  Xml := StringReplace(Xml, '$(CM_TEST_LIBDIR)\Source', '$(CmTestLib)\Source', []);
  Vars := TDictionary<string, string>.Create;
  try
    Vars.Add('cm_test_home', 'C:\Casa');
    ParseDproj(Xml, 'C:\Proj\Demo.dproj', 'Debug', 'Win64', Vars, D);
  finally
    Vars.Free;
  end;
  Assert.AreEqual('C:\Casa\Libs\Source', D.UnitSearchPath[2], 'a propriedade do projecto usa outra variavel');
end;

procedure TDprojTests.AnEnvironmentVariableOverridesTheProjectDefault;
var
  D: TDprojInfo;
  Xml: string;
begin
  Xml := StringReplace(Sample, '<Base>True</Base>',
    '<Base>True</Base><CmTestLib2 Condition="''$(CmTestLib2)''==''''">C:\Default</CmTestLib2>', []);
  Xml := StringReplace(Xml, '$(CM_TEST_LIBDIR)\Source', '$(CmTestLib2)\Source', []);
  SetEnvironmentVariable('CmTestLib2', 'C:\DoAmbiente');
  try
    ParseDproj(Xml, 'C:\Proj\Demo.dproj', 'Debug', 'Win64', nil, D);
  finally
    SetEnvironmentVariable('CmTestLib2', nil);
  end;
  Assert.AreEqual('C:\DoAmbiente\Source', D.UnitSearchPath[2], 'o ambiente ganha ao valor por omissao do projecto');
  ParseDproj(Xml, 'C:\Proj\Demo.dproj', 'Debug', 'Win64', nil, D);
  Assert.AreEqual('C:\Default\Source', D.UnitSearchPath[2], 'sem a variavel, vale o valor do projecto');
end;

procedure TDprojTests.EmptyTextIsNotFound;
var
  D: TDprojInfo;
begin
  ParseDproj('', 'C:\Proj\X.dproj', '', '', nil, D);
  Assert.IsFalse(D.Found);
  Assert.AreEqual('X', D.ProjectName);
  Assert.AreEqual<NativeInt>(0, Length(D.UnitSearchPath));
end;

procedure TDprojTests.XmlEntitiesAreDecoded;
var
  D: TDprojInfo;
begin
  D := Parse('Release', 'Win64');
  Assert.AreEqual('Demo & co', D.Description);
end;

procedure TDprojTests.FindsTheDprojInTheFolderOrAbove;
var
  Dir: TTempDir;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('Proj.dproj', '<Project/>');
    Dir.Write('src/Core/a.pas', 'unit a;');
    Assert.AreEqual(Dir.Full('Proj.dproj'), FindDprojFile(Dir.Path, 'Proj'), 'na propria pasta');
    Assert.AreEqual(Dir.Full('Proj.dproj'), FindDprojFile(Dir.Full('src/Core'), 'Proj'), 'duas pastas acima');
  finally
    Dir.Free;
  end;
end;

procedure TDprojTests.PrefersTheDprojWithTheGivenName;
var
  Dir: TTempDir;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('A.dproj', '<Project/>');
    Dir.Write('B.dproj', '<Project/>');
    Assert.AreEqual(Dir.Full('B.dproj'), FindDprojFile(Dir.Path, 'B'));
    Assert.AreEqual(Dir.Full('A.dproj'), FindDprojFile(Dir.Path, 'Outro'), 'sem o nome, o primeiro por ordem alfabetica');
  finally
    Dir.Free;
  end;
end;

procedure TDprojTests.NoDprojMeansEmpty;
var
  Dir: TTempDir;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('src/a.pas', 'unit a;');
    Assert.AreEqual('', FindDprojFile('', 'X'));
    Assert.AreEqual('', FindDprojFile('   ', 'X'));
  finally
    Dir.Free;
  end;
end;

procedure TDprojTests.LoadsAFileFromDisk;
var
  Dir: TTempDir;
  D: TDprojInfo;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('Demo.dproj', Sample);
    LoadDproj(Dir.Full('Demo.dproj'), 'Release', 'Win64', nil, D);
    Assert.IsTrue(D.Found);
    Assert.AreEqual('Demo', D.ProjectName);
    Assert.AreEqual('1.2.3.4', D.FileVersion);
    LoadDproj(Dir.Full('naoexiste.dproj'), '', '', nil, D);
    Assert.IsFalse(D.Found);
  finally
    Dir.Free;
  end;
end;

end.
