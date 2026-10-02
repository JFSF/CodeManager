unit CM.Pages.Map;

{ Pagina Mapa: arvore pastas > ficheiros > metodos, estatisticas, vista e exportacao/impressao
  da estrutura (Markdown, TXT, CSV, JSON). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, FMX.Printer,
  CM.Theme, CM.Controls, CM.Layouts, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.Export,
  CM.Print, CM.Plan, CM.Pages.Host;

type
  TMapPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMTreeList;
    FStats: TCMKeyValue;
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
  TCMLabel.Make(Card, 'Estatísticas', 15, True).Align := TAlignLayout.Top;
  FStats := TCMKeyValue.Create(Self);
  FStats.Parent := Card;
  FStats.Align := TAlignLayout.Top;
  FStats.Margins.Top := 8;

  Card := SideCard(Self, Side, 176);
  TCMLabel.Make(Card, 'Vista', 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, 'Expandir tudo', icChevronDown, bkSecondary, ExpandAllClick);
  TCMButton.Make(Row, 'Colapsar tudo', icChevronRight, bkSecondary, CollapseAllClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Abrir métodos', icChevronDown, bkSecondary, ExpandMethodsClick);
  TCMButton.Make(Row, 'Fechar métodos', icChevronRight, bkSecondary, CollapseMethodsClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Exportar mapa (HTML)', icExport, bkPrimary, ExportMapClick);

  Card := SideCard(Self, Side, 290);
  TCMLabel.Make(Card, 'Exportar e imprimir estrutura', 15, True).Align := TAlignLayout.Top;
  FExpMethods := TCMSwitch.Create(Self);
  FExpMethods.Parent := Card;
  FExpMethods.Align := TAlignLayout.Top;
  FExpMethods.Margins.Top := 12;
  FExpMethods.Text := 'Incluir métodos';
  FExpMethods.Checked := True;
  FExpProgress := TCMSwitch.Create(Self);
  FExpProgress.Parent := Card;
  FExpProgress.Align := TAlignLayout.Top;
  FExpProgress.Margins.Top := 6;
  FExpProgress.Text := 'Incluir estado e notas';
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, 'Markdown', icExport, bkSecondary, ExportMdClick);
  TCMButton.Make(Row, 'TXT', icExport, bkSecondary, ExportTxtClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'CSV (Excel)', icExport, bkSecondary, ExportCsvClick);
  TCMButton.Make(Row, 'JSON', icExport, bkSecondary, ExportJsonClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Imprimir…', icExport, bkPrimary, PrintClick);

  Note := TCMLabel.Make(Side, 'As checkboxes C (Compila) e S (Sonar) ficam guardadas com o progresso do projeto.',
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
  FList.EmptyText := 'Analise um projeto para ver o mapa de código.';

  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := 'Filtrar por pasta, ficheiro ou método…   ( / )';
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
  FStats.SetRows([KV('Pastas', '—'), KV('Ficheiros', '—'), KV('Métodos', '—'),
    KV('Units com métodos', '—'), KV('Ficheiros · Compila', '—'), KV('Ficheiros · Sonar', '—'),
    KV('Métodos · Compila', '—'), KV('Métodos · Sonar', '—')]);
  FitStatsCard;
end;

procedure TMapPage.ShowStats(const St: TStats);
var
  Rows: TList<TKeyValue>;
  S: TPlanSummary;
begin
  Rows := TList<TKeyValue>.Create;
  try
    Rows.Add(KV('Pastas', St.Folders.ToString));
    Rows.Add(KV('Ficheiros', St.Files.ToString));
    Rows.Add(KV('Métodos', St.Methods.ToString));
    Rows.Add(KV('Units com métodos', St.UnitsWithMethods.ToString));
    Rows.Add(KV('Ficheiros · Compila', Format('%d / %d', [St.FilesCompila, St.Files])));
    Rows.Add(KV('Ficheiros · Sonar', Format('%d / %d', [St.FilesSonar, St.Files])));
    Rows.Add(KV('Métodos · Compila', Format('%d / %d', [St.MethodsCompila, St.Methods])));
    Rows.Add(KV('Métodos · Sonar', Format('%d / %d', [St.MethodsSonar, St.Methods])));
    if FHost.HasPlan then
    begin
      // plano x codigo: o que ja existe do que estava previsto, o que falta e o que sobra
      S := FHost.PlanSummary;
      Rows.Add(KV('Plano · ficheiros', Format('%d / %d (%.0f%%)', [S.ImplementedFiles, S.PlannedFiles,
        S.FilesCoverage]), True));
      Rows.Add(KV('Plano · métodos', Format('%d / %d (%.0f%%)', [S.ImplementedMethods, S.PlannedMethods,
        S.MethodsCoverage]), True));
      Rows.Add(KV('Por implementar', Format('%d fich. · %d mét.', [S.MissingFiles, S.MissingMethods])));
      Rows.Add(KV('Extra no código', Format('%d fich. · %d mét.', [S.ExtraFiles, S.ExtraMethods])));
    end;
    FStats.SetRows(Rows.ToArray);
  finally
    Rows.Free;
  end;
  FitStatsCard;
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
    FHost.Toast('Exportado: ' + TPath.GetFileName(AFileName));
    Result := True;
  except
    on E: Exception do
      FHost.Toast('Falhou a exportação: ' + E.Message);
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
    FHost.Toast('Analise o projeto primeiro.');
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
      FHost.Toast('Enviada para a impressora: 1 página')
    else
      FHost.Toast(Format('Enviada para a impressora: %d páginas', [Pages]));
  except
    on E: Exception do
      FHost.Toast('Falhou a impressão: ' + E.Message);
  end;
end;

procedure TMapPage.PrintClick(Sender: TObject);
var
  D: TPrintDialog;
  Ok: Boolean;
begin
  if (FHost.CurrentProfile = nil) or (FHost.CurrentScan = nil) then
  begin
    FHost.Toast('Analise o projeto primeiro.');
    Exit;
  end;
  try
    if Printer.Count = 0 then
    begin
      FHost.Toast('Não há impressoras instaladas.');
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
      FHost.Toast('Impressora indisponível: ' + E.Message);
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
