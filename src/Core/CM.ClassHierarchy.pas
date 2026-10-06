unit CM.ClassHierarchy;

{ A hierarquia das classes e interfaces do projecto: quem herda de quem, a profundidade de heranca de cada uma (DIT: quantos
  niveis tem por cima, contando TObject como nivel 0, por isso uma classe sem ancestral tem profundidade 1), quantas lhe
  herdam e quantos metodos declara.

  O ancestral procura-se primeiro na propria unit e depois no projecto (sem qualificacao: 'Vcl.Forms.TForm' procura-se como
  'TForm'). Se esta fora do projecto, usa-se uma tabela de classes conhecidas da RTL; as que nao constam contam como um nivel
  a mais e a profundidade passa a ser um MINIMO (Exact = False): do que esta por cima delas nao se sabe. Os records nao
  herdam e ficam de fora da hierarquia (so se contam). }

interface

uses
  System.SysUtils, System.Generics.Collections, CM.Analyzer, CM.Classes, CM.Metrics;

type
  TClassNode = class
  public
    Name: string;
    Kind: TClassKind;
    UnitPath: string;              // relativo a raiz, com '/'
    Layer: string;
    Line: Integer;
    Ancestor: string;              // o que a declaracao diz ('' = nada)
    Interfaces: TArray<string>;
    Parent: TClassNode;            // se o ancestral esta no projecto
    ExternalBase: string;          // se esta fora: o seu nome ('' se ha ancestral no projecto ou nao ha ancestral)
    Depth: Integer;                // niveis acima, com TObject / IInterface a 0
    Exact: Boolean;                // False: Depth e um minimo (cadeia desconhecida acima de um ancestral externo)
    ProjectDepth: Integer;         // niveis dentro do projecto (a primeira classe do projecto de uma cadeia = 1)
    Children: Integer;             // heranca directa
    Descendants: Integer;          // heranca directa e indirecta
    Methods: Integer;              // metodos declarados pela classe (os da unit com esse dono)
    // 'TBar.TFoo' -> a cadeia de ancestrais ate ao topo conhecido: ['TFoo', 'TBar', 'TBase']
    function Chain: TArray<string>;
  end;

  THierarchy = class
  private
    FNodes: TObjectList<TClassNode>;
    FByName: TDictionary<string, TClassNode>;
    FRecords: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const AName: string): TClassNode;
    // classes e interfaces do projecto, pela ordem das units
    property Nodes: TObjectList<TClassNode> read FNodes;
    property Records: Integer read FRecords;
    function Count(AKind: TClassKind): Integer;
    function MaxDepth: Integer;
    function AverageDepth: Double;
    // quantas classes (e interfaces) tem cada profundidade: indice = profundidade
    function Histogram: TArray<Integer>;
    function Roots: TArray<TClassNode>;
    // as AMax mais profundas (empates: mais descendentes, depois o nome)
    function Deepest(AMax: Integer): TArray<TClassNode>;
    // as AMax com mais filhas directas
    function MostChildren(AMax: Integer): TArray<TClassNode>;
    // as raizes e, por baixo de cada uma, as suas filhas (por ordem do nome): a ordem em que se le a arvore
    function TreeOrder: TArray<TClassNode>;
  end;

// 1..4 normal, 5..6 moderada, 7 ou mais alta (cxNone para 0)
function DepthLevel(ADepth: Integer): TComplexityLevel;
// a profundidade de uma classe conhecida da RTL (TObject = 0); False se nao consta da tabela
function KnownDepth(const AName: string; out ADepth: Integer): Boolean;
function BuildHierarchy(AScan: TProjectScan): THierarchy;

implementation

uses
  System.Generics.Defaults;

const
  // classes e interfaces da RTL cuja cadeia se conhece com certeza (nome sem qualificacao -> niveis acima)
  KnownTable =
    'TObject=0,TPersistent=1,TInterfacedObject=1,TInterfacedPersistent=2,TComponent=2,TThread=1,TList=1,TStream=1,' +
    'THandleStream=2,TFileStream=3,TCustomMemoryStream=2,TMemoryStream=3,TStrings=2,TStringList=3,TCollection=2,' +
    'TCollectionItem=2,TDataModule=3,TCustomAttribute=1,Exception=1,EAbort=2,EConvertError=2,EInvalidOperation=2,' +
    'IInterface=0,IUnknown=0,IDispatch=1';

var
  GKnown: TDictionary<string, Integer>;

function KnownDepth(const AName: string; out ADepth: Integer): Boolean;
var
  N: string;
  P: Integer;
begin
  N := AName;
  P := LastDelimiter('.', N);
  if P > 0 then
    N := Copy(N, P + 1, MaxInt);
  Result := GKnown.TryGetValue(LowerCase(N), ADepth);
end;

function DepthLevel(ADepth: Integer): TComplexityLevel;
begin
  if ADepth <= 0 then
    Result := cxNone
  else if ADepth <= 4 then
    Result := cxLow
  else if ADepth <= 6 then
    Result := cxModerate
  else
    Result := cxHigh;
end;

{ TClassNode }

function TClassNode.Chain: TArray<string>;
var
  N: TClassNode;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    N := Self;
    while N <> nil do
    begin
      List.Add(N.Name);
      if N.Parent = nil then
      begin
        if N.ExternalBase <> '' then
          List.Add(N.ExternalBase);
        Break;
      end;
      N := N.Parent;
      if List.Count > 200 then
        Break;                       // um ciclo nunca chega aqui, mas protege
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ THierarchy }

constructor THierarchy.Create;
begin
  inherited;
  FNodes := TObjectList<TClassNode>.Create(True);
  FByName := TDictionary<string, TClassNode>.Create;
end;

destructor THierarchy.Destroy;
begin
  FByName.Free;
  FNodes.Free;
  inherited;
end;

function THierarchy.Find(const AName: string): TClassNode;
var
  N: string;
  P: Integer;
begin
  N := AName;
  P := LastDelimiter('.', N);
  if P > 0 then
    N := Copy(N, P + 1, MaxInt);
  if not FByName.TryGetValue(LowerCase(N), Result) then
    Result := nil;
end;

function THierarchy.Count(AKind: TClassKind): Integer;
var
  N: TClassNode;
begin
  Result := 0;
  for N in FNodes do
    if N.Kind = AKind then
      Inc(Result);
end;

function THierarchy.MaxDepth: Integer;
var
  N: TClassNode;
begin
  Result := 0;
  for N in FNodes do
    if N.Depth > Result then
      Result := N.Depth;
end;

function THierarchy.AverageDepth: Double;
var
  N: TClassNode;
  Sum: Integer;
begin
  if FNodes.Count = 0 then
    Exit(0);
  Sum := 0;
  for N in FNodes do
    Inc(Sum, N.Depth);
  Result := Sum / FNodes.Count;
end;

function THierarchy.Histogram: TArray<Integer>;
var
  N: TClassNode;
begin
  SetLength(Result, MaxDepth + 1);
  for N in FNodes do
    Inc(Result[N.Depth]);
end;

function THierarchy.Roots: TArray<TClassNode>;
var
  List: TList<TClassNode>;
  N: TClassNode;
begin
  List := TList<TClassNode>.Create;
  try
    for N in FNodes do
      if N.Parent = nil then
        List.Add(N);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SortedBy(ANodes: TObjectList<TClassNode>; AMax: Integer;
  const AComparison: TComparison<TClassNode>): TArray<TClassNode>;
var
  Arr: TArray<TClassNode>;
begin
  Arr := ANodes.ToArray;
  TArray.Sort<TClassNode>(Arr, TComparer<TClassNode>.Construct(AComparison));
  if (AMax >= 0) and (Length(Arr) > AMax) then
    SetLength(Arr, AMax);
  Result := Arr;
end;

function THierarchy.Deepest(AMax: Integer): TArray<TClassNode>;
begin
  Result := SortedBy(FNodes, AMax,
    function(const A, B: TClassNode): Integer
    begin
      Result := B.Depth - A.Depth;
      if Result = 0 then
        Result := B.Descendants - A.Descendants;
      if Result = 0 then
        Result := CompareText(A.Name, B.Name);
    end);
end;

function THierarchy.MostChildren(AMax: Integer): TArray<TClassNode>;
begin
  Result := SortedBy(FNodes, AMax,
    function(const A, B: TClassNode): Integer
    begin
      Result := B.Children - A.Children;
      if Result = 0 then
        Result := B.Descendants - A.Descendants;
      if Result = 0 then
        Result := CompareText(A.Name, B.Name);
    end);
end;

function THierarchy.TreeOrder: TArray<TClassNode>;
var
  Kids: TDictionary<TClassNode, TList<TClassNode>>;
  Ordered: TList<TClassNode>;
  N: TClassNode;
  Roots: TList<TClassNode>;
  Pair: TPair<TClassNode, TList<TClassNode>>;
  Cmp: IComparer<TClassNode>;

  procedure Visit(ANode: TClassNode; ALevel: Integer);
  var
    K: TClassNode;
  begin
    Ordered.Add(ANode);
    if (ALevel < 200) and Kids.ContainsKey(ANode) then
      for K in Kids[ANode] do
        Visit(K, ALevel + 1);
  end;

begin
  Cmp := TComparer<TClassNode>.Construct(
    function(const A, B: TClassNode): Integer
    begin
      Result := CompareText(A.Name, B.Name);
    end);
  Kids := TDictionary<TClassNode, TList<TClassNode>>.Create;
  Ordered := TList<TClassNode>.Create;
  Roots := TList<TClassNode>.Create;
  try
    for N in FNodes do
      if N.Parent = nil then
        Roots.Add(N)
      else
      begin
        if not Kids.ContainsKey(N.Parent) then
          Kids.Add(N.Parent, TList<TClassNode>.Create);
        Kids[N.Parent].Add(N);
      end;
    Roots.Sort(Cmp);
    for Pair in Kids do
      Pair.Value.Sort(Cmp);
    for N in Roots do
      Visit(N, 0);
    Result := Ordered.ToArray;
  finally
    for Pair in Kids do
      Pair.Value.Free;
    Roots.Free;
    Ordered.Free;
    Kids.Free;
  end;
end;

{ construcao }

function StripQualifier(const AName: string): string;
var
  P: Integer;
begin
  P := LastDelimiter('.', AName);
  if P > 0 then
    Result := Copy(AName, P + 1, MaxInt)
  else
    Result := AName;
end;

procedure ResolveDepth(ANode: TClassNode; AVisiting: TList<TClassNode>);
var
  D: Integer;
begin
  if ANode.Depth > 0 then
    Exit;                                  // ja calculada
  if AVisiting.IndexOf(ANode) >= 0 then
  begin
    ANode.Depth := 1;                      // um ciclo (A herda de B que herda de A): corta-se
    ANode.Exact := False;
    Exit;
  end;
  AVisiting.Add(ANode);
  try
    if ANode.Parent <> nil then
    begin
      ResolveDepth(ANode.Parent, AVisiting);
      ANode.Depth := ANode.Parent.Depth + 1;
      ANode.Exact := ANode.Parent.Exact;
      ANode.ProjectDepth := ANode.Parent.ProjectDepth + 1;
    end
    else if ANode.Ancestor = '' then
    begin
      ANode.Depth := 1;                    // TObject / IInterface por cima
      ANode.Exact := True;
      ANode.ProjectDepth := 1;
    end
    else
    begin
      ANode.ProjectDepth := 1;
      if KnownDepth(ANode.Ancestor, D) then
      begin
        ANode.Depth := D + 1;
        ANode.Exact := True;
      end
      else
      begin
        ANode.Depth := 2;                  // pelo menos: o ancestral externo e uma classe, que herda de TObject
        ANode.Exact := False;
      end;
    end;
  finally
    AVisiting.Delete(AVisiting.Count - 1);
  end;
end;

function BuildHierarchy(AScan: TProjectScan): THierarchy;
var
  U: TUnitInfo;
  C: TClassInfo;
  N, Other: TClassNode;
  M: TMethodInfo;
  Visiting: TList<TClassNode>;
  ByUnit: TObjectDictionary<string, TDictionary<string, TClassNode>>;
  InUnit: TDictionary<string, TClassNode>;
  Key: string;
begin
  Result := THierarchy.Create;
  if AScan = nil then
    Exit;
  Visiting := TList<TClassNode>.Create;
  ByUnit := TObjectDictionary<string, TDictionary<string, TClassNode>>.Create([doOwnsValues]);
  try
    for U in AScan.Units do
      for C in U.Classes do
      begin
        if C.Kind = ckRecord then
        begin
          Inc(Result.FRecords);
          Continue;
        end;
        N := TClassNode.Create;
        N.Name := C.Name;
        N.Kind := C.Kind;
        N.UnitPath := U.Path;
        N.Layer := U.Layer;
        N.Line := C.Line;
        N.Ancestor := C.Ancestor;
        N.Interfaces := C.Interfaces;
        for M in U.Methods do
          if SameText(M.Owner, C.Name) then
            Inc(N.Methods);
        Result.FNodes.Add(N);
        Key := LowerCase(C.Name);
        Result.FByName.TryAdd(Key, N);               // com nomes repetidos, fica a primeira
        if not ByUnit.TryGetValue(U.Path, InUnit) then
        begin
          InUnit := TDictionary<string, TClassNode>.Create;
          ByUnit.Add(U.Path, InUnit);
        end;
        InUnit.TryAdd(Key, N);
      end;

    // liga cada classe ao ancestral do projecto: primeiro o da propria unit, depois o primeiro do projecto
    for N in Result.FNodes do
    begin
      if N.Ancestor = '' then
        Continue;
      Key := LowerCase(StripQualifier(N.Ancestor));
      Other := nil;
      if ByUnit.TryGetValue(N.UnitPath, InUnit) then
        InUnit.TryGetValue(Key, Other);
      if Other = nil then
        Result.FByName.TryGetValue(Key, Other);
      if (Other <> nil) and (Other <> N) and (Other.Kind = N.Kind) then
        N.Parent := Other
      else
        N.ExternalBase := N.Ancestor;
    end;

    for N in Result.FNodes do
      ResolveDepth(N, Visiting);

    // filhas directas e descendentes
    for N in Result.FNodes do
      if N.Parent <> nil then
        Inc(N.Parent.Children);
    for N in Result.FNodes do
    begin
      Other := N.Parent;
      Visiting.Clear;
      while (Other <> nil) and (Visiting.IndexOf(Other) < 0) do
      begin
        Visiting.Add(Other);
        Inc(Other.Descendants);
        Other := Other.Parent;
      end;
    end;
  finally
    ByUnit.Free;
    Visiting.Free;
  end;
end;

procedure FillKnown;
var
  Item: string;
  P: Integer;
begin
  GKnown := TDictionary<string, Integer>.Create;
  for Item in KnownTable.Split([',']) do
  begin
    P := Pos('=', Item);
    GKnown.Add(LowerCase(Copy(Item, 1, P - 1)), StrToInt(Copy(Item, P + 1, MaxInt)));
  end;
end;

initialization
  FillKnown;

finalization
  GKnown.Free;

end.
