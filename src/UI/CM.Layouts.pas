unit CM.Layouts;

{ Controlos de disposicao e construtores de blocos usados pelas paginas da janela principal:
  linha de botoes, fluxo de "chips" e cartoes/campos com as margens e alturas da aplicacao. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  FMX.Types, FMX.Controls, FMX.Layouts,
  CM.Theme, CM.Controls;

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

  // dois blocos lado a lado, cada um com metade da largura (menos o intervalo)
  TCMHalves = class(TCMControl)
  protected
    procedure Resize; override;
  end;

  TCMChipFlow = class(TCMControl)
  protected
    procedure Resize; override;
  public
    procedure Relayout;
  end;

function NewCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
function SideCard(AOwner: TComponent; AParent: TFmxObject; AHeight: Single): TCMPanel;
function SideBox(AOwner: TComponent; AParent: TFmxObject; AWidth: Single): TVertScrollBox;
function AddField(AOwner: TComponent; AParent: TFmxObject; const ACaption, APlaceholder: string;
  ABrowse: Boolean): TCMInput;
function NewButtonRow(AOwner: TComponent; AParent: TFmxObject): TCMButtonRow;

implementation

{ TCMButtonRow: divide a largura por igual entre os botoes }

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
  W: Single;
  B: TCMButton;
begin
  inherited;
  if FWrap then
  begin
    ResizeWrapped;
    Exit;
  end;
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TCMButton then
      Inc(N);
  if N = 0 then
    Exit;
  W := (Width - (N - 1) * 8) / N;
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if Children[I] is TCMButton then
    begin
      B := TCMButton(Children[I]);
      B.SetBounds(N * (W + 8), 0, W, Height);
      Inc(N);
    end;
end;

{ TCMHalves }

procedure TCMHalves.Resize;
const
  Gap = 14;
var
  I, N: Integer;
  W: Single;
begin
  inherited;
  W := (Width - Gap) / 2;
  N := 0;
  for I := 0 to ChildrenCount - 1 do
    if (Children[I] is TControl) and (N < 2) then
    begin
      TControl(Children[I]).SetBounds(N * (W + Gap), 0, W, Height);
      Inc(N);
    end;
end;

{ TCMChipFlow: quebra de linha automatica para os filtros por camada }

procedure TCMChipFlow.Relayout;
var
  I: Integer;
  X, Y, RowH: Single;
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
  Height := Max(1, Y + RowH);
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

function SideBox(AOwner: TComponent; AParent: TFmxObject; AWidth: Single): TVertScrollBox;
begin
  Result := TVertScrollBox.Create(AOwner);
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
