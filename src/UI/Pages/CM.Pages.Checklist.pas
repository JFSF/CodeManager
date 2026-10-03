unit CM.Pages.Checklist;

{ Pagina Checklist: ficheiros agrupados por pasta, progresso por camada, filtros, notas e
  exportar/importar/reiniciar o progresso. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.IOUtils,
  System.Rtti,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, FMX.Platform, FMX.DialogService.Sync,
  CM.Theme, CM.Controls, CM.Layouts, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.Plan, CM.Pages.Host;

type
  TChecklistPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMTreeList;
    FRing: TCMRing;
    FBars: TCMBars;
    FPlanStats: TCMKeyValue;       // cobertura do plano; o cartao so aparece quando ha plano
    FChips: TCMChipFlow;
    FStarBtn: TCMButton;
    FNotePanel: TCMPanel;
    FNoteLabel: TCMLabel;
    FNoteIn: TCMInput;
    FNoteUnit: TUnitInfo;
    FLoadingFields: Boolean;
    procedure Hint(const AText: string);
    procedure FitProgressCard;
    procedure ShowPlanCard;
    procedure FitChipsCard(Sender: TObject);
    procedure ListChanged(Sender: TObject);
    procedure SearchChanged(Sender: TObject);
    procedure StarOnlyClick(Sender: TObject);
    procedure ChipClick(Sender: TObject);
    procedure EditNote(AUnit: TUnitInfo);
    procedure NoteChanged(Sender: TObject);
    procedure ExpandAllClick(Sender: TObject);
    procedure CollapseAllClick(Sender: TObject);
    procedure ExpandMethodsClick(Sender: TObject);
    procedure CollapseMethodsClick(Sender: TObject);
    procedure CopyMarkdownClick(Sender: TObject);
    procedure ExportProgressClick(Sender: TObject);
    procedure ImportProgressClick(Sender: TObject);
    procedure ResetProgressClick(Sender: TObject);
    procedure ExportChecklistClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    procedure ApplyTheme;
    procedure ClearStats;
    procedure ShowStats(const St: TStats);
    procedure RebuildChips;
    procedure CloseNote(Sender: TObject);
    // fecha a nota se o ficheiro deixou de existir na analise
    procedure CloseNoteIfRemoved(AScan: TProjectScan);
    property List: TCMTreeList read FList;
    property Search: TCMInput read FSearch;
    property NoteIn: TCMInput read FNoteIn;
  end;

implementation

function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

constructor TChecklistPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Bar: TCMControl;
  Side: TCMFadeScroll;
  Card: TCMPanel;
  Holder: TCMPanel;
  Row: TCMButtonRow;
  CloseBtn: TCMButton;
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

  Side := SideBox(Self, Self, 340);

  Card := SideCard(Self, Side, 250);
  TCMLabel.Make(Card, 'Progresso', 15, True).Align := TAlignLayout.Top;
  FRing := TCMRing.Create(Self);
  FRing.Parent := Card;
  FRing.Align := TAlignLayout.Top;
  FRing.Margins.Top := 12;
  FBars := TCMBars.Create(Self);
  FBars.Parent := Card;
  FBars.Align := TAlignLayout.Top;
  FBars.Margins.Top := 14;

  Card := SideCard(Self, Side, 200);
  Card.Visible := False;
  TCMLabel.Make(Card, 'Plano', 15, True).Align := TAlignLayout.Top;
  FPlanStats := TCMKeyValue.Create(Self);
  FPlanStats.Parent := Card;
  FPlanStats.Align := TAlignLayout.Top;
  FPlanStats.Margins.Top := 8;

  Card := SideCard(Self, Side, 120);
  TCMLabel.Make(Card, 'Filtrar por camada', 15, True).Align := TAlignLayout.Top;
  FChips := TCMChipFlow.Create(Self);
  FChips.Parent := Card;
  FChips.Align := TAlignLayout.Top;
  FChips.Margins.Top := 12;
  FChips.OnRelayout := FitChipsCard;

  Card := SideCard(Self, Side, 300);
  TCMLabel.Make(Card, 'Ações', 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, 'Expandir tudo', icChevronDown, bkSecondary, ExpandAllClick);
  TCMButton.Make(Row, 'Colapsar tudo', icChevronRight, bkSecondary, CollapseAllClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Abrir métodos', icChevronDown, bkSecondary, ExpandMethodsClick);
  TCMButton.Make(Row, 'Fechar métodos', icChevronRight, bkSecondary, CollapseMethodsClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Markdown', icCopy, bkSecondary, CopyMarkdownClick);
  TCMButton.Make(Row, 'Exportar HTML', icExport, bkPrimary, ExportChecklistClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Exportar', icDownload, bkSecondary, ExportProgressClick);
  TCMButton.Make(Row, 'Importar', icUpload, bkSecondary, ImportProgressClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, 'Reiniciar progresso', icRefresh, bkDanger, ResetProgressClick);

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(6, 8, 0, 8);

  FNotePanel := TCMPanel.Create(Self);
  FNotePanel.Parent := Holder;
  FNotePanel.Align := TAlignLayout.Bottom;
  FNotePanel.Height := 92;
  FNotePanel.Role := prSurface2;
  FNotePanel.Radius := 10;
  FNotePanel.Bordered := False;
  FNotePanel.Padding.Rect := TRectF.Create(14, 10, 14, 10);
  FNotePanel.Margins.Rect := TRectF.Create(6, 6, 6, 4);
  FNotePanel.Visible := False;
  CloseBtn := TCMButton.MakeIcon(FNotePanel, icClose, CloseNote, 'Fechar nota');
  CloseBtn.Align := TAlignLayout.Right;
  CloseBtn.Margins.Left := 8;
  FNoteLabel := TCMLabel.Make(FNotePanel, '', 12, True, lcDim, True);
  FNoteLabel.Align := TAlignLayout.Top;
  FNoteLabel.Height := 22;
  FNoteIn := TCMInput.Create(Self);
  FNoteIn.Parent := FNotePanel;
  FNoteIn.Align := TAlignLayout.Client;
  FNoteIn.Placeholder := 'Nota sobre este ficheiro…';
  FNoteIn.OnChangeText := NoteChanged;

  FList := TCMTreeList.Create(Self);
  FList.Parent := Holder;
  FList.Align := TAlignLayout.Client;
  FList.Mode := lmChecklist;
  FList.OnChanged := ListChanged;
  FList.OnEditNote := EditNote;
  FList.OnHint := Hint;
  FList.EmptyText := 'Analise um projeto para ver a checklist.';

  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := 'Filtrar por nome ou pasta…   ( / )';
  FSearch.OnChangeText := SearchChanged;

  FStarBtn := TCMButton.Make(Bar, 'Só prioritários', icStar, bkSecondary, StarOnlyClick);
  FStarBtn.Align := TAlignLayout.Right;
  FStarBtn.Height := 42;
  FStarBtn.Margins.Left := 10;
end;

procedure TChecklistPage.ApplyTheme;
begin
  FSearch.ApplyTheme;
  FNoteIn.ApplyTheme;
end;

procedure TChecklistPage.Hint(const AText: string);
begin
  FHost.Toast(AText);
end;

procedure TChecklistPage.ListChanged(Sender: TObject);
begin
  FHost.MarkStateDirty;
  FHost.UpdateAll;
end;

procedure TChecklistPage.SearchChanged(Sender: TObject);
begin
  FList.Query := FSearch.Text;
end;

procedure TChecklistPage.StarOnlyClick(Sender: TObject);
begin
  FStarBtn.Active := not FStarBtn.Active;
  FList.StarOnly := FStarBtn.Active;
end;

// o cartao acompanha o numero de camadas (cada linha de barras tem 24 px)
procedure TChecklistPage.FitProgressCard;
begin
  TCMPanel(FRing.Parent).Height := 16 + 16 + 26 + 12 + FRing.Height + 14 + Max(FBars.Height, 8);
end;

procedure TChecklistPage.ClearStats;
begin
  FRing.SetValues(0, '0%', '0 / 0 ficheiros', 0, '0 / 0 (0%)');
  FBars.SetRows(nil);
  FitProgressCard;
  ShowPlanCard;
end;

procedure TChecklistPage.ShowStats(const St: TStats);
var
  Bars: TArray<TBarRow>;
  I: Integer;
  Pct, MPct: Single;
begin
  if St.Files > 0 then Pct := St.DoneFiles / St.Files else Pct := 0;
  if St.Methods > 0 then MPct := St.DoneMethods / St.Methods else MPct := 0;
  FRing.SetValues(Pct, Format('%d%%', [Round(Pct * 100)]),
    Format('%d / %d ficheiros', [St.DoneFiles, St.Files]), MPct,
    Format('%d / %d (%d%%)', [St.DoneMethods, St.Methods, Round(MPct * 100)]));

  SetLength(Bars, Length(St.Layers));
  for I := 0 to High(St.Layers) do
  begin
    Bars[I].Name := St.Layers[I].Name;
    Bars[I].Done := St.Layers[I].Done;
    Bars[I].Total := St.Layers[I].Total;
  end;
  FBars.SetRows(Bars);
  FitProgressCard;
  ShowPlanCard;
end;

// cobertura do plano (o que ja existe, o que falta e o que sobra); escondido sem plano
procedure TChecklistPage.ShowPlanCard;
var
  Card: TCMPanel;
  S: TPlanSummary;
begin
  Card := TCMPanel(FPlanStats.Parent);
  Card.Visible := FHost.HasPlan;
  if not Card.Visible then
    Exit;
  S := FHost.PlanSummary;
  FPlanStats.SetRows([
    KV('Ficheiros', Format('%d / %d (%.0f%%)', [S.ImplementedFiles, S.PlannedFiles, S.FilesCoverage]), True),
    KV('Métodos', Format('%d / %d (%.0f%%)', [S.ImplementedMethods, S.PlannedMethods, S.MethodsCoverage]), True),
    KV('Por implementar', Format('%d fich. · %d mét.', [S.MissingFiles, S.MissingMethods])),
    KV('Extra no código', Format('%d fich. · %d mét.', [S.ExtraFiles, S.ExtraMethods]))]);
  Card.Height := 16 + 16 + 28 + 8 + FPlanStats.Height;
end;

procedure TChecklistPage.RebuildChips;
var
  St: TStats;
  L: TLayerStat;
  B: TCMButton;
begin
  while FChips.ChildrenCount > 0 do
    FChips.Children[0].Free;
  if FHost.CurrentScan <> nil then
  begin
    St := ComputeStats(FHost.CurrentScan, FHost.CurrentState);
    for L in St.Layers do
    begin
      B := TCMButton.Create(FChips);
      B.Parent := FChips;
      B.Height := 28;
      B.Text := L.Name;
      B.Active := FList.LayerActive(L.Name);
      B.OnClick := ChipClick;
    end;
  end;
  FChips.Relayout;
  FitChipsCard(nil);
end;

// o cartao dos filtros acompanha as linhas de "chips" (que quebram conforme a largura)
procedure TChecklistPage.FitChipsCard(Sender: TObject);
begin
  TCMPanel(FChips.Parent).Height := 16 + 16 + 26 + 12 + Max(FChips.Height, 8);
end;

procedure TChecklistPage.ChipClick(Sender: TObject);
var
  B: TCMButton;
begin
  B := TCMButton(Sender);
  FList.ToggleLayer(B.Text);
  B.Active := FList.LayerActive(B.Text);
end;

{ ---------------------------------------------------------------- notas }

procedure TChecklistPage.EditNote(AUnit: TUnitInfo);
var
  S: TUnitState;
begin
  FNoteUnit := AUnit;
  FLoadingFields := True;
  try
    S := FHost.CurrentState.Find(AUnit.Path);
    if S <> nil then FNoteIn.Text := S.Note else FNoteIn.Text := '';
  finally
    FLoadingFields := False;
  end;
  FNoteLabel.Text := 'Nota · ' + AUnit.Path;
  FNotePanel.Visible := True;
  FNoteIn.Edit.SetFocus;
end;

procedure TChecklistPage.NoteChanged(Sender: TObject);
begin
  if FLoadingFields or (FNoteUnit = nil) then
    Exit;
  FHost.CurrentState.Rec(FNoteUnit.Path).Note := FNoteIn.Text;
  FHost.MarkStateDirty;
  FList.Repaint;
end;

procedure TChecklistPage.CloseNote(Sender: TObject);
begin
  FNoteUnit := nil;
  FNotePanel.Visible := False;
end;

procedure TChecklistPage.CloseNoteIfRemoved(AScan: TProjectScan);
begin
  if (FNoteUnit <> nil) and (AScan.Units.IndexOf(FNoteUnit) < 0) then
    CloseNote(nil);
end;

{ ---------------------------------------------------------------- accoes }

procedure TChecklistPage.ExpandAllClick(Sender: TObject);
begin
  FList.ExpandAll;
end;

procedure TChecklistPage.CollapseAllClick(Sender: TObject);
begin
  FList.CollapseAll;
end;

procedure TChecklistPage.ExpandMethodsClick(Sender: TObject);
begin
  FList.ExpandMethods;
end;

procedure TChecklistPage.CollapseMethodsClick(Sender: TObject);
begin
  FList.CollapseMethods;
end;

procedure TChecklistPage.ExportChecklistClick(Sender: TObject);
begin
  FHost.ExportChecklistHtml;
end;

procedure TChecklistPage.CopyMarkdownClick(Sender: TObject);
var
  Svc: IFMXClipboardService;
begin
  if FHost.CurrentScan = nil then
  begin
    FHost.Toast('Analise um projeto primeiro.');
    Exit;
  end;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Svc.SetClipboard(TValue.From<string>(FList.BuildMarkdown(FHost.CurrentProfile.Name)));
    FHost.Toast('Markdown copiado');
  end;
end;

procedure TChecklistPage.ExportProgressClick(Sender: TObject);
var
  D: TSaveDialog;
  Json: string;
begin
  if FHost.CurrentProfile = nil then
    Exit;
  D := TSaveDialog.Create(nil);
  try
    D.Filter := 'Progresso (*.json)|*.json';
    D.DefaultExt := 'json';
    D.FileName := SlugOf(FHost.CurrentProfile.Name) + '-checklist-progresso-' + FormatDateTime('yyyy-mm-dd', Now) + '.json';
    if D.Execute then
    begin
      Json := '{"version":2,"exportedAt":"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) +
        '","state":' + FHost.CurrentState.ToJSONString + '}';
      TFile.WriteAllText(D.FileName, Json, TEncoding.UTF8);
      FHost.Toast('Progresso exportado');
    end;
  finally
    D.Free;
  end;
end;

procedure TChecklistPage.ImportProgressClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Filter := 'Progresso (*.json)|*.json';
    if D.Execute then
    begin
      try
        FHost.CurrentState.LoadFromFile(D.FileName);
      except
        on E: Exception do
        begin
          FHost.Toast('Ficheiro inválido: ' + E.Message);
          Exit;
        end;
      end;
      if FHost.CurrentScan <> nil then
        MigrateMethodKeys(FHost.CurrentScan, FHost.CurrentState);
      FHost.RefreshAllLists;
      RebuildChips;
      FHost.UpdateAll;
      FHost.MarkStateDirty;
      FHost.Toast('Progresso importado');
    end;
  finally
    D.Free;
  end;
end;

procedure TChecklistPage.ResetProgressClick(Sender: TObject);
begin
  if TDialogServiceSync.MessageDialog(
    'Reiniciar o progresso, notas e prioridades de todos os ficheiros deste projeto?',
    TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0) <> mrYes then
    Exit;
  FHost.CurrentState.Clear;
  CloseNote(nil);
  FHost.RefreshAllLists;
  FHost.UpdateAll;
  FHost.MarkStateDirty;
  FHost.Toast('Progresso reiniciado');
end;

end.
