unit CM.SbomResolve;

{ Resolve os componentes de um SBOM para ficheiros: onde esta cada unit, de quem e (Embarcadero, terceiros ou o proprio
  projecto) e o seu hash SHA-256.

  Procura cada unit, por esta ordem, nos caminhos de procura do .dproj, nas fontes do Delphi (source\) e nos caminhos da
  biblioteca do IDE (registo do Windows). Prefere o .pas ao .dcu. Um nome antigo, sem namespace (SysUtils), tenta-se
  tambem com os namespaces do projecto (System.SysUtils). Quem e achado fica com confianca forte; o resto continua a
  conhecer-se so pelo nome.

  Adaptado das regras do DX.Comply.UnitResolver (MIT, Olaf Monien): https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, CM.Analyzer, CM.Sbom;

type
  TSbomResolveOptions = record
    ProjectRoot: string;              // a pasta do projecto (as units do projecto resolvem-se com o seu caminho relativo)
    ProjectDir: string;               // a pasta do .dproj, base dos caminhos relativos ('' = ProjectRoot)
    DelphiRoot: string;               // onde o Delphi esta instalado ('' = nao se sabe)
    SearchPaths: TArray<string>;      // caminhos de procura do .dproj, como estao escritos
    LibraryPaths: TArray<string>;     // caminhos da biblioteca do IDE, ja expandidos
    Namespaces: TArray<string>;       // espacos de nomes do projecto (para os nomes antigos)
    ComputeHashes: Boolean;
  end;

// onde esta instalado o Delphi: a variavel BDS e, se nao existir, a instalacao mais recente do registo ('' se nenhuma)
function DetectDelphiRoot: string;
// os caminhos da biblioteca do IDE para uma plataforma ('Win64'), com $(BDS) e as outras variaveis expandidas
function DelphiLibraryPaths(const ADelphiRoot, APlatform: string): TArray<string>;
// SHA-256 do ficheiro em hexadecimal minusculo; '' se nao se consegue ler
function FileSha256(const AFileName: string): string;
// uma pasta esta dentro de outra (ou e a propria)?
function IsUnderFolder(const APath, AFolder: string): Boolean;
// preenche o ficheiro, o hash, a origem e a confianca dos componentes
procedure ResolveSbom(ASbom: TSbom; const AOptions: TSbomResolveOptions; const AProgress: TScanProgress = nil);

implementation

uses
  System.IOUtils, System.Hash, System.StrUtils, System.Win.Registry, Winapi.Windows;

{ indice de units }

type
  TUnitIndex = class
  private
    FPas: TDictionary<string, string>;
    FDcu: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddFolder(const ADir: string; ARecursive: Boolean);
    // o ficheiro da unit (ou '' ); AScopes: espacos de nomes a juntar a um nome sem ponto
    function Find(const AUnitName: string; const AScopes: TArray<string>): string;
  end;

constructor TUnitIndex.Create;
begin
  inherited;
  FPas := TDictionary<string, string>.Create;
  FDcu := TDictionary<string, string>.Create;
end;

destructor TUnitIndex.Destroy;
begin
  FDcu.Free;
  FPas.Free;
  inherited;
end;

procedure TUnitIndex.AddFolder(const ADir: string; ARecursive: Boolean);
var
  Option: TSearchOption;
  F, Key: string;
begin
  if (ADir = '') or not TDirectory.Exists(ADir) then
    Exit;
  if ARecursive then
    Option := TSearchOption.soAllDirectories
  else
    Option := TSearchOption.soTopDirectoryOnly;
  try
    for F in TDirectory.GetFiles(ADir, '*.pas', Option) do
    begin
      Key := LowerCase(TPath.GetFileNameWithoutExtension(F));
      FPas.TryAdd(Key, F);                    // a primeira que aparece ganha: segue a ordem de procura
    end;
    for F in TDirectory.GetFiles(ADir, '*.dcu', Option) do
    begin
      Key := LowerCase(TPath.GetFileNameWithoutExtension(F));
      FDcu.TryAdd(Key, F);
    end;
  except
    on Exception do ;                         // pasta sem acesso: segue-se
  end;
end;

function TUnitIndex.Find(const AUnitName: string; const AScopes: TArray<string>): string;
var
  Names: TList<string>;
  N, Scope: string;
begin
  Result := '';
  Names := TList<string>.Create;
  try
    Names.Add(LowerCase(AUnitName));
    if Pos('.', AUnitName) = 0 then
      for Scope in AScopes do
        Names.Add(LowerCase(Scope + '.' + AUnitName));
    for N in Names do
      if FPas.TryGetValue(N, Result) then
        Exit;
    for N in Names do
      if FDcu.TryGetValue(N, Result) then
        Exit;
    Result := '';
  finally
    Names.Free;
  end;
end;

{ ambiente do Delphi }

function DetectDelphiRoot: string;
var
  Reg: TRegistry;
  Versions: TStringList;
  I: Integer;
  Best: Double;
  V, Root: string;
  Fmt: TFormatSettings;
begin
  Result := GetEnvironmentVariable('BDS');
  if (Result <> '') and TDirectory.Exists(Result) then
    Exit(ExcludeTrailingPathDelimiter(Result));
  Result := '';
  Fmt := TFormatSettings.Invariant;
  Reg := TRegistry.Create(KEY_READ);
  Versions := TStringList.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS') then
      Exit;
    Reg.GetKeyNames(Versions);
    Reg.CloseKey;
    Best := -1;
    for I := 0 to Versions.Count - 1 do
    begin
      V := Versions[I];
      if not Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS\' + V) then
        Continue;
      try
        Root := Reg.ReadString('RootDir');
      finally
        Reg.CloseKey;
      end;
      if (Root <> '') and TDirectory.Exists(Root) and (StrToFloatDef(V, 0, Fmt) > Best) then
      begin
        Best := StrToFloatDef(V, 0, Fmt);
        Result := ExcludeTrailingPathDelimiter(Root);
      end;
    end;
  finally
    Versions.Free;
    Reg.Free;
  end;
end;

function ExpandIdeVars(const AText, ADelphiRoot, APlatform: string): string;
begin
  Result := AText.Replace('$(BDS)', ADelphiRoot, [rfReplaceAll, rfIgnoreCase])
    .Replace('$(BDSLIB)', ADelphiRoot + '\lib', [rfReplaceAll, rfIgnoreCase])
    .Replace('$(Platform)', APlatform, [rfReplaceAll, rfIgnoreCase])
    .Replace('$(BDSCOMMONDIR)', GetEnvironmentVariable('PUBLIC') + '\Documents\Embarcadero\Studio\' +
      ExtractFileName(ADelphiRoot), [rfReplaceAll, rfIgnoreCase]);
end;

function DelphiLibraryPaths(const ADelphiRoot, APlatform: string): TArray<string>;
var
  Reg: TRegistry;
  List: TList<string>;
  Seen: TDictionary<string, Boolean>;
  Name, Raw, Part, Dir: string;
begin
  List := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  Reg := TRegistry.Create(KEY_READ);
  try
    if ADelphiRoot <> '' then
    begin
      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly('\Software\Embarcadero\BDS\' + ExtractFileName(ADelphiRoot) + '\Library\' + APlatform) then
      try
        for Name in ['Search Path', 'Browsing Path'] do
        begin
          Raw := Reg.ReadString(Name);
          for Part in Raw.Split([';']) do
          begin
            Dir := Trim(ExpandIdeVars(Part, ADelphiRoot, APlatform));
            // as pastas lib\ do Delphi so tem DCU compilados da propria Embarcadero: nao interessam
            if (Dir <> '') and not Dir.Contains('$(') and not Dir.StartsWith(ADelphiRoot + '\lib', True) and
               Seen.TryAdd(LowerCase(Dir), True) then
              List.Add(Dir);
          end;
        end;
      finally
        Reg.CloseKey;
      end;
    end;
    Result := List.ToArray;
  finally
    Reg.Free;
    Seen.Free;
    List.Free;
  end;
end;

function FileSha256(const AFileName: string): string;
var
  Stream: TFileStream;
  Hash: THashSHA2;
  Buf: TBytes;
  Got: Integer;
begin
  Result := '';
  try
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      Hash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
      SetLength(Buf, 64 * 1024);
      repeat
        Got := Stream.Read(Buf[0], Length(Buf));
        if Got > 0 then
          Hash.Update(Buf, Got);
      until Got <= 0;
      Result := LowerCase(Hash.HashAsString);
    finally
      Stream.Free;
    end;
  except
    on Exception do
      Result := '';
  end;
end;

function IsUnderFolder(const APath, AFolder: string): Boolean;
var
  P, F: string;
begin
  if (APath = '') or (AFolder = '') then
    Exit(False);
  P := LowerCase(IncludeTrailingPathDelimiter(TPath.GetFullPath(APath)));
  F := LowerCase(IncludeTrailingPathDelimiter(TPath.GetFullPath(AFolder)));
  // APath pode ser um ficheiro: compara-se a pasta que o contem
  Result := P.StartsWith(F) or LowerCase(TPath.GetFullPath(APath)).StartsWith(F);
end;

{ resolucao }

function AbsolutePath(const APath, ABase: string): string;
begin
  if TPath.IsPathRooted(APath) then
    Result := APath
  else
    Result := TPath.Combine(ABase, APath);
  try
    Result := TPath.GetFullPath(Result);
  except
    on Exception do ;
  end;
end;

// de quem e um ficheiro que nao e do projecto: da Embarcadero (se esta dentro da instalacao) ou de terceiros
function OriginOfPath(const APath, AUnitName, AProjectDir, ADelphiRoot: string): TSbomOrigin;
var
  Lower: string;
begin
  if IsUnderFolder(APath, AProjectDir) then
    Exit(soProject);
  if IsUnderFolder(APath, ADelphiRoot) then
  begin
    Lower := LowerCase(APath);
    if SameText(Copy(AUnitName, 1, 4), 'Vcl.') or (Pos('\source\vcl\', Lower) > 0) then
      Exit(soVcl);
    if SameText(Copy(AUnitName, 1, 4), 'Fmx.') or (Pos('\source\fmx\', Lower) > 0) then
      Exit(soFmx);
    Exit(soRtl);
  end;
  Result := soThirdParty;
end;

procedure ResolveSbom(ASbom: TSbom; const AOptions: TSbomResolveOptions; const AProgress: TScanProgress);
var
  Index: TUnitIndex;
  C: TSbomComponent;
  Base, P, Found: string;
  Scopes: TArray<string>;
  I: Integer;
  Extra: TList<string>;
begin
  if ASbom = nil then
    Exit;
  Base := AOptions.ProjectDir;
  if Base = '' then
    Base := AOptions.ProjectRoot;
  Index := TUnitIndex.Create;
  Extra := TList<string>.Create;
  try
    if Assigned(AProgress) then
      AProgress('SBOM', 0, ASbom.Components.Count);
    // a ordem de procura: caminhos do .dproj, fontes do Delphi, biblioteca do IDE
    for P in AOptions.SearchPaths do
      Index.AddFolder(AbsolutePath(P, Base), False);
    if AOptions.DelphiRoot <> '' then
      Index.AddFolder(AOptions.DelphiRoot + '\source', True);
    for P in AOptions.LibraryPaths do
      Index.AddFolder(AbsolutePath(P, Base), False);
    // namespaces: os do projecto e os que o compilador junta por omissao
    for P in AOptions.Namespaces do
      Extra.Add(P);
    for P in ['System', 'System.Win', 'Winapi', 'Vcl', 'Fmx', 'FMX', 'Data', 'Data.Win', 'Xml', 'Xml.Win', 'Web',
              'Soap', 'Datasnap', 'REST', 'Net'] do
      if Extra.IndexOf(P) < 0 then
        Extra.Add(P);
    Scopes := Extra.ToArray;

    for I := 0 to ASbom.Components.Count - 1 do
    begin
      C := ASbom.Components[I];
      Found := '';
      if C.Origin = soProject then
      begin
        if C.RelPath <> '' then
        begin
          Found := TPath.Combine(AOptions.ProjectRoot, C.RelPath.Replace('/', '\'));
          if not TFile.Exists(Found) then
            Found := '';
        end;
      end
      else
        Found := Index.Find(C.Name, Scopes);
      if Found <> '' then
      begin
        C.Path := Found;
        C.Evidence := seFile;
        C.Confidence := scStrong;
        if C.Origin <> soProject then
          C.Origin := OriginOfPath(Found, C.Name, Base, AOptions.DelphiRoot);
        if AOptions.ComputeHashes then
          C.Hash := FileSha256(Found);
      end;
      if Assigned(AProgress) and ((I mod 25 = 0) or (I = ASbom.Components.Count - 1)) then
        AProgress('SBOM', I + 1, ASbom.Components.Count);
    end;
    ASbom.SortComponents;
  finally
    Extra.Free;
    Index.Free;
  end;
end;

end.
