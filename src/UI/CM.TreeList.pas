unit CM.TreeList;

{ Lista virtualizada pintada a mao, usada nas duas vistas:
    lmMap        - arvore de pastas > ficheiros > metodos (so leitura + flags Compila/Sonar)
    lmChecklist  - pastas agrupadas > ficheiros > metodos, com conclusao, prioridade e notas
  So as linhas visiveis sao desenhadas, por isso projectos com milhares de metodos continuam fluidos. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Generics.Collections, System.Generics.Defaults, System.StrUtils, FMX.Types, FMX.Controls, FMX.Graphics,
  CM.Analyzer, CM.Metrics, CM.Store, CM.Stats, CM.GitReview, CM.SonarModel, CM.Theme, CM.Controls;

type
  TListMode = (lmMap, lmChecklist);
  TRowKind = (rkDir, rkFile, rkMethod);
  TElem = (eNone, eCheck, eState, eStar, eCompila, eSonar, ePill, eNote, eRow);
  TReviewFilter = set of TReviewState;

  TRow = record
    Kind: TRowKind;
    Level: Integer;
    Caption: string;
    Key: string;
    U: TUnitInfo;
    M: Integer;
    Top: Single;
    Height: Single;
    CountA: Integer;
    CountB: Integer;
  end;

  TRowLayout = record
    Check, State, Star, Compila, Sonar, Pill, Note, Tag, NameR, KindR, Caret: TRectF;
  end;

  TCMHintEvent = procedure(const AText: string) of object;
  TCMNoteEvent = procedure(AUnit: TUnitInfo) of object;

  TDirNode = class
  public
    Name: string;
    Path: string;
    Dirs: TObjectList<TDirNode>;
    Files: TList<TUnitInfo>;
    FileCount: Integer;
    constructor Create(const AName, APath: string);
    destructor Destroy; override;
  end;

  TCMTreeList = class(TCMControl)
  private
    FMode: TListMode;
    FScan: TProjectScan;
    FState: TProgressState;
    FRoot: TDirNode;
    FGroups: TObjectDictionary<string, TList<TUnitInfo>>;
    FGroupKeys: TList<string>;
    FRows: TList<TRow>;
    FCollapsed: THashSet<string>;
    FOpen: THashSet<string>;
    FLayers: THashSet<string>;
    FQuery: string;
    FStarOnly: Boolean;
    FReviewFilter: TReviewFilter;     // vazio = todos os estados
    FStale: THashSet<string>;         // ficheiros revistos que mudaram desde a revisao (Git)
    FStaleHints: TDictionary<string, string>;   // dicas ja calculadas (cada uma custa uma chamada ao git)
    FStaleOnly: Boolean;
    FGitRoot, FGitHead: string;
    FSonar: TSonarSnapshot;           // nao e nosso; nil sem Sonar
    FScrollY: Single;
    FContentH: Single;
    FHoverRow: Integer;
    FDragThumb: Boolean;
    FDragOffset: Single;
    FOnChanged: TNotifyEvent;
    FOnEditNote: TCMNoteEvent;
    FOnHint: TCMHintEvent;
    FEmptyText: string;
    FFlash: TDictionary<string, UInt64>;   // chave -> instante (ms) em que o destaque termina
    FFlashTimer: TTimer;
    procedure FlashTick(Sender: TObject);
    function FlashAlpha(const AKey: string): Single;
    procedure SetQuery(const Value: string);
    procedure SetStarOnly(const Value: Boolean);
    procedure BuildStructure;
    procedure Rebuild;
    procedure AddRow(AKind: TRowKind; ALevel: Integer; const ACaption, AKey: string; AUnit: TUnitInfo;
      AMethod: Integer; ACountA, ACountB: Integer);
    function FileMatchesMap(U: TUnitInfo): Boolean;
    function NodeHasMatch(ANode: TDirNode): Boolean;
    procedure EmitMapNode(ANode: TDirNode; ALevel: Integer);
    procedure EmitMethods(U: TUnitInfo; ALevel: Integer);
    procedure BuildMapRows;
    procedure BuildChecklistRows;
    function FilePasses(U: TUnitInfo): Boolean;
    function ViewWidth: Single;
    function MaxScroll: Single;
    procedure ClampScroll;
    function RowAtContentY(AY: Single): Integer;
    function LayoutRow(const ARow: TRow; ATop: Single): TRowLayout;
    function PillText(const ARow: TRow): string;
    procedure HitTestAt(X, Y: Single; out ARowIdx: Integer; out AElem: TElem);
    procedure DrawRow(const ARow: TRow; ATop: Single; AHover: Boolean);
    procedure DrawDirRow(const ARow: TRow; const L: TRowLayout; ATop, AWidth: Single);
    procedure DrawFileRow(const ARow: TRow; const L: TRowLayout);
    procedure DrawMethodRow(const ARow: TRow; const L: TRowLayout);
    function OverflowHint(const ARow: TRow; X, Y: Single): string;
    function DrawPlanTag(ARight, ACenterY: Single; AStatus: TPlanStatus; AMoved: Boolean): Single;
    // etiqueta de contorno encostada a direita; devolve a largura ocupada
    function DrawTag(ARight, ACenterY: Single; const AText: string; AColor: TAlphaColor): Single;
    function StaleHintFor(const ARow: TRow): string;
    // linhas e complexidade do metodo, encostadas a direita em ARight; devolve a largura ocupada
    function DrawMetrics(ARight, ACenterY: Single; const AMethod: TMethodInfo): Single;
    procedure DrawFlag(const ARect: TRectF; const ALabel: string; AChecked: Boolean; AColor: TAlphaColor);
    procedure DrawCheckbox(const ARect: TRectF; AChecked, APending: Boolean; AColor: TAlphaColor);
    // pontinho do estado de revisao: anel (por rever/feito), anel com miolo (em revisao) ou cheio com ! (alterar)
    procedure DrawReviewDot(const ARect: TRectF; AState: TReviewState);
    function ReviewMatches(U: TUnitInfo; AMethod: Integer): Boolean;
    function RowReview(const ARow: TRow): TReviewState;
    procedure DrawScrollbar;
    function ThumbRect: TRectF;
    procedure SetFont(ASize: Single; const AFamily: string; AStyle: TFontStyles = []);
    procedure ApplyClick(const ARow: TRow; AElem: TElem);
    procedure Changed;
    function HintFor(const ARow: TRow; AElem: TElem): string;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean); override;
    procedure DoMouseLeave; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadData(AScan: TProjectScan; AState: TProgressState);
    procedure Refresh;
    // volta a construir a estrutura depois de a analise ter sido alterada no proprio objecto,
    // mantendo pastas fechadas, metodos abertos, filtros e posicao de scroll
    procedure ReloadKeepView;
    // passa a mostrar outra analise (ex.: a vista cruzada com o plano) mantendo pastas abertas e scroll
    procedure UseScan(AScan: TProjectScan);
    // realca durante uns segundos (esmorece) ficheiros e metodos: chaves de FlashKeyFile/FlashKeyMethod
    procedure MarkChanged(const AKeys: TArray<string>);
    class function FlashKeyFile(const APath: string): string; static;
    class function FlashKeyMethod(const APath, AMethodName: string): string; static;
    procedure ExpandAll;
    procedure CollapseAll;
    procedure ExpandMethods;
    procedure CollapseMethods;
    procedure ResetFilters;
    procedure ToggleLayer(const ALayer: string);
    function LayerActive(const ALayer: string): Boolean;
    // filtra a checklist pelo estado de revisao (varios estados somam-se; nenhum = todos)
    // revisoes desactualizadas segundo o Git: AStale = caminhos dos ficheiros revistos que mudaram; AHead = commit
    // actual (fica registado em cada revisao nova); AHead = '' sem Git
    procedure SetGit(const ARoot, AHead: string; AStale: THashSet<string>);
    procedure SetStaleOnly(AValue: Boolean);
    // problemas abertos no SonarQube por ficheiro (nil = sem Sonar); a lista nao fica dona
    procedure SetSonar(ASnapshot: TSonarSnapshot);
    property StaleOnly: Boolean read FStaleOnly;
    property GitHead: string read FGitHead;
    procedure ToggleReviewState(AState: TReviewState);
    function ReviewStateActive(AState: TReviewState): Boolean;
    function BuildMarkdown(const AProjectName: string): string;
    property Mode: TListMode read FMode write FMode;
    property Query: string read FQuery write SetQuery;
    property StarOnly: Boolean read FStarOnly write SetStarOnly;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnEditNote: TCMNoteEvent read FOnEditNote write FOnEditNote;
    property OnHint: TCMHintEvent read FOnHint write FOnHint;
    property EmptyText: string read FEmptyText write FEmptyText;
  end;

implementation


uses
  CM.Lang;
const
  DirH = 42;
  FileH = 38;
  MethodH = 30;
  IndentW = 22;
  ScrollW = 14;

{ TDirNode }

constructor TDirNode.Create(const AName, APath: string);
begin
  inherited Create;
  Name := AName;
  Path := APath;
  Dirs := TObjectList<TDirNode>.Create(True);
  Files := TList<TUnitInfo>.Create;
end;

destructor TDirNode.Destroy;
begin
  Dirs.Free;
  Files.Free;
  inherited;
end;

{ TCMTreeList }

constructor TCMTreeList.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  ClipChildren := True;
  FRows := TList<TRow>.Create;
  FCollapsed := THashSet<string>.Create;
  FOpen := THashSet<string>.Create;
  FLayers := THashSet<string>.Create;
  FStale := THashSet<string>.Create;
  FStaleHints := TDictionary<string, string>.Create;
  FGroups := TObjectDictionary<string, TList<TUnitInfo>>.Create([doOwnsValues]);
  FGroupKeys := TList<string>.Create;
  FHoverRow := -1;
  FEmptyText := Tr('Sem dados para mostrar.');
  FFlash := TDictionary<string, UInt64>.Create;
  FFlashTimer := TTimer.Create(Self);
  FFlashTimer.Enabled := False;
  FFlashTimer.Interval := 80;
  FFlashTimer.OnTimer := FlashTick;
end;

destructor TCMTreeList.Destroy;
begin
  FFlashTimer.Enabled := False;
  FFlash.Free;
  FRoot.Free;
  FGroups.Free;
  FGroupKeys.Free;
  FRows.Free;
  FCollapsed.Free;
  FOpen.Free;
  FLayers.Free;
  FStale.Free;
  FStaleHints.Free;
  inherited;
end;

procedure TCMTreeList.SetQuery(const Value: string);
begin
  FQuery := LowerCase(Trim(Value));
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.SetStarOnly(const Value: Boolean);
begin
  FStarOnly := Value;
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.LoadData(AScan: TProjectScan; AState: TProgressState);
begin
  FScan := AScan;
  FState := AState;
  FCollapsed.Clear;
  FOpen.Clear;
  FLayers.Clear;
  FScrollY := 0;
  BuildStructure;
  Rebuild;
end;

procedure TCMTreeList.Refresh;
begin
  Rebuild;
end;

procedure TCMTreeList.UseScan(AScan: TProjectScan);
begin
  FScan := AScan;
end;

procedure TCMTreeList.ReloadKeepView;
begin
  BuildStructure;
  Rebuild;
end;

const
  FlashMs = 7000;

class function TCMTreeList.FlashKeyFile(const APath: string): string;
begin
  Result := APath;
end;

class function TCMTreeList.FlashKeyMethod(const APath, AMethodName: string): string;
begin
  Result := APath + '|' + AMethodName;
end;

procedure TCMTreeList.MarkChanged(const AKeys: TArray<string>);
var
  K: string;
  Until_: UInt64;
begin
  if Length(AKeys) = 0 then
    Exit;
  Until_ := TThread.GetTickCount64 + FlashMs;
  for K in AKeys do
    FFlash.AddOrSetValue(K, Until_);
  FFlashTimer.Enabled := True;
  Repaint;
end;

// 1 = acabou de mudar, 0 = ja passou
function TCMTreeList.FlashAlpha(const AKey: string): Single;
var
  Until_, Now_: UInt64;
begin
  Result := 0;
  if (FFlash.Count = 0) or not FFlash.TryGetValue(AKey, Until_) then
    Exit;
  Now_ := TThread.GetTickCount64;
  if Now_ >= Until_ then
    Exit;
  Result := (Until_ - Now_) / FlashMs;
  Result := Min(1, Result * 1.6);          // fica cheio no inicio e esmorece no fim
end;

procedure TCMTreeList.FlashTick(Sender: TObject);
var
  Now_: UInt64;
  K: string;
  Expired: TList<string>;
begin
  Now_ := TThread.GetTickCount64;
  Expired := TList<string>.Create;
  try
    for K in FFlash.Keys do
      if FFlash[K] <= Now_ then
        Expired.Add(K);
    for K in Expired do
      FFlash.Remove(K);
  finally
    Expired.Free;
  end;
  if FFlash.Count = 0 then
    FFlashTimer.Enabled := False;
  Repaint;
end;

procedure TCMTreeList.BuildStructure;
var
  U: TUnitInfo;
  Node, Child: TDirNode;
  Segs: TArray<string>;
  Seg, Acc: string;
  List: TList<TUnitInfo>;
  Key: string;

  procedure SortNode(N: TDirNode);
  var
    C: TDirNode;
  begin
    N.Dirs.Sort(TComparer<TDirNode>.Construct(
      function(const A, B: TDirNode): Integer
      begin
        Result := CompareText(A.Name, B.Name);
      end));
    N.Files.Sort(TComparer<TUnitInfo>.Construct(
      function(const A, B: TUnitInfo): Integer
      begin
        Result := CompareText(A.FileName, B.FileName);
      end));
    for C in N.Dirs do
      SortNode(C);
  end;

  function FindChild(N: TDirNode; const AName: string): TDirNode;
  var
    C: TDirNode;
  begin
    for C in N.Dirs do
      if C.Name = AName then
        Exit(C);
    Result := nil;
  end;

  function CountFiles(N: TDirNode): Integer;
  var
    C: TDirNode;
  begin
    Result := N.Files.Count;
    for C in N.Dirs do
      Inc(Result, CountFiles(C));
    N.FileCount := Result;
  end;

begin
  FreeAndNil(FRoot);
  FGroups.Clear;
  FGroupKeys.Clear;
  if FScan = nil then
    Exit;
  FRoot := TDirNode.Create('', '');
  for U in FScan.Units do
  begin
    // arvore (vista Mapa)
    Node := FRoot;
    if U.Dir <> '' then
    begin
      Segs := U.Dir.Split(['/']);
      Acc := '';
      for Seg in Segs do
      begin
        if Acc = '' then Acc := Seg else Acc := Acc + '/' + Seg;
        Child := FindChild(Node, Seg);
        if Child = nil then
        begin
          Child := TDirNode.Create(Seg, Acc);
          Node.Dirs.Add(Child);
        end;
        Node := Child;
      end;
    end;
    Node.Files.Add(U);

    // grupos por pasta (vista Checklist)
    Key := U.Dir;
    if not FGroups.TryGetValue(Key, List) then
    begin
      List := TList<TUnitInfo>.Create;
      FGroups.Add(Key, List);
      FGroupKeys.Add(Key);
    end;
    List.Add(U);
  end;
  SortNode(FRoot);
  CountFiles(FRoot);
  FGroupKeys.Sort(TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareStr(A, B);
    end));
end;

procedure TCMTreeList.AddRow(AKind: TRowKind; ALevel: Integer; const ACaption, AKey: string;
  AUnit: TUnitInfo; AMethod: Integer; ACountA, ACountB: Integer);
var
  R: TRow;
begin
  R.Kind := AKind;
  R.Level := ALevel;
  R.Caption := ACaption;
  R.Key := AKey;
  R.U := AUnit;
  R.M := AMethod;
  R.CountA := ACountA;
  R.CountB := ACountB;
  R.Top := FContentH;
  case AKind of
    rkDir: R.Height := DirH;
    rkFile: R.Height := FileH;
  else
    R.Height := MethodH;
  end;
  FContentH := FContentH + R.Height;
  FRows.Add(R);
end;

function TCMTreeList.FileMatchesMap(U: TUnitInfo): Boolean;
var
  M: TMethodInfo;
begin
  if FQuery = '' then
    Exit(True);
  if Pos(FQuery, LowerCase(U.FileName)) > 0 then
    Exit(True);
  for M in U.Methods do
    if (Pos(FQuery, LowerCase(M.Name)) > 0) or (Pos(FQuery, LowerCase(M.Sig)) > 0) then
      Exit(True);
  Result := False;
end;

function TCMTreeList.NodeHasMatch(ANode: TDirNode): Boolean;
var
  C: TDirNode;
  U: TUnitInfo;
begin
  if Pos(FQuery, LowerCase(ANode.Name)) > 0 then
    Exit(True);
  for U in ANode.Files do
    if FileMatchesMap(U) then
      Exit(True);
  for C in ANode.Dirs do
    if NodeHasMatch(C) then
      Exit(True);
  Result := False;
end;

procedure TCMTreeList.EmitMethods(U: TUnitInfo; ALevel: Integer);
var
  I: Integer;
begin
  if FOpen.Contains(U.Path) then
    for I := 0 to High(U.Methods) do
      if (FReviewFilter = []) or (FMode <> lmChecklist) or ReviewMatches(U, I) then
        AddRow(rkMethod, ALevel, U.Methods[I].Sig, U.Path, U, I, 0, 0);
end;

procedure TCMTreeList.EmitMapNode(ANode: TDirNode; ALevel: Integer);
var
  C: TDirNode;
  U: TUnitInfo;
begin
  for C in ANode.Dirs do
  begin
    if (FQuery <> '') and not NodeHasMatch(C) then
      Continue;
    AddRow(rkDir, ALevel, C.Name + '/', C.Path, nil, -1, C.FileCount, 0);
    if (FQuery <> '') or not FCollapsed.Contains(C.Path) then
      EmitMapNode(C, ALevel + 1);
  end;
  for U in ANode.Files do
    if FileMatchesMap(U) then
    begin
      AddRow(rkFile, ALevel, U.FileName, U.Path, U, -1, 0, 0);
      EmitMethods(U, ALevel + 1);
    end;
end;

procedure TCMTreeList.BuildMapRows;
begin
  if FRoot <> nil then
    EmitMapNode(FRoot, 0);
end;

function TCMTreeList.FilePasses(U: TUnitInfo): Boolean;
var
  S: TUnitState;
begin
  if (FQuery <> '') and (Pos(FQuery, LowerCase(U.Path)) = 0) then
    Exit(False);
  if FStarOnly then
  begin
    S := FState.Find(U.Path);
    if (S = nil) or not S.Star then
      Exit(False);
  end;
  if (FLayers.Count > 0) and not FLayers.Contains(U.Layer) then
    Exit(False);
  if (FReviewFilter <> []) and (FMode = lmChecklist) and not ReviewMatches(U, -1) then
    Exit(False);
  if FStaleOnly and (FMode = lmChecklist) and not FStale.Contains(U.Path) then
    Exit(False);
  Result := True;
end;

// AMethod >= 0: esse metodo tem um estado do filtro; -1: o ficheiro ou algum dos seus metodos tem
function TCMTreeList.ReviewMatches(U: TUnitInfo; AMethod: Integer): Boolean;
var
  S: TUnitState;
  I: Integer;
begin
  if AMethod >= 0 then
    Exit(ReviewOfMethod(FState.Find(U.Path), U.Methods[AMethod].Name) in FReviewFilter);
  if ReviewOfUnit(U, FState) in FReviewFilter then
    Exit(True);
  S := FState.Find(U.Path);
  for I := 0 to High(U.Methods) do
    if ReviewOfMethod(S, U.Methods[I].Name) in FReviewFilter then
      Exit(True);
  Result := False;
end;

function TCMTreeList.RowReview(const ARow: TRow): TReviewState;
begin
  if ARow.Kind = rkMethod then
    Result := ReviewOfMethod(FState.Find(ARow.U.Path), ARow.U.Methods[ARow.M].Name)
  else
    Result := ReviewOfUnit(ARow.U, FState);
end;

procedure TCMTreeList.BuildChecklistRows;
var
  Key, Caption: string;
  U: TUnitInfo;
  Group: TList<TUnitInfo>;
  Passing: TList<TUnitInfo>;
  DoneCount: Integer;
begin
  Passing := TList<TUnitInfo>.Create;
  try
    for Key in FGroupKeys do
    begin
      Group := FGroups[Key];
      Passing.Clear;
      for U in Group do
        if FilePasses(U) then
          Passing.Add(U);
      if Passing.Count = 0 then
        Continue;
      DoneCount := 0;
      for U in Group do
        if UnitDone(U, FState) then
          Inc(DoneCount);
      if Key = '' then Caption := Tr('(raiz)') else Caption := Key;
      AddRow(rkDir, 0, Caption, Key, nil, -1, DoneCount, Group.Count);
      if not FCollapsed.Contains(Key) then
        for U in Passing do
        begin
          AddRow(rkFile, 0, U.FileName, U.Path, U, -1, 0, 0);
          EmitMethods(U, 1);
        end;
    end;
  finally
    Passing.Free;
  end;
end;

procedure TCMTreeList.Rebuild;
begin
  FRows.Clear;
  FContentH := 0;
  FHoverRow := -1;
  if (FScan <> nil) and (FState <> nil) then
  begin
    if FMode = lmMap then
      BuildMapRows
    else
      BuildChecklistRows;
  end;
  ClampScroll;
  Repaint;
end;

function TCMTreeList.ViewWidth: Single;
begin
  Result := Width - ScrollW;
end;

function TCMTreeList.MaxScroll: Single;
begin
  Result := Max(0, FContentH + 8 - Height);
end;

procedure TCMTreeList.ClampScroll;
begin
  FScrollY := EnsureRange(FScrollY, 0, MaxScroll);
end;

procedure TCMTreeList.Resize;
begin
  inherited;
  ClampScroll;
end;

function TCMTreeList.RowAtContentY(AY: Single): Integer;
var
  Lo, Hi, Mid: Integer;
begin
  Result := -1;
  if (FRows.Count = 0) or (AY < 0) or (AY >= FContentH) then
    Exit;
  Lo := 0;
  Hi := FRows.Count - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if AY < FRows[Mid].Top then
      Hi := Mid - 1
    else if AY >= FRows[Mid].Top + FRows[Mid].Height then
      Lo := Mid + 1
    else
      Exit(Mid);
  end;
end;

procedure TCMTreeList.SetFont(ASize: Single; const AFamily: string; AStyle: TFontStyles);
begin
  Canvas.Font.Family := AFamily;
  Canvas.Font.Size := ASize;
  Canvas.Font.Style := AStyle;
end;

function TCMTreeList.PillText(const ARow: TRow): string;
var
  N: Integer;
begin
  N := Length(ARow.U.Methods);
  if FMode = lmMap then
  begin
    Result := TrCount(N, 'método', 'métodos');
  end
  else
    Result := Format('%d/%d', [MethodsDoneCount(ARow.U, FState), N]);
end;

function TCMTreeList.LayoutRow(const ARow: TRow; ATop: Single): TRowLayout;
var
  W, X, H, Base, PillW: Single;

  function Box(ALeft, AWidth, AHeight: Single): TRectF;
  begin
    Result := TRectF.Create(ALeft, ATop + (H - AHeight) / 2, ALeft + AWidth, ATop + (H - AHeight) / 2 + AHeight);
  end;

begin
  Result := Default(TRowLayout);
  W := ViewWidth;
  H := ARow.Height;
  Base := 14 + ARow.Level * IndentW;
  case ARow.Kind of
    rkDir:
      begin
        Result.Caret := Box(Base, 16, 16);
        Result.NameR := TRectF.Create(Base + 26, ATop, W - 150, ATop + H);
      end;
    rkFile:
      begin
        X := W - 12;
        if FMode = lmChecklist then
        begin
          Result.Note := Box(X - 28, 28, 28);
          X := X - 28 - 4;
        end;
        if Length(ARow.U.Methods) > 0 then
        begin
          PillW := IfThen(FMode = lmMap, 112, 78);   // largura fixa: mantem as colunas C/S alinhadas
          Result.Pill := Box(X - PillW, PillW, 22);
          X := X - PillW - 8;
        end;
        Result.Sonar := Box(X - 34, 34, 22);
        X := X - 34;
        Result.Compila := Box(X - 34, 34, 22);
        X := X - 34;
        if FMode = lmChecklist then
        begin
          Result.State := Box(X - 26, 22, 22);
          X := X - 26;
          Result.Star := Box(X - 28, 28, 28);
          X := X - 28;
        end;
        if FMode = lmChecklist then
        begin
          Result.Check := Box(Base, 18, 18);
          SetFont(10, MonoFont);
          PillW := Canvas.TextWidth(ARow.U.Layer) + 16;
          Result.Tag := Box(Base + 28, PillW, 18);
          Result.NameR := TRectF.Create(Base + 28 + PillW + 10, ATop, X - 8, ATop + H);
        end
        else
          Result.NameR := TRectF.Create(Base + 18, ATop, X - 8, ATop + H);
      end;
    rkMethod:
      begin
        X := Base + 12;
        if FMode = lmChecklist then
        begin
          Result.Check := Box(X, 16, 16);
          X := X + 26;
          Result.State := Box(X - 2, 20, 20);
          X := X + 26;
        end;
        Result.Compila := Box(X, 34, 22);
        Result.Sonar := Box(X + 34, 34, 22);
        Result.KindR := TRectF.Create(X + 76, ATop, X + 76 + 108, ATop + H);
        Result.NameR := TRectF.Create(X + 76 + 114, ATop, W - 12, ATop + H);
      end;
  end;
end;

procedure TCMTreeList.HitTestAt(X, Y: Single; out ARowIdx: Integer; out AElem: TElem);
var
  L: TRowLayout;
  Row: TRow;
  Pt: TPointF;
begin
  AElem := eNone;
  ARowIdx := RowAtContentY(Y + FScrollY);
  if (ARowIdx < 0) or (X > ViewWidth) then
  begin
    ARowIdx := -1;
    Exit;
  end;
  Row := FRows[ARowIdx];
  AElem := eRow;
  L := LayoutRow(Row, Row.Top - FScrollY);
  Pt := PointF(X, Y);
  case Row.Kind of
    rkFile:
      begin
        if (FMode = lmChecklist) and L.Check.Contains(Pt) then AElem := eCheck
        else if (FMode = lmChecklist) and L.State.Contains(Pt) then AElem := eState
        else if (FMode = lmChecklist) and L.Star.Contains(Pt) then AElem := eStar
        else if L.Compila.Contains(Pt) then AElem := eCompila
        else if L.Sonar.Contains(Pt) then AElem := eSonar
        else if (Length(Row.U.Methods) > 0) and L.Pill.Contains(Pt) then AElem := ePill
        else if (FMode = lmChecklist) and L.Note.Contains(Pt) then AElem := eNote;
      end;
    rkMethod:
      begin
        if (FMode = lmChecklist) and L.Check.Contains(Pt) then AElem := eCheck
        else if (FMode = lmChecklist) and L.State.Contains(Pt) then AElem := eState
        else if L.Compila.Contains(Pt) then AElem := eCompila
        else if L.Sonar.Contains(Pt) then AElem := eSonar;
      end;
  end;
end;

function TCMTreeList.HintFor(const ARow: TRow; AElem: TElem): string;
begin
  Result := '';
  case AElem of
    eCheck:
      if (ARow.Kind = rkFile) and (Length(ARow.U.Methods) > 0) then
        Result := Tr('Concluída automaticamente quando todos os métodos estiverem marcados')
      else if ARow.Kind = rkMethod then
        Result := Tr('Método revisto')
      else
        Result := Tr('Marcar como concluída');
    eState:
      if (ARow.Kind = rkFile) and (Length(ARow.U.Methods) > 0) then
        Result := Tr('Estado: ') + ReviewText(RowReview(ARow)) + Tr(' (vem dos métodos)')
      else
        Result := Tr('Estado: ') + ReviewText(RowReview(ARow)) + Tr(' — clica para mudar');
    eStar: Result := Tr('Marcar prioridade');
    eCompila: if ARow.Kind = rkMethod then Result := Tr('Método compila sem erros') else Result := Tr('Compila sem erros');
    eSonar: if ARow.Kind = rkMethod then Result := Tr('Método aprovado no SonarQube') else Result := Tr('SonarQube aprovado');
    ePill: Result := Tr('Mostrar/ocultar os métodos desta unit');
    eNote: Result := Tr('Nota');
  end;
end;

function PlanTagText(AStatus: TPlanStatus; AMoved: Boolean): string;
begin
  case AStatus of
    psPlanned: Result := Tr('PLANEADO');
    psExtra: Result := Tr('EXTRA');
    psImplemented: if AMoved then Result := Tr('MOVIDO') else Result := '';
  else
    Result := '';
  end;
end;

function PlanStatusText(AStatus: TPlanStatus; const APlannedPath: string; AIsMethod: Boolean): string;
begin
  Result := '';
  case AStatus of
    psPlanned:
      if AIsMethod then Result := Tr('Planeado: ainda não está implementado')
      else Result := Tr('Planeado: ainda não existe no código');
    psExtra: Result := Tr('Extra: existe no código mas não está no plano');
    psImplemented: if APlannedPath <> '' then Result := Tr('Planeado em ') + APlannedPath;
  end;
end;

// texto da dica de um metodo: as medidas e o estado face ao plano, uma por linha
function MethodHintText(const AMethod: TMethodInfo; const APlanText: string): string;
begin
  Result := MetricsText(AMethod.Lines, AMethod.Complexity);
  if Result <> '' then
    Result := Result + sLineBreak + ShapeText(AMethod.Lines, AMethod.ParamCount, AMethod.Nesting);
  if (Result <> '') and (APlanText <> '') then
    Result := Result + sLineBreak;
  Result := Result + APlanText;
end;

function TCMTreeList.DrawMetrics(ARight, ACenterY: Single; const AMethod: TMethodInfo): Single;
const
  Gap = 6;
var
  LinesTxt, CxTxt: string;
  CxColor: TAlphaColor;
  CxW, LinesW: Single;
  R: TRectF;
begin
  Result := 0;
  if AMethod.Lines <= 0 then
    Exit;
  LinesTxt := IntToStr(AMethod.Lines) + ' l';
  CxTxt := 'cx ' + IntToStr(AMethod.Complexity);
  case ComplexityLevel(AMethod.Complexity) of
    cxHigh: CxColor := Pal.Danger;
    cxModerate: CxColor := Pal.Pending;
  else
    CxColor := Pal.TextFaint;
  end;
  CxW := MeasureText(CxTxt, 10.5, MonoFont);
  LinesW := MeasureText(LinesTxt, 10.5, MonoFont);
  R := TRectF.Create(ARight - CxW, ACenterY - 9, ARight, ACenterY + 9);
  DrawTextRect(Canvas, R, CxTxt, CxColor, 10.5, MonoFont, [], TTextAlign.Trailing);
  R := TRectF.Create(R.Left - Gap - LinesW, ACenterY - 9, R.Left - Gap, ACenterY + 9);
  DrawTextRect(Canvas, R, LinesTxt, Pal.TextFaint, 10.5, MonoFont, [], TTextAlign.Trailing);
  Result := CxW + Gap + LinesW;
end;

// etiqueta (contorno) encostada a direita em ARight; devolve a largura ocupada (0 = sem etiqueta)
function TCMTreeList.DrawPlanTag(ARight, ACenterY: Single; AStatus: TPlanStatus; AMoved: Boolean): Single;
var
  Txt: string;
  C: TAlphaColor;
begin
  Txt := PlanTagText(AStatus, AMoved);
  if Txt = '' then
    Exit(0);
  case AStatus of
    psPlanned: C := Pal.Pending;
    psExtra: C := Pal.FlagCompila;
  else
    C := Pal.TextDim;
  end;
  Result := DrawTag(ARight, ACenterY, Txt, C);
end;

function TCMTreeList.DrawTag(ARight, ACenterY: Single; const AText: string; AColor: TAlphaColor): Single;
var
  R: TRectF;
begin
  Result := MeasureText(AText, 9.5, MonoFont, [TFontStyle.fsBold]) + 14;
  R := TRectF.Create(ARight - Result, ACenterY - 9, ARight, ACenterY + 9);
  StrokeRound(Canvas, R, 9, AColor, 1);
  DrawTextRect(Canvas, R, AText, AColor, 9.5, MonoFont, [TFontStyle.fsBold], TTextAlign.Center);
end;

// dica de um ficheiro que mudou desde a revisao (calculada uma vez e guardada)
function TCMTreeList.StaleHintFor(const ARow: TRow): string;
var
  S: TUnitState;
begin
  if not FStaleHints.TryGetValue(ARow.U.Path, Result) then
  begin
    S := FState.Find(ARow.U.Path);
    if S = nil then
      Result := ''
    else
      Result := StaleHint(FGitRoot, S.Rev, ARow.U.Path);
    FStaleHints.Add(ARow.U.Path, Result);
  end;
end;

// texto completo de um nome/assinatura que foi cortado com "..." (so se o rato estiver sobre ele)
function TCMTreeList.OverflowHint(const ARow: TRow; X, Y: Single): string;
var
  L: TRowLayout;
  Text, Shown, Status: string;
  Size: Single;
  SonarInfo: TSonarFile;
begin
  Result := '';
  case ARow.Kind of
    rkFile:
      begin
        Shown := ARow.U.FileName;
        Text := ARow.U.Path;
        Size := 13;
        Status := PlanStatusText(ARow.U.PlanStatus, ARow.U.PlannedPath, False);
        if (FMode = lmChecklist) and FStale.Contains(ARow.U.Path) then
          Status := StaleHintFor(ARow);
        if (FSonar <> nil) and FSonar.Find(ARow.U.Path, SonarInfo) and (SonarInfo.Issues > 0) then
        begin
          if Status <> '' then
            Status := Status + sLineBreak;
          Status := Status + Format(Tr('SonarQube: %d problemas abertos (a pior: %s)'),
            [SonarInfo.Issues, SeverityText(SonarInfo.Worst)]);
        end;
      end;
    rkMethod:
      begin
        Shown := ARow.U.Methods[ARow.M].Sig;
        Text := Shown;
        Size := 12;
        Status := MethodHintText(ARow.U.Methods[ARow.M],
          PlanStatusText(ARow.U.MethodStatus(ARow.M), '', True));
      end;
  else
    Exit;
  end;
  L := LayoutRow(ARow, ARow.Top - FScrollY);
  if not L.NameR.Contains(PointF(X, Y)) then
    Exit;
  Result := Status;
  if MeasureText(Shown, Size, MonoFont) > L.NameR.Width then
  begin
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + Text;
  end;
end;

procedure TCMTreeList.Changed;
begin
  Rebuild;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TCMTreeList.ApplyClick(const ARow: TRow; AElem: TElem);
var
  S: TUnitState;
  Name: string;

  procedure Flip(ASet: THashSet<string>; const AName: string);
  begin
    if ASet.Contains(AName) then ASet.Remove(AName) else ASet.Add(AName);
  end;

begin
  if ARow.Kind = rkDir then
  begin
    if FCollapsed.Contains(ARow.Key) then FCollapsed.Remove(ARow.Key) else FCollapsed.Add(ARow.Key);
    Rebuild;
    Exit;
  end;
  if AElem in [eNone, eRow] then
    Exit;
  if AElem = ePill then
  begin
    if FOpen.Contains(ARow.U.Path) then FOpen.Remove(ARow.U.Path) else FOpen.Add(ARow.U.Path);
    Rebuild;
    Exit;
  end;
  if AElem = eNote then
  begin
    if Assigned(FOnEditNote) then
      FOnEditNote(ARow.U);
    Exit;
  end;

  if (ARow.Kind = rkFile) and (AElem = eCheck) and (Length(ARow.U.Methods) > 0) then
  begin
    if Assigned(FOnHint) then
      FOnHint(HintFor(ARow, eCheck));
    Exit;
  end;

  if (ARow.Kind = rkFile) and (AElem = eState) and (Length(ARow.U.Methods) > 0) then
  begin
    if Assigned(FOnHint) then
      FOnHint(HintFor(ARow, eState));
    Exit;
  end;

  S := FState.Rec(ARow.U.Path);
  if (AElem in [eCheck, eState]) and (FGitHead <> '') then
  begin
    S.Rev := FGitHead;                   // a revisao passa a ser deste commit
    FStale.Remove(ARow.U.Path);
  end;
  if ARow.Kind = rkFile then
  begin
    case AElem of
      eCheck:
        if ReviewOfUnit(ARow.U, FState) = rsDone then SetFileReview(S, rsPending) else SetFileReview(S, rsDone);
      eState: SetFileReview(S, NextReview(ReviewOfUnit(ARow.U, FState)));
      eStar: S.Star := not S.Star;
      eCompila: S.Compila := not S.Compila;
      eSonar: S.Sonar := not S.Sonar;
    end;
  end
  else
  begin
    Name := ARow.U.Methods[ARow.M].Name;
    case AElem of
      eCompila: Flip(S.MCompila, Name);
      eSonar: Flip(S.MSonar, Name);
      eCheck:
        if S.MDone.Contains(Name) then
          SetMethodReview(ARow.U, S, Name, rsPending)
        else
          SetMethodReview(ARow.U, S, Name, rsDone);
      eState: SetMethodReview(ARow.U, S, Name, NextReview(ReviewOfMethod(S, Name)));
    end;
  end;
  Changed;
end;

procedure TCMTreeList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  E: TElem;
  T: TRectF;
begin
  inherited;
  if Button <> TMouseButton.mbLeft then
    Exit;
  if X > ViewWidth then
  begin
    T := ThumbRect;
    if (MaxScroll > 0) then
      if T.Contains(PointF(X, Y)) then
      begin
        FDragThumb := True;
        FDragOffset := Y - T.Top;
      end
      else
      begin
        FScrollY := FScrollY + Sign(Y - T.CenterPoint.Y) * Height * 0.9;
        ClampScroll;
        Repaint;
      end;
    Exit;
  end;
  HitTestAt(X, Y, Idx, E);
  if Idx >= 0 then
    ApplyClick(FRows[Idx], E);
end;

procedure TCMTreeList.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FDragThumb := False;
end;

procedure TCMTreeList.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Idx: Integer;
  E: TElem;
  Track, T: TRectF;
  Ratio: Single;
begin
  inherited;
  if FDragThumb then
  begin
    T := ThumbRect;
    Track := TRectF.Create(0, 4, 0, Height - 4);
    Ratio := (Y - FDragOffset - Track.Top) / Max(1, (Track.Height - T.Height));
    FScrollY := EnsureRange(Ratio, 0, 1) * MaxScroll;
    Repaint;
    Exit;
  end;
  HitTestAt(X, Y, Idx, E);
  if Idx <> FHoverRow then
  begin
    FHoverRow := Idx;
    Repaint;
  end;
  if (Idx >= 0) and not (E in [eNone]) then
  begin
    if (E = eRow) and (FRows[Idx].Kind <> rkDir) then
      Cursor := crDefault
    else
      Cursor := crHandPoint;
    Hint := HintFor(FRows[Idx], E);
    if (Hint = '') and (E = eRow) then
      Hint := OverflowHint(FRows[Idx], X, Y);
    ShowHint := Hint <> '';
  end
  else
  begin
    Cursor := crDefault;
    Hint := '';
  end;
end;

procedure TCMTreeList.DoMouseLeave;
begin
  inherited;
  FHoverRow := -1;
  Repaint;
end;

procedure TCMTreeList.MouseWheel(Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  inherited;
  FScrollY := FScrollY - WheelDelta / 120 * 72;
  ClampScroll;
  Handled := True;
  Repaint;
end;

function TCMTreeList.ThumbRect: TRectF;
var
  TrackH, ThumbH, Y: Single;
begin
  TrackH := Height - 8;
  ThumbH := Max(36, TrackH * Height / Max(1, FContentH + 8));
  if MaxScroll <= 0 then
    Y := 4
  else
    Y := 4 + (TrackH - ThumbH) * (FScrollY / MaxScroll);
  Result := TRectF.Create(Width - ScrollW + 3, Y, Width - 3, Y + ThumbH);
end;

procedure TCMTreeList.DrawScrollbar;
begin
  if MaxScroll <= 0 then
    Exit;
  FillRound(Canvas, ThumbRect, 4, Fade(Pal.TextFaint, IfThen(FDragThumb, 0.9, 0.55)));
end;

procedure TCMTreeList.DrawFlag(const ARect: TRectF; const ALabel: string; AChecked: Boolean;
  AColor: TAlphaColor);
var
  Box, IR: TRectF;
begin
  Box := TRectF.Create(ARect.Left + 4, ARect.CenterPoint.Y - 7, ARect.Left + 18, ARect.CenterPoint.Y + 7);
  if AChecked then
  begin
    FillRound(Canvas, Box, 4, AColor);
    IR := Box;
    IR.Inflate(-2, -2);
    DrawIcon(Canvas, icCheck, IR, Pal.OnAccent);
  end
  else
  begin
    FillRound(Canvas, Box, 4, Pal.Surface);
    StrokeRound(Canvas, Box, 4, Pal.BorderStrong, 1.5);
  end;
  DrawTextRect(Canvas, TRectF.Create(Box.Right + 4, ARect.Top, ARect.Right, ARect.Bottom), ALabel,
    Pick(AChecked, Pal.TextDim, Pal.TextFaint), 10.5, MonoFont);
end;

procedure TCMTreeList.DrawReviewDot(const ARect: TRectF; AState: TReviewState);
var
  D, Inner: TRectF;
begin
  D := TRectF.Create(ARect.CenterPoint.X - 6, ARect.CenterPoint.Y - 6, ARect.CenterPoint.X + 6,
    ARect.CenterPoint.Y + 6);
  case AState of
    rsInReview:
      begin
        StrokeRound(Canvas, D, 6, Pal.Pending, 1.5);
        Inner := D;
        Inner.Inflate(-3.5, -3.5);
        FillRound(Canvas, Inner, 2.5, Pal.Pending);
      end;
    rsNeedsChange:
      begin
        FillRound(Canvas, D, 6, Pal.Danger);
        DrawTextRect(Canvas, D, '!', Pal.OnAccent, 9.5, MonoFont, [TFontStyle.fsBold], TTextAlign.Center);
      end;
  else
    StrokeRound(Canvas, D, 6, Pal.Border, 1.5);      // por rever (ou feito): so um anel discreto
  end;
end;

procedure TCMTreeList.DrawCheckbox(const ARect: TRectF; AChecked, APending: Boolean; AColor: TAlphaColor);
var
  IR: TRectF;
begin
  if APending then
  begin
    // por concluir (ha metodos por rever): caixa com traco, como uma caixa "indeterminada"
    FillRound(Canvas, ARect, 5, Pal.Surface);
    StrokeRound(Canvas, ARect, 5, Pal.Pending, 1.5);
    IR := TRectF.Create(ARect.CenterPoint.X - 4.5, ARect.CenterPoint.Y - 1.25,
      ARect.CenterPoint.X + 4.5, ARect.CenterPoint.Y + 1.25);
    FillRound(Canvas, IR, 1.25, Pal.Pending);
  end
  else if AChecked then
  begin
    FillRound(Canvas, ARect, 5, AColor);
    IR := ARect;
    IR.Inflate(-2.5, -2.5);
    DrawIcon(Canvas, icCheck, IR, Pal.OnAccent);
  end
  else
  begin
    FillRound(Canvas, ARect, 5, Pal.Surface);
    StrokeRound(Canvas, ARect, 5, Pal.BorderStrong, 1.5);
  end;
end;

procedure TCMTreeList.DrawDirRow(const ARow: TRow; const L: TRowLayout; ATop, AWidth: Single);
var
  P: TPalette;
  Caption: string;
  R, BarR, FillR: TRectF;
  Collapsed: Boolean;
  Slash: Integer;
  Prefix, Last: string;
  PW, Pct: Single;
  Ic: TIconKind;
begin
  P := Pal;
  Collapsed := (FQuery = '') and FCollapsed.Contains(ARow.Key);
  if Collapsed then Ic := icChevronRight else Ic := icChevronDown;
  DrawIcon(Canvas, Ic, L.Caret, P.TextFaint);
  R := L.NameR;
  if FMode = lmMap then
  begin
    SetFont(13, MonoFont, [TFontStyle.fsBold]);
    DrawTextRect(Canvas, R, FitText(Canvas, ARow.Caption, R.Width), P.AccentStrong, 13, MonoFont,
      [TFontStyle.fsBold]);
    R := TRectF.Create(AWidth - 150, ATop, AWidth - 14, ATop + ARow.Height);
    DrawTextRect(Canvas, R, TrCount(ARow.CountA, 'ficheiro', 'ficheiros'),
      P.TextFaint, 11, MonoFont, [], TTextAlign.Trailing);
  end
  else
  begin
    Caption := ARow.Caption;
    Slash := Caption.LastIndexOf('/');
    if Slash >= 0 then
    begin
      Prefix := Copy(Caption, 1, Slash + 1);
      Last := Copy(Caption, Slash + 2, MaxInt);
    end
    else
    begin
      Prefix := '';
      Last := Caption;
    end;
    SetFont(13, MonoFont);
    PW := Canvas.TextWidth(Prefix);
    if PW > R.Width * 0.6 then
    begin
      Prefix := FitText(Canvas, Prefix, R.Width * 0.6);
      PW := Canvas.TextWidth(Prefix);
    end;
    DrawTextRect(Canvas, R, Prefix, P.TextFaint, 13, MonoFont);
    R.Left := R.Left + PW;
    SetFont(13, MonoFont);
    DrawTextRect(Canvas, R, FitText(Canvas, Last, R.Width), P.Text, 13, MonoFont);

    R := TRectF.Create(AWidth - 150, ATop, AWidth - 14, ATop + ARow.Height);
    DrawTextRect(Canvas, R, Format('%d/%d', [ARow.CountA, ARow.CountB]), P.TextFaint, 11, MonoFont,
      [], TTextAlign.Trailing);
    BarR := TRectF.Create(R.Right - 44 - 50, ATop + ARow.Height / 2 - 2, R.Right - 44, ATop + ARow.Height / 2 + 2);
    FillRound(Canvas, BarR, 2, P.Surface2);
    if ARow.CountB > 0 then
      Pct := ARow.CountA / ARow.CountB
    else
      Pct := 0;
    if Pct > 0 then
    begin
      FillR := BarR;
      FillR.Right := FillR.Left + Max(4, BarR.Width * Pct);
      FillRound(Canvas, FillR, 2, P.Accent);
    end;
  end;
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := P.Border;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawLine(PointF(8, ATop + ARow.Height - 0.5), PointF(AWidth - 8, ATop + ARow.Height - 0.5), 1);
end;

procedure TCMTreeList.DrawFileRow(const ARow: TRow; const L: TRowLayout);
var
  P: TPalette;
  S: TUnitState;
  U: TUnitInfo;
  Done, Complete: Boolean;
  Full, Part1, Part2, Base: string;
  R, TR, NR: TRectF;
  W1, W2, TagW: Single;
  NameColor, ExtColor, PillFg, SonarColor: TAlphaColor;
  SonarInfo: TSonarFile;
  Y: Single;
begin
  P := Pal;
  U := ARow.U;
  S := FState.Find(U.Path);
  Done := UnitDone(U, FState);
  NameColor := Pick(Done and (FMode = lmChecklist), P.DoneStrike, P.Text);
  ExtColor := Pick(Done and (FMode = lmChecklist), P.DoneStrike, P.Accent);
  if U.PlanStatus = psPlanned then
  begin
    NameColor := P.TextFaint;       // so no plano: ainda nao existe
    ExtColor := P.TextFaint;
  end;

  if FMode = lmChecklist then
  begin
    DrawCheckbox(L.Check, Done, (Length(U.Methods) > 0) and not Done, P.Accent);
    DrawReviewDot(L.State, RowReview(ARow));
    FillRound(Canvas, L.Tag, 9, P.AccentSoft);
    DrawTextRect(Canvas, L.Tag, U.Layer, P.AccentStrong, 10, MonoFont, [], TTextAlign.Center);
  end
  else
  begin
    FillRound(Canvas, TRectF.Create(L.NameR.Left - 12, L.NameR.CenterPoint.Y - 2.5,
      L.NameR.Left - 7, L.NameR.CenterPoint.Y + 2.5), 2.5, P.TextFaint);
  end;

  // nome + extensao (extensao a cor de destaque)
  NR := L.NameR;
  TagW := DrawPlanTag(NR.Right, NR.CenterPoint.Y, U.PlanStatus, U.PlannedPath <> '');
  if TagW > 0 then
    NR.Right := NR.Right - TagW - 10;
  if (FMode = lmChecklist) and FStale.Contains(U.Path) then
  begin
    TagW := DrawTag(NR.Right, NR.CenterPoint.Y, CM.Lang.Tr('ALTERADO'), P.Pending);
    NR.Right := NR.Right - TagW - 10;
  end;
  if (FSonar <> nil) and FSonar.Find(U.Path, SonarInfo) and (SonarInfo.Issues > 0) then
  begin
    case SonarInfo.Worst of
      ssBlocker, ssCritical: SonarColor := P.Danger;
      ssMajor: SonarColor := P.Pending;
    else
      SonarColor := P.TextDim;
    end;
    TagW := DrawTag(NR.Right, NR.CenterPoint.Y, 'Sonar ' + IntToStr(SonarInfo.Issues), SonarColor);
    NR.Right := NR.Right - TagW - 10;
  end;
  SetFont(13, MonoFont);
  Full := FitText(Canvas, U.FileName, NR.Width);
  Base := U.BaseName;
  if Length(Full) > Length(Base) then
  begin
    Part1 := Base;
    Part2 := Copy(Full, Length(Base) + 1, MaxInt);
  end
  else
  begin
    Part1 := Full;
    Part2 := '';
  end;
  W1 := Canvas.TextWidth(Part1);
  W2 := Canvas.TextWidth(Part2);
  DrawTextRect(Canvas, NR, Part1, NameColor, 13, MonoFont);
  TR := NR;
  TR.Left := TR.Left + W1;
  DrawTextRect(Canvas, TR, Part2, ExtColor, 13, MonoFont);
  if Done and (FMode = lmChecklist) then
  begin
    Y := L.NameR.CenterPoint.Y;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := P.DoneStrike;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawLine(PointF(L.NameR.Left, Y), PointF(L.NameR.Left + W1 + W2, Y), 1);
  end;

  if FMode = lmChecklist then
  begin
    R := L.Star;
    R.Inflate(-5, -5);
    if (S <> nil) and S.Star then
      DrawIcon(Canvas, icStar, R, P.Star)
    else
      DrawIcon(Canvas, icStarOff, R, P.TextFaint);
  end;
  DrawFlag(L.Compila, 'C', (S <> nil) and S.Compila, P.FlagCompila);
  DrawFlag(L.Sonar, 'S', (S <> nil) and S.Sonar, P.FlagSonar);

  if Length(U.Methods) > 0 then
  begin
    Complete := (FMode = lmChecklist) and (MethodsDoneCount(U, FState) = Length(U.Methods));
    if FOpen.Contains(U.Path) then
      FillRound(Canvas, L.Pill, L.Pill.Height / 2, P.Surface2);
    StrokeRound(Canvas, L.Pill, L.Pill.Height / 2, Pick(Complete, P.Accent, P.Border));
    PillFg := Pick(Complete, P.Accent, P.TextDim);
    FillRound(Canvas, TRectF.Create(L.Pill.Left + 9, L.Pill.CenterPoint.Y - 3, L.Pill.Left + 15,
      L.Pill.CenterPoint.Y + 3), 3, Pick(Complete, P.Accent, P.TextFaint));
    TR := L.Pill;
    TR.Left := TR.Left + 20;
    DrawTextRect(Canvas, TR, PillText(ARow), PillFg, 10.5, MonoFont);
  end;

  if FMode = lmChecklist then
  begin
    R := L.Note;
    R.Inflate(-6, -6);
    DrawIcon(Canvas, icEdit, R, Pick((S <> nil) and (S.Note <> ''), P.Accent, P.TextFaint));
  end;
end;

procedure TCMTreeList.DrawMethodRow(const ARow: TRow; const L: TRowLayout);
var
  P: TPalette;
  S: TUnitState;
  M: TMethodInfo;
  Done: Boolean;
  Sig: string;
  Y, TagW: Single;
  TR, NR: TRectF;
  St: TPlanStatus;
  KindColor, SigColor: TAlphaColor;
  SigStyle: TFontStyles;
begin
  P := Pal;
  M := ARow.U.Methods[ARow.M];
  St := ARow.U.MethodStatus(ARow.M);
  S := FState.Find(ARow.U.Path);
  Done := (S <> nil) and S.MDone.Contains(M.Name);
  if FMode = lmChecklist then
  begin
    DrawCheckbox(L.Check, Done, False, P.Star);
    DrawReviewDot(L.State, RowReview(ARow));
  end;
  DrawFlag(L.Compila, 'C', (S <> nil) and S.MCompila.Contains(M.Name), P.FlagCompila);
  DrawFlag(L.Sonar, 'S', (S <> nil) and S.MSonar.Contains(M.Name), P.FlagSonar);
  KindColor := Pick(Done and (FMode = lmChecklist), P.DoneStrike, P.TextFaint);
  SigColor := Pick(Done and (FMode = lmChecklist), P.DoneStrike, P.Text);
  SigStyle := [];
  if St = psPlanned then
  begin
    KindColor := P.Pending;         // so no plano: texto esbatido e em italico
    SigColor := P.TextFaint;
    SigStyle := [TFontStyle.fsItalic];
  end
  else if St = psExtra then
    KindColor := P.FlagCompila;
  DrawTextRect(Canvas, L.KindR, M.Kind, KindColor, 10.5, MonoFont);
  NR := L.NameR;
  // so os metodos por implementar levam etiqueta; os extra ficam com a cor do tipo (a dica explica)
  if St = psPlanned then
  begin
    TagW := DrawPlanTag(NR.Right, NR.CenterPoint.Y, St, False);
    if TagW > 0 then
      NR.Right := NR.Right - TagW - 10;
  end;
  TagW := DrawMetrics(NR.Right, NR.CenterPoint.Y, M);
  if TagW > 0 then
    NR.Right := NR.Right - TagW - 10;
  SetFont(12, MonoFont, SigStyle);
  Sig := FitText(Canvas, M.Sig, NR.Width);
  DrawTextRect(Canvas, NR, Sig, SigColor, 12, MonoFont, SigStyle);
  if Done and (FMode = lmChecklist) then
  begin
    Y := L.NameR.CenterPoint.Y;
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := P.DoneStrike;
    Canvas.Stroke.Thickness := 1;
    TR := L.NameR;
    Canvas.DrawLine(PointF(TR.Left, Y), PointF(TR.Left + Canvas.TextWidth(Sig), Y), 1);
  end;
end;

procedure TCMTreeList.DrawRow(const ARow: TRow; ATop: Single; AHover: Boolean);
var
  L: TRowLayout;
  W, Flash: Single;
  Hover: TRectF;
begin
  W := ViewWidth;
  L := LayoutRow(ARow, ATop);
  if AHover then
  begin
    Hover := TRectF.Create(4, ATop + 1, W - 4, ATop + ARow.Height - 1);
    FillRound(Canvas, Hover, 7, Pal.Surface2);
  end;
  // ficheiro ou metodo acabado de mudar (modo acompanhar)
  if (FFlash.Count > 0) and (ARow.U <> nil) then
  begin
    case ARow.Kind of
      rkFile: Flash := FlashAlpha(FlashKeyFile(ARow.U.Path));
      rkMethod: Flash := FlashAlpha(FlashKeyMethod(ARow.U.Path, ARow.U.Methods[ARow.M].Name));
    else
      Flash := 0;
    end;
    if Flash > 0 then
      FillRound(Canvas, TRectF.Create(4, ATop + 1, W - 4, ATop + ARow.Height - 1), 7,
        Fade(Pal.Accent, 0.30 * Flash));
  end;
  // guia vertical dos metodos
  if ARow.Kind = rkMethod then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := Pal.Border;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawLine(PointF(14 + ARow.Level * IndentW - 2, ATop), PointF(14 + ARow.Level * IndentW - 2, ATop + ARow.Height), 1);
  end;
  case ARow.Kind of
    rkDir: DrawDirRow(ARow, L, ATop, W);
    rkFile: DrawFileRow(ARow, L);
    rkMethod: DrawMethodRow(ARow, L);
  end;
end;

procedure TCMTreeList.Paint;
var
  I, First: Integer;
  State: TCanvasSaveState;
  Y: Single;
begin
  State := Canvas.SaveState;
  try
    Canvas.IntersectClipRect(LocalRect);
    if FRows.Count = 0 then
    begin
      DrawTextRect(Canvas, LocalRect, FEmptyText, Pal.TextFaint, 13, MonoFont, [], TTextAlign.Center);
      Exit;
    end;
    First := RowAtContentY(FScrollY);
    if First < 0 then
      First := 0;
    for I := First to FRows.Count - 1 do
    begin
      Y := FRows[I].Top - FScrollY;
      if Y > Height then
        Break;
      DrawRow(FRows[I], Y, I = FHoverRow);
    end;
    DrawScrollbar;
  finally
    Canvas.RestoreState(State);
  end;
end;

procedure TCMTreeList.ExpandAll;
begin
  FCollapsed.Clear;
  Rebuild;
end;

procedure TCMTreeList.CollapseAll;
  procedure Walk(N: TDirNode);
  var
    C: TDirNode;
  begin
    for C in N.Dirs do
    begin
      FCollapsed.Add(C.Path);
      Walk(C);
    end;
  end;
var
  K: string;
begin
  if FMode = lmMap then
  begin
    if FRoot <> nil then
      Walk(FRoot);
  end
  else
    for K in FGroupKeys do
      FCollapsed.Add(K);
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.ExpandMethods;
var
  U: TUnitInfo;
begin
  if FScan = nil then
    Exit;
  for U in FScan.Units do
    if Length(U.Methods) > 0 then
      FOpen.Add(U.Path);
  Rebuild;
end;

procedure TCMTreeList.CollapseMethods;
begin
  FOpen.Clear;
  Rebuild;
end;

procedure TCMTreeList.ResetFilters;
begin
  FQuery := '';
  FStarOnly := False;
  FReviewFilter := [];
  FStaleOnly := False;
  FLayers.Clear;
  Rebuild;
end;

procedure TCMTreeList.ToggleLayer(const ALayer: string);
begin
  if FLayers.Contains(ALayer) then FLayers.Remove(ALayer) else FLayers.Add(ALayer);
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.ToggleReviewState(AState: TReviewState);
begin
  if AState in FReviewFilter then Exclude(FReviewFilter, AState) else Include(FReviewFilter, AState);
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.SetGit(const ARoot, AHead: string; AStale: THashSet<string>);
var
  P: string;
begin
  FGitRoot := ARoot;
  FGitHead := AHead;
  FStale.Clear;
  FStaleHints.Clear;
  if AStale <> nil then
    for P in AStale do
      FStale.Add(P);
  if FStaleOnly then
    Rebuild
  else
    Repaint;
end;

procedure TCMTreeList.SetStaleOnly(AValue: Boolean);
begin
  FStaleOnly := AValue;
  FScrollY := 0;
  Rebuild;
end;

procedure TCMTreeList.SetSonar(ASnapshot: TSonarSnapshot);
begin
  FSonar := ASnapshot;
  Repaint;
end;

function TCMTreeList.ReviewStateActive(AState: TReviewState): Boolean;
begin
  Result := AState in FReviewFilter;
end;

function TCMTreeList.LayerActive(const ALayer: string): Boolean;
begin
  Result := FLayers.Contains(ALayer);
end;

function TCMTreeList.BuildMarkdown(const AProjectName: string): string;
var
  SB: TStringBuilder;
  Key, Mark: string;
  U: TUnitInfo;
  S: TUnitState;
  M: TMethodInfo;
  Line: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('# ').Append(Tr('Checklist de Código-Fonte — ')).Append(AProjectName).AppendLine.AppendLine;
    for Key in FGroupKeys do
    begin
      SB.Append('### ').Append(IfThen(Key = '', Tr('(raiz)'), Key)).AppendLine;
      for U in FGroups[Key] do
      begin
        S := FState.Find(U.Path);
        Mark := IfThen(UnitDone(U, FState), 'x', ' ');
        Line := '- [' + Mark + '] ' + U.Path;
        if (S <> nil) and S.Compila then Line := Line + Tr(' [Compila]');
        if (S <> nil) and S.Sonar then Line := Line + Tr(' [Sonar]');
        Line := Line + ReviewTag(ReviewOfUnit(U, FState));
        if (S <> nil) and S.Star then Line := Line + ' ★';
        if (S <> nil) and (S.Note <> '') then
          Line := Line + '  <!-- ' + S.Note.Replace(#13#10, ' ').Replace(#10, ' ') + ' -->';
        SB.AppendLine(Line);
        for M in U.Methods do
        begin
          Mark := IfThen((S <> nil) and S.MDone.Contains(M.Name), 'x', ' ');
          Line := '  - [' + Mark + '] `' + M.Sig + '`';
          if (S <> nil) and S.MCompila.Contains(M.Name) then Line := Line + Tr(' [Compila]');
          if (S <> nil) and S.MSonar.Contains(M.Name) then Line := Line + Tr(' [Sonar]');
          Line := Line + ReviewTag(ReviewOfMethod(S, M.Name));
          SB.AppendLine(Line);
        end;
      end;
      SB.AppendLine;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
