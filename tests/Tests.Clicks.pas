unit Tests.Clicks;

// Testes do detector de duplo clique (CM.Clicks) e da escolha da fonte do codigo (CM.Theme).

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Clicks, CM.Theme;

type
  [TestFixture]
  TClicksTests = class
  public
    [Test] procedure TheFirstClickIsNeverADoubleClick;
    [Test] procedure TwoQuickClicksOnTheSameTargetAreADoubleClick;
    [Test] procedure ADoubleClickIsSpentSoTheThirdStartsAgain;
    [Test] procedure ClicksOnDifferentTargetsAreNotADoubleClick;
    [Test] procedure ASlowSecondClickIsNotADoubleClick;
    [Test] procedure ResetForgetsTheLastClick;
    [Test] procedure AnEmptyKeyNeverMatches;
  end;

  [TestFixture]
  TCodeFontTests = class
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ThereIsAlwaysACodeFont;
    [Test] procedure ChoicesAreInstalledFontsWithoutRepeats;
    [Test] procedure AnInstalledChoiceIsUsed;
    [Test] procedure UnknownOrEmptyFallsBackToTheFirstChoice;
  end;

implementation

procedure TClicksTests.TheFirstClickIsNeverADoubleClick;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  Assert.IsFalse(T.Click('a'));
end;

procedure TClicksTests.TwoQuickClicksOnTheSameTargetAreADoubleClick;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('a');
  Assert.IsTrue(T.Click('a'));
end;

procedure TClicksTests.ADoubleClickIsSpentSoTheThirdStartsAgain;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('a');
  Assert.IsTrue(T.Click('a'));
  Assert.IsFalse(T.Click('a'), 'o terceiro clique e o primeiro de outro duplo clique');
  Assert.IsTrue(T.Click('a'));
end;

procedure TClicksTests.ClicksOnDifferentTargetsAreNotADoubleClick;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('a');
  Assert.IsFalse(T.Click('b'));
  Assert.IsTrue(T.Click('b'), 'o segundo clique em b ja conta');
end;

procedure TClicksTests.ASlowSecondClickIsNotADoubleClick;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('a');
  Sleep(DoubleClickMs + 80);
  Assert.IsFalse(T.Click('a'));
end;

procedure TClicksTests.ResetForgetsTheLastClick;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('a');
  T.Reset;
  Assert.IsFalse(T.Click('a'));
end;

procedure TClicksTests.AnEmptyKeyNeverMatches;
var
  T: TDoubleClickTracker;
begin
  T.Reset;
  T.Click('');
  Assert.IsFalse(T.Click(''));
end;

{ TCodeFontTests }

procedure TCodeFontTests.Setup;
begin
  SetCodeFont('');
end;

procedure TCodeFontTests.TearDown;
begin
  SetCodeFont('');
end;

procedure TCodeFontTests.ThereIsAlwaysACodeFont;
begin
  Assert.IsTrue(CodeFont <> '');
end;

procedure TCodeFontTests.ChoicesAreInstalledFontsWithoutRepeats;
var
  C: TArray<string>;
  I, J: Integer;
begin
  C := CodeFontChoices;
  for I := 0 to High(C) do
    for J := I + 1 to High(C) do
      Assert.AreNotEqual(C[I], C[J]);
end;

procedure TCodeFontTests.AnInstalledChoiceIsUsed;
var
  C: TArray<string>;
begin
  C := CodeFontChoices;
  if Length(C) < 2 then
    Exit;                          // so ha uma fonte para escolher nesta maquina
  SetCodeFont(C[1]);
  Assert.AreEqual(C[1], CodeFont);
  SetCodeFont(LowerCase(C[0]));
  Assert.AreEqual(C[0], CodeFont, 'sem distinguir maiusculas');
end;

procedure TCodeFontTests.UnknownOrEmptyFallsBackToTheFirstChoice;
var
  C: TArray<string>;
begin
  C := CodeFontChoices;
  if Length(C) = 0 then
    Exit;
  SetCodeFont('Fonte Que Nao Existe');
  Assert.AreEqual(C[0], CodeFont);
  SetCodeFont('');
  Assert.AreEqual(C[0], CodeFont);
end;

initialization
  TDUnitX.RegisterTestFixture(TClicksTests);
  TDUnitX.RegisterTestFixture(TCodeFontTests);

end.
