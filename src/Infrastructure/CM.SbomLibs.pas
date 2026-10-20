unit CM.SbomLibs;

{ A biblioteca de cada unit de terceiros do SBOM: o nome, a versao e a licenca.

  Para cada unit de terceiros que tem ficheiro, sobe-se pelas pastas ate achar a raiz da biblioteca: a primeira pasta que
  tem um boss.json, um ficheiro de licenca (LICENSE, COPYING...), um repositorio (.git) ou que e uma pasta do GetIt
  (CatalogRepository\Nome-1.2) ou do Boss (<projeto>\modules\nome). Nunca se sobe acima da pasta do projeto. Dai:
    - nome: o do boss.json, ou o da pasta (sem o sufixo da versao);
    - versao: a do boss.json, a do boss-lock.json do projeto ou a do nome da pasta do GetIt ('Spring4D-2.0');
    - licenca: o campo license do boss.json ou, se nao diz, o texto do ficheiro de licenca (CM.Licenses). Um ficheiro que
      nao se reconhece fica como «ver o ficheiro», e nunca se adivinha uma licenca.
  So le: nada se escreve nem se altera. Cada pasta e lida uma so vez. }

interface

uses
  System.SysUtils, System.Generics.Collections, CM.Sbom;

type
  TSbomLibrary = record
    Found: Boolean;                // achou-se a raiz de uma biblioteca
    Root: string;
    Name: string;
    Version: string;
    VersionSource: string;         // 'boss.json', 'boss-lock.json' ou 'GetIt' (a pasta com a versao no nome)
    License: string;               // identificador SPDX; '' = nao reconhecida
    LicenseName: string;           // 'ver <ficheiro>' quando ha ficheiro de licenca nao reconhecido
    LicenseSource: string;         // o nome do ficheiro de licenca ou 'boss.json'
    HomePage: string;
  end;

  TLibraryFinder = class
  private
    FProjectRoot: string;
    FByDir: TDictionary<string, TSbomLibrary>;
    FLock: TDictionary<string, string>;
    FLockLoaded: Boolean;
    function LockVersion(const AName: string): string;
    function IsContainerRoot(const ADir: string): Boolean;
    function LicenseFile(const ADir: string): string;
    function Describe(const ARoot: string): TSbomLibrary;
  public
    constructor Create(const AProjectRoot: string);
    destructor Destroy; override;
    // a biblioteca de um ficheiro de unit (Found = False se nao se achou raiz)
    function Find(const AUnitFile: string): TSbomLibrary;
  end;

// preenche a biblioteca, a versao e a licenca dos componentes de terceiros que tem ficheiro
procedure AttachLibraries(ASbom: TSbom; const AProjectRoot: string);

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.StrUtils, CM.Licenses;

const
  MaxLevels = 8;
  MaxLicenseBytes = 20000;

function Norm(const APath: string): string;
begin
  Result := ExcludeTrailingPathDelimiter(APath.Replace('/', '\'));
end;

function IsDriveRoot(const ADir: string): Boolean;
begin
  Result := (Length(ADir) <= 3) and (Pos(':', ADir) > 0);
end;

function ReadTextHead(const AFileName: string; AMax: Integer): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
  Enc: TEncoding;
  N, Offset: Integer;
begin
  Result := '';
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      N := Min(Stream.Size, AMax);
      SetLength(Bytes, N);
      if N > 0 then
        Stream.ReadBuffer(Bytes[0], N);
    finally
      Stream.Free;
    end;
    Enc := nil;
    Offset := TEncoding.GetBufferEncoding(Bytes, Enc, TEncoding.UTF8);
    Result := Enc.GetString(Bytes, Offset, Length(Bytes) - Offset);
  except
    Result := '';
  end;
end;

{ TLibraryFinder }

constructor TLibraryFinder.Create(const AProjectRoot: string);
begin
  inherited Create;
  FProjectRoot := Norm(AProjectRoot);
  FByDir := TDictionary<string, TSbomLibrary>.Create;
end;

destructor TLibraryFinder.Destroy;
begin
  FLock.Free;
  FByDir.Free;
  inherited;
end;

function TLibraryFinder.LockVersion(const AName: string): string;
var
  Path: string;
begin
  if not FLockLoaded then
  begin
    FLockLoaded := True;
    Path := TPath.Combine(FProjectRoot, 'boss-lock.json');
    if (FProjectRoot <> '') and TFile.Exists(Path) then
      FLock := ParseBossLock(ReadTextHead(Path, 1024 * 1024));
  end;
  if (FLock = nil) or not FLock.TryGetValue(LowerCase(AName), Result) then
    Result := '';
end;

// uma pasta do GetIt (CatalogRepository\Nome-1.2) ou do Boss (<projeto>\modules\nome)
function TLibraryFinder.IsContainerRoot(const ADir: string): Boolean;
var
  Parent: string;
begin
  Parent := Norm(TPath.GetDirectoryName(ADir));
  Result := SameText(TPath.GetFileName(Parent), 'CatalogRepository') or
    ((FProjectRoot <> '') and SameText(Parent, FProjectRoot + '\modules')) or
    (IsVersionFolder(TPath.GetFileName(ADir)) and
     SameText(TPath.GetFileName(Norm(TPath.GetDirectoryName(Parent))), 'CatalogRepository'));
end;

// o ficheiro de licenca da pasta (o primeiro por ordem alfabetica); '' se nao ha
function TLibraryFinder.LicenseFile(const ADir: string): string;
var
  Pattern: string;
  Files: TArray<string>;
begin
  Result := '';
  for Pattern in ['LICEN*', 'COPYING*', 'UNLICENSE*'] do
  begin
    try
      Files := TDirectory.GetFiles(ADir, Pattern);
    except
      Files := nil;
    end;
    TArray.Sort<string>(Files);
    if Length(Files) > 0 then
      Exit(Files[0]);
  end;
end;

function TLibraryFinder.Describe(const ARoot: string): TSbomLibrary;
var
  Boss: TBossInfo;
  FolderName, FolderVersion, BossPath, LicPath, Id, Parent: string;
  HasBoss, Versioned, InGetIt: Boolean;
begin
  Result := Default(TSbomLibrary);
  Result.Found := True;
  Result.Root := ARoot;
  FolderName := TPath.GetFileName(ARoot);
  Versioned := SplitVersionedFolder(FolderName, Result.Name, FolderVersion);
  if not Versioned then
    Result.Name := FolderName;
  Parent := Norm(TPath.GetDirectoryName(ARoot));
  InGetIt := SameText(TPath.GetFileName(Parent), 'CatalogRepository');
  if Versioned and InGetIt then
  begin
    Result.Version := FolderVersion;                 // CatalogRepository\Spring4D-2.0
    Result.VersionSource := 'GetIt';
  end;
  if IsVersionFolder(FolderName) and (Parent <> '') and not IsDriveRoot(Parent) then
  begin
    // a pasta e so a versao (CatalogRepository\Chart4D-13.2.0): o nome esta na pasta de cima
    Result.Name := TPath.GetFileName(Parent);
    if SameText(TPath.GetFileName(Norm(TPath.GetDirectoryName(Parent))), 'CatalogRepository') then
    begin
      Result.Name := StripDelphiSuffix(Result.Name);
      Result.VersionSource := 'GetIt';
    end
    else
      Result.VersionSource := Result.Name;
    Result.Version := FolderName;
    if (Result.Version <> '') and (Result.Version[1] in ['v', 'V']) then
      Result.Version := Copy(Result.Version, 2, MaxInt);
    Versioned := False;
  end;

  BossPath := TPath.Combine(ARoot, 'boss.json');
  HasBoss := TFile.Exists(BossPath) and ParseBossJson(ReadTextHead(BossPath, 256 * 1024), Boss);
  if HasBoss then
  begin
    if Boss.Name <> '' then
      Result.Name := Boss.Name;
    if Boss.Version <> '' then
    begin
      Result.Version := Boss.Version;
      Result.VersionSource := 'boss.json';
    end;
    Result.HomePage := Boss.HomePage;
  end;
  if Result.Version = '' then
  begin
    Result.Version := LockVersion(Result.Name);
    if Result.Version = '' then
      Result.Version := LockVersion(FolderName);
    if Result.Version <> '' then
      Result.VersionSource := 'boss-lock.json'
    else if Versioned then
    begin
      Result.Version := FolderVersion;
      Result.VersionSource := FolderName;
    end;
  end;

  // a licenca: o que o boss.json diz, se for uma que se reconhece; senao o texto do ficheiro
  if HasBoss and (Boss.License <> '') then
  begin
    Id := NormalizeLicenseId(Boss.License);
    if Id <> '' then
    begin
      Result.License := Id;
      Result.LicenseSource := 'boss.json';
    end;
  end;
  if Result.License = '' then
  begin
    LicPath := LicenseFile(ARoot);
    if LicPath <> '' then
    begin
      Id := DetectLicenseId(ReadTextHead(LicPath, MaxLicenseBytes));
      Result.LicenseSource := TPath.GetFileName(LicPath);
      if Id <> '' then
        Result.License := Id
      else
        Result.LicenseName := 'See ' + Result.LicenseSource;
    end
    else if HasBoss and (Boss.License <> '') then
    begin
      Result.LicenseName := Boss.License;            // dito no boss.json, mas nao e uma que se reconheca
      Result.LicenseSource := 'boss.json';
    end;
  end;
end;

function TLibraryFinder.Find(const AUnitFile: string): TSbomLibrary;
var
  Dir: string;
  Level: Integer;
  Visited: TList<string>;
  Key: string;
begin
  Result := Default(TSbomLibrary);
  Dir := Norm(TPath.GetDirectoryName(AUnitFile));
  Visited := TList<string>.Create;
  try
    for Level := 1 to MaxLevels do
    begin
      if (Dir = '') or IsDriveRoot(Dir) then
        Break;
      // a pasta do proprio projecto nunca e uma biblioteca
      if (FProjectRoot <> '') and SameText(Dir, FProjectRoot) then
        Break;
      Key := LowerCase(Dir);
      if FByDir.TryGetValue(Key, Result) then
        Break;
      Visited.Add(Key);
      if TFile.Exists(TPath.Combine(Dir, 'boss.json')) or (LicenseFile(Dir) <> '') or TDirectory.Exists(TPath.Combine(Dir, '.git')) or
         IsContainerRoot(Dir) then
      begin
        Result := Describe(Dir);
        Visited.Add(Key);
        Break;
      end;
      Dir := Norm(TPath.GetDirectoryName(Dir));
    end;
    // as pastas por onde se passou ficam com o mesmo resultado (a proxima unit da biblioteca nao volta a procurar)
    for Key in Visited do
      FByDir.AddOrSetValue(Key, Result);
  finally
    Visited.Free;
  end;
end;

procedure AttachLibraries(ASbom: TSbom; const AProjectRoot: string);
var
  Finder: TLibraryFinder;
  C: TSbomComponent;
  L: TSbomLibrary;
begin
  if ASbom = nil then
    Exit;
  Finder := TLibraryFinder.Create(AProjectRoot);
  try
    for C in ASbom.Components do
    begin
      if (C.Origin <> soThirdParty) or (C.Path = '') then
        Continue;
      L := Finder.Find(C.Path);
      if not L.Found then
        Continue;
      C.LibraryName := L.Name;
      C.Version := L.Version;
      C.VersionSource := L.VersionSource;
      C.License := L.License;
      C.LicenseName := L.LicenseName;
      C.LicenseSource := L.LicenseSource;
      C.HomePage := L.HomePage;
    end;
  finally
    Finder.Free;
  end;
end;

end.
