unit CM.Pages.Classes;

{ Pagina Classes: as classes, interfaces e records do projecto com a profundidade de heranca de cada uma, o resumo e a
  exportacao (Markdown e CSV). A hierarquia constroi-se a partir da analise actual (e rapida, sem ler ficheiros) quando a
  pagina abre e refaz-se quando a analise muda. So le: nunca altera o projecto. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.IOUtils, System.Math, System.Generics.Collections, System.Generics.Defaults,
  FMX.Types, FMX.Controls, FMX.Layouts, FMX.Dialogs,
  CM.Theme, CM.Controls, CM.Layouts, CM.ClassView, CM.ClassHierarchy, CM.Analyzer, CM.Store, CM.Pages.Host;

type
  TClassesPage = class(TCMControl)
  private
    FHost: IPageHost;
    FSearch: TCMInput;
    FList: TCMClassList;
    FSummary: TCMKeyValue;
    FNote: TCMLabel;
    FInterfacesSwitch: TCMSwitch;
    FHier: THierarchy;            // dono da hierarquia actual
    FStale: Boolean;
    FSortColumn: Integer;         // -1 = pela arvore
    FSortDesc: Boolean;
    procedure SearchChanged(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
    procedure SortClick(Sender: TObject; AColumn: Integer);
    procedure OpenClick(Sender: TObject; ATag: Integer);
    procedure ExportMdClick(Sender: TObject);
    procedure ExportCsvClick(Sender: TObject);
    procedure DoExport(AKind: Integer);
    procedure Build;
    procedure ShowSummary;
    procedure ShowRows;
    procedure ShowNote;
    function ProjectName: string;
    function Ordered: TArray<TClassNode>;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    destructor Destroy; override;
    procedure ApplyTheme;
    // a analise mudou (ou ha outro projecto): a hierarquia actual deixa de valer
    procedure Invalidate;
    // a pagina passou a estar visivel: constroi a hierarquia se for preciso
    procedure Activate;
    // grava o relatorio (AKind: 0 Markdown, 1 CSV); levanta uma excepcao se falha
    procedure WriteExport(AKind: Integer; const APath: string);
    property Search: TCMInput read FSearch;
    property Hierarchy: THierarchy read FHier;
  end;

implementation

uses
  CM.Lang, CM.Classes, CM.Metrics, CM.ClassReport;

const
  ExportMd = 0;
  ExportCsv = 1;

function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

function DepthColor(ADepth: Integer): TAlphaColor;
begin
  case DepthLevel(ADepth) of
    cxHigh: Result := Pal.Danger;
    cxModerate: Result := Pal.Pending;
  else
    Result := Pal.Accent;
  end;
end;

constructor TClassesPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
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
  FSortColumn := -1;

  Bar := TCMControl.Create(Self);
  Bar.Parent := Self;
  Bar.Align := TAlignLayout.Top;
  Bar.Height := 42;
  Bar.Margins.Bottom := 16;
  FSearch := TCMInput.Create(Self);
  FSearch.Parent := Bar;
  FSearch.Align := TAlignLayout.Client;
  FSearch.SetLeadingIcon(icSearch);
  FSearch.Placeholder := Tr('Filtrar por classe, ancestral ou ficheiro…   ( / )');
  FSearch.OnChangeText := SearchChanged;

  Side := SideBox(Self, Self, 320);

  Card := SideCard(Self, Side, 264);
  TCMLabel.Make(Card, Tr('Resumo'), 15, True).Align := TAlignLayout.Top;
  FSummary := TCMKeyValue.Create(Self);
  FSummary.Parent := Card;
  FSummary.Align := TAlignLayout.Top;
  FSummary.Margins.Top := 8;

  Card := SideCard(Self, Side, 230);
  TCMLabel.Make(Card, Tr('Opções'), 15, True).Align := TAlignLayout.Top;
  FInterfacesSwitch := TCMSwitch.Create(Self);
  FInterfacesSwitch.Parent := Card;
  FInterfacesSwitch.Align := TAlignLayout.Top;
  FInterfacesSwitch.Height := 30;
  FInterfacesSwitch.Margins.Top := 8;
  FInterfacesSwitch.Checked := True;
  FInterfacesSwitch.Text := Tr('Mostrar as interfaces');
  FInterfacesSwitch.OnChange := OptionChanged;
  FNote := TCMLabel.Make(Card, '', 11.5, False, lcDim);
  FNote.Wrap := True;
  FNote.Align := TAlignLayout.Top;
  FNote.Margins.Top := 10;
  FNote.Height := 110;

  Card := SideCard(Self, Side, 130);
  TCMLabel.Make(Card, Tr('Exportar'), 15, True).Align := TAlignLayout.Top;
  Row := NewButtonRow(Self, Card);
  Row.Margins.Top := 12;
  TCMButton.Make(Row, Tr('Markdown'), icExport, bkPrimary, ExportMdClick);
  TCMButton.Make(Row, 'CSV', icExport, bkSecondary, ExportCsvClick);

  Holder := TCMPanel.Create(Self);
  Holder.Parent := Self;
  Holder.Align := TAlignLayout.Client;
  Holder.Padding.Rect := TRectF.Create(1, 1, 1, 1);
  FList := TCMClassList.Create(Self);
  FList.Parent := Holder;
  FList.Align := TAlignLayout.Client;
  FList.SetHeaders(Tr('Classe'), Tr('Profundidade'), Tr('Filhas'), Tr('Métodos'), Tr('Ficheiro'));
  FList.EmptyText := Tr('Analise um projeto para ver as classes.');
  FList.OnSort := SortClick;
  FList.OnOpen := OpenClick;
  ShowSummary;
  ShowNote;
end;

destructor TClassesPage.Destroy;
begin
  FreeAndNil(FHier);
  inherited;
end;

procedure TClassesPage.ApplyTheme;
begin
  FSearch.ApplyTheme;
  ShowRows;
  FList.Repaint;
end;

function TClassesPage.ProjectName: string;
begin
  if FHost.CurrentProfile <> nil then
    Result := FHost.CurrentProfile.Name
  else if FHost.CurrentScan <> nil then
    Result := TPath.GetFileName(ExcludeTrailingPathDelimiter(FHost.CurrentScan.Root))
  else
    Result := '';
end;

procedure TClassesPage.SearchChanged(Sender: TObject);
begin
  ShowRows;
end;

procedure TClassesPage.OptionChanged(Sender: TObject);
begin
  ShowRows;
end;

// 1.o clique: ordena (nome A-Z, numeros do maior para o menor); 2.o: inverte; 3.o: volta a ordem da arvore
procedure TClassesPage.SortClick(Sender: TObject; AColumn: Integer);
begin
  if AColumn <> FSortColumn then
  begin
    FSortColumn := AColumn;
    FSortDesc := AColumn <> 0;
  end
  else if FSortDesc = (AColumn <> 0) then
    FSortDesc := not FSortDesc
  else
    FSortColumn := -1;
  ShowRows;
end;

procedure TClassesPage.OpenClick(Sender: TObject; ATag: Integer);
var
  N: TClassNode;
  Idx: Integer;
begin
  if (FHier = nil) or (ATag < 0) or (ATag >= FHier.Nodes.Count) or (FHost.CurrentScan = nil) then
    Exit;
  N := FHier.Nodes[ATag];
  for Idx := 0 to FHost.CurrentScan.Units.Count - 1 do
    if SameText(FHost.CurrentScan.Units[Idx].Path, N.UnitPath) then
    begin
      FHost.OpenCodeAt(FHost.CurrentScan.Units[Idx], N.Line);
      Exit;
    end;
end;

procedure TClassesPage.Invalidate;
begin
  FStale := True;
  FreeAndNil(FHier);
  FSearch.Text := '';
  FSortColumn := -1;
  ShowSummary;
  ShowRows;
  ShowNote;
end;

procedure TClassesPage.Activate;
begin
  if FStale and (FHost.CurrentScan <> nil) then
    Build
  else if FHost.CurrentScan = nil then
    FList.EmptyText := Tr('Analise um projeto para ver as classes.');
end;

procedure TClassesPage.Build;
begin
  FreeAndNil(FHier);
  FHier := BuildHierarchy(FHost.CurrentScan);
  FStale := False;
  FList.EmptyText := Tr('Este projeto não declara classes.');
  ShowSummary;
  ShowRows;
  ShowNote;
end;

{ cartoes e lista }

procedure TClassesPage.ShowSummary;
var
  Rows: TArray<TKeyValue>;
  Dash: string;
  N: TClassNode;
  Minimum: Integer;
begin
  Dash := '—';
  if FHier = nil then
    Rows := [KV(Tr('Classes'), Dash), KV(Tr('Interfaces'), Dash), KV(Tr('Records'), Dash), KV(Tr('Profundidade máxima'), Dash),
      KV(Tr('Profundidade média'), Dash)]
  else
  begin
    Minimum := 0;
    for N in FHier.Nodes do
      if not N.Exact then
        Inc(Minimum);
    Rows := [KV(Tr('Classes'), IntToStr(FHier.Count(ckClass) + FHier.Count(ckObject))),
      KV(Tr('Interfaces'), IntToStr(FHier.Count(ckInterface))), KV(Tr('Records'), IntToStr(FHier.Records)),
      KV(Tr('Profundidade máxima'), IntToStr(FHier.MaxDepth), DepthLevel(FHier.MaxDepth) = cxHigh),
      KV(Tr('Profundidade média'), FormatFloat('0.0', FHier.AverageDepth))];
    if Minimum > 0 then
      Rows := Rows + [KV(Tr('Com profundidade mínima'), IntToStr(Minimum))];
  end;
  FSummary.SetRows(Rows);
  TCMPanel(FSummary.Parent).Height := 16 + 16 + 28 + 8 + FSummary.Height;
end;

function TClassesPage.Ordered: TArray<TClassNode>;
var
  List: TList<TClassNode>;
  Desc: Boolean;
begin
  if FSortColumn < 0 then
    Exit(FHier.TreeOrder);
  List := TList<TClassNode>.Create;
  try
    List.AddRange(FHier.Nodes);
    Desc := FSortDesc;
    List.Sort(TComparer<TClassNode>.Construct(
      function(const A, B: TClassNode): Integer
      begin
        case FSortColumn of
          0: Result := CompareText(A.Name, B.Name);
          1: Result := A.Depth - B.Depth;
          2: Result := A.Children - B.Children;
        else
          Result := A.Methods - B.Methods;
        end;
        if Result = 0 then
          Result := CompareText(A.Name, B.Name)
        else if Desc then
          Result := -Result;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

procedure TClassesPage.ShowRows;
var
  Rows: TArray<TClassRow>;
  N: TClassNode;
  Q, Chain: string;
  R: TClassRow;
  Part: string;
begin
  FList.SetSort(FSortColumn, FSortDesc);
  if FHier = nil then
  begin
    FList.SetRows(nil);
    Exit;
  end;
  Q := LowerCase(Trim(FSearch.Text));
  for N in Ordered do
  begin
    if (N.Kind = ckInterface) and not FInterfacesSwitch.Checked then
      Continue;
    if (Q <> '') and (Pos(Q, LowerCase(N.Name)) = 0) and (Pos(Q, LowerCase(N.Ancestor)) = 0) and
       (Pos(Q, LowerCase(N.UnitPath)) = 0) then
      Continue;
    R := Default(TClassRow);
    R.Name := N.Name;
    if (FSortColumn < 0) and (Q = '') then
      R.Indent := Max(0, N.ProjectDepth - 1);
    case N.Kind of
      ckInterface: R.KindText := Tr('interface');
      ckObject: R.KindText := Tr('objeto');
    end;
    R.DepthText := DepthText(N);
    R.DepthColor := DepthColor(N.Depth);
    R.Children := N.Children;
    R.Methods := N.Methods;
    R.FileText := N.UnitPath + ':' + IntToStr(N.Line);
    R.Tag := FHier.Nodes.IndexOf(N);
    Chain := '';
    for Part in N.Chain do
    begin
      if Chain <> '' then
        Chain := Chain + ' → ';
      Chain := Chain + Part;
    end;
    if N.ExternalBase <> '' then
    begin
      Chain := Chain + ' → ' + N.ExternalBase;
      if not N.Exact then
        Chain := Chain + ' …';
    end;
    R.Hint := Chain + sLineBreak + Tr('Profundidade') + ': ' + DepthText(N);
    if N.Descendants > 0 then
      R.Hint := R.Hint + sLineBreak + Tr('Descendentes') + ': ' + IntToStr(N.Descendants);
    if Length(N.Interfaces) > 0 then
      R.Hint := R.Hint + sLineBreak + Tr('Interfaces') + ': ' + string.Join(', ', N.Interfaces);
    R.Hint := R.Hint + sLineBreak + R.FileText;
    Rows := Rows + [R];
  end;
  FList.SetRows(Rows);
end;

procedure TClassesPage.ShowNote;
begin
  if FHier = nil then
    FNote.Text := ''
  else
    FNote.Text := Tr('Duplo clique numa classe abre o código na sua declaração. Os títulos ordenam a lista.') + sLineBreak +
      sLineBreak + Tr('Um «>=» na profundidade quer dizer que a classe herda de uma classe de fora do projeto de que não se conhece a cadeia: a profundidade real é, pelo menos, essa.');
end;

{ exportar }

procedure TClassesPage.ExportMdClick(Sender: TObject);
begin
  DoExport(ExportMd);
end;

procedure TClassesPage.ExportCsvClick(Sender: TObject);
begin
  DoExport(ExportCsv);
end;

procedure TClassesPage.WriteExport(AKind: Integer; const APath: string);
var
  Content: string;
begin
  if FHier = nil then
    raise Exception.Create('sem classes');
  if AKind = ExportMd then
    Content := ClassesMarkdown(FHier, ProjectName)
  else
    Content := ClassesCsv(FHier);
  TFile.WriteAllText(APath, Content, TEncoding.UTF8);
end;

procedure TClassesPage.DoExport(AKind: Integer);
var
  D: TSaveDialog;
  Profile: TProjectProfile;
  Path, Ext: string;
begin
  Profile := FHost.CurrentProfile;
  if (Profile = nil) or (FHier = nil) then
  begin
    FHost.Toast(Tr('Analise um projeto para ver as classes.'));
    Exit;
  end;
  if AKind = ExportMd then
    Ext := '.md'
  else
    Ext := '.csv';
  D := TSaveDialog.Create(nil);
  try
    if AKind = ExportMd then
      D.Filter := 'Markdown (*.md)|*.md'
    else
      D.Filter := 'CSV (*.csv)|*.csv';
    D.FileName := ClassesFileName(ProjectName, Ext);
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
  except
    on E: Exception do
      FHost.Toast(Tr('Falhou a exportação: ') + E.Message);
  end;
end;

end.
