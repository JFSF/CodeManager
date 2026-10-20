unit CM.SbomFormats;

{ Escreve um SBOM (CM.Sbom) nos dois formatos padrao em JSON: CycloneDX 1.5 e SPDX 2.3. Cada componente e uma unit com o
  seu SHA-256 (quando se achou o ficheiro), a origem, a evidencia e a confianca. Os validadores conferem o essencial
  (campos obrigatorios, referencias que existem, identificadores unicos e hashes bem formados) e dizem o que falha.

  Os caminhos completos nunca vao para o SBOM (nao se quer mostrar a estrutura de pastas de quem o gera): so o nome do
  ficheiro e, nas units do projecto, o caminho relativo.

  Adaptado dos escritores do DX.Comply (MIT, Olaf Monien): https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils, CM.Sbom;

type
  TSbomWriteOptions = record
    ToolName: string;            // 'CodeManager'
    ToolVersion: string;         // a versao da aplicacao
    ToolAuthor: string;
    SerialNumber: string;        // CycloneDX: urn:uuid (sem o prefixo); '' = um novo
    DocumentId: string;          // SPDX: o GUID do espaco de nomes do documento; '' = um novo
  end;

function SbomDefaultOptions(const AToolVersion: string): TSbomWriteOptions;
function SbomCycloneDxJson(ASbom: TSbom; const AOptions: TSbomWriteOptions): string;
function SbomSpdxJson(ASbom: TSbom; const AOptions: TSbomWriteOptions): string;
// True se AJson e um CycloneDX bem formado; senao AProblem diz o que falha
function ValidateCycloneDx(const AJson: string; out AProblem: string): Boolean;
function ValidateSpdx(const AJson: string; out AProblem: string): Boolean;
// grava o texto em UTF-8, sem BOM, criando a pasta se for preciso
procedure SaveSbomFile(const AFileName, AContent: string);

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.TimeSpan, System.Generics.Collections, System.RegularExpressions, System.StrUtils;

const
  CdxSpecVersion = '1.5';
  SpdxVersion = 'SPDX-2.3';
  EmbarcaderoSupplier = 'Embarcadero Technologies, Inc.';

function SbomDefaultOptions(const AToolVersion: string): TSbomWriteOptions;
begin
  Result := Default(TSbomWriteOptions);
  Result.ToolName := 'CodeManager';
  Result.ToolVersion := AToolVersion;
  Result.ToolAuthor := 'João Ferreira';
end;

function NewGuidText: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := LowerCase(GUIDToString(G));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

function IsoNow(ASbom: TSbom): string;
begin
  // em UTC, sem fraccoes de segundo e com o Z no fim (o SPDX exige exactamente este formato)
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', TTimeZone.Local.ToUniversalTime(ASbom.Generated));
end;

function SupplierOf(AOrigin: TSbomOrigin): string;
begin
  case AOrigin of
    soRtl, soVcl, soFmx: Result := EmbarcaderoSupplier;
  else
    Result := '';
  end;
end;

function ProjectNameOf(ASbom: TSbom): string;
begin
  Result := ASbom.Project.Name;
  if Result = '' then
    Result := 'Project';
end;

function UnitRef(const AName: string): string;
begin
  Result := 'unit:' + AName;
end;

{ CycloneDX }

function Prop(const AName, AValue: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('value', AValue);
end;

function ComponentProps(C: TSbomComponent): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(Prop('codemanager:origin', OriginName(C.Origin)));
  Result.Add(Prop('codemanager:evidence', EvidenceName(C.Evidence)));
  Result.Add(Prop('codemanager:confidence', ConfidenceName(C.Confidence)));
  if C.Path <> '' then
    Result.Add(Prop('codemanager:file', ExtractFileName(C.Path)));
  if C.RelPath <> '' then
    Result.Add(Prop('codemanager:path', C.RelPath));
  if C.Layer <> '' then
    Result.Add(Prop('codemanager:layer', C.Layer));
  if C.InMap then
    Result.Add(Prop('codemanager:linked', 'true'));
  if C.LibraryName <> '' then
    Result.Add(Prop('codemanager:library', C.LibraryName));
  if C.VersionSource <> '' then
    Result.Add(Prop('codemanager:version-source', C.VersionSource));
  if C.LicenseSource <> '' then
    Result.Add(Prop('codemanager:license-source', C.LicenseSource));
end;

// so se escreve uma ligacao web que seja mesmo http(s)
function IsWebUrl(const AUrl: string): Boolean;
begin
  Result := StartsText('https://', AUrl) or StartsText('http://', AUrl);
end;

// [{"license":{"id":"MIT"}}] com a licenca reconhecida, ou {"name":...} quando so se sabe que ha um ficheiro; nil sem licenca
function CdxLicenses(C: TSbomComponent): TJSONArray;
var
  Entry, Lic: TJSONObject;
begin
  Result := nil;
  if (C.License = '') and (C.LicenseName = '') then
    Exit;
  Lic := TJSONObject.Create;
  if C.License <> '' then
    Lic.AddPair('id', C.License)
  else
    Lic.AddPair('name', C.LicenseName);
  Entry := TJSONObject.Create;
  Entry.AddPair('license', Lic);
  Result := TJSONArray.Create;
  Result.Add(Entry);
end;

function CdxComponent(C: TSbomComponent): TJSONObject;
var
  Hashes, Lics, Refs: TJSONArray;
  H, Sup, Ref: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'library');
  Result.AddPair('bom-ref', UnitRef(C.Name));
  Result.AddPair('name', C.Name);
  if C.Version <> '' then
    Result.AddPair('version', C.Version);
  if SupplierOf(C.Origin) <> '' then
  begin
    Sup := TJSONObject.Create;
    Sup.AddPair('name', SupplierOf(C.Origin));
    Result.AddPair('supplier', Sup);
  end;
  Lics := CdxLicenses(C);
  if Lics <> nil then
    Result.AddPair('licenses', Lics);
  if IsWebUrl(C.HomePage) then
  begin
    Refs := TJSONArray.Create;
    Ref := TJSONObject.Create;
    Ref.AddPair('type', 'website');
    Ref.AddPair('url', C.HomePage);
    Refs.Add(Ref);
    Result.AddPair('externalReferences', Refs);
  end;
  if C.Hash <> '' then
  begin
    Hashes := TJSONArray.Create;
    H := TJSONObject.Create;
    H.AddPair('alg', 'SHA-256');
    H.AddPair('content', LowerCase(C.Hash));
    Hashes.Add(H);
    Result.AddPair('hashes', Hashes);
  end;
  Result.AddPair('properties', ComponentProps(C));
end;

function CdxMetadata(ASbom: TSbom; const AOptions: TSbomWriteOptions): TJSONObject;
var
  Tool, App, Sup, ToolList: TJSONObject;
  Arr, Props: TJSONArray;
  P: TSbomProject;
begin
  P := ASbom.Project;
  Result := TJSONObject.Create;
  Result.AddPair('timestamp', IsoNow(ASbom));
  Tool := TJSONObject.Create;
  Tool.AddPair('type', 'application');
  if AOptions.ToolAuthor <> '' then
    Tool.AddPair('author', AOptions.ToolAuthor);
  Tool.AddPair('name', AOptions.ToolName);
  Tool.AddPair('version', AOptions.ToolVersion);
  Arr := TJSONArray.Create;
  Arr.Add(Tool);
  ToolList := TJSONObject.Create;
  ToolList.AddPair('components', Arr);
  Result.AddPair('tools', ToolList);
  App := TJSONObject.Create;
  if P.IsPackage then
    App.AddPair('type', 'library')
  else
    App.AddPair('type', 'application');
  App.AddPair('bom-ref', 'app:' + ProjectNameOf(ASbom));
  App.AddPair('name', ProjectNameOf(ASbom));
  if P.Version <> '' then
    App.AddPair('version', P.Version);
  if P.Description <> '' then
    App.AddPair('description', P.Description);
  if P.Company <> '' then
  begin
    Sup := TJSONObject.Create;
    Sup.AddPair('name', P.Company);
    App.AddPair('supplier', Sup);
  end;
  Result.AddPair('component', App);
  Props := TJSONArray.Create;
  if P.FrameworkType <> '' then
    Props.Add(Prop('codemanager:framework', P.FrameworkType));
  if P.Platform <> '' then
    Props.Add(Prop('codemanager:platform', P.Platform));
  if P.Configuration <> '' then
    Props.Add(Prop('codemanager:configuration', P.Configuration));
  if P.DelphiVersion <> '' then
    Props.Add(Prop('codemanager:delphi-project-version', P.DelphiVersion));
  Props.Add(Prop('codemanager:components', IntToStr(ASbom.Components.Count)));
  Props.Add(Prop('codemanager:resolved', IntToStr(ASbom.ResolvedCount)));
  if ASbom.MapFile <> '' then
    Props.Add(Prop('codemanager:map-file', ExtractFileName(ASbom.MapFile)));
  Result.AddPair('properties', Props);
end;

function CdxDependencies(ASbom: TSbom): TJSONArray;
var
  Deps: TDictionary<string, TList<string>>;
  C: TSbomComponent;
  U, Key: string;
  Root: TJSONObject;
  RootDeps, List: TJSONArray;
  Entry: TJSONObject;
  Item: TPair<string, TList<string>>;
  Ref: string;
begin
  Result := TJSONArray.Create;
  Deps := TDictionary<string, TList<string>>.Create;
  try
    // quem usa quem: uma unit do projecto depende das units que usa
    for C in ASbom.Components do
      for U in C.UsedBy do
        if (ASbom.Find(U) <> nil) and (ASbom.Find(U).Origin = soProject) then
        begin
          Key := UnitRef(U);
          if not Deps.ContainsKey(Key) then
            Deps.Add(Key, TList<string>.Create);
          Deps[Key].Add(UnitRef(C.Name));
        end;
    // a aplicacao depende do que ninguem do projecto usa no SBOM (as de fora e os pontos de entrada)
    Root := TJSONObject.Create;
    Root.AddPair('ref', 'app:' + ProjectNameOf(ASbom));
    RootDeps := TJSONArray.Create;
    for C in ASbom.Components do
    begin
      Ref := UnitRef(C.Name);
      if (C.Origin <> soProject) or (Length(C.UsedBy) = 0) then
        RootDeps.Add(Ref);
    end;
    Root.AddPair('dependsOn', RootDeps);
    Result.Add(Root);
    for Item in Deps do
    begin
      Entry := TJSONObject.Create;
      Entry.AddPair('ref', Item.Key);
      List := TJSONArray.Create;
      for Ref in Item.Value do
        List.Add(Ref);
      Entry.AddPair('dependsOn', List);
      Result.Add(Entry);
    end;
  finally
    for Item in Deps do
      Item.Value.Free;
    Deps.Free;
  end;
end;

function SbomCycloneDxJson(ASbom: TSbom; const AOptions: TSbomWriteOptions): string;
var
  Root: TJSONObject;
  Comps: TJSONArray;
  C: TSbomComponent;
  Serial: string;
begin
  Serial := AOptions.SerialNumber;
  if Serial = '' then
    Serial := NewGuidText;
  Root := TJSONObject.Create;
  try
    Root.AddPair('$schema', 'http://cyclonedx.org/schema/bom-1.5.schema.json');
    Root.AddPair('bomFormat', 'CycloneDX');
    Root.AddPair('specVersion', CdxSpecVersion);
    Root.AddPair('serialNumber', 'urn:uuid:' + Serial);
    Root.AddPair('version', TJSONNumber.Create(1));
    Root.AddPair('metadata', CdxMetadata(ASbom, AOptions));
    Comps := TJSONArray.Create;
    for C in ASbom.Components do
      Comps.Add(CdxComponent(C));
    Root.AddPair('components', Comps);
    Root.AddPair('dependencies', CdxDependencies(ASbom));
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

{ SPDX }

function SpdxSafe(const AValue: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AValue do
    if CharInSet(C, ['a'..'z', 'A'..'Z', '0'..'9', '.', '-']) then
      Result := Result + C
    else
      Result := Result + '-';
end;

function SpdxPackage(const ASpdxId, AName, AVersion, ASupplier, AHash, ADescription: string; const ALicense: string = '';
  const AHomePage: string = ''): TJSONObject;
var
  Sums: TJSONArray;
  Sum: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('SPDXID', ASpdxId);
  Result.AddPair('name', AName);
  if AVersion <> '' then
    Result.AddPair('versionInfo', AVersion);
  Result.AddPair('downloadLocation', 'NOASSERTION');
  Result.AddPair('filesAnalyzed', TJSONBool.Create(False));
  if ASupplier <> '' then
    Result.AddPair('supplier', 'Organization: ' + ASupplier)
  else
    Result.AddPair('supplier', 'NOASSERTION');
  Result.AddPair('licenseConcluded', 'NOASSERTION');
  if ALicense <> '' then
    Result.AddPair('licenseDeclared', ALicense)
  else
    Result.AddPair('licenseDeclared', 'NOASSERTION');
  if IsWebUrl(AHomePage) then
    Result.AddPair('homepage', AHomePage);
  Result.AddPair('copyrightText', 'NOASSERTION');
  if AHash <> '' then
  begin
    Sums := TJSONArray.Create;
    Sum := TJSONObject.Create;
    Sum.AddPair('algorithm', 'SHA256');
    Sum.AddPair('checksumValue', LowerCase(AHash));
    Sums.Add(Sum);
    Result.AddPair('checksums', Sums);
  end;
  if ADescription <> '' then
    Result.AddPair('comment', ADescription);
end;

function Relationship(const AFrom, AType, ATo: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('spdxElementId', AFrom);
  Result.AddPair('relationshipType', AType);
  Result.AddPair('relatedSpdxElement', ATo);
end;

function SbomSpdxJson(ASbom: TSbom; const AOptions: TSbomWriteOptions): string;
var
  Root, Creation: TJSONObject;
  Creators, Packages, Rels: TJSONArray;
  Ids: TDictionary<string, string>;       // nome (minusculas) -> SPDXID
  Used: TDictionary<string, Boolean>;
  C: TSbomComponent;
  U, Id, Base, Doc, RootId, DocId: string;
  N: Integer;
  P: TSbomProject;
begin
  P := ASbom.Project;
  DocId := AOptions.DocumentId;
  if DocId = '' then
    DocId := NewGuidText;
  Doc := 'SPDXRef-DOCUMENT';
  RootId := 'SPDXRef-Package-App-' + SpdxSafe(ProjectNameOf(ASbom));
  Ids := TDictionary<string, string>.Create;
  Used := TDictionary<string, Boolean>.Create;
  Root := TJSONObject.Create;
  try
    Used.Add(LowerCase(RootId), True);
    for C in ASbom.Components do
    begin
      Base := 'SPDXRef-Unit-' + SpdxSafe(C.Name);
      Id := Base;
      N := 2;
      while not Used.TryAdd(LowerCase(Id), True) do
      begin
        Id := Base + '-' + IntToStr(N);
        Inc(N);
      end;
      Ids.Add(LowerCase(C.Name), Id);
    end;

    Root.AddPair('spdxVersion', SpdxVersion);
    Root.AddPair('dataLicense', 'CC0-1.0');
    Root.AddPair('SPDXID', Doc);
    Root.AddPair('name', ProjectNameOf(ASbom));
    Root.AddPair('documentNamespace', 'https://spdx.org/spdxdocs/' + SpdxSafe(ProjectNameOf(ASbom)) + '-' + DocId);
    Creation := TJSONObject.Create;
    Creation.AddPair('created', IsoNow(ASbom));
    Creators := TJSONArray.Create;
    Creators.Add('Tool: ' + AOptions.ToolName + '-' + AOptions.ToolVersion);
    if P.Company <> '' then
      Creators.Add('Organization: ' + P.Company);
    Creation.AddPair('creators', Creators);
    Root.AddPair('creationInfo', Creation);

    Packages := TJSONArray.Create;
    Packages.Add(SpdxPackage(RootId, ProjectNameOf(ASbom), P.Version, P.Company, '', P.Description));
    for C in ASbom.Components do
      Packages.Add(SpdxPackage(Ids[LowerCase(C.Name)], C.Name, C.Version, SupplierOf(C.Origin), C.Hash,
        OriginName(C.Origin) + ' · ' + EvidenceName(C.Evidence) + ' · ' + ConfidenceName(C.Confidence) +
        IfThen(C.LibraryName <> '', ' · ' + C.LibraryName, '') + IfThen(C.LicenseName <> '', ' · ' + C.LicenseName, ''),
        C.License, C.HomePage));
    Root.AddPair('packages', Packages);

    Rels := TJSONArray.Create;
    Rels.Add(Relationship(Doc, 'DESCRIBES', RootId));
    for C in ASbom.Components do
    begin
      if (C.Origin <> soProject) or (Length(C.UsedBy) = 0) then
        Rels.Add(Relationship(RootId, 'DEPENDS_ON', Ids[LowerCase(C.Name)]));
      for U in C.UsedBy do
        if (ASbom.Find(U) <> nil) and (ASbom.Find(U).Origin = soProject) then
          Rels.Add(Relationship(Ids[LowerCase(U)], 'DEPENDS_ON', Ids[LowerCase(C.Name)]));
    end;
    Root.AddPair('relationships', Rels);
    Result := Root.Format(2);
  finally
    Root.Free;
    Used.Free;
    Ids.Free;
  end;
end;

{ validadores }

function ParseObject(const AJson: string; out AProblem: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    AProblem := 'o ficheiro está vazio';
    Exit;
  end;
  try
    V := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      V := nil;
  end;
  if not (V is TJSONObject) then
  begin
    V.Free;
    AProblem := 'não é JSON válido';
    Exit;
  end;
  Result := TJSONObject(V);
end;

function IsHexHash(const AText: string; ALength: Integer): Boolean;
begin
  Result := (Length(AText) = ALength) and TRegEx.IsMatch(AText, '^[0-9a-f]+$');
end;

function ValidateCycloneDx(const AJson: string; out AProblem: string): Boolean;
var
  Root, Meta, C, D, H: TJSONObject;
  Comps, Deps, DepList, Hashes, Lics: TJSONArray;
  Refs: TDictionary<string, Boolean>;
  V: TJSONValue;
  I, J, K: Integer;
  Ref, Serial: string;
begin
  Result := False;
  AProblem := '';
  Root := ParseObject(AJson, AProblem);
  if Root = nil then
    Exit;
  Refs := TDictionary<string, Boolean>.Create;
  try
    if Root.GetValue<string>('bomFormat', '') <> 'CycloneDX' then
    begin
      AProblem := 'bomFormat deve ser CycloneDX';
      Exit;
    end;
    if Root.GetValue<string>('specVersion', '') = '' then
    begin
      AProblem := 'falta specVersion';
      Exit;
    end;
    Serial := Root.GetValue<string>('serialNumber', '');
    if (Serial <> '') and not TRegEx.IsMatch(Serial, '^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    begin
      AProblem := 'serialNumber inválido: ' + Serial;
      Exit;
    end;
    if Root.GetValue('version') = nil then
    begin
      AProblem := 'falta version';
      Exit;
    end;
    if not (Root.GetValue('metadata') is TJSONObject) then
    begin
      AProblem := 'falta metadata';
      Exit;
    end;
    Meta := TJSONObject(Root.GetValue('metadata'));
    if not (Meta.GetValue('component') is TJSONObject) then
    begin
      AProblem := 'falta metadata.component';
      Exit;
    end;
    C := TJSONObject(Meta.GetValue('component'));
    if (C.GetValue<string>('name', '') = '') or (C.GetValue<string>('type', '') = '') then
    begin
      AProblem := 'metadata.component precisa de type e name';
      Exit;
    end;
    Refs.TryAdd(C.GetValue<string>('bom-ref', ''), True);
    V := Root.GetValue('components');
    if not (V is TJSONArray) then
    begin
      AProblem := 'falta components';
      Exit;
    end;
    Comps := TJSONArray(V);
    for I := 0 to Comps.Count - 1 do
    begin
      if not (Comps.Items[I] is TJSONObject) then
      begin
        AProblem := Format('components[%d] não é um objeto', [I]);
        Exit;
      end;
      C := TJSONObject(Comps.Items[I]);
      if (C.GetValue<string>('type', '') = '') or (C.GetValue<string>('name', '') = '') then
      begin
        AProblem := Format('components[%d] precisa de type e name', [I]);
        Exit;
      end;
      Ref := C.GetValue<string>('bom-ref', '');
      if (Ref <> '') and not Refs.TryAdd(Ref, True) then
      begin
        AProblem := 'bom-ref repetido: ' + Ref;
        Exit;
      end;
      if C.GetValue('licenses') is TJSONArray then
      begin
        Lics := TJSONArray(C.GetValue('licenses'));
        for J := 0 to Lics.Count - 1 do
        begin
          if (not (Lics.Items[J] is TJSONObject)) or (not (TJSONObject(Lics.Items[J]).GetValue('license') is TJSONObject)) then
          begin
            AProblem := Format('licença mal formada em %s', [C.GetValue<string>('name', '')]);
            Exit;
          end;
          H := TJSONObject(TJSONObject(Lics.Items[J]).GetValue('license'));
          if (H.GetValue<string>('id', '') = '') and (H.GetValue<string>('name', '') = '') then
          begin
            AProblem := Format('a licença de %s precisa de id ou name', [C.GetValue<string>('name', '')]);
            Exit;
          end;
        end;
      end;
      if C.GetValue('hashes') is TJSONArray then
      begin
        Hashes := TJSONArray(C.GetValue('hashes'));
        for J := 0 to Hashes.Count - 1 do
        begin
          if not (Hashes.Items[J] is TJSONObject) then
            Continue;
          H := TJSONObject(Hashes.Items[J]);
          if (H.GetValue<string>('alg', '') = 'SHA-256') and not IsHexHash(H.GetValue<string>('content', ''), 64) then
          begin
            AProblem := Format('hash SHA-256 mal formado em %s', [C.GetValue<string>('name', '')]);
            Exit;
          end;
        end;
      end;
    end;
    V := Root.GetValue('dependencies');
    if V is TJSONArray then
    begin
      Deps := TJSONArray(V);
      for I := 0 to Deps.Count - 1 do
      begin
        D := TJSONObject(Deps.Items[I]);
        Ref := D.GetValue<string>('ref', '');
        if not Refs.ContainsKey(Ref) then
        begin
          AProblem := 'dependencies refere um componente que não existe: ' + Ref;
          Exit;
        end;
        if D.GetValue('dependsOn') is TJSONArray then
        begin
          DepList := TJSONArray(D.GetValue('dependsOn'));
          for K := 0 to DepList.Count - 1 do
            if not Refs.ContainsKey(DepList.Items[K].Value) then
            begin
              AProblem := 'dependsOn refere um componente que não existe: ' + DepList.Items[K].Value;
              Exit;
            end;
        end;
      end;
    end;
    Result := True;
  finally
    Refs.Free;
    Root.Free;
  end;
end;

function ValidateSpdx(const AJson: string; out AProblem: string): Boolean;
var
  Root, P, R, Sum, Creation: TJSONObject;
  Packages, Rels, Sums: TJSONArray;
  Ids: TDictionary<string, Boolean>;
  I, J: Integer;
  Id: string;
begin
  Result := False;
  AProblem := '';
  Root := ParseObject(AJson, AProblem);
  if Root = nil then
    Exit;
  Ids := TDictionary<string, Boolean>.Create;
  try
    if Root.GetValue<string>('spdxVersion', '') = '' then
    begin
      AProblem := 'falta spdxVersion';
      Exit;
    end;
    if Root.GetValue<string>('dataLicense', '') <> 'CC0-1.0' then
    begin
      AProblem := 'dataLicense deve ser CC0-1.0';
      Exit;
    end;
    if Root.GetValue<string>('SPDXID', '') <> 'SPDXRef-DOCUMENT' then
    begin
      AProblem := 'SPDXID do documento deve ser SPDXRef-DOCUMENT';
      Exit;
    end;
    if Root.GetValue<string>('name', '') = '' then
    begin
      AProblem := 'falta name';
      Exit;
    end;
    if Root.GetValue<string>('documentNamespace', '') = '' then
    begin
      AProblem := 'falta documentNamespace';
      Exit;
    end;
    if not (Root.GetValue('creationInfo') is TJSONObject) then
    begin
      AProblem := 'falta creationInfo';
      Exit;
    end;
    Creation := TJSONObject(Root.GetValue('creationInfo'));
    if (Creation.GetValue<string>('created', '') = '') or not (Creation.GetValue('creators') is TJSONArray) then
    begin
      AProblem := 'creationInfo precisa de created e creators';
      Exit;
    end;
    Ids.Add('SPDXRef-DOCUMENT', True);
    if not (Root.GetValue('packages') is TJSONArray) then
    begin
      AProblem := 'falta packages';
      Exit;
    end;
    Packages := TJSONArray(Root.GetValue('packages'));
    for I := 0 to Packages.Count - 1 do
    begin
      P := TJSONObject(Packages.Items[I]);
      Id := P.GetValue<string>('SPDXID', '');
      if not TRegEx.IsMatch(Id, '^SPDXRef-[A-Za-z0-9.\-]+$') then
      begin
        AProblem := Format('packages[%d]: SPDXID inválido: %s', [I, Id]);
        Exit;
      end;
      if not Ids.TryAdd(Id, True) then
      begin
        AProblem := 'SPDXID repetido: ' + Id;
        Exit;
      end;
      if P.GetValue<string>('name', '') = '' then
      begin
        AProblem := Format('packages[%d] precisa de name', [I]);
        Exit;
      end;
      if (P.GetValue<string>('downloadLocation', '') = '') or (P.GetValue<string>('copyrightText', '') = '') or
         (P.GetValue<string>('licenseConcluded', '') = '') or (P.GetValue<string>('licenseDeclared', '') = '') then
      begin
        AProblem := Format('packages[%d] (%s) não tem os campos obrigatórios do SPDX 2.3', [I, P.GetValue<string>('name', '')]);
        Exit;
      end;
      if P.GetValue('checksums') is TJSONArray then
      begin
        Sums := TJSONArray(P.GetValue('checksums'));
        for J := 0 to Sums.Count - 1 do
        begin
          Sum := TJSONObject(Sums.Items[J]);
          if (Sum.GetValue<string>('algorithm', '') = 'SHA256') and
             not IsHexHash(Sum.GetValue<string>('checksumValue', ''), 64) then
          begin
            AProblem := 'checksum SHA256 mal formado em ' + P.GetValue<string>('name', '');
            Exit;
          end;
        end;
      end;
    end;
    if Root.GetValue('relationships') is TJSONArray then
    begin
      Rels := TJSONArray(Root.GetValue('relationships'));
      for I := 0 to Rels.Count - 1 do
      begin
        R := TJSONObject(Rels.Items[I]);
        if not Ids.ContainsKey(R.GetValue<string>('spdxElementId', '')) then
        begin
          AProblem := 'relationships refere um elemento que não existe: ' + R.GetValue<string>('spdxElementId', '');
          Exit;
        end;
        if not Ids.ContainsKey(R.GetValue<string>('relatedSpdxElement', '')) then
        begin
          AProblem := 'relationships refere um elemento que não existe: ' + R.GetValue<string>('relatedSpdxElement', '');
          Exit;
        end;
      end;
    end;
    Result := True;
  finally
    Ids.Free;
    Root.Free;
  end;
end;

procedure SaveSbomFile(const AFileName, AContent: string);
var
  Dir: string;
  Enc: TUTF8Encoding;
begin
  Dir := TPath.GetDirectoryName(AFileName);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  Enc := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(AFileName, AContent, Enc);
  finally
    Enc.Free;
  end;
end;

end.
