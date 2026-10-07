unit CM.SbomView;

{ A lista dos componentes de um SBOM: uma linha por componente, com o nome, a origem, a confianca, quantas units a usam e
  o inicio do hash. Desliza com a roda do rato; a dica de cada linha traz os pormenores. A pagina SBOM monta as linhas
  (ja filtradas e no idioma activo) e entrega-as aqui. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, FMX.Types, FMX.Controls, FMX.Graphics,
  CM.Theme, CM.Controls;

type
  TSbomRow = record
    Name: string;
    OriginText: string;
    OriginColor: TAlphaColor;
    ConfidenceText: string;
    ConfidenceColor: TAlphaColor;
    LicenseText: string;        // o identificador SPDX, ou '' (mostra-se um travessao)
    LicenseKnown: Boolean;
    UsedBy: Integer;
    HashText: string;           // o inicio do hash ('' = sem hash)
    Hint: string;
  end;

  TCMSbomList = class(TCMControl)
  private
    FRows: TArray<TSbomRow>;
    FScrollY: Single;
    FHover: Integer;
    FEmptyText: string;
    FHeaders: array[0..5] of string;
    function MaxScroll: Single;
    function RowAt(Y: Single): Integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRows(const ARows: TArray<TSbomRow>);
    // os titulos das colunas: Unit, Origem, Licenca, Confianca, Usada por, SHA-256
    procedure SetHeaders(const AUnit, AOrigin, ALicense, AConfidence, AUsedBy, AHash: string);
    property EmptyText: string read FEmptyText write FEmptyText;
    function RowCount: Integer;
  end;

implementation

const
  RowH = 30;
  HeadH = 30;
  OriginW = 150;
  LicenseW = 112;
  ConfW = 84;
  UsedW = 70;
  HashW = 140;

constructor TCMSbomList.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  ClipChildren := True;
  FHover := -1;
end;

function TCMSbomList.RowCount: Integer;
begin
  Result := Length(FRows);
end;

procedure TCMSbomList.SetRows(const ARows: TArray<TSbomRow>);
begin
  FRows := ARows;
  FScrollY := 0;
  FHover := -1;
  Repaint;
end;

procedure TCMSbomList.SetHeaders(const AUnit, AOrigin, ALicense, AConfidence, AUsedBy, AHash: string);
begin
  FHeaders[0] := AUnit;
  FHeaders[1] := AOrigin;
  FHeaders[2] := AConfidence;
  FHeaders[3] := AUsedBy;
  FHeaders[4] := AHash;
  FHeaders[5] := ALicense;
  Repaint;
end;

function TCMSbomList.MaxScroll: Single;
begin
  Result := Max(0, Length(FRows) * RowH + 8 - (Height - HeadH));
end;

function TCMSbomList.RowAt(Y: Single): Integer;
begin
  Result := Trunc((Y - HeadH - 4 + FScrollY) / RowH);
  if (Y < HeadH) or (Result < 0) or (Result >= Length(FRows)) then
    Result := -1;
end;

procedure TCMSbomList.Paint;
var
  I, First: Integer;
  Y, NameW, X: Single;
  R, TagR: TRectF;
  Row: TSbomRow;
  TrackH, ThumbH: Single;
  ThumbR: TRectF;

  procedure Tag(const AText: string; AColor: TAlphaColor; ALeft, AWidth: Single);
  var
    W: Single;
  begin
    W := Min(AWidth - 10, MeasureText(AText, 10, UiFont, [TFontStyle.fsBold]) + 14);
    TagR := TRectF.Create(ALeft, R.CenterPoint.Y - 9, ALeft + W, R.CenterPoint.Y + 9);
    StrokeRound(Canvas, TagR, 9, AColor, 1);
    DrawTextRect(Canvas, TagR, AText, AColor, 10, UiFont, [TFontStyle.fsBold], TTextAlign.Center);
  end;

begin
  NameW := Max(120, Width - 16 - OriginW - LicenseW - ConfW - UsedW - HashW - 20);
  // cabecalho
  X := 12;
  DrawTextRect(Canvas, TRectF.Create(X, 0, X + NameW, HeadH), FHeaders[0], Pal.TextFaint, 11, UiFont, [TFontStyle.fsBold]);
  X := X + NameW + 8;
  DrawTextRect(Canvas, TRectF.Create(X, 0, X + OriginW, HeadH), FHeaders[1], Pal.TextFaint, 11, UiFont, [TFontStyle.fsBold]);
  X := X + OriginW;
  DrawTextRect(Canvas, TRectF.Create(X, 0, X + LicenseW, HeadH), FHeaders[5], Pal.TextFaint, 11, UiFont, [TFontStyle.fsBold]);
  X := X + LicenseW;
  DrawTextRect(Canvas, TRectF.Create(X, 0, X + ConfW, HeadH), FHeaders[2], Pal.TextFaint, 11, UiFont, [TFontStyle.fsBold]);
  X := X + ConfW;
  DrawTextRect(Canvas, TRectF.Create(X, 0, X + UsedW - 10, HeadH), FHeaders[3], Pal.TextFaint, 11, UiFont,
    [TFontStyle.fsBold], TTextAlign.Trailing);
  X := X + UsedW;
  DrawTextRect(Canvas, TRectF.Create(X + 10, 0, X + HashW, HeadH), FHeaders[4], Pal.TextFaint, 11, UiFont,
    [TFontStyle.fsBold]);
  FillRound(Canvas, TRectF.Create(8, HeadH - 1, Width - 8, HeadH), 0, Pal.Border);

  if Length(FRows) = 0 then
  begin
    DrawTextRect(Canvas, TRectF.Create(12, HeadH + 8, Width - 12, HeadH + 40), FEmptyText, Pal.TextFaint, 12, UiFont, [],
      TTextAlign.Leading);
    Exit;
  end;
  First := Max(0, Trunc(FScrollY / RowH));
  for I := First to High(FRows) do
  begin
    Y := HeadH + 4 + I * RowH - FScrollY;
    if Y > Height then
      Break;
    Row := FRows[I];
    R := TRectF.Create(4, Y, Width - 14, Y + RowH - 2);
    if I = FHover then
      FillRound(Canvas, R, 6, Pal.Hover);
    X := 12;
    DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + NameW, R.Bottom), FitText(Canvas, Row.Name, NameW), Pal.Text, 12,
      MonoFont);
    X := X + NameW + 8;
    Tag(Row.OriginText, Row.OriginColor, X, OriginW);
    X := X + OriginW;
    if Row.LicenseText = '' then
      DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + LicenseW - 6, R.Bottom), '—', Pal.TextFaint, 11, MonoFont)
    else if Row.LicenseKnown then
      DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + LicenseW - 6, R.Bottom), FitText(Canvas, Row.LicenseText, LicenseW - 6), Pal.Text, 11, MonoFont)
    else
      DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + LicenseW - 6, R.Bottom), FitText(Canvas, Row.LicenseText, LicenseW - 6), Pal.Pending, 11, MonoFont);
    X := X + LicenseW;
    Tag(Row.ConfidenceText, Row.ConfidenceColor, X, ConfW);
    X := X + ConfW;
    DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + UsedW - 10, R.Bottom), IntToStr(Row.UsedBy), Pal.TextDim, 11.5,
      MonoFont, [], TTextAlign.Trailing);
    X := X + UsedW;
    if Row.HashText <> '' then
      DrawTextRect(Canvas, TRectF.Create(X + 10, R.Top, X + HashW, R.Bottom), Row.HashText, Pal.TextFaint, 11, MonoFont)
    else
      DrawTextRect(Canvas, TRectF.Create(X + 10, R.Top, X + HashW, R.Bottom), '—', Pal.TextFaint, 11, MonoFont);
  end;
  if MaxScroll > 0 then
  begin
    TrackH := Height - HeadH - 8;
    ThumbH := Max(24, TrackH * (Height - HeadH) / (Length(FRows) * RowH + 8));
    ThumbR := TRectF.Create(Width - 9, HeadH + 4 + (TrackH - ThumbH) * (FScrollY / MaxScroll), Width - 3,
      HeadH + 4 + (TrackH - ThumbH) * (FScrollY / MaxScroll) + ThumbH);
    FillRound(Canvas, ThumbR, 3, Fade(Pal.TextFaint, 0.55));
  end;
end;

procedure TCMSbomList.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
begin
  inherited;
  Idx := RowAt(Y);
  if Idx <> FHover then
  begin
    FHover := Idx;
    if Idx >= 0 then
    begin
      Hint := FRows[Idx].Hint;
      ShowHint := True;
    end;
    Repaint;
  end;
end;

procedure TCMSbomList.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  Repaint;
end;

procedure TCMSbomList.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  FScrollY := EnsureRange(FScrollY - WheelDelta / 120 * RowH * 3, 0, MaxScroll);
  Handled := True;
  Repaint;
end;

end.
