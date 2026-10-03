unit CM.CodeView;

{ Controlos da pagina Codigo: a vista de leitura do codigo (numeros de linha, realce de sintaxe, scroll
  vertical e horizontal; so le, nunca edita) e a barra de separadores, um por ficheiro aberto. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics,
  CM.Theme, CM.Controls, CM.Highlight;

type
  // um ponto na margem de uma linha (por exemplo um problema do SonarQube); Line a partir de 0
  TCodeMarker = record
    Line: Integer;
    Color: TAlphaColor;
    Ring: Boolean;           // so o contorno (em vez de cheio)
    Hint: string;            // o que se mostra ao apontar a margem dessa linha
  end;

  TCMCodeView = class(TCMControl)
  private
    FDoc: TCodeDoc;              // de quem chama (a vista nao o liberta)
    FScrollX, FScrollY: Single;
    FMarkLine: Integer;          // linha em destaque (-1 = nenhuma)
    FDragV, FDragH: Boolean;
    FDragOffset: Single;
    FEmptyText: string;
    FLineH, FCharW: Single;
    FLigatures: Boolean;
    FMarkers: TArray<TCodeMarker>;       // por linha, a ordem de chegada
    function MarkersOnLine(ALine: Integer): TArray<TCodeMarker>;
    procedure MeasureFont;
    procedure SetLigatures(const Value: Boolean);
    function GutterW: Single;
    function ContentH: Single;
    function ContentW: Single;
    function MaxScrollX: Single;
    function MaxScrollY: Single;
    function VThumb: TRectF;
    function HThumb: TRectF;
    function ColorOf(AKind: TSynKind): TAlphaColor;
    procedure DrawLine(AIndex: Integer; AY: Single);
    procedure DrawSegment(const AText: string; AFrom, ALen: Integer; AKind: TSynKind; AY: Single);
    procedure DrawRun(const AText: string; AX, AY: Single; AColor: TAlphaColor; AStyle: TFontStyles);
    procedure DrawScrollbars;
    procedure ClampScroll;
    procedure SetScrollTo(AX, AY: Single);
    procedure SetMarkLine(const Value: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    // ADoc continua a ser de quem o passou; nil limpa a vista. O scroll volta ao principio
    procedure SetDoc(ADoc: TCodeDoc);
    // leva a linha (a partir de 0) para o terco de cima da vista e destaca-a
    procedure ShowLine(ALine: Integer);
    procedure SetScroll(AX, AY: Single);
    property Doc: TCodeDoc read FDoc;
    property ScrollX: Single read FScrollX;
    property ScrollY: Single read FScrollY;
    property MarkLine: Integer read FMarkLine write SetMarkLine;
    property EmptyText: string read FEmptyText write FEmptyText;
    // pontos na margem (por exemplo os problemas do Sonar); varios na mesma linha somam-se na dica
    procedure SetMarkers(const AMarkers: TArray<TCodeMarker>);
    // ligaduras da fonte (-> => <> := ...: desligadas, cada operador desenha-se no seu lugar, sem se fundir
    property Ligatures: Boolean read FLigatures write SetLigatures;
    // a fonte do tema mudou (SetCodeFont): volta a medir e a desenhar
    procedure FontChanged;
    // quantas linhas cabem na vista (para PageUp / PageDown)
    function VisibleLines: Integer;
    // a linha (a partir de 0) em cada posicao da vista; -1 fora do codigo
    function LineAtY(AY: Single): Integer;
  end;

  // uma linha da lista de problemas; Line a partir de 1 (0 = sem linha)
  TIssueRow = record
    Line: Integer;
    Color: TAlphaColor;
    Tag: string;             // 'BUG', 'HOTSPOT'...
    Text: string;
  end;

  TCMLineEvent = procedure(Sender: TObject; ALine: Integer) of object;

  // lista de itens ligados a linhas do codigo (problemas do Sonar, hotspots); um clique leva a vista a linha
  TCMIssueList = class(TCMControl)
  private
    FRows: TArray<TIssueRow>;
    FScrollY: Single;
    FHover: Integer;
    FEmptyText: string;
    FOnPick: TCMLineEvent;
    function MaxScroll: Single;
    function RowAt(Y: Single): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRows(const ARows: TArray<TIssueRow>);
    property EmptyText: string read FEmptyText write FEmptyText;
    // ALine: a linha escolhida, a partir de 0
    property OnPick: TCMLineEvent read FOnPick write FOnPick;
  end;

  TCMTabEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TCMTabBar = class(TCMControl)
  private
    FTitles: TList<string>;
    FHints: TList<string>;
    FActive: Integer;
    FHover, FHoverClose: Integer;
    FOnSelect: TCMTabEvent;
    FOnClose: TCMTabEvent;
    function TabWidth: Single;
    function TabRect(AIndex: Integer): TRectF;
    function CloseRect(AIndex: Integer): TRectF;
    function TabAt(X, Y: Single; out AClose: Boolean): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetTabs(const ATitles, AHints: TArray<string>; AActive: Integer);
    property Active: Integer read FActive;
    property OnSelect: TCMTabEvent read FOnSelect write FOnSelect;
    property OnClose: TCMTabEvent read FOnClose write FOnClose;
  end;

implementation

uses
  CM.Lang;

const
  CodeFontSize = 12.5;
  BarW = 10;                   // espessura das barras de scroll
  TabH = 36;
  MaxTabW = 230;
  MinTabW = 96;
  IssueRowH = 28;

{ TCMCodeView }

constructor TCMCodeView.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  CanFocus := True;
  ClipChildren := True;
  FMarkLine := -1;
  FLineH := 20;
  FLigatures := True;
  MeasureFont;
  FEmptyText := Tr('Sem código para mostrar.');
end;

procedure TCMCodeView.MeasureFont;
begin
  FCharW := MeasureText('0', CodeFontSize, CodeFont);
  if FCharW < 4 then
    FCharW := 7.5;
end;

procedure TCMCodeView.SetMarkers(const AMarkers: TArray<TCodeMarker>);
begin
  FMarkers := AMarkers;
  Repaint;
end;

function TCMCodeView.MarkersOnLine(ALine: Integer): TArray<TCodeMarker>;
var
  M: TCodeMarker;
begin
  Result := nil;
  for M in FMarkers do
    if M.Line = ALine then
      Result := Result + [M];
end;

procedure TCMCodeView.FontChanged;
begin
  MeasureFont;
  ClampScroll;
  Repaint;
end;

procedure TCMCodeView.SetLigatures(const Value: Boolean);
begin
  if FLigatures = Value then
    Exit;
  FLigatures := Value;
  Repaint;
end;

function TCMCodeView.GutterW: Single;
var
  Digits: Integer;
begin
  if FDoc = nil then
    Digits := 2
  else
    Digits := Max(2, Length(IntToStr(FDoc.Count)));
  Result := 18 + Digits * FCharW + 14;
end;

function TCMCodeView.ContentH: Single;
begin
  if FDoc = nil then
    Result := 0
  else
    Result := FDoc.Count * FLineH;
end;

function TCMCodeView.ContentW: Single;
begin
  if FDoc = nil then
    Result := 0
  else
    Result := FDoc.LongestLine * FCharW + 24;
end;

function TCMCodeView.MaxScrollY: Single;
begin
  Result := Max(0, ContentH + 8 - Height);
end;

function TCMCodeView.MaxScrollX: Single;
begin
  Result := Max(0, ContentW - (Width - GutterW));
end;

procedure TCMCodeView.ClampScroll;
begin
  FScrollY := EnsureRange(FScrollY, 0, MaxScrollY);
  FScrollX := EnsureRange(FScrollX, 0, MaxScrollX);
end;

procedure TCMCodeView.SetScrollTo(AX, AY: Single);
begin
  FScrollX := AX;
  FScrollY := AY;
  ClampScroll;
  Repaint;
end;

procedure TCMCodeView.SetScroll(AX, AY: Single);
begin
  SetScrollTo(AX, AY);
end;

procedure TCMCodeView.SetMarkLine(const Value: Integer);
begin
  if FMarkLine = Value then
    Exit;
  FMarkLine := Value;
  Repaint;
end;

procedure TCMCodeView.SetDoc(ADoc: TCodeDoc);
begin
  FDoc := ADoc;
  FScrollX := 0;
  FScrollY := 0;
  FMarkLine := -1;
  Repaint;
end;

procedure TCMCodeView.ShowLine(ALine: Integer);
begin
  if (FDoc = nil) or (ALine < 0) or (ALine >= FDoc.Count) then
    Exit;
  FMarkLine := ALine;
  FScrollY := ALine * FLineH - Height / 3;
  ClampScroll;
  Repaint;
end;

function TCMCodeView.VisibleLines: Integer;
begin
  Result := Max(1, Trunc(Height / FLineH) - 1);
end;

function TCMCodeView.LineAtY(AY: Single): Integer;
begin
  Result := Trunc((AY + FScrollY) / FLineH);
  if (FDoc = nil) or (Result < 0) or (Result >= FDoc.Count) then
    Result := -1;
end;

procedure TCMCodeView.Resize;
begin
  inherited;
  ClampScroll;
end;

function TCMCodeView.ColorOf(AKind: TSynKind): TAlphaColor;
begin
  case AKind of
    skKeyword: Result := Pal.Accent;
    skString: Result := Pal.FlagSonar;
    skComment: Result := Pal.TextFaint;
    skNumber: Result := Pal.FlagCompila;
    skDirective: Result := Pal.Pending;
  else
    Result := Pal.Text;
  end;
end;

procedure TCMCodeView.DrawSegment(const AText: string; AFrom, ALen: Integer; AKind: TSynKind; AY: Single);
var
  X: Single;
  Style: TFontStyles;
  S: string;
begin
  if ALen <= 0 then
    Exit;
  X := GutterW + 12 + (AFrom - 1) * FCharW - FScrollX;
  if (X + ALen * FCharW < GutterW) or (X > Width) then
    Exit;                                      // fora da vista
  S := Copy(AText, AFrom, ALen);
  Style := [];
  if AKind = skKeyword then
    Style := [TFontStyle.fsBold]
  else if AKind = skComment then
    Style := [TFontStyle.fsItalic];
  DrawRun(S, X, AY, ColorOf(AKind), Style);
end;

// com ligaduras o pedaco desenha-se de uma vez (o motor de texto funde -> => <> := ...); sem elas, cada
// operador desenha-se sozinho, na sua celula, e so as palavras ficam juntas
procedure TCMCodeView.DrawRun(const AText: string; AX, AY: Single; AColor: TAlphaColor; AStyle: TFontStyles);
const
  Operators = ['-', '<', '>', '=', '!', ':', '.', '|', '&', '*', '/', '+', '~', '#', '%', '^', '?', '\', '$', '@', '_'];
var
  I, RunStart: Integer;

  procedure Put(const APiece: string; AIndex: Integer);
  var
    X: Single;
  begin
    X := AX + (AIndex - 1) * FCharW;
    DrawTextRect(Canvas, TRectF.Create(X, AY, X + Length(APiece) * FCharW + 4, AY + FLineH), APiece, AColor,
      CodeFontSize, CodeFont, AStyle);
  end;

begin
  if FLigatures then
  begin
    Put(AText, 1);
    Exit;
  end;
  RunStart := 1;
  for I := 1 to Length(AText) do
    if CharInSet(AText[I], Operators) then
    begin
      if I > RunStart then
        Put(Copy(AText, RunStart, I - RunStart), RunStart);
      Put(AText[I], I);
      RunStart := I + 1;
    end;
  if RunStart <= Length(AText) then
    Put(Copy(AText, RunStart, MaxInt), RunStart);
end;

procedure TCMCodeView.DrawLine(AIndex: Integer; AY: Single);
var
  L: TCodeLine;
  Pos, I: Integer;
begin
  L := FDoc.Line(AIndex);
  Pos := 1;
  for I := 0 to High(L.Spans) do
  begin
    DrawSegment(L.Text, Pos, L.Spans[I].Start - Pos, skPlain, AY);
    DrawSegment(L.Text, L.Spans[I].Start, L.Spans[I].Len, L.Spans[I].Kind, AY);
    Pos := L.Spans[I].Start + L.Spans[I].Len;
  end;
  DrawSegment(L.Text, Pos, Length(L.Text) - Pos + 1, skPlain, AY);
end;

function TCMCodeView.VThumb: TRectF;
var
  TrackH, ThumbH, Y: Single;
begin
  TrackH := Height - 8;
  ThumbH := Max(36, TrackH * Height / Max(1, ContentH + 8));
  if MaxScrollY <= 0 then
    Y := 4
  else
    Y := 4 + (TrackH - ThumbH) * (FScrollY / MaxScrollY);
  Result := TRectF.Create(Width - BarW - 2, Y, Width - 2, Y + ThumbH);
end;

function TCMCodeView.HThumb: TRectF;
var
  TrackW, ThumbW, X: Single;
begin
  TrackW := Width - GutterW - 8;
  ThumbW := Max(36, TrackW * (Width - GutterW) / Max(1, ContentW));
  if MaxScrollX <= 0 then
    X := GutterW + 4
  else
    X := GutterW + 4 + (TrackW - ThumbW) * (FScrollX / MaxScrollX);
  Result := TRectF.Create(X, Height - BarW - 2, X + ThumbW, Height - 2);
end;

procedure TCMCodeView.DrawScrollbars;
begin
  if MaxScrollY > 0 then
    FillRound(Canvas, VThumb, 4, Fade(Pal.TextFaint, IfThen(FDragV, 0.9, 0.55)));
  if MaxScrollX > 0 then
    FillRound(Canvas, HThumb, 4, Fade(Pal.TextFaint, IfThen(FDragH, 0.9, 0.55)));
end;

procedure TCMCodeView.Paint;
var
  State: TCanvasSaveState;
  First, Last, I: Integer;
  Y: Single;
  G: Single;
  NumR, Row, Dot: TRectF;
  Mk: TCodeMarker;
begin
  State := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(LocalRect);
    if (FDoc = nil) or (FDoc.Count = 0) then
    begin
      DrawTextRect(Canvas, LocalRect, FEmptyText, Pal.TextFaint, 13, CodeFont, [], TTextAlign.Center);
      Exit;
    end;
    G := GutterW;
    // a margem com os numeros de linha
    FillRound(Canvas, TRectF.Create(0, 0, G, Height), 0, Pal.Surface2);
    FillRound(Canvas, TRectF.Create(G, 0, G + 1, Height), 0, Pal.Border);

    First := Max(0, Trunc(FScrollY / FLineH));
    Last := Min(FDoc.Count - 1, Trunc((FScrollY + Height) / FLineH));
    for I := First to Last do
    begin
      Y := I * FLineH - FScrollY + 4;
      Row := TRectF.Create(G + 1, Y, Width, Y + FLineH);
      if I = FMarkLine then
      begin
        FillRound(Canvas, Row, 0, Fade(Pal.Accent, 0.13));
      end;
      NumR := TRectF.Create(0, Y, G - 10, Y + FLineH);
      if Length(FMarkers) > 0 then
        for Mk in MarkersOnLine(I) do
        begin
          Dot := TRectF.Create(5, Y + FLineH / 2 - 3.5, 12, Y + FLineH / 2 + 3.5);
          if Mk.Ring then
            StrokeRound(Canvas, Dot, 3.5, Mk.Color, 1.5)
          else
            FillRound(Canvas, Dot, 3.5, Mk.Color);
          Break;                    // um ponto por linha: a dica leva todos
        end;
      DrawTextRect(Canvas, NumR, IntToStr(I + 1), Pick(I = FMarkLine, Pal.Accent, Pal.TextFaint), CodeFontSize - 1,
        CodeFont, [], TTextAlign.Trailing);
    end;
    // o codigo, cortado a direita da margem
    Canvas.IntersectClipRect(TRectF.Create(G + 1, 0, Width, Height));
    for I := First to Last do
      DrawLine(I, I * FLineH - FScrollY + 4);
    Canvas.IntersectClipRect(LocalRect);
    DrawScrollbars;
  finally
    Canvas.RestoreState(State);
  end;
end;

procedure TCMCodeView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  T: TRectF;
  Ratio: Single;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  SetFocus;
  if (MaxScrollY > 0) and (X >= Width - BarW - 6) then
  begin
    T := VThumb;
    if T.Contains(PointF(X, Y)) then
    begin
      FDragV := True;
      FDragOffset := Y - T.Top;
    end
    else
      SetScrollTo(FScrollX, FScrollY + Sign(Y - T.CenterPoint.Y) * Height * 0.9);
    Exit;
  end;
  if (MaxScrollX > 0) and (Y >= Height - BarW - 6) then
  begin
    T := HThumb;
    if T.Contains(PointF(X, Y)) then
    begin
      FDragH := True;
      FDragOffset := X - T.Left;
    end
    else
    begin
      Ratio := Sign(X - T.CenterPoint.X) * (Width - GutterW) * 0.9;
      SetScrollTo(FScrollX + Ratio, FScrollY);
    end;
    Exit;
  end;
  // um clique numa linha destaca-a (so para acompanhar a leitura)
  if (FDoc <> nil) and (X > 0) then
    MarkLine := LineAtY(Y - 4);
end;

procedure TCMCodeView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  T: TRectF;
  Ratio: Single;
  Line: Integer;
  Marks: TArray<TCodeMarker>;
  M: TCodeMarker;
  Text: string;
begin
  inherited;
  if not (FDragV or FDragH) then
  begin
    // ao apontar a margem: a dica reune o que ha nessa linha
    Text := '';
    if (X < GutterW) and (Length(FMarkers) > 0) then
    begin
      Line := LineAtY(Y - 4);
      if Line >= 0 then
      begin
        Marks := MarkersOnLine(Line);
        for M in Marks do
        begin
          if Text <> '' then
            Text := Text + sLineBreak;
          Text := Text + M.Hint;
        end;
      end;
    end;
    if Text <> Hint then
      Hint := Text;
    ShowHint := Text <> '';
  end;
  if FDragV then
  begin
    T := VThumb;
    Ratio := (Y - FDragOffset - 4) / Max(1, (Height - 8) - T.Height);
    SetScrollTo(FScrollX, EnsureRange(Ratio, 0, 1) * MaxScrollY);
  end
  else if FDragH then
  begin
    T := HThumb;
    Ratio := (X - FDragOffset - (GutterW + 4)) / Max(1, (Width - GutterW - 8) - T.Width);
    SetScrollTo(EnsureRange(Ratio, 0, 1) * MaxScrollX, FScrollY);
  end;
end;

procedure TCMCodeView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDragV := False;
  FDragH := False;
  Repaint;
end;

procedure TCMCodeView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  if ssShift in Shift then
    SetScrollTo(FScrollX - WheelDelta / 120 * 6 * FCharW * 3, FScrollY)
  else
    SetScrollTo(FScrollX, FScrollY - WheelDelta / 120 * FLineH * 3);
  Handled := True;
end;

procedure TCMCodeView.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  inherited;
  case Key of
    vkUp: SetScrollTo(FScrollX, FScrollY - FLineH);
    vkDown: SetScrollTo(FScrollX, FScrollY + FLineH);
    vkPrior: SetScrollTo(FScrollX, FScrollY - VisibleLines * FLineH);
    vkNext: SetScrollTo(FScrollX, FScrollY + VisibleLines * FLineH);
    vkLeft: SetScrollTo(FScrollX - FCharW * 4, FScrollY);
    vkRight: SetScrollTo(FScrollX + FCharW * 4, FScrollY);
    vkHome: if ssCtrl in Shift then SetScrollTo(0, 0) else SetScrollTo(0, FScrollY);
    vkEnd: if ssCtrl in Shift then SetScrollTo(FScrollX, MaxScrollY);
  else
    Exit;
  end;
  Key := 0;
end;

{ TCMIssueList }

constructor TCMIssueList.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  ClipChildren := True;
  FHover := -1;
end;

procedure TCMIssueList.SetRows(const ARows: TArray<TIssueRow>);
begin
  FRows := ARows;
  FScrollY := 0;
  FHover := -1;
  Repaint;
end;

function TCMIssueList.MaxScroll: Single;
begin
  Result := Max(0, Length(FRows) * IssueRowH + 8 - Height);
end;

procedure TCMIssueList.Paint;
var
  I, First: Integer;
  Y: Single;
  R, Dot, ThumbR: TRectF;
  Row: TIssueRow;
  LineTxt: string;
  W, TrackH, ThumbH: Single;
begin
  if Length(FRows) = 0 then
  begin
    DrawTextRect(Canvas, TRectF.Create(8, 0, Width - 8, Height), FEmptyText, Pal.TextFaint, 12, UiFont, [],
      TTextAlign.Leading);
    Exit;
  end;
  First := Max(0, Trunc(FScrollY / IssueRowH));
  for I := First to High(FRows) do
  begin
    Y := 4 + I * IssueRowH - FScrollY;
    if Y > Height then
      Break;
    Row := FRows[I];
    R := TRectF.Create(2, Y, Width - 14, Y + IssueRowH - 2);
    if I = FHover then
      FillRound(Canvas, R, 6, Pal.Hover);
    Dot := TRectF.Create(R.Left + 8, R.CenterPoint.Y - 4, R.Left + 16, R.CenterPoint.Y + 4);
    FillRound(Canvas, Dot, 4, Row.Color);
    if Row.Line > 0 then
      LineTxt := IntToStr(Row.Line)
    else
      LineTxt := '—';
    DrawTextRect(Canvas, TRectF.Create(R.Left + 24, R.Top, R.Left + 72, R.Bottom), LineTxt, Pal.TextFaint, 11.5,
      CodeFont, [], TTextAlign.Trailing);
    W := MeasureText(Row.Tag, 10, UiFont, [TFontStyle.fsBold]) + 14;
    ThumbR := TRectF.Create(R.Left + 82, R.CenterPoint.Y - 9, R.Left + 82 + W, R.CenterPoint.Y + 9);
    StrokeRound(Canvas, ThumbR, 9, Row.Color, 1);
    DrawTextRect(Canvas, ThumbR, Row.Tag, Row.Color, 10, UiFont, [TFontStyle.fsBold], TTextAlign.Center);
    DrawTextRect(Canvas, TRectF.Create(ThumbR.Right + 10, R.Top, R.Right - 6, R.Bottom),
      FitText(Canvas, Row.Text, R.Right - 6 - (ThumbR.Right + 10)), Pal.Text, 12, UiFont);
  end;
  if MaxScroll > 0 then
  begin
    TrackH := Height - 8;
    ThumbH := Max(24, TrackH * Height / (Length(FRows) * IssueRowH + 8));
    ThumbR := TRectF.Create(Width - 9, 4 + (TrackH - ThumbH) * (FScrollY / MaxScroll), Width - 3,
      4 + (TrackH - ThumbH) * (FScrollY / MaxScroll) + ThumbH);
    FillRound(Canvas, ThumbR, 3, Fade(Pal.TextFaint, 0.55));
  end;
end;

function TCMIssueList.RowAt(Y: Single): Integer;
begin
  Result := Trunc((Y - 4 + FScrollY) / IssueRowH);
  if (Result < 0) or (Result >= Length(FRows)) then
    Result := -1;
end;

procedure TCMIssueList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  Idx := RowAt(Y);
  if (Idx >= 0) and (FRows[Idx].Line > 0) and Assigned(FOnPick) then
    FOnPick(Self, FRows[Idx].Line - 1);
end;

procedure TCMIssueList.MouseMove(Shift: TShiftState; X, Y: Single);
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
      Hint := FRows[Idx].Text;
      ShowHint := True;
      Cursor := crHandPoint;
    end
    else
      Cursor := crDefault;
    Repaint;
  end;
end;

procedure TCMIssueList.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  Repaint;
end;

procedure TCMIssueList.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  FScrollY := EnsureRange(FScrollY - WheelDelta / 120 * IssueRowH * 2, 0, MaxScroll);
  Handled := True;
  Repaint;
end;

{ TCMTabBar }

constructor TCMTabBar.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  FTitles := TList<string>.Create;
  FHints := TList<string>.Create;
  FActive := -1;
  FHover := -1;
  FHoverClose := -1;
end;

destructor TCMTabBar.Destroy;
begin
  FHints.Free;
  FTitles.Free;
  inherited;
end;

procedure TCMTabBar.SetTabs(const ATitles, AHints: TArray<string>; AActive: Integer);
begin
  FTitles.Clear;
  FTitles.AddRange(ATitles);
  FHints.Clear;
  FHints.AddRange(AHints);
  FActive := AActive;
  FHover := -1;
  FHoverClose := -1;
  Repaint;
end;

function TCMTabBar.TabWidth: Single;
begin
  if FTitles.Count = 0 then
    Exit(MaxTabW);
  Result := EnsureRange((Width - 4) / FTitles.Count - 4, MinTabW, MaxTabW);
end;

function TCMTabBar.TabRect(AIndex: Integer): TRectF;
var
  W: Single;
begin
  W := TabWidth;
  Result := TRectF.Create(2 + AIndex * (W + 4), 4, 2 + AIndex * (W + 4) + W, 4 + TabH - 4);
end;

function TCMTabBar.CloseRect(AIndex: Integer): TRectF;
var
  R: TRectF;
begin
  R := TabRect(AIndex);
  Result := TRectF.Create(R.Right - 26, R.CenterPoint.Y - 9, R.Right - 8, R.CenterPoint.Y + 9);
end;

function TCMTabBar.TabAt(X, Y: Single; out AClose: Boolean): Integer;
var
  I: Integer;
begin
  AClose := False;
  for I := 0 to FTitles.Count - 1 do
    if TabRect(I).Contains(PointF(X, Y)) then
    begin
      AClose := CloseRect(I).Contains(PointF(X, Y));
      Exit(I);
    end;
  Result := -1;
end;

procedure TCMTabBar.Paint;
var
  I: Integer;
  R, C, IR: TRectF;
  Active: Boolean;
  Txt: string;
  Style: TFontStyles;
begin
  for I := 0 to FTitles.Count - 1 do
  begin
    R := TabRect(I);
    Active := I = FActive;
    if Active then
    begin
      FillRound(Canvas, R, 8, Pal.AccentSoft);
      StrokeRound(Canvas, R, 8, Fade(Pal.Accent, 0.45), 1);
    end
    else
    begin
      FillRound(Canvas, R, 8, Pick(I = FHover, Pal.Hover, Pal.Surface));
      StrokeRound(Canvas, R, 8, Pal.Border, 1);
    end;
    C := CloseRect(I);
    Txt := FitText(Canvas, FTitles[I], R.Width - 12 - 30);
    if Active then
      Style := [TFontStyle.fsBold]
    else
      Style := [];
    DrawTextRect(Canvas, TRectF.Create(R.Left + 12, R.Top, C.Left, R.Bottom), Txt,
      Pick(Active, Pal.AccentStrong, Pal.TextDim), 12, MonoFont, Style);
    if (I = FHoverClose) then
      FillRound(Canvas, C, 5, Pal.Border);
    IR := C;
    IR.Inflate(-4, -4);
    DrawIcon(Canvas, icClose, IR, Pick(Active or (I = FHover), Pal.TextDim, Pal.TextFaint));
  end;
end;

procedure TCMTabBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  OnClose: Boolean;
begin
  inherited;
  Idx := TabAt(X, Y, OnClose);
  if Idx < 0 then
    Exit;
  if (Button = TMouseButton.mbMiddle) or ((Button = TMouseButton.mbLeft) and OnClose) then
  begin
    if Assigned(FOnClose) then
      FOnClose(Self, Idx);
  end
  else if Button = TMouseButton.mbLeft then
    if Assigned(FOnSelect) then
      FOnSelect(Self, Idx);
end;

procedure TCMTabBar.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  OnClose: Boolean;
  NewClose: Integer;
begin
  inherited;
  Idx := TabAt(X, Y, OnClose);
  if OnClose then NewClose := Idx else NewClose := -1;
  if (Idx <> FHover) or (NewClose <> FHoverClose) then
  begin
    FHover := Idx;
    FHoverClose := NewClose;
    if (Idx >= 0) and (Idx < FHints.Count) then
    begin
      Hint := FHints[Idx];
      ShowHint := True;
    end
    else
      Hint := '';
    Repaint;
  end;
end;

procedure TCMTabBar.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  FHoverClose := -1;
  Repaint;
end;

end.
