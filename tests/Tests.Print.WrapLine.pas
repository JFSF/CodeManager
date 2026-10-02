unit Tests.Print.WrapLine;

// Testes da quebra de linha usada na impressao (CM.Print.WrapLine): a mesma logica que particiona
// uma linha longa da arvore em varias linhas de impressao, preferindo quebrar num espaco.

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Print, Tests.Helpers;

type
  [TestFixture]
  TWrapLineTests = class
  public
    [Test] procedure TextThatFitsStaysOnOneLine;
    [Test] procedure EmptyTextProducesOneEmptyLine;
    [Test] procedure ExactFitStaysOnOneLine;
    [Test] procedure OneCharacterOverFlowsToASecondLine;
    [Test] procedure BreaksAtTheLastSpaceWithinTheLimit;
    [Test] procedure ContinuationLinesUseTheContPrefix;
    [Test] procedure NoSpacesForcesAHardBreak;
    [Test] procedure LeadingSpaceOfTheNextChunkIsTrimmed;
    [Test] procedure AvailableWidthNeverDropsBelowEightEvenWithALongPrefix;
    [Test] procedure ManyWordsWrapAcrossSeveralLines;
    [Test] procedure PrefixCountsAgainstTheFirstLinesBudget;
  end;

implementation

{ TWrapLineTests }

procedure TWrapLineTests.TextThatFitsStaysOnOneLine;
begin
  Assert.AreEqual('> abc', Join(WrapLine('> ', '  ', 'abc', 80)));
end;

procedure TWrapLineTests.EmptyTextProducesOneEmptyLine;
begin
  Assert.AreEqual('> ', Join(WrapLine('> ', '  ', '', 80)));
end;

procedure TWrapLineTests.ExactFitStaysOnOneLine;
begin
  // prefixo '> ' (2) + 8 caracteres = 10 = AMaxChars: cabe exactamente, sem quebrar
  Assert.AreEqual('> 12345678', Join(WrapLine('> ', '  ', '12345678', 10)));
end;

procedure TWrapLineTests.OneCharacterOverFlowsToASecondLine;
var
  Lines: TArray<string>;
begin
  // prefixo '> ' (2) deixa 8 de largura; 9 caracteres nao cabem, so 8 + o resto
  Lines := WrapLine('> ', '  ', '123456789', 10);
  Assert.AreEqual<NativeInt>(2, Length(Lines));
  Assert.AreEqual('> 12345678', Lines[0]);
  Assert.AreEqual('  9', Lines[1]);
end;

procedure TWrapLineTests.BreaksAtTheLastSpaceWithinTheLimit;
var
  Lines: TArray<string>;
begin
  // 'procedure Foo(A: Integer);' nao cabe em 12: quebra no ultimo espaco dentro do limite
  Lines := WrapLine('', '  ', 'procedure Foo(A: Integer);', 12);
  Assert.AreEqual<NativeInt>(3, Length(Lines));
  Assert.AreEqual('procedure', Lines[0]);
  Assert.AreEqual('  Foo(A:', Lines[1]);
  Assert.AreEqual('  Integer);', Lines[2]);
end;

procedure TWrapLineTests.ContinuationLinesUseTheContPrefix;
var
  Lines: TArray<string>;
begin
  Lines := WrapLine('+-- ', '|   ', 'uma linha bastante mais comprida do que cabe', 20);
  Assert.IsTrue(Lines[0].StartsWith('+-- '));
  Assert.IsTrue(Lines[1].StartsWith('|   '));
  Assert.IsTrue(Lines[2].StartsWith('|   '));
end;

procedure TWrapLineTests.NoSpacesForcesAHardBreak;
var
  Lines: TArray<string>;
begin
  // sem espacos: 'Cut < 2' cai para a quebra a direito (Avail), sem contar com o prefixo
  Lines := WrapLine('', '', StringOfChar('x', 25), 10);
  Assert.AreEqual<NativeInt>(3, Length(Lines));
  Assert.AreEqual(StringOfChar('x', 10), Lines[0]);
  Assert.AreEqual(StringOfChar('x', 10), Lines[1]);
  Assert.AreEqual(StringOfChar('x', 5), Lines[2]);
end;

procedure TWrapLineTests.LeadingSpaceOfTheNextChunkIsTrimmed;
var
  Lines: TArray<string>;
begin
  Lines := WrapLine('', '  ', 'aaaaaaaaaa bbbbbbbbbb', 12);
  Assert.AreEqual('aaaaaaaaaa', Lines[0]);
  Assert.AreEqual('  bbbbbbbbbb', Lines[1], 'sem espaco a mais depois do prefixo de continuacao');
end;

procedure TWrapLineTests.AvailableWidthNeverDropsBelowEightEvenWithALongPrefix;
var
  Lines: TArray<string>;
  LongPrefix: string;
begin
  // prefixo (20) > AMaxChars (10): Avail usa o minimo de 8, nao um valor negativo
  LongPrefix := StringOfChar('>', 20);
  Lines := WrapLine(LongPrefix, LongPrefix, StringOfChar('x', 12), 10);
  Assert.AreEqual<NativeInt>(2, Length(Lines));
  Assert.AreEqual(LongPrefix + StringOfChar('x', 8), Lines[0]);
  Assert.AreEqual(LongPrefix + StringOfChar('x', 4), Lines[1]);
end;

procedure TWrapLineTests.ManyWordsWrapAcrossSeveralLines;
var
  Lines: TArray<string>;
  Rejoined: string;
  L: string;
begin
  Lines := WrapLine('', '', 'um dois tres quatro cinco seis sete oito nove dez', 12);
  Assert.IsTrue(Length(Lines) >= 4);
  Rejoined := '';
  for L in Lines do
    Rejoined := Rejoined + L + ' ';
  Rejoined := Rejoined.Replace('  ', ' ').Trim;
  Assert.AreEqual('um dois tres quatro cinco seis sete oito nove dez', Rejoined);
end;

procedure TWrapLineTests.PrefixCountsAgainstTheFirstLinesBudget;
var
  ShortLines, LongLines: TArray<string>;
  LongPrefix: string;
begin
  // um prefixo persistente e comprido (ex.: guias de uma arvore muito aninhada) come largura em
  // TODAS as linhas, nao so na primeira, e por isso precisa de mais linhas para o mesmo texto
  LongPrefix := StringOfChar('>', 15) + ' ';   // 16 caracteres
  ShortLines := WrapLine('> ', '  ', StringOfChar('x', 20), 20);
  LongLines := WrapLine(LongPrefix, LongPrefix, StringOfChar('x', 20), 20);
  Assert.AreEqual<NativeInt>(2, Length(ShortLines));
  Assert.AreEqual<NativeInt>(3, Length(LongLines));
end;

initialization
  TDUnitX.RegisterTestFixture(TWrapLineTests);

end.
