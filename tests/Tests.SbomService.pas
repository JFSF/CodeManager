unit Tests.SbomService;

// Testes da geracao do SBOM de ponta a ponta (CM.SbomService), com um projecto de pastas falsas.

interface

uses
  System.SysUtils, System.IOUtils, System.Hash, DUnitX.TestFramework, CM.Deps, CM.Sbom, CM.SbomService, Tests.Helpers;

type
  [TestFixture]
  TSbomServiceTests = class
  private
    FDir: TTempDir;
    FGraph: TDepGraph;
    FOptions: TSbomGenOptions;
    function Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean = False): TDepInput;
    function Gen: TSbom;
    procedure WriteProject(const AWithMap: Boolean);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ProjectDataComesFromTheDproj;
    [Test] procedure WithoutADprojTheAppNameIsUsedAndAWarningIsRaised;
    [Test] procedure ExternalUnitsAreResolvedToFilesAndHashes;
    [Test] procedure ProjectUnitsAreListedOnlyWhenAsked;
    [Test] procedure TheMapConfirmsAndAddsUnits;
    [Test] procedure AMissingMapRaisesAWarning;
    [Test] procedure TheMapCanBeSwitchedOff;
    [Test] procedure HashesCanBeSwitchedOff;
    [Test] procedure WithoutDelphiAWarningIsRaised;
    [Test] procedure SearchPathsOfTheDprojFindThirdPartyLibraries;
    [Test] procedure ConfigurationAndPlatformCanBeChosen;
    [Test] procedure ProgressIsReported;
    [Test] procedure DefaultsAreSensible;
    [Test] procedure FileNamesUseTheProjectSlug;
  end;

implementation

const
  DprojXml =
    '<Project>' + #13#10 +
    '<PropertyGroup><ProjectVersion>20.3</ProjectVersion><FrameworkType>VCL</FrameworkType><MainSource>Demo.dpr</MainSource>' +
    '<Base>True</Base></PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Base)''!=''''"><DCC_UnitSearchPath>libs\Chart;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    '<DCC_ExeOutput>.\out\$(Platform)\$(Config)</DCC_ExeOutput>' +
    '<VerInfo_Keys>CompanyName=Acme;FileDescription=Demo;FileVersion=2.0.0.1</VerInfo_Keys></PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_2)''!=''''"><Cfg_2>true</Cfg_2></PropertyGroup>' + #13#10 +
    '<PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_1)''!=''''"><Cfg_1>true</Cfg_1></PropertyGroup>' + #13#10 +
    '<ItemGroup><BuildConfiguration Include="Base"><Key>Base</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Debug"><Key>Cfg_1</Key></BuildConfiguration>' +
    '<BuildConfiguration Include="Release"><Key>Cfg_2</Key></BuildConfiguration></ItemGroup>' + #13#10 +
    '<ProjectExtensions><Platforms><Platform value="Win32">True</Platform><Platform value="Win64">True</Platform></Platforms></ProjectExtensions>' + #13#10 +
    '</Project>';

function TSbomServiceTests.Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean): TDepInput;
var
  I: Integer;
begin
  Result := Default(TDepInput);
  Result.Name := AName;
  Result.Path := AName + '.pas';
  Result.Layer := ALayer;
  Result.IsProgram := AProgram;
  SetLength(Result.InterfaceUses, Length(AIface));
  for I := 0 to High(AIface) do
    Result.InterfaceUses[I] := AIface[I];
  SetLength(Result.ImplUses, Length(AImpl));
  for I := 0 to High(AImpl) do
    Result.ImplUses[I] := AImpl[I];
end;

procedure TSbomServiceTests.WriteProject(const AWithMap: Boolean);
begin
  FDir.Write('proj/Demo.dproj', DprojXml);
  FDir.Write('proj/Main.pas', 'unit Main;');
  FDir.Write('proj/Core.pas', 'unit Core;');
  FDir.Write('proj/libs/Chart/Chart4D.FMX.pas', 'unit Chart4D.FMX;');
  FDir.Write('delphi/source/rtl/sys/System.SysUtils.pas', 'unit System.SysUtils;');
  FDir.Write('delphi/source/rtl/sys/System.Classes.pas', 'unit System.Classes;');
  FDir.Write('delphi/source/vcl/Vcl.Forms.pas', 'unit Vcl.Forms;');
  if AWithMap then
    FDir.Write('proj/out/Win64/Release/Demo.map',
      'Detailed map of segments' + #13#10 +
      ' 0001:00000000 000071A4 C=CODE S=.text G=(none) M=System ACBP=A9' + #13#10 +
      ' 0001:000071A4 00000FEC C=CODE S=.text G=(none) M=System.SysUtils ACBP=A9' + #13#10 +
      ' 0001:000081A4 00000FEC C=CODE S=.text G=(none) M=Chart4D.FMX ACBP=A9' + #13#10 +
      ' 0001:000091A4 00000200 C=CODE S=.text G=(none) M=Demo ACBP=A9' + #13#10);
end;

procedure TSbomServiceTests.Setup;
begin
  FDir := TTempDir.Create;
  FGraph := BuildDepGraph([
    Inp('Main', 'Raiz', ['Core', 'Vcl.Forms'], [], True),
    Inp('Core', 'Raiz', [], ['System.SysUtils', 'Chart4D.FMX', 'System.Classes'])]);
  FOptions := DefaultSbomGenOptions;
  FOptions.AutoDelphi := False;
  FOptions.DelphiRoot := FDir.Full('delphi');
end;

procedure TSbomServiceTests.TearDown;
begin
  FGraph.Free;
  FDir.Free;
end;

function TSbomServiceTests.Gen: TSbom;
begin
  Result := GenerateSbom(FGraph, FDir.Full('proj'), 'MeuDemo', FOptions);
end;

procedure TSbomServiceTests.ProjectDataComesFromTheDproj;
var
  S: TSbom;
begin
  WriteProject(False);
  S := Gen;
  try
    Assert.AreEqual('Demo', S.Project.Name, 'o nome do .dproj');
    Assert.AreEqual('2.0.0.1', S.Project.Version);
    Assert.AreEqual('Acme', S.Project.Company);
    Assert.AreEqual('Demo', S.Project.Description);
    Assert.AreEqual('VCL', S.Project.FrameworkType);
    Assert.AreEqual('Release', S.Project.Configuration, 'prefere a configuracao que se entrega');
    Assert.AreEqual('20.3', S.Project.DelphiVersion);
    Assert.AreEqual(FDir.Full('proj/Demo.dproj'), S.Project.ProjectFile);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.WithoutADprojTheAppNameIsUsedAndAWarningIsRaised;
var
  S: TSbom;
begin
  FDir.Write('proj/Main.pas', 'unit Main;');
  S := Gen;
  try
    Assert.AreEqual('MeuDemo', S.Project.Name);
    Assert.AreEqual('', S.Project.Version);
    Assert.IsTrue(S.Warnings.Contains('Não se encontrou o ficheiro .dproj: a versão e os caminhos de procura ficam por preencher.'));
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.ExternalUnitsAreResolvedToFilesAndHashes;
var
  S: TSbom;
  C: TSbomComponent;
begin
  WriteProject(False);
  S := Gen;
  try
    Assert.AreEqual<NativeInt>(4, S.Components.Count);
    C := S.Find('System.SysUtils');
    Assert.AreEqual(FDir.Full('delphi/source/rtl/sys/System.SysUtils.pas'), C.Path);
    Assert.AreEqual(Ord(soRtl), Ord(C.Origin));
    Assert.AreEqual(Ord(scStrong), Ord(C.Confidence));
    Assert.AreEqual(LowerCase(THashSHA2.GetHashStringFromFile(C.Path, THashSHA2.TSHA2Version.SHA256)), C.Hash);
    Assert.AreEqual(Ord(soVcl), Ord(S.Find('Vcl.Forms').Origin));
    C := S.Find('Chart4D.FMX');
    Assert.AreEqual(Ord(soThirdParty), Ord(C.Origin));
    Assert.AreEqual(Ord(scStrong), Ord(C.Confidence), 'achada nos caminhos de procura do .dproj');
    Assert.AreEqual(4, S.ResolvedCount);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.ProjectUnitsAreListedOnlyWhenAsked;
var
  S: TSbom;
begin
  WriteProject(False);
  S := Gen;
  try
    Assert.AreEqual(0, S.CountOf(soProject));
  finally
    S.Free;
  end;
  FOptions.IncludeProjectUnits := True;
  S := Gen;
  try
    Assert.AreEqual(2, S.CountOf(soProject));
    Assert.AreEqual(FDir.Full('proj/Main.pas'), S.Find('Main').Path);
    Assert.AreEqual<Integer>(64, Length(S.Find('Main').Hash));
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.TheMapConfirmsAndAddsUnits;
var
  S: TSbom;
begin
  WriteProject(True);
  S := Gen;
  try
    Assert.AreEqual('Demo.map', ExtractFileName(S.MapFile));
    Assert.IsTrue(S.Find('System.SysUtils').InMap);
    Assert.IsTrue(S.Find('Chart4D.FMX').InMap);
    Assert.IsFalse(S.Find('Vcl.Forms').InMap);
    Assert.IsNotNull(S.Find('System'), 'uma unit que so o mapa conhece passa a componente');
    Assert.IsNull(S.Find('Demo'), 'o programa principal do projecto nao e uma dependencia');
    Assert.AreEqual(Ord(seMap), Ord(S.Find('System.SysUtils').Evidence));
    Assert.AreEqual(Ord(seFile), Ord(S.Find('Vcl.Forms').Evidence), 'achada em ficheiro, mas fora do mapa');
    Assert.IsTrue(S.NotLinkedCount >= 2, 'Vcl.Forms e System.Classes nao estao no mapa');
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.AMissingMapRaisesAWarning;
var
  S: TSbom;
begin
  WriteProject(False);
  S := Gen;
  try
    Assert.AreEqual('', S.MapFile);
    Assert.IsTrue(S.Warnings.Contains('Não se encontrou o ficheiro .map: compila o projeto com o mapa «Detailed» para confirmar as units ligadas.'));
    Assert.AreEqual(0, S.NotLinkedCount);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.TheMapCanBeSwitchedOff;
var
  S: TSbom;
begin
  WriteProject(True);
  FOptions.UseMap := False;
  S := Gen;
  try
    Assert.AreEqual('', S.MapFile);
    Assert.IsFalse(S.Find('System.SysUtils').InMap);
    Assert.AreEqual<NativeInt>(4, S.Components.Count);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.HashesCanBeSwitchedOff;
var
  S: TSbom;
begin
  WriteProject(False);
  FOptions.ComputeHashes := False;
  S := Gen;
  try
    Assert.AreEqual('', S.Find('System.SysUtils').Hash);
    Assert.AreNotEqual('', S.Find('System.SysUtils').Path);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.WithoutDelphiAWarningIsRaised;
var
  S: TSbom;
begin
  WriteProject(False);
  FOptions.DelphiRoot := '';
  S := Gen;
  try
    Assert.IsTrue(S.Warnings.Contains('Não se encontrou a instalação do Delphi: as units da Embarcadero só se reconhecem pelo nome.'));
    Assert.AreEqual('', S.Find('System.SysUtils').Path);
    Assert.AreEqual(Ord(scMedium), Ord(S.Find('System.SysUtils').Confidence), 'continua a conhecer-se pelo nome');
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.SearchPathsOfTheDprojFindThirdPartyLibraries;
var
  S: TSbom;
begin
  WriteProject(False);
  S := Gen;
  try
    Assert.AreEqual(TPath.GetFullPath(FDir.Full('proj/libs/Chart/Chart4D.FMX.pas')), S.Find('Chart4D.FMX').Path);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.ConfigurationAndPlatformCanBeChosen;
var
  S: TSbom;
begin
  WriteProject(False);
  FOptions.Config := 'Debug';
  FOptions.Platform := 'Win32';
  S := Gen;
  try
    Assert.AreEqual('Debug', S.Project.Configuration);
    Assert.AreEqual('Win32', S.Project.Platform);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.ProgressIsReported;
var
  Calls: Integer;
  S: TSbom;
begin
  WriteProject(False);
  Calls := 0;
  S := GenerateSbom(FGraph, FDir.Full('proj'), 'MeuDemo', FOptions,
    procedure(const AMsg: string; ADone, ATotal: Integer)
    begin
      Inc(Calls);
    end);
  try
    Assert.IsTrue(Calls >= 2);
  finally
    S.Free;
  end;
end;

procedure TSbomServiceTests.DefaultsAreSensible;
var
  O: TSbomGenOptions;
begin
  O := DefaultSbomGenOptions;
  Assert.IsFalse(O.IncludeProjectUnits, 'o SBOM e das dependencias, nao do proprio codigo');
  Assert.IsTrue(O.UseMap);
  Assert.IsTrue(O.ComputeHashes);
  Assert.IsTrue(O.AutoDelphi);
end;

procedure TSbomServiceTests.FileNamesUseTheProjectSlug;
begin
  Assert.AreEqual('meu-projeto.cdx.json', SbomFileName('Meu Projeto', '.cdx.json'));
  Assert.AreEqual('x.spdx.json', SbomFileName('X!', '.spdx.json'));
  Assert.AreEqual('projeto.cdx.json', SbomFileName('', '.cdx.json'));
end;

end.
