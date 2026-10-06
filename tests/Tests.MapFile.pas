unit Tests.MapFile;

// Testes do leitor de .map (CM.MapFile), da sua aplicacao ao SBOM e da procura do ficheiro (CM.SbomResolve).

interface

uses
  System.SysUtils, System.IOUtils, DUnitX.TestFramework, CM.MapFile, CM.Sbom, CM.Dproj, CM.SbomResolve, Tests.Helpers;

type
  [TestFixture]
  TMapFileTests = class
  private
    function SampleMap: string;
  public
    [Test] procedure ReadsTheUnitsOfTheDetailedSegments;
    [Test] procedure ReadsTheLineNumberHeaders;
    [Test] procedure UnitsAreUniqueIgnoringCase;
    [Test] procedure OtherLinesAreIgnored;
    [Test] procedure EmptyTextHasNoUnits;
    [Test] procedure LoadsAFileAndIgnoresAMissingOne;
    [Test] procedure MapUnitsConfirmTheExistingComponents;
    [Test] procedure MapUnitsNotInTheCodeBecomeComponents;
    [Test] procedure ProjectUnitsInTheMapAreNotDependencies;
    [Test] procedure ProjectUnitsInTheMapConfirmTheListedOnes;
    [Test] procedure ComponentsOutsideTheMapAreCounted;
    [Test] procedure WithoutAMapNothingIsOutside;
    [Test] procedure NilSbomIsIgnored;
    [Test] procedure ResolvingKeepsTheMapEvidence;
    [Test] procedure FindsTheMapNextToTheExecutable;
    [Test] procedure FindsTheMapInThePlatformAndConfigurationFolder;
    [Test] procedure NoMapMeansEmpty;
  end;

implementation

function TMapFileTests.SampleMap: string;
begin
  Result :=
    ' Start         Length     Name                   Class' + #13#10 +
    ' 0001:00401000 0000F234H  .text                  CODE' + #13#10 +
    '' + #13#10 +
    'Detailed map of segments' + #13#10 +
    ' 0001:00000000 000071A4 C=CODE     S=.text    G=(none)   M=System   ACBP=A9' + #13#10 +
    ' 0001:000071A4 00000FEC C=CODE     S=.text    G=(none)   M=SysInit  ACBP=A9' + #13#10 +
    ' 0001:00008190 00001D80 C=CODE     S=.text    G=(none)   M=System.SysUtils ACBP=A9' + #13#10 +
    ' 0001:00009F10 00000B58 C=CODE     S=.text    G=(none)   M=Chart4D.FMX ACBP=A9' + #13#10 +
    ' 0001:0000AA68 00000200 C=CODE     S=.text    G=(none)   M=Main ACBP=A9' + #13#10 +
    '' + #13#10 +
    'Line numbers for System(System.pas) segment .text' + #13#10 +
    '  1234 0001:00000000' + #13#10 +
    'Line numbers for Vcl.Forms(Vcl.Forms.pas) segment .text' + #13#10 +
    '  99 0001:0000B000' + #13#10;
end;

procedure TMapFileTests.ReadsTheUnitsOfTheDetailedSegments;
var
  U: TArray<string>;
begin
  U := ParseMapUnits(SampleMap);
  Assert.AreEqual<NativeInt>(6, Length(U), 'cinco dos segmentos mais Vcl.Forms dos numeros de linha');
  Assert.AreEqual('System', U[0]);
  Assert.AreEqual('SysInit', U[1]);
  Assert.AreEqual('System.SysUtils', U[2]);
  Assert.AreEqual('Chart4D.FMX', U[3]);
  Assert.AreEqual('Main', U[4]);
end;

procedure TMapFileTests.ReadsTheLineNumberHeaders;
var
  U: TArray<string>;
begin
  U := ParseMapUnits('Line numbers for Vcl.Forms(Vcl.Forms.pas) segment .text');
  Assert.AreEqual<NativeInt>(1, Length(U));
  Assert.AreEqual('Vcl.Forms', U[0]);
end;

procedure TMapFileTests.UnitsAreUniqueIgnoringCase;
var
  U: TArray<string>;
begin
  U := ParseMapUnits(' 0001:0 1 C=CODE M=System ACBP=A9' + #10 + ' 0001:1 1 C=CODE M=SYSTEM ACBP=A9' + #10 +
    'Line numbers for system(System.pas) segment .text');
  Assert.AreEqual<NativeInt>(1, Length(U));
  Assert.AreEqual('System', U[0], 'fica a primeira forma que aparece');
end;

procedure TMapFileTests.OtherLinesAreIgnored;
begin
  Assert.AreEqual<NativeInt>(0, Length(ParseMapUnits(' Start Length Name Class' + #10 + ' 0001:00401000 0000F234H .text CODE' +
    #10 + 'Program entry point at 0001:0000B1A4')));
end;

procedure TMapFileTests.EmptyTextHasNoUnits;
begin
  Assert.AreEqual<NativeInt>(0, Length(ParseMapUnits('')));
end;

procedure TMapFileTests.LoadsAFileAndIgnoresAMissingOne;
var
  Dir: TTempDir;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('Demo.map', SampleMap);
    Assert.AreEqual<NativeInt>(6, Length(LoadMapUnits(Dir.Full('Demo.map'))));
    Assert.AreEqual<NativeInt>(0, Length(LoadMapUnits(Dir.Full('nao.map'))));
    Assert.AreEqual<NativeInt>(0, Length(LoadMapUnits('')));
  finally
    Dir.Free;
  end;
end;

procedure TMapFileTests.MapUnitsConfirmTheExistingComponents;
var
  S: TSbom;
  C: TSbomComponent;
  Created: Boolean;
begin
  S := TSbom.Create;
  try
    C := S.Obtain('System.SysUtils', Created);
    C.Origin := soRtl;
    C.Evidence := seUses;
    C.Confidence := scMedium;
    ApplyMapUnits(S, ParseMapUnits(SampleMap), 'C:\out\Demo.map');
    Assert.IsTrue(C.InMap);
    Assert.AreEqual(Ord(seMap), Ord(C.Evidence));
    Assert.AreEqual(Ord(scMedium), Ord(C.Confidence), 'a confianca nao muda: depende de se achar o ficheiro');
    Assert.AreEqual('C:\out\Demo.map', S.MapFile);
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.MapUnitsNotInTheCodeBecomeComponents;
var
  S: TSbom;
begin
  S := TSbom.Create;
  try
    ApplyMapUnits(S, ParseMapUnits(SampleMap), 'Demo.map');
    Assert.AreEqual<NativeInt>(6, S.Components.Count);
    Assert.AreEqual(Ord(soRtl), Ord(S.Find('SysInit').Origin));
    Assert.AreEqual(Ord(scMedium), Ord(S.Find('SysInit').Confidence));
    Assert.AreEqual(Ord(soThirdParty), Ord(S.Find('Chart4D.FMX').Origin));
    Assert.AreEqual(Ord(scWeak), Ord(S.Find('Chart4D.FMX').Confidence));
    Assert.AreEqual(Ord(soVcl), Ord(S.Find('Vcl.Forms').Origin));
    Assert.IsTrue(S.Find('System').InMap);
    Assert.AreEqual(Ord(seMap), Ord(S.Find('System').Evidence));
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.ProjectUnitsInTheMapAreNotDependencies;
var
  S: TSbom;
begin
  S := TSbom.Create;
  try
    S.NoteProjectUnit('Main');                  // uma unit do projecto que o SBOM nao lista
    ApplyMapUnits(S, ParseMapUnits(SampleMap), 'Demo.map');
    Assert.IsNull(S.Find('Main'), 'o mapa traz Main, mas e do projecto e o SBOM so lista dependencias');
    Assert.IsTrue(S.IsProjectUnit('main'));
    Assert.IsNotNull(S.Find('Chart4D.FMX'));
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.ProjectUnitsInTheMapConfirmTheListedOnes;
var
  S: TSbom;
  C: TSbomComponent;
  Created: Boolean;
begin
  S := TSbom.Create;
  try
    S.NoteProjectUnit('Main');
    C := S.Obtain('Main', Created);                // desta vez o SBOM lista-a
    C.Origin := soProject;
    ApplyMapUnits(S, ParseMapUnits(SampleMap), 'Demo.map');
    Assert.IsTrue(C.InMap);
    Assert.AreEqual(Ord(seMap), Ord(C.Evidence));
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.ComponentsOutsideTheMapAreCounted;
var
  S: TSbom;
  Created: Boolean;
begin
  S := TSbom.Create;
  try
    S.Obtain('Referenciada.Mas.Fora', Created).Origin := soThirdParty;
    ApplyMapUnits(S, ParseMapUnits(SampleMap), 'Demo.map');
    Assert.AreEqual(1, S.NotLinkedCount);
    Assert.IsFalse(S.Find('Referenciada.Mas.Fora').InMap);
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.WithoutAMapNothingIsOutside;
var
  S: TSbom;
  Created: Boolean;
begin
  S := TSbom.Create;
  try
    S.Obtain('X', Created);
    Assert.AreEqual(0, S.NotLinkedCount);
  finally
    S.Free;
  end;
end;

procedure TMapFileTests.NilSbomIsIgnored;
begin
  ApplyMapUnits(nil, ['System'], 'x.map');
  Assert.Pass;
end;

procedure TMapFileTests.ResolvingKeepsTheMapEvidence;
var
  S: TSbom;
  Dir: TTempDir;
  Opt: TSbomResolveOptions;
begin
  Dir := TTempDir.Create;
  S := TSbom.Create;
  try
    Dir.Write('libs/Chart4D.FMX.pas', 'unit Chart4D.FMX;');
    ApplyMapUnits(S, ['Chart4D.FMX'], 'Demo.map');
    Opt := Default(TSbomResolveOptions);
    Opt.ProjectRoot := Dir.Full('proj');
    Opt.SearchPaths := [Dir.Full('libs')];
    ResolveSbom(S, Opt);
    Assert.AreNotEqual('', S.Find('Chart4D.FMX').Path);
    Assert.AreEqual(Ord(seMap), Ord(S.Find('Chart4D.FMX').Evidence), 'o mapa e a prova mais forte');
    Assert.AreEqual(Ord(scStrong), Ord(S.Find('Chart4D.FMX').Confidence));
  finally
    S.Free;
    Dir.Free;
  end;
end;

procedure TMapFileTests.FindsTheMapNextToTheExecutable;
var
  Dir: TTempDir;
  D: TDprojInfo;
begin
  Dir := TTempDir.Create;
  try
    D := Default(TDprojInfo);
    D.Found := True;
    D.FileName := Dir.Full('Demo.dproj');
    D.ProjectName := 'Demo';
    D.Platform := 'Win64';
    D.Config := 'Release';
    D.ExeOutput := '.\out\bin\Win64\Release';
    Dir.Write('out/bin/Win64/Release/Demo.map', 'map');
    Assert.AreEqual(TPath.GetFullPath(Dir.Full('out/bin/Win64/Release/Demo.map')), FindMapFile(D));
  finally
    Dir.Free;
  end;
end;

procedure TMapFileTests.FindsTheMapInThePlatformAndConfigurationFolder;
var
  Dir: TTempDir;
  D: TDprojInfo;
begin
  Dir := TTempDir.Create;
  try
    D := Default(TDprojInfo);
    D.Found := True;
    D.FileName := Dir.Full('Demo.dproj');
    D.ProjectName := 'Demo';
    D.Platform := 'Win32';
    D.Config := 'Debug';
    Dir.Write('Win32/Debug/Demo.map', 'map');
    Assert.AreEqual(TPath.GetFullPath(Dir.Full('Win32/Debug/Demo.map')), FindMapFile(D));
  finally
    Dir.Free;
  end;
end;

procedure TMapFileTests.NoMapMeansEmpty;
var
  Dir: TTempDir;
  D: TDprojInfo;
begin
  Dir := TTempDir.Create;
  try
    D := Default(TDprojInfo);
    Assert.AreEqual('', FindMapFile(D), 'sem projecto');
    D.Found := True;
    D.FileName := Dir.Full('Demo.dproj');
    D.ProjectName := 'Demo';
    D.Platform := 'Win64';
    D.Config := 'Release';
    Assert.AreEqual('', FindMapFile(D));
  finally
    Dir.Free;
  end;
end;

end.
