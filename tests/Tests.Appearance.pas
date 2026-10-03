unit Tests.Appearance;

// Testes do aspecto (CM.Theme): a cor de destaque, as fontes e a escala do texto escolhidas pelo utilizador. O estado
// do tema e global: cada teste volta a deixa-lo como o encontrou.

interface

uses
  System.SysUtils, System.Classes, DUnitX.TestFramework, CM.Colors, CM.Store, CM.Theme;

type
  [TestFixture]
  TAppearanceTests = class
  private
    FMode: TThemeMode;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DefaultsKeepTheOriginalPalettes;
    [Test] procedure AccentChangesBothThemes;
    [Test] procedure DerivedAccentsAreReadableOnEachTheme;
    [Test] procedure ResettingRestoresTheOriginalAccent;
    [Test] procedure ApplyingRepaintsThroughTheListeners;
    [Test] procedure ScaleIsClampedToTheSupportedRange;
    [Test] procedure ScaleChangesScaledSizes;
    [Test] procedure ZeroScaleMeansOneHundredPercent;
    [Test] procedure CodeSizeIsClampedAndDefaults;
    [Test] procedure CodeSizeFollowsTheChoice;
    [Test] procedure UnknownFontsFallBackToTheDefaults;
    [Test] procedure InstalledChoicesAreUsed;
    [Test] procedure UiFontChoicesAlwaysStartWithTheDefault;
    [Test] procedure SettingsBecomeAnAppearance;
    [Test] procedure InvalidAccentInSettingsMeansTheOriginal;
    [Test] procedure NilSettingsGiveTheDefaults;
    [Test] procedure ModeSurvivesApplying;
  end;

implementation

var
  GListened: Integer;                 // os ouvintes do tema vivem ate ao fim: nao podem apontar para o fixture
  GRegistered: Boolean;

procedure TAppearanceTests.Setup;
begin
  FMode := ThemeMode;
  ApplyAppearance(DefaultAppearance);
end;

procedure TAppearanceTests.TearDown;
begin
  ApplyAppearance(DefaultAppearance);
  SetThemeMode(FMode);
end;

procedure TAppearanceTests.DefaultsKeepTheOriginalPalettes;
begin
  SetThemeMode(tmLight);
  Assert.AreEqual<Cardinal>(LightPalette.Accent, Pal.Accent);
  Assert.AreEqual<Cardinal>(LightPalette.AccentSoft, Pal.AccentSoft);
  SetThemeMode(tmDark);
  Assert.AreEqual<Cardinal>(DarkPalette.Accent, Pal.Accent);
  Assert.AreEqual<Cardinal>(DarkPalette.OnAccent, Pal.OnAccent);
end;

procedure TAppearanceTests.AccentChangesBothThemes;
var
  A: TAppearance;
begin
  A := DefaultAppearance;
  A.Accent := $FF7C4DCB;
  ApplyAppearance(A);
  SetThemeMode(tmLight);
  Assert.AreNotEqual<Cardinal>(LightPalette.Accent, Pal.Accent);
  Assert.AreNotEqual<Cardinal>(LightPalette.AccentSoft, Pal.AccentSoft);
  Assert.AreEqual<Cardinal>(LightPalette.Surface, Pal.Surface, 'so a cor de destaque muda');
  SetThemeMode(tmDark);
  Assert.AreNotEqual<Cardinal>(DarkPalette.Accent, Pal.Accent);
  Assert.AreEqual<Cardinal>(DarkPalette.Bg, Pal.Bg);
end;

procedure TAppearanceTests.DerivedAccentsAreReadableOnEachTheme;
var
  A: TAppearance;
  I: Integer;
begin
  for I := 0 to AccentPresetCount - 1 do
  begin
    A := DefaultAppearance;
    A.Accent := AccentPresetColors[I];
    ApplyAppearance(A);
    SetThemeMode(tmLight);
    Assert.IsTrue(ContrastRatio(Pal.Accent, Pal.OnAccent) >= 4.5, 'claro: ' + AccentPresetNames[I]);
    SetThemeMode(tmDark);
    Assert.IsTrue(ContrastRatio(Pal.Accent, Pal.Surface) >= 4.5, 'escuro: ' + AccentPresetNames[I]);
  end;
end;

procedure TAppearanceTests.ResettingRestoresTheOriginalAccent;
var
  A: TAppearance;
begin
  A := DefaultAppearance;
  A.Accent := $FFC2377F;
  ApplyAppearance(A);
  ApplyAppearance(DefaultAppearance);
  SetThemeMode(tmLight);
  Assert.AreEqual<Cardinal>(LightPalette.Accent, Pal.Accent);
  SetThemeMode(tmDark);
  Assert.AreEqual<Cardinal>(DarkPalette.AccentStrong, Pal.AccentStrong);
end;

procedure TAppearanceTests.ApplyingRepaintsThroughTheListeners;
var
  Before: Integer;
  A: TAppearance;
begin
  if not GRegistered then
  begin
    OnThemeChanged(
      procedure
      begin
        Inc(GListened);
      end);
    GRegistered := True;
  end;
  Before := GListened;
  A := DefaultAppearance;
  A.Accent := $FF2563C9;
  ApplyAppearance(A);
  Assert.IsTrue(GListened > Before, 'os controlos repintam-se com a cor nova');
end;

procedure TAppearanceTests.ScaleIsClampedToTheSupportedRange;
var
  A: TAppearance;
begin
  A := DefaultAppearance;
  A.TextScale := 50;
  ApplyAppearance(A);
  Assert.AreEqual(MinTextScale / 100, TextScale, 0.0001);
  A.TextScale := 300;
  ApplyAppearance(A);
  Assert.AreEqual(MaxTextScale / 100, TextScale, 0.0001);
  Assert.AreEqual(MaxTextScale, CurrentAppearance.TextScale);
end;

procedure TAppearanceTests.ScaleChangesScaledSizes;
var
  A: TAppearance;
begin
  A := DefaultAppearance;
  A.TextScale := 110;
  ApplyAppearance(A);
  Assert.AreEqual(13.2, ScaledSize(12), 0.001);
  Assert.IsTrue(MeasureText('Hello', 12, UiFont) > 0);
end;

procedure TAppearanceTests.ZeroScaleMeansOneHundredPercent;
begin
  ApplyAppearance(DefaultAppearance);
  Assert.AreEqual(1.0, TextScale, 0.0001);
  Assert.AreEqual(12.0, ScaledSize(12), 0.0001);
  Assert.AreEqual(100, CurrentAppearance.TextScale);
end;

procedure TAppearanceTests.CodeSizeIsClampedAndDefaults;
var
  A: TAppearance;
begin
  Assert.AreEqual(DefaultCodeSize, CodeFontSize, 0.0001);
  A := DefaultAppearance;
  A.CodeSize := 2;
  ApplyAppearance(A);
  Assert.AreEqual<Integer>(MinCodeSize, Round(CodeFontSize));
  A.CodeSize := 99;
  ApplyAppearance(A);
  Assert.AreEqual<Integer>(MaxCodeSize, Round(CodeFontSize));
end;

procedure TAppearanceTests.CodeSizeFollowsTheChoice;
var
  A: TAppearance;
begin
  A := DefaultAppearance;
  A.CodeSize := 14;
  A.TextScale := 125;
  ApplyAppearance(A);
  Assert.AreEqual(14.0, CodeFontSize, 0.0001, 'sem a escala: o desenho aplica-a');
end;

procedure TAppearanceTests.UnknownFontsFallBackToTheDefaults;
var
  A: TAppearance;
  Mono, Code: string;
begin
  ApplyAppearance(DefaultAppearance);
  Mono := MonoFont;
  Code := CodeFont;
  A := DefaultAppearance;
  A.UiFont := 'Fonte Que Nao Existe';
  A.MonoFont := 'Outra Que Nao Existe';
  A.CodeFont := 'E Mais Uma';
  ApplyAppearance(A);
  Assert.AreEqual('Segoe UI', UiFont);
  Assert.AreEqual(Mono, MonoFont);
  Assert.AreEqual(Code, CodeFont);
end;

procedure TAppearanceTests.InstalledChoicesAreUsed;
var
  A: TAppearance;
  Ui, Mono: TArray<string>;
begin
  Ui := UiFontChoices;
  Mono := MonoFontChoices;
  A := DefaultAppearance;
  if Length(Ui) > 1 then
  begin
    A.UiFont := LowerCase(Ui[1]);
    ApplyAppearance(A);
    Assert.AreEqual(Ui[1], UiFont, 'sem distinguir maiusculas');
  end;
  if Length(Mono) > 1 then
  begin
    A.MonoFont := Mono[1];
    ApplyAppearance(A);
    Assert.AreEqual(Mono[1], MonoFont);
  end;
end;

procedure TAppearanceTests.UiFontChoicesAlwaysStartWithTheDefault;
begin
  Assert.IsTrue(Length(UiFontChoices) >= 1);
  Assert.AreEqual('Segoe UI', UiFontChoices[0]);
end;

procedure TAppearanceTests.SettingsBecomeAnAppearance;
var
  S: TAppSettings;
  A: TAppearance;
begin
  S := TAppSettings.Create;
  try
    S.Accent := '#7C4DCB';
    S.UiFont := 'Inter';
    S.MonoFont := 'Fira Code';
    S.CodeFont := 'JetBrains Mono';
    S.CodeSize := 14;
    S.TextScale := 110;
    A := AppearanceFromSettings(S);
    Assert.AreEqual<Cardinal>($FF7C4DCB, A.Accent);
    Assert.AreEqual('Inter', A.UiFont);
    Assert.AreEqual('Fira Code', A.MonoFont);
    Assert.AreEqual('JetBrains Mono', A.CodeFont);
    Assert.AreEqual(14, A.CodeSize);
    Assert.AreEqual(110, A.TextScale);
  finally
    S.Free;
  end;
end;

procedure TAppearanceTests.InvalidAccentInSettingsMeansTheOriginal;
var
  S: TAppSettings;
begin
  S := TAppSettings.Create;
  try
    S.Accent := 'verde';
    Assert.AreEqual<Cardinal>(0, AppearanceFromSettings(S).Accent);
    S.Accent := '';
    Assert.AreEqual<Cardinal>(0, AppearanceFromSettings(S).Accent);
  finally
    S.Free;
  end;
end;

procedure TAppearanceTests.NilSettingsGiveTheDefaults;
var
  A: TAppearance;
begin
  A := AppearanceFromSettings(nil);
  Assert.AreEqual<Cardinal>(0, A.Accent);
  Assert.AreEqual('', A.UiFont);
  Assert.AreEqual(0, A.TextScale);
end;

procedure TAppearanceTests.ModeSurvivesApplying;
var
  A: TAppearance;
begin
  SetThemeMode(tmDark);
  A := DefaultAppearance;
  A.Accent := $FFC13F2F;
  ApplyAppearance(A);
  Assert.AreEqual(Ord(tmDark), Ord(ThemeMode), 'mudar a cor nao muda o tema');
end;

initialization
  TDUnitX.RegisterTestFixture(TAppearanceTests);

end.
