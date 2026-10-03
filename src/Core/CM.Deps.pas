unit CM.Deps;

{ Dependencias entre as units do projecto: le as clausulas "uses" (da interface e da implementation) e
  monta o grafo "esta unit usa aquela". Servem de base ao mapa visual e ao relatorio de dependencias.

  So contam as units do proprio projecto; as outras (System.*, FMX.*, de terceiros...) ficam guardadas
  em External de cada no, para os relatorios. O grafo calcula ainda o acoplamento (quem usa / quem e
  usada), os ciclos (componentes fortemente ligados) e a disposicao em colunas: a coluna 0 tem as
  units que ninguem usa (o programa), e cada coluna seguinte as que ficam um passo mais "por baixo". }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, CM.Analyzer;

type
  TUsesInfo = record
    UnitName: string;                 // 'unit X;' / 'program X;' / 'library' / 'package'; '' se nao se encontrou
    InterfaceUses: TArray<string>;    // "uses" da interface (num programa: o unico "uses")
    ImplUses: TArray<string>;         // "uses" da implementation
  end;

  // o que se sabe de uma unit para montar o grafo (o resto vem dos "uses")
  TDepInput = record
    Name: string;                     // nome da unit; vazio = o do ficheiro
    Path: string;                     // caminho relativo com '/'
    Layer: string;
    IsProgram: Boolean;               // .dpr / .dpk
    Methods, Lines, MaxComplexity: Integer;
    InterfaceUses: TArray<string>;
    ImplUses: TArray<string>;
  end;

  TDepEdge = record
    Source, Target: Integer;          // Source usa Target
    InInterface: Boolean;             // aparece no "uses" da interface (senao so na implementation)
  end;

  TDepNode = class
  public
    Index: Integer;
    Name: string;
    Path: string;
    Layer: string;
    IsProgram: Boolean;
    Methods, Lines, MaxComplexity: Integer;
    Deps: TArray<Integer>;            // units do projecto que esta usa, por ordem
    Dependents: TArray<Integer>;      // units do projecto que usam esta
    InterfaceDeps: TArray<Integer>;   // subconjunto de Deps: o que vem da interface
    External: TArray<string>;         // units de fora do projecto que esta usa, sem repeticoes
    Cycle: Integer;                   // numero do ciclo (0..) em que esta, ou -1
    Level: Integer;                   // coluna da disposicao
    Row: Integer;                     // linha dentro da coluna
    function FanOut: Integer;
    function FanIn: Integer;
    // 0 = muito estavel (so e usada), 1 = muito instavel (so usa)
    function Instability: Double;
  end;

  TLayerLink = record
    FromLayer, ToLayer: string;
    Count: Integer;
  end;

  TDepGraph = class
  private
    FNodes: TObjectList<TDepNode>;
    FEdges: TList<TDepEdge>;
    FByName: TDictionary<string, Integer>;
    FCycles: TArray<TArray<Integer>>;
    FLevelCount: Integer;
    procedure FindCycles;
    procedure Arrange;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const AName: string): TDepNode;
    function IndexOfName(const AName: string): Integer;
    property Nodes: TObjectList<TDepNode> read FNodes;
    property Edges: TList<TDepEdge> read FEdges;
    // cada ciclo e a lista de units que se usam umas as outras (uma unit que se usa a si mesma tambem conta)
    property Cycles: TArray<TArray<Integer>> read FCycles;
    property LevelCount: Integer read FLevelCount;
    // quantas units tem a coluna AColumn
    function ColumnSize(AColumn: Integer): Integer;
    function ExternalCount: Integer;
    function TopFanIn(ACount: Integer): TArray<TDepNode>;
    function TopFanOut(ACount: Integer): TArray<TDepNode>;
    // units que ninguem usa e que nao sao programas (candidatas a codigo morto ou a pontos de entrada)
    function Unused: TArray<TDepNode>;
    // dependencias entre as pastas/camadas (so entre camadas diferentes), da mais ligada para a menos
    function LayerLinks: TArray<TLayerLink>;
    // as units que AIndex alcanca (directa ou indirectamente), sem contar a propria
    function Reach(AIndex: Integer): TArray<Integer>;
    // as camadas (pastas imediatas) por ordem alfabetica; a posicao escolhe a cor (DepLayerColor)
    function Layers: TArray<string>;
  end;

const
  // cores das camadas (ARGB), por posicao em TDepGraph.Layers
  DepLayerPalette: array[0..8] of Cardinal = (
    $FF4FB89B, $FF6FA8FF, $FFC9A6FF, $FFE0B23C, $FFE58AB5, $FF5FC9D6, $FF9AA64B, $FFB98B5E, $FF8A94A6);

// le "unit X; interface uses ...; implementation uses ...;" (ou "program X; uses ...;") de um texto Delphi
procedure ExtractUsesText(const AText: string; out AInfo: TUsesInfo);
// monta o grafo a partir dos dados de cada unit
function BuildDepGraph(const AInputs: TArray<TDepInput>): TDepGraph;
// os dados que ja se conhecem de cada unit da analise (caminho, camada, medidas); rapido, para correr na
// thread da interface (a analise pode mudar enquanto a leitura dos ficheiros decorre)
function CollectDepInputs(AScan: TProjectScan): TArray<TDepInput>;
// le os ficheiros de ARoot e preenche o nome e os "uses" de cada unit (pode correr em segundo plano)
procedure ReadDepSources(const ARoot: string; var AInputs: TArray<TDepInput>; const AProgress: TScanProgress = nil);
// as tres coisas seguidas, para quem nao precisa de as separar
function LoadDepGraph(AScan: TProjectScan; const AProgress: TScanProgress = nil): TDepGraph;

implementation

uses
  System.IOUtils, System.RegularExpressions, System.Generics.Defaults, System.StrUtils;

{ TDepNode }

function TDepNode.FanOut: Integer;
begin
  Result := Length(Deps);
end;

function TDepNode.FanIn: Integer;
begin
  Result := Length(Dependents);
end;

function TDepNode.Instability: Double;
begin
  if FanIn + FanOut = 0 then
    Result := 0
  else
    Result := FanOut / (FanIn + FanOut);
end;

{ extraccao dos "uses" }

const
  RePatternHeader = '^\s*(unit|program|library|package)\s+([A-Za-z_][\w.]*)';
  ReUnitHeader = '(?im)' + RePatternHeader;
  ReInterface = '(?im)^\s*interface\b';
  ReImplementation = '(?im)^\s*implementation\b';
  ReUses = '(?is)\buses\b(.*?);';

// "Nome in 'caminho'" -> "Nome"; tira espacos e repeticoes
function UsesList(const ASection: string): TArray<string>;
var
  M: TMatch;
  Item, Name: string;
  List: TList<string>;
  Seen: TDictionary<string, Boolean>;
begin
  List := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    M := TRegEx.Match(ASection, ReUses);
    if M.Success then
      for Item in M.Groups[1].Value.Split([',']) do
      begin
        Name := TRegEx.Replace(Item, '(?is)\s+in\s+''.*$', '').Trim;
        // o que sobra de directivas de compilacao ou de lixo nao e um nome de unit
        if (Name <> '') and TRegEx.IsMatch(Name, '^[A-Za-z_][\w.]*$') and not Seen.ContainsKey(LowerCase(Name)) then
        begin
          Seen.Add(LowerCase(Name), True);
          List.Add(Name);
        end;
      end;
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

procedure ExtractUsesText(const AText: string; out AInfo: TUsesInfo);
var
  Clean, Iface, Impl: string;
  MH, MI, MM: TMatch;
begin
  AInfo := Default(TUsesInfo);
  Clean := CleanUnitText(AText);
  MH := TRegEx.Match(Clean, ReUnitHeader);
  if MH.Success then
    AInfo.UnitName := MH.Groups[2].Value;
  MI := TRegEx.Match(Clean, ReInterface);
  MM := TRegEx.Match(Clean, ReImplementation);
  if MI.Success and MM.Success and (MM.Index > MI.Index) then
  begin
    Iface := Copy(Clean, MI.Index + MI.Length, MM.Index - (MI.Index + MI.Length));
    Impl := Copy(Clean, MM.Index + MM.Length, MaxInt);
    AInfo.InterfaceUses := UsesList(Iface);
    AInfo.ImplUses := UsesList(Impl);
  end
  else
  begin
    // programa, biblioteca ou pacote: so ha um "uses" (ou "contains"/"requires", que se ignoram)
    AInfo.InterfaceUses := UsesList(Clean);
  end;
end;

{ TDepGraph }

function TDepGraph.Layers: TArray<string>;
var
  L: TList<string>;
  N: TDepNode;
begin
  L := TList<string>.Create;
  try
    for N in FNodes do
      if not L.Contains(N.Layer) then
        L.Add(N.Layer);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

constructor TDepGraph.Create;
begin
  inherited;
  FNodes := TObjectList<TDepNode>.Create(True);
  FEdges := TList<TDepEdge>.Create;
  FByName := TDictionary<string, Integer>.Create;
end;

destructor TDepGraph.Destroy;
begin
  FByName.Free;
  FEdges.Free;
  FNodes.Free;
  inherited;
end;

function TDepGraph.IndexOfName(const AName: string): Integer;
begin
  if not FByName.TryGetValue(LowerCase(AName), Result) then
    Result := -1;
end;

function TDepGraph.Find(const AName: string): TDepNode;
var
  I: Integer;
begin
  I := IndexOfName(AName);
  if I < 0 then
    Result := nil
  else
    Result := FNodes[I];
end;

function TDepGraph.ColumnSize(AColumn: Integer): Integer;
var
  N: TDepNode;
begin
  Result := 0;
  for N in FNodes do
    if N.Level = AColumn then
      Inc(Result);
end;

function TDepGraph.ExternalCount: Integer;
var
  N: TDepNode;
  S: string;
  Seen: TDictionary<string, Boolean>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for N in FNodes do
      for S in N.External do
        Seen.AddOrSetValue(LowerCase(S), True);
    Result := Seen.Count;
  finally
    Seen.Free;
  end;
end;

function TDepGraph.TopFanIn(ACount: Integer): TArray<TDepNode>;
var
  L: TList<TDepNode>;
begin
  L := TList<TDepNode>.Create(FNodes);
  try
    L.Sort(TComparer<TDepNode>.Construct(
      function(const A, B: TDepNode): Integer
      begin
        Result := B.FanIn - A.FanIn;
        if Result = 0 then
          Result := CompareText(A.Name, B.Name);
      end));
    Result := Copy(L.ToArray, 0, ACount);
  finally
    L.Free;
  end;
end;

function TDepGraph.TopFanOut(ACount: Integer): TArray<TDepNode>;
var
  L: TList<TDepNode>;
begin
  L := TList<TDepNode>.Create(FNodes);
  try
    L.Sort(TComparer<TDepNode>.Construct(
      function(const A, B: TDepNode): Integer
      begin
        Result := B.FanOut - A.FanOut;
        if Result = 0 then
          Result := CompareText(A.Name, B.Name);
      end));
    Result := Copy(L.ToArray, 0, ACount);
  finally
    L.Free;
  end;
end;

function TDepGraph.Unused: TArray<TDepNode>;
var
  L: TList<TDepNode>;
  N: TDepNode;
begin
  L := TList<TDepNode>.Create;
  try
    for N in FNodes do
      if (N.FanIn = 0) and not N.IsProgram then
        L.Add(N);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TDepGraph.LayerLinks: TArray<TLayerLink>;
var
  Counts: TDictionary<string, Integer>;
  E: TDepEdge;
  Key: string;
  P: TPair<string, Integer>;
  L: TList<TLayerLink>;
  Item: TLayerLink;
  Parts: TArray<string>;
  N: Integer;
begin
  Counts := TDictionary<string, Integer>.Create;
  L := TList<TLayerLink>.Create;
  try
    for E in FEdges do
      if FNodes[E.Source].Layer <> FNodes[E.Target].Layer then
      begin
        Key := FNodes[E.Source].Layer + #1 + FNodes[E.Target].Layer;
        if Counts.TryGetValue(Key, N) then
          Counts[Key] := N + 1
        else
          Counts.Add(Key, 1);
      end;
    for P in Counts do
    begin
      Parts := P.Key.Split([#1]);
      Item.FromLayer := Parts[0];
      Item.ToLayer := Parts[1];
      Item.Count := P.Value;
      L.Add(Item);
    end;
    L.Sort(TComparer<TLayerLink>.Construct(
      function(const A, B: TLayerLink): Integer
      begin
        Result := B.Count - A.Count;
        if Result = 0 then
          Result := CompareText(A.FromLayer + A.ToLayer, B.FromLayer + B.ToLayer);
      end));
    Result := L.ToArray;
  finally
    L.Free;
    Counts.Free;
  end;
end;

function TDepGraph.Reach(AIndex: Integer): TArray<Integer>;
var
  Seen: TDictionary<Integer, Boolean>;
  Stack: TStack<Integer>;
  I, J: Integer;
  L: TList<Integer>;
begin
  Seen := TDictionary<Integer, Boolean>.Create;
  Stack := TStack<Integer>.Create;
  L := TList<Integer>.Create;
  try
    Stack.Push(AIndex);
    while Stack.Count > 0 do
    begin
      I := Stack.Pop;
      for J in FNodes[I].Deps do
        if (J <> AIndex) and not Seen.ContainsKey(J) then
        begin
          Seen.Add(J, True);
          L.Add(J);
          Stack.Push(J);
        end;
    end;
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
    Stack.Free;
    Seen.Free;
  end;
end;

{ ciclos: componentes fortemente ligados (Tarjan) }

procedure TDepGraph.FindCycles;
var
  Idx, Low: TArray<Integer>;
  OnStack: TArray<Boolean>;
  Stack: TStack<Integer>;
  Counter: Integer;
  Cycles: TList<TArray<Integer>>;

  procedure Visit(V: Integer);
  var
    W: Integer;
    Members: TList<Integer>;
    SelfLoop: Boolean;
  begin
    Idx[V] := Counter;
    Low[V] := Counter;
    Inc(Counter);
    Stack.Push(V);
    OnStack[V] := True;
    SelfLoop := False;
    for W in FNodes[V].Deps do
    begin
      if W = V then
        SelfLoop := True
      else if Idx[W] < 0 then
      begin
        Visit(W);
        if Low[W] < Low[V] then
          Low[V] := Low[W];
      end
      else if OnStack[W] and (Idx[W] < Low[V]) then
        Low[V] := Idx[W];
    end;
    if Low[V] = Idx[V] then
    begin
      Members := TList<Integer>.Create;
      try
        repeat
          W := Stack.Pop;
          OnStack[W] := False;
          Members.Add(W);
        until W = V;
        if (Members.Count > 1) or SelfLoop then
        begin
          Members.Sort;
          Cycles.Add(Members.ToArray);
        end;
      finally
        Members.Free;
      end;
    end;
  end;

var
  I, C: Integer;
  Cyc: TArray<Integer>;
begin
  SetLength(Idx, FNodes.Count);
  SetLength(Low, FNodes.Count);
  SetLength(OnStack, FNodes.Count);
  for I := 0 to FNodes.Count - 1 do
  begin
    Idx[I] := -1;
    FNodes[I].Cycle := -1;
  end;
  Counter := 0;
  Stack := TStack<Integer>.Create;
  Cycles := TList<TArray<Integer>>.Create;
  try
    for I := 0 to FNodes.Count - 1 do
      if Idx[I] < 0 then
        Visit(I);
    // os ciclos por ordem da primeira unit de cada um (estavel entre execucoes)
    Cycles.Sort(TComparer<TArray<Integer>>.Construct(
      function(const A, B: TArray<Integer>): Integer
      begin
        Result := A[0] - B[0];
      end));
    FCycles := Cycles.ToArray;
  finally
    Cycles.Free;
    Stack.Free;
  end;
  for C := 0 to High(FCycles) do
  begin
    Cyc := FCycles[C];
    for I in Cyc do
      FNodes[I].Cycle := C;
  end;
end;

{ disposicao em colunas: o nivel e o caminho mais longo desde quem ninguem usa (os ciclos contam como uma
  so unit); dentro de cada coluna ordena-se pela media das posicoes dos vizinhos para reduzir cruzamentos }

procedure TDepGraph.Arrange;
var
  N, I, J, K, Pass, MaxLevel: Integer;
  Group: TArray<Integer>;          // unit -> grupo (ciclo ou ela propria)
  GroupCount: Integer;
  GLevel, InDeg: TArray<Integer>;
  GSucc: TArray<TArray<Integer>>;
  Queue: TQueue<Integer>;
  Cols: TArray<TList<Integer>>;
  Pos: TArray<Double>;
  Cyc: TArray<Integer>;

  procedure AddSucc(AFrom, ATo: Integer);
  var
    K2: Integer;
  begin
    if AFrom = ATo then
      Exit;
    for K2 := 0 to High(GSucc[AFrom]) do
      if GSucc[AFrom][K2] = ATo then
        Exit;
    SetLength(GSucc[AFrom], Length(GSucc[AFrom]) + 1);
    GSucc[AFrom][High(GSucc[AFrom])] := ATo;
    Inc(InDeg[ATo]);
  end;

  procedure SortColumn(AColumn: Integer; AUseUp, AUseDown: Boolean);
  var
    Keys: TDictionary<Integer, Double>;
    V, W, Cnt: Integer;
    Sum: Double;
  begin
    Keys := TDictionary<Integer, Double>.Create;
    try
      for V in Cols[AColumn] do
      begin
        Sum := 0;
        Cnt := 0;
        if AUseUp then
          for W in FNodes[V].Dependents do
          begin
            Sum := Sum + Pos[W];
            Inc(Cnt);
          end;
        if AUseDown then
          for W in FNodes[V].Deps do
          begin
            Sum := Sum + Pos[W];
            Inc(Cnt);
          end;
        if Cnt > 0 then
          Keys.Add(V, Sum / Cnt)
        else
          Keys.Add(V, Pos[V]);
      end;
      Cols[AColumn].Sort(TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          if Keys[A] < Keys[B] then
            Result := -1
          else if Keys[A] > Keys[B] then
            Result := 1
          else
            Result := CompareText(FNodes[A].Name, FNodes[B].Name);
        end));
      for V := 0 to Cols[AColumn].Count - 1 do
        Pos[Cols[AColumn][V]] := V;
    finally
      Keys.Free;
    end;
  end;

begin
  N := FNodes.Count;
  FLevelCount := 0;
  if N = 0 then
    Exit;
  SetLength(Group, N);
  for I := 0 to N - 1 do
    Group[I] := I;
  // as units de um ciclo ficam no mesmo grupo (e na mesma coluna)
  for Cyc in FCycles do
    for I in Cyc do
      Group[I] := Cyc[0];
  GroupCount := N;
  SetLength(GLevel, GroupCount);
  SetLength(InDeg, GroupCount);
  SetLength(GSucc, GroupCount);
  for I := 0 to N - 1 do
    for J in FNodes[I].Deps do
      AddSucc(Group[I], Group[J]);

  Queue := TQueue<Integer>.Create;
  try
    for I := 0 to GroupCount - 1 do
      if (Group[I] = I) and (InDeg[I] = 0) then
        Queue.Enqueue(I);
    while Queue.Count > 0 do
    begin
      K := Queue.Dequeue;
      for J in GSucc[K] do
      begin
        if GLevel[K] + 1 > GLevel[J] then
          GLevel[J] := GLevel[K] + 1;
        Dec(InDeg[J]);
        if InDeg[J] = 0 then
          Queue.Enqueue(J);
      end;
    end;
  finally
    Queue.Free;
  end;

  MaxLevel := 0;
  for I := 0 to N - 1 do
  begin
    FNodes[I].Level := GLevel[Group[I]];
    if FNodes[I].Level > MaxLevel then
      MaxLevel := FNodes[I].Level;
  end;
  FLevelCount := MaxLevel + 1;

  SetLength(Cols, FLevelCount);
  for I := 0 to FLevelCount - 1 do
    Cols[I] := TList<Integer>.Create;
  SetLength(Pos, N);
  try
    // ordem inicial: por nome
    for I := 0 to N - 1 do
      Cols[FNodes[I].Level].Add(I);
    for K := 0 to FLevelCount - 1 do
    begin
      Cols[K].Sort(TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          Result := CompareText(FNodes[A].Name, FNodes[B].Name);
        end));
      for I := 0 to Cols[K].Count - 1 do
        Pos[Cols[K][I]] := I;
    end;
    for Pass := 1 to 4 do
    begin
      for K := 1 to FLevelCount - 1 do
        SortColumn(K, True, False);
      for K := FLevelCount - 2 downto 0 do
        SortColumn(K, False, True);
    end;
    for K := 0 to FLevelCount - 1 do
      for I := 0 to Cols[K].Count - 1 do
        FNodes[Cols[K][I]].Row := I;
  finally
    for I := 0 to FLevelCount - 1 do
      Cols[I].Free;
  end;
end;

{ montagem }

// nome do ficheiro sem pasta nem extensao (sem validar o caminho: so se usa como chave)
function BaseNameOf(const APath: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(APath.Replace('/', '')), '');
end;

function BuildDepGraph(const AInputs: TArray<TDepInput>): TDepGraph;
var
  I, J, Target: Integer;
  Node: TDepNode;
  Inp: TDepInput;
  Ext: TList<string>;
  Uses_, Iface, UsedBy: TList<Integer>;
  Edge: TDepEdge;
  InIface: TDictionary<Integer, Boolean>;
  U: string;
  IncomingLists: TArray<TList<Integer>>;
begin
  Result := TDepGraph.Create;
  try
    for I := 0 to High(AInputs) do
    begin
      Inp := AInputs[I];
      Node := TDepNode.Create;
      Node.Index := I;
      Node.Name := Inp.Name;
      if Node.Name = '' then
        Node.Name := BaseNameOf(Inp.Path);
      Node.Path := Inp.Path;
      Node.Layer := Inp.Layer;
      Node.IsProgram := Inp.IsProgram;
      Node.Methods := Inp.Methods;
      Node.Lines := Inp.Lines;
      Node.MaxComplexity := Inp.MaxComplexity;
      Node.Cycle := -1;
      Result.FNodes.Add(Node);
      // o nome da unit e o do ficheiro: os dois resolvem para a mesma unit
      Result.FByName.AddOrSetValue(LowerCase(Node.Name), I);
      if not Result.FByName.ContainsKey(LowerCase(BaseNameOf(Inp.Path))) then
        Result.FByName.Add(LowerCase(BaseNameOf(Inp.Path)), I);
    end;

    SetLength(IncomingLists, Result.FNodes.Count);
    for I := 0 to High(IncomingLists) do
      IncomingLists[I] := TList<Integer>.Create;
    try
      for I := 0 to High(AInputs) do
      begin
        Inp := AInputs[I];
        Node := Result.FNodes[I];
        Uses_ := TList<Integer>.Create;
        Iface := TList<Integer>.Create;
        Ext := TList<string>.Create;
        InIface := TDictionary<Integer, Boolean>.Create;
        try
          for U in Inp.InterfaceUses do
          begin
            Target := Result.IndexOfName(U);
            if (Target >= 0) and (Target <> I) then
            begin
              if not InIface.ContainsKey(Target) then
              begin
                InIface.Add(Target, True);
                Iface.Add(Target);
                Uses_.Add(Target);
              end;
            end
            else if Target < 0 then
            begin
              if not Ext.Contains(U) then
                Ext.Add(U);
            end;
          end;
          for U in Inp.ImplUses do
          begin
            Target := Result.IndexOfName(U);
            if (Target >= 0) and (Target <> I) then
            begin
              if not InIface.ContainsKey(Target) and not Uses_.Contains(Target) then
                Uses_.Add(Target);
            end
            else if Target < 0 then
            begin
              if not Ext.Contains(U) then
                Ext.Add(U);
            end;
          end;
          Uses_.Sort;
          Iface.Sort;
          Ext.Sort(TComparer<string>.Construct(
            function(const A, B: string): Integer
            begin
              Result := CompareText(A, B);
            end));
          Node.Deps := Uses_.ToArray;
          Node.InterfaceDeps := Iface.ToArray;
          Node.External := Ext.ToArray;
          for J in Node.Deps do
          begin
            Edge.Source := I;
            Edge.Target := J;
            Edge.InInterface := InIface.ContainsKey(J);
            Result.FEdges.Add(Edge);
            IncomingLists[J].Add(I);
          end;
        finally
          InIface.Free;
          Ext.Free;
          Iface.Free;
          Uses_.Free;
        end;
      end;
      for I := 0 to High(IncomingLists) do
      begin
        UsedBy := IncomingLists[I];
        UsedBy.Sort;
        Result.FNodes[I].Dependents := UsedBy.ToArray;
      end;
    finally
      for I := 0 to High(IncomingLists) do
        IncomingLists[I].Free;
    end;
    Result.FindCycles;
    Result.Arrange;
  except
    Result.Free;
    raise;
  end;
end;

function CollectDepInputs(AScan: TProjectScan): TArray<TDepInput>;
var
  I, K: Integer;
  U: TUnitInfo;
  Inp: TDepInput;
begin
  SetLength(Result, AScan.Units.Count);
  for I := 0 to AScan.Units.Count - 1 do
  begin
    U := AScan.Units[I];
    Inp := Default(TDepInput);
    Inp.Path := U.Path;
    Inp.Layer := U.Layer;
    Inp.IsProgram := SameText(U.Ext, '.dpr') or SameText(U.Ext, '.dpk');
    Inp.Methods := Length(U.Methods);
    for K := 0 to High(U.Methods) do
    begin
      Inc(Inp.Lines, U.Methods[K].Lines);
      if U.Methods[K].Complexity > Inp.MaxComplexity then
        Inp.MaxComplexity := U.Methods[K].Complexity;
    end;
    Result[I] := Inp;
  end;
end;

procedure ReadDepSources(const ARoot: string; var AInputs: TArray<TDepInput>; const AProgress: TScanProgress);
var
  I: Integer;
  Info: TUsesInfo;
begin
  for I := 0 to High(AInputs) do
  begin
    try
      ExtractUsesText(ReadSourceText(TPath.Combine(ARoot, AInputs[I].Path.Replace('/', PathDelim))), Info);
      AInputs[I].Name := Info.UnitName;
      AInputs[I].InterfaceUses := Info.InterfaceUses;
      AInputs[I].ImplUses := Info.ImplUses;
    except
      on Exception do ;      // ficheiro ilegivel: a unit entra no grafo sem ligacoes
    end;
    if Assigned(AProgress) and ((I mod 16 = 0) or (I = High(AInputs))) then
      AProgress('', I + 1, Length(AInputs));
  end;
end;

function LoadDepGraph(AScan: TProjectScan; const AProgress: TScanProgress): TDepGraph;
var
  Inputs: TArray<TDepInput>;
begin
  Inputs := CollectDepInputs(AScan);
  ReadDepSources(AScan.Root, Inputs, AProgress);
  Result := BuildDepGraph(Inputs);
end;

end.
