unit CM.Layouts;

{ Controlos de disposicao e construtores de blocos usados pelas paginas da janela principal:
  linha de botoes, fluxo de "chips" e cartoes/campos com as margens e alturas da aplicacao. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  FMX.Types, FMX.Controls, FMX.Graphics, FMX.Layouts,
  CM.Theme, CM.Controls, CM.WidthShare;

type
  TCMButtonRow = class(TCMControl)
  private
    FWrap: Boolean;
    procedure ResizeWrapped;
  protected
    procedure Resize; override;
  public
    procedure Relayout;
    // Wrap: os botoes mantem a largura natural, ocupam o espaco disponivel na mesma linha
    // e so quebram para a linha seguinte quando ja nao cabem (a altura do cartao acompanha).
    property Wrap: Boolean read FWrap write FWrap;
  end;

  // coluna que desliza sem barra de scroll nativa: mostra um esbatido nas bordas com mais conteudo
  // e um indicador fino da posicao, nas cores do tema
  TCMFadeScroll = class(TVertScrollBox)
  protected
    procedure PaintChildren; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  // grelha de cartoes: os filhos ocupam N colunas iguais, linha a linha, com intervalos de 14 px
  // (o Padding.Bottom da linha fica livre para o espaco ate a linha seguinte)
  TCMCardRow = class(TCMControl)
  private
    FColumns: Integer;
    procedure SetColumns(const Value: Integer);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    // altura da linha para celulas com ACellHeight (conforme as colunas e o numero de filhos)
    function HeightFor(ACellHeight: Single): Single;
    property Columns: Integer read FColumns write SetColumns;
  end;

  TCMChipFlow = class(TCMControl)
  private
    FOnRelayout: TNotifyEvent;
  protected
    procedure Resize; override;
  public
    procedure Relayout;
    // avisa quando a altura mudou (o cartao que o contem ajusta-se)
    property OnRelayout: TNotifyEvent read FOnRelayout write FOnRelayout;
  end;

function NewCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
function SideCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
function SideBox(AOwner: TComponent; AParent: TFmxObject; AWidth: Single): TCMFadeScroll;
function AddField(AOwner: TComponent; AParent: TFmxObject; const ACaption, APlaceholder: string;
  ABrowse: Boolean): TCMInput;
function NewButtonRow(AOwner: TComponent; AParent: TFmxObject): TCMButtonRow;

implementation

{ TCMButtonRow: divide a largura entre os botoes (por igual; os de texto comprido ficam com a largura natural) }

procedure TCMButtonRow.ResizeWrapped;
const
  Gap = 8;
  LineH = 36;
var
  I, J, First, Count, Lines: Integer;
  Btns: TArray<TCMButton>;
  LineW, Extra, X, Y, NewH: Single;
begin
  Btns := nil;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TCMButton then
    begin
      SetLength(Btns, Length(Btns) + 1);
      Btns[High(Btns)] := TCMButton(Children[I]);
    end;
  if (Length(Btns) = 0) or (Width <= 0) then
    Exit;
  Lines := 0;
  Y := 0;
  First := 0;
  while First < Length(Btns) do
  begin
    // enche a linha com o maximo de botoes que cabem na largura natural
    Count := 1;
    LineW := Btns[First].NaturalWidth;
    while (First + Count < Length(Btns)) and
      (LineW + Gap + Btns[First + Count].NaturalWidth <= Width) do
    begin
      LineW := LineW + Gap + Btns[First + Count].NaturalWidth;
      Inc(Count);
    end;
    // a folga da linha e repartida por igual entre os botoes dela
    Extra := Max(0, Width - LineW) / Count;
    X := 0;
    for J := First to First + Count - 1 do
    begin
      Btns[J].SetBounds(X, Y, Btns[J].NaturalWidth + Extra, LineH);
      X := X + Btns[J].Width + Gap;
    end;
    Inc(Lines);
    Y := Y + LineH + Gap;
    Inc(First, Count);
  end;
  NewH := Lines * LineH + (Lines - 1) * Gap;
  if not SameValue(NewH, Height) then
  begin
    if Parent is TControl then
      TControl(Parent).Height := TControl(Parent).Height + (NewH - Height);
    Height := NewH;
  end;
end;

procedure TCMButtonRow.Relayout;
begin
  Resize;
end;

procedure TCMButtonRow.Resize;
var
  I, N: Integer;
  X: Single;
  B: TCMButton;
  Natural, Widths: TArray<Single>;
  Btns: TArray<TCMButton>;
begin
  inherited;
  if FWrap then
  begin
    ResizeWrapped;
    Exit;
  end;
  Btns := nil;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TCMButton then
    begin
      SetLength(Btns, Length(Btns) + 1);
      Btns[High(Btns)] := TCMButton(Children[I]);
    end;
  N := Length(Btns);
  if N = 0 then
    Exit;
  // parte igual para todos; quem tem um texto que nao cabe (idiomas mais compridos) fica com a largura natural
  SetLength(Natural, N);
  for I := 0 to N - 1 do
    if Btns[I].IconOnly then
      Natural[I] := 0
    else
      Natural[I] := Btns[I].NaturalWidth;
  Widths := ShareWidths(Width - (N - 1) * 8, Natural);
  X := 0;
  for I := 0 to N - 1 do
  begin
    B := Btns[I];
    B.SetBounds(X, 0, Widths[I], Height);
    X := X + Widths[I] + 8;
  end;
end;

{ TCMFadeScroll }

constructor TCMFadeScroll.Create(AOwner: TComponent);
begin
  inherited;
  Padding.Right := 10;           // faixa livre para o indicador de posicao
end;

procedure TCMFadeScroll.PaintChildren;
const
  FadeH = 38;
  ThumbW = 4;
var
  Total, ViewH, Top, ThumbH, ThumbY: Single;
  R: TRectF;

  function Tint(AAlpha: Byte): TAlphaColor;
  begin
    Result := (Pal.Bg and $00FFFFFF) or (TAlphaColor(AAlpha) shl 24);
  end;

  procedure Fade(const ARect: TRectF; AFromAlpha, AToAlpha: Byte);
  begin
    Canvas.Fill.Kind := TBrushKind.Gradient;
    Canvas.Fill.Gradient.Style := TGradientStyle.Linear;
    Canvas.Fill.Gradient.StartPosition.Point := PointF(0, 0);
    Canvas.Fill.Gradient.StopPosition.Point := PointF(0, 1);
    Canvas.Fill.Gradient.Points[0].Color := Tint(AFromAlpha);
    Canvas.Fill.Gradient.Points[0].Offset := 0;
    Canvas.Fill.Gradient.Points[1].Color := Tint(AToAlpha);
    Canvas.Fill.Gradient.Points[1].Offset := 1;
    Canvas.FillRect(ARect, 0, 0, [], 1);
  end;

begin
  inherited;
  Total := ContentBounds.Height;
  ViewH := Height;
  if Total <= ViewH + 1 then
    Exit;                                   // cabe tudo: nada a indicar
  Top := ViewportPosition.Y;
  // depois de pintar os filhos o canvas continua deslocado pelo scroll (as coordenadas sao as do conteudo):
  // soma-se Top para o esbatido e o indicador ficarem colados as bordas visiveis e nao andarem com o conteudo
  if Top + ViewH < Total - 1 then
    Fade(TRectF.Create(0, Top + ViewH - FadeH, Width, Top + ViewH), 0, 235);
  if Top > 1 then
    Fade(TRectF.Create(0, Top, Width, Top + FadeH * 0.6), 235, 0);
  // indicador de posicao (fino, junto a borda direita)
  ThumbH := Max(28, ViewH * ViewH / Total);
  ThumbY := Top + (ViewH - ThumbH) * Top / (Total - ViewH);
  R := TRectF.Create(Width - ThumbW - 2, ThumbY, Width - 2, ThumbY + ThumbH);
  FillRound(Canvas, R, ThumbW / 2, Pal.BorderStrong);
end;

{ TCMCardRow }

const
  CardGap = 14;

constructor TCMCardRow.Create(AOwner: TComponent);
begin
  inherited;
  FColumns := 2;
end;

procedure TCMCardRow.SetColumns(const Value: Integer);
begin
  if (Value >= 1) and (Value <> FColumns) then
  begin
    FColumns := Value;
    Resize;
  end;
end;

function TCMCardRow.HeightFor(ACellHeight: Single): Single;
var
  I, N, Rows: Integer;
begin
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TControl then
      Inc(N);
  Rows := Max(1, (N + FColumns - 1) div FColumns);
  Result := Rows * ACellHeight + (Rows - 1) * CardGap + Padding.Bottom;
end;

procedure TCMCardRow.Resize;
var
  I, N, Rows, Col, Row: Integer;
  CellW, CellH: Single;
begin
  inherited;
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TControl then
      Inc(N);
  if N = 0 then
    Exit;
  Rows := (N + FColumns - 1) div FColumns;
  CellW := (Width - (FColumns - 1) * CardGap) / FColumns;
  CellH := (Height - Padding.Bottom - (Rows - 1) * CardGap) / Rows;
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TControl then
    begin
      Col := N mod FColumns;
      Row := N div FColumns;
      TControl(Children[I]).SetBounds(Col * (CellW + CardGap), Row * (CellH + CardGap), CellW, CellH);
      Inc(N);
    end;
end;

{ TCMChipFlow: quebra de linha automatica para os filtros por camada }

procedure TCMChipFlow.Relayout;
var
  I: Integer;
  X, Y, RowH, NewH: Single;
  C: TControl;
begin
  X := 0;
  Y := 0;
  RowH := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TControl then
    begin
      C := TControl(Children[I]);
      if (X > 0) and (X + C.Width > Width) then
      begin
        X := 0;
        Y := Y + RowH + 6;
        RowH := 0;
      end;
      C.SetBounds(X, Y, C.Width, C.Height);
      X := X + C.Width + 6;
      RowH := Max(RowH, C.Height);
    end;
  NewH := Max(1, Y + RowH);
  if not SameValue(NewH, Height) then
  begin
    Height := NewH;
    if Assigned(FOnRelayout) then
      FOnRelayout(Self);
  end;
end;

procedure TCMChipFlow.Resize;
begin
  inherited;
  Relayout;
end;

{ construtores de blocos }

function NewCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
begin
  Result := TCMPanel.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Top;
  Result.Height := AHeight;
  Result.Margins.Bottom := 16;
  Result.Padding.Rect := TRectF.Create(22, 18, 22, 18);
end;

function SideCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
begin
  Result := NewCard(AOwner, AParent, AHeight);
  Result.Padding.Rect := TRectF.Create(18, 16, 18, 16);
  Result.Margins.Bottom := 14;
end;

function SideBox(AOwner: TComponent; AParent: TFmxObject; AWidth: Single): TCMFadeScroll;
begin
  Result := TCMFadeScroll.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Right;
  Result.Width := AWidth;
  Result.Margins.Left := 20;
  Result.ShowScrollBars := False;
end;

function AddField(AOwner: TComponent; AParent: TFmxObject; const ACaption, APlaceholder: string;
  ABrowse: Boolean): TCMInput;
var
  Lbl: TCMLabel;
begin
  Lbl := TCMLabel.Make(AParent, ACaption, 12.5, True, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Margins.Top := 14;
  Lbl.Height := 20;
  Result := TCMInput.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Top;
  Result.Height := 42;
  Result.Margins.Top := 6;
  Result.Placeholder := APlaceholder;
  if ABrowse then
    Result.SetTrailingIcon(icBrowse);
end;

function NewButtonRow(AOwner: TComponent; AParent: TFmxObject): TCMButtonRow;
begin
  Result := TCMButtonRow.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := TAlignLayout.Top;
  Result.Height := 36;
  Result.Margins.Bottom := 8;
end;

end.
