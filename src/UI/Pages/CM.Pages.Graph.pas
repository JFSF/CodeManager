unit CM.Pages.Graph;

{ Pagina Grafo: mapa visual das dependencias entre as units (quem usa quem), com o resumo, os ciclos,
  os detalhes da unit seleccionada e a exportacao do relatorio (HTML com o mapa em SVG, e Markdown).
  O grafo calcula-se em segundo plano ao abrir a pagina e refaz-se quando a analise muda. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.Math, System.Threading,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, Winapi.Windows, Winapi.ShellAPI,
  CM.Theme, CM.Controls, CM.Layouts, CM.GraphView, CM.Deps, CM.Analyzer, CM.Store, CM.Pages.Host;

type
  TGraphPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FView: TCMGraphView;
    FSummary: TCMKeyValue;
    FSelCard: TCMPanel;
    FSelTitle: TCMLabel;
    FSelInfo: TCMKeyValue;
    FSelUses, FSelUsedBy: TCMLabel;
    FCyclesCard: TCMPanel;
    FCyclesText: TCMLabel;
    FGraph: TDepGraph;            // dono do grafo (a vista so o usa)
    FToken: Integer;
    FBuilding: Boolean;
    FStale: Boolean;
    FSimplifyBtn: TCMButton;
    FBarRow: TCMButtonRow;
    procedure SimplifyClick(Sender: TObject);
    procedure SearchChanged(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure ViewSelect(Sender: TObject);
    procedure ExportHtmlClick(Sender: TObject);
    procedure ExportMdClick(Sender: TObject);
    procedure DoExport(const AExt: string; AHtml: Boolean);
    procedure Build;
    procedure BuildDone(AToken: Integer; AGraph: TDepGraph; const AError: string);
    procedure ReleaseGraph;
    procedure ShowSummary;
    procedure ShowCycles;
    procedure ShowSelection;
    procedure FitSummaryCard;
    procedure FitSelCard;
    function NeighbourText(const ATitle: string; const AIdx: TArray<Integer>): string;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    // a analise mudou (ou ha outro projeto): o grafo actual deixa de valer
    procedure Invalidate;
    // a pagina passou a estar visivel: calcula o grafo se for preciso
    procedure Activate;
    property View: TCMGraphView read FView;
    property Search: TCMInput read FSearch;
    property Graph: TDepGraph read FGraph;
  end;

implementation

uses
  CM.Lang, CM.DepsReport;

function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

constructor TGraphPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Bar, Dummy: TCMControl;
  Side: TCMFadeScroll;
  Card: TCMPanel;
  Holder: TCMPanel;
  Row: TCMButtonRow;
  B: TCMButton;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;
  FStale := True;

  Bar := TCMControl.Create(Self);
  Bar.Parent := Self;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 42;
  Bar.Margins.Bottom := 16;

  Side := SideBox(Self, Self, 320);

  Card := SideCard(Self, Side, 264);
  TCMLabel.Make(Card, Tr('Resumo'), 15, True).Align := TAlignLayout.Top;
  FSummary := TCMKeyValue.Create(Self);
  FSummary.Parent := Card;
  FSummary.Align := TAlignLayout.Top;
  FSummary.Margins.Top := 8;

  FSelCard := SideCard(Self, Side, 330);
  TCMLabel.Make(FSelCard, Tr('Unit selecionada'), 15, True).Align := TAlignLayout.Top;
  FSelTitle := TCMLabel.Make(FSelCard, '', 12.5, True, lcAccentStrong, True);
  FSelTitle.Align := TAlignLayout.Top;
  FSelTitle.Height := 24;
  FSelTitle.Margins.Top := 6;
  FSelInfo := TCMKeyValue.Create(Self);
  FSelInfo.Parent := FSelCard;
  FSelInfo.Align := TAlignLayout.Top;
  FSelInfo.Margins.Top := 4;
  FSelUses := TCMLabel.Make(FSelCard, '', 11.5, False, lcDim, True);
  FSelUses.Wrap := True;
  FSelUses.Align := TAlignLayout.Top;
  FSelUses.Margins.Top := 8;
  FSelUsedBy := TCMLabel.Make(FSelCard, '', 11.5, False, lcDim, True);
  FSelUsedBy.Align := TAlignLayout.Top;
  FSelUsedBy.Margins.Top := 8;

  FCyclesCard := SideCard(Self, Side, 120);
  TCMLabel.Make(FCyclesCard, Tr('Ciclos'), 15, True).Align := TAlignLayout.Top;
  FCyclesText := TCMLabel.Make(FCyclesCard, '', 11.5, False, lcDim);
  FCyclesText.Wrap := True;
  FCyclesText.Align := TAlignLayout.Top;
  FCyclesText.Margins.Top := 8;

  Card := SideCard(Self, Side, 152);
  TCMLabel.Make(Card, Tr('Relatório de dependências'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('HTML (com mapa)'), icExport, bkPrimary, ExportHtmlClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Markdown'), icExport, bkSecondary, ExportMdClick);

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(1, 1, 1, 1);
  FView := TCMGraphView.Create(Self);
  FView.Parent := Holder;
  FView.Align := TAlignLayout.Client;
  FView.OnSelect := ViewSelect;
  FView.EmptyText := Tr('Analise um projeto para ver o mapa de dependências.');

  // barra: pesquisa e controlos de zoom
  Dummy := TCMControl.Create(Self);
  Dummy.Parent := Bar;
  Dummy.Align := TAlignLayout.Right;
  Dummy.Width := 392;
  Dummy.Margins.Left := 12;
  Row := TCMButtonRow.Create(Self);
  Row.Parent := Dummy;
  Row.Align := TAlignLayout.Client;
  FBarRow := Row;
  FSimplifyBtn := TCMButton.Create(Row);
  FSimplifyBtn.Parent := Row;
  FSimplifyBtn.Height := 42;
  FSimplifyBtn.Text := Tr('Simplificar');
  FSimplifyBtn.Hint := Tr('Esconde as ligações para as units usadas por muitas outras (voltam a aparecer ao selecionar uma unit).');
  FSimplifyBtn.ShowHint := True;
  FSimplifyBtn.OnClick := SimplifyClick;
  B := TCMButton.Make(Row, Tr('Ajustar'), icRefresh, bkSecondary, FitClick);
  B.Height := 42;
  B := TCMButton.MakeIcon(Row, icMinus, ZoomOutClick, Tr('Afastar'));
  B.Kind := bkSecondary;
  B.Height := 42;
  B := TCMButton.MakeIcon(Row, icPlus, ZoomInClick, Tr('Aproximar'));
  B.Kind := bkSecondary;
  B.Height := 42;
  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := Tr('Filtrar por unit ou camada…   ( / )');
  FSearch.OnChangeText := SearchChanged;
  FBarRow.Relayout;
end;

procedure TGraphPage.Resize;
begin
  inherited;
  if FBarRow <> nil then
    FBarRow.Relayout;
end;

destructor TGraphPage.Destroy;
begin
  Inc(FToken);                   // um calculo em curso deixa de ter efeito
  FView.SetGraph(nil);
  FGraph.Free;
  inherited;
end;

procedure TGraphPage.ApplyTheme;
begin
  FSearch.ApplyTheme;
  FView.Repaint;
end;

procedure TGraphPage.SearchChanged(Sender: TObject);
begin
  FView.Filter := FSearch.Text;
end;

procedure TGraphPage.FitClick(Sender: TObject);
begin
  FView.FitToView(False);
end;

procedure TGraphPage.SimplifyClick(Sender: TObject);
begin
  FView.Simplify := not FView.Simplify;
  FSimplifyBtn.Active := FView.Simplify;
end;

procedure TGraphPage.ZoomInClick(Sender: TObject);
begin
  FView.ZoomBy(1.25);
end;

procedure TGraphPage.ZoomOutClick(Sender: TObject);
begin
  FView.ZoomBy(0.8);
end;

{ grafo }

procedure TGraphPage.ReleaseGraph;
begin
  FView.SetGraph(nil);
  FreeAndNil(FGraph);
end;

procedure TGraphPage.Invalidate;
begin
  Inc(FToken);
  FBuilding := False;
  FStale := True;
  ReleaseGraph;
  FSearch.Text := '';
  ShowSummary;
  ShowCycles;
  ShowSelection;
end;

procedure TGraphPage.Activate;
begin
  if FStale and not FBuilding and (FHost.CurrentScan <> nil) then
    Build
  else if FHost.CurrentScan = nil then
    FView.EmptyText := Tr('Analise um projeto para ver o mapa de dependências.');
end;

procedure TGraphPage.Build;
var
  Inputs: TArray<TDepInput>;
  Root: string;
  Token: Integer;
begin
  // a lista de units copia-se aqui (na thread da interface); so a leitura dos ficheiros corre em segundo plano
  Inputs := CollectDepInputs(FHost.CurrentScan);
  Root := FHost.CurrentScan.Root;
  Inc(FToken);
  Token := FToken;
  FBuilding := True;
  FView.EmptyText := Tr('A calcular as dependências…');
  TTask.Run(
    procedure
    var
      G: TDepGraph;
      Err: string;
    begin
      G := nil;
      Err := '';
      try
        ReadDepSources(Root, Inputs);
        G := BuildDepGraph(Inputs);
      except
        on E: Exception do
          Err := E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          BuildDone(Token, G, Err);
        end);
    end);
end;

procedure TGraphPage.BuildDone(AToken: Integer; AGraph: TDepGraph; const AError: string);
begin
  if FHost.ShuttingDown or (AToken <> FToken) then
  begin
    AGraph.Free;
    Exit;
  end;
  FBuilding := False;
  if AError <> '' then
  begin
    AGraph.Free;
    FView.EmptyText := Tr('Não foi possível calcular as dependências: ') + AError;
    Exit;
  end;
  FStale := False;
  FGraph := AGraph;
  FView.EmptyText := Tr('Este projeto não tem units para mostrar.');
  FView.SetGraph(FGraph);
  ShowSummary;
  ShowCycles;
  ShowSelection;
end;

{ cartoes }

procedure TGraphPage.FitSummaryCard;
begin
  TCMPanel(FSummary.Parent).Height := 16 + 16 + 28 + 8 + FSummary.Height;
end;

procedure TGraphPage.ShowSummary;
begin
  if FGraph = nil then
    FSummary.SetRows([KV(Tr('Units'), '—'), KV(Tr('Ligações'), '—'), KV(Tr('Units externas'), '—'),
      KV(Tr('Ciclos'), '—'), KV(Tr('Colunas do mapa'), '—'), KV(Tr('Units sem uso'), '—')])
  else
    FSummary.SetRows([KV(Tr('Units'), IntToStr(FGraph.Nodes.Count)), KV(Tr('Ligações'), IntToStr(FGraph.Edges.Count)),
      KV(Tr('Units externas'), IntToStr(FGraph.ExternalCount)),
      KV(Tr('Ciclos'), IntToStr(Length(FGraph.Cycles)), Length(FGraph.Cycles) > 0),
      KV(Tr('Colunas do mapa'), IntToStr(FGraph.LevelCount)),
      KV(Tr('Units sem uso'), IntToStr(Length(FGraph.Unused)))]);
  FitSummaryCard;
end;

procedure TGraphPage.ShowCycles;
var
  I, K, Shown: Integer;
  S: string;
begin
  if (FGraph = nil) or (Length(FGraph.Cycles) = 0) then
  begin
    FCyclesText.Text := Tr('Nenhum ciclo: as units não se usam em círculo.');
    FCyclesText.Height := 40;
  end
  else
  begin
    S := '';
    Shown := Min(4, Length(FGraph.Cycles));
    for I := 0 to Shown - 1 do
    begin
      S := S + Format('%d. ', [I + 1]);
      for K := 0 to Min(3, High(FGraph.Cycles[I])) do
      begin
        if K > 0 then
          S := S + ' ⇄ ';
        S := S + FGraph.Nodes[FGraph.Cycles[I][K]].Name;
      end;
      if Length(FGraph.Cycles[I]) > 4 then
        S := S + Format(' … (+%d)', [Length(FGraph.Cycles[I]) - 4]);
      S := S + sLineBreak;
    end;
    if Length(FGraph.Cycles) > Shown then
      S := S + Format(Tr('… e mais %d (veja o relatório)'), [Length(FGraph.Cycles) - Shown]);
    FCyclesText.Text := S.TrimRight;
    FCyclesText.Height := 17 * (Shown + IfThen(Length(FGraph.Cycles) > Shown, 1, 0)) * 2 + 4;
  end;
  FCyclesCard.Height := 16 + 16 + 28 + 8 + FCyclesText.Height;
end;

function TGraphPage.NeighbourText(const ATitle: string; const AIdx: TArray<Integer>): string;
const
  MaxShown = 6;
var
  I: Integer;
begin
  Result := ATitle + ' (' + IntToStr(Length(AIdx)) + ')';
  for I := 0 to Min(MaxShown, Length(AIdx)) - 1 do
    Result := Result + sLineBreak + '  ' + FGraph.Nodes[AIdx[I]].Name;
  if Length(AIdx) > MaxShown then
    Result := Result + sLineBreak + Format('  … +%d', [Length(AIdx) - MaxShown]);
end;

procedure TGraphPage.FitSelCard;
begin
  FSelCard.Height := 16 + 16 + 28 + 6 + 24 + 4 + FSelInfo.Height + 8 + FSelUses.Height + 8 + FSelUsedBy.Height;
end;

procedure TGraphPage.ViewSelect(Sender: TObject);
begin
  ShowSelection;
end;

procedure TGraphPage.ShowSelection;
var
  N: TDepNode;
  I: Integer;
begin
  I := FView.Selected;
  if (FGraph = nil) or (I < 0) or (I >= FGraph.Nodes.Count) then
  begin
    FSelTitle.Text := '';
    FSelInfo.SetRows([]);
    FSelUses.Text := Tr('Clique numa unit do mapa para ver os detalhes.');
    FSelUses.Height := 40;
    FSelUsedBy.Text := '';
    FSelUsedBy.Height := 0;
    FitSelCard;
    Exit;
  end;
  N := FGraph.Nodes[I];
  FSelTitle.Text := N.Name;
  FSelInfo.SetRows([KV(Tr('Camada'), N.Layer), KV(Tr('Métodos'), IntToStr(N.Methods)),
    KV(Tr('Linhas'), IntToStr(N.Lines)), KV(Tr('Complexidade'), IntToStr(N.MaxComplexity), N.MaxComplexity > 20),
    KV(Tr('Usa'), IntToStr(N.FanOut)), KV(Tr('Usada por'), IntToStr(N.FanIn)),
    KV(Tr('Instabilidade'), FormatFloat('0.00', N.Instability)),
    KV(Tr('Units externas'), IntToStr(Length(N.External)))]);
  FSelUses.Text := NeighbourText(Tr('Usa'), N.Deps);
  FSelUses.Height := 16 * (1 + Min(7, Length(N.Deps))) + 4;
  FSelUsedBy.Text := NeighbourText(Tr('Usada por'), N.Dependents);
  FSelUsedBy.Height := 16 * (1 + Min(7, Length(N.Dependents))) + 4;
  FitSelCard;
end;

{ exportacao }

procedure TGraphPage.ExportHtmlClick(Sender: TObject);
begin
  DoExport('.html', True);
end;

procedure TGraphPage.ExportMdClick(Sender: TObject);
begin
  DoExport('.md', False);
end;

procedure TGraphPage.DoExport(const AExt: string; AHtml: Boolean);
var
  D: TSaveDialog;
  Profile: TProjectProfile;
  Content, Path: string;
begin
  Profile := FHost.CurrentProfile;
  if (Profile = nil) or (FGraph = nil) then
  begin
    FHost.Toast(Tr('Aguarde: o mapa de dependências ainda não está pronto.'));
    Exit;
  end;
  D := TSaveDialog.Create(nil);
  try
    if AHtml then
      D.Filter := 'HTML (*.html)|*.html'
    else
      D.Filter := 'Markdown (*.md)|*.md';
    D.DefaultExt := Copy(AExt, 2, MaxInt);
    D.FileName := DepsDefaultFileName(Profile.Name, AExt);
    if (Profile.OutputFolder <> '') and TDirectory.Exists(Profile.OutputFolder) then
      D.InitialDir := Profile.OutputFolder;
    if not D.Execute then
      Exit;
    Path := D.FileName;
  finally
    D.Free;
  end;
  try
    if AHtml then
      Content := DepsHtml(FGraph, Profile.Name, FHost.CurrentScan.Root)
    else
      Content := DepsMarkdown(FGraph, Profile.Name);
    SaveDepsReport(Path, Content);
    FHost.Toast(Tr('Exportado: ') + TPath.GetFileName(Path));
    if AHtml and FHost.AppSettings.OpenAfterExport then
      ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

end.
