unit Tests.SbomResolve;

// Testes da resolucao dos componentes do SBOM para ficheiros (CM.SbomResolve), com uma arvore de pastas falsa:
// um projecto, uma "instalacao do Delphi" e duas bibliotecas de terceiros.

interface

uses
  System.SysUtils, System.IOUtils, System.Hash, DUnitX.TestFramework, CM.Sbom, CM.SbomResolve, Tests.Helpers;

type
  [TestFixture]
  TSbomResolveTests = class
  private
    FDir: TTempDir;
    FSbom: TSbom;
    FOptions: TSbomResolveOptions;
    function Add(const AName: string; AOrigin: TSbomOrigin; const ARelPath: string = ''): TSbomComponent;
    function Delphi: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ProjectUnitsResolveByTheirRelativePath;
    [Test] procedure EmbarcaderoUnitsAreFoundInTheDelphiSource;
    [Test] procedure VclAndFmxAreToldApartByNameOrFolder;
    [Test] procedure OldNamesWithoutNamespaceUseTheScopes;
    [Test] procedure ThirdPartyIsFoundInTheProjectSearchPaths;
    [Test] procedure PasIsPreferredOverDcu;
    [Test] procedure DcuIsTheFallback;
    [Test] procedure UnknownUnitsKeepTheirWeakConfidence;
    [Test] procedure HashesAreSha256OfTheFile;
    [Test] procedure HashesCanBeSkipped;
    [Test] procedure LibrariesCopiedIntoTheProjectFolderStayThirdParty;
    [Test] procedure SearchPathsAreRelativeToTheProjectFile;
    [Test] procedure ProgressIsReported;
    [Test] procedure NilSbomIsIgnored;
    [Test] procedure SortingFollowsTheRefinedOrigin;
    [Test] procedure FileHashOfAMissingFileIsEmpty;
    [Test] procedure FolderContainmentIgnoresCaseAndSiblings;
    [Test] procedure DelphiRootIsEmptyOrAnExistingFolder;
    [Test] procedure LibraryPathsNeedARoot;
  end;

implementation

function TSbomResolveTests.Delphi: string;
begin
  Result := FDir.Full('delphi');
end;

function TSbomResolveTests.Add(const AName: string; AOrigin: TSbomOrigin; const ARelPath: string): TSbomComponent;
var
  Created: Boolean;
begin
  Result := FSbom.Obtain(AName, Created);
  Result.Origin := AOrigin;
  Result.Evidence := seUses;
  Result.Confidence := scMedium;
  Result.RelPath := ARelPath;
end;

procedure TSbomResolveTests.Setup;
begin
  FDir := TTempDir.Create;
  FSbom := TSbom.Create;
  // o projecto
  FDir.Write('proj/Demo.dproj', '<Project/>');
  FDir.Write('proj/src/Core/a.pas', 'unit a;');
  // a instalacao do Delphi
  FDir.Write('delphi/source/rtl/sys/System.SysUtils.pas', 'unit System.SysUtils;');
  FDir.Write('delphi/source/rtl/win/Winapi.Windows.pas', 'unit Winapi.Windows;');
  FDir.Write('delphi/source/vcl/Vcl.Forms.pas', 'unit Vcl.Forms;');
  FDir.Write('delphi/source/vcl/Controls.Helper.pas', 'unit Controls.Helper;');
  FDir.Write('delphi/source/fmx/Fmx.Types.pas', 'unit Fmx.Types;');
  FDir.Write('delphi/source/fmx/Plain.Unit.pas', 'unit Plain.Unit;');
  // terceiros
  FDir.Write('libs/Chart/Chart4D.FMX.pas', 'unit Chart4D.FMX;');
  FDir.Write('libs/Spring/Spring.Collections.pas', 'unit Spring.Collections;');
  FDir.Write('libs/Spring/Spring.Collections.dcu', 'dcu');
  FDir.Write('libs/Only/Only.Compiled.dcu', 'compiled');
  FOptions := Default(TSbomResolveOptions);
  FOptions.ProjectRoot := FDir.Full('proj');
  FOptions.ProjectDir := FDir.Full('proj');
  FOptions.DelphiRoot := Delphi;
  FOptions.ComputeHashes := True;
  FOptions.SearchPaths := [FDir.Full('libs/Chart'), FDir.Full('libs/Spring'), FDir.Full('libs/Only')];
end;

procedure TSbomResolveTests.TearDown;
begin
  FSbom.Free;
  FDir.Free;
end;

procedure TSbomResolveTests.ProjectUnitsResolveByTheirRelativePath;
var
  C: TSbomComponent;
begin
  C := Add('a', soProject, 'src/Core/a.pas');
  C.Evidence := seFile;
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('proj/src/Core/a.pas'), C.Path);
  Assert.AreEqual(Ord(soProject), Ord(C.Origin));
  Assert.AreEqual(Ord(scStrong), Ord(C.Confidence));
  Assert.AreEqual<Integer>(64, Length(C.Hash));
end;

procedure TSbomResolveTests.EmbarcaderoUnitsAreFoundInTheDelphiSource;
var
  C: TSbomComponent;
begin
  C := Add('System.SysUtils', soRtl);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('delphi/source/rtl/sys/System.SysUtils.pas'), C.Path);
  Assert.AreEqual(Ord(soRtl), Ord(C.Origin));
  Assert.AreEqual(Ord(scStrong), Ord(C.Confidence));
  Assert.AreEqual(Ord(seFile), Ord(C.Evidence));
end;

procedure TSbomResolveTests.VclAndFmxAreToldApartByNameOrFolder;
begin
  Add('Vcl.Forms', soThirdParty);
  Add('Fmx.Types', soThirdParty);
  Add('Controls.Helper', soThirdParty);
  Add('Plain.Unit', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(Ord(soVcl), Ord(FSbom.Find('Vcl.Forms').Origin), 'pelo nome');
  Assert.AreEqual(Ord(soFmx), Ord(FSbom.Find('Fmx.Types').Origin), 'pelo nome');
  Assert.AreEqual(Ord(soVcl), Ord(FSbom.Find('Controls.Helper').Origin), 'pela pasta source\vcl');
  Assert.AreEqual(Ord(soFmx), Ord(FSbom.Find('Plain.Unit').Origin), 'pela pasta source\fmx');
end;

procedure TSbomResolveTests.OldNamesWithoutNamespaceUseTheScopes;
var
  C: TSbomComponent;
begin
  C := Add('SysUtils', soRtl);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('delphi/source/rtl/sys/System.SysUtils.pas'), C.Path);
  C := Add('Forms', soVcl);
  FOptions.Namespaces := ['Vcl'];
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('delphi/source/vcl/Vcl.Forms.pas'), C.Path);
end;

procedure TSbomResolveTests.ThirdPartyIsFoundInTheProjectSearchPaths;
var
  C: TSbomComponent;
begin
  C := Add('Chart4D.FMX', soThirdParty);
  C.Confidence := scWeak;
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('libs/Chart/Chart4D.FMX.pas'), C.Path);
  Assert.AreEqual(Ord(soThirdParty), Ord(C.Origin), 'fora do projecto e da instalacao do Delphi');
  Assert.AreEqual(Ord(scStrong), Ord(C.Confidence), 'passou de fraca a forte');
end;

procedure TSbomResolveTests.PasIsPreferredOverDcu;
var
  C: TSbomComponent;
begin
  C := Add('Spring.Collections', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual('.pas', TPath.GetExtension(C.Path));
end;

procedure TSbomResolveTests.DcuIsTheFallback;
var
  C: TSbomComponent;
begin
  C := Add('Only.Compiled', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(FDir.Full('libs/Only/Only.Compiled.dcu'), C.Path);
  Assert.AreEqual(Ord(scStrong), Ord(C.Confidence));
end;

procedure TSbomResolveTests.UnknownUnitsKeepTheirWeakConfidence;
var
  C: TSbomComponent;
begin
  C := Add('Nao.Existe', soThirdParty);
  C.Confidence := scWeak;
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual('', C.Path);
  Assert.AreEqual('', C.Hash);
  Assert.AreEqual(Ord(scWeak), Ord(C.Confidence));
  Assert.AreEqual(Ord(seUses), Ord(C.Evidence));
  Assert.AreEqual(0, FSbom.ResolvedCount);
end;

procedure TSbomResolveTests.HashesAreSha256OfTheFile;
var
  C: TSbomComponent;
begin
  C := Add('Chart4D.FMX', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(LowerCase(THashSHA2.GetHashStringFromFile(C.Path, THashSHA2.TSHA2Version.SHA256)), C.Hash);
  Assert.AreEqual(C.Hash, LowerCase(C.Hash), 'em minusculas');
end;

procedure TSbomResolveTests.HashesCanBeSkipped;
var
  C: TSbomComponent;
begin
  FOptions.ComputeHashes := False;
  C := Add('Chart4D.FMX', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreNotEqual('', C.Path);
  Assert.AreEqual('', C.Hash);
end;

procedure TSbomResolveTests.LibrariesCopiedIntoTheProjectFolderStayThirdParty;
var
  C: TSbomComponent;
begin
  // uma biblioteca copiada para a pasta do projecto (modules\, libs\) e uma dependencia, nao codigo do projecto
  FDir.Write('proj/modules/Extra.Unit.pas', 'unit Extra.Unit;');
  FOptions.SearchPaths := [FDir.Full('proj/modules')];
  C := Add('Extra.Unit', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(Ord(soThirdParty), Ord(C.Origin));
  Assert.AreEqual(Ord(scStrong), Ord(C.Confidence));
end;

procedure TSbomResolveTests.SearchPathsAreRelativeToTheProjectFile;
var
  C: TSbomComponent;
begin
  FOptions.SearchPaths := ['..\libs\Chart'];
  C := Add('Chart4D.FMX', soThirdParty);
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual(TPath.GetFullPath(FDir.Full('libs/Chart/Chart4D.FMX.pas')), C.Path);
end;

procedure TSbomResolveTests.ProgressIsReported;
var
  Calls, LastTotal, LastDone: Integer;
begin
  Calls := 0;
  LastTotal := 0;
  LastDone := 0;
  Add('Chart4D.FMX', soThirdParty);
  Add('System.SysUtils', soRtl);
  ResolveSbom(FSbom, FOptions,
    procedure(const AMsg: string; ADone, ATotal: Integer)
    begin
      Inc(Calls);
      LastDone := ADone;
      LastTotal := ATotal;
    end);
  Assert.IsTrue(Calls >= 2);
  Assert.AreEqual(2, LastTotal);
  Assert.AreEqual(2, LastDone);
end;

procedure TSbomResolveTests.NilSbomIsIgnored;
begin
  ResolveSbom(nil, FOptions);
  Assert.Pass;
end;

procedure TSbomResolveTests.SortingFollowsTheRefinedOrigin;
begin
  Add('Zeta.Lib', soThirdParty);
  Add('Vcl.Forms', soThirdParty);                 // acaba por ser VCL
  Add('System.SysUtils', soThirdParty);           // acaba por ser RTL
  ResolveSbom(FSbom, FOptions);
  Assert.AreEqual('System.SysUtils', FSbom.Components[0].Name);
  Assert.AreEqual('Vcl.Forms', FSbom.Components[1].Name);
  Assert.AreEqual('Zeta.Lib', FSbom.Components[2].Name);
end;

procedure TSbomResolveTests.FileHashOfAMissingFileIsEmpty;
begin
  Assert.AreEqual('', FileSha256(FDir.Full('nao/existe.pas')));
  Assert.AreEqual('', FileSha256(''));
end;

procedure TSbomResolveTests.FolderContainmentIgnoresCaseAndSiblings;
begin
  Assert.IsTrue(IsUnderFolder('C:\Proj\src\a.pas', 'c:\proj'));
  Assert.IsTrue(IsUnderFolder('C:\Proj\src', 'C:\Proj\'));
  Assert.IsTrue(IsUnderFolder('C:\Proj', 'C:\Proj'));
  Assert.IsFalse(IsUnderFolder('C:\Project\a.pas', 'C:\Proj'), 'uma pasta irma com o mesmo prefixo');
  Assert.IsFalse(IsUnderFolder('C:\Other\a.pas', 'C:\Proj'));
  Assert.IsFalse(IsUnderFolder('', 'C:\Proj'));
  Assert.IsFalse(IsUnderFolder('C:\Proj\a.pas', ''));
end;

procedure TSbomResolveTests.DelphiRootIsEmptyOrAnExistingFolder;
var
  Root: string;
begin
  Root := DetectDelphiRoot;
  Assert.IsTrue((Root = '') or TDirectory.Exists(Root), 'a raiz do Delphi: ' + Root);
end;

procedure TSbomResolveTests.LibraryPathsNeedARoot;
begin
  Assert.AreEqual<NativeInt>(0, Length(DelphiLibraryPaths('', 'Win64')));
end;

end.
