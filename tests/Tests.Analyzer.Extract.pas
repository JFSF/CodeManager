unit Tests.Analyzer.Extract;

// Testes da extracao de metodos (CM.Analyzer.ExtractMethods): limpeza de comentarios/strings,
// fusao interface/implementation, overloads, genericos, tipos aninhados e ficheiros ANSI.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, DUnitX.TestFramework, CM.Analyzer, Tests.Helpers;

type
  [TestFixture]
  TExtractBasicTests = class
  public
    [Test] procedure FreeRoutinesWithoutInterface;
    [Test] procedure KindsAreLowerCased;
    [Test] procedure EmptyFileHasNoMethods;
    [Test] procedure DprWithoutSectionsIsAnalysedAsImplementation;
    [Test] procedure ClassMethodsMergeInterfaceAndImplementation;
    [Test] procedure ConstructorsAndDestructors;
    [Test] procedure ClassMethodKeepsClassPrefix;
    [Test] procedure ParamNamesMayDifferBetweenInterfaceAndImplementation;
    [Test] procedure ImplementationOnlyMethodsAreListed;
    [Test] procedure SignatureTerminatesWithSemicolon;
    [Test] procedure OwnerAndSimpleAreFilled;
  end;

  [TestFixture]
  TExtractCleaningTests = class
  public
    [Test] procedure LineCommentsAreIgnored;
    [Test] procedure BraceCommentsAreIgnored;
    [Test] procedure ParenStarCommentsAreIgnored;
    [Test] procedure MultiLineCommentsAreIgnored;
    [Test] procedure StringLiteralsAreIgnored;
    [Test] procedure ApostropheInsideCommentDoesNotStartAString;
    [Test] procedure EscapedQuoteInsideString;
    [Test] procedure CommentMarkersInsideStringsAreNotComments;
    [Test] procedure CompilerDirectivesDoNotBreakParsing;
  end;

  [TestFixture]
  TExtractOverloadTests = class
  public
    [Test] procedure FirstOverloadKeepsPlainName;
    [Test] procedure LaterOverloadsUseParameterTypes;
    [Test] procedure GroupedParametersExpandToOneTypePerName;
    [Test] procedure DefaultValuesAreNotPartOfTheType;
    [Test] procedure ModifiersAreNotPartOfTheType;
    [Test] procedure UntypedParameters;
    [Test] procedure ProcedureTypedParameterDoesNotSplitTheList;
    [Test] procedure AddingAnOverloadKeepsTheFirstName;
    [Test] procedure ImplementationRepeatingWithoutParamsMergesWithSingleCandidate;
    [Test] procedure OverloadsMergeAcrossInterfaceAndImplementation;
    [Test] procedure SameNameDifferentClassesDoNotClash;
  end;

  [TestFixture]
  TExtractTypeTests = class
  public
    [Test] procedure GenericClassIsQualifiedWithoutTypeParameters;
    [Test] procedure GenericImplementationMatchesInterface;
    [Test] procedure NestedTypesJoinOwners;
    [Test] procedure RecordMethods;
    [Test] procedure InterfaceTypeMethods;
    [Test] procedure ClassReferenceIsNotATypeHead;
    [Test] procedure ForwardDeclarationDoesNotOpenContext;
    [Test] procedure EmptyClassWithAncestorDoesNotOpenContext;
    [Test] procedure ClassWithAncestorsAndInterfaces;
    [Test] procedure SealedAndAbstractClasses;
    [Test] procedure MethodAfterClosedTypeIsFree;
    [Test] procedure ProceduralTypesAreNotMethods;
    [Test] procedure ReferenceToProcedureIsNotAMethod;
    [Test] procedure VisibilitySectionsDoNotMatter;
    [Test] procedure ConsecutiveImplementationMethods;
  end;

  [TestFixture]
  TExtractFileTests = class
  private
    FDir: TTempDir;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Utf8WithBom;
    [Test] procedure AnsiFileWithAccents;
    [Test] procedure MissingFileRaises;
    [Test] procedure LfLineEndings;
  end;

implementation

function Src(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

{ TExtractBasicTests }

procedure TExtractBasicTests.FreeRoutinesWithoutInterface;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(Src(['procedure Foo;', 'begin', 'end;', '', 'function Bar(A: Integer): Boolean;', 'begin', 'end;']));
  Assert.AreEqual('Foo|Bar', NamesOf(M));
  Assert.AreEqual('procedure Foo;|function Bar(A: Integer): Boolean;', SigsOf(M));
end;

procedure TExtractBasicTests.KindsAreLowerCased;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit('', 'PROCEDURE Foo; begin end; FUNCTION Bar: Integer; begin Result := 0; end;'));
  Assert.AreEqual('Foo|Bar', NamesOf(M));
  Assert.AreEqual('procedure', M[0].Kind);
  Assert.AreEqual('function', M[1].Kind);
end;

procedure TExtractBasicTests.EmptyFileHasNoMethods;
begin
  Assert.AreEqual<NativeInt>(0, Length(Extract('')));
  Assert.AreEqual<NativeInt>(0, Length(Extract(WrapUnit(''))));
end;

procedure TExtractBasicTests.DprWithoutSectionsIsAnalysedAsImplementation;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(Src(['program P;', 'uses SysUtils;', 'procedure Hello;', 'begin', 'end;', 'begin', '  Hello;', 'end.']));
  Assert.AreEqual('Hello', NamesOf(M));
end;

procedure TExtractBasicTests.ClassMethodsMergeInterfaceAndImplementation;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '  public', '    procedure Bar;', '    function Baz(A: Integer): string;', '  end;']),
    Src(['procedure TFoo.Bar;', 'begin', 'end;', '', 'function TFoo.Baz(A: Integer): string;', 'begin', '  Result := '''';', 'end;'])));
  Assert.AreEqual('TFoo.Bar|TFoo.Baz', NamesOf(M));
  Assert.AreEqual('procedure TFoo.Bar;|function TFoo.Baz(A: Integer): string;', SigsOf(M));
end;

procedure TExtractBasicTests.ConstructorsAndDestructors;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '    constructor Create(AOwner: TObject);', '    destructor Destroy; override;', '  end;']),
    Src(['constructor TFoo.Create(AOwner: TObject);', 'begin', 'end;', 'destructor TFoo.Destroy;', 'begin', 'end;'])));
  Assert.AreEqual('TFoo.Create|TFoo.Destroy', NamesOf(M));
  Assert.AreEqual('constructor', M[0].Kind);
  Assert.AreEqual('destructor', M[1].Kind);
end;

procedure TExtractBasicTests.ClassMethodKeepsClassPrefix;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '    class function Make: TFoo; static;', '    class procedure Reset;', '  end;']),
    Src(['class function TFoo.Make: TFoo;', 'begin', 'end;', 'class procedure TFoo.Reset;', 'begin', 'end;'])));
  Assert.AreEqual('TFoo.Make|TFoo.Reset', NamesOf(M));
  Assert.AreEqual('class function', M[0].Kind);
  Assert.AreEqual('class procedure', M[1].Kind);
  Assert.IsTrue(M[0].Sig.StartsWith('class function TFoo.Make'), M[0].Sig);
end;

procedure TExtractBasicTests.ParamNamesMayDifferBetweenInterfaceAndImplementation;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '    procedure Bar(Value: Integer);', '  end;']),
    Src(['procedure TFoo.Bar(AValue: Integer);', 'begin', 'end;'])));
  Assert.AreEqual('TFoo.Bar', NamesOf(M));
  Assert.AreEqual<NativeInt>(1, Length(M));
end;

procedure TExtractBasicTests.ImplementationOnlyMethodsAreListed;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '    procedure Pub;', '  end;']),
    Src(['procedure Helper;', 'begin', 'end;', 'procedure TFoo.Pub;', 'begin', '  Helper;', 'end;'])));
  Assert.AreEqual('TFoo.Pub|Helper', NamesOf(M));
end;

procedure TExtractBasicTests.SignatureTerminatesWithSemicolon;
var
  M: TArray<TMethodInfo>;
  I: Integer;
begin
  M := Extract(WrapUnit('', Src(['procedure A;', 'begin', 'end;', 'function B(X: Integer): Integer;', 'begin', 'end;'])));
  Assert.AreEqual<NativeInt>(2, Length(M));
  for I := 0 to High(M) do
    Assert.IsTrue(M[I].Sig.EndsWith(';'), M[I].Sig);
end;

procedure TExtractBasicTests.OwnerAndSimpleAreFilled;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit('', Src(['procedure Free1;', 'begin', 'end;', 'procedure TFoo.Bar;', 'begin', 'end;'])));
  Assert.AreEqual('', M[0].Owner);
  Assert.AreEqual('Free1', M[0].Simple);
  Assert.AreEqual('TFoo', M[1].Owner);
  Assert.AreEqual('Bar', M[1].Simple);
end;

{ TExtractCleaningTests }

procedure TExtractCleaningTests.LineCommentsAreIgnored;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['// procedure Fake;', 'procedure Real; // procedure Fake2;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.BraceCommentsAreIgnored;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['{ procedure Fake; }', 'procedure Real;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.ParenStarCommentsAreIgnored;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['(* procedure Fake; *)', 'procedure Real;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.MultiLineCommentsAreIgnored;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['{', '  procedure Fake;', '  function Fake2: Integer;', '}', '(*', ' procedure Fake3;', '*)',
         'procedure Real;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.StringLiteralsAreIgnored;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['procedure Real;', 'begin', '  Writeln(''procedure Fake; function Fake2;'');', 'end;'])))));
end;

procedure TExtractCleaningTests.ApostropheInsideCommentDoesNotStartAString;
begin
  Assert.AreEqual('Real|After', NamesOf(Extract(WrapUnit('',
    Src(['// it''s a comment with an apostrophe', 'procedure Real;', 'begin', 'end;',
         '{ don''t break }', 'procedure After;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.EscapedQuoteInsideString;
begin
  Assert.AreEqual('Real|After', NamesOf(Extract(WrapUnit('',
    Src(['procedure Real;', 'begin', '  S := ''it''''s; procedure Fake;'';', 'end;',
         'procedure After;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.CommentMarkersInsideStringsAreNotComments;
begin
  // '//' e '{' dentro de uma string nao podem engolir o resto do ficheiro
  Assert.AreEqual('Real|After', NamesOf(Extract(WrapUnit('',
    Src(['procedure Real;', 'begin', '  U := ''http://x'';', '  T := ''{'';', 'end;',
         'procedure After;', 'begin', 'end;'])))));
end;

procedure TExtractCleaningTests.CompilerDirectivesDoNotBreakParsing;
begin
  Assert.AreEqual('Real', NamesOf(Extract(WrapUnit('',
    Src(['{$IFDEF DEBUG}', 'procedure Real;', '{$ENDIF}', 'begin', 'end;'])))));
end;

{ TExtractOverloadTests }

procedure TExtractOverloadTests.FirstOverloadKeepsPlainName;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TFoo = class', '    procedure Bar(A: Integer); overload;', '    procedure Bar(const S: string); overload;', '  end;']),
    Src(['procedure TFoo.Bar(A: Integer);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string);', 'begin', 'end;'])));
  Assert.AreEqual('TFoo.Bar|TFoo.Bar(string)', NamesOf(M));
end;

procedure TExtractOverloadTests.LaterOverloadsUseParameterTypes;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(A: Integer); overload;',
    'procedure Foo(A: Integer; B: string); overload;']), ''));
  Assert.AreEqual('Foo|Foo(Integer)|Foo(Integer, string)', NamesOf(M));
end;

procedure TExtractOverloadTests.GroupedParametersExpandToOneTypePerName;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(A, B: Integer; const S: string); overload;']), ''));
  Assert.AreEqual('Foo|Foo(Integer, Integer, string)', NamesOf(M));
end;

procedure TExtractOverloadTests.DefaultValuesAreNotPartOfTheType;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(A: Integer = 5; const S: string = ''x''); overload;']), ''));
  Assert.AreEqual('Foo|Foo(Integer, string)', NamesOf(M));
end;

procedure TExtractOverloadTests.ModifiersAreNotPartOfTheType;
var
  M: TArray<TMethodInfo>;
begin
  // var/const/out ficam do lado do nome, por isso a chave depende so dos tipos
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(var A: Integer; out B: string; const C: Double); overload;']), ''));
  Assert.AreEqual('Foo|Foo(Integer, string, Double)', NamesOf(M));
end;

procedure TExtractOverloadTests.UntypedParameters;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(var Buf); overload;']), ''));
  Assert.AreEqual('Foo|Foo(untyped)', NamesOf(M));
end;

procedure TExtractOverloadTests.ProcedureTypedParameterDoesNotSplitTheList;
var
  M: TArray<TMethodInfo>;
begin
  // o ';' dentro de parenteses (tipo procedural) nao separa parametros
  M := Extract(WrapUnit(Src([
    'procedure Foo; overload;',
    'procedure Foo(Cb: reference to procedure(A: Integer; B: Integer); N: Integer); overload;']), ''));
  Assert.AreEqual<NativeInt>(2, Length(M));
  Assert.IsTrue(M[1].Name.EndsWith(', Integer)'), M[1].Name);
end;

procedure TExtractOverloadTests.AddingAnOverloadKeepsTheFirstName;
var
  Before, After: TArray<TMethodInfo>;
begin
  // o progresso guardado usa o nome: acrescentar um overload nao pode renomear o primeiro
  Before := Extract(WrapUnit(Src(['procedure Foo(A: Integer);']), ''));
  After := Extract(WrapUnit(Src(['procedure Foo(A: Integer);', 'procedure Foo(S: string); overload;']), ''));
  Assert.AreEqual('Foo', NamesOf(Before));
  Assert.AreEqual('Foo|Foo(string)', NamesOf(After));
end;

procedure TExtractOverloadTests.ImplementationRepeatingWithoutParamsMergesWithSingleCandidate;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['procedure Foo(A: Integer);']),
    Src(['procedure Foo;', 'begin', 'end;'])));
  Assert.AreEqual('Foo', NamesOf(M));
end;

procedure TExtractOverloadTests.OverloadsMergeAcrossInterfaceAndImplementation;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['procedure Foo(A: Integer); overload;', 'procedure Foo(S: string); overload;']),
    Src(['procedure Foo(X: Integer);', 'begin', 'end;', 'procedure Foo(T: string);', 'begin', 'end;'])));
  Assert.AreEqual('Foo|Foo(string)', NamesOf(M));
end;

procedure TExtractOverloadTests.SameNameDifferentClassesDoNotClash;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit('', Src([
    'procedure TA.Run;', 'begin', 'end;',
    'procedure TB.Run;', 'begin', 'end;'])));
  Assert.AreEqual('TA.Run|TB.Run', NamesOf(M));
end;

{ TExtractTypeTests }

procedure TExtractTypeTests.GenericClassIsQualifiedWithoutTypeParameters;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TBox<T> = class',
    '    procedure Put(const V: T);',
    '  end;']), ''));
  Assert.AreEqual('TBox.Put', NamesOf(M));
end;

procedure TExtractTypeTests.GenericImplementationMatchesInterface;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(
    Src(['type', '  TBox<T> = class', '    procedure Put(const V: T);', '  end;']),
    Src(['procedure TBox<T>.Put(const V: T);', 'begin', 'end;'])));
  Assert.AreEqual('TBox.Put', NamesOf(M));
  Assert.AreEqual<NativeInt>(1, Length(M));
end;

procedure TExtractTypeTests.NestedTypesJoinOwners;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TOuter = class',
    '    procedure A;',
    '    type',
    '      TInner = class',
    '        procedure B;',
    '      end;',
    '    procedure C;',
    '  end;']), ''));
  Assert.AreEqual('TOuter.A|TOuter.TInner.B|TOuter.C', NamesOf(M));
  Assert.AreEqual('TOuter.TInner', M[1].Owner);
end;

procedure TExtractTypeTests.RecordMethods;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TPoint2 = record',
    '    X, Y: Integer;',
    '    function Len: Double;',
    '  end;']), ''));
  Assert.AreEqual('TPoint2.Len', NamesOf(M));
end;

procedure TExtractTypeTests.InterfaceTypeMethods;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  IShape = interface',
    '    function Area: Double;',
    '    procedure Draw;',
    '  end;']), ''));
  Assert.AreEqual('IShape.Area|IShape.Draw', NamesOf(M));
end;

procedure TExtractTypeTests.ClassReferenceIsNotATypeHead;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TFooClass = class of TFoo;',
    'procedure Free1;']), ''));
  Assert.AreEqual('Free1', NamesOf(M));
  Assert.AreEqual('', M[0].Owner);
end;

procedure TExtractTypeTests.ForwardDeclarationDoesNotOpenContext;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TFoo = class;',
    '  TBar = class',
    '    procedure Run;',
    '  end;']), ''));
  Assert.AreEqual('TBar.Run', NamesOf(M));
end;

procedure TExtractTypeTests.EmptyClassWithAncestorDoesNotOpenContext;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  EMyError = class(Exception);',
    '  TEmpty = class end;',
    'procedure Free1;']), ''));
  Assert.AreEqual('Free1', NamesOf(M));
  Assert.AreEqual('', M[0].Owner);
end;

procedure TExtractTypeTests.ClassWithAncestorsAndInterfaces;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TFoo = class(TBar, IFoo, IBaz)',
    '    procedure Run;',
    '  end;']), ''));
  Assert.AreEqual('TFoo.Run', NamesOf(M));
end;

procedure TExtractTypeTests.SealedAndAbstractClasses;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TA = class abstract',
    '    procedure One; virtual; abstract;',
    '  end;',
    '  TB = class sealed(TA)',
    '    procedure One; override;',
    '  end;']), ''));
  Assert.AreEqual('TA.One|TB.One', NamesOf(M));
end;

procedure TExtractTypeTests.MethodAfterClosedTypeIsFree;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TFoo = class',
    '    procedure A;',
    '  end;',
    'procedure Free1;']), ''));
  Assert.AreEqual('TFoo.A|Free1', NamesOf(M));
  Assert.AreEqual('', M[1].Owner);
end;

procedure TExtractTypeTests.ProceduralTypesAreNotMethods;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TNotify = procedure(Sender: TObject) of object;',
    '  TCompare = function(A, B: Integer): Integer;',
    'procedure Real;']), ''));
  Assert.AreEqual('Real', NamesOf(M));
end;

procedure TExtractTypeTests.ReferenceToProcedureIsNotAMethod;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TAction = reference to procedure(A: Integer);',
    '  TFunc2 = reference to function: Integer;',
    'procedure Real;']), ''));
  Assert.AreEqual('Real', NamesOf(M));
end;

procedure TExtractTypeTests.VisibilitySectionsDoNotMatter;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit(Src([
    'type',
    '  TFoo = class',
    '  strict private',
    '    procedure A;',
    '  protected',
    '    procedure B;',
    '  public',
    '    procedure C;',
    '  published',
    '    procedure D;',
    '  end;']), ''));
  Assert.AreEqual('TFoo.A|TFoo.B|TFoo.C|TFoo.D', NamesOf(M));
end;

procedure TExtractTypeTests.ConsecutiveImplementationMethods;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(WrapUnit('', Src([
    'procedure TFoo.Outer;',
    'begin',
    'end;',
    'procedure TFoo.After;',
    'begin',
    'end;'])));
  Assert.AreEqual('TFoo.Outer|TFoo.After', NamesOf(M));
end;

{ TExtractFileTests }

procedure TExtractFileTests.Setup;
begin
  FDir := TTempDir.Create;
end;

procedure TExtractFileTests.TearDown;
begin
  FDir.Free;
end;

procedure TExtractFileTests.Utf8WithBom;
var
  M: TArray<TMethodInfo>;
begin
  // 'Ac' + c-cedilha + a-til + 'o' escritos por codigo para o .pas nao depender da codificacao
  TFile.WriteAllText(FDir.Full('a.pas'),
    WrapUnit('', 'procedure Ac' + #$00E7 + #$00E3 + 'o; begin end;'), TEncoding.UTF8);
  M := ExtractMethods(FDir.Full('a.pas'));
  Assert.AreEqual<NativeInt>(1, Length(M));
end;

procedure TExtractFileTests.AnsiFileWithAccents;
var
  Text: string;
  M: TArray<TMethodInfo>;
begin
  // sem BOM e nao-UTF-8: cai para ANSI em vez de falhar
  Text := WrapUnit('', '// aten' + #$00E7 + #$00E3 + 'o: n' + #$00E3 + 'o e UTF-8' + #13#10 +
    'procedure Real; begin end;');
  TFile.WriteAllText(FDir.Full('b.pas'), Text, TEncoding.ANSI);
  M := ExtractMethods(FDir.Full('b.pas'));
  Assert.AreEqual('Real', NamesOf(M));
end;

procedure TExtractFileTests.MissingFileRaises;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    ExtractMethods(FDir.Full('nao-existe.pas'));
  except
    on Exception do
      Raised := True;
  end;
  Assert.IsTrue(Raised, 'um ficheiro inexistente deve levantar excepcao');
end;

procedure TExtractFileTests.LfLineEndings;
var
  Text: string;
begin
  Text := WrapUnit('', 'procedure A; begin end;').Replace(#13#10, #10);
  TFile.WriteAllText(FDir.Full('lf.pas'), Text, TEncoding.UTF8);
  Assert.AreEqual('A', NamesOf(ExtractMethods(FDir.Full('lf.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TExtractBasicTests);
  TDUnitX.RegisterTestFixture(TExtractCleaningTests);
  TDUnitX.RegisterTestFixture(TExtractOverloadTests);
  TDUnitX.RegisterTestFixture(TExtractTypeTests);
  TDUnitX.RegisterTestFixture(TExtractFileTests);

end.
