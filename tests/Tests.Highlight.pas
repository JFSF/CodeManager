unit Tests.Highlight;

// Testes de CM.Highlight: linhas, pedacos (palavras reservadas, textos, comentarios, numeros, directivas)
// e a localizacao da linha onde uma rotina comeca.

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, CM.Highlight;

type
  [TestFixture]
  THighlightTests = class
  private
    function KindsOf(const ALine: TCodeLine): string;
    function Slice(const ALine: TCodeLine; AIndex: Integer): string;
  public
    [Test] procedure SplitsLinesOfAnyEndingAndDropsTheTrailingOne;
    [Test] procedure TabsBecomeSpaces;
    [Test] procedure KeywordsAreCaseInsensitive;
    [Test] procedure MembersAfterADotAreNotKeywords;
    [Test] procedure StringsKeepDoubledQuotes;
    [Test] procedure CharCodesCountAsStrings;
    [Test] procedure LineCommentsRunToTheEnd;
    [Test] procedure BraceCommentsSpanLines;
    [Test] procedure ParenStarCommentsSpanLines;
    [Test] procedure CompilerDirectivesAreNotComments;
    [Test] procedure NumbersIncludingHexAndFloats;
    [Test] procedure RangesAreNotFloats;
    [Test] procedure KeywordsInsideStringsAndCommentsAreNotMarked;
    [Test] procedure UnterminatedStringEndsWithTheLine;
    [Test] procedure LongestLineIsMeasuredAfterTabExpansion;
    [Test] procedure EmptyTextHasOneEmptyLine;
    [Test] procedure FindsAMethodDefinitionInTheImplementation;
    [Test] procedure FindsAFreeRoutineAtItsLastOccurrence;
    [Test] procedure FallsBackToTheClassDeclaration;
    [Test] procedure ClassMethodsAndNestedOwnersAreFound;
    [Test] procedure CommentedOutHeadersAreIgnored;
    [Test] procedure UnknownRoutineIsNotFound;
  end;

implementation

const
  Sample =
    'unit U;' + sLineBreak +
    'interface' + sLineBreak +
    'type' + sLineBreak +
    '  TFoo = class' + sLineBreak +
    '    procedure Bar;' + sLineBreak +
    '    class function Make: TFoo;' + sLineBreak +
    '  end;' + sLineBreak +
    'procedure Free1;' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure TFoo.Bar;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'class function TFoo.Make: TFoo;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'procedure Free1;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    'end.';

function THighlightTests.KindsOf(const ALine: TCodeLine): string;
var
  S: TSynSpan;
begin
  Result := '';
  for S in ALine.Spans do
    Result := Result + Copy('PKSCND', Ord(S.Kind) + 1, 1);
end;

function THighlightTests.Slice(const ALine: TCodeLine; AIndex: Integer): string;
begin
  Result := Copy(ALine.Text, ALine.Spans[AIndex].Start, ALine.Spans[AIndex].Len);
end;

procedure THighlightTests.SplitsLinesOfAnyEndingAndDropsTheTrailingOne;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('a'#13#10'b'#10'c'#13'd'#13#10);
  try
    Assert.AreEqual(4, D.Count);
    Assert.AreEqual('c', D.Line(2).Text);
    Assert.AreEqual('d', D.Line(3).Text);
  finally
    D.Free;
  end;
end;

procedure THighlightTests.TabsBecomeSpaces;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create(#9'x');
  try
    Assert.AreEqual(StringOfChar(' ', TabWidth) + 'x', D.Line(0).Text);
  finally
    D.Free;
  end;
end;

procedure THighlightTests.KeywordsAreCaseInsensitive;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('BEGIN If x Then end;');
  try
    Assert.AreEqual('KKKK', KindsOf(D.Line(0)));
    Assert.AreEqual('BEGIN', Slice(D.Line(0), 0));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.MembersAfterADotAreNotKeywords;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('Obj.End := Self.Index;');
  try
    Assert.AreEqual('K', KindsOf(D.Line(0)), 'so o Self');
    Assert.AreEqual('Self', Slice(D.Line(0), 0));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.StringsKeepDoubledQuotes;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('x := ''it''''s'' + y;');
  try
    Assert.AreEqual('S', KindsOf(D.Line(0)));
    Assert.AreEqual('''it''''s''', Slice(D.Line(0), 0));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.CharCodesCountAsStrings;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('s := #13#10 + #$41;');
  try
    Assert.AreEqual('SSS', KindsOf(D.Line(0)));
    Assert.AreEqual('#13', Slice(D.Line(0), 0));
    Assert.AreEqual('#$41', Slice(D.Line(0), 2));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.LineCommentsRunToTheEnd;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('x := 1; // begin ''nope''');
  try
    Assert.AreEqual('NC', KindsOf(D.Line(0)));
    Assert.AreEqual('// begin ''nope''', Slice(D.Line(0), 1));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.BraceCommentsSpanLines;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('a { um' + sLineBreak + 'comentario begin' + sLineBreak + 'fim } begin');
  try
    Assert.AreEqual('C', KindsOf(D.Line(0)));
    Assert.AreEqual('C', KindsOf(D.Line(1)), 'a linha do meio e toda comentario');
    Assert.AreEqual('CK', KindsOf(D.Line(2)));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.ParenStarCommentsSpanLines;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('(* abre' + sLineBreak + 'if *) if');
  try
    Assert.AreEqual('C', KindsOf(D.Line(0)));
    Assert.AreEqual('CK', KindsOf(D.Line(1)));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.CompilerDirectivesAreNotComments;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('{$IFDEF DEBUG} x {$ENDIF}');
  try
    Assert.AreEqual('DD', KindsOf(D.Line(0)));
    Assert.AreEqual('{$IFDEF DEBUG}', Slice(D.Line(0), 0));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.NumbersIncludingHexAndFloats;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('a := 42 + $FF + 1.5e-3 + 2E8 + 1_000;');
  try
    Assert.AreEqual('NNNNN', KindsOf(D.Line(0)));
    Assert.AreEqual('1.5e-3', Slice(D.Line(0), 2));
    Assert.AreEqual('1_000', Slice(D.Line(0), 4));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.RangesAreNotFloats;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('a[1..5]');
  try
    Assert.AreEqual('NN', KindsOf(D.Line(0)));
    Assert.AreEqual('1', Slice(D.Line(0), 0));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.KeywordsInsideStringsAndCommentsAreNotMarked;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('s := ''begin end'' { if } ;');
  try
    Assert.AreEqual('SC', KindsOf(D.Line(0)));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.UnterminatedStringEndsWithTheLine;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('s := ''abc' + sLineBreak + 'begin');
  try
    Assert.AreEqual('S', KindsOf(D.Line(0)));
    Assert.AreEqual('K', KindsOf(D.Line(1)), 'a linha seguinte volta ao normal');
  finally
    D.Free;
  end;
end;

procedure THighlightTests.LongestLineIsMeasuredAfterTabExpansion;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('ab' + sLineBreak + #9#9'xyz');
  try
    Assert.AreEqual(2 * TabWidth + 3, D.LongestLine);
  finally
    D.Free;
  end;
end;

procedure THighlightTests.EmptyTextHasOneEmptyLine;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('');
  try
    Assert.AreEqual(1, D.Count);
    Assert.AreEqual('', D.Line(0).Text);
    Assert.AreEqual<NativeInt>(0, Length(D.Line(0).Spans));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.FindsAMethodDefinitionInTheImplementation;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create(Sample);
  try
    Assert.AreEqual(9, FindRoutineLine(D, 'TFoo', 'Bar'), 'linha de "procedure TFoo.Bar;", e nao a da classe');
    Assert.AreEqual(9, FindRoutineLine(D, 'tfoo', 'bar'), 'sem distinguir maiusculas');
  finally
    D.Free;
  end;
end;

procedure THighlightTests.FindsAFreeRoutineAtItsLastOccurrence;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create(Sample);
  try
    Assert.AreEqual(15, FindRoutineLine(D, '', 'Free1'), 'a definicao, nao a declaracao na interface');
  finally
    D.Free;
  end;
end;

procedure THighlightTests.FallsBackToTheClassDeclaration;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('type' + sLineBreak + '  TFoo = class' + sLineBreak + '    procedure Only;' + sLineBreak + '  end;');
  try
    Assert.AreEqual(2, FindRoutineLine(D, 'TFoo', 'Only'));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.ClassMethodsAndNestedOwnersAreFound;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create(Sample + sLineBreak + 'procedure TOuter.TInner.Deep;' + sLineBreak + 'begin end;');
  try
    Assert.AreEqual(12, FindRoutineLine(D, 'TFoo', 'Make'), 'class function');
    Assert.AreEqual(19, FindRoutineLine(D, 'TInner', 'Deep'), 'dono aninhado');
  finally
    D.Free;
  end;
end;

procedure THighlightTests.CommentedOutHeadersAreIgnored;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create('// procedure TFoo.Bar;' + sLineBreak + '{ procedure TFoo.Bar; }' + sLineBreak + 'procedure TFoo.Bar;');
  try
    Assert.AreEqual(2, FindRoutineLine(D, 'TFoo', 'Bar'));
  finally
    D.Free;
  end;
end;

procedure THighlightTests.UnknownRoutineIsNotFound;
var
  D: TCodeDoc;
begin
  D := TCodeDoc.Create(Sample);
  try
    Assert.AreEqual(-1, FindRoutineLine(D, 'TFoo', 'Nada'));
    Assert.AreEqual(-1, FindRoutineLine(D, '', ''));
    Assert.AreEqual(-1, FindRoutineLine(nil, 'TFoo', 'Bar'));
  finally
    D.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THighlightTests);

end.
