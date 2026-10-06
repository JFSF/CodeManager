unit CM.Pages.Project;

{ Pagina Projeto: lista de projectos, configuracao, analise (numa thread), modo "acompanhar
  alteracoes" (vigia da pasta) e exportacao das paginas HTML. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.IOUtils,
  System.Generics.Collections, System.Threading, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, FMX.DialogService.Sync,
  Winapi.Windows, Winapi.ShellAPI,
  CM.Theme, CM.Controls, CM.Layouts, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.Html,
  CM.Watcher, CM.Plan, CM.Sonar, CM.Secrets, CM.GitHub, CM.Pages.Host;

type
  TProjectPage = class(TCMControl)
  private
    FHost: IPageHost;
    FLoadingFields: Boolean;
    FScanToken: Integer;
    FScanBusy: Boolean;
    FWatcher: TFolderWatcher;
    FWatchTimer: TTimer;

    FProjList: TCMList;
    FStepsBox: TCMControl;
    FNameIn, FRootIn, FOutIn, FPlanIn, FExcludeIn, FRepoIn: TCMInput;
    FOpenSwitch: TCMSwitch;
    FWatchSwitch: TCMSwitch;
    FBtnSync, FBtnScan, FBtnExportMap, FBtnExportCk, FBtnFinalize, FBtnRemove: TCMButton;
    FProgress: TCMProgress;
    FStatus: TCMLabel;
    FSummary: TCMKeyValue;
    // SonarQube (opcional, por utilizador): o servidor e o token sao dele; a chave e de cada projecto
    FSonarSwitch: TCMSwitch;
    FSonarUrlIn, FSonarTokenIn, FSonarKeyIn: TCMInput;
    FSonarStatus: TCMLabel;
    FSonarTestJob: ISonarJob;
    FSonarTestTimer: TTimer;

    procedure SonarSwitchChanged(Sender: TObject);
    procedure SonarFieldChanged(Sender: TObject);
    procedure SonarTestClick(Sender: TObject);
    procedure SonarTestTick(Sender: TObject);
    procedure ProjListSelect(Sender: TObject);
    procedure FieldChanged(Sender: TObject);
    procedure BrowseRoot(Sender: TObject);
    procedure BrowseOut(Sender: TObject);
    procedure BrowsePlan(Sender: TObject);
    procedure OpenSwitchChanged(Sender: TObject);
    procedure NewProjectClick(Sender: TObject);
    procedure RemoveProjectClick(Sender: TObject);
    procedure ScanClick(Sender: TObject);
    procedure SyncRepoClick(Sender: TObject);
    procedure RepoChanged(Sender: TObject);
    procedure ApplyRepoLock;
    procedure SetBusy(ABusy: Boolean);
    procedure ScanProgress(AToken: Integer; const AMsg: string; ADone, ATotal: Integer);
    procedure ScanDone(AToken: Integer; AScan, APlan: TProjectScan; const AWarnings: TArray<string>;
      const AError: string);
    procedure WatcherSignal(Sender: TObject);
    procedure WatchTimerTick(Sender: TObject);
    procedure ApplyWatchChanges;
    procedure ShowScanChanges(AChanges: TList<TScanChange>);
    procedure ExportMapClick(Sender: TObject);
    procedure ExportChecklistClick(Sender: TObject);
    function EnsureReadyToExport: Boolean;
    procedure OpenFile(const APath: string);
    procedure LanguageClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    procedure RefreshProjectList;
    procedure NewProject;
    // preenche os campos com os dados do projecto
    procedure LoadFields(AProfile: TProjectProfile);
    // barra de progresso a zero e mensagem inicial
    procedure ResetStatus;
    // descarta qualquer analise ainda a decorrer e desbloqueia os botoes
    procedure CancelScan;
    // so descarta o resultado das analises a decorrer (fecho da janela)
    procedure InvalidateScans;
    // ASync: obtem de novo o repositorio do GitHub (so se o projeto tiver um); sem ele usa a cache
    procedure StartScan(ASync: Boolean = False);
    procedure StartWatch;
    procedure StopWatch;
    procedure WatchSwitchChanged(Sender: TObject);
    procedure FinalizeClick(Sender: TObject);
    procedure ClearStats;
    procedure ShowStats(const St: TStats);
    // texto e icone do botao Finalizar/Reabrir conforme o estado do projecto
    procedure UpdateFinalizeButton;
    function ExportMap(AQuiet: Boolean): Boolean;
    procedure ExportChecklist;
    // dica actual da lista de projectos (usada pelo modo de desenvolvimento)
    function ProjectsHint: string;
    property NameIn: TCMInput read FNameIn;
    property RootIn: TCMInput read FRootIn;
    property OutIn: TCMInput read FOutIn;
    property PlanIn: TCMInput read FPlanIn;
    property WatchSwitch: TCMSwitch read FWatchSwitch;
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

constructor TProjectPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Left: TCMPanel;
  Right: TCMFadeScroll;
  Card: TCMPanel;
  Row: TCMButtonRow;
  Sub: TCMLabel;
  NewBtn, LangBtn: TCMButton;
  L: TLang;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;

  FWatchTimer := TTimer.Create(Self);
  FWatchTimer.Enabled := False;
  FWatchTimer.Interval := 600;           // o IDE grava varias vezes seguidas: espera que assente
  FWatchTimer.OnTimer := WatchTimerTick;

  // coluna esquerda: lista de projectos
  Left := TCMPanel.Create(Self);
  Left.Parent := Self;
  Left.Align := TAlignLayout.Left;
  Left.Width := 340;
  Left.Margins.Right := 20;
  Left.Padding.Rect := TRectF.Create(16, 18, 16, 16);
  TCMLabel.Make(Left, Tr('Projetos'), 15, True).Align := TAlignLayout.Top;
  Sub := TCMLabel.Make(Left, Tr('Cada projeto guarda o seu progresso.'), 12, False, lcFaint);
  Sub.Align := TAlignLayout.Top;
  Sub.Margins.Bottom := 12;
  // orientacao enquanto o projecto ainda nao foi analisado (some quando ha analise)
  FStepsBox := TCMControl.Create(Self);
  FStepsBox.Parent := Left;
  FStepsBox.Align := TAlignLayout.Bottom;
  FStepsBox.Height := 92;
  Sub := TCMLabel.Make(FStepsBox, Tr('Primeiros passos'), 13, True);
  Sub.Align := TAlignLayout.Top;
  Sub.Height := 26;
  Sub := TCMLabel.Make(FStepsBox, Tr('1. Escolha a pasta do projeto e/ou o plano (.md)') + sLineBreak +
    Tr('2. Clique em «Analisar projeto»') + sLineBreak + Tr('3. Reveja no Mapa, na Checklist e no Painel'),
    12.5, False, lcDim);
  Sub.Align := TAlignLayout.Top;
  Sub.Height := 62;
  NewBtn := TCMButton.Make(Left, Tr('Novo projeto'), icPlus, bkSecondary, NewProjectClick);
  NewBtn.Align := TAlignLayout.Bottom;
  NewBtn.Height := 38;
  NewBtn.Margins.Top := 8;
  FProjList := TCMList.Create(Self);
  FProjList.Parent := Left;
  FProjList.Align := TAlignLayout.Client;
  FProjList.OnSelect := ProjListSelect;

  // coluna direita: configuracao, accoes, resumo
  Right := TCMFadeScroll.Create(Self);
  Right.Parent := Self;
  Right.Align := TAlignLayout.Client;
  Right.ShowScrollBars := False;

  // idioma da aplicacao (a escolha reconstroi a interface)
  Card := NewCard(Self, Right, 112);
  TCMLabel.Make(Card, Tr('Idioma'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  for L := Low(TLang) to High(TLang) do
  begin
    LangBtn := TCMButton.Create(Row);
    LangBtn.Parent := Row;
    LangBtn.Height := 36;
    LangBtn.Text := LangNames[L];
    LangBtn.Tag := Ord(L);
    LangBtn.Active := L = CurrentLang;
    LangBtn.OnClick := LanguageClick;
  end;

  Card := NewCard(Self, Right, 674);
  TCMLabel.Make(Card, Tr('Configuração'), 15, True).Align := TAlignLayout.Top;
  FNameIn := AddField(Self, Card, Tr('Nome do projeto'), Tr('ex.: AssisTEC'), False);
  FRootIn := AddField(Self, Card, Tr('Localização do projeto (pasta raiz a analisar)'), 'C:\Projetos\MeuProjeto', True);
  FRepoIn := AddField(Self, Card, Tr('Ou um repositório do GitHub (opcional, só leitura)'), Tr('https://github.com/utilizador/repositorio'), False);
  FOutIn := AddField(Self, Card, Tr('Pasta onde guardar as páginas HTML'), 'C:\Projetos\MeuProjeto\docs', True);
  FPlanIn := AddField(Self, Card, Tr('Documento do plano (.md) — opcional: estrutura e código previstos'),
    'C:\Projetos\MeuProjeto\docs\plano.md', True);
  FExcludeIn := AddField(Self, Card, Tr('Pastas a ignorar (separadas por vírgulas)'), ExcludedDirsText, False);
  FOpenSwitch := TCMSwitch.Create(Self);
  FOpenSwitch.Parent := Card;
  FOpenSwitch.Align := TAlignLayout.Top;
  FOpenSwitch.Margins.Top := 16;
  FOpenSwitch.Text := Tr('Abrir a página no navegador depois de exportar');
  FOpenSwitch.OnChange := OpenSwitchChanged;
  FWatchSwitch := TCMSwitch.Create(Self);
  FWatchSwitch.Parent := Card;
  FWatchSwitch.Align := TAlignLayout.Top;
  FWatchSwitch.Margins.Top := 6;
  FWatchSwitch.Text := Tr('Acompanhar alterações na pasta do projeto');
  FWatchSwitch.OnChange := WatchSwitchChanged;
  Sub := TCMLabel.Make(Card, Tr('Em branco = predefinidas. Analisa .pas, .dpr e .dpk. Com pasta e plano, o Mapa mostra o que falta e o que sobra.'),
    11.5, False, lcFaint, True);
  Sub.Align := TAlignLayout.Top;
  Sub.Wrap := True;                  // em alemao a frase ocupa duas linhas
  Sub.Height := 34;
  Sub.Margins.Top := 10;
  FNameIn.OnChangeText := FieldChanged;
  FRootIn.OnChangeText := FieldChanged;
  FRepoIn.OnChangeText := RepoChanged;
  FOutIn.OnChangeText := FieldChanged;
  FPlanIn.OnChangeText := FieldChanged;
  FExcludeIn.OnChangeText := FieldChanged;
  FRootIn.OnTrailingClick := BrowseRoot;
  FOutIn.OnTrailingClick := BrowseOut;
  FPlanIn.OnTrailingClick := BrowsePlan;

  // SonarQube: opcional. Cada utilizador decide se o usa e como; nada se liga sem ele o activar
  Card := NewCard(Self, Right, 486);
  TCMLabel.Make(Card, Tr('SonarQube (opcional)'), 15, True).Align := TAlignLayout.Top;
  Sub := TCMLabel.Make(Card, Tr('Cada utilizador decide se o usa. O endereço e o token ficam nos teus dados;') + sLineBreak +
    Tr('o token é cifrado e só funciona neste computador e nesta conta do Windows.'), 11.5, False, lcFaint);
  Sub.Align := TAlignLayout.Top;
  Sub.Height := 36;
  Sub.Margins.Top := 4;
  FSonarSwitch := TCMSwitch.Create(Self);
  FSonarSwitch.Parent := Card;
  FSonarSwitch.Align := TAlignLayout.Top;
  FSonarSwitch.Margins.Top := 8;
  FSonarSwitch.Text := Tr('Usar o SonarQube neste computador');
  FSonarSwitch.OnChange := SonarSwitchChanged;
  FSonarUrlIn := AddField(Self, Card, Tr('Endereço do servidor'), 'http://localhost:5000', False);
  FSonarTokenIn := AddField(Self, Card, Tr('Token de utilizador'), Tr('cola aqui o token (My Account › Security)'), False);
  FSonarTokenIn.Edit.Password := True;
  FSonarKeyIn := AddField(Self, Card, Tr('Chave deste projeto no SonarQube'), Tr('ex.: CodeManager'), False);
  FSonarUrlIn.OnChangeText := SonarFieldChanged;
  FSonarTokenIn.OnChangeText := SonarFieldChanged;
  FSonarKeyIn.OnChangeText := SonarFieldChanged;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 14;
  TCMButton.Make(Row, Tr('Testar ligação'), icRefresh, bkSecondary, SonarTestClick);
  FSonarStatus := TCMLabel.Make(Card, '', 12, False, lcDim);
  FSonarStatus.Align := TAlignLayout.Top;
  FSonarStatus.Height := 38;
  FSonarStatus.Margins.Top := 8;
  FSonarTestTimer := TTimer.Create(Self);
  FSonarTestTimer.Enabled := False;
  FSonarTestTimer.Interval := 200;
  FSonarTestTimer.OnTimer := SonarTestTick;

  Card := NewCard(Self, Right, 192);
  TCMLabel.Make(Card, Tr('Ações'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Wrap := True;
  Row.Margins.Top := 14;
  FBtnScan := TCMButton.Make(Row, Tr('Analisar projeto'), icRefresh, bkPrimary, ScanClick);
  FBtnSync := TCMButton.Make(Row, Tr('Atualizar do GitHub'), icDownload, bkSecondary, SyncRepoClick);
  FBtnExportMap := TCMButton.Make(Row, Tr('Exportar mapa (HTML)'), icExport, bkSecondary, ExportMapClick);
  FBtnExportCk := TCMButton.Make(Row, Tr('Exportar checklist (HTML)'), icExport, bkSecondary, ExportChecklistClick);
  FBtnFinalize := TCMButton.Make(Row, Tr('Fechar projeto como finalizado'), icFlag, bkSecondary, FinalizeClick);
  FBtnRemove := TCMButton.Make(Row, Tr('Remover projeto'), icTrash, bkDanger, RemoveProjectClick);
  FProgress := TCMProgress.Create(Self);
  FProgress.Parent := Card;
  FProgress.Align := TAlignLayout.Top;
  FProgress.Margins.Top := 10;
  FStatus := TCMLabel.Make(Card, Tr('Escolha a pasta do projeto e clique em «Analisar projeto».'), 12.5, False, lcDim);
  FStatus.Align := TAlignLayout.Top;
  FStatus.Margins.Top := 10;

  Card := NewCard(Self, Right, 226);
  TCMLabel.Make(Card, Tr('Resumo da análise'), 15, True).Align := TAlignLayout.Top;
  FSummary := TCMKeyValue.Create(Self);
  FSummary.Parent := Card;
  FSummary.Align := TAlignLayout.Top;
  FSummary.Margins.Top := 10;
end;

destructor TProjectPage.Destroy;
begin
  FSonarTestJob := nil;          // a thread acaba sozinha
  StopWatch;
  inherited;
end;

function TProjectPage.ProjectsHint: string;
begin
  Result := FProjList.Hint;
end;

procedure TProjectPage.ApplyTheme;
begin
  FNameIn.ApplyTheme;
  FRootIn.ApplyTheme;
  FRepoIn.ApplyTheme;
  FOutIn.ApplyTheme;
  FPlanIn.ApplyTheme;
  FExcludeIn.ApplyTheme;
end;

{ ---------------------------------------------------------------- projectos }

procedure TProjectPage.RefreshProjectList;
var
  Items: TArray<TListEntry>;
  I, Sel: Integer;
  P: TProjectProfile;
  Projects: TObjectList<TProjectProfile>;
begin
  Projects := FHost.AppSettings.Projects;
  SetLength(Items, Projects.Count);
  Sel := -1;
  for I := 0 to Projects.Count - 1 do
  begin
    P := Projects[I];
    if Trim(P.Name) <> '' then Items[I].Title := P.Name else Items[I].Title := Tr('(sem nome)');
    if P.RootPath <> '' then Items[I].Sub := P.RootPath else Items[I].Sub := Tr('(sem pasta)');
    if P.Finalized then Items[I].Badge := Tr('FINALIZADO') else Items[I].Badge := '';
    if P = FHost.CurrentProfile then
      Sel := I;
  end;
  FProjList.SetItems(Items, Sel);
end;

procedure TProjectPage.NewProjectClick(Sender: TObject);
begin
  NewProject;
end;

procedure TProjectPage.NewProject;
var
  P: TProjectProfile;
begin
  P := FHost.AppSettings.AddProject;
  P.Name := Tr('Novo projeto');
  FHost.AppSettings.ActiveProjectId := P.Id;
  FHost.MarkSettingsDirty;
  FHost.SelectProject(P);
  FHost.ShowPage(pgProject);
  FNameIn.Edit.SetFocus;
  FNameIn.Edit.SelectAll;
end;

procedure TProjectPage.LoadFields(AProfile: TProjectProfile);
begin
  FLoadingFields := True;
  try
    FNameIn.Text := AProfile.Name;
    FRootIn.Text := AProfile.RootPath;
    FRepoIn.Text := AProfile.RepoUrl;
    FOutIn.Text := AProfile.OutputFolder;
    FPlanIn.Text := AProfile.PlanPath;
    FExcludeIn.Text := AProfile.ExcludeDirs;
    FOpenSwitch.Checked := FHost.AppSettings.OpenAfterExport;
    FWatchSwitch.Checked := AProfile.Watch;
    FSonarSwitch.Checked := FHost.AppSettings.SonarEnabled;
    FSonarUrlIn.Text := FHost.AppSettings.SonarUrl;
    FSonarTokenIn.Text := UnprotectText(FHost.AppSettings.SonarTokenCipher);
    FSonarKeyIn.Text := AProfile.SonarKey;
    FSonarStatus.Text := '';
  finally
    FLoadingFields := False;
  end;
  ApplyRepoLock;
end;

procedure TProjectPage.ResetStatus;
begin
  FProgress.Value := 0;
  FStatus.ColorRole := lcDim;
  FStatus.Text := Tr('Escolha a pasta do projeto e clique em «Analisar projeto».');
end;

procedure TProjectPage.ProjListSelect(Sender: TObject);
var
  I: Integer;
  Projects: TObjectList<TProjectProfile>;
begin
  Projects := FHost.AppSettings.Projects;
  I := FProjList.ItemIndex;
  if (I >= 0) and (I < Projects.Count) and (Projects[I] <> FHost.CurrentProfile) then
    FHost.SelectProject(Projects[I]);
end;

procedure TProjectPage.SonarSwitchChanged(Sender: TObject);
begin
  if FLoadingFields then
    Exit;
  FHost.AppSettings.SonarEnabled := FSonarSwitch.Checked;
  FHost.MarkSettingsDirty;
  FHost.RequestSonarRefresh;
end;

procedure TProjectPage.SonarFieldChanged(Sender: TObject);
begin
  if FLoadingFields then
    Exit;
  FHost.AppSettings.SonarUrl := Trim(FSonarUrlIn.Text);
  FHost.AppSettings.SonarTokenCipher := ProtectText(Trim(FSonarTokenIn.Text));
  if FHost.CurrentProfile <> nil then
    FHost.CurrentProfile.SonarKey := Trim(FSonarKeyIn.Text);
  FHost.MarkSettingsDirty;
end;

// testa com o que esta nos campos (mesmo que ainda nao esteja activado), em segundo plano
procedure TProjectPage.SonarTestClick(Sender: TObject);
var
  Config: TSonarConfig;
begin
  Config.Url := Trim(FSonarUrlIn.Text);
  Config.Token := Trim(FSonarTokenIn.Text);
  Config.ProjectKey := Trim(FSonarKeyIn.Text);
  FSonarStatus.ColorRole := lcDim;
  FSonarStatus.Text := Tr('A testar…');
  FSonarTestJob := StartSonarTest(Config);
  FSonarTestTimer.Enabled := True;
end;

procedure TProjectPage.SonarTestTick(Sender: TObject);
var
  Job: ISonarJob;
begin
  if FSonarTestJob = nil then
  begin
    FSonarTestTimer.Enabled := False;
    Exit;
  end;
  if not FSonarTestJob.Done then
    Exit;
  FSonarTestTimer.Enabled := False;
  Job := FSonarTestJob;
  FSonarTestJob := nil;
  if Job.Success then
    FSonarStatus.ColorRole := lcAccentStrong
  else
    FSonarStatus.ColorRole := lcDanger;
  FSonarStatus.Text := WrapText(Job.Message, sLineBreak, [' '], 90);       // o rotulo nao quebra linhas sozinho
  FSonarStatus.Height := 18 * Length(FSonarStatus.Text.Split([sLineBreak])) + 4;
  if Job.Success and FHost.AppSettings.SonarEnabled then
    FHost.RequestSonarRefresh;
end;

// com um repositorio do GitHub a pasta de analise e a cache: o campo da pasta passa a so de leitura
procedure TProjectPage.ApplyRepoLock;
var
  Ref: TRepoRef;
  Err: string;
begin
  FRootIn.Edit.ReadOnly := (Trim(FRepoIn.Text) <> '') and ParseRepoUrl(Trim(FRepoIn.Text), Ref, Err);
  FBtnSync.Enabled := not FScanBusy;
end;

procedure TProjectPage.RepoChanged(Sender: TObject);
var
  Ref: TRepoRef;
  Err: string;
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if FLoadingFields or (Profile = nil) then
    Exit;
  if (Trim(FRepoIn.Text) <> '') and ParseRepoUrl(Trim(FRepoIn.Text), Ref, Err) then
  begin
    FRootIn.Edit.ReadOnly := False;
    FRootIn.Text := RepoWorkDir(Profile.Id, Ref);
    if Trim(FOutIn.Text) = '' then
      FOutIn.Text := TPath.Combine(TPath.Combine(AppDataDir, 'html'), Profile.Id);
    if Trim(FNameIn.Text) = '' then
      FNameIn.Text := Ref.Name;
  end
  else if Trim(FRepoIn.Text) = '' then
    FRootIn.Edit.ReadOnly := False;
  FieldChanged(Sender);
  ApplyRepoLock;
end;

procedure TProjectPage.FieldChanged(Sender: TObject);
var
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if FLoadingFields or (Profile = nil) then
    Exit;
  Profile.Name := Trim(FNameIn.Text);
  Profile.RootPath := Trim(FRootIn.Text);
  Profile.RepoUrl := Trim(FRepoIn.Text);
  Profile.OutputFolder := Trim(FOutIn.Text);
  Profile.PlanPath := Trim(FPlanIn.Text);
  Profile.ExcludeDirs := Trim(FExcludeIn.Text);
  FHost.MarkSettingsDirty;
  RefreshProjectList;
  FHost.UpdateHeader;
end;

procedure TProjectPage.BrowseRoot(Sender: TObject);
var
  Dir: string;
begin
  Dir := FRootIn.Text;
  if not TDirectory.Exists(Dir) then
    Dir := '';
  if SelectDirectory(Tr('Escolha a pasta raiz do projeto a analisar'), '', Dir) then
  begin
    FRootIn.Text := Dir;
    if Trim(FNameIn.Text) = '' then
      FNameIn.Text := TPath.GetFileName(ExcludeTrailingPathDelimiter(Dir));
    if Trim(FOutIn.Text) = '' then
      FOutIn.Text := TPath.Combine(Dir, 'docs');
    StartScan;
  end;
end;

procedure TProjectPage.BrowseOut(Sender: TObject);
var
  Dir: string;
begin
  Dir := FOutIn.Text;
  if not TDirectory.Exists(Dir) then
    Dir := FRootIn.Text;
  if SelectDirectory(Tr('Escolha a pasta onde guardar as páginas HTML'), '', Dir) then
    FOutIn.Text := Dir;
end;

procedure TProjectPage.BrowsePlan(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Title := Tr('Escolha o documento do plano (Markdown)');
    D.Filter := Tr('Markdown (*.md;*.markdown)|*.md;*.markdown|Todos os ficheiros (*.*)|*.*');
    if TFile.Exists(FPlanIn.Text) then
      D.FileName := FPlanIn.Text
    else if TDirectory.Exists(FRootIn.Text) then
      D.InitialDir := FRootIn.Text;
    if D.Execute then
    begin
      FPlanIn.Text := D.FileName;
      StartScan;
    end;
  finally
    D.Free;
  end;
end;

procedure TProjectPage.LanguageClick(Sender: TObject);
begin
  FHost.SetLanguage(TLang(TFmxObject(Sender).Tag));
end;

procedure TProjectPage.OpenSwitchChanged(Sender: TObject);
begin
  if FLoadingFields then
    Exit;
  FHost.AppSettings.OpenAfterExport := FOpenSwitch.Checked;
  FHost.MarkSettingsDirty;
end;

procedure TProjectPage.RemoveProjectClick(Sender: TObject);
var
  P: TProjectProfile;
  Idx: Integer;
  Settings: TAppSettings;
begin
  P := FHost.CurrentProfile;
  if P = nil then
    Exit;
  if TDialogServiceSync.MessageDialog(
    Format(Tr('Remover o projeto "%s" da lista? O progresso guardado será apagado (os ficheiros do projeto não são tocados).'),
      [P.Name]), TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
    TMsgDlgBtn.mbNo, 0) <> mrYes then
    Exit;
  Settings := FHost.AppSettings;
  Idx := Settings.Projects.IndexOf(P);
  FHost.DetachProfile;
  if P.RepoUrl <> '' then
    DeleteRepoCache(P.Id);
  Settings.RemoveProject(P);
  FHost.MarkSettingsDirty;
  if Settings.Projects.Count = 0 then
    NewProject
  else
    FHost.SelectProject(Settings.Projects[Min(Idx, Settings.Projects.Count - 1)]);
end;

procedure TProjectPage.FinalizeClick(Sender: TObject);
var
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if Profile = nil then
    Exit;
  if not Profile.Finalized then
  begin
    if TDialogServiceSync.MessageDialog(
      Tr('Fechar o projeto como finalizado? O mapa exportado passa a ter o selo "PROJETO FINALIZADO".'),
      TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbYes, 0) <> mrYes then
      Exit;
    Profile.Finalized := True;
    Profile.FinalizedAt := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  end
  else
  begin
    Profile.Finalized := False;
    Profile.FinalizedAt := '';
  end;
  FHost.MarkSettingsDirty;
  RefreshProjectList;
  FHost.UpdateHeader;
  // tal como no script original, regenera o mapa com (ou sem) o selo, se houver destino e analise
  if (FHost.CurrentScan <> nil) and (Trim(FOutIn.Text) <> '') then
    ExportMap(False)
  else if Profile.Finalized then
    FHost.Toast(Tr('Projeto finalizado'))
  else
    FHost.Toast(Tr('Projeto reaberto'));
end;

procedure TProjectPage.UpdateFinalizeButton;
var
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if (Profile <> nil) and Profile.Finalized then
  begin
    FBtnFinalize.Text := Tr('Reabrir projeto');
    FBtnFinalize.Icon := icRefresh;
  end
  else
  begin
    FBtnFinalize.Text := Tr('Fechar projeto como finalizado');
    FBtnFinalize.Icon := icFlag;
  end;
  TCMButtonRow(FBtnFinalize.Parent).Relayout;
end;

{ ---------------------------------------------------------------- modo acompanhar }

procedure TProjectPage.WatchSwitchChanged(Sender: TObject);
var
  Profile: TProjectProfile;
begin
  Profile := FHost.CurrentProfile;
  if FLoadingFields or (Profile = nil) then
    Exit;
  Profile.Watch := FWatchSwitch.Checked;
  FHost.MarkSettingsDirty;
  if Profile.Watch then
    StartWatch
  else
    StopWatch;
end;

procedure TProjectPage.StopWatch;
begin
  if FWatchTimer <> nil then
    FWatchTimer.Enabled := False;
  FreeAndNil(FWatcher);
end;

procedure TProjectPage.StartWatch;
var
  Profile: TProjectProfile;
  Scan: TProjectScan;
begin
  StopWatch;
  Profile := FHost.CurrentProfile;
  Scan := FHost.CurrentScan;
  if (Profile = nil) or not Profile.Watch or (Scan = nil) or not TDirectory.Exists(Scan.Root) then
    Exit;
  FWatcher := TFolderWatcher.Create(Scan.Root, WatcherSignal);
  FStatus.ColorRole := lcDim;
  FStatus.Text := FStatus.Text + Tr('  ·  a acompanhar alterações');
end;

procedure TProjectPage.WatcherSignal(Sender: TObject);
begin
  FWatchTimer.Enabled := False;      // reinicia a espera
  FWatchTimer.Enabled := True;
end;

procedure TProjectPage.WatchTimerTick(Sender: TObject);
begin
  FWatchTimer.Enabled := False;
  if FHost.ShuttingDown or (FWatcher = nil) then
    Exit;
  // uma analise completa corre noutra thread e usa as mesmas regex: espera que acabe
  if FScanBusy then
  begin
    FWatchTimer.Enabled := True;
    Exit;
  end;
  ApplyWatchChanges;
end;

procedure TProjectPage.ApplyWatchChanges;
var
  Paths: TArray<string>;
  Overflow, Reconcile: Boolean;
  Path: string;
  Changes: TList<TScanChange>;
  Change: TScanChange;
  Scan: TProjectScan;
begin
  Scan := FHost.CurrentScan;
  if (FWatcher = nil) or (Scan = nil) then
    Exit;
  FWatcher.TakeChanges(Paths, Overflow);
  Reconcile := Overflow;
  Changes := TList<TScanChange>.Create;
  try
    for Path in Paths do
    begin
      if IsPathExcluded(Scan, Path) then
        Continue;
      if IsSourceFile(Path) then
      begin
        if RescanFile(Scan, Path, Change) <> rcNone then
          Changes.Add(Change);
      end
      // sem extensao ou pasta existente: pasta criada, renomeada ou apagada
      else if (TPath.GetExtension(Path) = '') or
              TDirectory.Exists(TPath.Combine(Scan.Root, Path.Replace('/', PathDelim))) then
        Reconcile := True;
    end;
    if Reconcile then
      ReconcileScan(Scan, Changes);
    if Changes.Count > 0 then
      ShowScanChanges(Changes);
  finally
    Changes.Free;
  end;
end;

// reflecte nas vistas o que mudou na analise, sem perder scroll nem pastas abertas
procedure TProjectPage.ShowScanChanges(AChanges: TList<TScanChange>);
var
  C: TScanChange;
  Keys: TList<string>;
  Name, Msg: string;
  Added, Changed, Removed: Integer;
begin
  Added := 0;
  Changed := 0;
  Removed := 0;
  Keys := TList<string>.Create;
  try
    for C in AChanges do
    begin
      case C.Kind of
        rcAdded: Inc(Added);
        rcChanged: Inc(Changed);
        rcRemoved: Inc(Removed);
      end;
      if C.Kind in [rcAdded, rcChanged] then
      begin
        Keys.Add(TCMTreeList.FlashKeyFile(C.Path));
        for Name in C.NewMethods do
          Keys.Add(TCMTreeList.FlashKeyMethod(C.Path, Name));
      end;
    end;
    FHost.ScanChangesApplied(Keys.ToArray);
  finally
    Keys.Free;
  end;

  if AChanges.Count = 1 then
  begin
    C := AChanges[0];
    Name := C.Path.Substring(C.Path.LastIndexOf('/') + 1);
    case C.Kind of
      rcAdded: Msg := Format(Tr('novo: %s (%d métodos)'), [Name, Length(C.NewMethods)]);
      rcRemoved: Msg := Tr('removido: ') + Name;
    else
      if Length(C.NewMethods) > 0 then
        Msg := Format(Tr('%s (%d métodos novos ou alterados)'), [Name, Length(C.NewMethods)])
      else
        Msg := Name + Tr(' atualizado');
    end;
  end
  else
    Msg := Format(Tr('%d ficheiros (%d novos, %d alterados, %d removidos)'), [AChanges.Count, Added, Changed, Removed]);
  FStatus.ColorRole := lcDim;
  FStatus.Text := Format(Tr('Acompanhar · %s · %s'), [FormatDateTime('hh:nn:ss', Now), Msg]);
  FHost.Toast(Tr('Atualizado: ') + Msg);
end;

{ ---------------------------------------------------------------- analise }

procedure TProjectPage.ScanClick(Sender: TObject);
begin
  StartScan;
end;

procedure TProjectPage.SyncRepoClick(Sender: TObject);
begin
  if Trim(FRepoIn.Text) = '' then
  begin
    FHost.Toast(Tr('Indique o endereço do repositório no GitHub.'));
    Exit;
  end;
  StartScan(True);
end;

procedure TProjectPage.SetBusy(ABusy: Boolean);
begin
  FScanBusy := ABusy;
  FBtnScan.Enabled := not ABusy;
  FBtnSync.Enabled := not ABusy;
  FBtnExportMap.Enabled := not ABusy;
  FBtnExportCk.Enabled := not ABusy;
  if ABusy then
    FBtnScan.Text := Tr('A analisar…')
  else
    FBtnScan.Text := Tr('Analisar projeto');
  TCMButtonRow(FBtnScan.Parent).Relayout;
end;

procedure TProjectPage.CancelScan;
begin
  Inc(FScanToken);               // descarta qualquer analise ainda a decorrer
  SetBusy(False);
end;

procedure TProjectPage.InvalidateScans;
begin
  Inc(FScanToken);
end;

procedure TProjectPage.StartScan(ASync: Boolean);
var
  Token: Integer;
  Root, PlanFile, RepoText, RepoErr, ProjectId: string;
  ExcludeList: TArray<string>;
  Ref: TRepoRef;
  NeedSync: Boolean;
begin
  if FHost.CurrentProfile = nil then
    Exit;
  Root := Trim(FRootIn.Text);
  NeedSync := False;
  ProjectId := FHost.CurrentProfile.Id;
  RepoText := Trim(FRepoIn.Text);
  if RepoText <> '' then
  begin
    // repositorio do GitHub: analisa-se a cache; so se vai buscar ao GitHub quando pedido ou se ainda nao existe
    if not ParseRepoUrl(RepoText, Ref, RepoErr) then
    begin
      FStatus.ColorRole := lcDanger;
      FStatus.Text := RepoErr;
      FHost.Toast(RepoErr);
      Exit;
    end;
    Root := RepoWorkDir(ProjectId, Ref);
    if Trim(FRootIn.Text) <> Root then
      FRootIn.Text := Root;
    NeedSync := ASync or not TDirectory.Exists(TPath.Combine(RepoCacheDir(ProjectId), '.git'));
  end;
  PlanFile := Trim(FPlanIn.Text);
  ExcludeList := ParseExcludeDirs(Trim(FExcludeIn.Text));
  if Trim(FNameIn.Text) = '' then
  begin
    FHost.Toast(Tr('Indique o nome do projeto.'));
    Exit;
  end;
  if (Root <> '') and not NeedSync and not TDirectory.Exists(Root) then
  begin
    FStatus.ColorRole := lcDanger;
    FStatus.Text := Tr('Indique uma pasta de projeto válida.');
    FHost.Toast(Tr('Indique uma pasta de projeto válida.'));
    Exit;
  end;
  if (Root = '') and not TFile.Exists(PlanFile) then
  begin
    FStatus.ColorRole := lcDanger;
    FStatus.Text := Tr('Indique uma pasta de projeto ou um documento de plano válido.');
    FHost.Toast(Tr('Indique uma pasta de projeto ou um documento de plano válido.'));
    Exit;
  end;
  Inc(FScanToken);
  Token := FScanToken;
  SetBusy(True);
  FStatus.ColorRole := lcDim;
  if NeedSync then
    FStatus.Text := TrF('A obter %s do GitHub…', [Ref.Display])
  else
    FStatus.Text := Tr('A procurar unidades .pas/.dpr/.dpk…');
  FProgress.Value := 0;

  TTask.Run(
    procedure
    var
      Res, PlanRes: TProjectScan;
      Err: string;
      Warnings: TArray<string>;
    begin
      Res := nil;
      PlanRes := nil;
      Err := '';
      if NeedSync then
      begin
        if not SyncRepo(ProjectId, Ref, Err) then
          Root := ''
        else if not TDirectory.Exists(Root) then
        begin
          Err := Tr('A pasta indicada no endereço não existe no repositório.');
          Root := '';
        end;
      end;
      if Err <> '' then
        Root := '';
      try
        if Root <> '' then
          Res := ScanProject(Root, ExcludeList,
            procedure(const AMsg: string; ADone, ATotal: Integer)
            var
              M: string;
            begin
              if (ADone mod 8 <> 0) and (ADone <> ATotal) then
                Exit;
              M := AMsg;
              System.Classes.TThread.Queue(nil,
                procedure
                begin
                  ScanProgress(Token, M, ADone, ATotal);
                end);
            end);
      except
        on E: Exception do
          Err := E.Message;
      end;
      // o plano e opcional: se falhar, a analise do codigo segue sem ele (com um aviso)
      if (Err = '') and (PlanFile <> '') then
        try
          if TFile.Exists(PlanFile) then
            PlanRes := LoadPlanFile(PlanFile, Warnings)
          else
            Warnings := [Tr('Documento do plano não encontrado: ') + PlanFile];
        except
          on E: Exception do
            Warnings := [Tr('Falhou a leitura do plano: ') + E.Message];
        end;
      System.Classes.TThread.Queue(nil,
        procedure
        begin
          ScanDone(Token, Res, PlanRes, Warnings, Err);
        end);
    end);
end;

procedure TProjectPage.ScanProgress(AToken: Integer; const AMsg: string; ADone, ATotal: Integer);
begin
  if FHost.ShuttingDown or (AToken <> FScanToken) then
    Exit;
  if ATotal > 0 then
    FProgress.Value := ADone / ATotal;
  FStatus.Text := AMsg;
end;

procedure TProjectPage.ScanDone(AToken: Integer; AScan, APlan: TProjectScan;
  const AWarnings: TArray<string>; const AError: string);
var
  Msg: string;
  S: TPlanSummary;
begin
  if FHost.ShuttingDown or (AToken <> FScanToken) then
  begin
    AScan.Free;
    APlan.Free;
    Exit;
  end;
  SetBusy(False);
  if AError <> '' then
  begin
    APlan.Free;
    FStatus.ColorRole := lcDanger;
    FStatus.Text := Tr('ERRO: ') + AError;
    FHost.Toast(Tr('Falhou a análise do projeto.'));
    Exit;
  end;
  FStatus.ColorRole := lcDim;
  FProgress.Value := 1;
  if AScan <> nil then
  begin
    FHost.BindScan(AScan, APlan);
    Msg := Format(Tr('Análise concluída: %d ficheiros · %d métodos em %d units.'),
      [AScan.Units.Count, AScan.TotalMethods, AScan.UnitsWithMethods]);
    if FHost.HasPlan then
    begin
      S := FHost.PlanSummary;
      Msg := Msg + Format(Tr(' Plano: %.0f%% dos ficheiros e %.0f%% dos métodos já existem.'),
        [S.FilesCoverage, S.MethodsCoverage]);
    end;
  end
  else if APlan <> nil then
  begin
    // so o documento: a analise e a do plano (sem codigo para cruzar)
    FHost.BindScan(APlan, nil);
    Msg := Format(Tr('Plano analisado: %d ficheiros · %d métodos em %d units (sem pasta de código).'),
      [APlan.Units.Count, APlan.TotalMethods, APlan.UnitsWithMethods]);
  end
  else
    Msg := Tr('Nada para analisar.');
  if Length(AWarnings) > 0 then
  begin
    Msg := Msg + Format(Tr(' %d aviso(s) do plano.'), [Length(AWarnings)]);
    FHost.Toast(AWarnings[0]);
  end;
  FStatus.Text := Msg;
end;

{ ---------------------------------------------------------------- estatisticas }

procedure TProjectPage.ClearStats;
begin
  FStepsBox.Visible := True;
  FSummary.SetRows([KV(Tr('Pastas'), '—'), KV(Tr('Ficheiros'), '—'), KV(Tr('Métodos'), '—'),
    KV(Tr('Units com métodos'), '—'), KV(Tr('Ficheiros concluídos'), '—'), KV(Tr('Métodos revistos'), '—')]);
end;

procedure TProjectPage.ShowStats(const St: TStats);
begin
  FStepsBox.Visible := False;
  FSummary.SetRows([
    KV(Tr('Pastas'), St.Folders.ToString), KV(Tr('Ficheiros'), St.Files.ToString),
    KV(Tr('Métodos'), St.Methods.ToString), KV(Tr('Units com métodos'), St.UnitsWithMethods.ToString),
    KV(Tr('Ficheiros concluídos'), Format('%d / %d', [St.DoneFiles, St.Files]), True),
    KV(Tr('Métodos revistos'), Format('%d / %d', [St.DoneMethods, St.Methods]), True)]);
end;

{ ---------------------------------------------------------------- exportacao HTML }

procedure TProjectPage.OpenFile(const APath: string);
begin
  ShellExecute(0, 'open', PChar(APath), nil, nil, SW_SHOWNORMAL);
end;

function TProjectPage.EnsureReadyToExport: Boolean;
begin
  Result := False;
  if (FHost.CurrentProfile = nil) or (FHost.CurrentScan = nil) then
  begin
    FHost.Toast(Tr('Analise o projeto primeiro.'));
    Exit;
  end;
  if Trim(FOutIn.Text) = '' then
  begin
    FHost.ShowPage(pgProject);
    FOutIn.Edit.SetFocus;
    FHost.Toast(Tr('Indique a pasta onde guardar as páginas HTML.'));
    Exit;
  end;
  if Trim(FHost.CurrentProfile.Name) = '' then
  begin
    FHost.ShowPage(pgProject);
    FHost.Toast(Tr('Indique o nome do projeto.'));
    Exit;
  end;
  Result := True;
end;

function TProjectPage.ExportMap(AQuiet: Boolean): Boolean;
var
  Path: string;
begin
  Result := False;
  if not EnsureReadyToExport then
    Exit;
  try
    Path := MapOutputPath(FHost.CurrentProfile);
    ExportMapHtml(FHost.CurrentProfile, FHost.CurrentScan, FHost.CurrentState, Path);
    Result := True;
    FHost.Toast(Tr('Mapa exportado: ') + TPath.GetFileName(Path));
    if FHost.AppSettings.OpenAfterExport and not AQuiet then
      OpenFile(Path);
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

procedure TProjectPage.ExportMapClick(Sender: TObject);
begin
  ExportMap(False);
end;

procedure TProjectPage.ExportChecklist;
var
  Path: string;
begin
  if not EnsureReadyToExport then
    Exit;
  try
    Path := ChecklistOutputPath(FHost.CurrentProfile);
    ExportChecklistHtml(FHost.CurrentProfile, FHost.CurrentScan, FHost.CurrentState, Path);
    FHost.Toast(Tr('Checklist exportada: ') + TPath.GetFileName(Path));
    if FHost.AppSettings.OpenAfterExport then
      OpenFile(Path);
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

procedure TProjectPage.ExportChecklistClick(Sender: TObject);
begin
  ExportChecklist;
end;

end.
