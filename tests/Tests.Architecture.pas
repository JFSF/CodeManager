unit Tests.Architecture;

// Testes de arquitectura: garantem que as camadas de src\ so dependem do que podem.
//   Core            -> so Core, e nenhuma unit de UI/sistema (FMX.*, VCL.*, Winapi.*)
//   Infrastructure  -> Core, Infrastructure
//   Services        -> Core, Infrastructure, Services
//   UI              -> todas
// Le o texto dos .pas (clausulas "uses" de interface e implementation); nao compila nada.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  System.RegularExpressions, DUnitX.TestFramework;

type
  [TestFixture]
  TArchitectureTests = class
  private
    FSrc: string;
    FLayerOf: TDictionary<string, string>;   // unit (minusculas) -> camada
    function FindSrcDir: string;
    function LayerAllows(const AFrom, ATo: string): Boolean;
    function UsedUnits(const AFile: string): TArray<string>;
    function Violations(const ALayer: string; AExternalCheck: Boolean): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SourceTreeWasFound;
    [Test] procedure EveryUnitLivesInAKnownLayerFolder;
    [Test] procedure CoreDoesNotDependOnOtherLayers;
    [Test] procedure CoreDoesNotUseUiOrSystemUnits;
    [Test] procedure InfrastructureOnlyDependsOnCoreAndItself;
    [Test] procedure ServicesDoNotDependOnUi;
  end;

implementation

const
  LAYERS: array[0..3] of string = ('Core', 'Infrastructure', 'Services', 'UI');

function StripComments(const AText: string): string;
begin
  Result := TRegEx.Replace(AText, '\(\*.*?\*\)', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '\{.*?\}', ' ', [roSingleLine]);
  Result := TRegEx.Replace(Result, '//[^\r\n]*', ' ');
  Result := TRegEx.Replace(Result, '''[^''\r\n]*''', '''''');
end;

procedure TArchitectureTests.Setup;
var
  Layer, F: string;
begin
  FSrc := FindSrcDir;
  FLayerOf := TDictionary<string, string>.Create;
  if FSrc = '' then
    Exit;
  for Layer in LAYERS do
    if TDirectory.Exists(TPath.Combine(FSrc, Layer)) then
      for F in TDirectory.GetFiles(TPath.Combine(FSrc, Layer), '*.pas', TSearchOption.soAllDirectories) do
        FLayerOf.AddOrSetValue(LowerCase(TPath.GetFileNameWithoutExtension(F)), Layer);
end;

procedure TArchitectureTests.TearDown;
begin
  FLayerOf.Free;
end;

function TArchitectureTests.FindSrcDir: string;
var
  Dir, Cand: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  while Dir <> '' do
  begin
    Cand := TPath.Combine(Dir, 'src');
    if TDirectory.Exists(TPath.Combine(Cand, 'Core')) then
      Exit(Cand);
    if TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir)) = Dir then
      Break;
    Dir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir));
  end;
  Result := '';
end;

function TArchitectureTests.LayerAllows(const AFrom, ATo: string): Boolean;
begin
  if SameText(AFrom, 'UI') then
    Result := True
  else if SameText(AFrom, 'Services') then
    Result := not SameText(ATo, 'UI')
  else if SameText(AFrom, 'Infrastructure') then
    Result := SameText(ATo, 'Core') or SameText(ATo, 'Infrastructure')
  else
    Result := SameText(ATo, 'Core');
end;

function TArchitectureTests.UsedUnits(const AFile: string): TArray<string>;
var
  Text, Item: string;
  M: TMatch;
  List: TList<string>;
begin
  Text := StripComments(TFile.ReadAllText(AFile));
  List := TList<string>.Create;
  try
    for M in TRegEx.Matches(Text, '\buses\b(.*?);', [roIgnoreCase, roSingleLine]) do
      for Item in M.Groups[1].Value.Split([',']) do
        // "Nome in 'caminho'" -> "Nome"
        List.Add(TRegEx.Replace(Item, '\s+in\s+''.*$', '', [roIgnoreCase, roSingleLine]).Trim);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// Devolve uma linha por violacao ("Unit -> Dependencia"); vazio se esta tudo bem.
// AExternalCheck=True verifica unidades de UI/sistema em vez de dependencias entre camadas.
function TArchitectureTests.Violations(const ALayer: string; AExternalCheck: Boolean): string;
var
  F, U, TargetLayer: string;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for F in TDirectory.GetFiles(TPath.Combine(FSrc, ALayer), '*.pas', TSearchOption.soAllDirectories) do
      for U in UsedUnits(F) do
        if AExternalCheck then
        begin
          if U.StartsWith('FMX.', True) or U.StartsWith('Vcl.', True) or U.StartsWith('Winapi.', True) then
            SB.AppendLine(TPath.GetFileNameWithoutExtension(F) + ' -> ' + U);
        end
        else if FLayerOf.TryGetValue(LowerCase(U), TargetLayer) and not LayerAllows(ALayer, TargetLayer) then
          SB.AppendLine(TPath.GetFileNameWithoutExtension(F) + ' (' + ALayer + ') -> ' + U + ' (' + TargetLayer + ')');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TArchitectureTests.SourceTreeWasFound;
begin
  Assert.AreNotEqual('', FSrc, 'Pasta src\ (com a subpasta Core) nao encontrada a partir do executavel');
  Assert.IsTrue(FLayerOf.Count > 0, 'Nenhuma unit encontrada nas pastas das camadas');
end;

procedure TArchitectureTests.EveryUnitLivesInAKnownLayerFolder;
var
  F: string;
  Stray: TStringBuilder;
begin
  Assert.AreNotEqual('', FSrc);
  Stray := TStringBuilder.Create;
  try
    // Qualquer .pas directamente em src\ (ou em pastas que nao sao camadas) escapa as regras.
    for F in TDirectory.GetFiles(FSrc, '*.pas', TSearchOption.soAllDirectories) do
      if not FLayerOf.ContainsKey(LowerCase(TPath.GetFileNameWithoutExtension(F))) then
        Stray.AppendLine(F);
    Assert.AreEqual('', Stray.ToString, 'Units fora das pastas Core/Infrastructure/Services/UI:');
  finally
    Stray.Free;
  end;
end;

procedure TArchitectureTests.CoreDoesNotDependOnOtherLayers;
begin
  Assert.AreNotEqual('', FSrc);
  Assert.AreEqual('', Violations('Core', False), 'Core importa outras camadas:');
end;

procedure TArchitectureTests.CoreDoesNotUseUiOrSystemUnits;
begin
  Assert.AreNotEqual('', FSrc);
  Assert.AreEqual('', Violations('Core', True), 'Core usa FMX/Vcl/Winapi:');
end;

procedure TArchitectureTests.InfrastructureOnlyDependsOnCoreAndItself;
begin
  Assert.AreNotEqual('', FSrc);
  Assert.AreEqual('', Violations('Infrastructure', False), 'Infrastructure importa Services ou UI:');
end;

procedure TArchitectureTests.ServicesDoNotDependOnUi;
begin
  Assert.AreNotEqual('', FSrc);
  Assert.AreEqual('', Violations('Services', False), 'Services importa UI:');
end;

end.
