unit CM.Pages.Code;

{ Pagina Codigo: leitura do codigo-fonte de uma unit, em separadores (um por ficheiro aberto), so de leitura.
  Abre-se com um duplo clique numa unit do Grafo ou num ficheiro / metodo do Mapa e da Checklist; num metodo
  salta para a linha onde ele comeca. O ficheiro e lido do disco (se mudar, volta a ler-se ao voltar a pagina). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.IOUtils, System.Rtti,
  System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Platform,
  CM.Theme, CM.Controls, CM.Layouts, CM.CodeView, CM.Highlight, CM.Analyzer, CM.SonarModel, CM.Pages.Host;

type
  TCodeTab = class
  public
    Path: string;            // relativo a raiz do projecto, com '/'
    FullPath: string;
    Title: string;
    Doc: TCodeDoc;
    ScrollX, ScrollY: Single;
    Mark: Integer;
    Stamp: TDateTime;        // a data do ficheiro quando foi lido
    destructor Destroy; override;
  end;

  TCodePage = class(TCMControl)
  private
    FHost: IPageHost;
    FTabs: TCMTabBar;
    FView: TCMCodeView;
    FInfo: TCMLabel;
    FFontBtn, FLigBtn: TCMButton;
    FSonarPanel: TCMPanel;
    FSonarTitle: TCMLabel;
    FIssues: TCMIssueList;
    FList: TObjectList<TCodeTab>;
    FActive: Integer;
    procedure TabSelect(Sender: TObject; AIndex: Integer);
    procedure TabClose(Sender: TObject; AIndex: Integer);
    procedure CopyClick(Sender: TObject);
    procedure IssuePick(Sender: TObject; ALine: Integer);
    procedure RefreshSonar;
    procedure FontClick(Sender: TObject);
    procedure LigaturesClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure CloseAllClick(Sender: TObject);
    procedure Select(AIndex: Integer);
    procedure SaveViewState;
    procedure RefreshTabs;
    procedure ShowInfo;
    function Load(const AFullPath: string; out ADoc: TCodeDoc; out AStamp: TDateTime): Boolean;
    function IndexOfPath(const APath: string): Integer;
    procedure ReloadIfChanged(ATab: TCodeTab);
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    // fecha todos os separadores (outro projecto, ou a analise mudou)
    procedure Reset;
    // abre (ou volta a mostrar) o codigo da unit; AMethodIndex >= 0 salta para o metodo (indice em AUnit.Methods)
    function OpenUnit(AUnit: TUnitInfo; AMethodIndex: Integer = -1): Boolean;
    // abre a unit e salta para a linha ALine (1 = primeira)
    function OpenUnitAt(AUnit: TUnitInfo; ALine: Integer): Boolean;
    // a pagina passou a estar visivel: se o ficheiro aberto mudou no disco, volta a le-lo
    procedure Activate;
    // chegou uma consulta nova ao SonarQube (ou deixou de haver): refaz os pontos da margem e a lista
    procedure SonarChanged;
    function TabCount: Integer;
    function ActivePath: string;
    // a linha em destaque no separador activo (-1 = nenhuma)
    function MarkedLine: Integer;
    property View: TCMCodeView read FView;
  end;

implementation

uses
  CM.Lang;

{ TCodeTab }

destructor TCodeTab.Destroy;
begin
  Doc.Free;
  inherited;
end;

{ TCodePage }

constructor TCodePage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Bar: TCMControl;
  Side: TCMControl;
  Row: TCMButtonRow;
  Holder: TCMPanel;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;
  FList := TObjectList<TCodeTab>.Create(True);
  FActive := -1;

  FTabs := TCMTabBar.Create(Self);
  FTabs.Parent := Self;
  FTabs.Align := TAlignLayout.Top;
  FTabs.Height := 44;
  FTabs.OnSelect := TabSelect;
  FTabs.OnClose := TabClose;

  Bar := TCMControl.Create(Self);
  Bar.Parent := Self;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 42;
  Bar.Margins.Top := 6;
  Bar.Margins.Bottom := 8;

  Side := TCMControl.Create(Self);
  Side.Parent := Bar;
  Side.Align := TAlignLayout.Right;
  Side.Width := 700;
  Row := TCMButtonRow.Create(Self);
  Row.Parent := Side;
  Row.Align := TAlignLayout.Client;
  FFontBtn := TCMButton.Make(Row, CodeFont, icCode, bkSecondary, FontClick);
  FFontBtn.Height := 38;
  FFontBtn.Hint := Tr('Muda a fonte do código (as fontes modernas instaladas).');
  FFontBtn.ShowHint := True;
  FLigBtn := TCMButton.Make(Row, Tr('Ligaduras'), icCode, bkSecondary, LigaturesClick);
  FLigBtn.Height := 38;
  FLigBtn.Hint := Tr('Mostra os operadores como -> => <> := fundidos (ligaduras da fonte).');
  FLigBtn.ShowHint := True;
  TCMButton.Make(Row, Tr('Copiar tudo'), icCopy, bkSecondary, CopyClick).Height := 38;
  TCMButton.Make(Row, Tr('Fechar'), icClose, bkSecondary, CloseClick).Height := 38;
  TCMButton.Make(Row, Tr('Fechar todos'), icClose, bkSecondary, CloseAllClick).Height := 38;
  Row.Relayout;

  FInfo := TCMLabel.Make(Bar, '', 12.5, False, lcDim, True);
  FInfo.Align := TAlignLayout.Client;

  FSonarPanel := TCMPanel.Create(Self);
  FSonarPanel.Parent := Self;
  FSonarPanel.Align := TAlignLayout.Bottom;
  FSonarPanel.Height := 190;
  FSonarPanel.Margins.Top := 10;
  FSonarPanel.Padding.Rect := TRectF.Create(14, 10, 8, 6);
  FSonarPanel.Visible := False;
  FSonarTitle := TCMLabel.Make(FSonarPanel, '', 12.5, True, lcAccentStrong, True);
  FSonarTitle.Align := TAlignLayout.Top;
  FSonarTitle.Height := 26;
  FIssues := TCMIssueList.Create(Self);
  FIssues.Parent := FSonarPanel;
  FIssues.Align := TAlignLayout.Client;
  FIssues.OnPick := IssuePick;

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(1, 1, 1, 1);
  FView := TCMCodeView.Create(Self);
  FView.Parent := Holder;
  FView.Align := TAlignLayout.Client;
  if FHost.AppSettings <> nil then
  begin
    SetCodeFont(FHost.AppSettings.CodeFont);
    FView.Ligatures := FHost.AppSettings.CodeLigatures;
  end;
  FFontBtn.Text := CodeFont;
  FLigBtn.Active := FView.Ligatures;
  FView.EmptyText := Tr('Dê um duplo clique numa unit do Grafo, ou num ficheiro ou método do Mapa ou da Checklist, para ler o código aqui.');
end;

destructor TCodePage.Destroy;
begin
  FList.Free;
  inherited;
end;

procedure TCodePage.ApplyTheme;
begin
  FTabs.Repaint;
  FView.Repaint;
end;

function TCodePage.TabCount: Integer;
begin
  Result := FList.Count;
end;

function TCodePage.ActivePath: string;
begin
  if (FActive >= 0) and (FActive < FList.Count) then
    Result := FList[FActive].Path
  else
    Result := '';
end;

function TCodePage.MarkedLine: Integer;
begin
  Result := FView.MarkLine;
end;

function TCodePage.IndexOfPath(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    if SameText(FList[I].Path, APath) then
      Exit(I);
  Result := -1;
end;

function TCodePage.Load(const AFullPath: string; out ADoc: TCodeDoc; out AStamp: TDateTime): Boolean;
begin
  ADoc := nil;
  Result := False;
  try
    ADoc := TCodeDoc.Create(ReadSourceText(AFullPath));
    AStamp := TFile.GetLastWriteTime(AFullPath);
    Result := True;
  except
    on E: Exception do
    begin
      FreeAndNil(ADoc);
      FHost.Toast(Tr('Não foi possível ler o ficheiro: ') + E.Message);
    end;
  end;
end;

procedure TCodePage.SaveViewState;
begin
  if (FActive >= 0) and (FActive < FList.Count) then
  begin
    FList[FActive].ScrollX := FView.ScrollX;
    FList[FActive].ScrollY := FView.ScrollY;
    FList[FActive].Mark := FView.MarkLine;
  end;
end;

procedure TCodePage.RefreshTabs;
var
  Titles, Hints: TArray<string>;
  I: Integer;
begin
  SetLength(Titles, FList.Count);
  SetLength(Hints, FList.Count);
  for I := 0 to FList.Count - 1 do
  begin
    Titles[I] := FList[I].Title;
    Hints[I] := FList[I].Path;
  end;
  FTabs.SetTabs(Titles, Hints, FActive);
end;

procedure TCodePage.ShowInfo;
var
  T: TCodeTab;
begin
  if (FActive < 0) or (FActive >= FList.Count) then
  begin
    FInfo.Text := '';
    Exit;
  end;
  T := FList[FActive];
  FInfo.Text := T.Path + '  ·  ' + TrCount(T.Doc.Count, 'linha', 'linhas') + '  ·  ' + Tr('só de leitura');
end;

procedure TCodePage.Select(AIndex: Integer);
var
  T: TCodeTab;
begin
  SaveViewState;
  FActive := AIndex;
  if (AIndex < 0) or (AIndex >= FList.Count) then
  begin
    FActive := -1;
    FView.SetDoc(nil);
  end
  else
  begin
    T := FList[AIndex];
    FView.SetDoc(T.Doc);
    FView.SetScroll(T.ScrollX, T.ScrollY);
    FView.MarkLine := T.Mark;
  end;
  RefreshTabs;
  ShowInfo;
  RefreshSonar;
end;

function TCodePage.OpenUnit(AUnit: TUnitInfo; AMethodIndex: Integer): Boolean;
var
  Scan: TProjectScan;
  Full: string;
  Idx, Line: Integer;
  Tab: TCodeTab;
  Doc: TCodeDoc;
  Stamp: TDateTime;
  M: TMethodInfo;
begin
  Result := False;
  Scan := FHost.CurrentScan;
  if (AUnit = nil) or (Scan = nil) then
    Exit;
  Full := TPath.Combine(Scan.Root, AUnit.Path.Replace('/', PathDelim));
  if not TFile.Exists(Full) then
  begin
    FHost.Toast(Tr('Este ficheiro ainda não existe no código.'));
    Exit;
  end;
  Idx := IndexOfPath(AUnit.Path);
  if Idx < 0 then
  begin
    if not Load(Full, Doc, Stamp) then
      Exit;
    Tab := TCodeTab.Create;
    Tab.Path := AUnit.Path;
    Tab.FullPath := Full;
    Tab.Title := AUnit.FileName;
    Tab.Doc := Doc;
    Tab.Stamp := Stamp;
    Tab.Mark := -1;
    FList.Add(Tab);
    Idx := FList.Count - 1;
  end
  else
    ReloadIfChanged(FList[Idx]);
  Select(Idx);
  Line := -1;
  if (AMethodIndex >= 0) and (AMethodIndex < Length(AUnit.Methods)) then
  begin
    M := AUnit.Methods[AMethodIndex];
    Line := FindRoutineLine(FList[Idx].Doc, M.Owner, M.Simple);
    if Line >= 0 then
      FView.ShowLine(Line)
    else
      FHost.Toast(Tr('Não foi possível localizar o método no ficheiro.'));
  end;
  Result := True;
end;

function TCodePage.OpenUnitAt(AUnit: TUnitInfo; ALine: Integer): Boolean;
begin
  Result := OpenUnit(AUnit, -1);
  if Result and (ALine > 0) then
    FView.ShowLine(ALine - 1);
end;

procedure TCodePage.ReloadIfChanged(ATab: TCodeTab);
var
  Doc: TCodeDoc;
  Stamp: TDateTime;
  Old: TCodeDoc;
begin
  if not TFile.Exists(ATab.FullPath) then
    Exit;
  if TFile.GetLastWriteTime(ATab.FullPath) = ATab.Stamp then
    Exit;
  if not Load(ATab.FullPath, Doc, Stamp) then
    Exit;
  Old := ATab.Doc;
  // o separador activo esta a mostrar o documento antigo: troca-se a vista antes de o libertar
  if (FActive >= 0) and (FList[FActive] = ATab) then
  begin
    SaveViewState;
    FView.SetDoc(Doc);
    FView.SetScroll(ATab.ScrollX, ATab.ScrollY);
  end;
  ATab.Doc := Doc;
  ATab.Stamp := Stamp;
  Old.Free;
end;

procedure TCodePage.Activate;
begin
  if (FActive >= 0) and (FActive < FList.Count) then
  begin
    ReloadIfChanged(FList[FActive]);
    ShowInfo;
  end;
  RefreshSonar;
end;

procedure TCodePage.Reset;
begin
  FView.SetDoc(nil);
  FActive := -1;
  FList.Clear;
  RefreshTabs;
  ShowInfo;
end;

procedure TCodePage.TabSelect(Sender: TObject; AIndex: Integer);
begin
  if AIndex <> FActive then
    Select(AIndex);
end;

procedure TCodePage.TabClose(Sender: TObject; AIndex: Integer);
var
  NewActive: Integer;
begin
  if (AIndex < 0) or (AIndex >= FList.Count) then
    Exit;
  SaveViewState;
  // o documento do separador que se fecha deixa de estar na vista antes de ser libertado
  if AIndex = FActive then
    FView.SetDoc(nil);
  if AIndex < FActive then
    NewActive := FActive - 1
  else if AIndex = FActive then
    NewActive := AIndex
  else
    NewActive := FActive;
  FList.Delete(AIndex);
  if FList.Count = 0 then
    NewActive := -1
  else if NewActive >= FList.Count then
    NewActive := FList.Count - 1;
  FActive := -2;                 // forca a Select a voltar a mostrar o separador
  Select(NewActive);
end;

procedure TCodePage.CloseClick(Sender: TObject);
begin
  TabClose(Self, FActive);
end;

procedure TCodePage.CloseAllClick(Sender: TObject);
begin
  Reset;
end;

function PercentText(AValue: Double): string;
begin
  Result := FormatFloat('0.#', AValue) + '%';
end;

function SeverityColor(ASeverity: TSonarSeverity): TAlphaColor;
begin
  case ASeverity of
    ssBlocker, ssCritical: Result := Pal.Danger;
    ssMajor: Result := Pal.Pending;
  else
    Result := Pal.FlagCompila;
  end;
end;

function KindTag(const AKind: string): string;
begin
  if SameText(AKind, 'BUG') then Result := 'BUG'
  else if SameText(AKind, 'VULNERABILITY') then Result := Tr('VULN.')
  else if SameText(AKind, 'CODE_SMELL') then Result := 'SMELL'
  else Result := Tr('PROBLEMA');
end;

// os problemas e os hotspots do SonarQube para o ficheiro aberto: pontos na margem, a lista em baixo e as medidas no titulo
procedure TCodePage.RefreshSonar;
var
  Snap: TSonarSnapshot;
  Path, Title: string;
  Info: TSonarFile;
  Issues: TArray<TSonarIssue>;
  Spots: TArray<TSonarHotspot>;
  Marks: TArray<TCodeMarker>;
  Rows: TArray<TIssueRow>;
  I: Integer;
  Mk: TCodeMarker;
  Row: TIssueRow;
begin
  Snap := FHost.CurrentSonar;
  Path := ActivePath;
  if (Snap = nil) or (Path = '') or not Snap.Find(Path, Info) then
  begin
    FView.SetMarkers(nil);
    FSonarPanel.Visible := False;
    Exit;
  end;
  Issues := Snap.IssuesOf(Path);
  Spots := Snap.HotspotsOf(Path);
  SetLength(Marks, 0);
  SetLength(Rows, 0);
  for I := 0 to High(Issues) do
  begin
    Row.Line := Issues[I].Line;
    Row.Color := SeverityColor(Issues[I].Severity);
    Row.Tag := KindTag(Issues[I].Kind);
    Row.Text := Issues[I].Message;
    if Issues[I].Rule <> '' then
      Row.Text := Row.Text + '  (' + Issues[I].Rule + ')';
    Rows := Rows + [Row];
    if Issues[I].Line > 0 then
    begin
      Mk.Line := Issues[I].Line - 1;
      Mk.Color := Row.Color;
      Mk.Ring := False;
      Mk.Hint := Format('%s · %s: %s', [SeverityText(Issues[I].Severity), Row.Tag, Issues[I].Message]);
      Marks := Marks + [Mk];
    end;
  end;
  for I := 0 to High(Spots) do
  begin
    Row.Line := Spots[I].Line;
    Row.Color := Pal.FlagSonar;
    Row.Tag := 'HOTSPOT';
    Row.Text := Spots[I].Message;
    if Spots[I].Probability <> '' then
      Row.Text := Row.Text + '  (' + Tr('risco ') + Spots[I].Probability + ')';
    Rows := Rows + [Row];
    if Spots[I].Line > 0 then
    begin
      Mk.Line := Spots[I].Line - 1;
      Mk.Color := Pal.FlagSonar;
      Mk.Ring := True;
      Mk.Hint := 'HOTSPOT: ' + Spots[I].Message;
      Marks := Marks + [Mk];
    end;
  end;
  FView.SetMarkers(Marks);
  FIssues.SetRows(Rows);

  Title := 'SonarQube  ·  ' + TrCount(Length(Issues), 'problema', 'problemas');
  if Length(Spots) > 0 then
    Title := Title + '  ·  ' + TrCount(Length(Spots), 'hotspot', 'hotspots');
  if Info.HasMeasures then
  begin
    if Info.Coverage >= 0 then
      Title := Title + '  ·  ' + Tr('cobertura ') + PercentText(Info.Coverage);
    if Info.DupDensity >= 0 then
      Title := Title + '  ·  ' + Tr('duplicação ') + PercentText(Info.DupDensity);
    if Info.DebtMin > 0 then
      Title := Title + '  ·  ' + Tr('dívida ') + DebtText(Info.DebtMin);
  end;
  FSonarTitle.Text := Title;
  if Length(Rows) = 0 then
  begin
    FIssues.EmptyText := Tr('Sem problemas abertos neste ficheiro.');
    FSonarPanel.Height := 84;
  end
  else
    FSonarPanel.Height := 44 + Min(Length(Rows), 5) * 28 + 14;
  FSonarPanel.Visible := True;
end;

procedure TCodePage.SonarChanged;
begin
  RefreshSonar;
end;

procedure TCodePage.IssuePick(Sender: TObject; ALine: Integer);
begin
  FView.ShowLine(ALine);
end;

// passa para a fonte seguinte da lista das instaladas (e grava a escolha)
procedure TCodePage.FontClick(Sender: TObject);
var
  Choices: TArray<string>;
  I, Next: Integer;
begin
  Choices := CodeFontChoices;
  if Length(Choices) < 2 then
  begin
    FHost.Toast(Tr('Só há uma fonte de código instalada.'));
    Exit;
  end;
  Next := 0;
  for I := 0 to High(Choices) do
    if SameText(Choices[I], CodeFont) then
      Next := (I + 1) mod Length(Choices);
  SetCodeFont(Choices[Next]);
  FHost.AppSettings.CodeFont := Choices[Next];
  FHost.MarkSettingsDirty;
  FFontBtn.Text := CodeFont;
  FView.FontChanged;
end;

procedure TCodePage.LigaturesClick(Sender: TObject);
begin
  FView.Ligatures := not FView.Ligatures;
  FLigBtn.Active := FView.Ligatures;
  FHost.AppSettings.CodeLigatures := FView.Ligatures;
  FHost.MarkSettingsDirty;
end;

procedure TCodePage.CopyClick(Sender: TObject);
var
  Svc: IFMXClipboardService;
  SB: TStringBuilder;
  I: Integer;
begin
  if (FActive < 0) or (FActive >= FList.Count) then
  begin
    FHost.Toast(Tr('Nenhum ficheiro aberto.'));
    Exit;
  end;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
    Exit;
  SB := TStringBuilder.Create;
  try
    for I := 0 to FList[FActive].Doc.Count - 1 do
      SB.AppendLine(FList[FActive].Doc.Line(I).Text);
    Svc.SetClipboard(TValue.From<string>(SB.ToString));
  finally
    SB.Free;
  end;
  FHost.Toast(Tr('Código copiado'));
end;

end.
