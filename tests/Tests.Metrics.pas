unit Tests.Metrics;

// Testes das medidas dos corpos (CM.Metrics) vistas pela analise: linhas de codigo e complexidade
// ciclomatica de cada metodo. Os textos sao fontes Delphi em memoria.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, DUnitX.TestFramework,
  CM.Analyzer, CM.Metrics, Tests.Helpers;

type
  [TestFixture]
  TMetricsTests = class
  private
    function Find(const AMethods: TArray<TMethodInfo>; const AName: string): TMethodInfo;
    function Impl(const AInterface, AImplementation: string): TArray<TMethodInfo>;
  public
    [Test] procedure SimpleMethodsGetLinesAndBaseComplexity;
    [Test] procedure DecisionsAddToTheComplexity;
    [Test] procedure BooleanOperatorsCount;
    [Test] procedure ExceptionHandlersCount;
    [Test] procedure BlankLinesAndCommentsAreNotCounted;
    [Test] procedure StringsDoNotHideOrCreateDecisions;
    [Test] procedure KeywordsInsideCommentsDoNotCount;
    [Test] procedure DeclarationWithoutBodyHasNoMetrics;
    [Test] procedure OverloadsAreMeasuredSeparately;
    [Test] procedure NestedRoutineHasItsOwnComplexity;
    [Test] procedure OuterLinesIncludeTheNestedRoutine;
    [Test] procedure AnonymousMethodsCountForTheEnclosingRoutine;
    [Test] procedure ProceduralTypesAreNotRoutines;
    [Test] procedure ForwardAndExternalHaveNoBody;
    [Test] procedure TypeDeclaredInTheImplementationIsNotABody;
    [Test] procedure FreeRoutinesInAProgramAreMeasured;
    [Test] procedure CaseCountsOnceAndKeepsTheBlockBalanced;
    [Test] procedure UnbalancedTextDoesNotRaise;
    [Test] procedure MeasureRoutinesWorksOnCleanText;
    [Test] procedure ComplexityLevelsUseTheUsualLimits;
    [Test] procedure ParamsAndNestingLevelsUseTheirLimits;
    [Test] procedure MetricsTextIsEmptyWithoutABody;
    [Test] procedure MetricsTextPluralises;
    [Test] procedure ParametersAreCountedByName;
    [Test] procedure NestingCountsInnerBlocksOnly;
    [Test] procedure RepeatCountsAsABlock;
    [Test] procedure ShapeTextDescribesParametersAndNesting;
  end;

  [TestFixture]
  TMetricsRescanTests = class
  private
    FDir: TTempDir;
    FScan: TProjectScan;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ChangingOnlyTheBodyRefreshesTheMetrics;
    [Test] procedure SavingTheSameTextChangesNothing;
  end;

implementation

const
  ClassIntf =
    'type' + sLineBreak +
    '  TFoo = class' + sLineBreak +
    '    procedure Bar(A: Integer);' + sLineBreak +
    '    function Baz: Integer;' + sLineBreak +
    '  end;';

function TMetricsTests.Find(const AMethods: TArray<TMethodInfo>; const AName: string): TMethodInfo;
var
  M: TMethodInfo;
begin
  for M in AMethods do
    if M.Name = AName then
      Exit(M);
  Result := Default(TMethodInfo);
  Assert.Fail('metodo nao encontrado: ' + AName);
end;

function TMetricsTests.Impl(const AInterface, AImplementation: string): TArray<TMethodInfo>;
begin
  Result := Extract(WrapUnit(AInterface, AImplementation));
end;

procedure TMetricsTests.SimpleMethodsGetLinesAndBaseComplexity;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(A);' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'function TFoo.Baz: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := 1;' + sLineBreak +
    '  Inc(Result);' + sLineBreak +
    'end;');
  Assert.AreEqual(4, Find(M, 'TFoo.Bar').Lines);
  Assert.AreEqual(1, Find(M, 'TFoo.Bar').Complexity);
  Assert.AreEqual(5, Find(M, 'TFoo.Baz').Lines);
  Assert.AreEqual(1, Find(M, 'TFoo.Baz').Complexity);
end;

procedure TMetricsTests.DecisionsAddToTheComplexity;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'var I: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  if A > 0 then Writeln(A) else Writeln(0);' + sLineBreak +
    '  while A > 0 do Dec(A);' + sLineBreak +
    '  for I := 1 to 3 do Inc(A);' + sLineBreak +
    '  repeat Dec(A) until A < 0;' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer;' + sLineBreak +
    'begin end;');
  Assert.AreEqual(5, Find(M, 'TFoo.Bar').Complexity, '1 + if + while + for + repeat');
  Assert.AreEqual(1, Find(M, 'TFoo.Baz').Complexity);
end;

procedure TMetricsTests.BooleanOperatorsCount;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  if (A > 0) and (A < 9) or (A = 20) then Exit;' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer; begin Result := 0 end;');
  Assert.AreEqual(4, Find(M, 'TFoo.Bar').Complexity, '1 + if + and + or');
end;

procedure TMetricsTests.ExceptionHandlersCount;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  try' + sLineBreak +
    '    Writeln(A);' + sLineBreak +
    '  except' + sLineBreak +
    '    on E: EAbort do Exit;' + sLineBreak +
    '    on Exception do Writeln(0);' + sLineBreak +
    '  end;' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer; begin Result := 0 end;');
  Assert.AreEqual(3, Find(M, 'TFoo.Bar').Complexity, '1 + dois handlers');
  Assert.AreEqual(9, Find(M, 'TFoo.Bar').Lines);
end;

procedure TMetricsTests.BlankLinesAndCommentsAreNotCounted;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    '{ comentario' + sLineBreak +
    '  de varias' + sLineBreak +
    '  linhas }' + sLineBreak +
    'begin' + sLineBreak +
    sLineBreak +
    '  // so um comentario' + sLineBreak +
    '  (* outro' + sLineBreak +
    '     bloco *)' + sLineBreak +
    '  Writeln(A); // com codigo' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer; begin Result := 0 end;');
  Assert.AreEqual(4, Find(M, 'TFoo.Bar').Lines, 'cabecalho, begin, Writeln e end');
end;

procedure TMetricsTests.StringsDoNotHideOrCreateDecisions;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(''if while end begin; and or'');' + sLineBreak +
    '  Writeln(''it''''s'');' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer; begin Result := 0 end;');
  Assert.AreEqual(1, Find(M, 'TFoo.Bar').Complexity);
  Assert.AreEqual(5, Find(M, 'TFoo.Bar').Lines);
end;

procedure TMetricsTests.KeywordsInsideCommentsDoNotCount;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  // if x then begin' + sLineBreak +
    '  { while true do }' + sLineBreak +
    '  Writeln(A);' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer; begin Result := 0 end;');
  Assert.AreEqual(1, Find(M, 'TFoo.Bar').Complexity);
  Assert.AreEqual(4, Find(M, 'TFoo.Bar').Lines);
end;

procedure TMetricsTests.DeclarationWithoutBodyHasNoMetrics;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf, 'procedure TFoo.Bar(A: Integer);' + sLineBreak + 'begin end;');
  Assert.AreEqual(1, Find(M, 'TFoo.Bar').Complexity);
  Assert.AreEqual(0, Find(M, 'TFoo.Baz').Lines, 'declarado mas sem corpo nesta unit');
  Assert.AreEqual(0, Find(M, 'TFoo.Baz').Complexity);
end;

procedure TMetricsTests.OverloadsAreMeasuredSeparately;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(
    'procedure Show(A: Integer); overload;' + sLineBreak +
    'procedure Show(const S: string); overload;',
    'procedure Show(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  if A > 0 then Exit;' + sLineBreak +
    'end;' + sLineBreak +
    'procedure Show(const S: string);' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(S);' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'Show').Complexity, 'o primeiro overload');
  Assert.AreEqual(1, Find(M, 'Show(string)').Complexity, 'o segundo');
end;

procedure TMetricsTests.NestedRoutineHasItsOwnComplexity;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Outer;',
    'procedure Outer;' + sLineBreak +
    '  procedure Inner(X: Integer);' + sLineBreak +
    '  begin' + sLineBreak +
    '    if X > 0 then Exit;' + sLineBreak +
    '    while X < 0 do Inc(X);' + sLineBreak +
    '  end;' + sLineBreak +
    'begin' + sLineBreak +
    '  Inner(1);' + sLineBreak +
    'end;');
  Assert.AreEqual(1, Find(M, 'Outer').Complexity, 'sem as decisoes da rotina aninhada');
  Assert.AreEqual(3, Find(M, 'Inner').Complexity);
end;

procedure TMetricsTests.OuterLinesIncludeTheNestedRoutine;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Outer;',
    'procedure Outer;' + sLineBreak +
    '  procedure Inner;' + sLineBreak +
    '  begin' + sLineBreak +
    '    Writeln(1);' + sLineBreak +
    '  end;' + sLineBreak +
    'begin' + sLineBreak +
    '  Inner;' + sLineBreak +
    'end;');
  Assert.AreEqual(8, Find(M, 'Outer').Lines);
  Assert.AreEqual(4, Find(M, 'Inner').Lines);
end;

procedure TMetricsTests.AnonymousMethodsCountForTheEnclosingRoutine;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Run;',
    'procedure Run;' + sLineBreak +
    'var P: TProc;' + sLineBreak +
    'begin' + sLineBreak +
    '  P := procedure' + sLineBreak +
    '       begin' + sLineBreak +
    '         if Assigned(P) then Exit;' + sLineBreak +
    '       end;' + sLineBreak +
    '  P;' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'Run').Complexity);
  Assert.AreEqual(9, Find(M, 'Run').Lines, 'o corpo anonimo nao fecha o da rotina');
end;

procedure TMetricsTests.ProceduralTypesAreNotRoutines;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Run;',
    'type' + sLineBreak +
    '  TCallback = procedure(A: Integer);' + sLineBreak +
    '  TGetter = function: Integer;' + sLineBreak +
    '  TRef = reference to procedure;' + sLineBreak +
    'procedure Run;' + sLineBreak +
    'begin' + sLineBreak +
    '  if True then Exit;' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'Run').Complexity);
  Assert.AreEqual(4, Find(M, 'Run').Lines);
end;

procedure TMetricsTests.ForwardAndExternalHaveNoBody;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Real;',
    'procedure Fwd; forward;' + sLineBreak +
    'procedure Ext(A: Integer); external ''x.dll'' name ''Ext'';' + sLineBreak +
    'procedure Real;' + sLineBreak +
    'begin' + sLineBreak +
    '  if True then Exit;' + sLineBreak +
    'end;' + sLineBreak +
    'procedure Fwd;' + sLineBreak +
    'begin' + sLineBreak +
    '  Real;' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'Real').Complexity);
  Assert.AreEqual(4, Find(M, 'Real').Lines);
  Assert.AreEqual(4, Find(M, 'Fwd').Lines);
  Assert.AreEqual(0, Find(M, 'Ext').Lines);
end;

procedure TMetricsTests.TypeDeclaredInTheImplementationIsNotABody;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Pub;',
    'type' + sLineBreak +
    '  THelper = class' + sLineBreak +
    '    procedure Work(A: Integer);' + sLineBreak +
    '    function Calc: Integer;' + sLineBreak +
    '  end;' + sLineBreak +
    'procedure THelper.Work(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  if A > 1 then Exit;' + sLineBreak +
    'end;' + sLineBreak +
    'function THelper.Calc: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := 0;' + sLineBreak +
    'end;' + sLineBreak +
    'procedure Pub;' + sLineBreak +
    'begin' + sLineBreak +
    '  while True do Break;' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'THelper.Work').Complexity);
  Assert.AreEqual(4, Find(M, 'THelper.Work').Lines);
  Assert.AreEqual(1, Find(M, 'THelper.Calc').Complexity);
  Assert.AreEqual(4, Find(M, 'THelper.Calc').Lines);
  Assert.AreEqual(2, Find(M, 'Pub').Complexity);
end;

procedure TMetricsTests.FreeRoutinesInAProgramAreMeasured;
var
  M: TArray<TMethodInfo>;
begin
  M := Extract(
    'program P;' + sLineBreak +
    'procedure Hello(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  if A > 0 then Writeln(A);' + sLineBreak +
    'end;' + sLineBreak +
    'begin' + sLineBreak +
    '  Hello(1);' + sLineBreak +
    'end.');
  Assert.AreEqual(2, Find(M, 'Hello').Complexity);
  Assert.AreEqual(4, Find(M, 'Hello').Lines);
end;

procedure TMetricsTests.CaseCountsOnceAndKeepsTheBlockBalanced;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure One; procedure Two;',
    'procedure One;' + sLineBreak +
    'begin' + sLineBreak +
    '  case 1 of' + sLineBreak +
    '    1: Writeln(1);' + sLineBreak +
    '    2: begin Writeln(2); end;' + sLineBreak +
    '  else Writeln(0);' + sLineBreak +
    '  end;' + sLineBreak +
    'end;' + sLineBreak +
    'procedure Two;' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(2);' + sLineBreak +
    'end;');
  Assert.AreEqual(2, Find(M, 'One').Complexity);
  Assert.AreEqual(8, Find(M, 'One').Lines);
  Assert.AreEqual(4, Find(M, 'Two').Lines, 'o case nao desequilibrou o fim da rotina');
end;

procedure TMetricsTests.UnbalancedTextDoesNotRaise;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl('procedure Broken;',
    'procedure Broken;' + sLineBreak +
    'begin' + sLineBreak +
    '  if A then begin');
  Assert.AreEqual(0, Find(M, 'Broken').Lines, 'corpo por fechar: sem medida');
end;

procedure TMetricsTests.MeasureRoutinesWorksOnCleanText;
var
  L: TList<TRoutineMetric>;
begin
  L := TList<TRoutineMetric>.Create;
  try
    MeasureRoutines('procedure A;' + #10 + 'begin' + #10 + '  if X then Y;' + #10 + 'end;' + #10, L);
    Assert.AreEqual<NativeInt>(1, L.Count);
    Assert.AreEqual('procedure A', L[0].Header);
    Assert.AreEqual(4, L[0].Lines);
    Assert.AreEqual(2, L[0].Complexity);
    L.Clear;
    MeasureRoutines('', L);
    Assert.AreEqual<NativeInt>(0, L.Count);
  finally
    L.Free;
  end;
end;

procedure TMetricsTests.ComplexityLevelsUseTheUsualLimits;
begin
  Assert.AreEqual(Ord(cxNone), Ord(ComplexityLevel(0)));
  Assert.AreEqual(Ord(cxLow), Ord(ComplexityLevel(1)));
  Assert.AreEqual(Ord(cxLow), Ord(ComplexityLevel(10)));
  Assert.AreEqual(Ord(cxModerate), Ord(ComplexityLevel(11)));
  Assert.AreEqual(Ord(cxModerate), Ord(ComplexityLevel(20)));
  Assert.AreEqual(Ord(cxHigh), Ord(ComplexityLevel(21)));
end;

procedure TMetricsTests.ParamsAndNestingLevelsUseTheirLimits;
begin
  Assert.AreEqual(Ord(cxNone), Ord(ParamsLevel(0)));
  Assert.AreEqual(Ord(cxLow), Ord(ParamsLevel(4)));
  Assert.AreEqual(Ord(cxModerate), Ord(ParamsLevel(5)));
  Assert.AreEqual(Ord(cxModerate), Ord(ParamsLevel(7)));
  Assert.AreEqual(Ord(cxHigh), Ord(ParamsLevel(8)));
  Assert.AreEqual(Ord(cxNone), Ord(NestingLevel(0)));
  Assert.AreEqual(Ord(cxLow), Ord(NestingLevel(3)));
  Assert.AreEqual(Ord(cxModerate), Ord(NestingLevel(4)));
  Assert.AreEqual(Ord(cxModerate), Ord(NestingLevel(5)));
  Assert.AreEqual(Ord(cxHigh), Ord(NestingLevel(6)));
end;

procedure TMetricsTests.MetricsTextIsEmptyWithoutABody;
begin
  Assert.AreEqual('', MetricsText(0, 0));
end;

procedure TMetricsTests.MetricsTextPluralises;
begin
  Assert.AreEqual('1 linha · complexidade 1', MetricsText(1, 1));
  Assert.AreEqual('42 linhas · complexidade 7', MetricsText(42, 7));
end;

procedure TMetricsTests.ParametersAreCountedByName;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(
    'type' + sLineBreak +
    '  TFoo = class' + sLineBreak +
    '    procedure A;' + sLineBreak +
    '    procedure B(X: Integer);' + sLineBreak +
    '    procedure C(X, Y: Integer; var Z: string; const W: array of Integer; P: TProc<Integer, string> = nil);' + sLineBreak +
    '  end;',
    'procedure TFoo.A; begin end;' + sLineBreak +
    'procedure TFoo.B(X: Integer); begin end;' + sLineBreak +
    'procedure TFoo.C(X, Y: Integer; var Z: string; const W: array of Integer; P: TProc<Integer, string> = nil);' + sLineBreak +
    'begin' + sLineBreak +
    'end;');
  Assert.AreEqual(0, Find(M, 'TFoo.A').ParamCount);
  Assert.AreEqual(1, Find(M, 'TFoo.B').ParamCount);
  Assert.AreEqual(5, Find(M, 'TFoo.C').ParamCount);
end;

procedure TMetricsTests.NestingCountsInnerBlocksOnly;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  Writeln(A);' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  if Result > 0 then' + sLineBreak +
    '  begin' + sLineBreak +
    '    try' + sLineBreak +
    '      case Result of' + sLineBreak +
    '        1: Inc(Result);' + sLineBreak +
    '      end;' + sLineBreak +
    '    finally' + sLineBreak +
    '      Dec(Result);' + sLineBreak +
    '    end;' + sLineBreak +
    '  end;' + sLineBreak +
    'end;');
  Assert.AreEqual(0, Find(M, 'TFoo.Bar').Nesting);
  Assert.AreEqual(3, Find(M, 'TFoo.Baz').Nesting);
end;

procedure TMetricsTests.RepeatCountsAsABlock;
var
  M: TArray<TMethodInfo>;
begin
  M := Impl(ClassIntf,
    'procedure TFoo.Bar(A: Integer);' + sLineBreak +
    'begin' + sLineBreak +
    '  repeat' + sLineBreak +
    '    Inc(A);' + sLineBreak +
    '  until A > 3;' + sLineBreak +
    '  Writeln(A);' + sLineBreak +
    'end;' + sLineBreak +
    'function TFoo.Baz: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    'end;');
  Assert.AreEqual(1, Find(M, 'TFoo.Bar').Nesting);
  Assert.AreEqual(7, Find(M, 'TFoo.Bar').Lines, 'o until nao termina o corpo');
end;

procedure TMetricsTests.ShapeTextDescribesParametersAndNesting;
begin
  Assert.AreEqual('', ShapeText(0, 2, 1));
  Assert.AreEqual('sem parâmetros · aninhamento 0', ShapeText(5, 0, 0));
  Assert.AreEqual('1 parâmetro · aninhamento 2', ShapeText(5, 1, 2));
  Assert.AreEqual('3 parâmetros · aninhamento 1', ShapeText(5, 3, 1));
end;

{ TMetricsRescanTests }

procedure TMetricsRescanTests.Setup;
begin
  FDir := TTempDir.Create;
  FDir.Write('a.pas', WrapUnit('procedure Run;',
    'procedure Run;' + sLineBreak + 'begin' + sLineBreak + '  Writeln(1);' + sLineBreak + 'end;'));
  FScan := ScanProject(FDir.Path, nil);
end;

procedure TMetricsRescanTests.TearDown;
begin
  FScan.Free;
  FDir.Free;
end;

procedure TMetricsRescanTests.ChangingOnlyTheBodyRefreshesTheMetrics;
begin
  Assert.AreEqual(4, FScan.Units[0].Methods[0].Lines);
  FDir.Write('a.pas', WrapUnit('procedure Run;',
    'procedure Run;' + sLineBreak + 'begin' + sLineBreak + '  if True then' + sLineBreak +
    '    Writeln(1);' + sLineBreak + 'end;'));
  Assert.AreEqual(Ord(rcChanged), Ord(RescanFile(FScan, 'a.pas')));
  Assert.AreEqual(5, FScan.Units[0].Methods[0].Lines);
  Assert.AreEqual(2, FScan.Units[0].Methods[0].Complexity);
end;

procedure TMetricsRescanTests.SavingTheSameTextChangesNothing;
begin
  FDir.Write('a.pas', WrapUnit('procedure Run;',
    'procedure Run;' + sLineBreak + 'begin' + sLineBreak + '  Writeln(1);' + sLineBreak + 'end;'));
  Assert.AreEqual(Ord(rcNone), Ord(RescanFile(FScan, 'a.pas')));
end;

end.
