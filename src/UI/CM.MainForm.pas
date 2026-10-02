unit CM.MainForm;

{ Janela principal: barra lateral de navegacao + tres paginas (Projeto, Mapa, Checklist).
  A janela guarda o estado partilhado (definicoes, projecto activo, analise, progresso), a
  persistencia, o tema e a navegacao; cada pagina vive na sua unit (CM.Pages.*) e fala com a
  janela pela interface IPageHost. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.IOUtils,
  System.Generics.Collections, System.StrUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Edit, FMX.Printer,
  CM.Theme, CM.Controls, CM.TreeList, CM.Analyzer, CM.Store, CM.Stats, CM.History, CM.Plan, CM.Export, CM.Print,
  CM.Pages.Host, CM.Pages.Project, CM.Pages.Map, CM.Pages.Checklist, CM.Pages.Dashboard;

type
  TMainForm = class(TForm, IPageHost)
  private
    FSettings: TAppSettings;
    FProfile: TProjectProfile;
    FScan: TProjectScan;
    FPlan: TProjectScan;          // analise do documento do plano (nil sem plano)
    FPlanView: TProjectScan;      // codigo cruzado com o plano (so existe com os dois)
    FPlanSummary: TPlanSummary;
    FState: TProgressState;
    FHistory: THistory;
    FPage: TPage;
    FShuttingDown: Boolean;
    FDirtyState: Boolean;
    FDirtySettings: Boolean;
    FDirtyHistory: Boolean;
    FSaveTimer: TTimer;
{$IFDEF DEBUG}
    FDevQueue: TStringList;
    FDevTimer: TTimer;
    FDevWait: Integer;
{$ENDIF}

    // estrutura
    FRail: TCMPanel;
    FContent: TCMControl;
    FHeader: TCMControl;
    FPages: TCMControl;
    FNav: array[TPage] of TCMNavButton;
    FPageBox: array[TPage] of TCMControl;
    FThemeBtn: TCMButton;
    FTitle: TCMLabel;
    FSubtitle: TCMLabel;
    FBadge: TCMPanel;
    FBadgeLabel: TCMLabel;
    FToast: TCMToast;

    // paginas
    FProject: TProjectPage;
    FMap: TMapPage;
    FCk: TChecklistPage;
    FDashboard: TDashboardPage;

    procedure BuildUI;
    procedure BuildRail;
    procedure BuildHeader;

    procedure ApplyTheme;
    procedure ThemeClick(Sender: TObject);
    procedure NavClick(Sender: TObject);
    function ActiveList: TCMTreeList;
    procedure SaveTick(Sender: TObject);
    procedure SaveAll;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);

    // IPageHost
    function GetAppSettings: TAppSettings;
    function GetCurrentProfile: TProjectProfile;
    function GetCurrentScan: TProjectScan;
    function GetCurrentState: TProgressState;
    function GetCurrentHistory: THistory;
    function GetShuttingDown: Boolean;
    function GetHasPlan: Boolean;
    function GetPlanSummary: TPlanSummary;
    function MapScan: TProjectScan;
    function SwapPlanView: TProjectScan;
    procedure Toast(const AText: string);
    procedure MarkStateDirty;
    procedure MarkSettingsDirty;
    procedure CaptureHistory(const St: TStats);
    procedure ShowPage(APage: TPage);
    procedure SelectProject(AProfile: TProjectProfile);
    procedure DetachProfile;
    procedure BindScan(AScan, APlan: TProjectScan);
    procedure UpdateAll;
    procedure UpdateHeader;
    procedure RefreshAllLists;
    procedure ScanChangesApplied(const AFlashKeys: TArray<string>);
    function ExportMapHtml(AQuiet: Boolean): Boolean;
    procedure ExportChecklistHtml;
{$IFDEF DEBUG}
    procedure DevTick(Sender: TObject);
    procedure DevExec(const ACmd: string);
    procedure DevPrintPreview(APage, ADpi: Integer; ALandscape: Boolean; const AFile: string);
{$ENDIF}
  protected
    procedure DoShow; override;
  public
    procedure KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState); override;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
{$IFDEF DEBUG}
    // Modo de desenvolvimento (so em compilacoes DEBUG): executa um guiao interno, ex.:
    //   CodeManager.exe --dev "page:map;wait:1;click:900,212;shot:out.png;quit"
    procedure DevRun(const AScript: string);
{$ENDIF}
  end;

var
  MainForm: TMainForm;

implementation

const
  ProjectFinalizedTitle = 'PROJETO FINALIZADO';

{ TMainForm }

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'CodeManager';
  Width := 1360;
  Height := 860;
  Constraints.MinWidth := 1040;
  Constraints.MinHeight := 640;
  Position := TFormPosition.ScreenCenter;
  OnClose := FormClose;

  FSettings := TAppSettings.Create;
  FState := TProgressState.Create;
  FHistory := THistory.Create;
  try
    FSettings.Load;
  except
    on Exception do ;   // definicoes ilegiveis: recomecar com os valores por omissao
  end;
  if FSettings.Theme = 'dark' then
    SetThemeMode(tmDark)
  else if FSettings.Theme = 'light' then
    SetThemeMode(tmLight)
  else if SystemPrefersDark then
    SetThemeMode(tmDark)
  else
    SetThemeMode(tmLight);

  FSaveTimer := TTimer.Create(Self);
  FSaveTimer.Enabled := False;
  FSaveTimer.Interval := 700;
  FSaveTimer.OnTimer := SaveTick;

  BuildUI;
  ApplyTheme;
  ShowPage(pgProject);

  if FSettings.Projects.Count = 0 then
    FProject.NewProject
  else
  begin
    FProject.RefreshProjectList;
    FProfile := FSettings.FindProject(FSettings.ActiveProjectId);
    if FProfile = nil then
      FProfile := FSettings.Projects[0];
    SelectProject(FProfile);
  end;
{$IFDEF DEBUG}
  if (ParamCount >= 2) and (ParamStr(1) = '--dev') then
    DevRun(ParamStr(2));
{$ENDIF}
end;

destructor TMainForm.Destroy;
begin
  FShuttingDown := True;
  FProject.StopWatch;
  FPlanView.Free;
  FPlan.Free;
  FScan.Free;
  FHistory.Free;
  FState.Free;
  FSettings.Free;
  inherited;
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FShuttingDown := True;
  FProject.StopWatch;
  FProject.InvalidateScans;
  SaveAll;
end;

{ ---------------------------------------------------------------- construcao da UI }

procedure TMainForm.BuildUI;
begin
  FRail := TCMPanel.Create(Self);
  FRail.Parent := Self;
  FRail.Align := TAlignLayout.Left;
  FRail.Width := 88;
  FRail.Role := prSurface;
  FRail.Radius := 0;
  FRail.Bordered := False;
  BuildRail;

  FContent := TCMControl.Create(Self);
  FContent.Parent := Self;
  FContent.Align := TAlignLayout.Client;
  FContent.Padding.Rect := TRectF.Create(28, 0, 28, 24);

  BuildHeader;

  FPages := TCMControl.Create(Self);
  FPages.Parent := FContent;
  FPages.Align := TAlignLayout.Client;

  FProject := TProjectPage.Create(Self, FPages, Self);
  FMap := TMapPage.Create(Self, FPages, Self);
  FCk := TChecklistPage.Create(Self, FPages, Self);
  FDashboard := TDashboardPage.Create(Self, FPages, Self);
  FPageBox[pgProject] := FProject;
  FPageBox[pgMap] := FMap;
  FPageBox[pgChecklist] := FCk;
  FPageBox[pgDashboard] := FDashboard;

  FToast := TCMToast.Create(Self);
  FToast.Parent := FContent;   // o toast posiciona-se em relacao a um TControl
end;

procedure TMainForm.BuildRail;
const
  Names: array[TPage] of string = ('Projeto', 'Mapa', 'Checklist', 'Painel');
  Icons: array[TPage] of TIconKind = (icDashboard, icMap, icChecklist, icChart);
var
  P: TPage;
  Logo: TCMLogo;
  Line: TCMPanel;
begin
  Line := TCMPanel.Create(Self);
  Line.Parent := FRail;
  Line.Align := TAlignLayout.Right;
  Line.Width := 1;
  Line.Radius := 0;
  Line.Bordered := False;
  Line.Role := prSurface2;

  Logo := TCMLogo.Create(Self);
  Logo.Parent := FRail;
  Logo.Align := TAlignLayout.Top;
  Logo.Height := 40;
  Logo.Margins.Top := 20;
  Logo.Margins.Bottom := 14;

  for P := Low(TPage) to High(TPage) do
  begin
    FNav[P] := TCMNavButton.Create(Self);
    FNav[P].Parent := FRail;
    FNav[P].Align := TAlignLayout.Top;
    FNav[P].Text := Names[P];
    FNav[P].Icon := Icons[P];
    FNav[P].Tag := Ord(P);
    FNav[P].OnClick := NavClick;
    FNav[P].Margins.Rect := TRectF.Create(8, 0, 8, 6);
  end;

  FThemeBtn := TCMButton.MakeIcon(FRail, icMoon, ThemeClick, 'Alternar entre tema claro e escuro');
  FThemeBtn.Align := TAlignLayout.Bottom;
  FThemeBtn.Height := 44;
  FThemeBtn.Margins.Rect := TRectF.Create(20, 0, 20, 20);
end;

procedure TMainForm.BuildHeader;
begin
  FHeader := TCMControl.Create(Self);
  FHeader.Parent := FContent;
  FHeader.Align := TAlignLayout.Top;
  FHeader.Height := 96;

  FBadge := TCMPanel.Create(Self);
  FBadge.Parent := FHeader;
  FBadge.Align := TAlignLayout.Right;
  FBadge.Width := 250;
  FBadge.Height := 34;
  FBadge.Role := prAccentSoft;
  FBadge.Radius := 17;
  FBadge.Margins.Top := 34;
  FBadge.Margins.Bottom := 30;
  FBadge.Visible := False;
  FBadgeLabel := TCMLabel.Make(FBadge, ProjectFinalizedTitle, 11, True, lcAccentStrong, True);
  FBadgeLabel.Align := TAlignLayout.Client;
  FBadgeLabel.HAlign := TTextAlign.Center;

  FTitle := TCMLabel.Make(FHeader, 'Projeto', 26, True);
  FTitle.Align := TAlignLayout.Top;
  FTitle.Height := 38;
  FTitle.Margins.Top := 26;
  FSubtitle := TCMLabel.Make(FHeader, '', 13, False, lcDim);
  FSubtitle.Align := TAlignLayout.Top;
  FSubtitle.Height := 22;
end;

{ ---------------------------------------------------------------- tema e navegacao }

procedure TMainForm.ApplyTheme;
begin
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := Pal.Bg;
  if ThemeMode = tmDark then
    FThemeBtn.Icon := icSun
  else
    FThemeBtn.Icon := icMoon;
  FProject.ApplyTheme;
  FMap.ApplyTheme;
  FCk.ApplyTheme;
  FDashboard.ApplyTheme;
  ApplyTitleBarTheme(Self);
  Invalidate;
end;

procedure TMainForm.DoShow;
begin
  inherited;
  ApplyTitleBarTheme(Self);
end;

procedure TMainForm.ThemeClick(Sender: TObject);
begin
  if ThemeMode = tmDark then
  begin
    SetThemeMode(tmLight);
    FSettings.Theme := 'light';
  end
  else
  begin
    SetThemeMode(tmDark);
    FSettings.Theme := 'dark';
  end;
  MarkSettingsDirty;
  ApplyTheme;
end;

procedure TMainForm.NavClick(Sender: TObject);
begin
  ShowPage(TPage(TFmxObject(Sender).Tag));
end;

function TMainForm.ActiveList: TCMTreeList;
begin
  case FPage of
    pgMap: Result := FMap.List;
    pgChecklist: Result := FCk.List;
  else
    Result := nil;
  end;
end;

procedure TMainForm.ShowPage(APage: TPage);
var
  P: TPage;
begin
  FPage := APage;
  for P := Low(TPage) to High(TPage) do
  begin
    FPageBox[P].Visible := P = APage;
    FNav[P].Selected := P = APage;
  end;
  if ActiveList <> nil then
    ActiveList.Refresh;      // as duas vistas partilham o progresso (Compila/Sonar)
  if APage = pgDashboard then
    FDashboard.Activate;
  UpdateHeader;
end;

procedure TMainForm.Toast(const AText: string);
begin
  FToast.ShowText(AText);
end;

{ ---------------------------------------------------------------- IPageHost: estado partilhado }

function TMainForm.GetAppSettings: TAppSettings;
begin
  Result := FSettings;
end;

function TMainForm.GetCurrentProfile: TProjectProfile;
begin
  Result := FProfile;
end;

function TMainForm.GetCurrentScan: TProjectScan;
begin
  Result := FScan;
end;

function TMainForm.GetCurrentState: TProgressState;
begin
  Result := FState;
end;

function TMainForm.GetCurrentHistory: THistory;
begin
  Result := FHistory;
end;

function TMainForm.GetHasPlan: Boolean;
begin
  Result := FPlanView <> nil;
end;

function TMainForm.GetPlanSummary: TPlanSummary;
begin
  Result := FPlanSummary;
end;

// o que o Mapa mostra: a vista cruzada com o plano, ou a analise do codigo
function TMainForm.MapScan: TProjectScan;
begin
  if FPlanView <> nil then
    Result := FPlanView
  else
    Result := FScan;
end;

// reconstroi a vista cruzada; devolve a anterior para quem chama a libertar depois de as listas
// deixarem de a usar
function TMainForm.SwapPlanView: TProjectScan;
begin
  Result := FPlanView;
  FPlanView := nil;
  FPlanSummary := Default(TPlanSummary);
  if (FScan <> nil) and (FPlan <> nil) then
    FPlanView := MergePlan(FScan, FPlan, FPlanSummary);
end;

function TMainForm.GetShuttingDown: Boolean;
begin
  Result := FShuttingDown;
end;

{ ---------------------------------------------------------------- persistencia }

procedure TMainForm.MarkStateDirty;
begin
  FDirtyState := True;
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

procedure TMainForm.MarkSettingsDirty;
begin
  FDirtySettings := True;
  FSaveTimer.Enabled := False;
  FSaveTimer.Enabled := True;
end;

// regista o dia de hoje no historico (so marca para guardar se os valores mudaram)
procedure TMainForm.CaptureHistory(const St: TStats);
begin
  if (FProfile = nil) or (St.Files = 0) then
    Exit;
  if FHistory.Capture(TSnapshot.FromStats(DayText(Date), St)) then
  begin
    FDirtyHistory := True;
    FSaveTimer.Enabled := False;
    FSaveTimer.Enabled := True;
  end;
end;

procedure TMainForm.SaveTick(Sender: TObject);
begin
  SaveAll;
end;

procedure TMainForm.SaveAll;
begin
  FSaveTimer.Enabled := False;
  try
    if FDirtySettings then
    begin
      FSettings.Save;
      FDirtySettings := False;
    end;
    if FDirtyState and (FProfile <> nil) then
    begin
      FState.SaveToFile(ProgressFileFor(FProfile.Id));
      FDirtyState := False;
    end;
    if FDirtyHistory and (FProfile <> nil) then
    begin
      FHistory.SaveToFile(HistoryFileFor(FProfile.Id));
      FDirtyHistory := False;
    end;
  except
    on E: Exception do
      Toast('Não foi possível guardar: ' + E.Message);
  end;
end;

{ ---------------------------------------------------------------- projecto activo e analise }

procedure TMainForm.SelectProject(AProfile: TProjectProfile);
var
  F: string;
begin
  SaveAll;                       // guarda o progresso do projecto que estava aberto
  FProject.CancelScan;           // descarta qualquer analise ainda a decorrer
  FProfile := AProfile;
  FSettings.ActiveProjectId := AProfile.Id;
  MarkSettingsDirty;

  FState.Clear;
  F := ProgressFileFor(AProfile.Id);
  if TFile.Exists(F) then
    try
      FState.LoadFromFile(F);
    except
      on Exception do FState.Clear;
    end;

  FHistory.Clear;
  FDirtyHistory := False;
  F := HistoryFileFor(AProfile.Id);
  if TFile.Exists(F) then
    try
      FHistory.LoadFromFile(F);
    except
      on Exception do FHistory.Clear;
    end;

  FProject.LoadFields(AProfile);
  FCk.CloseNote(nil);
  BindScan(nil, nil);
  FProject.ResetStatus;
  FProject.RefreshProjectList;
  UpdateHeader;

  // analisa ao abrir: a pasta de codigo, ou so o documento do plano quando nao ha pasta
  if ((AProfile.RootPath <> '') and TDirectory.Exists(AProfile.RootPath)) or
     ((AProfile.RootPath = '') and (AProfile.PlanPath <> '') and TFile.Exists(AProfile.PlanPath)) then
    FProject.StartScan;
end;

procedure TMainForm.DetachProfile;
begin
  FProfile := nil;
  FDirtyState := False;
  FDirtyHistory := False;
  FHistory.Clear;
end;

procedure TMainForm.BindScan(AScan, APlan: TProjectScan);
var
  Old, OldPlan, OldView: TProjectScan;
begin
  FProject.StopWatch;            // o vigia e da analise anterior (a pasta pode ter mudado)
  Old := FScan;
  OldPlan := FPlan;
  FScan := AScan;
  FPlan := APlan;
  // progresso guardado antes de os metodos passarem a ter chave qualificada (TFoo.Bar)
  if (FScan <> nil) and MigrateMethodKeys(FScan, FState) then
    MarkStateDirty;
  OldView := SwapPlanView;
  FMap.List.LoadData(MapScan, FState);
  FCk.List.LoadData(FScan, FState);
  OldView.Free;
  OldPlan.Free;
  Old.Free;
  FCk.RebuildChips;
  UpdateAll;
  UpdateHeader;
  if FScan <> nil then
    FProject.StartWatch;
end;

procedure TMainForm.RefreshAllLists;
begin
  FMap.List.Refresh;
  FCk.List.Refresh;
end;

// reflecte nas duas vistas o que mudou na analise, sem perder scroll nem pastas abertas
procedure TMainForm.ScanChangesApplied(const AFlashKeys: TArray<string>);
var
  OldView: TProjectScan;
begin
  if FScan <> nil then
    FCk.CloseNoteIfRemoved(FScan);
  OldView := SwapPlanView;
  FMap.List.UseScan(MapScan);
  FMap.List.ReloadKeepView;
  FCk.List.ReloadKeepView;
  FMap.List.MarkChanged(AFlashKeys);
  FCk.List.MarkChanged(AFlashKeys);
  OldView.Free;
  FCk.RebuildChips;
  UpdateAll;
  UpdateHeader;
end;

{ ---------------------------------------------------------------- estatisticas e cabecalho }

procedure TMainForm.UpdateAll;
var
  St: TStats;
begin
  if FScan = nil then
  begin
    FProject.ClearStats;
    FMap.ClearStats;
    FCk.ClearStats;
    FDashboard.ClearStats;
    Exit;
  end;
  St := ComputeStats(FScan, FState);
  CaptureHistory(St);
  FProject.ShowStats(St);
  FMap.ShowStats(St);
  FCk.ShowStats(St);
  FDashboard.ShowStats(St);
end;

procedure TMainForm.UpdateHeader;
var
  Info: string;
begin
  case FPage of
    pgProject:
      begin
        FTitle.Text := 'Projeto';
        FSubtitle.Text := 'Configure o projeto, analise o código-fonte e exporte as páginas HTML.';
      end;
    pgMap, pgChecklist, pgDashboard:
      begin
        case FPage of
          pgMap: FTitle.Text := 'Mapa de código';
          pgChecklist: FTitle.Text := 'Checklist de código';
        else
          FTitle.Text := 'Painel';
        end;
        if (FProfile <> nil) and (FScan <> nil) then
          Info := Format('%s  ·  %d ficheiros  ·  %d métodos', [FProfile.Name, FScan.Units.Count, FScan.TotalMethods])
        else if FProfile <> nil then
          Info := FProfile.Name + '  ·  ainda sem análise (separador Projeto)'
        else
          Info := '';
        FSubtitle.Text := Info;
      end;
  end;
  if (FProfile <> nil) and FProfile.Finalized then
  begin
    FBadgeLabel.Text := ProjectFinalizedTitle + '  ·  ' + FProfile.FinalizedAt;
    FBadge.Width := MeasureText(FBadgeLabel.Text, 11, MonoFont, [TFontStyle.fsBold]) + 40;
    FBadge.Visible := True;
  end
  else
    FBadge.Visible := False;
  FProject.UpdateFinalizeButton;
end;

{ ---------------------------------------------------------------- exportacao HTML }

function TMainForm.ExportMapHtml(AQuiet: Boolean): Boolean;
begin
  Result := FProject.ExportMap(AQuiet);
end;

procedure TMainForm.ExportChecklistHtml;
begin
  FProject.ExportChecklist;
end;

{$IFDEF DEBUG}
procedure TMainForm.DevRun(const AScript: string);
var
  S: string;
begin
  FDevQueue := TStringList.Create;
  for S in AScript.Split([';']) do
    if Trim(S) <> '' then
      FDevQueue.Add(Trim(S));
  FDevTimer := TTimer.Create(Self);
  FDevTimer.Interval := 250;
  FDevTimer.OnTimer := DevTick;
  FDevTimer.Enabled := True;
end;

procedure TMainForm.DevTick(Sender: TObject);
var
  Cmd: string;
begin
  if FDevWait > 0 then
  begin
    Dec(FDevWait);
    Exit;
  end;
  if FDevQueue.Count = 0 then
    Exit;
  Cmd := FDevQueue[0];
  FDevQueue.Delete(0);
  try
    DevExec(Cmd);
    TFile.AppendAllText('dev.log', 'ok   ' + Cmd + sLineBreak);
  except
    on E: Exception do
      TFile.AppendAllText('dev.log', 'ERRO ' + Cmd + ' -> ' + E.ClassName + ': ' + E.Message + sLineBreak);
  end;
end;

procedure TMainForm.DevPrintPreview(APage, ADpi: Integer; ALandscape: Boolean; const AFile: string);
var
  Bmp: FMX.Graphics.TBitmap;
  Doc: TStructureDoc;
  W, H, T: Integer;
begin
  if FScan = nil then
    raise Exception.Create('sem analise');
  W := Round(8.27 * ADpi);
  H := Round(11.69 * ADpi);
  if ALandscape then
  begin
    T := W;
    W := H;
    H := T;
  end;
  Bmp := FMX.Graphics.TBitmap.Create(W, H);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(W, H, ADpi), FProfile, FScan, FState, FMap.ExportOptionsNow);
    try
      Bmp.Canvas.BeginScene;
      try
        Bmp.Canvas.Clear(TAlphaColors.White);
        Doc.DrawPage(Bmp.Canvas, Min(APage, Doc.PageCount - 1));
      finally
        Bmp.Canvas.EndScene;
      end;
      Bmp.SaveToFile(AFile);
      TFile.AppendAllText('dev.log', Format('     paginas=%d colunas=%d%s', [Doc.PageCount, Doc.MaxChars, sLineBreak]));
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
  end;
end;

procedure TMainForm.DevExec(const ACmd: string);
var
  Cmd, Arg: string;
  P, I: Integer;
  Parts: TArray<string>;
  X, Y: Single;
  Handled: Boolean;
  Bmp: FMX.Graphics.TBitmap;
begin
  P := ACmd.IndexOf(':');
  if P >= 0 then
  begin
    Cmd := Copy(ACmd, 1, P);
    Arg := Copy(ACmd, P + 2, MaxInt);
  end
  else
  begin
    Cmd := ACmd;
    Arg := '';
  end;
  if Cmd = 'wait' then
    FDevWait := Round(StrToFloat(Arg, TFormatSettings.Invariant) * 4)
  else if Cmd = 'page' then
    ShowPage(TPage(StrToInt(Arg)))
  else if Cmd = 'search' then
  begin
    if FPage = pgMap then FMap.Search.Text := Arg else FCk.Search.Text := Arg;
  end
  else if Cmd = 'theme' then
  begin
    if (Arg = 'dark') <> (ThemeMode = tmDark) then
      ThemeClick(nil);
  end
  else if Cmd = 'size' then
  begin
    // size:largura,altura - redimensiona a area cliente (testar a disposicao em janelas pequenas)
    Parts := Arg.Split([',']);
    ClientWidth := StrToInt(Parts[0]);
    ClientHeight := StrToInt(Parts[1]);
  end
  else if Cmd = 'hint' then
  begin
    // hint:x,y - poe o rato em (x,y) e regista no dev.log a dica que o controlo mostraria
    Parts := Arg.Split([',']);
    X := StrToFloat(Parts[0], TFormatSettings.Invariant);
    Y := StrToFloat(Parts[1], TFormatSettings.Invariant);
    MouseMove([], X, Y);
    case FPage of
      pgMap: TFile.AppendAllText('dev.log', 'dica(mapa)=[' + FMap.List.Hint + ']' + sLineBreak);
      pgChecklist: TFile.AppendAllText('dev.log', 'dica(checklist)=[' + FCk.List.Hint + ']' + sLineBreak);
      pgProject: TFile.AppendAllText('dev.log', 'dica(projeto)=[' + FProject.ProjectsHint + ']' + sLineBreak);
    end;
  end
  else if Cmd = 'toast' then
    Toast(Arg)
  else if Cmd = 'notetext' then
    FCk.NoteIn.Text := Arg
  else if Cmd = 'exportmap' then
    ExportMapHtml(False)
  else if Cmd = 'exportstruct' then
  begin
    // exportstruct:md|txt|csv|json,ficheiro,metodos(0/1),estado(0/1)
    Parts := Arg.Split([',']);
    FMap.ExpMethods.Checked := Parts[2] = '1';
    FMap.ExpProgress.Checked := Parts[3] = '1';
    if (FScan = nil) or not FMap.SaveStructure(TExportFormat(IndexText(Parts[0], ['md', 'txt', 'csv', 'json'])), Parts[1]) then
      raise Exception.Create('exportstruct falhou');
  end
  else if Cmd = 'printprev' then
  begin
    // printprev:pagina,dpi,horizontal(0/1),ficheiro.png - desenha uma pagina num bitmap (A4)
    Parts := Arg.Split([',']);
    FMap.ExpMethods.Checked := True;
    DevPrintPreview(StrToInt(Parts[0]), StrToInt(Parts[1]), Parts[2] = '1', Parts[3]);
  end
  else if Cmd = 'printto' then
  begin
    // printto:nome da impressora (ou parte do nome) - imprime sem passar pelo dialogo
    for I := 0 to Printer.Count - 1 do
      if ContainsText(Printer.Printers[I].Title, Arg) then
      begin
        Printer.ActivePrinter := Printer.Printers[I];
        Break;
      end;
    if not ContainsText(Printer.ActivePrinter.Title, Arg) then
      raise Exception.Create('impressora nao encontrada: ' + Arg);
    FMap.PrintNow;
  end
  else if Cmd = 'setproj' then
  begin
    // setproj:nome,pasta raiz,pasta de destino[,plano.md] - preenche o projecto activo e analisa
    Parts := Arg.Split([',']);
    FProject.NameIn.Text := Parts[0];
    FProject.RootIn.Text := Parts[1];
    FProject.OutIn.Text := Parts[2];
    if Length(Parts) > 3 then
      FProject.PlanIn.Text := Parts[3];
    FProject.StartScan;
  end
  else if Cmd = 'watch' then
  begin
    FProject.WatchSwitch.Checked := Arg = '1';
    FProject.WatchSwitchChanged(nil);
  end
  else if Cmd = 'exportck' then
    ExportChecklistHtml
  else if Cmd = 'finalize' then
    FProject.FinalizeClick(nil)
  else if Cmd = 'select' then
    SelectProject(FSettings.Projects[StrToInt(Arg)])
  else if (Cmd = 'click') or (Cmd = 'move') then
  begin
    Parts := Arg.Split([',']);
    X := StrToFloat(Parts[0], TFormatSettings.Invariant);
    Y := StrToFloat(Parts[1], TFormatSettings.Invariant);
    MouseMove([], X, Y);
    if Cmd = 'click' then
    begin
      MouseDown(TMouseButton.mbLeft, [ssLeft], X, Y);
      MouseUp(TMouseButton.mbLeft, [], X, Y);
    end;
  end
  else if Cmd = 'wheel' then
  begin
    Parts := Arg.Split([',']);
    Handled := False;
    MouseMove([], StrToFloat(Parts[0], TFormatSettings.Invariant), StrToFloat(Parts[1], TFormatSettings.Invariant));
    MouseWheel([], StrToInt(Parts[2]), Handled);
  end
  else if Cmd = 'shot' then
  begin
    // compoe a captura a partir dos dois blocos de topo (o TForm nao tem MakeScreenshot)
    Bmp := FMX.Graphics.TBitmap.Create(Round(ClientWidth), Round(ClientHeight));
    try
      if Bmp.Canvas.BeginScene then
        try
          Bmp.Canvas.Clear(Pal.Bg);
          FRail.PaintTo(Bmp.Canvas, TRectF.Create(0, 0, FRail.Width, ClientHeight));
          FContent.PaintTo(Bmp.Canvas, TRectF.Create(FRail.Width, 0, ClientWidth, ClientHeight));
          if FToast.Visible then
            FToast.PaintTo(Bmp.Canvas, TRectF.Create(FToast.AbsoluteRect.Left, FToast.AbsoluteRect.Top,
              FToast.AbsoluteRect.Right, FToast.AbsoluteRect.Bottom));
        finally
          Bmp.Canvas.EndScene;
        end;
      Bmp.SaveToFile(Arg);
    finally
      Bmp.Free;
    end;
  end
  else if Cmd = 'quit' then
    Application.Terminate;
end;
{$ENDIF}

{ ---------------------------------------------------------------- teclado }

procedure TMainForm.KeyDown(var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
var
  Target: TCMInput;
begin
  inherited;
  if KeyChar <> '/' then
    Exit;
  if (Focused <> nil) and (Focused.GetObject is TEdit) then
    Exit;
  case FPage of
    pgMap: Target := FMap.Search;
    pgChecklist: Target := FCk.Search;
  else
    Target := nil;
  end;
  if Target <> nil then
  begin
    Target.Edit.SetFocus;
    KeyChar := #0;
  end;
end;

end.
