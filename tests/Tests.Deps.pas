unit Tests.Deps;
// Testes das dependencias entre units: leitura dos "uses", grafo, ciclos, colunas e carregamento de disco.

interface

uses
  System.SysUtils, System.IOUtils, DUnitX.TestFramework, CM.Analyzer, CM.Deps;

type
  [TestFixture]
  TDepsTests = class
  private
    function Inp(const AName, ALayer: string; const AIface, AImpl: array of string;
      AIsProgram: Boolean = False): TDepInput;
  public
    [Test] procedure ReadsInterfaceAndImplementationUses;
    [Test] procedure ReadsProgramUses;
    [Test] procedure IgnoresCommentsDirectivesAndPaths;
    [Test] procedure UnitNameComesFromTheHeader;
    [Test] procedure BuildsEdgesAndSeparatesExternalUnits;
    [Test] procedure CountsFanInFanOutAndInstability;
    [Test] procedure InterfaceDependenciesWinOverImplementationOnes;
    [Test] procedure FindsCycles;
    [Test] procedure ACycleNeverBreaksTheColumns;
    [Test] procedure ColumnsFollowTheLongestPath;
    [Test] procedure RowsAreUniqueWithinAColumn;
    [Test] procedure ListsUnusedUnitsButNotPrograms;
    [Test] procedure SummarisesLinksBetweenLayers;
    [Test] procedure ReachFollowsDependenciesTransitively;
    [Test] procedure NameLookupIgnoresCase;
    [Test] procedure LoadsTheGraphFromDisk;
  end;

implementation

function TDepsTests.Inp(const AName, ALayer: string; const AIface, AImpl: array of string;
  AIsProgram: Boolean): TDepInput;
var
  I: Integer;
begin
  Result := Default(TDepInput);
  Result.Name := AName;
  Result.Path := ALayer + '/' + AName + '.pas';
  Result.Layer := ALayer;
  Result.IsProgram := AIsProgram;
  SetLength(Result.InterfaceUses, Length(AIface));
  for I := 0 to High(AIface) do
    Result.InterfaceUses[I] := AIface[I];
  SetLength(Result.ImplUses, Length(AImpl));
  for I := 0 to High(AImpl) do
    Result.ImplUses[I] := AImpl[I];
end;

procedure TDepsTests.ReadsInterfaceAndImplementationUses;
var
  Info: TUsesInfo;
begin
  ExtractUsesText('unit Foo.Bar;' + sLineBreak + 'interface' + sLineBreak +
    'uses System.SysUtils, Core.One;' + sLineBreak + 'type TX = class end;' + sLineBreak +
    'implementation' + sLineBreak + 'uses' + sLineBreak + '  Core.Two,' + sLineBreak + '  System.Classes;' +
    sLineBreak + 'end.', Info);
  Assert.AreEqual('Foo.Bar', Info.UnitName);
  Assert.AreEqual<Integer>(2, Length(Info.InterfaceUses));
  Assert.AreEqual('System.SysUtils', Info.InterfaceUses[0]);
  Assert.AreEqual('Core.One', Info.InterfaceUses[1]);
  Assert.AreEqual<Integer>(2, Length(Info.ImplUses));
  Assert.AreEqual('Core.Two', Info.ImplUses[0]);
  Assert.AreEqual('System.Classes', Info.ImplUses[1]);
end;

procedure TDepsTests.ReadsProgramUses;
var
  Info: TUsesInfo;
begin
  ExtractUsesText('program App;' + sLineBreak + 'uses' + sLineBreak + '  Forms,' + sLineBreak +
    '  Main in ''src\Main.pas'';' + sLineBreak + 'begin end.', Info);
  Assert.AreEqual('App', Info.UnitName);
  Assert.AreEqual<Integer>(2, Length(Info.InterfaceUses));
  Assert.AreEqual('Forms', Info.InterfaceUses[0]);
  Assert.AreEqual('Main', Info.InterfaceUses[1]);
  Assert.AreEqual<Integer>(0, Length(Info.ImplUses));
end;

procedure TDepsTests.IgnoresCommentsDirectivesAndPaths;
var
  Info: TUsesInfo;
begin
  ExtractUsesText('unit A;' + sLineBreak + 'interface' + sLineBreak +
    'uses // Old,' + sLineBreak + '  {$IFDEF X} One, {$ENDIF}' + sLineBreak + '  (* Gone *) Two in ''two.pas'',' +
    sLineBreak + '  Three, three;' + sLineBreak + 'implementation' + sLineBreak + 'end.', Info);
  Assert.AreEqual<Integer>(3, Length(Info.InterfaceUses), 'sem repeticoes e sem o que esta comentado');
  Assert.AreEqual('One', Info.InterfaceUses[0]);
  Assert.AreEqual('Two', Info.InterfaceUses[1]);
  Assert.AreEqual('Three', Info.InterfaceUses[2]);
end;

procedure TDepsTests.UnitNameComesFromTheHeader;
var
  Info: TUsesInfo;
begin
  ExtractUsesText('{ unit Falsa; }' + sLineBreak + 'unit Real.Name;' + sLineBreak + 'interface' + sLineBreak +
    'implementation' + sLineBreak + 'end.', Info);
  Assert.AreEqual('Real.Name', Info.UnitName);
  ExtractUsesText('texto sem cabecalho', Info);
  Assert.AreEqual('', Info.UnitName);
end;

procedure TDepsTests.BuildsEdgesAndSeparatesExternalUnits;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([
    Inp('Main', 'UI', ['Core', 'FMX.Forms'], ['Util']),
    Inp('Core', 'Core', ['System.SysUtils'], []),
    Inp('Util', 'Core', [], ['Core'])]);
  try
    Assert.AreEqual<Integer>(3, G.Nodes.Count);
    Assert.AreEqual<Integer>(3, G.Edges.Count);
    Assert.AreEqual<Integer>(2, Length(G.Find('Main').Deps));
    Assert.AreEqual<Integer>(2, Length(G.Find('Main').External + G.Find('Core').External), 'FMX.Forms e System.SysUtils');
    Assert.AreEqual('FMX.Forms', G.Find('Main').External[0]);
    Assert.AreEqual(2, G.ExternalCount);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.CountsFanInFanOutAndInstability;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([
    Inp('A', 'X', ['C'], ['B']),
    Inp('B', 'X', ['C'], []),
    Inp('C', 'X', [], [])]);
  try
    Assert.AreEqual(2, G.Find('A').FanOut);
    Assert.AreEqual(0, G.Find('A').FanIn);
    Assert.AreEqual(2, G.Find('C').FanIn);
    Assert.AreEqual(0, G.Find('C').FanOut);
    Assert.AreEqual(1.0, G.Find('A').Instability, 0.001);
    Assert.AreEqual(0.0, G.Find('C').Instability, 0.001);
    Assert.AreEqual(0.5, G.Find('B').Instability, 0.001);
    Assert.AreEqual('C', G.TopFanIn(1)[0].Name);
    Assert.AreEqual('A', G.TopFanOut(1)[0].Name);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.InterfaceDependenciesWinOverImplementationOnes;
var
  G: TDepGraph;
  I: Integer;
begin
  G := BuildDepGraph([
    Inp('A', 'X', ['B'], ['B', 'C']),
    Inp('B', 'X', [], []),
    Inp('C', 'X', [], [])]);
  try
    Assert.AreEqual<Integer>(2, G.Edges.Count, 'B conta uma so vez');
    for I := 0 to G.Edges.Count - 1 do
      if G.Nodes[G.Edges[I].Target].Name = 'B' then
        Assert.IsTrue(G.Edges[I].InInterface)
      else
        Assert.IsFalse(G.Edges[I].InInterface);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.FindsCycles;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([
    Inp('A', 'X', ['B'], []),
    Inp('B', 'X', [], ['C']),
    Inp('C', 'X', [], ['A']),
    Inp('D', 'X', ['A'], [])]);
  try
    Assert.AreEqual<Integer>(1, Length(G.Cycles));
    Assert.AreEqual<Integer>(3, Length(G.Cycles[0]));
    Assert.AreEqual(0, G.Find('A').Cycle);
    Assert.AreEqual(0, G.Find('C').Cycle);
    Assert.AreEqual(-1, G.Find('D').Cycle);
  finally
    G.Free;
  end;
  G := BuildDepGraph([Inp('A', 'X', ['B'], []), Inp('B', 'X', [], [])]);
  try
    Assert.AreEqual<Integer>(0, Length(G.Cycles));
  finally
    G.Free;
  end;
end;

procedure TDepsTests.ACycleNeverBreaksTheColumns;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([
    Inp('Top', 'X', ['A'], []),
    Inp('A', 'X', ['B'], []),
    Inp('B', 'X', ['A', 'Leaf'], []),
    Inp('Leaf', 'X', [], [])]);
  try
    Assert.AreEqual(G.Find('A').Level, G.Find('B').Level, 'as units de um ciclo ficam na mesma coluna');
    Assert.IsTrue(G.Find('Top').Level < G.Find('A').Level);
    Assert.IsTrue(G.Find('A').Level < G.Find('Leaf').Level);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.ColumnsFollowTheLongestPath;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([
    Inp('Prog', 'X', ['A', 'C'], [], True),
    Inp('A', 'X', ['B'], []),
    Inp('B', 'X', ['C'], []),
    Inp('C', 'X', [], [])]);
  try
    Assert.AreEqual(0, G.Find('Prog').Level);
    Assert.AreEqual(1, G.Find('A').Level);
    Assert.AreEqual(2, G.Find('B').Level);
    Assert.AreEqual(3, G.Find('C').Level, 'C fica depois de B mesmo sendo usada directamente pelo programa');
    Assert.AreEqual(4, G.LevelCount);
    Assert.AreEqual(1, G.ColumnSize(2));
  finally
    G.Free;
  end;
end;

procedure TDepsTests.RowsAreUniqueWithinAColumn;
var
  G: TDepGraph;
  I, J: Integer;
begin
  G := BuildDepGraph([
    Inp('Prog', 'X', ['A', 'B', 'C', 'D'], [], True),
    Inp('A', 'X', ['Z'], []), Inp('B', 'X', ['Z'], []), Inp('C', 'X', [], []), Inp('D', 'X', [], []),
    Inp('Z', 'X', [], [])]);
  try
    for I := 0 to G.Nodes.Count - 1 do
      for J := I + 1 to G.Nodes.Count - 1 do
        if G.Nodes[I].Level = G.Nodes[J].Level then
          Assert.AreNotEqual(G.Nodes[I].Row, G.Nodes[J].Row, G.Nodes[I].Name + ' / ' + G.Nodes[J].Name);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.ListsUnusedUnitsButNotPrograms;
var
  G: TDepGraph;
  U: TArray<TDepNode>;
begin
  G := BuildDepGraph([
    Inp('Prog', 'X', ['A'], [], True),
    Inp('A', 'X', [], []),
    Inp('Orphan', 'X', [], [])]);
  try
    U := G.Unused;
    Assert.AreEqual<Integer>(1, Length(U));
    Assert.AreEqual('Orphan', U[0].Name);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.SummarisesLinksBetweenLayers;
var
  G: TDepGraph;
  L: TArray<TLayerLink>;
begin
  G := BuildDepGraph([
    Inp('U1', 'UI', ['C1', 'C2'], []),
    Inp('U2', 'UI', ['C1'], []),
    Inp('C1', 'Core', [], []),
    Inp('C2', 'Core', ['C1'], [])]);
  try
    L := G.LayerLinks;
    Assert.AreEqual<Integer>(1, Length(L), 'C2 -> C1 e dentro da mesma camada: nao conta');
    Assert.AreEqual('UI', L[0].FromLayer);
    Assert.AreEqual('Core', L[0].ToLayer);
    Assert.AreEqual(3, L[0].Count);
  finally
    G.Free;
  end;
end;

procedure TDepsTests.ReachFollowsDependenciesTransitively;
var
  G: TDepGraph;
  R: TArray<Integer>;
begin
  G := BuildDepGraph([
    Inp('A', 'X', ['B'], []),
    Inp('B', 'X', ['C'], []),
    Inp('C', 'X', ['A'], []),
    Inp('D', 'X', [], [])]);
  try
    R := G.Reach(0);
    Assert.AreEqual<Integer>(2, Length(R), 'A chega a B e a C, nao a si propria nem a D');
    Assert.AreEqual<Integer>(0, Length(G.Reach(3)));
  finally
    G.Free;
  end;
end;

procedure TDepsTests.NameLookupIgnoresCase;
var
  G: TDepGraph;
begin
  G := BuildDepGraph([Inp('CM.Core', 'X', [], []), Inp('Main', 'X', ['cm.core'], [])]);
  try
    Assert.IsNotNull(G.Find('CM.CORE'));
    Assert.AreEqual<Integer>(1, Length(G.Find('Main').Deps));
    Assert.IsNull(G.Find('Nada'));
  finally
    G.Free;
  end;
end;

procedure TDepsTests.LoadsTheGraphFromDisk;
var
  Dir: string;
  Scan: TProjectScan;
  G: TDepGraph;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'cm-deps-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(TPath.Combine(Dir, 'Core'));
  TDirectory.CreateDirectory(TPath.Combine(Dir, 'UI'));
  try
    TFile.WriteAllText(TPath.Combine(Dir, 'Core\Base.pas'),
      'unit Base;' + sLineBreak + 'interface' + sLineBreak + 'uses System.SysUtils;' + sLineBreak +
      'procedure Hello;' + sLineBreak + 'implementation' + sLineBreak + 'procedure Hello; begin end;' +
      sLineBreak + 'end.', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir, 'UI\Screen.pas'),
      'unit Screen;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'uses Base;' +
      sLineBreak + 'end.', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir, 'App.dpr'),
      'program App;' + sLineBreak + 'uses Screen, Base in ''Core\Base.pas'';' + sLineBreak + 'begin end.',
      TEncoding.UTF8);
    Scan := ScanProject(Dir, nil);
    try
      G := LoadDepGraph(Scan);
      try
        Assert.AreEqual<Integer>(3, G.Nodes.Count);
        Assert.IsNotNull(G.Find('Base'));
        Assert.AreEqual(2, G.Find('Base').FanIn, 'o programa e o ecra usam-na');
        Assert.AreEqual(1, G.Find('Screen').FanIn);
        Assert.IsTrue(G.Find('App').IsProgram);
        Assert.AreEqual('Core', G.Find('Base').Layer);
        Assert.AreEqual(1, G.Find('Base').Methods);
        Assert.AreEqual('System.SysUtils', G.Find('Base').External[0]);
        Assert.AreEqual<Integer>(0, Length(G.Cycles));
      finally
        G.Free;
      end;
    finally
      Scan.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDepsTests);

end.
