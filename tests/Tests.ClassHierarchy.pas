unit Tests.ClassHierarchy;

// Testes da hierarquia de classes e da profundidade de heranca (CM.ClassHierarchy).

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Analyzer, CM.Classes, CM.ClassHierarchy, CM.Metrics, Tests.Helpers;

type
  [TestFixture]
  TClassHierarchyTests = class
  private
    FHier: THierarchy;
    FScan: TProjectScan;
    // monta o projecto: cada texto e o codigo (limpo) de uma unit; o caminho vem de 'u1.pas', 'u2.pas'...
    procedure Build(const ASources: array of string);
    function Node(const AName: string): TClassNode;
  public
    [TearDown] procedure TearDown;
    [Test] procedure ClassWithoutAncestorHasDepthOne;
    [Test] procedure ChainsInsideTheProjectAddLevels;
    [Test] procedure KnownExternalAncestorsGiveAnExactDepth;
    [Test] procedure UnknownExternalAncestorsGiveAMinimum;
    [Test] procedure TheInexactnessPassesToTheDescendants;
    [Test] procedure QualifiedAncestorsAreFoundInTheProject;
    [Test] procedure TheAncestorOfTheSameUnitIsPreferred;
    [Test] procedure ChildrenAndDescendantsAreCounted;
    [Test] procedure InterfacesFormTheirOwnHierarchy;
    [Test] procedure AClassNeverInheritsFromAnInterfaceOfTheProject;
    [Test] procedure CyclesDoNotHang;
    [Test] procedure ARecordIsCountedButNotListed;
    [Test] procedure MethodsAreCountedPerClass;
    [Test] procedure StatisticsAndHistogram;
    [Test] procedure DeepestAndMostChildrenAreSorted;
    [Test] procedure TreeOrderPutsChildrenUnderTheirParent;
    [Test] procedure ChainListsTheAncestors;
    [Test] procedure DepthLevelsUseTheirLimits;
    [Test] procedure KnownDepthIgnoresCaseAndQualification;
    [Test] procedure FmxOnlyClassesAreKnownButTControlIsNot;
    [Test] procedure NilScanIsEmpty;
    [Test] procedure FindIgnoresQualificationAndCase;
    [Test] procedure UnitLayerAndLineAreKept;
  end;

implementation

procedure TClassHierarchyTests.TearDown;
begin
  FHier.Free;
  FScan.Free;
  FHier := nil;
  FScan := nil;
end;

procedure TClassHierarchyTests.Build(const ASources: array of string);
var
  Units: array of TUnitInfo;
  I: Integer;
begin
  SetLength(Units, Length(ASources));
  for I := 0 to High(ASources) do
  begin
    Units[I] := MakeUnitInfo(Format('Core/u%d.pas', [I + 1]), 'Core', [Meth('TA.One', 'TA', 'One'), Meth('TA.Two', 'TA', 'Two'),
      Meth('TB.Run', 'TB', 'Run')]);
    Units[I].Classes := ExtractClasses(ASources[I]);
  end;
  FScan := NewScan(1, Units);
  FHier := BuildHierarchy(FScan);
end;

function TClassHierarchyTests.Node(const AName: string): TClassNode;
begin
  Result := FHier.Find(AName);
  Assert.IsNotNull(Result, 'classe nao encontrada: ' + AName);
end;

procedure TClassHierarchyTests.ClassWithoutAncestorHasDepthOne;
begin
  Build(['type TA = class end;']);
  Assert.AreEqual(1, Node('TA').Depth);
  Assert.IsTrue(Node('TA').Exact);
  Assert.IsNull(Node('TA').Parent);
  Assert.AreEqual('', Node('TA').ExternalBase);
end;

procedure TClassHierarchyTests.ChainsInsideTheProjectAddLevels;
begin
  Build(['type TA = class end; TB = class(TA) end; TC = class(TB) end;']);
  Assert.AreEqual(1, Node('TA').Depth);
  Assert.AreEqual(2, Node('TB').Depth);
  Assert.AreEqual(3, Node('TC').Depth);
  Assert.AreEqual(3, Node('TC').ProjectDepth);
  Assert.IsTrue(Node('TC').Parent = Node('TB'));
  Assert.IsTrue(Node('TC').Exact);
end;

procedure TClassHierarchyTests.KnownExternalAncestorsGiveAnExactDepth;
begin
  Build(['type TObj = class(TObject) end; TComp = class(TComponent) end; TList2 = class(TStringList) end;']);
  Assert.AreEqual(1, Node('TObj').Depth, 'TObject esta a 0');
  Assert.AreEqual(3, Node('TComp').Depth, 'TObject > TPersistent > TComponent > TComp');
  Assert.AreEqual(4, Node('TList2').Depth, 'TObject > TPersistent > TStrings > TStringList > TList2');
  Assert.IsTrue(Node('TComp').Exact);
  Assert.AreEqual('TComponent', Node('TComp').ExternalBase);
  Assert.AreEqual(1, Node('TComp').ProjectDepth);
end;

procedure TClassHierarchyTests.UnknownExternalAncestorsGiveAMinimum;
begin
  Build(['type TFoo = class(TFancyThing) end;']);
  Assert.AreEqual(2, Node('TFoo').Depth, 'pelo menos TObject > TFancyThing > TFoo');
  Assert.IsFalse(Node('TFoo').Exact);
  Assert.AreEqual('TFancyThing', Node('TFoo').ExternalBase);
end;

procedure TClassHierarchyTests.TheInexactnessPassesToTheDescendants;
begin
  Build(['type TFoo = class(TFancyThing) end; TBar = class(TFoo) end; TBaz = class(TBar) end;']);
  Assert.AreEqual(4, Node('TBaz').Depth);
  Assert.IsFalse(Node('TBaz').Exact);
  Assert.AreEqual(3, Node('TBaz').ProjectDepth);
end;

procedure TClassHierarchyTests.QualifiedAncestorsAreFoundInTheProject;
begin
  Build(['type TBase = class end;', 'type TKid = class(Core.u1.TBase) end;']);
  Assert.IsTrue(Node('TKid').Parent = Node('TBase'));
  Assert.AreEqual(2, Node('TKid').Depth);
end;

procedure TClassHierarchyTests.TheAncestorOfTheSameUnitIsPreferred;
var
  Kid: TClassNode;
  N: TClassNode;
begin
  Build(['type TBase = class end;', 'type TBase = class(TComponent) end; TKid = class(TBase) end;']);
  Kid := Node('TKid');
  Assert.AreEqual('Core/u2.pas', Kid.Parent.UnitPath, 'a TBase da mesma unit, nao a da primeira');
  Assert.AreEqual(4, Kid.Depth);
  Assert.AreEqual<NativeInt>(3, FHier.Nodes.Count);
  N := FHier.Nodes[0];
  Assert.AreEqual(0, N.Children, 'a TBase da unit 1 nao tem filhas');
end;

procedure TClassHierarchyTests.ChildrenAndDescendantsAreCounted;
begin
  Build(['type TA = class end; TB = class(TA) end; TC = class(TA) end; TD = class(TB) end; TE = class(TD) end;']);
  Assert.AreEqual(2, Node('TA').Children);
  Assert.AreEqual(4, Node('TA').Descendants);
  Assert.AreEqual(1, Node('TB').Children);
  Assert.AreEqual(2, Node('TB').Descendants);
  Assert.AreEqual(0, Node('TC').Children);
  Assert.AreEqual(0, Node('TE').Descendants);
end;

procedure TClassHierarchyTests.InterfacesFormTheirOwnHierarchy;
begin
  Build(['type IBase = interface end; IKid = interface(IBase) end; ILeaf = interface(IKid) end; IExt = interface(IEnumerable) end;']);
  Assert.AreEqual(1, Node('IBase').Depth);
  Assert.AreEqual(2, Node('IKid').Depth);
  Assert.AreEqual(3, Node('ILeaf').Depth);
  Assert.AreEqual(Ord(ckInterface), Ord(Node('ILeaf').Kind));
  Assert.IsFalse(Node('IExt').Exact);
  Assert.AreEqual(1, FHier.Count(ckInterface) - 3, 'quatro interfaces');
end;

procedure TClassHierarchyTests.AClassNeverInheritsFromAnInterfaceOfTheProject;
begin
  // um nome igual de outro tipo (aqui uma interface) nao e o ancestral de uma classe
  Build(['type TFoo = interface end; TFoo2 = class(TFoo) end;']);
  Assert.IsNull(Node('TFoo2').Parent);
  Assert.AreEqual('TFoo', Node('TFoo2').ExternalBase);
end;

procedure TClassHierarchyTests.CyclesDoNotHang;
begin
  Build(['type TA = class(TB) end; TB = class(TA) end; TC = class(TC) end;']);
  Assert.AreEqual<NativeInt>(3, FHier.Nodes.Count);
  Assert.IsFalse(Node('TA').Exact);
  Assert.IsTrue(Node('TA').Depth >= 1);
  Assert.IsNull(Node('TC').Parent, 'uma classe nao herda de si propria');
end;

procedure TClassHierarchyTests.ARecordIsCountedButNotListed;
begin
  Build(['type TRec = record X: Integer; end; TA = class end;']);
  Assert.AreEqual(1, FHier.Records);
  Assert.AreEqual<NativeInt>(1, FHier.Nodes.Count);
  Assert.IsNull(FHier.Find('TRec'));
end;

procedure TClassHierarchyTests.MethodsAreCountedPerClass;
begin
  Build(['type TA = class end; TB = class end; TC = class end;']);
  Assert.AreEqual(2, Node('TA').Methods);
  Assert.AreEqual(1, Node('TB').Methods);
  Assert.AreEqual(0, Node('TC').Methods);
end;

procedure TClassHierarchyTests.StatisticsAndHistogram;
var
  H: TArray<Integer>;
begin
  Build(['type TA = class end; TB = class(TA) end; TC = class(TB) end; TD = class end;']);
  Assert.AreEqual(3, FHier.MaxDepth);
  Assert.AreEqual(7 / 4, FHier.AverageDepth, 0.0001);
  H := FHier.Histogram;
  Assert.AreEqual<NativeInt>(4, Length(H));
  Assert.AreEqual(0, H[0]);
  Assert.AreEqual(2, H[1]);
  Assert.AreEqual(1, H[2]);
  Assert.AreEqual(1, H[3]);
  Assert.AreEqual(4, FHier.Count(ckClass));
  Assert.AreEqual<NativeInt>(2, Length(FHier.Roots));
end;

procedure TClassHierarchyTests.DeepestAndMostChildrenAreSorted;
var
  D, M: TArray<TClassNode>;
begin
  Build(['type TA = class end; TB = class(TA) end; TC = class(TA) end; TD = class(TB) end; TE = class(TA) end;']);
  D := FHier.Deepest(2);
  Assert.AreEqual<NativeInt>(2, Length(D));
  Assert.AreEqual('TD', D[0].Name, 'a mais profunda');
  Assert.AreEqual('TB', D[1].Name, 'empate a profundidade 2: mais descendentes primeiro');
  M := FHier.MostChildren(1);
  Assert.AreEqual('TA', M[0].Name);
  Assert.AreEqual<NativeInt>(5, Length(FHier.Deepest(-1)), 'sem limite');
end;

procedure TClassHierarchyTests.TreeOrderPutsChildrenUnderTheirParent;
var
  T: TArray<TClassNode>;
  Names: string;
  N: TClassNode;
begin
  Build(['type TZ = class end; TA = class end; TB = class(TA) end; TC = class(TA) end; TD = class(TB) end;']);
  T := FHier.TreeOrder;
  Names := '';
  for N in T do
    Names := Names + N.Name + ' ';
  Assert.AreEqual('TA TB TD TC TZ ', Names);
end;

procedure TClassHierarchyTests.ChainListsTheAncestors;
var
  C: TArray<string>;
begin
  Build(['type TA = class end; TB = class(TA) end; TC = class(TB) end; TS = class(TStringList) end;']);
  C := Node('TC').Chain;
  Assert.AreEqual('TC|TB|TA', string.Join('|', C));
  C := Node('TS').Chain;
  Assert.AreEqual('TS|TStringList', string.Join('|', C));
end;

procedure TClassHierarchyTests.DepthLevelsUseTheirLimits;
begin
  Assert.AreEqual(Ord(cxNone), Ord(DepthLevel(0)));
  Assert.AreEqual(Ord(cxLow), Ord(DepthLevel(1)));
  Assert.AreEqual(Ord(cxLow), Ord(DepthLevel(4)));
  Assert.AreEqual(Ord(cxModerate), Ord(DepthLevel(5)));
  Assert.AreEqual(Ord(cxModerate), Ord(DepthLevel(6)));
  Assert.AreEqual(Ord(cxHigh), Ord(DepthLevel(7)));
end;

procedure TClassHierarchyTests.KnownDepthIgnoresCaseAndQualification;
var
  D: Integer;
begin
  Assert.IsTrue(KnownDepth('TObject', D));
  Assert.AreEqual(0, D);
  Assert.IsTrue(KnownDepth('system.classes.tcomponent', D));
  Assert.AreEqual(2, D);
  Assert.IsTrue(KnownDepth('Exception', D));
  Assert.AreEqual(1, D);
  Assert.IsFalse(KnownDepth('TForm', D), 'depende do framework: nao consta');
  Assert.IsFalse(KnownDepth('', D));
end;

procedure TClassHierarchyTests.FmxOnlyClassesAreKnownButTControlIsNot;
var
  D: Integer;
begin
  Assert.IsTrue(KnownDepth('FMX.Layouts.TLayout', D));
  Assert.AreEqual(5, D);
  Assert.IsTrue(KnownDepth('TFmxObject', D));
  Assert.AreEqual(3, D);
  Assert.IsFalse(KnownDepth('TControl', D));   // existe no VCL e no FMX com cadeias diferentes
end;

procedure TClassHierarchyTests.NilScanIsEmpty;
var
  H: THierarchy;
begin
  H := BuildHierarchy(nil);
  try
    Assert.AreEqual<NativeInt>(0, H.Nodes.Count);
    Assert.AreEqual(0, H.MaxDepth);
    Assert.AreEqual(0.0, H.AverageDepth, 0.0001);
    Assert.AreEqual<NativeInt>(1, Length(H.Histogram));
  finally
    H.Free;
  end;
end;

procedure TClassHierarchyTests.FindIgnoresQualificationAndCase;
begin
  Build(['type TFoo = class end;']);
  Assert.IsNotNull(FHier.Find('tfoo'));
  Assert.IsNotNull(FHier.Find('Core.u1.TFoo'));
  Assert.IsNull(FHier.Find('TBar'));
end;

procedure TClassHierarchyTests.UnitLayerAndLineAreKept;
begin
  Build(['unit u;' + #10 + 'type' + #10 + '  TFoo = class end;']);
  Assert.AreEqual('Core/u1.pas', Node('TFoo').UnitPath);
  Assert.AreEqual('Core', Node('TFoo').Layer);
  Assert.AreEqual(3, Node('TFoo').Line);
end;

end.
