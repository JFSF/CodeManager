unit CM.Controls;

{ Controlos visuais proprios (pintados a mao a partir da paleta do tema). Como leem Pal em
  cada Paint, a troca claro/escuro nao exige reaplicar estilos - basta repintar. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Generics.Collections, FMX.Types, FMX.Controls, FMX.Graphics, FMX.Objects,
  FMX.Layouts, FMX.Edit, FMX.StdCtrls, CM.Theme;

type
  TCMControl = class(TLayout)
  protected
    FHover: Boolean;
    FDown: Boolean;
    procedure DoMouseEnter; override;
    procedure DoMouseLeave; override;
    procedure ParentChanged; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TPanelRole = (prNone, prBg, prSurface, prSurface2, prAccentSoft);

  TCMPanel = class(TCMControl)
  private
    FRole: TPanelRole;
    FRadius: Single;
    FBordered: Boolean;
    procedure SetRole(const Value: TPanelRole);
    procedure SetBordered(const Value: Boolean);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Role: TPanelRole read FRole write SetRole;
    property Radius: Single read FRadius write FRadius;
    property Bordered: Boolean read FBordered write SetBordered;
  end;

  // Selo da aplicacao: quadrado arredondado na cor de destaque com o simbolo { } (o do icone do .exe).
  TCMLogo = class(TCMControl)
  protected
    procedure Paint; override;
  end;

  TLabelColor = (lcText, lcDim, lcFaint, lcAccent, lcAccentStrong, lcDanger);

  TCMLabel = class(TCMControl)
  private
    FText: string;
    FSize: Single;
    FBold: Boolean;
    FMono: Boolean;
    FColorRole: TLabelColor;
    FHAlign: TTextAlign;
    FWrap: Boolean;
    procedure SetText(const Value: string);
    procedure SetColorRole(const Value: TLabelColor);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    class function Make(AParent: TFmxObject; const AText: string; ASize: Single;
      ABold: Boolean = False; AColor: TLabelColor = lcText; AMono: Boolean = False): TCMLabel;
    property Text: string read FText write SetText;
    property Size: Single read FSize write FSize;
    property Bold: Boolean read FBold write FBold;
    property Mono: Boolean read FMono write FMono;
    property ColorRole: TLabelColor read FColorRole write SetColorRole;
    property HAlign: TTextAlign read FHAlign write FHAlign;
    property Wrap: Boolean read FWrap write FWrap;
  end;

  TButtonKind = (bkPrimary, bkSecondary, bkGhost, bkDanger);

  TCMButton = class(TCMControl)
  private
    FText: string;
    FKind: TButtonKind;
    FIcon: TIconKind;
    FHasIcon: Boolean;
    FActive: Boolean;
    FIconOnly: Boolean;
    procedure SetText(const Value: string);
    procedure SetActive(const Value: Boolean);
    procedure SetIcon(const Value: TIconKind);
    procedure UpdateWidth;
  protected
    procedure Paint; override;
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    function NaturalWidth: Single;
    class function Make(AParent: TFmxObject; const AText: string; AIcon: TIconKind;
      AKind: TButtonKind; AHandler: TNotifyEvent): TCMButton;
    class function MakeIcon(AParent: TFmxObject; AIcon: TIconKind; AHandler: TNotifyEvent;
      const AHint: string): TCMButton;
    property Text: string read FText write SetText;
    property Icon: TIconKind read FIcon write SetIcon;
    property Kind: TButtonKind read FKind write FKind;
    property Active: Boolean read FActive write SetActive;
  end;

  TCMNavButton = class(TCMControl)
  private
    FText: string;
    FIcon: TIconKind;
    FSelected: Boolean;
    procedure SetSelected(const Value: Boolean);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Text: string read FText write FText;
    property Icon: TIconKind read FIcon write FIcon;
    property Selected: Boolean read FSelected write SetSelected;
  end;

  TCMSwitch = class(TCMControl)
  private
    FText: string;
    FChecked: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(const Value: Boolean);
  protected
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Text: string read FText write FText;
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TCMInput = class(TCMControl)
  private
    FEdit: TEdit;
    FIcon: TIconKind;
    FHasIcon: Boolean;
    FTrailing: TIconKind;
    FHasTrailing: Boolean;
    FFocused: Boolean;
    FOnTrailingClick: TNotifyEvent;
    FOnChangeText: TNotifyEvent;
    function GetText: string;
    procedure SetText(const Value: string);
    procedure SetPlaceholder(const Value: string);
    function GetPlaceholder: string;
    procedure EditEnter(Sender: TObject);
    procedure EditExit(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure LayoutEdit;
    function LeftPad: Single;
    function RightPad: Single;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyTheme;
    procedure SetLeadingIcon(AIcon: TIconKind);
    procedure SetTrailingIcon(AIcon: TIconKind);
    property Text: string read GetText write SetText;
    property Placeholder: string read GetPlaceholder write SetPlaceholder;
    property Edit: TEdit read FEdit;
    property OnTrailingClick: TNotifyEvent read FOnTrailingClick write FOnTrailingClick;
    property OnChangeText: TNotifyEvent read FOnChangeText write FOnChangeText;
  end;

  TCMProgress = class(TCMControl)
  private
    FValue: Single;
    procedure SetValue(const Value: Single);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Value: Single read FValue write SetValue;
  end;

  TKeyValue = record
    Caption: string;
    Value: string;
    Highlight: Boolean;
  end;

  TCMKeyValue = class(TCMControl)
  private
    FRows: TArray<TKeyValue>;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRows(const ARows: TArray<TKeyValue>);
  end;

  TCMRing = class(TCMControl)
  private
    FPct: Single;
    FCaption: string;
    FSub: string;
    FMethodsCaption: string;
    FMethodsPct: Single;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetValues(APct: Single; const ACaption, ASub: string;
      AMethodsPct: Single; const AMethodsCaption: string);
  end;

  TBarRow = record
    Name: string;
    Done: Integer;
    Total: Integer;
  end;

  TCMBars = class(TCMControl)
  private
    FRows: TArray<TBarRow>;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRows(const ARows: TArray<TBarRow>);
  end;

  TListEntry = record
    Title: string;
    Sub: string;
    Badge: string;
  end;

  TCMList = class(TCMControl)
  private
    FItems: TArray<TListEntry>;
    FIndex: Integer;
    FHoverIdx: Integer;
    FOnSelect: TNotifyEvent;
    function IndexAt(Y: Single): Integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetItems(const AItems: TArray<TListEntry>; ASelected: Integer);
    property ItemIndex: Integer read FIndex;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
  end;

  TCMToast = class(TCMControl)
  private
    FText: string;
    FTimer: TTimer;
    procedure HideNow(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowText(const AText: string);
  end;

function Fade(AColor: TAlphaColor; AAlpha: Single): TAlphaColor;
function LabelColor(ARole: TLabelColor): TAlphaColor;

implementation

const
  RowHeightList = 62;

var
  GPlaceSeq: Integer = 100000;

function Fade(AColor: TAlphaColor; AAlpha: Single): TAlphaColor;
begin
  TAlphaColorRec(Result).A := Round(TAlphaColorRec(AColor).A * AAlpha);
  TAlphaColorRec(Result).R := TAlphaColorRec(AColor).R;
  TAlphaColorRec(Result).G := TAlphaColorRec(AColor).G;
  TAlphaColorRec(Result).B := TAlphaColorRec(AColor).B;
end;

function LabelColor(ARole: TLabelColor): TAlphaColor;
begin
  case ARole of
    lcDim: Result := Pal.TextDim;
    lcFaint: Result := Pal.TextFaint;
    lcAccent: Result := Pal.Accent;
    lcAccentStrong: Result := Pal.AccentStrong;
    lcDanger: Result := Pal.Danger;
  else
    Result := Pal.Text;
  end;
end;

{ TCMControl }

constructor TCMControl.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := False;
end;

// O FMX ordena os controlos com o mesmo Align pela posicao (e, em empate, ao contrario da criacao).
// Atribuir uma sequencia crescente ao entrar no pai fixa a ordem = ordem de criacao.
procedure TCMControl.ParentChanged;
begin
  inherited;
  if Parent <> nil then
  begin
    Inc(GPlaceSeq);
    Position.Point := PointF(GPlaceSeq, GPlaceSeq);
  end;
end;

procedure TCMControl.DoMouseEnter;
begin
  inherited;
  FHover := True;
  Repaint;
end;

procedure TCMControl.DoMouseLeave;
begin
  inherited;
  FHover := False;
  FDown := False;
  Repaint;
end;

procedure TCMControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button = TMouseButton.mbLeft then
  begin
    FDown := True;
    Repaint;
  end;
end;

procedure TCMControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDown := False;
  Repaint;
end;

{ TCMPanel }

constructor TCMPanel.Create(AOwner: TComponent);
begin
  inherited;
  FRole := prSurface;
  FRadius := 12;
  FBordered := True;
end;

procedure TCMPanel.SetRole(const Value: TPanelRole);
begin
  FRole := Value;
  Repaint;
end;

procedure TCMPanel.SetBordered(const Value: Boolean);
begin
  FBordered := Value;
  Repaint;
end;

procedure TCMPanel.Paint;
var
  C: TAlphaColor;
begin
  case FRole of
    prBg: C := Pal.Bg;
    prSurface: C := Pal.Surface;
    prSurface2: C := Pal.Surface2;
    prAccentSoft: C := Pal.AccentSoft;
  else
    C := TAlphaColors.Null;
  end;
  if FRole <> prNone then
    FillRound(Canvas, LocalRect, FRadius, C);
  if FBordered then
    StrokeRound(Canvas, LocalRect, FRadius, Pal.Border);
end;

{ TCMLogo }

procedure TCMLogo.Paint;
var
  S: Single;
  R: TRectF;
begin
  S := Min(Width, Height);
  R := TRectF.Create(0, 0, S, S);
  R.SetLocation((Width - S) / 2, (Height - S) / 2);
  FillRound(Canvas, R, S * 0.22, Pal.Accent);
  // Os colchetes ocupam 16/24 do glifo; 0,56 do lado do selo, como no .ico
  R.Inflate(-S * 0.5 * (1 - 0.56 * 24 / 16), -S * 0.5 * (1 - 0.56 * 24 / 16));
  DrawIcon(Canvas, icBrackets, R, Pal.OnAccent);
end;

{ TCMLabel }

constructor TCMLabel.Create(AOwner: TComponent);
begin
  inherited;
  FSize := 13;
  FHAlign := TTextAlign.Leading;
  Height := 20;
end;

class function TCMLabel.Make(AParent: TFmxObject; const AText: string; ASize: Single;
  ABold: Boolean; AColor: TLabelColor; AMono: Boolean): TCMLabel;
begin
  Result := TCMLabel.Create(AParent);
  Result.Parent := AParent;
  Result.FText := AText;
  Result.FSize := ASize;
  Result.FBold := ABold;
  Result.FColorRole := AColor;
  Result.FMono := AMono;
  Result.Height := Ceil(ASize * 1.6);
end;

procedure TCMLabel.SetText(const Value: string);
begin
  if FText <> Value then
  begin
    FText := Value;
    Repaint;
  end;
end;

procedure TCMLabel.SetColorRole(const Value: TLabelColor);
begin
  FColorRole := Value;
  Repaint;
end;

procedure TCMLabel.Paint;
var
  Family: string;
  Style: TFontStyles;
  S: string;
begin
  if FMono then Family := MonoFont else Family := UiFont;
  if FBold then Style := [TFontStyle.fsBold] else Style := [];
  Canvas.Font.Family := Family;
  Canvas.Font.Size := FSize;
  Canvas.Font.Style := Style;
  if FWrap then
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := LabelColor(FColorRole);
    Canvas.FillText(LocalRect, FText, True, 1, [], FHAlign, TTextAlign.Leading);
    Exit;
  end;
  S := FitText(Canvas, FText, Width);
  DrawTextRect(Canvas, LocalRect, S, LabelColor(FColorRole), FSize, Family, Style, FHAlign);
end;

{ TCMButton }

constructor TCMButton.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  Cursor := crHandPoint;
  Height := 36;
  FKind := bkSecondary;
  CanFocus := False;
end;

class function TCMButton.Make(AParent: TFmxObject; const AText: string; AIcon: TIconKind;
  AKind: TButtonKind; AHandler: TNotifyEvent): TCMButton;
begin
  Result := TCMButton.Create(AParent);
  Result.Parent := AParent;
  Result.FKind := AKind;
  Result.FText := AText;
  Result.FIcon := AIcon;
  Result.FHasIcon := True;
  Result.OnClick := AHandler;
  Result.UpdateWidth;
end;

class function TCMButton.MakeIcon(AParent: TFmxObject; AIcon: TIconKind; AHandler: TNotifyEvent;
  const AHint: string): TCMButton;
begin
  Result := TCMButton.Create(AParent);
  Result.Parent := AParent;
  Result.FKind := bkGhost;
  Result.FIcon := AIcon;
  Result.FHasIcon := True;
  Result.FIconOnly := True;
  Result.OnClick := AHandler;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.Width := 36;
end;

function TCMButton.NaturalWidth: Single;
begin
  Result := 28 + MeasureText(FText, 13, UiFont, [TFontStyle.fsBold]);
  if FHasIcon then
    Result := Result + 21;
  Result := Ceil(Result);
end;

procedure TCMButton.UpdateWidth;
begin
  if FIconOnly then
    Exit;
  Width := NaturalWidth;
end;

procedure TCMButton.SetText(const Value: string);
begin
  FText := Value;
  UpdateWidth;
  Repaint;
end;

procedure TCMButton.SetIcon(const Value: TIconKind);
begin
  FIcon := Value;
  FHasIcon := True;
  UpdateWidth;
  Repaint;
end;

procedure TCMButton.SetActive(const Value: Boolean);
begin
  FActive := Value;
  Repaint;
end;

procedure TCMButton.EnabledChanged;
begin
  inherited;
  Repaint;
end;

procedure TCMButton.Paint;
var
  P: TPalette;
  R, IR, TR: TRectF;
  Fill, Line, Fg: TAlphaColor;
  HasFill, HasLine: Boolean;
  Alpha: Single;
begin
  P := Pal;
  R := LocalRect;
  HasFill := True;
  HasLine := True;
  Line := TAlphaColors.Null;
  case FKind of
    bkPrimary:
      begin
        Fill := P.Accent;
        if FHover then Fill := P.AccentStrong;
        Fg := P.OnAccent;
        HasLine := False;
      end;
    bkGhost:
      begin
        Fill := P.Surface2;
        HasFill := FHover or FDown;
        if FHover then Fg := P.Text else Fg := P.TextDim;
        HasLine := False;
      end;
    bkDanger:
      begin
        Fill := P.Surface;
        Line := P.Border;
        Fg := P.TextDim;
        if FHover then
        begin
          Line := P.Danger;
          Fg := P.Danger;
        end;
      end;
  else
    Fill := P.Surface;
    Line := P.Border;
    Fg := P.TextDim;
    if FHover then
    begin
      Line := P.Accent;
      Fg := P.Accent;
    end;
  end;
  if FActive and (FKind <> bkPrimary) then
  begin
    Fill := P.AccentSoft;
    Line := P.Accent;
    Fg := P.AccentStrong;
    HasFill := True;
    HasLine := True;
  end;
  if FDown then
    Fill := Pick(FKind = bkPrimary, P.AccentStrong, P.Surface2);

  Alpha := IfThen(Enabled, 1.0, 0.45);
  if HasFill then
    FillRound(Canvas, R, 9, Fade(Fill, Alpha));
  if HasLine then
    StrokeRound(Canvas, R, 9, Fade(Line, Alpha));

  if FIconOnly then
  begin
    IR := TRectF.Create(0, 0, 18, 18);
    IR.SetLocation((R.Width - 18) / 2, (R.Height - 18) / 2);
    DrawIcon(Canvas, FIcon, IR, Fade(Fg, Alpha));
    Exit;
  end;

  TR := R;
  TR.Left := 14;
  if FHasIcon then
  begin
    IR := TRectF.Create(0, 0, 16, 16);
    IR.SetLocation(13, (R.Height - 16) / 2);
    DrawIcon(Canvas, FIcon, IR, Fade(Fg, Alpha));
    TR.Left := 34;
  end;
  TR.Right := R.Right - 8;
  DrawTextRect(Canvas, TR, FText, Fade(Fg, Alpha), 13, UiFont, [TFontStyle.fsBold]);
end;

{ TCMNavButton }

constructor TCMNavButton.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  Cursor := crHandPoint;
  Height := 62;
end;

procedure TCMNavButton.SetSelected(const Value: Boolean);
begin
  FSelected := Value;
  Repaint;
end;

procedure TCMNavButton.Paint;
var
  P: TPalette;
  R, IR, TR, BubbleR: TRectF;
  Fg: TAlphaColor;
  Style: TFontStyles;
begin
  P := Pal;
  R := LocalRect;
  BubbleR := TRectF.Create(0, 0, 44, 30);
  BubbleR.SetLocation((R.Width - 44) / 2, 6);
  if FSelected then
    FillRound(Canvas, BubbleR, 15, P.AccentSoft)
  else if FHover then
    FillRound(Canvas, BubbleR, 15, P.Surface2);
  if FSelected then Fg := P.Accent else if FHover then Fg := P.Text else Fg := P.TextDim;
  IR := TRectF.Create(0, 0, 20, 20);
  IR.SetLocation((R.Width - 20) / 2, 11);
  DrawIcon(Canvas, FIcon, IR, Fg);
  TR := TRectF.Create(0, 40, R.Width, R.Height - 4);
  if FSelected then Style := [TFontStyle.fsBold] else Style := [];
  DrawTextRect(Canvas, TR, FText, Pick(FSelected, P.AccentStrong, P.TextDim), 10.5, UiFont,
    Style, TTextAlign.Center, TTextAlign.Leading);
end;

{ TCMSwitch }

constructor TCMSwitch.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  Cursor := crHandPoint;
  Height := 30;
end;

procedure TCMSwitch.SetChecked(const Value: Boolean);
begin
  if FChecked <> Value then
  begin
    FChecked := Value;
    Repaint;
  end;
end;

procedure TCMSwitch.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if (Button = TMouseButton.mbLeft) and PointInObjectLocal(X, Y) then
  begin
    FChecked := not FChecked;
    Repaint;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
end;

procedure TCMSwitch.Paint;
var
  P: TPalette;
  Track, Knob, TR: TRectF;
begin
  P := Pal;
  Track := TRectF.Create(0, 0, 38, 22);
  Track.SetLocation(0, (Height - 22) / 2);
  if FChecked then
    FillRound(Canvas, Track, 11, P.Accent)
  else
  begin
    FillRound(Canvas, Track, 11, P.Surface2);
    StrokeRound(Canvas, Track, 11, P.BorderStrong);
  end;
  Knob := TRectF.Create(0, 0, 16, 16);
  Knob.SetLocation(Track.Left + IfThen(FChecked, 19, 3), Track.Top + 3);
  FillRound(Canvas, Knob, 8, Pick(FChecked, P.OnAccent, P.TextFaint));
  TR := TRectF.Create(48, 0, Width, Height);
  DrawTextRect(Canvas, TR, FText, P.Text, 13, UiFont);
end;

{ TCMInput }

constructor TCMInput.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  Height := 40;
  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.StyleLookup := 'transparentedit';
  FEdit.StyledSettings := [];
  FEdit.OnEnter := EditEnter;
  FEdit.OnExit := EditExit;
  FEdit.OnChangeTracking := EditChange;
  ApplyTheme;
end;

function TCMInput.LeftPad: Single;
begin
  Result := IfThen(FHasIcon, 40, 14);
end;

function TCMInput.RightPad: Single;
begin
  Result := IfThen(FHasTrailing, 44, 12);
end;

procedure TCMInput.ApplyTheme;
begin
  FEdit.TextSettings.Font.Family := UiFont;
  FEdit.TextSettings.Font.Size := 13.5;
  FEdit.TextSettings.FontColor := Pal.Text;
  FEdit.Repaint;
  Repaint;
end;

procedure TCMInput.LayoutEdit;
begin
  if FEdit = nil then
    Exit;
  FEdit.SetBounds(LeftPad, (Height - 26) / 2, Max(20, Width - LeftPad - RightPad), 26);
end;

procedure TCMInput.Resize;
begin
  inherited;
  LayoutEdit;
end;

procedure TCMInput.SetLeadingIcon(AIcon: TIconKind);
begin
  FIcon := AIcon;
  FHasIcon := True;
  LayoutEdit;
end;

procedure TCMInput.SetTrailingIcon(AIcon: TIconKind);
begin
  FTrailing := AIcon;
  FHasTrailing := True;
  Cursor := crDefault;
  LayoutEdit;
end;

function TCMInput.GetText: string;
begin
  Result := FEdit.Text;
end;

procedure TCMInput.SetText(const Value: string);
begin
  FEdit.Text := Value;
end;

function TCMInput.GetPlaceholder: string;
begin
  Result := FEdit.TextPrompt;
end;

procedure TCMInput.SetPlaceholder(const Value: string);
begin
  FEdit.TextPrompt := Value;
end;

procedure TCMInput.EditEnter(Sender: TObject);
begin
  FFocused := True;
  Repaint;
end;

procedure TCMInput.EditExit(Sender: TObject);
begin
  FFocused := False;
  Repaint;
end;

procedure TCMInput.EditChange(Sender: TObject);
begin
  if Assigned(FOnChangeText) then
    FOnChangeText(Self);
end;

procedure TCMInput.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if FHasTrailing and (Button = TMouseButton.mbLeft) and (X >= Width - 44) then
  begin
    if Assigned(FOnTrailingClick) then
      FOnTrailingClick(Self);
  end
  else
    FEdit.SetFocus;
end;

procedure TCMInput.Paint;
var
  P: TPalette;
  R, IR: TRectF;
begin
  P := Pal;
  R := LocalRect;
  FillRound(Canvas, R, 10, P.Surface);
  StrokeRound(Canvas, R, 10, Pick(FFocused, P.Accent, P.Border), IfThen(FFocused, 1.5, 1));
  if FHasIcon then
  begin
    IR := TRectF.Create(0, 0, 18, 18);
    IR.SetLocation(13, (Height - 18) / 2);
    DrawIcon(Canvas, FIcon, IR, P.TextFaint);
  end;
  if FHasTrailing then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := P.Border;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(PointF(Width - 44, 8), PointF(Width - 44, Height - 8), 1);
    IR := TRectF.Create(0, 0, 18, 18);
    IR.SetLocation(Width - 44 + 13, (Height - 18) / 2);
    DrawIcon(Canvas, FTrailing, IR, Pick(FHover, P.Accent, P.TextDim));
  end;
end;

{ TCMProgress }

constructor TCMProgress.Create(AOwner: TComponent);
begin
  inherited;
  Height := 8;
end;

procedure TCMProgress.SetValue(const Value: Single);
begin
  FValue := EnsureRange(Value, 0, 1);
  Repaint;
end;

procedure TCMProgress.Paint;
var
  R, F: TRectF;
begin
  R := LocalRect;
  FillRound(Canvas, R, R.Height / 2, Pal.Surface2);
  if FValue > 0 then
  begin
    F := R;
    F.Right := F.Left + Max(R.Height, R.Width * FValue);
    FillRound(Canvas, F, R.Height / 2, Pal.Accent);
  end;
end;

{ TCMKeyValue }

constructor TCMKeyValue.Create(AOwner: TComponent);
begin
  inherited;
end;

procedure TCMKeyValue.SetRows(const ARows: TArray<TKeyValue>);
begin
  FRows := ARows;
  Height := Length(FRows) * 28;
  Repaint;
end;

procedure TCMKeyValue.Paint;
var
  I: Integer;
  R: TRectF;
begin
  for I := 0 to High(FRows) do
  begin
    R := TRectF.Create(0, I * 28, Width, I * 28 + 28);
    DrawTextRect(Canvas, R, FRows[I].Caption, Pal.TextDim, 12.5, UiFont);
    DrawTextRect(Canvas, R, FRows[I].Value, Pick(FRows[I].Highlight, Pal.Accent, Pal.Text),
      13, MonoFont, [TFontStyle.fsBold], TTextAlign.Trailing);
  end;
end;

{ TCMRing }

constructor TCMRing.Create(AOwner: TComponent);
begin
  inherited;
  Height := 112;
end;

procedure TCMRing.SetValues(APct: Single; const ACaption, ASub: string; AMethodsPct: Single;
  const AMethodsCaption: string);
begin
  FPct := EnsureRange(APct, 0, 1);
  FCaption := ACaption;
  FSub := ASub;
  FMethodsPct := EnsureRange(AMethodsPct, 0, 1);
  FMethodsCaption := AMethodsCaption;
  Repaint;
end;

procedure TCMRing.Paint;
var
  P: TPalette;
  C: TPointF;
  Rad: Single;
  TR, BarR, FillR: TRectF;
begin
  P := Pal;
  C := PointF(36, 36);
  Rad := 30;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Thickness := 7;
  Canvas.Stroke.Cap := TStrokeCap.Round;
  Canvas.Stroke.Color := P.Surface2;
  Canvas.DrawEllipse(TRectF.Create(C.X - Rad, C.Y - Rad, C.X + Rad, C.Y + Rad), 1);
  if FPct > 0.001 then
  begin
    Canvas.Stroke.Color := P.Accent;
    Canvas.DrawArc(C, PointF(Rad, Rad), -90, Min(359.9, 360 * FPct), 1);
  end;
  TR := TRectF.Create(84, 8, Width, 40);
  DrawTextRect(Canvas, TR, FCaption, P.Text, 26, MonoFont, [TFontStyle.fsBold]);
  TR := TRectF.Create(84, 38, Width, 56);
  DrawTextRect(Canvas, TR, 'concluído', P.TextDim, 12, UiFont);
  TR := TRectF.Create(84, 54, Width, 72);
  DrawTextRect(Canvas, TR, FSub, P.TextFaint, 11.5, MonoFont);

  TR := TRectF.Create(0, 78, Width, 96);
  DrawTextRect(Canvas, TR, 'Métodos revistos', P.TextDim, 11.5, MonoFont);
  DrawTextRect(Canvas, TR, FMethodsCaption, P.Pending, 11.5, MonoFont, [TFontStyle.fsBold],
    TTextAlign.Trailing);
  BarR := TRectF.Create(0, 100, Width, 105);
  FillRound(Canvas, BarR, 2.5, P.Surface2);
  if FMethodsPct > 0 then
  begin
    FillR := BarR;
    FillR.Right := FillR.Left + Max(5, BarR.Width * FMethodsPct);
    FillRound(Canvas, FillR, 2.5, P.Star);
  end;
end;

{ TCMBars }

constructor TCMBars.Create(AOwner: TComponent);
begin
  inherited;
end;

procedure TCMBars.SetRows(const ARows: TArray<TBarRow>);
begin
  FRows := ARows;
  Height := Max(1, Length(FRows) * 24);
  Repaint;
end;

procedure TCMBars.Paint;
var
  I: Integer;
  Y, TrackL, TrackR: Single;
  R, Track, F: TRectF;
  Pct: Single;
begin
  TrackL := 104;
  TrackR := Width - 44;
  for I := 0 to High(FRows) do
  begin
    Y := I * 24;
    R := TRectF.Create(0, Y, TrackL - 8, Y + 24);
    Canvas.Font.Family := MonoFont;
    Canvas.Font.Size := 11.5;
    DrawTextRect(Canvas, R, FitText(Canvas, FRows[I].Name, R.Width), Pal.TextDim, 11.5, MonoFont);
    Track := TRectF.Create(TrackL, Y + 10, TrackR, Y + 15);
    FillRound(Canvas, Track, 2.5, Pal.Surface2);
    if FRows[I].Total > 0 then
      Pct := FRows[I].Done / FRows[I].Total
    else
      Pct := 0;
    if Pct > 0 then
    begin
      F := Track;
      F.Right := F.Left + Max(5, Track.Width * Pct);
      FillRound(Canvas, F, 2.5, Pal.Accent);
    end;
    R := TRectF.Create(TrackR + 6, Y, Width, Y + 24);
    DrawTextRect(Canvas, R, Format('%d/%d', [FRows[I].Done, FRows[I].Total]), Pal.TextFaint, 11,
      MonoFont, [], TTextAlign.Trailing);
  end;
end;

{ TCMList }

constructor TCMList.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  Cursor := crHandPoint;
  FIndex := -1;
  FHoverIdx := -1;
end;

procedure TCMList.SetItems(const AItems: TArray<TListEntry>; ASelected: Integer);
begin
  FItems := AItems;
  FIndex := ASelected;
  Repaint;
end;

function TCMList.IndexAt(Y: Single): Integer;
begin
  Result := Trunc(Y / RowHeightList);
  if (Result < 0) or (Result > High(FItems)) then
    Result := -1;
end;

procedure TCMList.MouseMove(Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  I := IndexAt(Y);
  if I <> FHoverIdx then
  begin
    FHoverIdx := I;
    Repaint;
  end;
end;

procedure TCMList.DoMouseLeave;
begin
  inherited;
  FHoverIdx := -1;
end;

procedure TCMList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  I: Integer;
begin
  inherited;
  I := IndexAt(Y);
  if (Button = TMouseButton.mbLeft) and (I >= 0) and (I <> FIndex) then
  begin
    FIndex := I;
    Repaint;
    if Assigned(FOnSelect) then
      FOnSelect(Self);
  end;
end;

procedure TCMList.Paint;
var
  I: Integer;
  P: TPalette;
  R, TR, BR: TRectF;
  BadgeW: Single;
begin
  P := Pal;
  for I := 0 to High(FItems) do
  begin
    R := TRectF.Create(0, I * RowHeightList, Width, I * RowHeightList + RowHeightList - 6);
    if I = FIndex then
    begin
      FillRound(Canvas, R, 10, P.AccentSoft);
      StrokeRound(Canvas, R, 10, P.Accent);
    end
    else if I = FHoverIdx then
      FillRound(Canvas, R, 10, P.Surface2);
    TR := TRectF.Create(R.Left + 14, R.Top + 8, R.Right - 14, R.Top + 30);
    Canvas.Font.Family := UiFont;
    Canvas.Font.Size := 13.5;
    Canvas.Font.Style := [TFontStyle.fsBold];
    if FItems[I].Badge <> '' then
    begin
      BadgeW := MeasureText(FItems[I].Badge, 10, MonoFont) + 14;
      BR := TRectF.Create(R.Right - 14 - BadgeW, R.Top + 10, R.Right - 14, R.Top + 28);
      FillRound(Canvas, BR, 9, P.Accent);
      DrawTextRect(Canvas, BR, FItems[I].Badge, P.OnAccent, 10, MonoFont, [], TTextAlign.Center);
      TR.Right := BR.Left - 8;
    end;
    DrawTextRect(Canvas, TR, FitText(Canvas, FItems[I].Title, TR.Width),
      Pick(I = FIndex, P.AccentStrong, P.Text), 13.5, UiFont, [TFontStyle.fsBold]);
    TR := TRectF.Create(R.Left + 14, R.Top + 30, R.Right - 14, R.Bottom - 6);
    Canvas.Font.Family := MonoFont;
    Canvas.Font.Size := 11;
    Canvas.Font.Style := [];
    DrawTextRect(Canvas, TR, FitText(Canvas, FItems[I].Sub, TR.Width), P.TextFaint, 11, MonoFont);
  end;
end;

{ TCMToast }

constructor TCMToast.Create(AOwner: TComponent);
begin
  inherited;
  Visible := False;
  HitTest := False;
  Height := 38;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 2200;
  FTimer.OnTimer := HideNow;
end;

procedure TCMToast.HideNow(Sender: TObject);
begin
  FTimer.Enabled := False;
  Visible := False;
end;

procedure TCMToast.ShowText(const AText: string);
begin
  FText := AText;
  Width := MeasureText(AText, 13, UiFont) + 40;
  if Parent is TControl then
    Position.Point := PointF((TControl(Parent).Width - Width) / 2, TControl(Parent).Height - Height - 28);
  Visible := True;
  BringToFront;
  Repaint;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TCMToast.Paint;
begin
  FillRound(Canvas, LocalRect, 10, Pal.AccentStrong);
  DrawTextRect(Canvas, LocalRect, FText, Pal.OnAccent, 13, UiFont, [], TTextAlign.Center);
end;

end.
