unit CM.Sbom;

{ SBOM (lista de materiais de software) de um projecto: que componentes entram nele, de onde vem cada um e quem os usa.

  Parte do grafo de dependencias (CM.Deps): cada unit de fora do projecto que as units do projecto usam passa a ser um
  componente. Cada componente leva a origem (RTL, VCL e FMX da Embarcadero, terceiros, ou do proprio projecto), como se
  soube dele e com que confianca:
    - confianca forte: o ficheiro da unit foi encontrado (e tem hash SHA-256);
    - media: so se conhece pelo nome e o nome e de uma biblioteca da Embarcadero;
    - fraca: so se conhece pelo nome e nao se sabe de onde vem.
  A resolucao de ficheiros e os hashes sao feitos a parte (CM.SbomResolve); aqui so ha o modelo e a classificacao pelo nome.

  Adaptado da ideia e das regras de classificacao do DX.Comply (MIT, Olaf Monien):
  https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, CM.Deps;

type
  TSbomOrigin = (soProject, soRtl, soVcl, soFmx, soThirdParty);

  // como se soube do componente
  TSbomEvidence = (seUses, seFile, seMap);

  TSbomConfidence = (scStrong, scMedium, scWeak);

  TSbomComponent = class
  public
    Name: string;                  // nome da unit
    Origin: TSbomOrigin;
    Evidence: TSbomEvidence;
    Confidence: TSbomConfidence;
    Path: string;                  // ficheiro encontrado (completo); '' = nao se encontrou
    Hash: string;                  // SHA-256 em hexadecimal; '' = nao calculado
    Layer: string;                 // so as units do projecto
    RelPath: string;               // so as units do projecto: caminho relativo a pasta do projecto, com '/'
    UsedBy: TArray<string>;        // units do projecto que a usam, por ordem alfabetica
    InMap: Boolean;                // confirmada no ficheiro .map (esta realmente ligada ao executavel)
  end;

  // o que se sabe do projecto (vem do .dproj, quando existe)
  TSbomProject = record
    Name: string;
    Version: string;               // 'FileVersion' do .dproj ('' = nao indicada)
    Description: string;
    Company: string;
    Copyright: string;
    Root: string;                  // pasta do projecto
    MainSource: string;            // .dpr / .dpk
    FrameworkType: string;         // 'VCL', 'FMX', ''
    DelphiVersion: string;         // 'ProjectVersion' do .dproj ('20.3')
    Platform: string;
    Configuration: string;
    ProjectFile: string;           // o .dproj (caminho completo; '' = nao encontrado)
    IsPackage: Boolean;
  end;

  TSbom = class
  private
    FComponents: TObjectList<TSbomComponent>;
    FWarnings: TList<string>;
    FIndex: TDictionary<string, TSbomComponent>;
    FProjectUnits: TDictionary<string, Boolean>;
  public
    Project: TSbomProject;
    Generated: TDateTime;
    MapFile: string;               // o .map usado ('' = nenhum)
    constructor Create;
    destructor Destroy; override;
    function Find(const AName: string): TSbomComponent;
    // as units do proprio projecto (estejam ou nao listadas como componentes): nunca sao dependencias
    procedure NoteProjectUnit(const AName: string);
    function IsProjectUnit(const AName: string): Boolean;
    // devolve o componente de AName, criando-o se ainda nao existe (ACreated diz se e novo)
    function Obtain(const AName: string; out ACreated: Boolean): TSbomComponent;
    procedure SortComponents;
    function CountOf(AOrigin: TSbomOrigin): Integer;
    function CountByConfidence(AConfidence: TSbomConfidence): Integer;
    function ResolvedCount: Integer;
    // com um .map: quantos componentes nao aparecem nele (so se sabem pelas clausulas uses); 0 sem mapa
    function NotLinkedCount: Integer;
    property Components: TObjectList<TSbomComponent> read FComponents;
    property Warnings: TList<string> read FWarnings;
  end;

// o nome da origem em ingles, como se escreve nos ficheiros de SBOM ('Embarcadero RTL', 'Third party'...)
function OriginName(AOrigin: TSbomOrigin): string;
function ConfidenceName(AConfidence: TSbomConfidence): string;
function EvidenceName(AEvidence: TSbomEvidence): string;
// a origem que o nome da unit sugere: bibliotecas da Embarcadero (por namespace e pelos nomes antigos, sem namespace)
// ou, se nao se reconhece, terceiros
function ClassifyUnitName(const AUnitName: string): TSbomOrigin;
// junta ao SBOM as units de um .map: as que ja la estao ficam confirmadas (ligadas ao executavel) e as outras, que ninguem
// nomeia no codigo do projecto, passam a componentes. AMapFile e o ficheiro usado (so o nome vai para os relatorios)
procedure ApplyMapUnits(ASbom: TSbom; const AUnits: TArray<string>; const AMapFile: string);
// monta o SBOM: um componente por unit de fora que o projecto usa e, se AIncludeProjectUnits, tambem as units do projecto
function BuildSbom(AGraph: TDepGraph; const AProject: TSbomProject; AIncludeProjectUnits: Boolean): TSbom;

implementation

const
  // namespaces da Embarcadero (o primeiro segmento do nome)
  RtlScopes = 'System,Winapi,Posix,Macapi,iOSapi,Androidapi,Data,Datasnap,Xml,Web,Soap,REST,Net,Bde,Ibx,FireDAC';

  // unidades da RTL antigas, escritas sem namespace (o compilador junta-lhes System., Winapi., Data...)
  LegacyRtl = 'SysInit,SysUtils,Classes,Math,Variants,StrUtils,TypInfo,DateUtils,IniFiles,Registry,ComObj,ActiveX,' +
    'ShellAPI,Windows,Messages,Types,UITypes,IOUtils,Character,Rtti,Masks,Contnrs,SyncObjs,ZLib,Hash,Diagnostics,' +
    'Threading,Generics.Collections,Generics.Defaults,WideStrUtils,AnsiStrings,StdConvs,ConvUtils,MaskUtils,Odbc,' +
    'WinSock,WinInet,ShlObj,CommCtrl,RichEdit,MMSystem,Imm,UxTheme,DwmApi,PsAPI,TlHelp32,SHFolder,WinSvc,ComConst,' +
    'CtlConsts,DB,DBClient,Provider,SqlExpr,DBXCommon,JSON,NetEncoding,HttpApp,XmlDoc,XMLIntf,XmlDom,ADOInt,ADODB,' +
    'DBCommon,Consts,RTLConsts,Ole2,OleCtrls,OleServer,StdActns';

  LegacyVcl = 'Forms,Controls,Graphics,Dialogs,StdCtrls,ExtCtrls,ComCtrls,Menus,Buttons,ImgList,ActnList,ActnMan,' +
    'ActnCtrls,ToolWin,Grids,DBGrids,DBCtrls,CheckLst,Clipbrd,ExtDlgs,FileCtrl,Mask,Printers,Tabs,TabNotBk,Themes,' +
    'Styles,GraphUtil,Jpeg,GIFImg,PngImage,AppEvnts,ValEdit,Spin,OleCtnrs,ScktComp,WinHelpViewer,HelpIntfs,ExtActns,' +
    'ComStrs,Calendar';

var
  GScopes: TDictionary<string, Boolean>;
  GLegacy: TDictionary<string, TSbomOrigin>;

procedure FillTables;
var
  S: string;
begin
  GScopes := TDictionary<string, Boolean>.Create;
  for S in RtlScopes.Split([',']) do
    GScopes.Add(LowerCase(S), True);
  GLegacy := TDictionary<string, TSbomOrigin>.Create;
  for S in LegacyRtl.Split([',']) do
    GLegacy.AddOrSetValue(LowerCase(S), soRtl);
  for S in LegacyVcl.Split([',']) do
    GLegacy.AddOrSetValue(LowerCase(S), soVcl);
end;

function OriginName(AOrigin: TSbomOrigin): string;
begin
  case AOrigin of
    soProject: Result := 'Local project';
    soRtl: Result := 'Embarcadero RTL';
    soVcl: Result := 'Embarcadero VCL';
    soFmx: Result := 'Embarcadero FMX';
  else
    Result := 'Third party';
  end;
end;

function ConfidenceName(AConfidence: TSbomConfidence): string;
begin
  case AConfidence of
    scStrong: Result := 'Strong';
    scMedium: Result := 'Medium';
  else
    Result := 'Weak';
  end;
end;

function EvidenceName(AEvidence: TSbomEvidence): string;
begin
  case AEvidence of
    seFile: Result := 'File';
    seMap: Result := 'Map';
  else
    Result := 'Uses';
  end;
end;

function ClassifyUnitName(const AUnitName: string): TSbomOrigin;
var
  P: Integer;
  Scope: string;
begin
  P := Pos('.', AUnitName);
  if P > 0 then
  begin
    Scope := LowerCase(Copy(AUnitName, 1, P - 1));
    if Scope = 'vcl' then
      Exit(soVcl);
    if Scope = 'fmx' then
      Exit(soFmx);
    if GScopes.ContainsKey(Scope) then
      Exit(soRtl);
  end
  else if SameText(AUnitName, 'System') then
    Exit(soRtl);
  if not GLegacy.TryGetValue(LowerCase(AUnitName), Result) then
    Result := soThirdParty;
end;

{ TSbom }

constructor TSbom.Create;
begin
  inherited;
  FComponents := TObjectList<TSbomComponent>.Create(True);
  FWarnings := TList<string>.Create;
  FIndex := TDictionary<string, TSbomComponent>.Create;
  FProjectUnits := TDictionary<string, Boolean>.Create;
  Generated := Now;
end;

destructor TSbom.Destroy;
begin
  FProjectUnits.Free;
  FIndex.Free;
  FWarnings.Free;
  FComponents.Free;
  inherited;
end;

function TSbom.Find(const AName: string): TSbomComponent;
begin
  if not FIndex.TryGetValue(LowerCase(AName), Result) then
    Result := nil;
end;

procedure TSbom.NoteProjectUnit(const AName: string);
begin
  FProjectUnits.AddOrSetValue(LowerCase(AName), True);
end;

function TSbom.IsProjectUnit(const AName: string): Boolean;
begin
  Result := FProjectUnits.ContainsKey(LowerCase(AName));
end;

function TSbom.Obtain(const AName: string; out ACreated: Boolean): TSbomComponent;
begin
  Result := Find(AName);
  ACreated := Result = nil;
  if ACreated then
  begin
    Result := TSbomComponent.Create;
    Result.Name := AName;
    FComponents.Add(Result);
    FIndex.Add(LowerCase(AName), Result);
  end;
end;

procedure TSbom.SortComponents;
begin
  FComponents.Sort(TComparer<TSbomComponent>.Construct(
    function(const A, B: TSbomComponent): Integer
    begin
      Result := Ord(A.Origin) - Ord(B.Origin);
      if Result = 0 then
        Result := CompareText(A.Name, B.Name);
    end));
end;

function TSbom.CountOf(AOrigin: TSbomOrigin): Integer;
var
  C: TSbomComponent;
begin
  Result := 0;
  for C in FComponents do
    if C.Origin = AOrigin then
      Inc(Result);
end;

function TSbom.CountByConfidence(AConfidence: TSbomConfidence): Integer;
var
  C: TSbomComponent;
begin
  Result := 0;
  for C in FComponents do
    if C.Confidence = AConfidence then
      Inc(Result);
end;

function TSbom.ResolvedCount: Integer;
var
  C: TSbomComponent;
begin
  Result := 0;
  for C in FComponents do
    if C.Path <> '' then
      Inc(Result);
end;

function TSbom.NotLinkedCount: Integer;
var
  C: TSbomComponent;
begin
  Result := 0;
  if MapFile = '' then
    Exit;
  for C in FComponents do
    if not C.InMap then
      Inc(Result);
end;

procedure ApplyMapUnits(ASbom: TSbom; const AUnits: TArray<string>; const AMapFile: string);
var
  Name: string;
  C: TSbomComponent;
  Created: Boolean;
begin
  if ASbom = nil then
    Exit;
  ASbom.MapFile := AMapFile;
  for Name in AUnits do
  begin
    // as units do proprio projecto que o mapa tambem traz: so contam se o SBOM as lista
    if ASbom.IsProjectUnit(Name) and (ASbom.Find(Name) = nil) then
      Continue;
    C := ASbom.Obtain(Name, Created);
    if Created then
    begin
      C.Origin := ClassifyUnitName(Name);
      if C.Origin = soThirdParty then
        C.Confidence := scWeak
      else
        C.Confidence := scMedium;
    end;
    C.InMap := True;
    C.Evidence := seMap;
  end;
  ASbom.SortComponents;
end;

procedure AddUser(AComponent: TSbomComponent; const AUser: string);
var
  U: string;
begin
  for U in AComponent.UsedBy do
    if SameText(U, AUser) then
      Exit;
  SetLength(AComponent.UsedBy, Length(AComponent.UsedBy) + 1);
  AComponent.UsedBy[High(AComponent.UsedBy)] := AUser;
end;

function BuildSbom(AGraph: TDepGraph; const AProject: TSbomProject; AIncludeProjectUnits: Boolean): TSbom;
var
  N: TDepNode;
  C: TSbomComponent;
  Created: Boolean;
  Ext: string;
  D: Integer;
begin
  Result := TSbom.Create;
  Result.Project := AProject;
  if AGraph = nil then
    Exit;
  for N in AGraph.Nodes do
    Result.NoteProjectUnit(N.Name);
  if AIncludeProjectUnits then
    for N in AGraph.Nodes do
    begin
      C := Result.Obtain(N.Name, Created);
      C.Origin := soProject;
      C.Evidence := seFile;
      C.Confidence := scStrong;
      C.Layer := N.Layer;
      C.RelPath := N.Path;
      for D in N.Dependents do
        AddUser(C, AGraph.Nodes[D].Name);
    end;
  for N in AGraph.Nodes do
    for Ext in N.External do
    begin
      C := Result.Obtain(Ext, Created);
      if Created then
      begin
        C.Origin := ClassifyUnitName(Ext);
        C.Evidence := seUses;
        if C.Origin = soThirdParty then
          C.Confidence := scWeak
        else
          C.Confidence := scMedium;
      end;
      AddUser(C, N.Name);
    end;
  for C in Result.Components do
    TArray.Sort<string>(C.UsedBy, TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareText(A, B);
      end));
  Result.SortComponents;
end;

initialization
  FillTables;

finalization
  GLegacy.Free;
  GScopes.Free;

end.
