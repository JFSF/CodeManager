unit CM.Pages.Map;

{ Pagina Mapa: arvore pastas > ficheiros > metodos, estatisticas, vista e exportacao/impressao
  da estrutura (Markdown, TXT, CSV, JSON). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, FMX.Printer,
  CM.Theme, CM.Controls, CM.Layouts, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.Export,
  CM.Print, CM.Plan, CM.SonarModel, CM.Pages.Host;

type
  TMapPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMTreeList;
    FStats: TCMKeyValue;
    FSonarCard: TCMPanel;
    FSonarInfo: TCMKeyValue;
    FExpMethods, FExpProgress: TCMSwitch;
    procedure Hint(const AText: string);
    procedure ListChanged(Sender: TObject);
    procedure FitStatsCard;
    procedure SearchChanged(Sender: TObject);
    procedure ExpandAllClick(Sender: TObject);
    procedure CollapseAllClick(Sender: TObject);
    procedure ExpandMethodsClick(Sender: TObject);
    procedure CollapseMethodsClick(Sender: TObject);
    procedure ExportMapClick(Sender: TObject);
    procedure ExportMdClick(Sender: TObject);
    procedure ExportTxtClick(Sender: TObject);
    procedure ExportCsvClick(Sender: TObject);
    procedure ExportJsonClick(Sender: TObject);
    procedure PrintClick(Sender: TObject);
    procedure ExportStructure(AFormat: TExportFormat);
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    procedure ApplyTheme;
    procedure ClearStats;
    procedure ShowStats(const St: TStats);
    // as medidas do SonarQube (so com uma consulta que as traga): liga e desliga o cartao
    procedure ShowSonar;
    function ExportOptionsNow: TExportOptions;
    // grava a estrutura no formato pedido; devolve False (com aviso) se falhar
    function SaveStructure(AFormat: TExportFormat; const AFileName: string): Boolean;
    // imprime na impressora activa do FMX (a escolhida no dialogo de impressao)
    procedure PrintNow;
    property List: TCMTreeList read FList;
    property Search: TCMInput read FSearch;
    property ExpMethods: TCMSwitch read FExpMethods;
    property ExpProgress: TCMSwitch read FExpProgress;
  end;

implementation


uses
  CM.Lang;
function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

constructor TMapPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Bar: TCMControl;
  Side: TCMFadeScroll;
  Card: TCMPanel;
  Holder: TCMPanel;
  Row: TCMButtonRow;
  Note: TCMLabel;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;

  Bar := TCMControl.Create(Self);
  Bar.Parent := Self;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 42;
  Bar.Margins.Bottom := 16;

  Side := SideBox(Self, Self, 320);

  Card := SideCard(Self, Side, 292);
  TCMLabel.Make(Card, Tr('Estatísticas'), 15, True).Align := TAlignLayout.Top;
  FStats := TCMKeyValue.Create(Self);
  FStats.Parent := Card;
  FStats.Align := TAlignLayout.Top;
  FStats.Margins.Top := 8;

  FSonarCard := SideCard(Self, Side, 200);
  FSonarCard.Visible := False;
  TCMLabel.Make(FSonarCard, 'SonarQube', 15, True).Align := TAlignLayout.Top;
  FSonarInfo := TCMKeyValue.Create(Self);
  FSonarInfo.Parent := FSonarCard;
  FSonarInfo.Align := TAlignLayout.Top;
  FSonarInfo.Margins.Top := 8;

  Card := SideCard(Self, Side, 176);
  TCMLabel.Make(Card, Tr('Vista'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('Expandir tudo'), icChevronDown, bkSecondary, ExpandAllClick);
  TCMButton.Make(Row, Tr('Colapsar tudo'), icChevronRight, bkSecondary, CollapseAllClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Abrir métodos'), icChevronDown, bkSecondary, ExpandMethodsClick);
  TCMButton.Make(Row, Tr('Fechar métodos'), icChevronRight, bkSecondary, CollapseMethodsClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Exportar mapa (HTML)'), icExport, bkPrimary, ExportMapClick);

  Card := SideCard(Self, Side, 290);
  TCMLabel.Make(Card, Tr('Exportar e imprimir estrutura'), 15, True).Align := TAlignLayout.Top;
  FExpMethods := TCMSwitch.Create(Self);
  FExpMethods.Parent := Card;
  FExpMethods.Align := TAlignLayout.Top;
  FExpMethods.Margins.Top := 12;
  FExpMethods.Text := Tr('Incluir métodos');
  FExpMethods.Checked := True;
  FExpProgress := TCMSwitch.Create(Self);
  FExpProgress.Parent := Card;
  FExpProgress.Align := TAlignLayout.Top;
  FExpProgress.Margins.Top := 6;
  FExpProgress.Text := Tr('Incluir estado e notas');
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('Markdown'), icExport, bkSecondary, ExportMdClick);
  TCMButton.Make(Row, Tr('TXT'), icExport, bkSecondary, ExportTxtClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('CSV (Excel)'), icExport, bkSecondary, ExportCsvClick);
  TCMButton.Make(Row, Tr('JSON'), icExport, bkSecondary, ExportJsonClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Imprimir…'), icExport, bkPrimary, PrintClick);

  Note := TCMLabel.Make(Side, Tr('As checkboxes C (Compila) e S (Sonar) ficam guardadas com o progresso do projeto.'),
    11.5, False, lcFaint);
  Note.Align := TAlignLayout.Top;
  Note.Wrap := True;
  Note.Height := 44;

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(6, 8, 0, 8);
  FList := TCMTreeList.Create(Self);
  FList.Parent := Holder;
  FList.Align := TAlignLayout.Client;
  FList.Mode := lmMap;
  FList.OnChanged := ListChanged;
  FList.OnHint := Hint;
  FList.EmptyText := Tr('Analise um projeto para ver o mapa de código.');

  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := Tr('Filtrar por pasta, ficheiro ou método…   ( / )');
  FSearch.OnChangeText := SearchChanged;
end;

procedure TMapPage.ApplyTheme;
begin
  FSearch.ApplyTheme;
end;

procedure TMapPage.Hint(const AText: string);
begin
  FHost.Toast(AText);
end;

procedure TMapPage.ListChanged(Sender: TObject);
begin
  FHost.MarkStateDirty;
  FHost.UpdateAll;
end;

procedure TMapPage.SearchChanged(Sender: TObject);
begin
  FList.Query := FSearch.Text;
end;

// o cartao das estatisticas acompanha o numero de linhas (28 px cada)
procedure TMapPage.FitStatsCard;
begin
  TCMPanel(FStats.Parent).Height := 16 + 16 + 28 + 8 + FStats.Height;
end;

procedure TMapPage.ClearStats;
begin
  FStats.SetRows([KV(Tr('Pastas'), '—'), KV(Tr('Ficheiros'), '—'), KV(Tr('Métodos'), '—'),
    KV(Tr('Units com métodos'), '—'), KV(Tr('Ficheiros · Compila'), '—'), KV(Tr('Ficheiros · Sonar'), '—'),
    KV(Tr('Métodos · Compila'), '—'), KV(Tr('Métodos · Sonar'), '—')]);
  FitStatsCard;
end;

procedure TMapPage.ShowStats(const St: TStats);
var
  Rows: TList<TKeyValue>;
  S: TPlanSummary;
begin
  Rows := TList<TKeyValue>.Create;
  try
    Rows.Add(KV(Tr('Pastas'), St.Folders.ToString));
    Rows.Add(KV(Tr('Ficheiros'), St.Files.ToString));
    Rows.Add(KV(Tr('Métodos'), St.Methods.ToString));
    Rows.Add(KV(Tr('Units com métodos'), St.UnitsWithMethods.ToString));
    Rows.Add(KV(Tr('Ficheiros · Compila'), Format('%d / %d', [St.FilesCompila, St.Files])));
    Rows.Add(KV(Tr('Ficheiros · Sonar'), Format('%d / %d', [St.FilesSonar, St.Files])));
    Rows.Add(KV(Tr('Métodos · Compila'), Format('%d / %d', [St.MethodsCompila, St.Methods])));
    Rows.Add(KV(Tr('Métodos · Sonar'), Format('%d / %d', [St.MethodsSonar, St.Methods])));
    if FHost.HasPlan then
    begin
      // plano x codigo: o que ja existe do que estava previsto, o que falta e o que sobra
      S := FHost.PlanSummary;
      Rows.Add(KV(Tr('Plano · ficheiros'), Format('%d / %d (%.0f%%)', [S.ImplementedFiles, S.PlannedFiles,
        S.FilesCoverage]), True));
      Rows.Add(KV(Tr('Plano · métodos'), Format('%d / %d (%.0f%%)', [S.ImplementedMethods, S.PlannedMethods,
        S.MethodsCoverage]), True));
      Rows.Add(KV(Tr('Por implementar'), Format(Tr('%d fich. · %d mét.'), [S.MissingFiles, S.MissingMethods])));
      Rows.Add(KV(Tr('Extra no código'), Format(Tr('%d fich. · %d mét.'), [S.ExtraFiles, S.ExtraMethods])));
    end;
    FStats.SetRows(Rows.ToArray);
  finally
    Rows.Free;
  end;
  FitStatsCard;
end;

procedure TMapPage.ShowSonar;
var
  Snap: TSonarSnapshot;
  Lines: TArray<TSonarLine>;
  Rows: TArray<TKeyValue>;
  I: Integer;
begin
  Snap := FHost.CurrentSonar;
  FSonarCard.Visible := False;
  if Snap = nil then
    Exit;
  Lines := SonarProjectLines(Snap.Project);
  if Length(Lines) = 0 then
    Exit;
  SetLength(Rows, Length(Lines));
  for I := 0 to High(Lines) do
    Rows[I] := KV(Lines[I].Caption, Lines[I].Value, Lines[I].Good);
  FSonarInfo.SetRows(Rows);
  FSonarCard.Height := 16 + 16 + 28 + 8 + FSonarInfo.Height;
  FSonarCard.Visible := True;
end;

procedure TMapPage.ExpandAllClick(Sender: TObject);
begin
  FList.ExpandAll;
end;

procedure TMapPage.CollapseAllClick(Sender: TObject);
begin
  FList.CollapseAll;
end;

procedure TMapPage.ExpandMethodsClick(Sender: TObject);
begin
  FList.ExpandMethods;
end;

procedure TMapPage.CollapseMethodsClick(Sender: TObject);
begin
  FList.CollapseMethods;
end;

procedure TMapPage.ExportMapClick(Sender: TObject);
begin
  FHost.ExportMapHtml(False);
end;

function TMapPage.ExportOptionsNow: TExportOptions;
begin
  Result.IncludeMethods := FExpMethods.Checked;
  Result.IncludeProgress := FExpProgress.Checked;
end;

function TMapPage.SaveStructure(AFormat: TExportFormat; const AFileName: string): Boolean;
begin
  Result := False;
  try
    ExportToFile(AFormat, FHost.CurrentProfile, FHost.CurrentScan, FHost.CurrentState,
      ExportOptionsNow, AFileName);
    FHost.Toast(Tr('Exportado: ') + TPath.GetFileName(AFileName));
    Result := True;
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

procedure TMapPage.ExportStructure(AFormat: TExportFormat);
var
  D: TSaveDialog;
  Ext: string;
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if (Profile = nil) or (FHost.CurrentScan = nil) then
  begin
    FHost.Toast(Tr('Analise o projeto primeiro.'));
    Exit;
  end;
  Ext := ExportFormatExt(AFormat);
  D := TSaveDialog.Create(nil);
  try
    D.Filter := ExportFormatName(AFormat) + ' (*' + Ext + ')|*' + Ext;
    D.DefaultExt := Copy(Ext, 2, MaxInt);
    D.FileName := ExportDefaultFileName(Profile, AFormat);
    if (Profile.OutputFolder <> '') and TDirectory.Exists(Profile.OutputFolder) then
      D.InitialDir := Profile.OutputFolder;
    if D.Execute then
      SaveStructure(AFormat, D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMapPage.PrintNow;
var
  Pages: Integer;
begin
  try
    Pages := PrintStructure(FHost.CurrentProfile, FHost.CurrentScan, FHost.CurrentState, ExportOptionsNow);
    if Pages = 1 then
      FHost.Toast(Tr('Enviada para a impressora: 1 página'))
    else
      FHost.Toast(Format(Tr('Enviada para a impressora: %d páginas'), [Pages]));
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a impressão: ') + E.Message);
  end;
end;

procedure TMapPage.PrintClick(Sender: TObject);
var
  D: TPrintDialog;
  Ok: Boolean;
begin
  if (FHost.CurrentProfile = nil) or (FHost.CurrentScan = nil) then
  begin
    FHost.Toast(Tr('Analise o projeto primeiro.'));
    Exit;
  end;
  try
    if Printer.Count = 0 then
    begin
      FHost.Toast(Tr('Não há impressoras instaladas.'));
      Exit;
    end;
    D := TPrintDialog.Create(nil);
    try
      D.Copies := 1;
      Ok := D.Execute;
    finally
      D.Free;
    end;
  except
    on E: Exception do
    begin
      FHost.Toast(Tr('Impressora indisponível: ') + E.Message);
      Exit;
    end;
  end;
  if Ok then
    PrintNow;
end;

procedure TMapPage.ExportMdClick(Sender: TObject);
begin
  ExportStructure(efMarkdown);
end;

procedure TMapPage.ExportTxtClick(Sender: TObject);
begin
  ExportStructure(efText);
end;

procedure TMapPage.ExportCsvClick(Sender: TObject);
begin
  ExportStructure(efCsv);
end;

procedure TMapPage.ExportJsonClick(Sender: TObject);
begin
  ExportStructure(efJson);
end;

end.
