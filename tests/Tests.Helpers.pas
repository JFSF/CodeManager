unit Tests.Helpers;

// Apoio aos testes: pastas temporarias, escrita de units de exemplo e formatacao dos resultados.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows, CM.Analyzer;

type
  // pasta temporaria que se apaga sozinha (com todo o conteudo)
  TTempDir = class
  private
    FPath: string;
  public
    constructor Create;
    destructor Destroy; override;
    // escreve um ficheiro (caminho relativo com '/'; cria as pastas) e devolve o caminho completo
    function Write(const ARelPath, AText: string): string;
    procedure Delete(const ARelPath: string);
    function Full(const ARelPath: string): string;
    property Path: string read FPath;
  end;

  // isola CM.Store.AppDataDir (e por isso settings.json / progress-*.json) numa pasta temporaria,
  // via a variavel CODEMANAGER_DATA (so tem efeito em builds Debug); repoe o valor anterior ao
  // libertar. Sem isto os testes leriam/escreveriam a pasta real do utilizador.
  TIsolatedAppData = class
  private
    FDir: TTempDir;
    FHadPrev: Boolean;
    FPrev: string;
    function GetPath: string;
  public
    constructor Create;
    destructor Destroy; override;
    property Path: string read GetPath;
  end;

// analisa um texto Delphi (grava-o num ficheiro temporario)
function Extract(const ASource: string): TArray<TMethodInfo>;
// 'TFoo.Bar|TFoo.Baz(Integer)'
function NamesOf(const AMethods: TArray<TMethodInfo>): string;
function SigsOf(const AMethods: TArray<TMethodInfo>): string;
function UnitPaths(AScan: TProjectScan): string;
function Join(const AItems: TArray<string>): string;
// unit com interface/implementation vazias, para embrulhar declaracoes de teste
function WrapUnit(const AInterface: string; const AImplementation: string = ''): string;

// constroi um TMethodInfo sem passar por ficheiros/regex (para testar CM.Stats e CM.Store
// isoladamente); ASimple = AName quando omitido
function Meth(const AName: string; const AOwner: string = ''; ASimple: string = ''): TMethodInfo;
// constroi uma TUnitInfo com os metodos dados (Dir/FileName derivados de APath com '/')
function MakeUnitInfo(const APath, ALayer: string; const AMethods: TArray<TMethodInfo>): TUnitInfo;
// TProjectScan com as units dadas (a lista fica dona delas) e Folders/TotalMethods/UnitsWithMethods
// recalculados a partir delas
function NewScan(const AFolders: Integer; const AUnits: array of TUnitInfo): TProjectScan;

implementation

{ TIsolatedAppData }

constructor TIsolatedAppData.Create;
begin
  inherited Create;
  FPrev := GetEnvironmentVariable('CODEMANAGER_DATA');
  FHadPrev := FPrev <> '';
  FDir := TTempDir.Create;
  Winapi.Windows.SetEnvironmentVariable('CODEMANAGER_DATA', PWideChar(FDir.Path));
end;

destructor TIsolatedAppData.Destroy;
begin
  if FHadPrev then
    Winapi.Windows.SetEnvironmentVariable('CODEMANAGER_DATA', PWideChar(FPrev))
  else
    Winapi.Windows.SetEnvironmentVariable('CODEMANAGER_DATA', nil);
  FDir.Free;
  inherited;
end;

function TIsolatedAppData.GetPath: string;
begin
  Result := FDir.Path;
end;

{ TTempDir }

constructor TTempDir.Create;
begin
  inherited;
  FPath := TPath.Combine(TPath.GetTempPath, 'cm-tests-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FPath);
end;

destructor TTempDir.Destroy;
begin
  try
    if TDirectory.Exists(FPath) then
      TDirectory.Delete(FPath, True);
  except
    on Exception do ;
  end;
  inherited;
end;

function TTempDir.Full(const ARelPath: string): string;
begin
  Result := TPath.Combine(FPath, ARelPath.Replace('/', PathDelim));
end;

function TTempDir.Write(const ARelPath, AText: string): string;
begin
  Result := Full(ARelPath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(Result));
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

procedure TTempDir.Delete(const ARelPath: string);
begin
  TFile.Delete(Full(ARelPath));
end;

function Extract(const ASource: string): TArray<TMethodInfo>;
var
  Dir: TTempDir;
begin
  Dir := TTempDir.Create;
  try
    Result := ExtractMethods(Dir.Write('Unit1.pas', ASource));
  finally
    Dir.Free;
  end;
end;

function Join(const AItems: TArray<string>): string;
begin
  Result := string.Join('|', AItems);
end;

function NamesOf(const AMethods: TArray<TMethodInfo>): string;
var
  I: Integer;
  Items: TArray<string>;
begin
  SetLength(Items, Length(AMethods));
  for I := 0 to High(AMethods) do
    Items[I] := AMethods[I].Name;
  Result := Join(Items);
end;

function SigsOf(const AMethods: TArray<TMethodInfo>): string;
var
  I: Integer;
  Items: TArray<string>;
begin
  SetLength(Items, Length(AMethods));
  for I := 0 to High(AMethods) do
    Items[I] := AMethods[I].Sig;
  Result := Join(Items);
end;

function UnitPaths(AScan: TProjectScan): string;
var
  I: Integer;
  Items: TArray<string>;
begin
  SetLength(Items, AScan.Units.Count);
  for I := 0 to AScan.Units.Count - 1 do
    Items[I] := AScan.Units[I].Path;
  Result := Join(Items);
end;

function WrapUnit(const AInterface, AImplementation: string): string;
begin
  Result := 'unit Unit1;' + sLineBreak + 'interface' + sLineBreak + AInterface + sLineBreak +
    'implementation' + sLineBreak + AImplementation + sLineBreak + 'end.' + sLineBreak;
end;

function Meth(const AName, AOwner: string; ASimple: string): TMethodInfo;
begin
  if ASimple = '' then
    ASimple := AName;
  Result.Name := AName;
  Result.Owner := AOwner;
  Result.Simple := ASimple;
  Result.Kind := 'procedure';
  Result.Sig := 'procedure ' + AName + ';';
end;

function MakeUnitInfo(const APath, ALayer: string; const AMethods: TArray<TMethodInfo>): TUnitInfo;
var
  P: Integer;
begin
  Result := TUnitInfo.Create;
  Result.Path := APath;
  P := APath.LastIndexOf('/');
  if P < 0 then
  begin
    Result.Dir := '';
    Result.FileName := APath;
  end
  else
  begin
    Result.Dir := Copy(APath, 1, P);
    Result.FileName := Copy(APath, P + 2, MaxInt);
  end;
  Result.Layer := ALayer;
  Result.Methods := AMethods;
end;

function NewScan(const AFolders: Integer; const AUnits: array of TUnitInfo): TProjectScan;
var
  U: TUnitInfo;
begin
  Result := TProjectScan.Create;
  Result.Folders := AFolders;
  for U in AUnits do
  begin
    Result.Units.Add(U);
    Inc(Result.TotalMethods, Length(U.Methods));
    if Length(U.Methods) > 0 then
      Inc(Result.UnitsWithMethods);
  end;
end;

end.
