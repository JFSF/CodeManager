unit CM.Pages.Appearance;

{ Pagina Aspeto: a cor de destaque, as fontes (interface, texto tecnico e codigo) e o tamanho do texto. As escolhas
  sao do utilizador (ficam nas definicoes dele). A cor aplica-se logo; as fontes e o tamanho tambem se repintam logo
  e, passado um instante sem mexer, a interface reconstroi-se para os controlos medirem o texto de novo. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Layouts,
  CM.Colors, CM.Theme, CM.Controls, CM.Layouts, CM.CodeView, CM.Highlight, CM.Store, CM.Pages.Host;

type
  // fichas de escolha que quebram de linha; cada uma pode ser escrita na sua propria fonte (pre-visualizacao)
  TCMChoiceBar = class(TCMControl)
  private
    FLabels: TArray<string>;
    FFonts: TArray<string>;           // '' = a fonte da interface
    FActive: Integer;
    FHover: Integer;
    FOnPick: TCMTabEvent;
    FOnFit: TNotifyEvent;
    function ChipRect(AIndex: Integer; out ARight: Single): TRectF;
    function ChipAt(X, Y: Single): Integer;
    function ChipWidth(AIndex: Integer): Single;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetItems(const ALabels, AFonts: TArray<string>; AActive: Integer);
    procedure Fit;
    property Active: Integer read FActive;
    property OnPick: TCMTabEvent read FOnPick write FOnPick;
    // a altura mudou (as fichas quebraram de linha de outra maneira)
    property OnFit: TNotifyEvent read FOnFit write FOnFit;
  end;

  // as cores prontas, em circulos, mais um para "outra cor" (a do campo hexadecimal)
  TCMSwatchBar = class(TCMControl)
  private
    FActive: Integer;                 // indice nas cores prontas; -1 = uma cor livre
    FCustom: Cardinal;                // a cor livre (0 = nenhuma)
    FHover: Integer;
    FOnPick: TCMTabEvent;
    function SwatchRect(AIndex: Integer): TRectF;
    function SwatchAt(X, Y: Single): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetState(AActive: Integer; ACustom: Cardinal);
    property OnPick: TCMTabEvent read FOnPick write FOnPick;
  end;

  TAppearancePage = class(TCMControl)
  private
    FHost: IPageHost;
    FScroll: TCMFadeScroll;
    FBody: TCMPanel;                  // o fundo por baixo dos cartoes (sem ele os intervalos ficam brancos no tema escuro)
    FSwatches: TCMSwatchBar;
    FHex: TCMInput;
    FUiBar, FMonoBar, FCodeBar, FScaleBar, FSizeBar: TCMChoiceBar;
    FPreview: TCMCodeView;
    FPreviewDoc: TCodeDoc;
    FCards: array[0..3] of TCMPanel;
    FRebuildTimer: TTimer;
    FBuilding: Boolean;
    FFitting: Boolean;
    FScaleValues: TArray<Integer>;
    FSizeValues: TArray<Integer>;
    procedure SwatchPick(Sender: TObject; AIndex: Integer);
    procedure HexChanged(Sender: TObject);
    procedure UiPick(Sender: TObject; AIndex: Integer);
    procedure MonoPick(Sender: TObject; AIndex: Integer);
    procedure CodePick(Sender: TObject; AIndex: Integer);
    procedure ScalePick(Sender: TObject; AIndex: Integer);
    procedure SizePick(Sender: TObject; AIndex: Integer);
    procedure ResetClick(Sender: TObject);
    procedure RebuildTick(Sender: TObject);
    procedure Changed(AFontsOrSize: Boolean);
    procedure Load;
    procedure FitCards;
    procedure BarFitted(Sender: TObject);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    // a pagina passou a estar visivel: volta a ler as definicoes
    procedure Activate;
  end;

implementation

uses
  CM.Lang;

const
  PreviewCode =
    '{ Pre-visualizacao do codigo }' + sLineBreak +
    'function Soma(A, B: Integer): Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  if (A <> B) and (A >= 0) then' + sLineBreak +
    '    Result := A + B * 2   // ligaduras: <> >= := ->' + sLineBreak +
    '  else' + sLineBreak +
    '    raise Exception.Create(''valor invalido'');' + sLineBreak +
    'end;';
  ChipH = 34;
  ChipGap = 8;

{ TCMChoiceBar }

constructor TCMChoiceBar.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  FActive := -1;
  FHover := -1;
end;

procedure TCMChoiceBar.SetItems(const ALabels, AFonts: TArray<string>; AActive: Integer);
begin
  FLabels := ALabels;
  FFonts := AFonts;
  FActive := AActive;
  Fit;
  Repaint;
end;

function TCMChoiceBar.ChipWidth(AIndex: Integer): Single;
var
  F: string;
begin
  F := UiFont;
  if (AIndex < Length(FFonts)) and (FFonts[AIndex] <> '') then
    F := FFonts[AIndex];
  Result := MeasureText(FLabels[AIndex], 12.5, F, [TFontStyle.fsBold]) + 30;
end;

// o rectangulo de uma ficha (as fichas enchem a linha e quebram para a seguinte)
function TCMChoiceBar.ChipRect(AIndex: Integer; out ARight: Single): TRectF;
var
  I: Integer;
  X, Y, W: Single;
begin
  X := 0;
  Y := 0;
  Result := TRectF.Empty;
  for I := 0 to AIndex do
  begin
    W := ChipWidth(I);
    if (X > 0) and (X + W > Width) then
    begin
      X := 0;
      Y := Y + ChipH + ChipGap;
    end;
    Result := TRectF.Create(X, Y, X + W, Y + ChipH);
    X := X + W + ChipGap;
  end;
  ARight := X;
end;

procedure TCMChoiceBar.Fit;
var
  R: TRectF;
  Dummy: Single;
begin
  if (Length(FLabels) = 0) or (Width <= 0) then
    Exit;
  R := ChipRect(High(FLabels), Dummy);
  if Abs(Height - R.Bottom) > 0.5 then
  begin
    Height := R.Bottom;
    if Assigned(FOnFit) then
      FOnFit(Self);
  end;
end;

procedure TCMChoiceBar.Resize;
begin
  inherited;
  Fit;
end;

function TCMChoiceBar.ChipAt(X, Y: Single): Integer;
var
  I: Integer;
  Dummy: Single;
begin
  for I := 0 to High(FLabels) do
    if ChipRect(I, Dummy).Contains(PointF(X, Y)) then
      Exit(I);
  Result := -1;
end;

procedure TCMChoiceBar.Paint;
var
  I: Integer;
  R: TRectF;
  Dummy: Single;
  F: string;
  Active: Boolean;
begin
  for I := 0 to High(FLabels) do
  begin
    R := ChipRect(I, Dummy);
    Active := I = FActive;
    if Active then
    begin
      FillRound(Canvas, R, 8, Pal.AccentSoft);
      StrokeRound(Canvas, R, 8, Fade(Pal.Accent, 0.55), 1.5);
    end
    else
    begin
      FillRound(Canvas, R, 8, Pick(I = FHover, Pal.Hover, Pal.Surface));
      StrokeRound(Canvas, R, 8, Pal.Border, 1);
    end;
    F := UiFont;
    if (I < Length(FFonts)) and (FFonts[I] <> '') then
      F := FFonts[I];
    DrawTextRect(Canvas, R, FLabels[I], Pick(Active, Pal.AccentStrong, Pal.Text), 12.5, F, [TFontStyle.fsBold],
      TTextAlign.Center);
  end;
end;

procedure TCMChoiceBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  I := ChipAt(X, Y);
  if (I >= 0) and (I <> FActive) then
  begin
    FActive := I;
    Repaint;
    if Assigned(FOnPick) then
      FOnPick(Self, I);
  end;
end;

procedure TCMChoiceBar.MouseMove(Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  I := ChipAt(X, Y);
  if I <> FHover then
  begin
    FHover := I;
    if I >= 0 then Cursor := crHandPoint else Cursor := crDefault;
    Repaint;
  end;
end;

procedure TCMChoiceBar.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  Repaint;
end;

{ TCMSwatchBar }

constructor TCMSwatchBar.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  FActive := 0;
  FHover := -1;
end;

procedure TCMSwatchBar.SetState(AActive: Integer; ACustom: Cardinal);
begin
  FActive := AActive;
  FCustom := ACustom;
  Repaint;
end;

// as cores prontas e, a seguir, a livre
function TCMSwatchBar.SwatchRect(AIndex: Integer): TRectF;
const
  D = 34;
  Gap = 12;
begin
  Result := TRectF.Create(AIndex * (D + Gap), 4, AIndex * (D + Gap) + D, 4 + D);
end;

function TCMSwatchBar.SwatchAt(X, Y: Single): Integer;
var
  I: Integer;
begin
  for I := 0 to AccentPresetCount - 1 do
    if SwatchRect(I).Contains(PointF(X, Y)) then
      Exit(I);
  Result := -1;
end;

procedure TCMSwatchBar.Paint;
var
  I: Integer;
  R, Ring: TRectF;
  C: Cardinal;
  Shown: TAccentSet;
begin
  for I := 0 to AccentPresetCount - 1 do
  begin
    R := SwatchRect(I);
    C := AccentPresetColors[I];
    Shown := DeriveAccent(C, ThemeMode = tmDark, Pal.Surface);       // a cor tal como vai aparecer neste tema
    FillRound(Canvas, R, R.Width / 2, Shown.Accent);
    if I = FActive then
    begin
      Ring := R;
      Ring.Inflate(4, 4);
      StrokeRound(Canvas, Ring, Ring.Width / 2, Pal.Text, 2);
      DrawIcon(Canvas, icCheck, TRectF.Create(R.Left + 8, R.Top + 8, R.Right - 8, R.Bottom - 8), Shown.OnAccent);
    end
    else if I = FHover then
      StrokeRound(Canvas, TRectF.Create(R.Left - 3, R.Top - 3, R.Right + 3, R.Bottom + 3), (R.Width + 6) / 2,
        Pal.BorderStrong, 2);
  end;
end;

procedure TCMSwatchBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  I := SwatchAt(X, Y);
  if (I >= 0) and Assigned(FOnPick) then
    FOnPick(Self, I);
end;

procedure TCMSwatchBar.MouseMove(Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  I := SwatchAt(X, Y);
  if I <> FHover then
  begin
    FHover := I;
    if I >= 0 then
    begin
      Cursor := crHandPoint;
      Hint := Tr(AccentPresetNames[I]);
      ShowHint := True;
    end
    else
      Cursor := crDefault;
    Repaint;
  end;
end;

procedure TCMSwatchBar.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  Repaint;
end;

{ TAppearancePage }

constructor TAppearancePage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Lbl: TCMLabel;
  Note: TCMLabel;
  Bar: TCMControl;
  Reset: TCMButton;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;
  FBuilding := True;
  FScaleValues := [90, 100, 110, 125];
  FSizeValues := [0, 11, 12, 13, 14, 16];

  FRebuildTimer := TTimer.Create(Self);
  FRebuildTimer.Enabled := False;
  FRebuildTimer.Interval := 1300;
  FRebuildTimer.OnTimer := RebuildTick;

  Bar := TCMControl.Create(Self);
  Bar.Parent := Self;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 42;
  Bar.Margins.Bottom := 14;
  Reset := TCMButton.Make(Bar, Tr('Repor aspeto padrão'), icRefresh, bkSecondary, ResetClick);
  Reset.Align := TAlignLayout.Right;
  Reset.Width := 240;
  Reset.Height := 42;

  FScroll := TCMFadeScroll.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := TAlignLayout.Client;
  FScroll.ShowScrollBars := False;
  FScroll.Padding.Right := 0;       // sem a faixa do indicador: nao pinta nada no tema escuro
  FBody := TCMPanel.Create(Self);
  FBody.Parent := FScroll;
  FBody.Align := TAlignLayout.Top;
  FBody.Role := prBg;
  FBody.Radius := 0;
  FBody.Bordered := False;
  FBody.Height := 1400;

  // 1) cor de destaque
  FCards[0] := NewCard(Self, FBody, 240);
  TCMLabel.Make(FCards[0], Tr('Cor de destaque'), 15, True).Align := TAlignLayout.Top;
  Note := TCMLabel.Make(FCards[0], Tr('A cor dos botões, dos itens selecionados e dos gráficos. As variantes forte e suave, e o texto por cima, calculam-se sozinhas para se lerem bem nos dois temas.'),
    12, False, lcDim);
  Note.Align := TAlignLayout.Top;
  Note.Wrap := True;
  Note.Height := 36;
  Note.Margins.Top := 4;
  FSwatches := TCMSwatchBar.Create(Self);
  FSwatches.Parent := FCards[0];
  FSwatches.Align := TAlignLayout.Top;
  FSwatches.Height := 46;
  FSwatches.Margins.Top := 14;
  FSwatches.OnPick := SwatchPick;
  Lbl := TCMLabel.Make(FCards[0], Tr('Ou uma cor livre (#RRGGBB)'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 12;
  FHex := TCMInput.Create(Self);
  FHex.Parent := FCards[0];
  FHex.Align := TAlignLayout.Top;
  FHex.Height := 42;
  FHex.Margins.Top := 6;
  FHex.Placeholder := '#23705F';
  FHex.OnChangeText := HexChanged;

  // 2) fontes
  FCards[1] := NewCard(Self, FBody, 420);
  TCMLabel.Make(FCards[1], Tr('Fontes'), 15, True).Align := TAlignLayout.Top;
  Lbl := TCMLabel.Make(FCards[1], Tr('Interface'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 14;
  FUiBar := TCMChoiceBar.Create(Self);
  FUiBar.Parent := FCards[1];
  FUiBar.Align := TAlignLayout.Top;
  FUiBar.Margins.Top := 6;
  FUiBar.OnPick := UiPick;
  FUiBar.OnFit := BarFitted;
  Lbl := TCMLabel.Make(FCards[1], Tr('Texto técnico (nomes, números, etiquetas)'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 16;
  FMonoBar := TCMChoiceBar.Create(Self);
  FMonoBar.Parent := FCards[1];
  FMonoBar.Align := TAlignLayout.Top;
  FMonoBar.Margins.Top := 6;
  FMonoBar.OnPick := MonoPick;
  FMonoBar.OnFit := BarFitted;
  Lbl := TCMLabel.Make(FCards[1], Tr('Código (página Código)'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 16;
  FCodeBar := TCMChoiceBar.Create(Self);
  FCodeBar.Parent := FCards[1];
  FCodeBar.Align := TAlignLayout.Top;
  FCodeBar.Margins.Top := 6;
  FCodeBar.OnPick := CodePick;
  FCodeBar.OnFit := BarFitted;

  // 3) tamanho
  FCards[2] := NewCard(Self, FBody, 260);
  TCMLabel.Make(FCards[2], Tr('Tamanho'), 15, True).Align := TAlignLayout.Top;
  Lbl := TCMLabel.Make(FCards[2], Tr('Texto da aplicação'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 14;
  FScaleBar := TCMChoiceBar.Create(Self);
  FScaleBar.Parent := FCards[2];
  FScaleBar.Align := TAlignLayout.Top;
  FScaleBar.Margins.Top := 6;
  FScaleBar.OnPick := ScalePick;
  FScaleBar.OnFit := BarFitted;
  Lbl := TCMLabel.Make(FCards[2], Tr('Código (em pontos)'), 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 20;
  Lbl.Margins.Top := 16;
  FSizeBar := TCMChoiceBar.Create(Self);
  FSizeBar.Parent := FCards[2];
  FSizeBar.Align := TAlignLayout.Top;
  FSizeBar.Margins.Top := 6;
  FSizeBar.OnPick := SizePick;
  FSizeBar.OnFit := BarFitted;

  // 4) pre-visualizacao e repor
  FCards[3] := NewCard(Self, FBody, 270);
  TCMLabel.Make(FCards[3], Tr('Pré-visualização'), 15, True).Align := TAlignLayout.Top;
  FPreviewDoc := TCodeDoc.Create(PreviewCode);
  FPreview := TCMCodeView.Create(Self);
  FPreview.Parent := FCards[3];
  FPreview.Align := TAlignLayout.Top;
  FPreview.Height := 190;
  FPreview.Margins.Top := 10;
  FPreview.SetDoc(FPreviewDoc);

  Load;
  FBuilding := False;
end;

destructor TAppearancePage.Destroy;
begin
  FRebuildTimer.Enabled := False;
  if FPreview <> nil then
    FPreview.SetDoc(nil);
  FPreviewDoc.Free;
  inherited;
end;

procedure TAppearancePage.ApplyTheme;
begin
  FHex.ApplyTheme;
  FSwatches.Repaint;
  FUiBar.Repaint;
  FMonoBar.Repaint;
  FCodeBar.Repaint;
  FScaleBar.Repaint;
  FSizeBar.Repaint;
  FPreview.FontChanged;
end;

procedure TAppearancePage.Activate;
begin
  Load;
end;

procedure TAppearancePage.Resize;
begin
  inherited;
  if FCards[0] <> nil then
    FitCards;
end;

// as alturas dos cartoes seguem as fichas (que quebram de linha conforme a largura)
procedure TAppearancePage.FitCards;
begin
  if FFitting then
    Exit;
  FFitting := True;          // Fit das fichas volta a chamar este metodo
  try
    FUiBar.Fit;
    FMonoBar.Fit;
    FCodeBar.Fit;
    FScaleBar.Fit;
    FSizeBar.Fit;
  finally
    FFitting := False;
  end;
  FCards[1].Height := 18 + 18 + 28 + 20 + 6 + FUiBar.Height + 16 + 20 + 6 + FMonoBar.Height + 16 + 20 + 6 +
    FCodeBar.Height + 6;
  FCards[2].Height := 18 + 18 + 28 + 20 + 6 + FScaleBar.Height + 16 + 20 + 6 + FSizeBar.Height + 6;
  FBody.Height := FCards[0].Height + FCards[1].Height + FCards[2].Height + FCards[3].Height + 4 * 16 + 8;
end;

procedure TAppearancePage.BarFitted(Sender: TObject);
begin
  FitCards;
end;

procedure TAppearancePage.Load;
var
  S: TAppSettings;
  A: TAppearance;
  Items, Fonts: TArray<string>;
  Choices: TArray<string>;
  I, Idx, Active: Integer;
begin
  S := FHost.AppSettings;
  if S = nil then
    Exit;
  FBuilding := True;
  try
    A := AppearanceFromSettings(S);
    // cor
    Active := -1;
    for I := 0 to AccentPresetCount - 1 do
      if ((A.Accent = 0) and (I = 0)) or (A.Accent = AccentPresetColors[I]) then
        Active := I;
    if A.Accent <> 0 then
      FHex.Text := ColorToHex(A.Accent)
    else
      FHex.Text := '';
    if Active = 0 then
      FSwatches.SetState(0, 0)
    else
      FSwatches.SetState(Active, A.Accent);
    // fontes da interface: a primeira e a da aplicacao
    Choices := UiFontChoices;
    SetLength(Items, Length(Choices));
    SetLength(Fonts, Length(Choices));
    Idx := 0;
    for I := 0 to High(Choices) do
    begin
      Items[I] := Choices[I];
      Fonts[I] := Choices[I];
      if SameText(Choices[I], A.UiFont) then
        Idx := I;
    end;
    FUiBar.SetItems(Items, Fonts, Idx);
    // texto tecnico: uma ficha "Automática" e as fontes de codigo instaladas
    Choices := MonoFontChoices;
    SetLength(Items, Length(Choices) + 1);
    SetLength(Fonts, Length(Choices) + 1);
    Items[0] := Tr('Automática');
    Fonts[0] := '';
    Idx := 0;
    for I := 0 to High(Choices) do
    begin
      Items[I + 1] := Choices[I];
      Fonts[I + 1] := Choices[I];
      if SameText(Choices[I], A.MonoFont) then
        Idx := I + 1;
    end;
    FMonoBar.SetItems(Items, Fonts, Idx);
    // codigo: so as modernas
    Choices := CodeFontChoices;
    SetLength(Items, Length(Choices));
    SetLength(Fonts, Length(Choices));
    Idx := 0;
    for I := 0 to High(Choices) do
    begin
      Items[I] := Choices[I];
      Fonts[I] := Choices[I];
      if SameText(Choices[I], CodeFont) then
        Idx := I;
    end;
    FCodeBar.SetItems(Items, Fonts, Idx);
    // tamanhos
    SetLength(Items, Length(FScaleValues));
    SetLength(Fonts, Length(FScaleValues));
    Idx := 1;
    for I := 0 to High(FScaleValues) do
    begin
      Items[I] := IntToStr(FScaleValues[I]) + '%';
      Fonts[I] := '';
      if FScaleValues[I] = IfThen(S.TextScale = 0, 100, S.TextScale) then
        Idx := I;
    end;
    FScaleBar.SetItems(Items, Fonts, Idx);
    SetLength(Items, Length(FSizeValues));
    SetLength(Fonts, Length(FSizeValues));
    Idx := 0;
    for I := 0 to High(FSizeValues) do
    begin
      if FSizeValues[I] = 0 then
        Items[I] := Tr('Automático')
      else
        Items[I] := IntToStr(FSizeValues[I]) + ' pt';
      Fonts[I] := '';
      if FSizeValues[I] = S.CodeSize then
        Idx := I;
    end;
    FSizeBar.SetItems(Items, Fonts, Idx);
    FitCards;
  finally
    FBuilding := False;
  end;
end;

// as escolhas ja estao nas definicoes: aplica-as. Cor so repinta; fontes e tamanho reconstroem depois de um instante
procedure TAppearancePage.Changed(AFontsOrSize: Boolean);
begin
  ApplyAppearance(AppearanceFromSettings(FHost.AppSettings));
  FHost.AppearanceChanged(False);
  FHost.MarkSettingsDirty;
  if AFontsOrSize then
  begin
    FRebuildTimer.Enabled := False;
    FRebuildTimer.Enabled := True;
  end;
end;

procedure TAppearancePage.RebuildTick(Sender: TObject);
begin
  FRebuildTimer.Enabled := False;
  FHost.AppearanceChanged(True);
end;

procedure TAppearancePage.SwatchPick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  if AIndex = 0 then
    FHost.AppSettings.Accent := ''
  else
    FHost.AppSettings.Accent := ColorToHex(AccentPresetColors[AIndex]);
  FBuilding := True;
  try
    if AIndex = 0 then FHex.Text := '' else FHex.Text := ColorToHex(AccentPresetColors[AIndex]);
  finally
    FBuilding := False;
  end;
  FSwatches.SetState(AIndex, 0);
  Changed(False);
end;

procedure TAppearancePage.HexChanged(Sender: TObject);
var
  C: Cardinal;
  I, Active: Integer;
begin
  if FBuilding then
    Exit;
  if Trim(FHex.Text) = '' then
  begin
    FHost.AppSettings.Accent := '';
    FSwatches.SetState(0, 0);
    Changed(False);
    Exit;
  end;
  if not ParseHexColor(FHex.Text, C) then
    Exit;                       // ainda a escrever: so se aplica um valor completo
  FHost.AppSettings.Accent := ColorToHex(C);
  Active := -1;
  for I := 0 to AccentPresetCount - 1 do
    if AccentPresetColors[I] = C then
      Active := I;
  FSwatches.SetState(Active, C);
  Changed(False);
end;

procedure TAppearancePage.UiPick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  if AIndex = 0 then
    FHost.AppSettings.UiFont := ''
  else
    FHost.AppSettings.UiFont := UiFontChoices[AIndex];
  Changed(True);
end;

procedure TAppearancePage.MonoPick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  if AIndex = 0 then
    FHost.AppSettings.MonoFont := ''
  else
    FHost.AppSettings.MonoFont := MonoFontChoices[AIndex - 1];
  Changed(True);
end;

procedure TAppearancePage.CodePick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  FHost.AppSettings.CodeFont := CodeFontChoices[AIndex];
  Changed(True);
end;

procedure TAppearancePage.ScalePick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  if FScaleValues[AIndex] = 100 then
    FHost.AppSettings.TextScale := 0
  else
    FHost.AppSettings.TextScale := FScaleValues[AIndex];
  Changed(True);
end;

procedure TAppearancePage.SizePick(Sender: TObject; AIndex: Integer);
begin
  if FBuilding then
    Exit;
  FHost.AppSettings.CodeSize := FSizeValues[AIndex];
  Changed(True);
end;

procedure TAppearancePage.ResetClick(Sender: TObject);
var
  S: TAppSettings;
begin
  S := FHost.AppSettings;
  S.Accent := '';
  S.UiFont := '';
  S.MonoFont := '';
  S.CodeFont := '';
  S.CodeSize := 0;
  S.TextScale := 0;
  Load;
  Changed(True);
end;

end.
