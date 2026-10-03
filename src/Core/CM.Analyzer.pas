unit CM.Analyzer;

// Analise estatica de projectos Delphi: percorre as pastas, encontra as units .pas/.dpr e
// extrai as assinaturas function/procedure/constructor/destructor de cada uma.
// Nao e um parser Delphi completo - e a mesma heuristica dos scripts PowerShell originais.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, System.IOUtils, CM.Metrics;

type
  TMethodInfo = record
    Name: string;       // chave unica dentro da unit ('TFoo.Bar'; 'TFoo.Bar(Integer)' num overload)
                        // - e tambem a chave do progresso guardado
    Kind: string;
    Sig: string;
    Owner: string;      // classe/record que declara o metodo ('' = rotina livre)
    Simple: string;     // nome sem qualificacao ('Bar')
    Lines: Integer;     // linhas de codigo do corpo (0 = sem corpo nesta unit)
    Complexity: Integer; // complexidade ciclomatica do corpo (0 = sem corpo)
  end;

  // estado de uma unit/metodo face ao plano (documento .md): so tem valor numa vista com plano
  TPlanStatus = (psNone, psImplemented, psPlanned, psExtra);

  TUnitInfo = class
  public
    PlanStatus: TPlanStatus;
    PlannedPath: string;            // caminho previsto no plano quando a unit esta noutra pasta
    MethodPlan: TArray<TPlanStatus>; // estado de cada metodo (mesmo indice de Methods); vazio sem plano
    Path: string;       // relativo a raiz, com '/'
    Dir: string;        // pasta relativa ('' na raiz)
    FileName: string;
    Layer: string;      // nome da pasta imediata ('Raiz' na raiz)
    Methods: TArray<TMethodInfo>;
    function BaseName: string;
    function Ext: string;
    function MethodStatus(AIndex: Integer): TPlanStatus;
  end;

  TScanProgress = reference to procedure(const Msg: string; Done, Total: Integer);

  TProjectScan = class
  public
    Root: string;
    ExcludeDirs: TArray<string>;   // nomes de pastas ignoradas nesta analise
    Units: TObjectList<TUnitInfo>;
    Folders: Integer;
    TotalMethods: Integer;
    UnitsWithMethods: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  // resultado de RescanFile
  TRescanKind = (rcNone, rcAdded, rcChanged, rcRemoved);

  // o que mudou numa unit ao voltar a analisa-la
  TScanChange = record
    Path: string;
    Kind: TRescanKind;
    NewMethods: TArray<string>;   // metodos novos ou de assinatura alterada (TMethodInfo.Name)
  end;

const
  DefaultExcludeDirs: array[0..8] of string =
    ('.git', '.svn', '.hg', 'modules', 'bin', 'out', '__history', '__recovery', 'node_modules');

function DefaultExcludeList: TArray<string>;
// texto livre (separado por virgulas, ponto e virgula ou linhas) -> lista; vazio = predefinidas
function ParseExcludeDirs(const AText: string): TArray<string>;
function ExcludedDirsText: string; overload;
function ExcludedDirsText(const AList: TArray<string>): string; overload;
function IsSourceFile(const AFileName: string): Boolean;
function ScanProject(const ARoot: string; const AExclude: TArray<string>;
  const AProgress: TScanProgress = nil): TProjectScan;
// volta a analisar um so ficheiro (caminho relativo com '/') e actualiza AScan: junta, altera ou
// retira a unit conforme o estado no disco. Nao e thread-safe (usa as regex partilhadas do modulo).
function RescanFile(AScan: TProjectScan; const ARelPath: string): TRescanKind; overload;
function RescanFile(AScan: TProjectScan; const ARelPath: string; out AChange: TScanChange): TRescanKind; overload;
// compara os ficheiros no disco com as units da analise e junta/retira as que faltam ou sobram
// (pastas criadas, renomeadas ou apagadas); acrescenta a AChanges o que mudou
procedure ReconcileScan(AScan: TProjectScan; AChanges: TList<TScanChange>);
// o caminho relativo passa por uma pasta ignorada?
function IsPathExcluded(AScan: TProjectScan; const ARelPath: string): Boolean;
function ExtractMethods(const AFilePath: string): TArray<TMethodInfo>;
// o mesmo a partir de texto Delphi; sem "interface" o texto e tratado como declaracoes da interface
function ExtractMethodsFromText(const AText: string): TArray<TMethodInfo>;
// preenche Path/Dir/FileName/Layer de uma unit a partir do caminho relativo ('a/b/x.pas')
procedure SetUnitPath(U: TUnitInfo; const ARel: string);
// recalcula Folders/TotalMethods/UnitsWithMethods
procedure RecountScan(AScan: TProjectScan);
function SlugOf(const AText: string): string;

implementation

type
  // declaracao encontrada, antes de fundir interface/implementation e de atribuir o nome unico
  TRawMethod = record
    Owner: string;
    Simple: string;
    Kind: string;
    Sig: string;
    Params: string;     // so os tipos dos parametros ('Integer, string'); '' = sem parametros
    Lines, Complexity: Integer;   // medidas do corpo (0 = ainda sem medida)
  end;

var
  GReInterface: TRegEx;
  GReImplementation: TRegEx;
  GReDecl: TRegEx;
  GReSpaces: TRegEx;
  GReTypeHead: TRegEx;      // 'TFoo = class(...)' / record / object / interface
  GReAncestors: TRegEx;     // '(TBar, IFoo)' e sealed/abstract logo a seguir a 'class'
  GReLeadingEnd: TRegEx;
  GReTrailingEnd: TRegEx;
  GReStartsBegin: TRegEx;

const
  ReservedWords: array[0..9] of string =
    ('begin', 'var', 'const', 'type', 'asm', 'end', 'try', 'except', 'finally', 'of');

function IsReserved(const AWord: string): Boolean;
var
  W: string;
begin
  for W in ReservedWords do
    if SameText(W, AWord) then
      Exit(True);
  Result := False;
end;

function DefaultExcludeList: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, Length(DefaultExcludeDirs));
  for I := Low(DefaultExcludeDirs) to High(DefaultExcludeDirs) do
    Result[I - Low(DefaultExcludeDirs)] := DefaultExcludeDirs[I];
end;

function ParseExcludeDirs(const AText: string): TArray<string>;
var
  Part, Name: string;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    for Part in AText.Split([',', ';', #13, #10]) do
    begin
      Name := Part.Trim;
      if Name <> '' then
        List.Add(Name);
    end;
    if List.Count = 0 then
      Result := DefaultExcludeList
    else
      Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function ExcludedDirsText(const AList: TArray<string>): string;
begin
  Result := string.Join(', ', AList);
end;

function ExcludedDirsText: string;
begin
  Result := ExcludedDirsText(DefaultExcludeList);
end;

function SlugOf(const AText: string): string;
var
  C: Char;
  LastDash: Boolean;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    LastDash := True;
    for C in AText.ToLowerInvariant do
      if CharInSet(C, ['a'..'z', '0'..'9']) then
      begin
        SB.Append(C);
        LastDash := False;
      end
      else if not LastDash then
      begin
        SB.Append('-');
        LastDash := True;
      end;
    Result := SB.ToString.TrimRight(['-']);
  finally
    SB.Free;
  end;
  if Result = '' then
    Result := 'projecto';
end;

{ TUnitInfo }

function TUnitInfo.MethodStatus(AIndex: Integer): TPlanStatus;
begin
  if (AIndex >= 0) and (AIndex < Length(MethodPlan)) then
    Result := MethodPlan[AIndex]
  else
    Result := psNone;
end;

function TUnitInfo.Ext: string;
begin
  Result := TPath.GetExtension(FileName);
end;

function TUnitInfo.BaseName: string;
begin
  Result := Copy(FileName, 1, Length(FileName) - Length(Ext));
end;

{ TProjectScan }

constructor TProjectScan.Create;
begin
  inherited;
  Units := TObjectList<TUnitInfo>.Create(True);
end;

destructor TProjectScan.Destroy;
begin
  Units.Free;
  inherited;
end;

// Limpeza do texto: strings passam a '', e os comentarios (chavetas, parenteses-asterisco
// e barras duplas) sao removidos. Passagem unica (ao contrario de varias regexes em
// sequencia), por isso um apostrofo dentro de um comentario nao e confundido com uma string.
function CleanUnitText(const AText: string): string;
var
  SB: TStringBuilder;
  I, N: Integer;
  C: Char;
begin
  N := Length(AText);
  SB := TStringBuilder.Create(N);
  try
    I := 1;
    while I <= N do
    begin
      C := AText[I];
      if C = '''' then
      begin
        // string literal: nao atravessa linhas; '' dentro da string e um apostrofo escapado
        Inc(I);
        while I <= N do
        begin
          if AText[I] = '''' then
          begin
            if (I < N) and (AText[I + 1] = '''') then
              Inc(I, 2)
            else
              Break;
          end
          else if (AText[I] = #13) or (AText[I] = #10) then
            Break
          else
            Inc(I);
        end;
        if (I <= N) and (AText[I] = '''') then
          Inc(I);
        SB.Append('''''');
      end
      else if C = '{' then
      begin
        Inc(I);
        SB.Append(' ');
        while (I <= N) and (AText[I] <> '}') do
        begin
          if AText[I] = #10 then
            SB.Append(#10);          // as linhas contam-se no texto limpo (medidas dos metodos)
          Inc(I);
        end;
        Inc(I);
      end
      else if (C = '(') and (I < N) and (AText[I + 1] = '*') then
      begin
        Inc(I, 2);
        SB.Append(' ');
        while (I < N) and not ((AText[I] = '*') and (AText[I + 1] = ')')) do
        begin
          if AText[I] = #10 then
            SB.Append(#10);
          Inc(I);
        end;
        Inc(I, 2);
      end
      else if (C = '/') and (I < N) and (AText[I + 1] = '/') then
      begin
        while (I <= N) and (AText[I] <> #13) and (AText[I] <> #10) do
          Inc(I);
      end
      else
      begin
        SB.Append(C);
        Inc(I);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure SplitSections(const AText: string; out AInterface, AImplementation: string);
var
  MI, MM: TMatch;
begin
  MI := GReInterface.Match(AText);
  MM := GReImplementation.Match(AText);
  if MI.Success and MM.Success and (MM.Index > MI.Index) then
  begin
    AInterface := Copy(AText, MI.Index + MI.Length, MM.Index - (MI.Index + MI.Length));
    AImplementation := Copy(AText, MM.Index + MM.Length, MaxInt);
  end
  else if MM.Success then
  begin
    AInterface := '';
    AImplementation := Copy(AText, MM.Index + MM.Length, MaxInt);
  end
  else
  begin
    AInterface := '';
    AImplementation := AText;
  end;
end;

procedure TopLevelStatements(const AText: string; AStatements: TStrings);
var
  SB: TStringBuilder;
  Depth: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    for C in AText do
    begin
      if C = '(' then
        Inc(Depth)
      else if C = ')' then
        Dec(Depth);
      if (C = ';') and (Depth <= 0) then
      begin
        AStatements.Add(SB.ToString);
        SB.Clear;
      end
      else
        SB.Append(C);
    end;
    if SB.Length > 0 then
      AStatements.Add(SB.ToString);
  finally
    SB.Free;
  end;
end;

// PCRE omite de Groups os grupos finais que nao participaram no match
function GroupText(const AMatch: TMatch; AIndex: Integer): string;
begin
  if AIndex < AMatch.Groups.Count then
    Result := AMatch.Groups[AIndex].Value
  else
    Result := '';
end;

// Tira os parametros de tipo genericos e os espacos: 'TFoo<T>.Bar' -> 'TFoo.Bar'
function StripGenerics(const AText: string): string;
var
  SB: TStringBuilder;
  C: Char;
  Depth: Integer;
begin
  SB := TStringBuilder.Create(Length(AText));
  try
    Depth := 0;
    for C in AText do
      if C = '<' then
        Inc(Depth)
      else if C = '>' then
      begin
        if Depth > 0 then
          Dec(Depth);
      end
      else if (Depth = 0) and (C > ' ') then
        SB.Append(C);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// 'TOuter.TInner.Bar' -> Owner 'TOuter.TInner', Simple 'Bar'
procedure SplitQualified(const AQualified: string; out AOwner, ASimple: string);
var
  S: string;
  P: Integer;
begin
  S := StripGenerics(AQualified);
  P := S.LastIndexOf('.');
  if P < 0 then
  begin
    AOwner := '';
    ASimple := S;
  end
  else
  begin
    AOwner := Copy(S, 1, P);
    ASimple := Copy(S, P + 2, MaxInt);
  end;
end;

// ARest e o texto logo a seguir ao nome do metodo. Devolve so os tipos dos parametros, um por
// parametro ('A, B: Integer; const S: string' -> 'Integer, Integer, string'), para distinguir
// overloads sem depender dos nomes dos parametros (a interface e a implementation podem diferir).
function ParamTypes(const ARest: string): string;
var
  S, Content: string;
  I, Depth, Start, EndPos: Integer;
  C: Char;
  Types: TList<string>;

  procedure AddGroup(const AGroup: string);
  var
    Group, NamePart, TypePart: string;
    P, Q, K, Cnt: Integer;
    Ch: Char;
  begin
    Group := AGroup.Trim;
    if Group = '' then
      Exit;
    P := Group.IndexOf(':');
    if P < 0 then
    begin
      NamePart := Group;
      TypePart := 'untyped';
    end
    else
    begin
      NamePart := Copy(Group, 1, P);
      TypePart := Copy(Group, P + 2, MaxInt);
      Q := TypePart.IndexOf('=');       // valor por omissao
      if Q >= 0 then
        TypePart := Copy(TypePart, 1, Q);
      TypePart := GReSpaces.Replace(TypePart, ' ').Trim;
    end;
    Cnt := 1;
    for Ch in NamePart do
      if Ch = ',' then
        Inc(Cnt);
    for K := 1 to Cnt do
      Types.Add(TypePart);
  end;

begin
  S := ARest.TrimLeft;
  if (S = '') or (S[1] <> '(') then
    Exit('');
  Depth := 0;
  EndPos := 0;
  for I := 1 to Length(S) do
    if S[I] = '(' then
      Inc(Depth)
    else if S[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        EndPos := I;
        Break;
      end;
    end;
  if EndPos = 0 then
    Exit('');
  Content := Copy(S, 2, EndPos - 2);
  Types := TList<string>.Create;
  try
    Depth := 0;
    Start := 1;
    for I := 1 to Length(Content) + 1 do
    begin
      if I <= Length(Content) then
        C := Content[I]
      else
        C := ';';
      if C = '(' then
        Inc(Depth)
      else if C = ')' then
        Dec(Depth)
      else if (C = ';') and (Depth = 0) then
      begin
        AddGroup(Copy(Content, Start, I - Start));
        Start := I + 1;
      end;
    end;
    Result := string.Join(', ', Types.ToArray);
  finally
    Types.Free;
  end;
end;

function LastDeclMatch(const AStatement: string; out AMatch: TMatch): Boolean;
var
  Ms: TMatchCollection;
  I: Integer;
  Owner, Simple: string;
begin
  Ms := GReDecl.Matches(AStatement);
  for I := Ms.Count - 1 downto 0 do
  begin
    SplitQualified(GroupText(Ms[I], 3), Owner, Simple);
    if IsReserved(Simple) then
      Continue;
    AMatch := Ms[I];
    Exit(True);
  end;
  Result := False;
end;

// Percorre as instrucoes de topo de uma secao, acompanhando em que tipo (class/record/interface...)
// se esta, para saber a que classe pertence cada metodo declarado sem qualificacao. Numa
// implementation os metodos ja vem qualificados ('TFoo.Bar'); numa interface vem dentro do tipo.
procedure CollectFromSection(const ASection: string; ARaw: TList<TRawMethod>);
var
  Stmts: TStringList;
  Stack: TList<string>;
  Stmt, Rest, Owner, Simple, QOwner, Prefix: string;
  Head, M: TMatch;
  Pushed, ClassPrefix: Boolean;
  R: TRawMethod;
begin
  Stmts := TStringList.Create;
  Stack := TList<string>.Create;
  try
    TopLevelStatements(ASection, Stmts);
    for Stmt in Stmts do
    begin
      // um corpo de metodo nunca esta dentro de um tipo: limpa qualquer contexto falso
      if GReStartsBegin.IsMatch(Stmt) then
        Stack.Clear;

      Head := GReTypeHead.Match(Stmt);
      Pushed := False;
      if Head.Success then
      begin
        // 'TFoo = class;' (forward), 'TFoo = class(TBar);' e 'TFoo = class end;' nao abrem contexto
        Rest := GReAncestors.Replace(GroupText(Head, 3), '', 1).Trim;
        if (Rest <> '') and not GReLeadingEnd.IsMatch(Rest) then
        begin
          Stack.Add(StripGenerics(GroupText(Head, 1)));
          Pushed := True;
        end;
      end;

      if LastDeclMatch(Stmt, M) then
      begin
        SplitQualified(GroupText(M, 3), QOwner, Simple);
        Owner := QOwner;
        if Owner = '' then
          Owner := string.Join('.', Stack.ToArray);
        // 'TFoo = class procedure Bar' - o 'class' da declaracao do tipo nao e prefixo do metodo
        ClassPrefix := (GroupText(M, 1) <> '') and
          not (Head.Success and (M.Groups[1].Index = Head.Groups[2].Index));
        R := Default(TRawMethod);
        R.Owner := Owner;
        R.Simple := Simple;
        R.Kind := LowerCase(GroupText(M, 2));
        Prefix := '';
        if ClassPrefix then
        begin
          R.Kind := 'class ' + R.Kind;
          Prefix := 'class ';
        end;
        Rest := Copy(Stmt, M.Index + M.Length, MaxInt);       // o que vem a seguir ao nome
        if GReTrailingEnd.IsMatch(Rest) then
          Rest := GReTrailingEnd.Replace(Rest, '');
        R.Params := ParamTypes(Rest);
        // a assinatura mostra sempre a classe, mesmo quando a interface a declara dentro do tipo
        if Owner <> '' then
          R.Sig := Prefix + GroupText(M, 2) + ' ' + Owner + '.' + Simple + Rest
        else
          R.Sig := Prefix + GroupText(M, 2) + ' ' + Simple + Rest;
        R.Sig := GReSpaces.Replace(R.Sig, ' ').Trim;
        if not R.Sig.EndsWith(';') then
          R.Sig := R.Sig + ';';
        ARaw.Add(R);
      end;

      // 'end' final fecha o tipo (nao se aplica a um cabecalho que ja se fechou a si proprio)
      if (Stack.Count > 0) and GReTrailingEnd.IsMatch(Stmt) and (Pushed or not Head.Success) then
        Stack.Delete(Stack.Count - 1);
    end;
  finally
    Stack.Free;
    Stmts.Free;
  end;
end;

// le um cabecalho de rotina ('procedure TFoo.Bar(A: Integer)') como a analise das declaracoes o faz
function ParseHeader(const AHeader: string; out R: TRawMethod): Boolean;
var
  M: TMatch;
  QOwner, Simple, Rest: string;
begin
  R := Default(TRawMethod);
  Result := LastDeclMatch(AHeader, M);
  if not Result then
    Exit;
  SplitQualified(GroupText(M, 3), QOwner, Simple);
  R.Owner := QOwner;
  R.Simple := Simple;
  Rest := Copy(AHeader, M.Index + M.Length, MaxInt);
  R.Params := ParamTypes(Rest);
end;

function SameParams(const A, B: string): Boolean;
begin
  Result := SameText(A.Replace(' ', ''), B.Replace(' ', ''));
end;

function FindRaw(AList: TList<TRawMethod>; const R: TRawMethod): Integer;
var
  I, Found, Count: Integer;
begin
  for I := 0 to AList.Count - 1 do
    if SameText(AList[I].Owner, R.Owner) and SameText(AList[I].Simple, R.Simple) and
       SameParams(AList[I].Params, R.Params) then
      Exit(I);
  // a implementation pode repetir uma rotina livre sem parametros ('procedure Foo;' para
  // 'procedure Foo(A: Integer)'): se so ha um candidato com esse nome, e o mesmo
  Found := -1;
  Count := 0;
  if R.Params = '' then
    for I := 0 to AList.Count - 1 do
      if SameText(AList[I].Owner, R.Owner) and SameText(AList[I].Simple, R.Simple) then
      begin
        Found := I;
        Inc(Count);
      end;
  if Count = 1 then
    Result := Found
  else
    Result := -1;
end;

// Funde a interface com a implementation (a mesma declaracao aparece nas duas) e atribui a cada
// metodo um nome unico na unit. O primeiro fica com 'TFoo.Bar' - para nao perder o progresso
// guardado quando se acrescenta um overload - e os seguintes com 'TFoo.Bar(Integer)'.
function MergeMethods(ARaw: TList<TRawMethod>): TArray<TMethodInfo>;
var
  Merged: TList<TRawMethod>;
  Counts: TDictionary<string, Integer>;
  Used: THashSet<string>;
  Items: TList<TMethodInfo>;
  R: TRawMethod;
  Info: TMethodInfo;
  Base, Name, Cand: string;
  N, Cnt: Integer;
begin
  Merged := TList<TRawMethod>.Create;
  Counts := TDictionary<string, Integer>.Create;
  Used := THashSet<string>.Create;
  Items := TList<TMethodInfo>.Create;
  try
    for R in ARaw do
      if FindRaw(Merged, R) < 0 then
        Merged.Add(R);
    for R in Merged do
    begin
      if R.Owner <> '' then
        Base := R.Owner + '.' + R.Simple
      else
        Base := R.Simple;
      if Counts.TryGetValue(LowerCase(Base), Cnt) then
      begin
        Counts[LowerCase(Base)] := Cnt + 1;
        Name := Base + '(' + R.Params + ')';
      end
      else
      begin
        Counts.Add(LowerCase(Base), 1);
        Name := Base;
      end;
      Cand := Name;
      N := 2;
      while not Used.Add(LowerCase(Cand)) do
      begin
        Cand := Name + '#' + IntToStr(N);
        Inc(N);
      end;
      Info := Default(TMethodInfo);
      Info.Name := Cand;
      Info.Kind := R.Kind;
      Info.Sig := R.Sig;
      Info.Owner := R.Owner;
      Info.Simple := R.Simple;
      Info.Lines := R.Lines;
      Info.Complexity := R.Complexity;
      Items.Add(Info);
    end;
    Result := Items.ToArray;
  finally
    Items.Free;
    Used.Free;
    Counts.Free;
    Merged.Free;
  end;
end;

// mede os corpos da implementation e junta as medidas as declaracoes (a primeira ocorrencia de
// cada metodo e a que passa a unit); uma rotina repetida (aninhada com o mesmo nome) fica com a primeira
procedure ApplyMetrics(const AImpl: string; ARaw: TList<TRawMethod>);
var
  Measures: TList<TRoutineMetric>;
  Metric: TRoutineMetric;
  Key: TRawMethod;
  Idx: Integer;
  Target: TRawMethod;
begin
  Measures := TList<TRoutineMetric>.Create;
  try
    MeasureRoutines(AImpl, Measures);
    for Metric in Measures do
      if ParseHeader(Metric.Header, Key) then
      begin
        Idx := FindRaw(ARaw, Key);
        if Idx < 0 then
          Continue;
        Target := ARaw[Idx];
        if Target.Lines = 0 then
        begin
          Target.Lines := Metric.Lines;
          Target.Complexity := Metric.Complexity;
          ARaw[Idx] := Target;
        end;
      end;
  finally
    Measures.Free;
  end;
end;

function ReadSourceText(const AFilePath: string): string;
var
  Bytes: TBytes;
  Enc: TEncoding;
  Skip: Integer;
begin
  Bytes := TFile.ReadAllBytes(AFilePath);
  Enc := nil;
  Skip := TEncoding.GetBufferEncoding(Bytes, Enc, TEncoding.UTF8);
  try
    Result := Enc.GetString(Bytes, Skip, Length(Bytes) - Skip);
  except
    on EEncodingError do   // ficheiro em ANSI (acentos em comentarios): nao e UTF-8 valido
      Result := TEncoding.ANSI.GetString(Bytes, Skip, Length(Bytes) - Skip);
  end;
end;

function ExtractMethods(const AFilePath: string): TArray<TMethodInfo>;
begin
  Result := ExtractMethodsFromText(ReadSourceText(AFilePath));
end;

function ExtractMethodsFromText(const AText: string): TArray<TMethodInfo>;
var
  Clean, Iface, Impl, Bodies: string;
  Raw: TList<TRawMethod>;
begin
  Clean := CleanUnitText(AText);
  Bodies := '';
  if not GReInterface.IsMatch(Clean) then
  begin
    Bodies := Clean;            // programas e fragmentos: os corpos estao no texto todo
    Clean := 'unit Plano;' + sLineBreak + 'interface' + sLineBreak + Clean + sLineBreak +
      'implementation' + sLineBreak + 'end.';
  end;
  SplitSections(Clean, Iface, Impl);
  Raw := TList<TRawMethod>.Create;
  try
    CollectFromSection(Iface, Raw);
    CollectFromSection(Impl, Raw);
    if Bodies <> '' then
      ApplyMetrics(Bodies, Raw)
    else
      ApplyMetrics(Impl, Raw);
    Result := MergeMethods(Raw);
  finally
    Raw.Free;
  end;
end;

function IsSourceFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := TPath.GetExtension(AFileName);
  Result := SameText(Ext, '.pas') or SameText(Ext, '.dpr') or SameText(Ext, '.dpk');
end;

function IsExcludedDir(const AName: string; const AExclude: TArray<string>): Boolean;
var
  Ex: string;
begin
  for Ex in AExclude do
    if SameText(Ex, AName) then
      Exit(True);
  Result := False;
end;

// alguma das pastas do caminho relativo ('a/b/x.pas' -> a, b) esta na lista de ignoradas?
function IsPathExcluded(AScan: TProjectScan; const ARelPath: string): Boolean;
var
  Parts: TArray<string>;
  I: Integer;
begin
  Parts := ARelPath.Split(['/']);
  for I := 0 to High(Parts) - 1 do
    if IsExcludedDir(Parts[I], AScan.ExcludeDirs) then
      Exit(True);
  Result := False;
end;

procedure CollectFiles(const ADir, ARelDir: string; const AExclude: TArray<string>; AFiles: TStrings);
var
  Sub, F, Name: string;
begin
  try
    for F in TDirectory.GetFiles(ADir) do
    begin
      Name := TPath.GetFileName(F);
      if IsSourceFile(Name) then
        AFiles.Add(ARelDir + Name);
    end;
    for Sub in TDirectory.GetDirectories(ADir) do
    begin
      Name := TPath.GetFileName(Sub);
      if not IsExcludedDir(Name, AExclude) then
        CollectFiles(Sub, ARelDir + Name + '/', AExclude, AFiles);
    end;
  except
    on E: Exception do ;   // pasta inacessivel ou caminho invalido: ignorar
  end;
end;

function CompareRelPaths(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareText(List[Index1], List[Index2]);
end;

function ParentDir(const ADir: string): string;
var
  P: Integer;
begin
  P := ADir.LastIndexOf('/');
  if P < 0 then
    Result := ''
  else
    Result := Copy(ADir, 1, P);
end;

// preenche Path/Dir/FileName/Layer de uma unit a partir do caminho relativo ('a/b/x.pas')
procedure SetUnitPath(U: TUnitInfo; const ARel: string);
var
  P: Integer;
  Seg: string;
begin
  U.Path := ARel;
  P := ARel.LastIndexOf('/');
  if P < 0 then
  begin
    U.Dir := '';
    U.FileName := ARel;
    U.Layer := 'Raiz';
  end
  else
  begin
    U.Dir := Copy(ARel, 1, P);
    U.FileName := Copy(ARel, P + 2, MaxInt);
    Seg := U.Dir;
    if Seg.LastIndexOf('/') >= 0 then
      Seg := Copy(Seg, Seg.LastIndexOf('/') + 2, MaxInt);
    U.Layer := Seg;
  end;
end;

// totais derivados da lista de units (pastas com codigo, metodos, units com metodos)
procedure RecountScan(AScan: TProjectScan);
var
  Folders: THashSet<string>;
  U: TUnitInfo;
  Dir: string;
begin
  AScan.TotalMethods := 0;
  AScan.UnitsWithMethods := 0;
  Folders := THashSet<string>.Create;
  try
    for U in AScan.Units do
    begin
      Inc(AScan.TotalMethods, Length(U.Methods));
      if Length(U.Methods) > 0 then
        Inc(AScan.UnitsWithMethods);
      Dir := U.Dir;
      while Dir <> '' do
      begin
        Folders.Add(Dir);
        Dir := ParentDir(Dir);
      end;
    end;
    AScan.Folders := Folders.Count;
  finally
    Folders.Free;
  end;
end;

function ScanProject(const ARoot: string; const AExclude: TArray<string>;
  const AProgress: TScanProgress): TProjectScan;
var
  Root: string;
  Rels: TStringList;
  I: Integer;
  Rel: string;
  U: TUnitInfo;
begin
  Root := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ARoot));
  if not TDirectory.Exists(Root) then
    raise Exception.CreateFmt('A pasta do projecto nao existe: %s', [Root]);

  Result := TProjectScan.Create;
  Rels := TStringList.Create;
  try
    try
      Result.Root := Root;
      if Length(AExclude) = 0 then
        Result.ExcludeDirs := DefaultExcludeList
      else
        Result.ExcludeDirs := AExclude;
      if Assigned(AProgress) then
        AProgress('A procurar unidades .pas/.dpr/.dpk...', 0, 0);
      CollectFiles(Root, '', Result.ExcludeDirs, Rels);
      Rels.CustomSort(CompareRelPaths);
      if Rels.Count = 0 then
        raise Exception.CreateFmt(
          'Nao foi encontrada nenhuma unidade .pas/.dpr/.dpk em "%s" (fora das pastas ignoradas).', [Root]);

      for I := 0 to Rels.Count - 1 do
      begin
        Rel := Rels[I];
        U := TUnitInfo.Create;
        Result.Units.Add(U);
        SetUnitPath(U, Rel);
        try
          U.Methods := ExtractMethods(TPath.Combine(Root, Rel.Replace('/', PathDelim)));
        except
          on E: Exception do
            U.Methods := nil;   // unit ilegivel: fica sem metodos, como nos scripts originais
        end;
        if Assigned(AProgress) then
          AProgress('A analisar metodos... ' + Rel, I + 1, Rels.Count);
      end;
      RecountScan(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Rels.Free;
  end;
end;

function SameMethods(const A, B: TArray<TMethodInfo>): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
    if (A[I].Name <> B[I].Name) or (A[I].Sig <> B[I].Sig) or (A[I].Lines <> B[I].Lines) or
       (A[I].Complexity <> B[I].Complexity) then
      Exit(False);
  Result := True;
end;

function FindUnitIndex(AScan: TProjectScan; const ARelPath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to AScan.Units.Count - 1 do
    if SameText(AScan.Units[I].Path, ARelPath) then
      Exit(I);
  Result := -1;
end;

function RescanFile(AScan: TProjectScan; const ARelPath: string; out AChange: TScanChange): TRescanKind; overload;
var
  Idx, Pos, I, J: Integer;
  Full: string;
  U: TUnitInfo;
  Old, NewMethods: TArray<TMethodInfo>;
  Readable, Found: Boolean;
  Names: TList<string>;
begin
  Result := rcNone;
  AChange := Default(TScanChange);
  AChange.Path := ARelPath;
  Idx := FindUnitIndex(AScan, ARelPath);
  Full := TPath.Combine(AScan.Root, ARelPath.Replace('/', PathDelim));
  if IsSourceFile(ARelPath) and not IsPathExcluded(AScan, ARelPath) and TFile.Exists(Full) then
  begin
    Readable := True;
    try
      NewMethods := ExtractMethods(Full);
    except
      on E: Exception do
      begin
        Readable := False;      // p.ex. o IDE ainda esta a gravar o ficheiro
        NewMethods := nil;
      end;
    end;
    if Idx < 0 then
    begin
      U := TUnitInfo.Create;
      SetUnitPath(U, ARelPath);
      U.Methods := NewMethods;
      Pos := 0;                 // a lista esta ordenada por caminho, como na analise completa
      while (Pos < AScan.Units.Count) and (CompareText(AScan.Units[Pos].Path, ARelPath) < 0) do
        Inc(Pos);
      AScan.Units.Insert(Pos, U);
      Result := rcAdded;
      SetLength(AChange.NewMethods, Length(NewMethods));
      for I := 0 to High(NewMethods) do
        AChange.NewMethods[I] := NewMethods[I].Name;
    end
    else if Readable and not SameMethods(AScan.Units[Idx].Methods, NewMethods) then
    begin
      Old := AScan.Units[Idx].Methods;
      Names := TList<string>.Create;
      try
        for I := 0 to High(NewMethods) do
        begin
          Found := False;       // novo, ou com a assinatura alterada
          for J := 0 to High(Old) do
            if (Old[J].Name = NewMethods[I].Name) and (Old[J].Sig = NewMethods[I].Sig) then
            begin
              Found := True;
              Break;
            end;
          if not Found then
            Names.Add(NewMethods[I].Name);
        end;
        AChange.NewMethods := Names.ToArray;
      finally
        Names.Free;
      end;
      AScan.Units[Idx].Methods := NewMethods;
      Result := rcChanged;
    end;
  end
  else if Idx >= 0 then
  begin
    AScan.Units.Delete(Idx);
    Result := rcRemoved;
  end;
  AChange.Kind := Result;
  if Result <> rcNone then
    RecountScan(AScan);
end;

function RescanFile(AScan: TProjectScan; const ARelPath: string): TRescanKind; overload;
var
  Change: TScanChange;
begin
  Result := RescanFile(AScan, ARelPath, Change);
end;

procedure ReconcileScan(AScan: TProjectScan; AChanges: TList<TScanChange>);
var
  OnDisk: TStringList;
  Known: THashSet<string>;
  Stale: TList<string>;
  U: TUnitInfo;
  Rel: string;
  Change: TScanChange;
begin
  OnDisk := TStringList.Create;
  Known := THashSet<string>.Create;
  Stale := TList<string>.Create;
  try
    CollectFiles(AScan.Root, '', AScan.ExcludeDirs, OnDisk);
    for Rel in OnDisk do
      Known.Add(LowerCase(Rel));
    for U in AScan.Units do
      if not Known.Contains(LowerCase(U.Path)) then
        Stale.Add(U.Path);
    for Rel in Stale do
      if RescanFile(AScan, Rel, Change) <> rcNone then
        AChanges.Add(Change);
    for Rel in OnDisk do
      if FindUnitIndex(AScan, Rel) < 0 then
        if RescanFile(AScan, Rel, Change) <> rcNone then
          AChanges.Add(Change);
  finally
    Stale.Free;
    Known.Free;
    OnDisk.Free;
  end;
end;

initialization
  GReInterface := TRegEx.Create('^\s*interface\s*$', [roIgnoreCase, roMultiLine]);
  GReImplementation := TRegEx.Create('^\s*implementation\s*$', [roIgnoreCase, roMultiLine]);
  // [class] function|procedure|constructor|destructor Nome[<T>][.Nome[<T>]...]
  GReDecl := TRegEx.Create(
    '\b(class\s+)?(function|procedure|constructor|destructor)\s+' +
    '([A-Za-z_][A-Za-z0-9_]*(?:<[^<>;]*(?:<[^<>;]*>[^<>;]*)*>)?' +
    '(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*(?:<[^<>;]*(?:<[^<>;]*>[^<>;]*)*>)?)*)',
    [roIgnoreCase]);
  GReSpaces := TRegEx.Create('\s+', []);
  // TFoo[<T>] = [packed] class|record|object|interface|dispinterface  (nao 'class of')
  GReTypeHead := TRegEx.Create(
    '\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^=;]*>)?\s*=\s*(?:packed\s+)?' +
    '(class|record|object|interface|dispinterface)\b(?!\s+of\b)([\s\S]*)$',
    [roIgnoreCase]);
  GReAncestors := TRegEx.Create('^\s*(?:(?:sealed|abstract)\b\s*)*(?:\(\s*[^()]*\)\s*)?', [roIgnoreCase]);
  GReLeadingEnd := TRegEx.Create('^end\b', [roIgnoreCase]);
  GReTrailingEnd := TRegEx.Create('\bend\s*$', [roIgnoreCase]);
  GReStartsBegin := TRegEx.Create('^\s*begin\b', [roIgnoreCase]);

end.
