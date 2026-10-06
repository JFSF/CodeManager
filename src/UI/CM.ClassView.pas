unit CM.ClassView;

{ A lista das classes do projecto: uma linha por classe, com o nome (recuado conforme a profundidade no projecto), o tipo, a
  profundidade de heranca, as filhas, os metodos e o ficheiro. Os titulos ordenam (clique) e a roda do rato desliza; a dica
  de cada linha traz a cadeia de ancestrais; o duplo clique abre o codigo. A pagina Classes monta as linhas (filtradas e
  ordenadas, no idioma activo) e entrega-as aqui. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, FMX.Types, FMX.Controls, FMX.Graphics,
  CM.Theme, CM.Controls, CM.Clicks;

type
  TClassRow = record
    Name: string;
    Indent: Integer;
    KindText: string;           // '' para uma classe normal; 'interface', 'objeto'... nos outros
    DepthText: string;
    DepthColor: TAlphaColor;
    Children: Integer;
    Methods: Integer;
    FileText: string;
    Hint: string;
    Tag: Integer;               // o indice da classe, para quem abre o codigo
  end;

  TClassOpenEvent = procedure(Sender: TObject; ATag: Integer) of object;
  TClassSortEvent = procedure(Sender: TObject; AColumn: Integer) of object;

  TCMClassList = class(TCMControl)
  private
    FRows: TArray<TClassRow>;
    FScrollY: Single;
    FHover: Integer;
    FEmptyText: string;
    FHeaders: array[0..4] of string;
    FSortColumn: Integer;
    FSortDesc: Boolean;
    FDblClick: TDoubleClickTracker;
    FOnOpen: TClassOpenEvent;
    FOnSort: TClassSortEvent;
    function MaxScroll: Single;
    function RowAt(Y: Single): Integer;
    function ColumnAt(X: Single): Integer;
    function NameWidth: Single;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    // mantem a posicao do scroll quando AKeepScroll
    procedure SetRows(const ARows: TArray<TClassRow>; AKeepScroll: Boolean = False);
    // os titulos das colunas: Classe, Profundidade, Filhas, Metodos, Ficheiro
    procedure SetHeaders(const AClass, ADepth, AChildren, AMethods, AFile: string);
    procedure SetSort(AColumn: Integer; ADescending: Boolean);
    function RowCount: Integer;
    property EmptyText: string read FEmptyText write FEmptyText;
    property SortColumn: Integer read FSortColumn;
    property SortDescending: Boolean read FSortDesc;
    property OnOpen: TClassOpenEvent read FOnOpen write FOnOpen;
    property OnSort: TClassSortEvent read FOnSort write FOnSort;
  end;

implementation

const
  RowH = 28;
  HeadH = 30;
  DepthW = 92;
  ChildW = 70;
  MethW = 80;
  FileW = 230;
  Indent = 14;

function ChildrenText(AChildren: Integer): string;
begin
  if AChildren > 0 then
    Result := IntToStr(AChildren)
  else
    Result := '—';
end;

constructor TCMClassList.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  ClipChildren := True;
  FHover := -1;
  FSortColumn := -1;
end;

function TCMClassList.RowCount: Integer;
begin
  Result := Length(FRows);
end;

procedure TCMClassList.SetRows(const ARows: TArray<TClassRow>; AKeepScroll: Boolean);
begin
  FRows := ARows;
  if not AKeepScroll then
    FScrollY := 0;
  FScrollY := EnsureRange(FScrollY, 0, MaxScroll);
  FHover := -1;
  FDblClick.Reset;
  Repaint;
end;

procedure TCMClassList.SetHeaders(const AClass, ADepth, AChildren, AMethods, AFile: string);
begin
  FHeaders[0] := AClass;
  FHeaders[1] := ADepth;
  FHeaders[2] := AChildren;
  FHeaders[3] := AMethods;
  FHeaders[4] := AFile;
  Repaint;
end;

procedure TCMClassList.SetSort(AColumn: Integer; ADescending: Boolean);
begin
  FSortColumn := AColumn;
  FSortDesc := ADescending;
  Repaint;
end;

function TCMClassList.NameWidth: Single;
begin
  Result := Max(120, Width - 16 - DepthW - ChildW - MethW - FileW - 20);
end;

function TCMClassList.MaxScroll: Single;
begin
  Result := Max(0, Length(FRows) * RowH + 8 - (Height - HeadH));
end;

function TCMClassList.RowAt(Y: Single): Integer;
begin
  Result := Trunc((Y - HeadH - 4 + FScrollY) / RowH);
  if (Y < HeadH) or (Result < 0) or (Result >= Length(FRows)) then
    Result := -1;
end;

// a coluna do titulo sob X (0 classe, 1 profundidade, 2 filhas, 3 metodos, 4 ficheiro), ou -1
function TCMClassList.ColumnAt(X: Single): Integer;
var
  Edge: Single;
begin
  Edge := 12 + NameWidth + 8;
  if X < Edge then
    Exit(0);
  Edge := Edge + DepthW;
  if X < Edge then
    Exit(1);
  Edge := Edge + ChildW;
  if X < Edge then
    Exit(2);
  Edge := Edge + MethW;
  if X < Edge then
    Exit(3);
  Result := 4;
end;

procedure TCMClassList.Paint;
var
  I, First: Integer;
  Y, NameW, X, W, Left: Single;
  R, TagR: TRectF;
  Row: TClassRow;
  TrackH, ThumbH: Single;
  ThumbR: TRectF;

  procedure Head(ACol: Integer; ALeft, AWidth: Single; AAlign: TTextAlign);
  var
    T: string;
    Color: TAlphaColor;
  begin
    T := FHeaders[ACol];
    if ACol = FSortColumn then
      if FSortDesc then
        T := T + ' ↓'
      else
        T := T + ' ↑';
    if ACol = FSortColumn then
      Color := Pal.Text
    else
      Color := Pal.TextFaint;
    DrawTextRect(Canvas, TRectF.Create(ALeft, 0, ALeft + AWidth, HeadH), T, Color, 11, UiFont, [TFontStyle.fsBold], AAlign);
  end;

begin
  NameW := NameWidth;
  X := 12;
  Head(0, X, NameW, TTextAlign.Leading);
  X := X + NameW + 8;
  Head(1, X, DepthW, TTextAlign.Leading);
  X := X + DepthW;
  Head(2, X, ChildW - 10, TTextAlign.Trailing);
  X := X + ChildW;
  Head(3, X, MethW - 10, TTextAlign.Trailing);
  X := X + MethW;
  Head(4, X + 10, FileW - 10, TTextAlign.Leading);
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
    Left := X + Row.Indent * Indent;
    W := NameW - Row.Indent * Indent;
    if Row.KindText <> '' then
    begin
      TagR := TRectF.Create(Left, R.CenterPoint.Y - 8, Left + MeasureText(Row.KindText, 9.5, UiFont, [TFontStyle.fsBold]) + 12,
        R.CenterPoint.Y + 8);
      StrokeRound(Canvas, TagR, 8, Pal.TextFaint, 1);
      DrawTextRect(Canvas, TagR, Row.KindText, Pal.TextFaint, 9.5, UiFont, [TFontStyle.fsBold], TTextAlign.Center);
      Left := TagR.Right + 6;
      W := W - (TagR.Width + 6);
    end;
    DrawTextRect(Canvas, TRectF.Create(Left, R.Top, Left + Max(20, W), R.Bottom), FitText(Canvas, Row.Name, Max(20, W)),
      Pal.Text, 12, MonoFont);
    X := X + NameW + 8;
    TagR := TRectF.Create(X, R.CenterPoint.Y - 9, X + Min(DepthW - 14, MeasureText(Row.DepthText, 10.5, UiFont, [TFontStyle.fsBold]) + 14),
      R.CenterPoint.Y + 9);
    StrokeRound(Canvas, TagR, 9, Row.DepthColor, 1);
    DrawTextRect(Canvas, TagR, Row.DepthText, Row.DepthColor, 10.5, UiFont, [TFontStyle.fsBold], TTextAlign.Center);
    X := X + DepthW;
    DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + ChildW - 10, R.Bottom), ChildrenText(Row.Children),
      Pal.TextDim, 11.5, MonoFont, [], TTextAlign.Trailing);
    X := X + ChildW;
    DrawTextRect(Canvas, TRectF.Create(X, R.Top, X + MethW - 10, R.Bottom), IntToStr(Row.Methods), Pal.TextDim, 11.5, MonoFont,
      [], TTextAlign.Trailing);
    X := X + MethW;
    DrawTextRect(Canvas, TRectF.Create(X + 10, R.Top, X + FileW, R.Bottom), FitText(Canvas, Row.FileText, FileW - 10),
      Pal.TextFaint, 11, MonoFont);
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

procedure TCMClassList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx, Col: Integer;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  if Y < HeadH then
  begin
    Col := ColumnAt(X);
    if (Col in [0..3]) and Assigned(FOnSort) then
      FOnSort(Self, Col);
    Exit;
  end;
  Idx := RowAt(Y);
  if (Idx >= 0) and FDblClick.Click(IntToStr(Idx)) then
  begin
    if Assigned(FOnOpen) then
      FOnOpen(Self, FRows[Idx].Tag);
  end;
end;

procedure TCMClassList.MouseMove(Shift: TShiftState; X, Y: Single);
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

procedure TCMClassList.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  Repaint;
end;

procedure TCMClassList.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  FScrollY := EnsureRange(FScrollY - WheelDelta / 120 * RowH * 3, 0, MaxScroll);
  Handled := True;
  Repaint;
end;

end.
