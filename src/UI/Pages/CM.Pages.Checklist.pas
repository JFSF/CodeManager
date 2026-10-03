unit CM.Pages.Checklist;

{ Pagina Checklist: ficheiros agrupados por pasta, progresso por camada, filtros, notas e
  exportar/importar/reiniciar o progresso. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.IOUtils,
  System.Rtti, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, FMX.Platform, FMX.DialogService.Sync,
  CM.Theme, CM.Controls, CM.Layouts, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.Plan, CM.GitReview, CM.SonarModel, CM.Pages.Host;

type
  TChecklistPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMTreeList;
    FRing: TCMRing;
    FBars: TCMBars;
    FSonarCard: TCMPanel;          // so aparece se o utilizador activou o SonarQube e o projecto tem chave
    FSonarInfo: TCMKeyValue;
    FSonarNote: TCMLabel;
    FGitCard: TCMPanel;            // so aparece num repositorio Git
    FGitInfo: TCMKeyValue;
    FGitShowBtn: TCMButton;
    FGitTimer: TTimer;             // adia a consulta ao git: o IDE grava varias vezes seguidas
    FStalePaths: TArray<string>;
    FPlanStats: TCMKeyValue;       // cobertura do plano; o cartao so aparece quando ha plano
    FChips: TCMChipFlow;
    FStateChips: TCMChipFlow;      // filtros por estado de revisao, com a contagem de ficheiros
    FStarBtn: TCMButton;
    FNotePanel: TCMPanel;
    FNoteLabel: TCMLabel;
    FNoteIn: TCMInput;
    FNoteUnit: TUnitInfo;
    FLoadingFields: Boolean;
    procedure Hint(const AText: string);
    procedure FitProgressCard;
    procedure ShowPlanCard;
    procedure GitTick(Sender: TObject);
    procedure SonarRefreshClick(Sender: TObject);
    procedure SonarSyncClick(Sender: TObject);
    procedure GitShowClick(Sender: TObject);
    procedure GitRefreshClick(Sender: TObject);
    procedure GitResetClick(Sender: TObject);
    procedure ShowGitCard(const AHead: string);
    procedure FitChipsCard(Sender: TObject);
    procedure FitStateCard(Sender: TObject);
    procedure RebuildStateChips(const St: TStats);
    procedure StateChipClick(Sender: TObject);
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
    // pede para ver que ficheiros revistos mudaram desde a revisao (Git); junta pedidos seguidos
    procedure RequestGitRefresh;
    // mostra (ou esconde) o cartao do SonarQube conforme a ultima consulta
    procedure ShowSonar;
    procedure RefreshGit;
    procedure CloseNote(Sender: TObject);
    // fecha a nota se o ficheiro deixou de existir na analise
    procedure CloseNoteIfRemoved(AScan: TProjectScan);
    property List: TCMTreeList read FList;
    property Search: TCMInput read FSearch;
    property NoteIn: TCMInput read FNoteIn;
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
  TCMLabel.Make(Card, Tr('Progresso'), 15, True).Align := TAlignLayout.Top;
  FRing := TCMRing.Create(Self);
  FRing.Parent := Card;
  FRing.Align := TAlignLayout.Top;
  FRing.Margins.Top := 12;
  FBars := TCMBars.Create(Self);
  FBars.Parent := Card;
  FBars.Align := TAlignLayout.Top;
  FBars.Margins.Top := 14;

  Card := SideCard(Self, Side, 120);
  TCMLabel.Make(Card, Tr('Estado da revisão'), 15, True).Align := TAlignLayout.Top;
  FStateChips := TCMChipFlow.Create(Self);
  FStateChips.Parent := Card;
  FStateChips.Align := TAlignLayout.Top;
  FStateChips.Margins.Top := 12;
  FStateChips.OnRelayout := FitStateCard;

  FSonarCard := SideCard(Self, Side, 220);
  FSonarCard.Visible := False;
  TCMLabel.Make(FSonarCard, 'SonarQube', 15, True).Align := TAlignLayout.Top;
  FSonarInfo := TCMKeyValue.Create(Self);
  FSonarInfo.Parent := FSonarCard;
  FSonarInfo.Align := TAlignLayout.Top;
  FSonarInfo.Margins.Top := 8;
  FSonarNote := TCMLabel.Make(FSonarCard, '', 12, False, lcDim, False);
  FSonarNote.Align := TAlignLayout.Top;
  FSonarNote.Height := 0;
  Row := NewButtonRow(Self, FSonarCard);
  Row.Margins.Top := 10;
  TCMButton.Make(Row, Tr('Atualizar'), icRefresh, bkSecondary, SonarRefreshClick);
  TCMButton.Make(Row, Tr('Sincronizar S'), icCheck, bkSecondary, SonarSyncClick);

  FGitCard := SideCard(Self, Side, 200);
  FGitCard.Visible := False;
  TCMLabel.Make(FGitCard, 'Git', 15, True).Align := TAlignLayout.Top;
  FGitInfo := TCMKeyValue.Create(Self);
  FGitInfo.Parent := FGitCard;
  FGitInfo.Align := TAlignLayout.Top;
  FGitInfo.Margins.Top := 8;
  Row := NewButtonRow(Self, FGitCard);
  Row.Margins.Top := 10;
  FGitShowBtn := TCMButton.Make(Row, Tr('Só alterados'), icChecklist, bkSecondary, GitShowClick);
  TCMButton.Make(Row, Tr('Atualizar'), icRefresh, bkSecondary, GitRefreshClick);
  Row := NewButtonRow(Self, FGitCard);
  TCMButton.Make(Row, Tr('Voltar a «por rever»'), icRefresh, bkSecondary, GitResetClick);
  FGitTimer := TTimer.Create(Self);
  FGitTimer.Enabled := False;
  FGitTimer.Interval := 900;
  FGitTimer.OnTimer := GitTick;

  Card := SideCard(Self, Side, 200);
  Card.Visible := False;
  TCMLabel.Make(Card, Tr('Plano'), 15, True).Align := TAlignLayout.Top;
  FPlanStats := TCMKeyValue.Create(Self);
  FPlanStats.Parent := Card;
  FPlanStats.Align := TAlignLayout.Top;
  FPlanStats.Margins.Top := 8;

  Card := SideCard(Self, Side, 120);
  TCMLabel.Make(Card, Tr('Filtrar por camada'), 15, True).Align := TAlignLayout.Top;
  FChips := TCMChipFlow.Create(Self);
  FChips.Parent := Card;
  FChips.Align := TAlignLayout.Top;
  FChips.Margins.Top := 12;
  FChips.OnRelayout := FitChipsCard;

  Card := SideCard(Self, Side, 300);
  TCMLabel.Make(Card, Tr('Ações'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('Expandir tudo'), icChevronDown, bkSecondary, ExpandAllClick);
  TCMButton.Make(Row, Tr('Colapsar tudo'), icChevronRight, bkSecondary, CollapseAllClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Abrir métodos'), icChevronDown, bkSecondary, ExpandMethodsClick);
  TCMButton.Make(Row, Tr('Fechar métodos'), icChevronRight, bkSecondary, CollapseMethodsClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Markdown'), icCopy, bkSecondary, CopyMarkdownClick);
  TCMButton.Make(Row, Tr('Exportar HTML'), icExport, bkPrimary, ExportChecklistClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Exportar'), icDownload, bkSecondary, ExportProgressClick);
  TCMButton.Make(Row, Tr('Importar'), icUpload, bkSecondary, ImportProgressClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Reiniciar progresso'), icRefresh, bkDanger, ResetProgressClick);

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
  CloseBtn := TCMButton.MakeIcon(FNotePanel, icClose, CloseNote, Tr('Fechar nota'));
  CloseBtn.Align := TAlignLayout.Right;
  CloseBtn.Margins.Left := 8;
  FNoteLabel := TCMLabel.Make(FNotePanel, '', 12, True, lcDim, True);
  FNoteLabel.Align := TAlignLayout.Top;
  FNoteLabel.Height := 22;
  FNoteIn := TCMInput.Create(Self);
  FNoteIn.Parent := FNotePanel;
  FNoteIn.Align := TAlignLayout.Client;
  FNoteIn.Placeholder := Tr('Nota sobre este ficheiro…');
  FNoteIn.OnChangeText := NoteChanged;

  FList := TCMTreeList.Create(Self);
  FList.Parent := Holder;
  FList.Align := TAlignLayout.Client;
  FList.Mode := lmChecklist;
  FList.OnChanged := ListChanged;
  FList.OnEditNote := EditNote;
  FList.OnHint := Hint;
  FList.EmptyText := Tr('Analise um projeto para ver a checklist.');

  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := Tr('Filtrar por nome ou pasta…   ( / )');
  FSearch.OnChangeText := SearchChanged;

  FStarBtn := TCMButton.Make(Bar, Tr('Só prioritários'), icStar, bkSecondary, StarOnlyClick);
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
  FRing.SetValues(0, '0%', Tr('0 / 0 ficheiros'), 0, '0 / 0 (0%)');
  FBars.SetRows(nil);
  FitProgressCard;
  RebuildStateChips(Default(TStats));
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
    Format(Tr('%d / %d ficheiros'), [St.DoneFiles, St.Files]), MPct,
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
  RebuildStateChips(St);
  ShowPlanCard;
  ShowSonar;
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
    KV(Tr('Ficheiros'), Format('%d / %d (%.0f%%)', [S.ImplementedFiles, S.PlannedFiles, S.FilesCoverage]), True),
    KV(Tr('Métodos'), Format('%d / %d (%.0f%%)', [S.ImplementedMethods, S.PlannedMethods, S.MethodsCoverage]), True),
    KV(Tr('Por implementar'), Format(Tr('%d fich. · %d mét.'), [S.MissingFiles, S.MissingMethods])),
    KV(Tr('Extra no código'), Format(Tr('%d fich. · %d mét.'), [S.ExtraFiles, S.ExtraMethods]))]);
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

// os quatro estados como filtros; a etiqueta leva quantos ficheiros estao em cada um
procedure TChecklistPage.RebuildStateChips(const St: TStats);
var
  S: TReviewState;
  B: TCMButton;
begin
  while FStateChips.ChildrenCount > 0 do
    FStateChips.Children[0].Free;
  for S := Low(TReviewState) to High(TReviewState) do
  begin
    B := TCMButton.Create(FStateChips);
    B.Parent := FStateChips;
    B.Height := 28;
    B.Text := Format('%s · %d', [ReviewText(S), St.FilesByReview[S]]);
    B.Tag := Ord(S);
    B.Active := FList.ReviewStateActive(S);
    B.OnClick := StateChipClick;
  end;
  FStateChips.Relayout;
  FitStateCard(nil);
end;

procedure TChecklistPage.FitStateCard(Sender: TObject);
begin
  TCMPanel(FStateChips.Parent).Height := 16 + 16 + 26 + 12 + Max(FStateChips.Height, 8);
end;

procedure TChecklistPage.StateChipClick(Sender: TObject);
var
  B: TCMButton;
begin
  B := TCMButton(Sender);
  FList.ToggleReviewState(TReviewState(B.Tag));
  B.Active := FList.ReviewStateActive(TReviewState(B.Tag));
end;

// o SonarQube e opcional: o cartao so existe se o utilizador o activou e este projecto tem chave
procedure TChecklistPage.ShowSonar;
var
  Snap: TSonarSnapshot;
  Profile: TProjectProfile;
  Gate, Msg: string;
  WithIssues: Integer;
  Info: TSonarFile;
  U: TUnitInfo;
begin
  Profile := FHost.CurrentProfile;
  FSonarCard.Visible := FHost.AppSettings.SonarEnabled and (Profile <> nil) and (Trim(Profile.SonarKey) <> '');
  if not FSonarCard.Visible then
    Exit;
  Snap := FHost.CurrentSonar;
  Msg := FHost.SonarMessage;
  if Snap = nil then
  begin
    FSonarInfo.SetRows([KV(Tr('Servidor'), IfThen(FHost.SonarBusy, Tr('a consultar…'), Tr('sem dados')))]);
  end
  else
  begin
    WithIssues := 0;
    if FHost.CurrentScan <> nil then
      for U in FHost.CurrentScan.Units do
        if Snap.Find(U.Path, Info) and (Info.Issues > 0) then
          Inc(WithIssues);
    if Snap.GateStatus = 'OK' then Gate := Tr('aprovada')
    else if Snap.GateStatus = 'ERROR' then Gate := Tr('reprovada')
    else if Snap.GateStatus = 'WARN' then Gate := Tr('com avisos')
    else if Snap.GateStatus = 'NONE' then Gate := Tr('sem gate')
    else Gate := Tr('desconhecida');
    FSonarInfo.SetRows([
      KV(Tr('Quality gate'), Gate, Snap.GateStatus = 'OK'),
      KV(Tr('Problemas abertos'), IntToStr(Snap.TotalIssues)),
      KV(Tr('Ficheiros com problemas'), IntToStr(WithIssues)),
      KV(Tr('Atualizado'), FormatDateTime('hh:nn', Snap.FetchedAt))]);
  end;
  // erro ou estado numa linha de texto por baixo (so quando ha o que dizer)
  if Snap = nil then
    FSonarNote.Text := WrapText(Msg, sLineBreak, [' '], 38)       // o rotulo nao quebra linhas sozinho
  else if Snap.FileCount = 0 then
    // o projecto existe mas o servidor nao tem ficheiros analisados: "0 problemas" enganaria
    FSonarNote.Text := WrapText(Tr('O servidor ainda não tem ficheiros analisados para este projeto (sem análises, ') +
      Tr('ou o SonarQube não analisa Delphi sem um plugin).'), sLineBreak, [' '], 38)
  else
    FSonarNote.Text := '';
  if FSonarNote.Text = '' then
    FSonarNote.Height := 0
  else
    FSonarNote.Height := 17 * (Length(FSonarNote.Text.Split([sLineBreak])) ) + 6;
  FSonarCard.Height := 16 + 16 + 28 + 8 + FSonarInfo.Height + FSonarNote.Height + 10 + 36;
end;

procedure TChecklistPage.SonarRefreshClick(Sender: TObject);
begin
  FHost.RequestSonarRefresh;
end;

// "S" nos ficheiros que o Sonar analisou sem problemas; tira-o aos que tem problemas abertos
procedure TChecklistPage.SonarSyncClick(Sender: TObject);
var
  R: TSonarSync;
begin
  if FHost.CurrentSonar = nil then
  begin
    FHost.Toast(Tr('Ainda não há dados do SonarQube. Usa «Atualizar».'));
    Exit;
  end;
  if TDialogServiceSync.MessageDialog(
    Tr('Marcar «S» nos ficheiros que o SonarQube analisou sem problemas abertos e tirá-lo aos que têm problemas? ') +
    Tr('Os ficheiros que o SonarQube não conhece ficam como estão.'),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0) <> mrYes then
    Exit;
  R := SyncSonarFlags(FHost.CurrentScan, FHost.CurrentState, FHost.CurrentSonar);
  FHost.RefreshAllLists;
  FHost.UpdateAll;
  FHost.MarkStateDirty;
  FHost.Toast(Format(Tr('Sonar: %d ficheiros marcados, %d desmarcados'), [R.Marked, R.Cleared]));
end;

procedure TChecklistPage.RequestGitRefresh;
begin
  FGitTimer.Enabled := False;
  FGitTimer.Enabled := True;
end;

procedure TChecklistPage.GitTick(Sender: TObject);
begin
  FGitTimer.Enabled := False;
  RefreshGit;
end;

procedure TChecklistPage.RefreshGit;
var
  Scan: TProjectScan;
  R: TGitReviewResult;
begin
  FGitTimer.Enabled := False;
  Scan := FHost.CurrentScan;
  if (Scan = nil) or (Scan.Root = '') then
  begin
    FList.SetGit('', '', nil);
    FStalePaths := nil;
    ShowGitCard('');
    Exit;
  end;
  R := FindStaleReviews(Scan.Root, Scan, FHost.CurrentState);
  try
    FList.SetGit(Scan.Root, R.Head, R.Stale);
    FStalePaths := R.Stale.ToArray;
    if R.Backfilled > 0 then
      FHost.MarkStateDirty;          // as revisoes antigas ganharam o commit
    ShowGitCard(R.Head);
  finally
    R.Stale.Free;
  end;
end;

// o cartao so existe num repositorio; mostra o commit actual e quantos ficheiros revistos mudaram
procedure TChecklistPage.ShowGitCard(const AHead: string);
begin
  FGitCard.Visible := AHead <> '';
  if AHead = '' then
  begin
    if FList.StaleOnly then
    begin
      FList.SetStaleOnly(False);
      FGitShowBtn.Active := False;
    end;
    Exit;
  end;
  FGitInfo.SetRows([
    KV(Tr('Commit atual'), Copy(AHead, 1, 8)),
    KV(Tr('Mudaram desde a revisão'), IntToStr(Length(FStalePaths)), Length(FStalePaths) > 0)]);
  FGitCard.Height := 16 + 16 + 28 + 8 + FGitInfo.Height + 10 + 36 + 8 + 36;
end;

procedure TChecklistPage.GitShowClick(Sender: TObject);
begin
  FList.SetStaleOnly(not FList.StaleOnly);
  FGitShowBtn.Active := FList.StaleOnly;
end;

procedure TChecklistPage.GitRefreshClick(Sender: TObject);
begin
  RefreshGit;
  FHost.Toast(Format(Tr('Git: %d ficheiros revistos mudaram desde a revisão'), [Length(FStalePaths)]));
end;

procedure TChecklistPage.GitResetClick(Sender: TObject);
var
  Path: string;
  S: TUnitState;
begin
  if Length(FStalePaths) = 0 then
  begin
    FHost.Toast(Tr('Nenhum ficheiro revisto mudou desde a revisão'));
    Exit;
  end;
  if TDialogServiceSync.MessageDialog(
    Format(Tr('Voltar a «por rever» os %d ficheiros que mudaram desde a revisão? ') +
      Tr('Ficam sem estado de revisão; Compila, Sonar, prioridade e notas mantêm-se.'), [Length(FStalePaths)]),
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0) <> mrYes then
    Exit;
  for Path in FStalePaths do
  begin
    S := FHost.CurrentState.Find(Path);
    if S <> nil then
      ResetReview(S);
  end;
  FHost.RefreshAllLists;
  FHost.UpdateAll;
  FHost.MarkStateDirty;
  RefreshGit;
  FHost.Toast(Tr('Ficheiros repostos como por rever'));
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
  FNoteLabel.Text := Tr('Nota · ') + AUnit.Path;
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
    FHost.Toast(Tr('Analise um projeto primeiro.'));
    Exit;
  end;
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Svc.SetClipboard(TValue.From<string>(FList.BuildMarkdown(FHost.CurrentProfile.Name)));
    FHost.Toast(Tr('Markdown copiado'));
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
    D.Filter := Tr('Progresso (*.json)|*.json');
    D.DefaultExt := 'json';
    D.FileName := SlugOf(FHost.CurrentProfile.Name) + Tr('-checklist-progresso-') + FormatDateTime('yyyy-mm-dd', Now) + '.json';
    if D.Execute then
    begin
      Json := '{"version":2,"exportedAt":"' + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now) +
        '","state":' + FHost.CurrentState.ToJSONString + '}';
      TFile.WriteAllText(D.FileName, Json, TEncoding.UTF8);
      FHost.Toast(Tr('Progresso exportado'));
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
    D.Filter := Tr('Progresso (*.json)|*.json');
    if D.Execute then
    begin
      try
        FHost.CurrentState.LoadFromFile(D.FileName);
      except
        on E: Exception do
        begin
          FHost.Toast(Tr('Ficheiro inválido: ') + E.Message);
          Exit;
        end;
      end;
      if FHost.CurrentScan <> nil then
        MigrateMethodKeys(FHost.CurrentScan, FHost.CurrentState);
      FHost.RefreshAllLists;
      RebuildChips;
      FHost.UpdateAll;
      FHost.MarkStateDirty;
      FHost.Toast(Tr('Progresso importado'));
    end;
  finally
    D.Free;
  end;
end;

procedure TChecklistPage.ResetProgressClick(Sender: TObject);
begin
  if TDialogServiceSync.MessageDialog(
    Tr('Reiniciar o progresso, notas e prioridades de todos os ficheiros deste projeto?'),
    TMsgDlgType.mtWarning, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0) <> mrYes then
    Exit;
  FHost.CurrentState.Clear;
  CloseNote(nil);
  FHost.RefreshAllLists;
  FHost.UpdateAll;
  FHost.MarkStateDirty;
  FHost.Toast(Tr('Progresso reiniciado'));
end;

end.
