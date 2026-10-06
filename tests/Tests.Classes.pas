unit Tests.Classes;

// Testes da extraccao das declaracoes de tipos (CM.Classes) e da sua ligacao ao analisador.

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Classes, CM.Analyzer, Tests.Helpers;

type
  [TestFixture]
  TClassesTests = class
  private
    function One(const AText: string): TClassInfo;
  public
    [Test] procedure AClassWithoutAncestorHasNone;
    [Test] procedure TheFirstNameInParenthesesIsTheAncestor;
    [Test] procedure TheOthersAreInterfaces;
    [Test] procedure AClassThatOnlyListsAnInterfaceInheritsFromTObject;
    [Test] procedure GenericsLoseTheirArguments;
    [Test] procedure ForwardDeclarationsAreSkipped;
    [Test] procedure AnEmptyClassWithAnAncestorIsKept;
    [Test] procedure ClassReferencesAreSkipped;
    [Test] procedure HelpersAreNotNewTypes;
    [Test] procedure RecordsAndObjectsAreListed;
    [Test] procedure InterfacesHaveAnAncestorToo;
    [Test] procedure SealedAndAbstractAreIgnored;
    [Test] procedure NestedTypesAreFound;
    [Test] procedure QualifiedAncestorsKeepTheirQualification;
    [Test] procedure LinesAreCounted;
    [Test] procedure ManyTypesComeInOrder;
    [Test] procedure PlainTextHasNoClasses;
    [Test] procedure SameClassesComparesEverything;
    [Test] procedure KindNamesAreReadable;
    [Test] procedure TheScanKeepsTheClassesOfEachUnit;
    [Test] procedure RescanningNoticesAChangedAncestor;
  end;

implementation

function TClassesTests.One(const AText: string): TClassInfo;
var
  C: TArray<TClassInfo>;
begin
  C := ExtractClasses(AText);
  Assert.AreEqual<NativeInt>(1, Length(C), AText);
  Result := C[0];
end;

procedure TClassesTests.AClassWithoutAncestorHasNone;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class end;');
  Assert.AreEqual('TFoo', C.Name);
  Assert.AreEqual(Ord(ckClass), Ord(C.Kind));
  Assert.AreEqual('', C.Ancestor);
  Assert.AreEqual<NativeInt>(0, Length(C.Interfaces));
  C := One('type TFoo = class' + #10 + '  procedure Bar;' + #10 + 'end;');
  Assert.AreEqual('', C.Ancestor);
end;

procedure TClassesTests.TheFirstNameInParenthesesIsTheAncestor;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class(TBar) procedure X; end;');
  Assert.AreEqual('TBar', C.Ancestor);
  Assert.AreEqual<NativeInt>(0, Length(C.Interfaces));
end;

procedure TClassesTests.TheOthersAreInterfaces;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class(TInterfacedObject, IFoo, IBar) end;');
  Assert.AreEqual('TInterfacedObject', C.Ancestor);
  Assert.AreEqual<NativeInt>(2, Length(C.Interfaces));
  Assert.AreEqual('IFoo', C.Interfaces[0]);
  Assert.AreEqual('IBar', C.Interfaces[1]);
end;

procedure TClassesTests.AClassThatOnlyListsAnInterfaceInheritsFromTObject;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class(IFoo) end;');
  Assert.AreEqual('', C.Ancestor, 'IFoo e uma interface: a base e TObject');
  Assert.AreEqual<NativeInt>(1, Length(C.Interfaces));
  Assert.AreEqual('IFoo', C.Interfaces[0]);
  C := One('type TFoo = class(IFoo, IBar) end;');
  Assert.AreEqual('', C.Ancestor);
  Assert.AreEqual<NativeInt>(2, Length(C.Interfaces));
  C := One('type TItem = class(Item) end;');
  Assert.AreEqual('Item', C.Ancestor, 'Item nao parece uma interface (I + maiuscula)');
end;

procedure TClassesTests.GenericsLoseTheirArguments;
var
  C: TClassInfo;
begin
  C := One('type TFoo<T> = class(TBar<T>) end;');
  Assert.AreEqual('TFoo', C.Name);
  Assert.AreEqual('TBar', C.Ancestor);
  C := One('type TPair<K, V: class> = class(TDictionary<K, TList<V>>, IEnumerable<V>) end;');
  Assert.AreEqual('TPair', C.Name);
  Assert.AreEqual('TDictionary', C.Ancestor);
  Assert.AreEqual<NativeInt>(1, Length(C.Interfaces));
  Assert.AreEqual('IEnumerable', C.Interfaces[0]);
end;

procedure TClassesTests.ForwardDeclarationsAreSkipped;
begin
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TFoo = class; IBar = interface;')));
  Assert.AreEqual<NativeInt>(1, Length(ExtractClasses('type TFoo = class; TFoo = class(TBar) end;')),
    'so a declaracao completa conta');
end;

procedure TClassesTests.AnEmptyClassWithAnAncestorIsKept;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class(TBar);');
  Assert.AreEqual('TFoo', C.Name);
  Assert.AreEqual('TBar', C.Ancestor);
end;

procedure TClassesTests.ClassReferencesAreSkipped;
begin
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TFooClass = class of TFoo;')));
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TFooClass = class  of  TFoo;')));
end;

procedure TClassesTests.HelpersAreNotNewTypes;
begin
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TStrHelper = class helper for TStringList end;')));
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TRecHelper = record helper for TRec end;')));
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('type TInt = class helper(TBase) for TFoo end;')) , 'helper com ancestral');
end;

procedure TClassesTests.RecordsAndObjectsAreListed;
var
  C: TArray<TClassInfo>;
begin
  C := ExtractClasses('type TRec = record X: Integer; end; TPacked = packed record Y: Byte; end; TOld = object(TBase) end;');
  Assert.AreEqual<NativeInt>(3, Length(C));
  Assert.AreEqual(Ord(ckRecord), Ord(C[0].Kind));
  Assert.AreEqual(Ord(ckRecord), Ord(C[1].Kind));
  Assert.AreEqual(Ord(ckObject), Ord(C[2].Kind));
  Assert.AreEqual('TBase', C[2].Ancestor);
  Assert.AreEqual('', C[0].Ancestor, 'um record nao herda');
end;

procedure TClassesTests.InterfacesHaveAnAncestorToo;
var
  C: TClassInfo;
begin
  C := One('type IFoo = interface(IBar) [''{00000000-0000-0000-0000-000000000000}''] procedure X; end;');
  Assert.AreEqual(Ord(ckInterface), Ord(C.Kind));
  Assert.AreEqual('IBar', C.Ancestor);
  C := One('type IBaz = interface [''''] procedure X; end;');
  Assert.AreEqual('', C.Ancestor);
  C := One('type IDisp = dispinterface [''''] end;');
  Assert.AreEqual(Ord(ckInterface), Ord(C.Kind));
end;

procedure TClassesTests.SealedAndAbstractAreIgnored;
begin
  Assert.AreEqual('TBar', One('type TFoo = class sealed(TBar) end;').Ancestor);
  Assert.AreEqual('TBar', One('type TFoo = class abstract(TBar) end;').Ancestor);
  Assert.AreEqual('', One('type TFoo = class abstract end;').Ancestor);
end;

procedure TClassesTests.NestedTypesAreFound;
var
  C: TArray<TClassInfo>;
begin
  C := ExtractClasses('type TOuter = class(TBase) type TInner = class(TOuter) end; end;');
  Assert.AreEqual<NativeInt>(2, Length(C));
  Assert.AreEqual('TOuter', C[0].Name);
  Assert.AreEqual('TInner', C[1].Name);
  Assert.AreEqual('TOuter', C[1].Ancestor);
end;

procedure TClassesTests.QualifiedAncestorsKeepTheirQualification;
var
  C: TClassInfo;
begin
  C := One('type TFoo = class(System.Classes.TComponent) end;');
  Assert.AreEqual('System.Classes.TComponent', C.Ancestor);
  C := One('type TFoo = class(Vcl.Forms.TForm, Core.IFoo) end;');
  Assert.AreEqual('Vcl.Forms.TForm', C.Ancestor);
end;

procedure TClassesTests.LinesAreCounted;
var
  C: TArray<TClassInfo>;
begin
  C := ExtractClasses('unit X;' + #10 + 'interface' + #10 + 'type' + #10 + '  TA = class end;' + #10 + #10 +
    '  TB = class(TA)' + #10 + '  end;');
  Assert.AreEqual<NativeInt>(2, Length(C));
  Assert.AreEqual(4, C[0].Line);
  Assert.AreEqual(6, C[1].Line);
end;

procedure TClassesTests.ManyTypesComeInOrder;
var
  C: TArray<TClassInfo>;
begin
  C := ExtractClasses('type TA = class end; TB = class(TA) end; IC = interface end; TD = class(TB, IC) end;');
  Assert.AreEqual<NativeInt>(4, Length(C));
  Assert.AreEqual('TA|TB|IC|TD', string.Join('|', [C[0].Name, C[1].Name, C[2].Name, C[3].Name]));
end;

procedure TClassesTests.PlainTextHasNoClasses;
begin
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('')));
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('unit X; interface implementation procedure A; begin end; end.')));
  Assert.AreEqual<NativeInt>(0, Length(ExtractClasses('const X = 1; var Y: Integer;')));
end;

procedure TClassesTests.SameClassesComparesEverything;
var
  A, B: TArray<TClassInfo>;
begin
  A := ExtractClasses('type TFoo = class(TBar, IX) end;');
  B := ExtractClasses('type TFoo = class(TBar, IX) end;');
  Assert.IsTrue(SameClasses(A, B));
  Assert.IsFalse(SameClasses(A, ExtractClasses('type TFoo = class(TBaz, IX) end;')), 'ancestral');
  Assert.IsFalse(SameClasses(A, ExtractClasses('type TFoo = class(TBar, IY) end;')), 'interface');
  Assert.IsFalse(SameClasses(A, ExtractClasses('type TFoo = class(TBar) end;')), 'interfaces a menos');
  Assert.IsFalse(SameClasses(A, ExtractClasses('type TFoo2 = class(TBar, IX) end;')), 'nome');
  Assert.IsFalse(SameClasses(A, nil));
  Assert.IsTrue(SameClasses(nil, nil));
end;

procedure TClassesTests.KindNamesAreReadable;
begin
  Assert.AreEqual('class', ClassKindName(ckClass));
  Assert.AreEqual('interface', ClassKindName(ckInterface));
  Assert.AreEqual('record', ClassKindName(ckRecord));
  Assert.AreEqual('object', ClassKindName(ckObject));
end;

procedure TClassesTests.TheScanKeepsTheClassesOfEachUnit;
var
  Dir: TTempDir;
  Scan: TProjectScan;
  U: TUnitInfo;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('a.pas', 'unit a; interface type TA = class(TObject) procedure X; end; TB = class(TA) end; implementation procedure TA.X; begin end; end.');
    Dir.Write('b.pas', 'unit b; interface type IB = interface end; implementation end.');
    Scan := ScanProject(Dir.Path, nil);
    try
      U := Scan.Units[0];
      Assert.AreEqual('a.pas', U.Path);
      Assert.AreEqual<NativeInt>(2, Length(U.Classes));
      Assert.AreEqual('TA', U.Classes[0].Name);
      Assert.AreEqual('TObject', U.Classes[0].Ancestor);
      Assert.AreEqual('TA', U.Classes[1].Ancestor);
      Assert.AreEqual<NativeInt>(1, Length(Scan.Units[1].Classes));
      Assert.AreEqual(Ord(ckInterface), Ord(Scan.Units[1].Classes[0].Kind));
    finally
      Scan.Free;
    end;
  finally
    Dir.Free;
  end;
end;

procedure TClassesTests.RescanningNoticesAChangedAncestor;
var
  Dir: TTempDir;
  Scan: TProjectScan;
begin
  Dir := TTempDir.Create;
  try
    Dir.Write('a.pas', 'unit a; interface type TA = class(TObject) end; implementation end.');
    Scan := ScanProject(Dir.Path, nil);
    try
      Assert.AreEqual(Ord(rcNone), Ord(RescanFile(Scan, 'a.pas')), 'nada mudou');
      Dir.Write('a.pas', 'unit a; interface type TA = class(TComponent) end; implementation end.');
      Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(Scan, 'a.pas')), 'so o ancestral mudou');
      Assert.AreEqual('TComponent', Scan.Units[0].Classes[0].Ancestor);
    finally
      Scan.Free;
    end;
  finally
    Dir.Free;
  end;
end;

end.
