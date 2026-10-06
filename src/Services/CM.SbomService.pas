unit CM.SbomService;

{ Gera o SBOM de um projecto de ponta a ponta: le o .dproj, monta os componentes a partir do grafo de dependencias,
  confirma-os com o .map (se existir e se o utilizador quiser) e resolve cada um para um ficheiro, uma origem e um hash.

  Tudo so de leitura. Pode correr em segundo plano (a resolucao percorre pastas e calcula hashes). Os avisos ficam em
  TSbom.Warnings, como frases em portugues, para a interface os traduzir. }

interface

uses
  System.SysUtils, CM.Analyzer, CM.Deps, CM.Sbom;

type
  TSbomGenOptions = record
    IncludeProjectUnits: Boolean;     // tambem lista as units do proprio projecto
    UseMap: Boolean;                  // confirma com o .map, se existir
    ComputeHashes: Boolean;
    Config: string;                   // '' = a que se entrega (Release)
    Platform: string;                 // '' = a do projecto
    AutoDelphi: Boolean;              // True: procura a instalacao do Delphi quando DelphiRoot esta vazio
    DelphiRoot: string;
  end;

function DefaultSbomGenOptions: TSbomGenOptions;
// AProjectName: o nome do projecto na aplicacao (usa-se quando nao ha .dproj)
function GenerateSbom(AGraph: TDepGraph; const ARoot, AProjectName: string; const AOptions: TSbomGenOptions;
  const AProgress: TScanProgress = nil): TSbom;
// <nome-do-projecto>.cdx.json / .spdx.json
function SbomFileName(const AProjectName, AExt: string): string;

implementation

uses
  System.Classes, System.IOUtils, System.Generics.Collections, CM.Dproj, CM.MapFile, CM.SbomResolve;

const
  WarnNoDproj = 'Não se encontrou o ficheiro .dproj: a versão e os caminhos de procura ficam por preencher.';
  WarnNoDelphi = 'Não se encontrou a instalação do Delphi: as units da Embarcadero só se reconhecem pelo nome.';
  WarnNoMap = 'Não se encontrou o ficheiro .map: compila o projeto com o mapa «Detailed» para confirmar as units ligadas.';

function DefaultSbomGenOptions: TSbomGenOptions;
begin
  Result := Default(TSbomGenOptions);
  Result.IncludeProjectUnits := False;
  Result.UseMap := True;
  Result.ComputeHashes := True;
  Result.AutoDelphi := True;
end;

function SbomFileName(const AProjectName, AExt: string): string;
var
  C: Char;
  Slug: string;
begin
  Slug := '';
  for C in LowerCase(Trim(AProjectName)) do
    if CharInSet(C, ['a'..'z', '0'..'9']) then
      Slug := Slug + C
    else if (Slug <> '') and (Slug[Length(Slug)] <> '-') then
      Slug := Slug + '-';
  Slug := Slug.TrimRight(['-']);
  if Slug = '' then
    Slug := 'projeto';
  Result := Slug + AExt;
end;

function GenerateSbom(AGraph: TDepGraph; const ARoot, AProjectName: string; const AOptions: TSbomGenOptions;
  const AProgress: TScanProgress): TSbom;
var
  Dproj: TDprojInfo;
  Vars: TDictionary<string, string>;
  Project: TSbomProject;
  Resolve: TSbomResolveOptions;
  DelphiRoot, DprojFile, MapPath, BaseDir: string;
begin
  DelphiRoot := AOptions.DelphiRoot;
  if (DelphiRoot = '') and AOptions.AutoDelphi then
    DelphiRoot := DetectDelphiRoot;

  Vars := IdeEnvironmentVars(DelphiRoot);          // as variaveis do IDE (so as que o utilizador definiu)
  try
    if DelphiRoot <> '' then
      Vars.AddOrSetValue('bds', DelphiRoot);
    DprojFile := FindDprojFile(ARoot, AProjectName);
    LoadDproj(DprojFile, AOptions.Config, AOptions.Platform, Vars, Dproj);
  finally
    Vars.Free;
  end;

  Project := Default(TSbomProject);
  Project.Root := ARoot;
  Project.Name := AProjectName;
  if Dproj.Found then
  begin
    if Dproj.ProjectName <> '' then
      Project.Name := Dproj.ProjectName;
    Project.Version := Dproj.FileVersion;
    Project.Description := Dproj.Description;
    Project.Company := Dproj.Company;
    Project.Copyright := Dproj.Copyright;
    Project.MainSource := Dproj.MainSource;
    Project.FrameworkType := Dproj.FrameworkType;
    Project.DelphiVersion := Dproj.ProjectVersion;
    Project.Platform := Dproj.Platform;
    Project.Configuration := Dproj.Config;
    Project.ProjectFile := Dproj.FileName;
    Project.IsPackage := Dproj.IsPackage;
  end;

  Result := BuildSbom(AGraph, Project, AOptions.IncludeProjectUnits);
  try
    // o programa principal (o .dpr) pode estar fora da pasta analisada, mas o mapa traz o seu nome: nao e uma dependencia
    Result.NoteProjectUnit(Project.Name);
    if Project.MainSource <> '' then
      Result.NoteProjectUnit(TPath.GetFileNameWithoutExtension(Project.MainSource));
    if not Dproj.Found then
      Result.Warnings.Add(WarnNoDproj);
    if DelphiRoot = '' then
      Result.Warnings.Add(WarnNoDelphi);

    if AOptions.UseMap then
    begin
      MapPath := FindMapFile(Dproj);
      if MapPath <> '' then
        ApplyMapUnits(Result, LoadMapUnits(MapPath), MapPath)
      else
        Result.Warnings.Add(WarnNoMap);
    end;

    if Dproj.Found then
      BaseDir := TPath.GetDirectoryName(Dproj.FileName)
    else
      BaseDir := ARoot;
    Resolve := Default(TSbomResolveOptions);
    Resolve.ProjectRoot := ARoot;
    Resolve.ProjectDir := BaseDir;
    Resolve.DelphiRoot := DelphiRoot;
    Resolve.SearchPaths := Dproj.UnitSearchPath;
    Resolve.Namespaces := Dproj.Namespaces;
    Resolve.ComputeHashes := AOptions.ComputeHashes;
    if DelphiRoot <> '' then
    begin
      if Dproj.Platform <> '' then
        Resolve.LibraryPaths := DelphiLibraryPaths(DelphiRoot, Dproj.Platform)
      else
        Resolve.LibraryPaths := DelphiLibraryPaths(DelphiRoot, 'Win64');
    end;
    ResolveSbom(Result, Resolve, AProgress);
  except
    Result.Free;
    raise;
  end;
end;

end.
