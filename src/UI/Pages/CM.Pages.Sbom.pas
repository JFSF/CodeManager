unit CM.Pages.Sbom;

{ Pagina SBOM: a lista de materiais de software do projecto (que units de fora o projecto usa, de onde vem cada uma e com
  que confianca), com o resumo, as opcoes de geracao e a exportacao para CycloneDX, SPDX, relatorio HTML e Markdown.
  Gera-se em segundo plano ao abrir a pagina e refaz-se quando a analise muda ou se mudam as opcoes. So le: nunca altera
  o projecto. Adaptado da ideia do DX.Comply (MIT, Olaf Monien). }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IOUtils, System.Math, System.Threading,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs, Winapi.Windows, Winapi.ShellAPI,
  CM.Theme, CM.Controls, CM.Layouts, CM.SbomView, CM.Sbom, CM.Deps, CM.Analyzer, CM.Store, CM.Pages.Host;

type
  TSbomPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMSbomList;
    FSummary: TCMKeyValue;
    FNote: TCMLabel;
    FProjectSwitch, FMapSwitch, FHashSwitch: TCMSwitch;
    FOptionsCard: TCMPanel;
    FSbom: TSbom;                 // dono do SBOM actual
    FToken: Integer;
    FBuilding: Boolean;
    FStale: Boolean;
    procedure SearchChanged(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure RegenerateClick(Sender: TObject);
    procedure ExportCdxClick(Sender: TObject);
    procedure ExportSpdxClick(Sender: TObject);
    procedure ExportHtmlClick(Sender: TObject);
    procedure ExportMdClick(Sender: TObject);
    procedure DoExport(AKind: Integer);
    procedure Build;
    procedure BuildDone(AToken: Integer; ASbom: TSbom; const AError: string);
    procedure ReleaseSbom;
    procedure ShowSummary;
    procedure ShowRows;
    procedure ShowNote;
    function NoteText: string;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    // a analise mudou (ou ha outro projecto): o SBOM actual deixa de valer
    procedure Invalidate;
    // a pagina passou a estar visivel: gera o SBOM se for preciso
    procedure Activate;
    // grava o SBOM actual (AKind: 0 CycloneDX, 1 SPDX, 2 relatorio HTML, 3 Markdown); levanta uma excepcao se falha
    procedure WriteExport(AKind: Integer; const APath: string);
    property Search: TCMInput read FSearch;
    property Sbom: TSbom read FSbom;
  end;

implementation

uses
  CM.Lang, CM.SbomService, CM.SbomFormats, CM.SbomReport, CM.SysInfo;

const
  ExportCdx = 0;
  ExportSpdx = 1;
  ExportHtml = 2;
  ExportMd = 3;

function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

function OriginColor(AOrigin: TSbomOrigin): TAlphaColor;
begin
  case AOrigin of
    soProject: Result := Pal.Accent;
    soRtl, soVcl, soFmx: Result := Pal.FlagCompila;
  else
    Result := Pal.Pending;
  end;
end;

function ConfidenceColor(AConfidence: TSbomConfidence): TAlphaColor;
begin
  case AConfidence of
    scStrong: Result := Pal.Accent;
    scMedium: Result := Pal.Pending;
  else
    Result := Pal.Danger;
  end;
end;

constructor TSbomPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Bar: TCMControl;
  Side: TCMFadeScroll;
  Card: TCMPanel;
  Holder: TCMPanel;
  Row: TCMButtonRow;
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
  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := Tr('Filtrar por unit, origem ou licença…   ( / )');
  FSearch.OnChangeText := SearchChanged;

  Side := SideBox(Self, Self, 320);

  Card := SideCard(Self, Side, 264);
  TCMLabel.Make(Card, Tr('Resumo'), 15, True).Align := TAlignLayout.Top;
  FSummary := TCMKeyValue.Create(Self);
  FSummary.Parent := Card;
  FSummary.Align := TAlignLayout.Top;
  FSummary.Margins.Top := 8;

  FOptionsCard := SideCard(Self, Side, 330);
  TCMLabel.Make(FOptionsCard, Tr('Opções'), 15, True).Align := TAlignLayout.Top;
  FProjectSwitch := TCMSwitch.Create(Self);
  FProjectSwitch.Parent := FOptionsCard;
  FProjectSwitch.Align := TAlignLayout.Top;
  FProjectSwitch.Height := 30;
  FProjectSwitch.Margins.Top := 8;
  FProjectSwitch.Text := Tr('Incluir as units do projeto');
  FProjectSwitch.OnChange := OptionChanged;
  FMapSwitch := TCMSwitch.Create(Self);
  FMapSwitch.Parent := FOptionsCard;
  FMapSwitch.Align := TAlignLayout.Top;
  FMapSwitch.Height := 30;
  FMapSwitch.Checked := True;
  FMapSwitch.Text := Tr('Confirmar com o ficheiro .map');
  FMapSwitch.OnChange := OptionChanged;
  FHashSwitch := TCMSwitch.Create(Self);
  FHashSwitch.Parent := FOptionsCard;
  FHashSwitch.Align := TAlignLayout.Top;
  FHashSwitch.Height := 30;
  FHashSwitch.Checked := True;
  FHashSwitch.Text := Tr('Calcular os hashes SHA-256');
  FHashSwitch.OnChange := OptionChanged;
  FNote := TCMLabel.Make(FOptionsCard, '', 11.5, False, lcDim);
  FNote.Wrap := True;
  FNote.Align := TAlignLayout.Top;
  FNote.Margins.Top := 10;
  FNote.Height := 100;
  Row := NewButtonRow(Self, FOptionsCard);
  Row.Align := TAlignLayout.Bottom;
  TCMButton.Make(Row, Tr('Gerar de novo'), icRefresh, bkSecondary, RegenerateClick);

  Card := SideCard(Self, Side, 196);
  TCMLabel.Make(Card, Tr('Exportar'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('CycloneDX (JSON)'), icExport, bkPrimary, ExportCdxClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('SPDX (JSON)'), icExport, bkSecondary, ExportSpdxClick);
  Row := NewButtonRow(Self, Card);
  TCMButton.Make(Row, Tr('Relatório HTML'), icExport, bkSecondary, ExportHtmlClick);
  TCMButton.Make(Row, Tr('Markdown'), icExport, bkSecondary, ExportMdClick);

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(1, 1, 1, 1);
  FList := TCMSbomList.Create(Self);
  FList.Parent := Holder;
  FList.Align := TAlignLayout.Client;
  FList.SetHeaders(Tr('Unit'), Tr('Origem'), Tr('Licença'), Tr('Confiança'), Tr('Usada por'), 'SHA-256');
  FList.EmptyText := Tr('Analise um projeto para gerar o SBOM.');
  ShowSummary;
  ShowNote;
end;

destructor TSbomPage.Destroy;
begin
  Inc(FToken);                   // uma geracao em curso deixa de ter efeito
  FreeAndNil(FSbom);
  inherited;
end;

procedure TSbomPage.ApplyTheme;
begin
  FSearch.ApplyTheme;
  ShowRows;
  FList.Repaint;
end;

procedure TSbomPage.SearchChanged(Sender: TObject);
begin
  ShowRows;
end;

procedure TSbomPage.OptionChanged(Sender: TObject);
begin
  Invalidate;
  if Visible then
    Activate;
end;

procedure TSbomPage.RegenerateClick(Sender: TObject);
begin
  Invalidate;
  Activate;
end;

procedure TSbomPage.ReleaseSbom;
begin
  FreeAndNil(FSbom);
end;

procedure TSbomPage.Invalidate;
begin
  Inc(FToken);
  FBuilding := False;
  FStale := True;
  ReleaseSbom;
  FSearch.Text := '';
  ShowSummary;
  ShowRows;
  ShowNote;
end;

procedure TSbomPage.Activate;
begin
  if FStale and not FBuilding and (FHost.CurrentScan <> nil) then
    Build
  else if FHost.CurrentScan = nil then
    FList.EmptyText := Tr('Analise um projeto para gerar o SBOM.');
end;

{ geracao }

procedure TSbomPage.Build;
var
  Inputs: TArray<TDepInput>;
  Root, Name: string;
  Token: Integer;
  Opts: TSbomGenOptions;
begin
  // a lista de units copia-se aqui (na thread da interface); a leitura dos ficheiros e a resolucao correm em segundo plano
  Inputs := CollectDepInputs(FHost.CurrentScan);
  Root := FHost.CurrentScan.Root;
  if FHost.CurrentProfile <> nil then
    Name := FHost.CurrentProfile.Name
  else
    Name := TPath.GetFileName(ExcludeTrailingPathDelimiter(Root));
  Opts := DefaultSbomGenOptions;
  Opts.IncludeProjectUnits := FProjectSwitch.Checked;
  Opts.UseMap := FMapSwitch.Checked;
  Opts.ComputeHashes := FHashSwitch.Checked;
  Inc(FToken);
  Token := FToken;
  FBuilding := True;
  FList.EmptyText := Tr('A gerar o SBOM…');
  FList.SetRows(nil);
  TTask.Run(
    procedure
    var
      G: TDepGraph;
      S: TSbom;
      Err: string;
    begin
      S := nil;
      G := nil;
      Err := '';
      try
        ReadDepSources(Root, Inputs);
        G := BuildDepGraph(Inputs);
        S := GenerateSbom(G, Root, Name, Opts);
      except
        on E: Exception do
          Err := E.Message;
      end;
      G.Free;
      TThread.Queue(nil,
        procedure
        begin
          BuildDone(Token, S, Err);
        end);
    end);
end;

procedure TSbomPage.BuildDone(AToken: Integer; ASbom: TSbom; const AError: string);
begin
  if FHost.ShuttingDown or (AToken <> FToken) then
  begin
    ASbom.Free;
    Exit;
  end;
  FBuilding := False;
  if AError <> '' then
  begin
    ASbom.Free;
    FList.EmptyText := Tr('Não foi possível gerar o SBOM: ') + AError;
    Exit;
  end;
  FStale := False;
  FSbom := ASbom;
  FList.EmptyText := Tr('Este projeto não tem componentes para mostrar.');
  ShowSummary;
  ShowRows;
  ShowNote;
end;

{ cartoes e lista }

procedure TSbomPage.ShowSummary;
var
  Rows: TArray<TKeyValue>;
  Dash: string;
begin
  Dash := '—';
  if FSbom = nil then
    Rows := [KV(Tr('Componentes'), Dash), KV(Tr('Com ficheiro encontrado'), Dash), KV(Tr('Da Embarcadero'), Dash),
      KV(Tr('De terceiros'), Dash), KV(Tr('Do projeto'), Dash), KV(Tr('Por confirmar'), Dash), KV(Tr('Sem licença conhecida'), Dash)]
  else
  begin
    Rows := [KV(Tr('Componentes'), IntToStr(FSbom.Components.Count)),
      KV(Tr('Com ficheiro encontrado'), IntToStr(FSbom.ResolvedCount)),
      KV(Tr('Da Embarcadero'), IntToStr(FSbom.CountOf(soRtl) + FSbom.CountOf(soVcl) + FSbom.CountOf(soFmx))),
      KV(Tr('De terceiros'), IntToStr(FSbom.CountOf(soThirdParty))),
      KV(Tr('Do projeto'), IntToStr(FSbom.CountOf(soProject))),
      KV(Tr('Por confirmar'), IntToStr(FSbom.CountByConfidence(scWeak)), FSbom.CountByConfidence(scWeak) > 0),
      KV(Tr('Sem licença conhecida'), IntToStr(FSbom.ThirdPartyUnlicensedCount), FSbom.ThirdPartyUnlicensedCount > 0)];
    if FSbom.MapFile <> '' then
      Rows := Rows + [KV(Tr('Fora do mapa'), IntToStr(FSbom.NotLinkedCount), FSbom.NotLinkedCount > 0)];
  end;
  FSummary.SetRows(Rows);
  TCMPanel(FSummary.Parent).Height := 16 + 16 + 28 + 8 + FSummary.Height;
end;

procedure TSbomPage.ShowRows;
var
  Rows: TArray<TSbomRow>;
  C: TSbomComponent;
  Q: string;
  R: TSbomRow;
  Used: string;
  I: Integer;
begin
  if FSbom = nil then
  begin
    FList.SetRows(nil);
    Exit;
  end;
  Q := LowerCase(Trim(FSearch.Text));
  for C in FSbom.Components do
  begin
    R := Default(TSbomRow);
    R.Name := C.Name;
    R.OriginText := OriginText(C.Origin);
    R.OriginColor := OriginColor(C.Origin);
    R.ConfidenceText := ConfidenceText(C.Confidence);
    R.ConfidenceColor := ConfidenceColor(C.Confidence);
    R.UsedBy := Length(C.UsedBy);
    R.LicenseKnown := C.License <> '';
    if C.License <> '' then
      R.LicenseText := C.License
    else if C.LicenseName <> '' then
      R.LicenseText := Tr('Ver') + ' ' + C.LicenseSource;
    if C.Hash <> '' then
      R.HashText := Copy(C.Hash, 1, 16);
    if (Q <> '') and (Pos(Q, LowerCase(C.Name)) = 0) and (Pos(Q, LowerCase(R.OriginText)) = 0) and
       (Pos(Q, LowerCase(C.LibraryName)) = 0) and (Pos(Q, LowerCase(C.License)) = 0) then
      Continue;
    Used := '';
    for I := 0 to Min(8, Length(C.UsedBy)) - 1 do
    begin
      if I > 0 then
        Used := Used + ', ';
      Used := Used + C.UsedBy[I];
    end;
    if Length(C.UsedBy) > 8 then
      Used := Used + ', …';
    R.Hint := C.Name + sLineBreak + R.OriginText + ' · ' + EvidenceText(C.Evidence) + ' · ' + R.ConfidenceText;
    if Used <> '' then
      R.Hint := R.Hint + sLineBreak + Tr('Usada por') + ': ' + Used;
    if C.LibraryName <> '' then
    begin
      R.Hint := R.Hint + sLineBreak + Tr('Biblioteca') + ': ' + C.LibraryName;
      if C.Version <> '' then
        R.Hint := R.Hint + ' ' + C.Version;
    end;
    if R.LicenseText <> '' then
      R.Hint := R.Hint + sLineBreak + Tr('Licença') + ': ' + R.LicenseText;
    if C.Path <> '' then
      R.Hint := R.Hint + sLineBreak + ExtractFileName(C.Path)
    else
      R.Hint := R.Hint + sLineBreak + Tr('Sem ficheiro encontrado');
    if C.Hash <> '' then
      R.Hint := R.Hint + sLineBreak + C.Hash;
    Rows := Rows + [R];
  end;
  FList.SetRows(Rows);
end;

function TSbomPage.NoteText: string;
var
  W: string;
  P: TSbomProject;
begin
  if FSbom = nil then
    Exit('');
  P := FSbom.Project;
  Result := P.Name;
  if P.Version <> '' then
    Result := Result + ' ' + P.Version;
  if (P.Configuration <> '') or (P.Platform <> '') then
    Result := Result + ' · ' + P.Configuration + ' ' + P.Platform;
  for W in FSbom.Warnings do
    Result := Result + sLineBreak + sLineBreak + Tr(W);
end;

procedure TSbomPage.ShowNote;
var
  Text, Part: string;
  Lines: Integer;
begin
  Text := NoteText;
  FNote.Text := Text;
  Lines := 0;
  for Part in Text.Split([sLineBreak]) do
    Lines := Lines + Max(1, Ceil(Length(Part) / 40));
  FNote.Height := Max(20, Lines * 16);
  FOptionsCard.Height := 16 + 16 + 28 + 8 + 3 * 30 + 10 + FNote.Height + 12 + 36;
end;

{ exportar }

procedure TSbomPage.ExportCdxClick(Sender: TObject);
begin
  DoExport(ExportCdx);
end;

procedure TSbomPage.ExportSpdxClick(Sender: TObject);
begin
  DoExport(ExportSpdx);
end;

procedure TSbomPage.ExportHtmlClick(Sender: TObject);
begin
  DoExport(ExportHtml);
end;

procedure TSbomPage.ExportMdClick(Sender: TObject);
begin
  DoExport(ExportMd);
end;

procedure TSbomPage.WriteExport(AKind: Integer; const APath: string);
var
  Content, Problem, Version: string;
  Options: TSbomWriteOptions;
begin
  if FSbom = nil then
    raise Exception.Create('sem SBOM');
  Version := ExeVersionText;
  if Version = '' then
    Version := 'dev';
  Options := SbomDefaultOptions(Version);
  case AKind of
    ExportCdx:
      begin
        Content := SbomCycloneDxJson(FSbom, Options);
        if not ValidateCycloneDx(Content, Problem) then
          raise Exception.Create(Problem);
      end;
    ExportSpdx:
      begin
        Content := SbomSpdxJson(FSbom, Options);
        if not ValidateSpdx(Content, Problem) then
          raise Exception.Create(Problem);
      end;
    ExportHtml: Content := SbomHtml(FSbom, FHost.CurrentScan.Root);
  else
    Content := SbomMarkdown(FSbom, FHost.CurrentScan.Root);
  end;
  SaveSbomFile(APath, Content);
end;

procedure TSbomPage.DoExport(AKind: Integer);
var
  D: TSaveDialog;
  Profile: TProjectProfile;
  Path, Ext: string;
begin
  Profile := FHost.CurrentProfile;
  if (Profile = nil) or (FSbom = nil) then
  begin
    FHost.Toast(Tr('Aguarde: o SBOM ainda não está pronto.'));
    Exit;
  end;
  case AKind of
    ExportCdx: Ext := '.cdx.json';
    ExportSpdx: Ext := '.spdx.json';
    ExportHtml: Ext := '.html';
  else
    Ext := '.md';
  end;
  D := TSaveDialog.Create(nil);
  try
    case AKind of
      ExportCdx: D.Filter := 'CycloneDX (*.cdx.json)|*.cdx.json|JSON (*.json)|*.json';
      ExportSpdx: D.Filter := 'SPDX (*.spdx.json)|*.spdx.json|JSON (*.json)|*.json';
      ExportHtml: D.Filter := 'HTML (*.html)|*.html';
    else
      D.Filter := 'Markdown (*.md)|*.md';
    end;
    case AKind of
      ExportHtml, ExportMd: D.FileName := SbomReportFileName(FSbom.Project.Name, Ext);
    else
      D.FileName := SbomFileName(FSbom.Project.Name, Ext);
    end;
    if (Profile.OutputFolder <> '') and TDirectory.Exists(Profile.OutputFolder) then
      D.InitialDir := Profile.OutputFolder;
    if not D.Execute then
      Exit;
    Path := D.FileName;
  finally
    D.Free;
  end;
  try
    WriteExport(AKind, Path);
    FHost.Toast(Tr('Exportado: ') + TPath.GetFileName(Path));
    if (AKind = ExportHtml) and FHost.AppSettings.OpenAfterExport then
      ShellExecute(0, 'open', PChar(Path), nil, nil, SW_SHOWNORMAL);
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

end.
