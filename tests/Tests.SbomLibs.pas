unit Tests.SbomLibs;

// Testes da biblioteca, da versao e da licenca de cada unit de terceiros (CM.SbomLibs), com pastas falsas:
// um projecto e, fora dele, bibliotecas com e sem boss.json e ficheiro de licenca, e uma pasta do GetIt.

interface

uses
  System.SysUtils, System.IOUtils, DUnitX.TestFramework, CM.Sbom, CM.Licenses, CM.SbomLibs, Tests.Helpers;

type
  [TestFixture]
  TSbomLibsTests = class
  private
    FDir: TTempDir;
    FFinder: TLibraryFinder;
    function Lib(const ARelUnit: string): TSbomLibrary;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure LicenseFileGivesTheLicenseAndTheFolderTheName;
    [Test] procedure BossJsonGivesNameVersionAndLicense;
    [Test] procedure BossLicenseNotRecognisedFallsBackToTheFile;
    [Test] procedure UnrecognisedLicenseFileIsNotGuessed;
    [Test] procedure LibraryWithoutAnyLicenseHasNone;
    [Test] procedure GetItFolderGivesNameAndVersion;
    [Test] procedure GetItPackageFolderWithAVersionSubfolder;
    [Test] procedure PlainVersionFolderOutsideGetItTakesTheNameFromTheParent;
    [Test] procedure BossModuleVersionComesFromTheLockFile;
    [Test] procedure NeverLooksAboveTheProjectFolder;
    [Test] procedure UnitsOfTheSameLibraryShareTheResult;
    [Test] procedure NoMarkerMeansNoLibrary;
    [Test] procedure GitFolderMarksALibraryRoot;
    [Test] procedure AttachFillsOnlyThirdPartyUnitsWithAFile;
    [Test] procedure AttachIgnoresNilAndUnresolved;
    [Test] procedure UnlicensedCountOnlyCountsThirdParty;
  end;

implementation

const
  Mit = 'Permission is hereby granted, free of charge, to any person obtaining a copy of this software. THE SOFTWARE IS PROVIDED "AS IS"';

function TSbomLibsTests.Lib(const ARelUnit: string): TSbomLibrary;
begin
  Result := FFinder.Find(FDir.Full(ARelUnit));
end;

procedure TSbomLibsTests.Setup;
begin
  FDir := TTempDir.Create;
  FDir.Write('proj/Demo.dproj', '<Project/>');
  FDir.Write('proj/LICENSE', Mit);                                  // o do proprio projecto: nunca conta
  FDir.Write('proj/vendor/Inner/inner.pas', 'unit inner;');
  FFinder := TLibraryFinder.Create(FDir.Full('proj'));
end;

procedure TSbomLibsTests.TearDown;
begin
  FFinder.Free;
  FDir.Free;
end;

procedure TSbomLibsTests.LicenseFileGivesTheLicenseAndTheFolderTheName;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Foo/LICENSE', Mit);
  FDir.Write('libs/Foo/src/foo.pas', 'unit foo;');
  L := Lib('libs/Foo/src/foo.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('Foo', L.Name);
  Assert.AreEqual('MIT', L.License);
  Assert.AreEqual('LICENSE', L.LicenseSource);
  Assert.AreEqual('', L.Version);
  Assert.AreEqual('', L.LicenseName);
end;

procedure TSbomLibsTests.BossJsonGivesNameVersionAndLicense;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/horse/boss.json', '{"name":"Horse","version":"3.1.0","license":"MIT","homepage":"https://x.test/horse"}');
  FDir.Write('libs/horse/src/horse.pas', 'unit horse;');
  L := Lib('libs/horse/src/horse.pas');
  Assert.AreEqual('Horse', L.Name);
  Assert.AreEqual('3.1.0', L.Version);
  Assert.AreEqual('boss.json', L.VersionSource);
  Assert.AreEqual('MIT', L.License);
  Assert.AreEqual('boss.json', L.LicenseSource);
  Assert.AreEqual('https://x.test/horse', L.HomePage);
end;

procedure TSbomLibsTests.BossLicenseNotRecognisedFallsBackToTheFile;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Bar/boss.json', '{"name":"Bar","license":"see file"}');
  FDir.Write('libs/Bar/LICENSE.txt', 'Apache License Version 2.0, January 2004');
  FDir.Write('libs/Bar/bar.pas', 'unit bar;');
  L := Lib('libs/Bar/bar.pas');
  Assert.AreEqual('Apache-2.0', L.License);
  Assert.AreEqual('LICENSE.txt', L.LicenseSource);
end;

procedure TSbomLibsTests.UnrecognisedLicenseFileIsNotGuessed;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Baz/LICENSE', 'Free for personal use. Ask the author for commercial use.');
  FDir.Write('libs/Baz/baz.pas', 'unit baz;');
  L := Lib('libs/Baz/baz.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('', L.License);
  Assert.AreEqual('See LICENSE', L.LicenseName);
  Assert.AreEqual('LICENSE', L.LicenseSource);
end;

procedure TSbomLibsTests.LibraryWithoutAnyLicenseHasNone;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Qux/boss.json', '{"name":"Qux","version":"1.0.0"}');
  FDir.Write('libs/Qux/qux.pas', 'unit qux;');
  L := Lib('libs/Qux/qux.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('', L.License);
  Assert.AreEqual('', L.LicenseName);
  Assert.AreEqual('', L.LicenseSource);
  Assert.AreEqual('1.0.0', L.Version);
end;

procedure TSbomLibsTests.GetItFolderGivesNameAndVersion;
var
  L: TSbomLibrary;
begin
  FDir.Write('Studio/CatalogRepository/Spring4D-2.0/Source/Spring.pas', 'unit Spring;');
  L := Lib('Studio/CatalogRepository/Spring4D-2.0/Source/Spring.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('Spring4D', L.Name);
  Assert.AreEqual('2.0', L.Version);
  Assert.AreEqual('GetIt', L.VersionSource);
end;

procedure TSbomLibsTests.GetItPackageFolderWithAVersionSubfolder;
var
  L: TSbomLibrary;
begin
  // o desenho real do GetIt: CatalogRepository\Pacote-DelphiNersao\Source
  FDir.Write('Studio/CatalogRepository/Chart4D-13/1.2.0/LICENSE', Mit);
  FDir.Write('Studio/CatalogRepository/Chart4D-13/1.2.0/Source/FMX/c.pas', 'unit c;');
  L := Lib('Studio/CatalogRepository/Chart4D-13/1.2.0/Source/FMX/c.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('Chart4D', L.Name);
  Assert.AreEqual('1.2.0', L.Version);
  Assert.AreEqual('GetIt', L.VersionSource);
  Assert.AreEqual('MIT', L.License);
end;

procedure TSbomLibsTests.PlainVersionFolderOutsideGetItTakesTheNameFromTheParent;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Widgets/v2.3/LICENSE', Mit);
  FDir.Write('libs/Widgets/v2.3/w.pas', 'unit w;');
  L := Lib('libs/Widgets/v2.3/w.pas');
  Assert.AreEqual('Widgets', L.Name);
  Assert.AreEqual('2.3', L.Version);
  Assert.AreEqual('Widgets', L.VersionSource);
end;

procedure TSbomLibsTests.BossModuleVersionComesFromTheLockFile;
var
  L: TSbomLibrary;
begin
  FDir.Write('proj/boss-lock.json', '{"installedModules":{"github.com/hashload/horse":{"version":"3.1.0"}}}');
  FDir.Write('proj/modules/horse/src/horse.pas', 'unit horse;');
  L := Lib('proj/modules/horse/src/horse.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('horse', L.Name);
  Assert.AreEqual('3.1.0', L.Version);
  Assert.AreEqual('boss-lock.json', L.VersionSource);
end;

procedure TSbomLibsTests.NeverLooksAboveTheProjectFolder;
begin
  // proj/LICENSE existe, mas pertence ao projecto: a pasta vendor/Inner nao tem marcador proprio
  Assert.IsFalse(Lib('proj/vendor/Inner/inner.pas').Found);
end;

procedure TSbomLibsTests.UnitsOfTheSameLibraryShareTheResult;
var
  A, B: TSbomLibrary;
begin
  FDir.Write('libs/Foo/LICENSE', Mit);
  FDir.Write('libs/Foo/src/a.pas', 'unit a;');
  FDir.Write('libs/Foo/src/deep/b.pas', 'unit b;');
  A := Lib('libs/Foo/src/a.pas');
  B := Lib('libs/Foo/src/deep/b.pas');
  Assert.AreEqual(A.Root, B.Root);
  Assert.AreEqual('MIT', B.License);
  Assert.AreEqual(A.Name, B.Name);
end;

procedure TSbomLibsTests.NoMarkerMeansNoLibrary;
begin
  FDir.Write('loose/x.pas', 'unit x;');
  Assert.IsFalse(Lib('loose/x.pas').Found);
end;

procedure TSbomLibsTests.GitFolderMarksALibraryRoot;
var
  L: TSbomLibrary;
begin
  FDir.Write('libs/Git/.git/HEAD', 'ref: refs/heads/main');
  FDir.Write('libs/Git/src/g.pas', 'unit g;');
  L := Lib('libs/Git/src/g.pas');
  Assert.IsTrue(L.Found);
  Assert.AreEqual('Git', L.Name);
  Assert.AreEqual('', L.License);
end;

procedure TSbomLibsTests.AttachFillsOnlyThirdPartyUnitsWithAFile;
var
  Sbom: TSbom;
  Created: Boolean;
  C, E, N: TSbomComponent;
begin
  FDir.Write('libs/Foo/LICENSE', Mit);
  FDir.Write('libs/Foo/foo.pas', 'unit foo;');
  Sbom := TSbom.Create;
  try
    C := Sbom.Obtain('foo', Created);
    C.Origin := soThirdParty;
    C.Path := FDir.Full('libs/Foo/foo.pas');
    E := Sbom.Obtain('System.SysUtils', Created);
    E.Origin := soRtl;
    E.Path := FDir.Full('libs/Foo/foo.pas');           // nem que o caminho coincida: a Embarcadero nao se toca
    N := Sbom.Obtain('nofile', Created);
    N.Origin := soThirdParty;
    AttachLibraries(Sbom, FDir.Full('proj'));
    Assert.AreEqual('Foo', C.LibraryName);
    Assert.AreEqual('MIT', C.License);
    Assert.AreEqual('', E.License);
    Assert.AreEqual('', E.LibraryName);
    Assert.AreEqual('', N.License);
  finally
    Sbom.Free;
  end;
end;

procedure TSbomLibsTests.AttachIgnoresNilAndUnresolved;
begin
  AttachLibraries(nil, FDir.Full('proj'));          // nao rebenta
  Assert.Pass;
end;

procedure TSbomLibsTests.UnlicensedCountOnlyCountsThirdParty;
var
  Sbom: TSbom;
  Created: Boolean;
begin
  Sbom := TSbom.Create;
  try
    Sbom.Obtain('a', Created).Origin := soThirdParty;
    Sbom.Obtain('b', Created).Origin := soThirdParty;
    Sbom.Obtain('b', Created).License := 'MIT';
    Sbom.Obtain('System.Classes', Created).Origin := soRtl;
    Assert.AreEqual(1, Sbom.ThirdPartyLicensedCount);
    Assert.AreEqual(1, Sbom.ThirdPartyUnlicensedCount);
  finally
    Sbom.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSbomLibsTests);

end.
