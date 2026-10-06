unit Tests.SbomFormats;

// Testes dos escritores de SBOM (CM.SbomFormats): CycloneDX 1.5 e SPDX 2.3 em JSON, e dos validadores.

interface

uses
  System.SysUtils, System.IOUtils, System.JSON, System.RegularExpressions, DUnitX.TestFramework, CM.Sbom,
  CM.SbomFormats, Tests.Helpers;

type
  [TestFixture]
  TSbomFormatsTests = class
  private
    FSbom: TSbom;
    FOptions: TSbomWriteOptions;
    function Cdx: TJSONObject;
    function Spdx: TJSONObject;
    function CdxComponentNamed(ARoot: TJSONObject; const AName: string): TJSONObject;
    function PropValue(AComponent: TJSONObject; const AName: string): string;
    procedure Add(const AName: string; AOrigin: TSbomOrigin; AConfidence: TSbomConfidence; const AHash, APath: string;
      const AUsedBy: array of string; const ARel: string = '');
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CycloneDxHasTheRequiredTopLevelFields;
    [Test] procedure CycloneDxDescribesTheProject;
    [Test] procedure CycloneDxComponentsCarryHashesSuppliersAndProperties;
    [Test] procedure CycloneDxNeverWritesFullPaths;
    [Test] procedure CycloneDxDependenciesFollowWhoUsesWhom;
    [Test] procedure CycloneDxIsValid;
    [Test] procedure CycloneDxSerialNumberCanBeGiven;
    [Test] procedure CycloneDxPackageProjectIsALibrary;
    [Test] procedure SpdxHasTheRequiredTopLevelFields;
    [Test] procedure SpdxPackagesCarryChecksumsAndSuppliers;
    [Test] procedure SpdxRelationshipsDescribeTheProjectAndItsDependencies;
    [Test] procedure SpdxIdsAreSafeAndUnique;
    [Test] procedure SpdxIsValid;
    [Test] procedure SpdxDateHasNoFractionOfASecond;
    [Test] procedure ValidatorRejectsGarbage;
    [Test] procedure CycloneDxValidatorFindsEachProblem;
    [Test] procedure SpdxValidatorFindsEachProblem;
    [Test] procedure SavesWithoutBomAndCreatesTheFolder;
    [Test] procedure EmptySbomStillProducesValidFiles;
    [Test] procedure ProjectWithoutNameGetsADefault;
  end;

implementation

procedure TSbomFormatsTests.Add(const AName: string; AOrigin: TSbomOrigin; AConfidence: TSbomConfidence;
  const AHash, APath: string; const AUsedBy: array of string; const ARel: string);
var
  C: TSbomComponent;
  Created: Boolean;
  I: Integer;
begin
  C := FSbom.Obtain(AName, Created);
  C.Origin := AOrigin;
  C.Confidence := AConfidence;
  C.Hash := AHash;
  C.Path := APath;
  C.RelPath := ARel;
  if APath <> '' then
    C.Evidence := seFile
  else
    C.Evidence := seUses;
  SetLength(C.UsedBy, Length(AUsedBy));
  for I := 0 to High(AUsedBy) do
    C.UsedBy[I] := AUsedBy[I];
end;

procedure TSbomFormatsTests.Setup;
begin
  FSbom := TSbom.Create;
  FSbom.Generated := EncodeDate(2026, 10, 6) + EncodeTime(12, 30, 15, 250);
  FSbom.Project.Name := 'Demo';
  FSbom.Project.Version := '1.2.3.4';
  FSbom.Project.Description := 'Aplicacao de demonstracao';
  FSbom.Project.Company := 'Acme';
  FSbom.Project.FrameworkType := 'VCL';
  FSbom.Project.Platform := 'Win64';
  FSbom.Project.Configuration := 'Release';
  // dois componentes de fora, um de terceiros por resolver e duas units do projecto
  Add('Main', soProject, scStrong, StringOfChar('a', 64), 'C:\Secret\Proj\src\Main.pas', [], 'src/Main.pas');
  Add('Core.A', soProject, scStrong, StringOfChar('b', 64), 'C:\Secret\Proj\src\Core.A.pas', ['Main'], 'src/Core.A.pas');
  Add('System.SysUtils', soRtl, scStrong, StringOfChar('c', 64), 'C:\Delphi\source\rtl\System.SysUtils.pas', ['Core.A', 'Main']);
  Add('Vcl.Forms', soVcl, scMedium, '', '', ['Main']);
  Add('Chart4D.FMX', soThirdParty, scWeak, '', '', ['Core.A']);
  FSbom.SortComponents;
  FOptions := SbomDefaultOptions('1.0.3');
  FOptions.SerialNumber := '3e671687-395b-41f5-a30f-a58921a69b79';
  FOptions.DocumentId := '0d3d7a4e-1b5c-4c3e-8a0b-2f4f6a5e9c11';
end;

procedure TSbomFormatsTests.TearDown;
begin
  FSbom.Free;
end;

function TSbomFormatsTests.Cdx: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(SbomCycloneDxJson(FSbom, FOptions)) as TJSONObject;
  Assert.IsNotNull(Result, 'o CycloneDX nao e JSON');
end;

function TSbomFormatsTests.Spdx: TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(SbomSpdxJson(FSbom, FOptions)) as TJSONObject;
  Assert.IsNotNull(Result, 'o SPDX nao e JSON');
end;

function TSbomFormatsTests.CdxComponentNamed(ARoot: TJSONObject; const AName: string): TJSONObject;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Arr := ARoot.GetValue('components') as TJSONArray;
  for I := 0 to Arr.Count - 1 do
    if (Arr.Items[I] as TJSONObject).GetValue<string>('name') = AName then
      Exit(Arr.Items[I] as TJSONObject);
  Result := nil;
  Assert.Fail('componente nao encontrado: ' + AName);
end;

function TSbomFormatsTests.PropValue(AComponent: TJSONObject; const AName: string): string;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := '';
  Arr := AComponent.GetValue('properties') as TJSONArray;
  if Arr = nil then
    Exit;
  for I := 0 to Arr.Count - 1 do
    if (Arr.Items[I] as TJSONObject).GetValue<string>('name') = AName then
      Exit((Arr.Items[I] as TJSONObject).GetValue<string>('value'));
end;

procedure TSbomFormatsTests.CycloneDxHasTheRequiredTopLevelFields;
var
  R: TJSONObject;
begin
  R := Cdx;
  try
    Assert.AreEqual('CycloneDX', R.GetValue<string>('bomFormat'));
    Assert.AreEqual('1.5', R.GetValue<string>('specVersion'));
    Assert.AreEqual('urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79', R.GetValue<string>('serialNumber'));
    Assert.AreEqual(1, R.GetValue<Integer>('version'));
    Assert.IsTrue(R.GetValue('metadata') is TJSONObject);
    Assert.IsTrue(R.GetValue('components') is TJSONArray);
    Assert.IsTrue(R.GetValue('dependencies') is TJSONArray);
    Assert.AreEqual('2026-10-06', Copy(R.GetValue<string>('metadata.timestamp'), 1, 10));
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.CycloneDxDescribesTheProject;
var
  R, M, Tool: TJSONObject;
begin
  R := Cdx;
  try
    M := (R.GetValue('metadata') as TJSONObject).GetValue('component') as TJSONObject;
    Assert.AreEqual('application', M.GetValue<string>('type'));
    Assert.AreEqual('Demo', M.GetValue<string>('name'));
    Assert.AreEqual('1.2.3.4', M.GetValue<string>('version'));
    Assert.AreEqual('app:Demo', M.GetValue<string>('bom-ref'));
    Assert.AreEqual('Acme', M.GetValue<string>('supplier.name'));
    Assert.AreEqual('Aplicacao de demonstracao', M.GetValue<string>('description'));
    Tool := ((((R.GetValue('metadata') as TJSONObject).GetValue('tools') as TJSONObject).GetValue('components')
      as TJSONArray).Items[0]) as TJSONObject;
    Assert.AreEqual('CodeManager', Tool.GetValue<string>('name'));
    Assert.AreEqual('1.0.3', Tool.GetValue<string>('version'));
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.CycloneDxComponentsCarryHashesSuppliersAndProperties;
var
  R, C: TJSONObject;
begin
  R := Cdx;
  try
    Assert.AreEqual(5, (R.GetValue('components') as TJSONArray).Count);
    C := CdxComponentNamed(R, 'System.SysUtils');
    Assert.AreEqual('library', C.GetValue<string>('type'));
    Assert.AreEqual('unit:System.SysUtils', C.GetValue<string>('bom-ref'));
    Assert.AreEqual('Embarcadero Technologies, Inc.', C.GetValue<string>('supplier.name'));
    Assert.AreEqual('SHA-256', ((C.GetValue('hashes') as TJSONArray).Items[0] as TJSONObject).GetValue<string>('alg'));
    Assert.AreEqual(StringOfChar('c', 64), ((C.GetValue('hashes') as TJSONArray).Items[0] as TJSONObject).GetValue<string>('content'));
    Assert.AreEqual('Embarcadero RTL', PropValue(C, 'codemanager:origin'));
    Assert.AreEqual('File', PropValue(C, 'codemanager:evidence'));
    Assert.AreEqual('Strong', PropValue(C, 'codemanager:confidence'));
    Assert.AreEqual('System.SysUtils.pas', PropValue(C, 'codemanager:file'));
    C := CdxComponentNamed(R, 'Chart4D.FMX');
    Assert.IsNull(C.GetValue('hashes'), 'sem ficheiro nao ha hash');
    Assert.IsNull(C.GetValue('supplier'), 'de terceiros nao se sabe o fornecedor');
    Assert.AreEqual('Third party', PropValue(C, 'codemanager:origin'));
    Assert.AreEqual('Uses', PropValue(C, 'codemanager:evidence'));
    Assert.AreEqual('Weak', PropValue(C, 'codemanager:confidence'));
    Assert.AreEqual('', PropValue(C, 'codemanager:file'));
    C := CdxComponentNamed(R, 'Core.A');
    Assert.AreEqual('src/Core.A.pas', PropValue(C, 'codemanager:path'));
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.CycloneDxNeverWritesFullPaths;
var
  Text: string;
begin
  Text := SbomCycloneDxJson(FSbom, FOptions);
  Assert.IsFalse(Text.Contains('Secret'), 'a pasta do utilizador nao vai para o SBOM');
  Assert.IsFalse(Text.Contains('C:\\Delphi'));
  Text := SbomSpdxJson(FSbom, FOptions);
  Assert.IsFalse(Text.Contains('Secret'));
  Assert.IsFalse(Text.Contains('C:\\Delphi'));
end;

function RefsOf(AEntry: TJSONObject): string;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := '|';
  Arr := AEntry.GetValue('dependsOn') as TJSONArray;
  for I := 0 to Arr.Count - 1 do
    Result := Result + Arr.Items[I].Value + '|';
end;

procedure TSbomFormatsTests.CycloneDxDependenciesFollowWhoUsesWhom;
var
  R: TJSONObject;
  Deps: TJSONArray;
  I: Integer;
  AppRefs, MainRefs, CoreRefs: string;
  E: TJSONObject;
begin
  R := Cdx;
  try
    Deps := R.GetValue('dependencies') as TJSONArray;
    AppRefs := '';
    MainRefs := '';
    CoreRefs := '';
    for I := 0 to Deps.Count - 1 do
    begin
      E := Deps.Items[I] as TJSONObject;
      if E.GetValue<string>('ref') = 'app:Demo' then AppRefs := RefsOf(E);
      if E.GetValue<string>('ref') = 'unit:Main' then MainRefs := RefsOf(E);
      if E.GetValue<string>('ref') = 'unit:Core.A' then CoreRefs := RefsOf(E);
    end;
    // a aplicacao: as de fora e as units do projecto que ninguem usa (o programa)
    Assert.IsTrue(AppRefs.Contains('|unit:Main|'));
    Assert.IsTrue(AppRefs.Contains('|unit:System.SysUtils|'));
    Assert.IsTrue(AppRefs.Contains('|unit:Vcl.Forms|'));
    Assert.IsFalse(AppRefs.Contains('|unit:Core.A|'), 'Core.A e usada por Main');
    // Main usa Core.A; Core.A usa SysUtils e Chart4D (por UsedBy invertido)
    Assert.IsTrue(MainRefs.Contains('|unit:Core.A|'));
    Assert.IsTrue(MainRefs.Contains('|unit:System.SysUtils|'));
    Assert.IsTrue(MainRefs.Contains('|unit:Vcl.Forms|'));
    Assert.IsTrue(CoreRefs.Contains('|unit:System.SysUtils|'));
    Assert.IsTrue(CoreRefs.Contains('|unit:Chart4D.FMX|'));
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.CycloneDxIsValid;
var
  Problem: string;
begin
  Assert.IsTrue(ValidateCycloneDx(SbomCycloneDxJson(FSbom, FOptions), Problem), Problem);
  Assert.AreEqual('', Problem);
end;

procedure TSbomFormatsTests.CycloneDxSerialNumberCanBeGiven;
var
  Text: string;
begin
  Text := SbomCycloneDxJson(FSbom, FOptions);
  Assert.IsTrue(Text.Contains('urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79'));
  FOptions.SerialNumber := '';
  Assert.IsTrue(TRegEx.IsMatch(SbomCycloneDxJson(FSbom, FOptions),
    'urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'), 'sem numero dado gera um novo');
end;

procedure TSbomFormatsTests.CycloneDxPackageProjectIsALibrary;
var
  R: TJSONObject;
begin
  FSbom.Project.IsPackage := True;
  R := Cdx;
  try
    Assert.AreEqual('library', R.GetValue<string>('metadata.component.type'));
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.SpdxHasTheRequiredTopLevelFields;
var
  R: TJSONObject;
begin
  R := Spdx;
  try
    Assert.AreEqual('SPDX-2.3', R.GetValue<string>('spdxVersion'));
    Assert.AreEqual('CC0-1.0', R.GetValue<string>('dataLicense'));
    Assert.AreEqual('SPDXRef-DOCUMENT', R.GetValue<string>('SPDXID'));
    Assert.AreEqual('Demo', R.GetValue<string>('name'));
    Assert.AreEqual('https://spdx.org/spdxdocs/Demo-0d3d7a4e-1b5c-4c3e-8a0b-2f4f6a5e9c11',
      R.GetValue<string>('documentNamespace'));
    Assert.AreEqual('Tool: CodeManager-1.0.3',
      (((R.GetValue('creationInfo') as TJSONObject).GetValue('creators') as TJSONArray).Items[0]).Value);
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.SpdxPackagesCarryChecksumsAndSuppliers;
var
  R, P: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Found: Boolean;
begin
  R := Spdx;
  try
    Arr := R.GetValue('packages') as TJSONArray;
    Assert.AreEqual(6, Arr.Count, 'o projecto e mais cinco componentes');
    Found := False;
    for I := 0 to Arr.Count - 1 do
    begin
      P := Arr.Items[I] as TJSONObject;
      if P.GetValue<string>('name') = 'System.SysUtils' then
      begin
        Found := True;
        Assert.AreEqual('Organization: Embarcadero Technologies, Inc.', P.GetValue<string>('supplier'));
        Assert.AreEqual('SHA256', ((P.GetValue('checksums') as TJSONArray).Items[0] as TJSONObject).GetValue<string>('algorithm'));
        Assert.AreEqual('NOASSERTION', P.GetValue<string>('licenseConcluded'));
        Assert.AreEqual('NOASSERTION', P.GetValue<string>('downloadLocation'));
      end;
      if P.GetValue<string>('name') = 'Chart4D.FMX' then
      begin
        Assert.AreEqual('NOASSERTION', P.GetValue<string>('supplier'));
        Assert.IsNull(P.GetValue('checksums'));
      end;
      if P.GetValue<string>('name') = 'Demo' then
      begin
        Assert.AreEqual('1.2.3.4', P.GetValue<string>('versionInfo'));
        Assert.AreEqual('Organization: Acme', P.GetValue<string>('supplier'));
      end;
    end;
    Assert.IsTrue(Found);
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.SpdxRelationshipsDescribeTheProjectAndItsDependencies;
var
  R, E: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Describes, Depends: Integer;
begin
  R := Spdx;
  try
    Arr := R.GetValue('relationships') as TJSONArray;
    Describes := 0;
    Depends := 0;
    for I := 0 to Arr.Count - 1 do
    begin
      E := Arr.Items[I] as TJSONObject;
      if E.GetValue<string>('relationshipType') = 'DESCRIBES' then
      begin
        Inc(Describes);
        Assert.AreEqual('SPDXRef-DOCUMENT', E.GetValue<string>('spdxElementId'));
        Assert.AreEqual('SPDXRef-Package-App-Demo', E.GetValue<string>('relatedSpdxElement'));
      end
      else if E.GetValue<string>('relationshipType') = 'DEPENDS_ON' then
        Inc(Depends);
    end;
    Assert.AreEqual(1, Describes);
    // a aplicacao: Main, SysUtils, Forms e Chart4D (5 componentes menos Core.A, que e usada por Main) = 4;
    // Main -> Core.A, SysUtils, Forms = 3; Core.A -> SysUtils, Chart4D = 2
    Assert.AreEqual(9, Depends);
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.SpdxIdsAreSafeAndUnique;
var
  Problem: string;
begin
  // 'A.B' e 'A_B' dao o mesmo identificador seguro: o segundo leva um sufixo
  Add('A.B', soThirdParty, scWeak, '', '', []);
  Add('A_B', soThirdParty, scWeak, '', '', []);
  Add('Nome com espaço', soThirdParty, scWeak, '', '', []);
  Assert.IsTrue(ValidateSpdx(SbomSpdxJson(FSbom, FOptions), Problem), Problem);
end;

procedure TSbomFormatsTests.SpdxIsValid;
var
  Problem: string;
begin
  Assert.IsTrue(ValidateSpdx(SbomSpdxJson(FSbom, FOptions), Problem), Problem);
end;

procedure TSbomFormatsTests.SpdxDateHasNoFractionOfASecond;
var
  R: TJSONObject;
  Created: string;
begin
  R := Spdx;
  try
    Created := (R.GetValue('creationInfo') as TJSONObject).GetValue<string>('created');
    Assert.IsTrue(TRegEx.IsMatch(Created, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'), Created);
  finally
    R.Free;
  end;
end;

procedure TSbomFormatsTests.ValidatorRejectsGarbage;
var
  Problem: string;
begin
  Assert.IsFalse(ValidateCycloneDx('', Problem));
  Assert.IsFalse(ValidateCycloneDx('isto nao e json', Problem));
  Assert.AreEqual('não é JSON válido', Problem);
  Assert.IsFalse(ValidateCycloneDx('[1,2,3]', Problem));
  Assert.IsFalse(ValidateSpdx('{}', Problem));
  Assert.IsFalse(ValidateSpdx('', Problem));
end;

procedure TSbomFormatsTests.CycloneDxValidatorFindsEachProblem;
var
  Good, Problem: string;
begin
  Good := SbomCycloneDxJson(FSbom, FOptions);
  Assert.IsFalse(ValidateCycloneDx(Good.Replace('"bomFormat": "CycloneDX"', '"bomFormat": "Outro"'), Problem));
  Assert.Contains(Problem, 'bomFormat');
  Assert.IsFalse(ValidateCycloneDx(Good.Replace('urn:uuid:3e671687', 'urn:uuid:XX'), Problem));
  Assert.Contains(Problem, 'serialNumber');
  Assert.IsFalse(ValidateCycloneDx(Good.Replace('"bom-ref": "unit:Core.A"', '"bom-ref": "unit:Main"'), Problem));
  Assert.Contains(Problem, 'bom-ref repetido');
  Assert.IsFalse(ValidateCycloneDx(Good.Replace('"ref": "unit:Core.A"', '"ref": "unit:Fantasma"'), Problem));
  Assert.Contains(Problem, 'não existe');
  Assert.IsFalse(ValidateCycloneDx(Good.Replace(StringOfChar('c', 64), 'curto'), Problem));
  Assert.Contains(Problem, 'hash SHA-256');
  Assert.IsFalse(ValidateCycloneDx(Good.Replace('"specVersion": "1.5"', '"x": "1.5"'), Problem));
  Assert.Contains(Problem, 'specVersion');
end;

procedure TSbomFormatsTests.SpdxValidatorFindsEachProblem;
var
  Good, Problem: string;
begin
  Good := SbomSpdxJson(FSbom, FOptions);
  Assert.IsFalse(ValidateSpdx(Good.Replace('"dataLicense": "CC0-1.0"', '"dataLicense": "MIT"'), Problem));
  Assert.Contains(Problem, 'dataLicense');
  Assert.IsFalse(ValidateSpdx(Good.Replace('SPDXRef-Unit-Core.A"', 'SPDXRef-Unit-Main"'), Problem));
  Assert.Contains(Problem, 'repetido');
  Assert.IsFalse(ValidateSpdx(Good.Replace('"relatedSpdxElement": "SPDXRef-Unit-Vcl.Forms"', '"relatedSpdxElement": "SPDXRef-Nada"'), Problem));
  Assert.Contains(Problem, 'não existe');
  Assert.IsFalse(ValidateSpdx(Good.Replace(StringOfChar('c', 64), 'curto'), Problem));
  Assert.Contains(Problem, 'checksum');
  Assert.IsFalse(ValidateSpdx(Good.Replace('"documentNamespace"', '"x"'), Problem));
  Assert.Contains(Problem, 'documentNamespace');
end;

procedure TSbomFormatsTests.SavesWithoutBomAndCreatesTheFolder;
var
  Dir: TTempDir;
  Bytes: TBytes;
  Path: string;
begin
  Dir := TTempDir.Create;
  try
    Path := Dir.Full('novo/sub/demo.cdx.json');
    SaveSbomFile(Path, SbomCycloneDxJson(FSbom, FOptions));
    Assert.IsTrue(TFile.Exists(Path));
    Bytes := TFile.ReadAllBytes(Path);
    Assert.AreEqual<Integer>(Ord('{'), Bytes[0], 'sem BOM: comeca logo por {');
  finally
    Dir.Free;
  end;
end;

procedure TSbomFormatsTests.EmptySbomStillProducesValidFiles;
var
  S: TSbom;
  Problem: string;
begin
  S := TSbom.Create;
  try
    S.Project.Name := 'Vazio';
    Assert.IsTrue(ValidateCycloneDx(SbomCycloneDxJson(S, FOptions), Problem), Problem);
    Assert.IsTrue(ValidateSpdx(SbomSpdxJson(S, FOptions), Problem), Problem);
  finally
    S.Free;
  end;
end;

procedure TSbomFormatsTests.ProjectWithoutNameGetsADefault;
var
  S: TSbom;
  Problem: string;
begin
  S := TSbom.Create;
  try
    Assert.IsTrue(ValidateCycloneDx(SbomCycloneDxJson(S, FOptions), Problem), Problem);
    Assert.IsTrue(SbomCycloneDxJson(S, FOptions).Contains('"name": "Project"'));
  finally
    S.Free;
  end;
end;

end.
