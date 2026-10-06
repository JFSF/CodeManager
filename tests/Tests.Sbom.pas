unit Tests.Sbom;

// Testes do modelo de SBOM (CM.Sbom): classificacao pelo nome e montagem a partir do grafo de dependencias.

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Deps, CM.Sbom;

type
  [TestFixture]
  TSbomClassifyTests = class
  public
    [Test] procedure NamespacesOfTheRtl;
    [Test] procedure VclAndFmxHaveTheirOwnOrigin;
    [Test] procedure OldUnitsWithoutNamespaceAreRecognised;
    [Test] procedure ClassificationIgnoresCase;
    [Test] procedure OtherNamesAreThirdParty;
    [Test] procedure NamesAreWrittenInEnglish;
  end;

  [TestFixture]
  TSbomBuildTests = class
  private
    FGraph: TDepGraph;
    FProject: TSbomProject;
    function Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean = False): TDepInput;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure EveryExternalUnitBecomesOneComponent;
    [Test] procedure ComponentsKnowWhoUsesThem;
    [Test] procedure ExternalComponentsStartWithWeakOrMediumConfidence;
    [Test] procedure ComponentsAreSortedByOriginAndName;
    [Test] procedure ProjectUnitsAreOptional;
    [Test] procedure ProjectUnitsKnowTheirDependents;
    [Test] procedure CountsFollowTheComponents;
    [Test] procedure NoGraphGivesAnEmptySbom;
    [Test] procedure TheProjectIsKept;
    [Test] procedure ObtainIsCaseInsensitive;
    [Test] procedure ProjectUnitsAreRememberedEvenWhenNotListed;
  end;

implementation

{ TSbomClassifyTests }

procedure TSbomClassifyTests.NamespacesOfTheRtl;
begin
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('System.SysUtils')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('Winapi.Windows')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('Data.DB')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('Xml.XMLDoc')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('REST.Client')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('System')));
end;

procedure TSbomClassifyTests.VclAndFmxHaveTheirOwnOrigin;
begin
  Assert.AreEqual(Ord(soVcl), Ord(ClassifyUnitName('Vcl.Forms')));
  Assert.AreEqual(Ord(soFmx), Ord(ClassifyUnitName('FMX.Types')));
  Assert.AreEqual(Ord(soFmx), Ord(ClassifyUnitName('Fmx.Controls')));
end;

procedure TSbomClassifyTests.OldUnitsWithoutNamespaceAreRecognised;
begin
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('SysUtils')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('Windows')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('Classes')));
  Assert.AreEqual(Ord(soVcl), Ord(ClassifyUnitName('Forms')));
  Assert.AreEqual(Ord(soVcl), Ord(ClassifyUnitName('Controls')));
end;

procedure TSbomClassifyTests.ClassificationIgnoresCase;
begin
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('system.sysutils')));
  Assert.AreEqual(Ord(soVcl), Ord(ClassifyUnitName('VCL.FORMS')));
  Assert.AreEqual(Ord(soRtl), Ord(ClassifyUnitName('SYSUTILS')));
end;

procedure TSbomClassifyTests.OtherNamesAreThirdParty;
begin
  Assert.AreEqual(Ord(soThirdParty), Ord(ClassifyUnitName('Chart4D.FMX')));
  Assert.AreEqual(Ord(soThirdParty), Ord(ClassifyUnitName('DUnitX.TestFramework')));
  Assert.AreEqual(Ord(soThirdParty), Ord(ClassifyUnitName('Spring.Collections')));
  Assert.AreEqual(Ord(soThirdParty), Ord(ClassifyUnitName('MinhaUnit')));
  Assert.AreEqual(Ord(soThirdParty), Ord(ClassifyUnitName('Systematic')), 'nao e o namespace System');
end;

procedure TSbomClassifyTests.NamesAreWrittenInEnglish;
begin
  Assert.AreEqual('Embarcadero RTL', OriginName(soRtl));
  Assert.AreEqual('Embarcadero VCL', OriginName(soVcl));
  Assert.AreEqual('Embarcadero FMX', OriginName(soFmx));
  Assert.AreEqual('Third party', OriginName(soThirdParty));
  Assert.AreEqual('Local project', OriginName(soProject));
  Assert.AreEqual('Strong', ConfidenceName(scStrong));
  Assert.AreEqual('Medium', ConfidenceName(scMedium));
  Assert.AreEqual('Weak', ConfidenceName(scWeak));
  Assert.AreEqual('Uses', EvidenceName(seUses));
  Assert.AreEqual('File', EvidenceName(seFile));
  Assert.AreEqual('Map', EvidenceName(seMap));
end;

{ TSbomBuildTests }

function TSbomBuildTests.Inp(const AName, ALayer: string; const AIface, AImpl: array of string; AProgram: Boolean): TDepInput;
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

procedure TSbomBuildTests.Setup;
begin
  FGraph := BuildDepGraph([
    Inp('App', 'Raiz', ['Vcl.Forms', 'UI.Main'], [], True),
    Inp('UI.Main', 'UI', ['Core.A', 'Vcl.Forms'], ['System.SysUtils', 'Chart4D.FMX']),
    Inp('Core.A', 'Core', [], ['System.SysUtils', 'DUnitX.TestFramework'])]);
  FProject := Default(TSbomProject);
  FProject.Name := 'App';
  FProject.Version := '1.2.3.4';
end;

procedure TSbomBuildTests.TearDown;
begin
  FGraph.Free;
end;

procedure TSbomBuildTests.EveryExternalUnitBecomesOneComponent;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    // Vcl.Forms (usada por duas units), System.SysUtils (duas), Chart4D.FMX e DUnitX.TestFramework
    Assert.AreEqual<NativeInt>(4, S.Components.Count);
    Assert.IsNotNull(S.Find('Vcl.Forms'));
    Assert.IsNotNull(S.Find('System.SysUtils'));
    Assert.IsNotNull(S.Find('Chart4D.FMX'));
    Assert.IsNotNull(S.Find('DUnitX.TestFramework'));
    Assert.IsNull(S.Find('UI.Main'), 'as units do projecto ficam de fora por omissao');
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ComponentsKnowWhoUsesThem;
var
  S: TSbom;
  C: TSbomComponent;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    C := S.Find('System.SysUtils');
    Assert.AreEqual<NativeInt>(2, Length(C.UsedBy));
    Assert.AreEqual('Core.A', C.UsedBy[0], 'por ordem alfabetica');
    Assert.AreEqual('UI.Main', C.UsedBy[1]);
    C := S.Find('Chart4D.FMX');
    Assert.AreEqual<NativeInt>(1, Length(C.UsedBy));
    Assert.AreEqual('UI.Main', C.UsedBy[0]);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ExternalComponentsStartWithWeakOrMediumConfidence;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    Assert.AreEqual(Ord(scMedium), Ord(S.Find('System.SysUtils').Confidence), 'nome da Embarcadero');
    Assert.AreEqual(Ord(scWeak), Ord(S.Find('Chart4D.FMX').Confidence), 'so se conhece pelo nome');
    Assert.AreEqual(Ord(seUses), Ord(S.Find('Chart4D.FMX').Evidence));
    Assert.AreEqual('', S.Find('Chart4D.FMX').Path);
    Assert.AreEqual('', S.Find('Chart4D.FMX').Hash);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ComponentsAreSortedByOriginAndName;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    Assert.AreEqual('System.SysUtils', S.Components[0].Name, 'RTL primeiro');
    Assert.AreEqual('Vcl.Forms', S.Components[1].Name, 'depois a VCL');
    Assert.AreEqual('Chart4D.FMX', S.Components[2].Name, 'terceiros no fim, por nome');
    Assert.AreEqual('DUnitX.TestFramework', S.Components[3].Name);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ProjectUnitsAreOptional;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, True);
  try
    Assert.AreEqual<NativeInt>(7, S.Components.Count);
    Assert.AreEqual(3, S.CountOf(soProject));
    Assert.AreEqual(Ord(soProject), Ord(S.Components[0].Origin), 'as do projecto vem primeiro');
    Assert.AreEqual(Ord(seFile), Ord(S.Find('UI.Main').Evidence));
    Assert.AreEqual('UI', S.Find('UI.Main').Layer);
    Assert.AreEqual('UI.Main.pas', S.Find('UI.Main').RelPath);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ProjectUnitsKnowTheirDependents;
var
  S: TSbom;
  C: TSbomComponent;
begin
  S := BuildSbom(FGraph, FProject, True);
  try
    C := S.Find('Core.A');
    Assert.AreEqual<NativeInt>(1, Length(C.UsedBy));
    Assert.AreEqual('UI.Main', C.UsedBy[0]);
    Assert.AreEqual<NativeInt>(0, Length(S.Find('App').UsedBy), 'o programa ninguem o usa');
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.CountsFollowTheComponents;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    Assert.AreEqual(1, S.CountOf(soRtl));
    Assert.AreEqual(1, S.CountOf(soVcl));
    Assert.AreEqual(0, S.CountOf(soFmx));
    Assert.AreEqual(2, S.CountOf(soThirdParty));
    Assert.AreEqual(2, S.CountByConfidence(scMedium));
    Assert.AreEqual(2, S.CountByConfidence(scWeak));
    Assert.AreEqual(0, S.CountByConfidence(scStrong));
    Assert.AreEqual(0, S.ResolvedCount, 'ainda nada foi resolvido para ficheiros');
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.NoGraphGivesAnEmptySbom;
var
  S: TSbom;
begin
  S := BuildSbom(nil, FProject, True);
  try
    Assert.AreEqual<NativeInt>(0, S.Components.Count);
    Assert.AreEqual('App', S.Project.Name);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.TheProjectIsKept;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    Assert.AreEqual('App', S.Project.Name);
    Assert.AreEqual('1.2.3.4', S.Project.Version);
    Assert.IsTrue(S.Generated > 0);
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ProjectUnitsAreRememberedEvenWhenNotListed;
var
  S: TSbom;
begin
  S := BuildSbom(FGraph, FProject, False);
  try
    Assert.IsNull(S.Find('UI.Main'));
    Assert.IsTrue(S.IsProjectUnit('UI.Main'));
    Assert.IsTrue(S.IsProjectUnit('ui.main'), 'sem distinguir maiusculas');
    Assert.IsTrue(S.IsProjectUnit('App'));
    Assert.IsFalse(S.IsProjectUnit('System.SysUtils'));
  finally
    S.Free;
  end;
end;

procedure TSbomBuildTests.ObtainIsCaseInsensitive;
var
  S: TSbom;
  A, B: TSbomComponent;
  Created: Boolean;
begin
  S := TSbom.Create;
  try
    A := S.Obtain('System.SysUtils', Created);
    Assert.IsTrue(Created);
    B := S.Obtain('system.sysutils', Created);
    Assert.IsFalse(Created);
    Assert.IsTrue(A = B);
    Assert.AreEqual<NativeInt>(1, S.Components.Count);
  finally
    S.Free;
  end;
end;

end.
