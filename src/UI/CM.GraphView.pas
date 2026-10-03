unit CM.GraphView;

{ Mapa visual das dependencias: cada unit e um no e cada "uses" uma curva. As units dispoem-se em colunas
  (a da esquerda tem as que ninguem usa; cada coluna seguinte fica um passo mais "por baixo"), com a cor da
  camada (pasta) e um traco vermelho nos ciclos. Arrasta-se para mover, a roda aproxima/afasta, um clique
  seleciona uma unit e realca o que ela usa (a verde) e o que a usa (a azul).

  A forma dos nos e das ligacoes em curva de Bezier inspira-se no DelphiNodeEditor (MIT, HemulGM);
  o codigo aqui e proprio, a medida do CodeManager (ver THIRD-PARTY-NOTICES.md). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.Math.Vectors,
  System.Generics.Collections, FMX.Types, FMX.Controls, FMX.Graphics, CM.Theme, CM.Controls, CM.Deps;

type
  TCMGraphView = class(TCMControl)
  private
    FGraph: TDepGraph;                 // pertence a quem o criou
    FZoom: Single;
    FPanX, FPanY: Single;              // ecra = mundo * zoom + pan
    FSelected, FHover: Integer;
    FFilter: string;
    FMatch: TArray<Boolean>;
    FHub: TArray<Boolean>;             // units usadas por muitas outras (as ligacoes para elas poluem o mapa)
    FSimplify: Boolean;
    FColSizes: TArray<Integer>;
    FMaxRows: Integer;
    FLayers: TArray<string>;
    FLayerColors: TDictionary<string, TAlphaColor>;
    FDown, FMoved: Boolean;
    FDownX, FDownY, FLastX, FLastY: Single;
    FPath: TPathData;
    FEmptyText: string;
    FOnSelect: TNotifyEvent;
    procedure SetFilter(const Value: string);
    procedure SetEmptyText(const Value: string);
    procedure SetSimplify(const Value: Boolean);
    function WorldRect(AIndex: Integer): TRectF;
    function ToScreen(const R: TRectF): TRectF;
    function NodeAt(X, Y: Single): Integer;
    function ColorOfLayer(const ALayer: string): TAlphaColor;
    function Related(AIndex, AOther: Integer): Integer;
    procedure ClampPan;
    procedure DrawEdges(const AView: TRectF);
    procedure DrawNodes(const AView: TRectF);
    procedure DrawLegend;
    procedure CurvePoints(const S, T: TRectF; ASameColumn: Boolean; out P0, P1, P2, P3: TPointF);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // o grafo continua a ser de quem o passou; passar nil limpa a vista
    procedure SetGraph(AGraph: TDepGraph);
    // AReadable: se o grafo nao cabe, em vez de o encolher ate ficar ilegivel mostra-o a um tamanho legivel,
    // a partir da esquerda; sem AReadable ajusta tudo a janela
    procedure FitToView(AReadable: Boolean = False);
    procedure ZoomBy(AFactor: Single);
    // selecciona uma unit (-1 = nenhuma); ACenter leva-a para o meio da vista
    procedure SelectNode(AIndex: Integer; ACenter: Boolean = False);
    function LayerCount: Integer;
    function LayerName(AIndex: Integer): string;
    function LayerColor(AIndex: Integer): TAlphaColor;
    property Graph: TDepGraph read FGraph;
    property Selected: Integer read FSelected;
    // so as units cujo nome ou pasta contem o texto ficam em destaque
    property Filter: string read FFilter write SetFilter;
    property EmptyText: string read FEmptyText write SetEmptyText;
    // esconde as ligacoes para as units muito usadas (reaparecem ao seleccionar ou apontar uma unit)
    property Simplify: Boolean read FSimplify write SetSimplify;
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
  end;

implementation

uses
  CM.Lang;

const
  ColW = 300;
  RowH = 46;
  NodeW = 232;
  NodeH = 34;
  Margin = 40;
  MinZoom = 0.05;
  ReadableZoom = 0.75;
  MaxZoom = 2.5;


constructor TCMGraphView.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  ClipChildren := True;
  FZoom := 1;
  FSelected := -1;
  FHover := -1;
  FLayerColors := TDictionary<string, TAlphaColor>.Create;
  FPath := TPathData.Create;
end;

destructor TCMGraphView.Destroy;
begin
  FPath.Free;
  FLayerColors.Free;
  inherited;
end;

procedure TCMGraphView.SetEmptyText(const Value: string);
begin
  FEmptyText := Value;
  Repaint;
end;

procedure TCMGraphView.SetGraph(AGraph: TDepGraph);
var
  N: TDepNode;
  I: Integer;
begin
  FGraph := AGraph;
  FSelected := -1;
  FHover := -1;
  FLayerColors.Clear;
  FLayers := nil;
  FColSizes := nil;
  FMaxRows := 0;
  FHub := nil;
  if FGraph <> nil then
  begin
    SetLength(FHub, FGraph.Nodes.Count);
    for I := 0 to FGraph.Nodes.Count - 1 do
      FHub[I] := FGraph.Nodes[I].FanIn >= Max(8, Round(FGraph.Nodes.Count * 0.2));
    SetLength(FColSizes, FGraph.LevelCount);
    for N in FGraph.Nodes do
      Inc(FColSizes[N.Level]);
    FLayers := FGraph.Layers;
    for I := 0 to High(FLayers) do
      FLayerColors.Add(FLayers[I], TAlphaColor(DepLayerPalette[I mod Length(DepLayerPalette)]));
    for I := 0 to High(FColSizes) do
      FMaxRows := Max(FMaxRows, FColSizes[I]);
  end;
  SetFilter(FFilter);
  FitToView(True);
end;

function TCMGraphView.LayerCount: Integer;
begin
  Result := Length(FLayers);
end;

function TCMGraphView.LayerName(AIndex: Integer): string;
begin
  Result := FLayers[AIndex];
end;

function TCMGraphView.LayerColor(AIndex: Integer): TAlphaColor;
begin
  Result := ColorOfLayer(FLayers[AIndex]);
end;

function TCMGraphView.ColorOfLayer(const ALayer: string): TAlphaColor;
begin
  if not FLayerColors.TryGetValue(ALayer, Result) then
    Result := Pal.TextFaint;
end;

procedure TCMGraphView.SetSimplify(const Value: Boolean);
begin
  FSimplify := Value;
  Repaint;
end;

procedure TCMGraphView.SetFilter(const Value: string);
var
  I: Integer;
  Q: string;
begin
  FFilter := Value;
  FMatch := nil;
  Q := LowerCase(Trim(Value));
  if (FGraph <> nil) and (Q <> '') then
  begin
    SetLength(FMatch, FGraph.Nodes.Count);
    for I := 0 to FGraph.Nodes.Count - 1 do
      FMatch[I] := LowerCase(FGraph.Nodes[I].Name).Contains(Q) or LowerCase(FGraph.Nodes[I].Layer).Contains(Q);
  end;
  Repaint;
end;

{ geometria }

function TCMGraphView.WorldRect(AIndex: Integer): TRectF;
var
  N: TDepNode;
  X, Y: Single;
begin
  N := FGraph.Nodes[AIndex];
  X := Margin + N.Level * ColW;
  Y := Margin + N.Row * RowH + (FMaxRows - FColSizes[N.Level]) * RowH / 2;
  Result := TRectF.Create(X, Y, X + NodeW, Y + NodeH);
end;

function TCMGraphView.ToScreen(const R: TRectF): TRectF;
begin
  Result := TRectF.Create(R.Left * FZoom + FPanX, R.Top * FZoom + FPanY, R.Right * FZoom + FPanX,
    R.Bottom * FZoom + FPanY);
end;

function TCMGraphView.NodeAt(X, Y: Single): Integer;
var
  I: Integer;
  R: TRectF;
  P: TPointF;
begin
  Result := -1;
  if FGraph = nil then
    Exit;
  P := PointF((X - FPanX) / FZoom, (Y - FPanY) / FZoom);
  for I := 0 to FGraph.Nodes.Count - 1 do
  begin
    R := WorldRect(I);
    if R.Contains(P) then
      Exit(I);
  end;
end;

procedure TCMGraphView.ClampPan;
var
  W, H: Single;
begin
  if FGraph = nil then
    Exit;
  W := (Margin * 2 + (FGraph.LevelCount - 1) * ColW + NodeW) * FZoom;
  H := (Margin * 2 + (FMaxRows - 1) * RowH + NodeH) * FZoom;
  // deixa sempre algum grafo a vista
  FPanX := EnsureRange(FPanX, Width - W - 200, 200);
  FPanY := EnsureRange(FPanY, Height - H - 200, 200);
end;

procedure TCMGraphView.FitToView(AReadable: Boolean);
var
  W, H, Fit: Single;
begin
  if (FGraph = nil) or (FGraph.Nodes.Count = 0) or (Width < 10) or (Height < 10) then
  begin
    FZoom := 1;
    FPanX := 0;
    FPanY := 0;
    Repaint;
    Exit;
  end;
  W := Margin * 2 + (FGraph.LevelCount - 1) * ColW + NodeW;
  H := Margin * 2 + (FMaxRows - 1) * RowH + NodeH;
  Fit := EnsureRange(Min(Width / W, Height / H), MinZoom, 1);
  if AReadable and (Fit < ReadableZoom) then
  begin
    FZoom := ReadableZoom;
    FPanX := 8;
    FPanY := (Height - H * FZoom) / 2;
  end
  else
  begin
    FZoom := Fit;
    FPanX := (Width - W * FZoom) / 2;
    FPanY := (Height - H * FZoom) / 2;
  end;
  ClampPan;
  Repaint;
end;

procedure TCMGraphView.ZoomBy(AFactor: Single);
var
  Cx, Cy, NewZoom: Single;
begin
  Cx := Width / 2;
  Cy := Height / 2;
  NewZoom := EnsureRange(FZoom * AFactor, MinZoom, MaxZoom);
  FPanX := Cx - (Cx - FPanX) * NewZoom / FZoom;
  FPanY := Cy - (Cy - FPanY) * NewZoom / FZoom;
  FZoom := NewZoom;
  ClampPan;
  Repaint;
end;

procedure TCMGraphView.SelectNode(AIndex: Integer; ACenter: Boolean);
var
  R: TRectF;
begin
  if (FGraph = nil) or (AIndex < 0) or (AIndex >= FGraph.Nodes.Count) then
    AIndex := -1;
  FSelected := AIndex;
  if ACenter and (AIndex >= 0) then
  begin
    R := WorldRect(AIndex);
    FPanX := Width / 2 - R.CenterPoint.X * FZoom;
    FPanY := Height / 2 - R.CenterPoint.Y * FZoom;
    ClampPan;
  end;
  Repaint;
  if Assigned(FOnSelect) then
    FOnSelect(Self);
end;

// 1 = AOther e usada por AIndex; -1 = AOther usa AIndex; 0 = sem relacao directa
function TCMGraphView.Related(AIndex, AOther: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if AIndex < 0 then
    Exit;
  for J in FGraph.Nodes[AIndex].Deps do
    if J = AOther then
      Exit(1);
  for J in FGraph.Nodes[AIndex].Dependents do
    if J = AOther then
      Exit(-1);
end;

{ pintura }

procedure TCMGraphView.CurvePoints(const S, T: TRectF; ASameColumn: Boolean; out P0, P1, P2, P3: TPointF);
var
  Dx: Single;
begin
  if ASameColumn then
  begin
    // duas units da mesma coluna (um ciclo): a curva sai pela direita e volta pela direita
    P0 := PointF(S.Right, S.CenterPoint.Y);
    P3 := PointF(T.Right, T.CenterPoint.Y);
    Dx := 70 * FZoom;
    P1 := PointF(P0.X + Dx, P0.Y);
    P2 := PointF(P3.X + Dx, P3.Y);
  end
  else
  begin
    P0 := PointF(S.Right, S.CenterPoint.Y);
    P3 := PointF(T.Left, T.CenterPoint.Y);
    Dx := Max(40 * FZoom, Abs(P3.X - P0.X) / 2);
    P1 := PointF(P0.X + Dx, P0.Y);
    P2 := PointF(P3.X - Dx, P3.Y);
  end;
end;

procedure TCMGraphView.DrawEdges(const AView: TRectF);
var
  E: TDepEdge;
  S, T, Box: TRectF;
  P0, P1, P2, P3: TPointF;
  Rel: Integer;
  Active: Boolean;
  Cyc, Out_, In_: Boolean;
  Col: TAlphaColor;
  Thick: Single;
begin
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Join := TStrokeJoin.Round;
  Canvas.Stroke.Cap := TStrokeCap.Round;
  Active := FSelected >= 0;
  for E in FGraph.Edges do
  begin
    S := ToScreen(WorldRect(E.Source));
    T := ToScreen(WorldRect(E.Target));
    Box := TRectF.Create(Min(S.Left, T.Left), Min(S.Top, T.Top), Max(S.Right, T.Right) + 80, Max(S.Bottom, T.Bottom));
    if not IntersectRect(Box, AView) then
      Continue;
    Out_ := Active and (E.Source = FSelected);
    In_ := Active and (E.Target = FSelected);
    if FSimplify and FHub[E.Target] and not (Out_ or In_) and (E.Source <> FHover) and (E.Target <> FHover) then
      Continue;
    Cyc := (FGraph.Nodes[E.Source].Cycle >= 0) and (FGraph.Nodes[E.Source].Cycle = FGraph.Nodes[E.Target].Cycle);
    Rel := 0;
    if Out_ then
      Rel := 1
    else if In_ then
      Rel := -1;
    Thick := 0.9;
    if Rel = 1 then
    begin
      Col := Pal.Accent;
      Thick := 2.2;
    end
    else if Rel = -1 then
    begin
      Col := Pal.FlagCompila;
      Thick := 2.2;
    end
    else if Cyc then
      Col := Fade(Pal.Danger, IfThen(Active, 0.25, 0.8))
    else if Active then
      Col := Fade(Pal.TextFaint, 0.12)
    else if (FHover >= 0) and ((E.Source = FHover) or (E.Target = FHover)) then
    begin
      Col := Pal.TextDim;
      Thick := 1.6;
    end
    else
      Col := Fade(Pal.TextFaint, 0.32);
    CurvePoints(S, T, FGraph.Nodes[E.Source].Level = FGraph.Nodes[E.Target].Level, P0, P1, P2, P3);
    FPath.Clear;
    FPath.MoveTo(P0);
    FPath.CurveTo(P1, P2, P3);
    Canvas.Stroke.Color := Col;
    Canvas.Stroke.Thickness := Thick;
    // so na implementation: tracejado
    if E.InInterface then
      Canvas.Stroke.Dash := TStrokeDash.Solid
    else
      Canvas.Stroke.Dash := TStrokeDash.Dash;
    Canvas.DrawPath(FPath, 1);
    if Rel <> 0 then
    begin
      Canvas.Fill.Color := Col;
      Canvas.FillEllipse(TRectF.Create(P3.X - 3.5, P3.Y - 3.5, P3.X + 3.5, P3.Y + 3.5), 1);
    end;
  end;
  Canvas.Stroke.Dash := TStrokeDash.Solid;
end;

procedure TCMGraphView.DrawNodes(const AView: TRectF);
var
  I: Integer;
  N: TDepNode;
  R, Bar, TextR, SubR: TRectF;
  P: TPalette;
  Dim: Boolean;
  Alpha: Single;
  Border, FillC: TAlphaColor;
  Rel: Integer;
  Detail: string;
  ShowText: Boolean;
begin
  P := Pal;
  ShowText := FZoom >= 0.42;
  for I := 0 to FGraph.Nodes.Count - 1 do
  begin
    N := FGraph.Nodes[I];
    R := ToScreen(WorldRect(I));
    if not IntersectRect(R, AView) then
      Continue;
    Rel := Related(FSelected, I);
    Dim := False;
    if (FSelected >= 0) and (I <> FSelected) and (Rel = 0) then
      Dim := True;
    if (Length(FMatch) > 0) and not FMatch[I] then
      Dim := True;
    if Dim then
      Alpha := 0.3
    else
      Alpha := 1;

    FillC := P.Surface;
    Border := P.BorderStrong;
    if I = FSelected then
    begin
      FillC := P.AccentSoft;
      Border := P.Accent;
    end
    else if Rel = 1 then
      Border := P.Accent
    else if Rel = -1 then
      Border := P.FlagCompila
    else if I = FHover then
      Border := P.TextDim;
    FillRound(Canvas, R, 7 * FZoom, Fade(FillC, Alpha));
    StrokeRound(Canvas, R, 7 * FZoom, Fade(Border, Alpha), IfThen((I = FSelected) or (Rel <> 0), 2, 1));
    // faixa com a cor da camada
    Bar := TRectF.Create(R.Left + 1, R.Top + 6 * FZoom, R.Left + 1 + Max(3, 5 * FZoom), R.Bottom - 6 * FZoom);
    FillRound(Canvas, Bar, 2, Fade(ColorOfLayer(N.Layer), Alpha));
    if N.Cycle >= 0 then
      FillRound(Canvas, TRectF.Create(R.Right - 12 * FZoom, R.Top + 5 * FZoom, R.Right - 6 * FZoom,
        R.Top + 11 * FZoom), 3 * FZoom, Fade(P.Danger, Alpha));
    if ShowText then
    begin
      TextR := TRectF.Create(R.Left + 14 * FZoom, R.Top + 2 * FZoom, R.Right - 14 * FZoom, R.Top + R.Height * 0.58);
      DrawTextRect(Canvas, TextR, FitText(Canvas, N.Name, TextR.Width), Fade(P.Text, Alpha), 11.5 * FZoom, MonoFont,
        [TFontStyle.fsBold]);
      SubR := TRectF.Create(R.Left + 14 * FZoom, R.Top + R.Height * 0.52, R.Right - 6 * FZoom, R.Bottom - 2 * FZoom);
      Detail := TrF('usa %d · usada por %d', [N.FanOut, N.FanIn]);
      DrawTextRect(Canvas, SubR, FitText(Canvas, Detail, SubR.Width), Fade(P.TextFaint, Alpha), 9.5 * FZoom, UiFont);
    end;
  end;
end;

procedure TCMGraphView.DrawLegend;
var
  I: Integer;
  X, Y, W, RowW: Single;
  R: TRectF;
begin
  if Length(FLayers) = 0 then
    Exit;
  X := 12;
  Y := 10;
  RowW := 0;
  for I := 0 to High(FLayers) do
    RowW := Max(RowW, MeasureText(FLayers[I], 11, UiFont));
  W := RowW + 44;
  R := TRectF.Create(X, Y, X + W, Y + 12 + Length(FLayers) * 20);
  FillRound(Canvas, R, 8, Fade(Pal.Surface, 0.92));
  StrokeRound(Canvas, R, 8, Pal.Border);
  for I := 0 to High(FLayers) do
  begin
    FillRound(Canvas, TRectF.Create(X + 12, Y + 12 + I * 20, X + 22, Y + 22 + I * 20), 3, ColorOfLayer(FLayers[I]));
    DrawTextRect(Canvas, TRectF.Create(X + 30, Y + 6 + I * 20, X + W - 4, Y + 28 + I * 20), FLayers[I], Pal.TextDim, 11,
      UiFont);
  end;
end;

procedure TCMGraphView.Paint;
var
  View: TRectF;
begin
  View := TRectF.Create(-80, -80, Width + 80, Height + 80);
  if (FGraph = nil) or (FGraph.Nodes.Count = 0) then
  begin
    DrawTextRect(Canvas, LocalRect, FEmptyText, Pal.TextFaint, 14, UiFont, [], TTextAlign.Center);
    Exit;
  end;
  DrawEdges(View);
  DrawNodes(View);
  DrawLegend;
end;

{ rato }

procedure TCMGraphView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  FDown := True;
  FMoved := False;
  FDownX := X;
  FDownY := Y;
  FLastX := X;
  FLastY := Y;
end;

procedure TCMGraphView.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  N: TDepNode;
begin
  inherited;
  if FDown then
  begin
    if (Abs(X - FDownX) > 3) or (Abs(Y - FDownY) > 3) then
      FMoved := True;
    if FMoved then
    begin
      FPanX := FPanX + (X - FLastX);
      FPanY := FPanY + (Y - FLastY);
      ClampPan;
      Cursor := crSizeAll;
      Repaint;
    end;
    FLastX := X;
    FLastY := Y;
    Exit;
  end;
  FLastX := X;
  FLastY := Y;
  Idx := NodeAt(X, Y);
  if Idx <> FHover then
  begin
    FHover := Idx;
    Repaint;
  end;
  if Idx >= 0 then
  begin
    N := FGraph.Nodes[Idx];
    Cursor := crHandPoint;
    Hint := N.Path + sLineBreak + TrF('%d métodos · %d linhas · complexidade máx. %d',
      [N.Methods, N.Lines, N.MaxComplexity]) + sLineBreak + TrF('usa %d · usada por %d', [N.FanOut, N.FanIn]);
    ShowHint := True;
  end
  else
  begin
    Cursor := crDefault;
    Hint := '';
  end;
end;

procedure TCMGraphView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
begin
  inherited;
  if not FDown then
    Exit;
  FDown := False;
  Cursor := crDefault;
  if not FMoved then
  begin
    Idx := NodeAt(X, Y);
    if Idx = FSelected then
      Idx := -1;         // um segundo clique larga a selecao
    SelectNode(Idx);
  end;
end;

procedure TCMGraphView.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
var
  NewZoom: Single;
begin
  inherited;
  NewZoom := EnsureRange(FZoom * Power(1.12, WheelDelta / 120), MinZoom, MaxZoom);
  // aproxima em volta do cursor
  FPanX := FLastX - (FLastX - FPanX) * NewZoom / FZoom;
  FPanY := FLastY - (FLastY - FPanY) * NewZoom / FZoom;
  FZoom := NewZoom;
  ClampPan;
  Handled := True;
  Repaint;
end;

procedure TCMGraphView.DoMouseLeave;
begin
  inherited;
  FHover := -1;
  FDown := False;
  Repaint;
end;

procedure TCMGraphView.Resize;
begin
  inherited;
  Repaint;
end;

end.
