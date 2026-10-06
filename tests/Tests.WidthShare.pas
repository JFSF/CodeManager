unit Tests.WidthShare;

// Testes da repartição da largura de uma linha de botoes (CM.WidthShare).

interface

uses
  System.SysUtils, System.Math, DUnitX.TestFramework, CM.WidthShare;

type
  [TestFixture]
  TWidthShareTests = class
  private
    function Sum(const AWidths: TArray<Single>): Single;
  public
    [Test] procedure EmptyRowHasNoWidths;
    [Test] procedure ButtonsThatFitShareTheWidthEqually;
    [Test] procedure ALongButtonKeepsItsNaturalWidthAndTheOthersShareTheRest;
    [Test] procedure SharingALongButtonCanMakeAnotherOneLong;
    [Test] procedure IconOnlyButtonsTakeAnEqualShare;
    [Test] procedure WhenNothingFitsItFallsBackToAnEqualSplit;
    [Test] procedure WidthsAlwaysAddUpToTheAvailableWidth;
  end;

implementation

function TWidthShareTests.Sum(const AWidths: TArray<Single>): Single;
var
  W: Single;
begin
  Result := 0;
  for W in AWidths do
    Result := Result + W;
end;

procedure TWidthShareTests.EmptyRowHasNoWidths;
begin
  Assert.AreEqual<NativeInt>(0, Length(ShareWidths(100, nil)));
end;

procedure TWidthShareTests.ButtonsThatFitShareTheWidthEqually;
var
  W: TArray<Single>;
begin
  W := ShareWidths(300, [80, 90, 100]);
  Assert.AreEqual(100.0, W[0], 0.01);
  Assert.AreEqual(100.0, W[1], 0.01);
  Assert.AreEqual(100.0, W[2], 0.01);
end;

procedure TWidthShareTests.ALongButtonKeepsItsNaturalWidthAndTheOthersShareTheRest;
var
  W: TArray<Single>;
begin
  // duas colunas de 143: o botao de 150 nao cabia; o outro (109) fica com o que sobra (136)
  W := ShareWidths(286, [109, 150]);
  Assert.AreEqual(150.0, W[1], 0.01, 'o botao comprido fica com a largura natural');
  Assert.AreEqual(136.0, W[0], 0.01);
end;

procedure TWidthShareTests.SharingALongButtonCanMakeAnotherOneLong;
var
  W: TArray<Single>;
begin
  // a parte igual e 100; o 130 passa a longo e a parte dos outros desce para 85, o que ja nao chega ao 90
  W := ShareWidths(300, [130, 90, 40]);
  Assert.AreEqual(130.0, W[0], 0.01);
  Assert.AreEqual(90.0, W[1], 0.01);
  Assert.AreEqual(80.0, W[2], 0.01);
  Assert.AreEqual(300.0, Sum(W), 0.01);
end;

procedure TWidthShareTests.IconOnlyButtonsTakeAnEqualShare;
var
  W: TArray<Single>;
begin
  // barra do Grafo: dois botoes de texto e dois so com icone (natural 0)
  W := ShareWidths(368, [116, 111, 0, 0]);
  Assert.AreEqual(116.0, W[0], 0.01);
  Assert.AreEqual(111.0, W[1], 0.01);
  Assert.AreEqual(70.5, W[2], 0.01);
  Assert.AreEqual(70.5, W[3], 0.01);
end;

procedure TWidthShareTests.WhenNothingFitsItFallsBackToAnEqualSplit;
var
  W: TArray<Single>;
begin
  W := ShareWidths(200, [150, 170]);
  Assert.AreEqual(100.0, W[0], 0.01);
  Assert.AreEqual(100.0, W[1], 0.01);
end;

procedure TWidthShareTests.WidthsAlwaysAddUpToTheAvailableWidth;
var
  Cases: array[0..5] of TArray<Single>;
  Avail: Single;
  I, K: Integer;
const
  Widths: array[0..3] of Single = (120, 286, 368, 520);
begin
  Cases[0] := [80, 90, 100];
  Cases[1] := [109, 150];
  Cases[2] := [130, 90, 40];
  Cases[3] := [116, 111, 0, 0];
  Cases[4] := [150, 170];
  Cases[5] := [0];
  for I := 0 to High(Cases) do
    for K := 0 to High(Widths) do
    begin
      Avail := Widths[K];
      Assert.AreEqual(Double(Avail), Double(Sum(ShareWidths(Avail, Cases[I]))), 0.05,
        Format('caso %d, largura %.0f', [I, Avail]));
    end;
end;

end.
