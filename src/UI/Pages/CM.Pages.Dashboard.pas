unit CM.Pages.Dashboard;

{ Pagina Painel: graficos (Chart4D) com o progresso do projecto e a distribuicao do codigo.
  Os graficos seguem o tema da aplicacao (claro/escuro) e so se reconstroem quando a pagina
  esta visivel; ao voltar a ela (Activate) mostram sempre o estado actual. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Generics.Collections, System.Generics.Defaults,
  FMX.Types, FMX.Controls, FMX.Layouts,
  Chart4D.Types, Chart4D.Style, Chart4D.Axis, Chart4D.FMX,
  CM.Theme, CM.Controls, CM.Layouts, CM.Analyzer, CM.Store, CM.Stats, CM.History, CM.Plan, CM.Metrics, CM.Pages.Host;

type
  TDashboardPage = class(TCMControl)
  private
    FHost: IPageHost;
    FEmpty: TCMLabel;
    FScroll: TCMFadeScroll;
    FBody: TCMControl;
    FKpiRow: TCMCardRow;
    FKpi: array[0..3] of TCMKpi;
    FEvoRow: TCMControl;
    FRows: array[0..4] of TCMCardRow;           // a ultima so aparece quando ha plano
    FEvolution, FLayers, FStatus, FTop, FHist, FLayerMethods, FCompilaSonar: TChart4D;
    FPlanLayers, FPlanOverview, FComplexTop, FComplexDist: TChart4D;
    FStats: TStats;
    FHasStats: Boolean;
    FDirty: Boolean;
    function AddChartCard(ARow: Integer): TChart4D;
    function MakeChart(AParent: TFmxObject; AFill: Boolean): TChart4D;
    procedure Rebuild;
    procedure Relayout;
    procedure FillKpis;
    procedure StyleAll;
    procedure FillEvolution;
    procedure FillLayers;
    procedure FillCompilaSonar;
    procedure FillStatus;
    procedure FillTop;
    procedure FillHistogram;
    procedure FillLayerMethods;
    procedure FillPlan;
    procedure FillComplexity;
    procedure Reset(AChart: TChart4D; AKind: TChartKind; const ATitle, ASubtitle: string);
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    procedure ApplyTheme;
    procedure ClearStats;
    procedure ShowStats(const St: TStats);
    // a pagina passou a estar visivel: actualiza os graficos se os dados mudaram
    procedure Activate;
  end;

implementation

const
  ChartScale = 0.6;
  KpiHeight = 100;
  RowGap = 14;

function ThemedStyle: TChartStyle;
begin
  Result := TChartStyle.Default;
  Result.FontName := UiFont;
  Result.BackgroundColor := Pal.Surface;
  Result.TitleColor := Pal.Text;
  Result.TextColor := Pal.TextDim;
  Result.MutedTextColor := Pal.TextFaint;
  Result.GridColor := Pal.Border;
  Result.BaselineColor := Pal.BorderStrong;
  Result.ScaleFactor := ChartScale;
end;

constructor TDashboardPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  I: Integer;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;

  FEmpty := TCMLabel.Make(Self, 'Analise um projeto para ver o painel.', 14, False, lcFaint);
  FEmpty.Align := TAlignLayout.Top;
  FEmpty.Height := 40;
  FEmpty.Margins.Top := 8;

  FScroll := TCMFadeScroll.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := TAlignLayout.Client;
  FScroll.ShowScrollBars := False;

  FBody := TCMControl.Create(Self);
  FBody.Parent := FScroll;
  FBody.Align := TAlignLayout.Top;
  FBody.Height := 1200;
  FBody.Visible := False;
  FKpiRow := TCMCardRow.Create(Self);
  FKpiRow.Parent := FBody;
  FKpiRow.Align := TAlignLayout.Top;
  FKpiRow.Height := KpiHeight + RowGap;
  FKpiRow.Padding.Bottom := RowGap;
  FKpiRow.Columns := 4;
  for I := 0 to 3 do
  begin
    FKpi[I] := TCMKpi.Create(Self);
    FKpi[I].Parent := FKpiRow;
  end;
  FEvoRow := TCMControl.Create(Self);
  FEvoRow.Parent := FBody;
  FEvoRow.Align := TAlignLayout.Top;
  FEvoRow.Height := 380;
  FEvoRow.Padding.Bottom := RowGap;
  for I := 0 to High(FRows) do
  begin
    FRows[I] := TCMCardRow.Create(Self);
    FRows[I].Parent := FBody;
    FRows[I].Align := TAlignLayout.Top;
    FRows[I].Height := 380;
    FRows[I].Padding.Bottom := RowGap;
  end;

  FEvolution := MakeChart(FEvoRow, True);
  FLayers := AddChartCard(0);
  FStatus := AddChartCard(0);
  FTop := AddChartCard(1);
  FLayerMethods := AddChartCard(1);
  FHist := AddChartCard(2);
  FCompilaSonar := AddChartCard(2);
  FComplexTop := AddChartCard(3);
  FComplexDist := AddChartCard(3);
  FPlanLayers := AddChartCard(4);
  FPlanOverview := AddChartCard(4);
  StyleAll;
  Relayout;
end;

procedure TDashboardPage.Resize;
begin
  inherited;
  if FBody <> nil then
    Relayout;
end;

// alturas conforme o espaco: dois graficos por altura de janela, e em janelas estreitas os
// cartoes passam para menos colunas (numeros 4 -> 2, graficos 2 -> 1)
procedure TDashboardPage.Relayout;
var
  Narrow: Boolean;
  Cell: Single;
  I: Integer;
begin
  Narrow := Width < 940;
  Cell := EnsureRange((Height - KpiHeight - 3 * RowGap) / 2, 300, 460);
  if Narrow then FKpiRow.Columns := 2 else FKpiRow.Columns := 4;
  FKpiRow.Height := FKpiRow.HeightFor(KpiHeight);
  FEvoRow.Height := Cell + RowGap;
  for I := 0 to High(FRows) do
  begin
    if Narrow then FRows[I].Columns := 1 else FRows[I].Columns := 2;
    FRows[I].Height := FRows[I].HeightFor(Cell);
  end;
  FRows[4].Visible := FHost.HasPlan;
  FBody.Height := FKpiRow.Height + FEvoRow.Height + FRows[0].Height + FRows[1].Height + FRows[2].Height;
  FBody.Height := FBody.Height + FRows[3].Height;
  if FRows[4].Visible then
    FBody.Height := FBody.Height + FRows[4].Height;
end;

function TDashboardPage.AddChartCard(ARow: Integer): TChart4D;
begin
  Result := MakeChart(FRows[ARow], False);
end;

// cartao com um grafico dentro; AFill=True ocupa toda a linha (as linhas TCMHalves
// posicionam os cartoes elas proprias)
function TDashboardPage.MakeChart(AParent: TFmxObject; AFill: Boolean): TChart4D;
var
  Card: TCMPanel;
begin
  Card := TCMPanel.Create(Self);
  Card.Parent := AParent;
  if AFill then
    Card.Align := TAlignLayout.Client;
  Card.Padding.Rect := TRectF.Create(8, 8, 8, 8);
  Result := TChart4D.Create(Self);
  Result.Parent := Card;
  Result.Align := TAlignLayout.Client;
  Result.ShowTooltips := True;
end;

procedure TDashboardPage.StyleAll;
var
  C: TChart4D;
begin
  for C in [FEvolution, FLayers, FStatus, FTop, FHist, FLayerMethods, FCompilaSonar, FPlanLayers, FPlanOverview, FComplexTop, FComplexDist] do
    C.Plot.Style := ThemedStyle;
end;

procedure TDashboardPage.ApplyTheme;
begin
  StyleAll;
  Rebuild;
end;

procedure TDashboardPage.ClearStats;
begin
  FHasStats := False;
  FDirty := True;
  if Visible then
    Rebuild;
end;

procedure TDashboardPage.ShowStats(const St: TStats);
begin
  FStats := St;
  FHasStats := True;
  FDirty := True;
  if Visible then
    Rebuild;
end;

procedure TDashboardPage.Activate;
begin
  if FDirty then
    Rebuild;
end;

procedure TDashboardPage.Reset(AChart: TChart4D; AKind: TChartKind; const ATitle, ASubtitle: string);
begin
  AChart.Plot.ClearSeries;
  AChart.Plot.Categories := [];
  AChart.Plot.Kind := AKind;
  AChart.Plot.Title := ATitle;
  AChart.Plot.Subtitle := ASubtitle;
  AChart.Plot.Orientation := TChartOrientation.Vertical;
  AChart.Plot.LegendPosition := TLegendPosition.None;
  AChart.Plot.ValueLabels := TValueLabelMode.None;
  AChart.Plot.DonutCenterText := '';
  AChart.Plot.YAxis := TAxisOptions.Default;
  AChart.Plot.XAxis := TAxisOptions.Default;
end;

procedure TDashboardPage.Rebuild;
begin
  FDirty := False;
  FEmpty.Visible := not FHasStats or (FHost.CurrentScan = nil);
  FBody.Visible := not FEmpty.Visible;
  if FEmpty.Visible then
    Exit;
  FillKpis;
  FillEvolution;
  FillLayers;
  FillStatus;
  FillTop;
  FillHistogram;
  FillLayerMethods;
  FillCompilaSonar;
  FillComplexity;
  FillPlan;
  Relayout;                // a linha do plano aparece ou desaparece conforme ha plano
end;

procedure TDashboardPage.FillEvolution;
var
  History: THistory;
  Days, FilesPct, MethodsPct: TArray<Double>;
  I, N: Integer;
  Day: TDateTime;
  Axis: TAxisOptions;
  Subtitle: string;
begin
  History := FHost.CurrentHistory;
  N := 0;
  SetLength(Days, History.Count);
  SetLength(FilesPct, History.Count);
  SetLength(MethodsPct, History.Count);
  for I := 0 to History.Count - 1 do
    if History[I].TryDay(Day) then
    begin
      Days[N] := Day;
      FilesPct[N] := History[I].PercentFiles;
      MethodsPct[N] := History[I].PercentMethods;
      Inc(N);
    end;
  SetLength(Days, N);
  SetLength(FilesPct, N);
  SetLength(MethodsPct, N);

  if N < 2 then
    Subtitle := 'Ainda só há um registo: a curva aparece a partir do segundo dia'
  else
    Subtitle := Format('%s a %s · %d registos', [FormatDateTime('dd/mm/yyyy', Days[0]),
      FormatDateTime('dd/mm/yyyy', Days[N - 1]), N]);
  Reset(FEvolution, TChartKind.Line, 'Evolução do progresso', Subtitle);
  if N = 0 then
    Exit;
  FEvolution.Plot.LegendPosition := TLegendPosition.Top;
  FEvolution.Plot.AddLineSeries('Ficheiros concluídos', Days, FilesPct).Color := Pal.Accent;
  FEvolution.Plot.AddLineSeries('Métodos revistos', Days, MethodsPct).Color := Pal.FlagCompila;
  Axis := FEvolution.Plot.YAxis;
  Axis.MinValue := 0;
  Axis.MaxValue := 100;
  Axis.LabelSuffix := '%';
  FEvolution.Plot.YAxis := Axis;
  Axis := FEvolution.Plot.XAxis;
  Axis.DateMode := TAxisDateMode.Auto;
  Axis.LocaleName := 'pt-PT';             // meses em portugues no eixo
  FEvolution.Plot.XAxis := Axis;
end;

procedure TDashboardPage.FillLayers;
var
  Names: TArray<string>;
  Done, Pending: TArray<Double>;
  I: Integer;
begin
  SetLength(Names, Length(FStats.Layers));
  SetLength(Done, Length(Names));
  SetLength(Pending, Length(Names));
  for I := 0 to High(FStats.Layers) do
  begin
    Names[I] := FStats.Layers[I].Name;
    Done[I] := FStats.Layers[I].Done;
    Pending[I] := FStats.Layers[I].Total - FStats.Layers[I].Done;
  end;
  Reset(FLayers, TChartKind.StackedBar, 'Progresso por camada', 'Ficheiros concluídos e por concluir');
  FLayers.Plot.Orientation := TChartOrientation.Horizontal;
  FLayers.Plot.LegendPosition := TLegendPosition.Top;
  FLayers.Plot.Categories := Names;
  FLayers.Plot.AddSeries('Concluídos', Done).Color := Pal.Accent;
  FLayers.Plot.AddSeries('Por concluir', Pending).Color := Pal.BorderStrong;
end;

procedure TDashboardPage.FillKpis;
const
  MaxSpark = 30;           // ultimos registos na mini-curva
var
  History: THistory;
  Files, Methods, Compila, Sonar: TArray<Double>;
  I, First, N: Integer;

  function Pct(AValue, ATotal: Integer): Integer;
  begin
    if ATotal > 0 then Result := Round(100 * AValue / ATotal) else Result := 0;
  end;

begin
  History := FHost.CurrentHistory;
  First := Max(0, History.Count - MaxSpark);
  N := History.Count - First;
  SetLength(Files, N);
  SetLength(Methods, N);
  SetLength(Compila, N);
  SetLength(Sonar, N);
  for I := 0 to N - 1 do
  begin
    Files[I] := History[First + I].PercentFiles;
    Methods[I] := History[First + I].PercentMethods;
    Compila[I] := History[First + I].PercentFilesCompila;
    Sonar[I] := History[First + I].PercentFilesSonar;
  end;
  FKpi[0].SetValues('Ficheiros concluídos', Format('%d / %d', [FStats.DoneFiles, FStats.Files]),
    Format('%d%% do projeto', [Pct(FStats.DoneFiles, FStats.Files)]), Files, Pal.Accent);
  FKpi[1].SetValues('Métodos revistos', Format('%d / %d', [FStats.DoneMethods, FStats.Methods]),
    Format('%d%% dos métodos', [Pct(FStats.DoneMethods, FStats.Methods)]), Methods, Pal.FlagCompila);
  FKpi[2].SetValues('Compila', Format('%d / %d', [FStats.FilesCompila, FStats.Files]),
    Format('%d%% dos ficheiros', [Pct(FStats.FilesCompila, FStats.Files)]), Compila, Pal.FlagCompila);
  FKpi[3].SetValues('Sonar', Format('%d / %d', [FStats.FilesSonar, FStats.Files]),
    Format('%d%% dos ficheiros', [Pct(FStats.FilesSonar, FStats.Files)]), Sonar, Pal.FlagSonar);
end;

procedure TDashboardPage.FillCompilaSonar;
var
  Names: TArray<string>;
  Compila, Sonar: TArray<Double>;
  Index: TDictionary<string, Integer>;
  U: TUnitInfo;
  S: TUnitState;
  Idx: Integer;
begin
  Index := TDictionary<string, Integer>.Create;
  try
    SetLength(Names, 0);
    SetLength(Compila, 0);
    SetLength(Sonar, 0);
    if FHost.CurrentScan <> nil then
      for U in FHost.CurrentScan.Units do
      begin
        if not Index.TryGetValue(U.Layer, Idx) then
        begin
          Idx := Length(Names);
          Index.Add(U.Layer, Idx);
          SetLength(Names, Idx + 1);
          SetLength(Compila, Idx + 1);
          SetLength(Sonar, Idx + 1);
          Names[Idx] := U.Layer;
        end;
        S := FHost.CurrentState.Find(U.Path);
        if S <> nil then
        begin
          if S.Compila then Compila[Idx] := Compila[Idx] + 1;
          if S.Sonar then Sonar[Idx] := Sonar[Idx] + 1;
        end;
      end;
  finally
    Index.Free;
  end;
  Reset(FCompilaSonar, TChartKind.GroupedBar, 'Compila e Sonar por camada', 'Ficheiros com cada marca');
  FCompilaSonar.Plot.LegendPosition := TLegendPosition.Top;
  FCompilaSonar.Plot.Categories := Names;
  FCompilaSonar.Plot.AddSeries('Compila', Compila).Color := Pal.FlagCompila;
  FCompilaSonar.Plot.AddSeries('Sonar', Sonar).Color := Pal.FlagSonar;
end;

// complexidade ciclomatica dos metodos com corpo: os mais complexos e quantos ha em cada nivel
procedure TDashboardPage.FillComplexity;
const
  TopN = 10;
type
  TEntry = record
    Name: string;
    Lines, Complexity: Integer;
  end;
var
  Items: TList<TEntry>;
  U: TUnitInfo;
  M: TMethodInfo;
  E: TEntry;
  Names: TArray<string>;
  Values: TArray<Double>;
  Levels: array[TComplexityLevel] of Integer;
  I, N: Integer;
begin
  Items := TList<TEntry>.Create;
  try
    FillChar(Levels, SizeOf(Levels), 0);
    if FHost.CurrentScan <> nil then
      for U in FHost.CurrentScan.Units do
        for M in U.Methods do
          if M.Lines > 0 then
          begin
            E.Name := M.Name;
            E.Lines := M.Lines;
            E.Complexity := M.Complexity;
            Items.Add(E);
            Inc(Levels[ComplexityLevel(M.Complexity)]);
          end;
    Items.Sort(TComparer<TEntry>.Construct(
      function(const A, B: TEntry): Integer
      begin
        Result := B.Complexity - A.Complexity;
        if Result = 0 then
          Result := B.Lines - A.Lines;
        if Result = 0 then
          Result := CompareText(A.Name, B.Name);
      end));
    N := Min(TopN, Items.Count);
    SetLength(Names, N);
    SetLength(Values, N);
    for I := 0 to N - 1 do
    begin
      Names[I] := Items[I].Name;
      Values[I] := Items[I].Complexity;
    end;
  finally
    Items.Free;
  end;
  Reset(FComplexTop, TChartKind.Bar, 'Métodos mais complexos',
    Format('Os %d com maior complexidade ciclomática', [N]));
  FComplexTop.Plot.Orientation := TChartOrientation.Horizontal;
  FComplexTop.Plot.Categories := Names;
  FComplexTop.Plot.AddSeries('Complexidade', Values).Color := Pal.Pending;

  Reset(FComplexDist, TChartKind.Bar, 'Complexidade dos métodos',
    'Quantos métodos em cada nível (simples até 10, moderada até 20)');
  FComplexDist.Plot.Categories := ['Simples', 'Moderada', 'Alta'];
  FComplexDist.Plot.AddSeries('Métodos',
    [Levels[cxLow], Levels[cxModerate], Levels[cxHigh]]).Color := Pal.Accent;
end;

// cobertura do plano: por camada (ficheiros) e o total de ficheiros e metodos; so com plano
procedure TDashboardPage.FillPlan;
var
  Layers: TArray<TPlanLayerCoverage>;
  Names: TArray<string>;
  Done, Missing, Extra: TArray<Double>;
  S: TPlanSummary;
  I: Integer;
begin
  if not FHost.HasPlan then
    Exit;
  S := FHost.PlanSummary;
  Layers := PlanLayerCoverage(FHost.CurrentPlanView);
  SetLength(Names, Length(Layers));
  SetLength(Done, Length(Layers));
  SetLength(Missing, Length(Layers));
  SetLength(Extra, Length(Layers));
  for I := 0 to High(Layers) do
  begin
    Names[I] := Layers[I].Layer;
    Done[I] := Layers[I].Implemented;
    Missing[I] := Layers[I].Missing;
    Extra[I] := Layers[I].Extra;
  end;
  Reset(FPlanLayers, TChartKind.StackedBar, 'Cobertura do plano por camada',
    Format('Ficheiros · %.0f%% do planeado já existe', [S.FilesCoverage]));
  FPlanLayers.Plot.Orientation := TChartOrientation.Horizontal;
  FPlanLayers.Plot.LegendPosition := TLegendPosition.Top;
  FPlanLayers.Plot.Categories := Names;
  FPlanLayers.Plot.AddSeries('Implementados', Done).Color := Pal.Accent;
  FPlanLayers.Plot.AddSeries('Por implementar', Missing).Color := Pal.Pending;
  FPlanLayers.Plot.AddSeries('Extra', Extra).Color := Pal.FlagCompila;

  Reset(FPlanOverview, TChartKind.GroupedBar, 'Plano e código',
    Format('Cobertura: %.0f%% dos ficheiros · %.0f%% dos métodos', [S.FilesCoverage, S.MethodsCoverage]));
  FPlanOverview.Plot.LegendPosition := TLegendPosition.Top;
  FPlanOverview.Plot.Categories := ['Ficheiros', 'Métodos'];
  FPlanOverview.Plot.AddSeries('Implementados', [S.ImplementedFiles, S.ImplementedMethods]).Color := Pal.Accent;
  FPlanOverview.Plot.AddSeries('Por implementar', [S.MissingFiles, S.MissingMethods]).Color := Pal.Pending;
  FPlanOverview.Plot.AddSeries('Extra', [S.ExtraFiles, S.ExtraMethods]).Color := Pal.FlagCompila;
end;

procedure TDashboardPage.FillStatus;
var
  Axis: TAxisOptions;
begin
  Reset(FStatus, TChartKind.Bar, 'Estado dos ficheiros',
    Format('Em %d ficheiros', [FStats.Files]));
  FStatus.Plot.Categories := ['Concluídos', 'Em revisão', 'A alterar', 'Compila', 'Sonar'];
  FStatus.Plot.AddSeries('Ficheiros',
    [FStats.FilesByReview[rsDone], FStats.FilesByReview[rsInReview], FStats.FilesByReview[rsNeedsChange],
     FStats.FilesCompila, FStats.FilesSonar]).Color := Pal.Accent;
  // a escala vai de 0 ao total de ficheiros, mesmo quando ainda nada esta marcado
  Axis := FStatus.Plot.YAxis;
  Axis.MinValue := 0;
  Axis.MaxValue := Max(FStats.Files, 1);
  FStatus.Plot.YAxis := Axis;
end;

procedure TDashboardPage.FillTop;
const
  TopN = 10;
var
  Units: TList<TUnitInfo>;
  Names: TArray<string>;
  Counts: TArray<Double>;
  I, N: Integer;
begin
  Units := TList<TUnitInfo>.Create;
  try
    if FHost.CurrentScan <> nil then
      Units.AddRange(FHost.CurrentScan.Units);
    Units.Sort(TComparer<TUnitInfo>.Construct(
      function(const A, B: TUnitInfo): Integer
      begin
        Result := Length(B.Methods) - Length(A.Methods);
        if Result = 0 then
          Result := CompareText(A.BaseName, B.BaseName);
      end));
    N := Min(TopN, Units.Count);
    SetLength(Names, N);
    SetLength(Counts, N);
    for I := 0 to N - 1 do
    begin
      Names[I] := Units[I].BaseName;
      Counts[I] := Length(Units[I].Methods);
    end;
  finally
    Units.Free;
  end;
  Reset(FTop, TChartKind.Bar, 'Maiores units', Format('As %d com mais métodos', [N]));
  FTop.Plot.Orientation := TChartOrientation.Horizontal;
  FTop.Plot.Categories := Names;
  FTop.Plot.AddSeries('Métodos', Counts).Color := Pal.Accent;
end;

procedure TDashboardPage.FillHistogram;
var
  Values: TArray<Double>;
  U: TUnitInfo;
  I, MaxM: Integer;
  Width: Double;
begin
  SetLength(Values, 0);
  MaxM := 0;
  if FHost.CurrentScan <> nil then
  begin
    SetLength(Values, FHost.CurrentScan.Units.Count);
    I := 0;
    for U in FHost.CurrentScan.Units do
    begin
      Values[I] := Length(U.Methods);
      MaxM := Max(MaxM, Length(U.Methods));
      Inc(I);
    end;
  end;
  Reset(FHist, TChartKind.Histogram, 'Métodos por ficheiro', 'Quantos ficheiros têm cada número de métodos');
  if Length(Values) = 0 then
    Exit;
  Width := Max(1, Ceil(MaxM / 8));
  FHist.Plot.SetHistogramData(Values, Width);
  if FHist.Plot.Series.Count > 0 then
    FHist.Plot.Series[0].Color := Pal.Accent;
end;

procedure TDashboardPage.FillLayerMethods;
var
  Names: TArray<string>;
  Counts: TArray<Double>;
  Index: TDictionary<string, Integer>;
  U: TUnitInfo;
  Idx: Integer;
begin
  Index := TDictionary<string, Integer>.Create;
  try
    SetLength(Names, 0);
    SetLength(Counts, 0);
    if FHost.CurrentScan <> nil then
      for U in FHost.CurrentScan.Units do
      begin
        if not Index.TryGetValue(U.Layer, Idx) then
        begin
          Idx := Length(Names);
          Index.Add(U.Layer, Idx);
          SetLength(Names, Idx + 1);
          SetLength(Counts, Idx + 1);
          Names[Idx] := U.Layer;
        end;
        Counts[Idx] := Counts[Idx] + Length(U.Methods);
      end;
  finally
    Index.Free;
  end;
  Reset(FLayerMethods, TChartKind.Bar, 'Métodos por camada', Format('Total: %d métodos', [FStats.Methods]));
  FLayerMethods.Plot.Categories := Names;
  FLayerMethods.Plot.AddSeries('Métodos', Counts).Color := Pal.Accent;
end;

end.
