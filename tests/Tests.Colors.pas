unit Tests.Colors;

// Testes de CM.Colors: ler e escrever cores em hexadecimal, HSL, contraste e a derivacao das cores do tema a partir
// da cor de destaque escolhida.

interface

uses
  System.SysUtils, System.Math, DUnitX.TestFramework, CM.Colors;

type
  [TestFixture]
  TColorsTests = class
  public
    [Test] procedure HexColorsAcceptWithAndWithoutHashAndShortForm;
    [Test] procedure HexColorsRejectGarbage;
    [Test] procedure ColorToHexIgnoresAlphaAndUsesUpperCase;
    [Test] procedure HslRoundTripsTheCommonColors;
    [Test] procedure GreysHaveNoSaturation;
    [Test] procedure MixingEndpointsGivesTheEnds;
    [Test] procedure ContrastOfBlackAndWhiteIs21;
    [Test] procedure ContrastIsSymmetric;
    [Test] procedure LightAccentsAlwaysReadWithWhiteText;
    [Test] procedure DarkAccentsAlwaysReadOnTheSurface;
    [Test] procedure DerivedSetsKeepTheHue;
    [Test] procedure OnAccentIsTheBestOfBlackAndWhite;
    [Test] procedure PresetsAreValidAndDistinct;
    [Test] procedure ExtremeColorsDoNotBreakTheDerivation;
  end;

implementation

const
  LightSurface = $FFFFFFFF;
  DarkSurface = $FF1B1F22;

procedure TColorsTests.HexColorsAcceptWithAndWithoutHashAndShortForm;
var
  C: Cardinal;
begin
  Assert.IsTrue(ParseHexColor('#23705F', C));
  Assert.AreEqual<Cardinal>($FF23705F, C);
  Assert.IsTrue(ParseHexColor('23705f', C));
  Assert.AreEqual<Cardinal>($FF23705F, C);
  Assert.IsTrue(ParseHexColor('  #2A6  ', C));
  Assert.AreEqual<Cardinal>($FF22AA66, C, 'a forma curta duplica cada digito');
end;

procedure TColorsTests.HexColorsRejectGarbage;
var
  C: Cardinal;
begin
  Assert.IsFalse(ParseHexColor('', C));
  Assert.IsFalse(ParseHexColor('#', C));
  Assert.IsFalse(ParseHexColor('#12345', C));
  Assert.IsFalse(ParseHexColor('#1234567', C));
  Assert.IsFalse(ParseHexColor('#GGGGGG', C));
  Assert.IsFalse(ParseHexColor('verde', C));
  Assert.AreEqual<Cardinal>(0, C, 'em caso de falha o valor fica a zero');
end;

procedure TColorsTests.ColorToHexIgnoresAlphaAndUsesUpperCase;
begin
  Assert.AreEqual('#23705F', ColorToHex($FF23705F));
  Assert.AreEqual('#0A0B0C', ColorToHex($800A0B0C));
  Assert.AreEqual('#000000', ColorToHex($FF000000));
end;

procedure TColorsTests.HslRoundTripsTheCommonColors;
var
  C, Back: Cardinal;
  H, S, L: Double;
begin
  for C in [Cardinal($FF23705F), Cardinal($FF2563C9), Cardinal($FFC13F2F), Cardinal($FFFFFFFF), Cardinal($FF000000),
            Cardinal($FF7C4DCB), Cardinal($FFB85C0B)] do
  begin
    ColorToHsl(C, H, S, L);
    Back := HslToColor(H, S, L);
    Assert.AreEqual(ColorToHex(C), ColorToHex(Back), 'ida e volta de ' + ColorToHex(C));
  end;
end;

procedure TColorsTests.GreysHaveNoSaturation;
var
  H, S, L: Double;
begin
  ColorToHsl($FF808080, H, S, L);
  Assert.AreEqual(0.0, S, 0.0001);
  Assert.AreEqual(0.5, L, 0.01);
end;

procedure TColorsTests.MixingEndpointsGivesTheEnds;
begin
  Assert.AreEqual<Cardinal>($FF102030, MixColors($FF102030, $FFFFFFFF, 0));
  Assert.AreEqual<Cardinal>($FFFFFFFF, MixColors($FF102030, $FFFFFFFF, 1));
  Assert.AreEqual<Cardinal>($FF808080, MixColors($FF000000, $FFFFFFFF, 0.5));
  Assert.AreEqual<Cardinal>($FFFFFFFF, MixColors($FF000000, $FFFFFFFF, 5), 'a quantidade limita-se a 1');
end;

procedure TColorsTests.ContrastOfBlackAndWhiteIs21;
begin
  Assert.AreEqual(21.0, ContrastRatio($FF000000, $FFFFFFFF), 0.01);
  Assert.AreEqual(1.0, ContrastRatio($FF336699, $FF336699), 0.0001);
end;

procedure TColorsTests.ContrastIsSymmetric;
begin
  Assert.AreEqual(ContrastRatio($FF23705F, $FFFFFFFF), ContrastRatio($FFFFFFFF, $FF23705F), 0.0001);
end;

procedure TColorsTests.LightAccentsAlwaysReadWithWhiteText;
var
  I: Integer;
  S: TAccentSet;
begin
  for I := 0 to AccentPresetCount - 1 do
  begin
    S := DeriveAccent(AccentPresetColors[I], False, LightSurface);
    Assert.IsTrue(ContrastRatio(S.Accent, $FFFFFFFF) >= 4.5, AccentPresetNames[I]);
  end;
  // uma cor clara e puxada para baixo ate se ler
  S := DeriveAccent($FFFFEE00, False, LightSurface);
  Assert.IsTrue(ContrastRatio(S.Accent, $FFFFFFFF) >= 4.5, 'amarelo');
end;

procedure TColorsTests.DarkAccentsAlwaysReadOnTheSurface;
var
  I: Integer;
  S: TAccentSet;
begin
  for I := 0 to AccentPresetCount - 1 do
  begin
    S := DeriveAccent(AccentPresetColors[I], True, DarkSurface);
    Assert.IsTrue(ContrastRatio(S.Accent, DarkSurface) >= 4.5, AccentPresetNames[I]);
  end;
  S := DeriveAccent($FF101080, True, DarkSurface);
  Assert.IsTrue(ContrastRatio(S.Accent, DarkSurface) >= 4.5, 'azul escuro sobe de luminosidade');
end;

procedure TColorsTests.DerivedSetsKeepTheHue;
var
  H0, S0, L0, H1, S1, L1: Double;
  Set1: TAccentSet;
begin
  ColorToHsl($FF2563C9, H0, S0, L0);
  Set1 := DeriveAccent($FF2563C9, False, LightSurface);
  ColorToHsl(Set1.Strong, H1, S1, L1);
  Assert.AreEqual(H0, H1, 4.0, 'a variante forte continua azul');
  Assert.IsTrue(L1 < L0, 'e mais escura');
  Set1 := DeriveAccent($FF2563C9, True, DarkSurface);
  ColorToHsl(Set1.Strong, H1, S1, L1);
  Assert.AreEqual(H0, H1, 4.0);
  ColorToHsl(Set1.Accent, H0, S0, L0);
  Assert.IsTrue(L1 > L0, 'no escuro a forte e mais clara');
end;

procedure TColorsTests.OnAccentIsTheBestOfBlackAndWhite;
var
  S: TAccentSet;
begin
  S := DeriveAccent($FF23705F, False, LightSurface);
  Assert.AreEqual<Cardinal>($FFFFFFFF, S.OnAccent, 'verde escuro: texto branco');
  S := DeriveAccent($FFFFD54F, True, DarkSurface);
  Assert.AreEqual<Cardinal>($FF0E1513, S.OnAccent, 'amarelo claro: texto escuro');
end;

procedure TColorsTests.PresetsAreValidAndDistinct;
var
  I, J: Integer;
begin
  Assert.AreEqual<Cardinal>($FF23705F, AccentPresetColors[0], 'a primeira e a cor original');
  for I := 0 to AccentPresetCount - 1 do
  begin
    Assert.AreEqual<Cardinal>($FF, AccentPresetColors[I] shr 24, 'opaca');
    for J := I + 1 to AccentPresetCount - 1 do
      Assert.AreNotEqual<Cardinal>(AccentPresetColors[I], AccentPresetColors[J]);
  end;
end;

procedure TColorsTests.ExtremeColorsDoNotBreakTheDerivation;
var
  C: Cardinal;
  S: TAccentSet;
begin
  for C in [Cardinal($FF000000), Cardinal($FFFFFFFF), Cardinal($FF808080), Cardinal($FF00FF00)] do
  begin
    S := DeriveAccent(C, False, LightSurface);
    Assert.IsTrue(S.Accent <> 0);
    S := DeriveAccent(C, True, DarkSurface);
    Assert.IsTrue(S.Accent <> 0);
    Assert.IsTrue(S.Soft <> 0);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TColorsTests);

end.
