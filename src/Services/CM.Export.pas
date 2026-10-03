unit CM.Export;

{ Exportacao da estrutura do projecto (pastas > ficheiros > metodos) para Markdown, TXT, CSV e JSON.
  Todos os formatos partem da mesma lista plana de linhas (FlattenStructure), pela mesma ordem da
  vista Mapa: em cada pasta primeiro as subpastas e depois os ficheiros, por ordem alfabetica.
  A impressao reutiliza essa lista. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.IOUtils, System.JSON, CM.Analyzer, CM.Store, CM.Stats;

type
  TExportFormat = (efMarkdown, efText, efCsv, efJson);

  TExportOptions = record
    IncludeMethods: Boolean;
    IncludeProgress: Boolean;   // concluido, Compila, Sonar, prioridade e notas
  end;

  TExportRowKind = (xkDir, xkFile, xkMethod);

  TExportRow = record
    Kind: TExportRowKind;
    Level: Integer;
    Name: string;         // pasta, ficheiro ou metodo (TMethodInfo.Name)
    Path: string;         // caminho relativo da pasta ou do ficheiro
    U: TUnitInfo;         // ficheiro (tambem nas linhas de metodo); nil nas pastas
    MIndex: Integer;      // indice em U.Methods nos metodos; -1 nos outros
    FileCount: Integer;   // pastas: ficheiros la dentro (recursivo)
  end;

  TRowProgress = record
    Done, Star, Compila, Sonar: Boolean;
    Note: string;
  end;

  // uma linha da arvore ASCII: Prefix + Text; se Text quebrar, as linhas seguintes levam ContPrefix
  TTreeLine = record
    Row: TExportRow;
    Prefix: string;       // guias e conector ('|   +-- ')
    ContPrefix: string;   // guias das linhas de continuacao
    Text: string;         // etiqueta, com marcas de estado se pedido
  end;

function ExportFormatName(AFormat: TExportFormat): string;
function ExportFormatExt(AFormat: TExportFormat): string;
function ExportDefaultFileName(AProfile: TProjectProfile; AFormat: TExportFormat): string;

function FlattenStructure(AScan: TProjectScan; AIncludeMethods: Boolean): TArray<TExportRow>;
function RowProgress(const ARow: TExportRow; AState: TProgressState): TRowProgress;

// linhas de cabecalho (pasta raiz, data, totais e, se pedido, progresso)
function ExportHeaderLines(AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): TArray<string>;
// a arvore ASCII pronta a escrever (TXT) ou a imprimir
function BuildTreeLines(AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): TArray<TTreeLine>;

function BuildExport(AFormat: TExportFormat; AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOptions: TExportOptions): string;
procedure ExportToFile(AFormat: TExportFormat; AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOptions: TExportOptions; const AFileName: string);

// os construtores por formato (chamados por BuildExport) e o escape de campos CSV: expostos so
// para serem testados directamente (Tests.Export.Formats), sem passar pelo dispatch por formato
function BuildMarkdown(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
function BuildText(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
function BuildCsv(AScan: TProjectScan; AState: TProgressState; const AOptions: TExportOptions): string;
function BuildJson(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
// separador ';' (o Excel em portugues abre-o em colunas); campos com ; " ou quebras vao entre aspas
function CsvField(const AText: string): string;
function CsvLine(const AFields: array of string): string;

implementation

type
  TXNode = class
  public
    Name: string;
    Path: string;
    Dirs: TObjectList<TXNode>;
    Files: TList<TUnitInfo>;
    FileCount: Integer;
    constructor Create(const AName, APath: string);
    destructor Destroy; override;
  end;

constructor TXNode.Create(const AName, APath: string);
begin
  inherited Create;
  Name := AName;
  Path := APath;
  Dirs := TObjectList<TXNode>.Create(True);
  Files := TList<TUnitInfo>.Create;
end;

destructor TXNode.Destroy;
begin
  Files.Free;
  Dirs.Free;
  inherited;
end;

function ExportFormatName(AFormat: TExportFormat): string;
begin
  case AFormat of
    efMarkdown: Result := 'Markdown';
    efText: Result := 'Texto (árvore)';
    efCsv: Result := 'CSV (Excel)';
    efJson: Result := 'JSON';
  end;
end;

function ExportFormatExt(AFormat: TExportFormat): string;
begin
  case AFormat of
    efMarkdown: Result := '.md';
    efText: Result := '.txt';
    efCsv: Result := '.csv';
    efJson: Result := '.json';
  end;
end;

function ExportDefaultFileName(AProfile: TProjectProfile; AFormat: TExportFormat): string;
begin
  Result := SlugOf(AProfile.Name) + '-estrutura' + ExportFormatExt(AFormat);
end;

{ ---------------------------------------------------------------- lista plana }

function FindChild(N: TXNode; const AName: string): TXNode;
var
  C: TXNode;
begin
  for C in N.Dirs do
    if C.Name = AName then
      Exit(C);
  Result := nil;
end;

procedure SortNode(N: TXNode);
var
  C: TXNode;
begin
  N.Dirs.Sort(TComparer<TXNode>.Construct(
    function(const A, B: TXNode): Integer
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

function CountFiles(N: TXNode): Integer;
var
  C: TXNode;
begin
  Result := N.Files.Count;
  for C in N.Dirs do
    Inc(Result, CountFiles(C));
  N.FileCount := Result;
end;

procedure BuildTree(AScan: TProjectScan; ARoot: TXNode);
var
  U: TUnitInfo;
  Node, Child: TXNode;
  Seg, Acc: string;
begin
  for U in AScan.Units do
  begin
    Node := ARoot;
    if U.Dir <> '' then
    begin
      Acc := '';
      for Seg in U.Dir.Split(['/']) do
      begin
        if Acc = '' then
          Acc := Seg
        else
          Acc := Acc + '/' + Seg;
        Child := FindChild(Node, Seg);
        if Child = nil then
        begin
          Child := TXNode.Create(Seg, Acc);
          Node.Dirs.Add(Child);
        end;
        Node := Child;
      end;
    end;
    Node.Files.Add(U);
  end;
  SortNode(ARoot);
  CountFiles(ARoot);
end;

procedure EmitNode(N: TXNode; ALevel: Integer; AIncludeMethods: Boolean; ARows: TList<TExportRow>);
var
  C: TXNode;
  U: TUnitInfo;
  R: TExportRow;
  I: Integer;
begin
  for C in N.Dirs do
  begin
    R := Default(TExportRow);
    R.Kind := xkDir;
    R.Level := ALevel;
    R.Name := C.Name;
    R.Path := C.Path;
    R.MIndex := -1;
    R.FileCount := C.FileCount;
    ARows.Add(R);
    EmitNode(C, ALevel + 1, AIncludeMethods, ARows);
  end;
  for U in N.Files do
  begin
    R := Default(TExportRow);
    R.Kind := xkFile;
    R.Level := ALevel;
    R.Name := U.FileName;
    R.Path := U.Path;
    R.U := U;
    R.MIndex := -1;
    ARows.Add(R);
    if AIncludeMethods then
      for I := 0 to High(U.Methods) do
      begin
        R := Default(TExportRow);
        R.Kind := xkMethod;
        R.Level := ALevel + 1;
        R.Name := U.Methods[I].Name;
        R.Path := U.Path;
        R.U := U;
        R.MIndex := I;
        ARows.Add(R);
      end;
  end;
end;

function FlattenStructure(AScan: TProjectScan; AIncludeMethods: Boolean): TArray<TExportRow>;
var
  Root: TXNode;
  Rows: TList<TExportRow>;
begin
  Root := TXNode.Create('', '');
  Rows := TList<TExportRow>.Create;
  try
    BuildTree(AScan, Root);
    EmitNode(Root, 0, AIncludeMethods, Rows);
    Result := Rows.ToArray;
  finally
    Rows.Free;
    Root.Free;
  end;
end;

function RowProgress(const ARow: TExportRow; AState: TProgressState): TRowProgress;
var
  S: TUnitState;
  Name: string;
begin
  Result := Default(TRowProgress);
  if ARow.U = nil then
    Exit;
  S := AState.Find(ARow.U.Path);
  case ARow.Kind of
    xkFile:
      begin
        Result.Done := UnitDone(ARow.U, AState);
        if S <> nil then
        begin
          Result.Star := S.Star;
          Result.Compila := S.Compila;
          Result.Sonar := S.Sonar;
          Result.Note := S.Note;
        end;
      end;
    xkMethod:
      if S <> nil then
      begin
        Name := ARow.U.Methods[ARow.MIndex].Name;
        Result.Done := S.MDone.Contains(Name);
        Result.Compila := S.MCompila.Contains(Name);
        Result.Sonar := S.MSonar.Contains(Name);
      end;
  end;
end;

{ ---------------------------------------------------------------- utilitarios }

function OneLine(const AText: string): string;
begin
  Result := AText.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
end;

function YesNo(AValue: Boolean): string;
begin
  if AValue then
    Result := 'Sim'
  else
    Result := 'Não';
end;

function Plural(ACount: Integer; const ASingular, APlural: string): string;
begin
  if ACount = 1 then
    Result := IntToStr(ACount) + ' ' + ASingular
  else
    Result := IntToStr(ACount) + ' ' + APlural;
end;

// linhas de cabecalho comuns ao Markdown e ao TXT
function ExportHeaderLines(AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): TArray<string>;
var
  St: TStats;
  L: TList<string>;
begin
  L := TList<string>.Create;
  try
    L.Add('Pasta raiz: ' + AScan.Root);
    L.Add('Gerado em: ' + FormatDateTime('yyyy-mm-dd hh:nn', Now));
    L.Add(Plural(AScan.Folders, 'pasta', 'pastas') + ', ' + Plural(AScan.Units.Count, 'ficheiro', 'ficheiros') +
      ', ' + Plural(AScan.TotalMethods, 'método', 'métodos'));
    if AOptions.IncludeProgress then
    begin
      St := ComputeStats(AScan, AState);
      L.Add(Format('Progresso: %d/%d ficheiros concluídos, %d/%d métodos revistos',
        [St.DoneFiles, St.Files, St.DoneMethods, St.Methods]));
    end;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------------- Markdown }

function BuildMarkdown(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
var
  SB: TStringBuilder;
  Rows: TArray<TExportRow>;
  R: TExportRow;
  P: TRowProgress;
  Line, Line2, Mark: string;
begin
  Rows := FlattenStructure(AScan, AOptions.IncludeMethods);
  SB := TStringBuilder.Create;
  try
    SB.Append('# Estrutura do código — ').Append(AProfile.Name).AppendLine.AppendLine;
    for Line in ExportHeaderLines(AScan, AState, AOptions) do
      SB.Append('- ').AppendLine(Line);
    SB.AppendLine.AppendLine('## Estrutura').AppendLine;
    for R in Rows do
    begin
      P := RowProgress(R, AState);
      if AOptions.IncludeProgress and (R.Kind <> xkDir) then
      begin
        if P.Done then
          Mark := '[x] '
        else
          Mark := '[ ] ';
      end
      else
        Mark := '';
      Line := StringOfChar(' ', 2 * R.Level) + '- ' + Mark;
      case R.Kind of
        xkDir:
          Line := Line + '**`' + R.Name + '/`** _(' + Plural(R.FileCount, 'ficheiro', 'ficheiros') + ')_';
        xkFile:
          begin
            Line := Line + '`' + R.Name + '`';
            if (not AOptions.IncludeMethods) and (Length(R.U.Methods) > 0) then
              Line := Line + ' _(' + Plural(Length(R.U.Methods), 'método', 'métodos') + ')_';
          end;
        xkMethod:
          Line := Line + '`' + R.U.Methods[R.MIndex].Sig + '`';
      end;
      if AOptions.IncludeProgress and (R.Kind <> xkDir) then
      begin
        if P.Compila then Line := Line + ' [Compila]';
        if P.Sonar then Line := Line + ' [Sonar]';
        if P.Star then Line := Line + ' ★';
        Line2 := OneLine(P.Note);
        if Line2 <> '' then
          Line := Line + ' — nota: ' + Line2;
      end;
      SB.AppendLine(Line);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---------------------------------------------------------------- TXT (arvore ASCII) }

function IsLastSibling(const ARows: TArray<TExportRow>; AIndex: Integer): Boolean;
var
  J: Integer;
begin
  for J := AIndex + 1 to High(ARows) do
  begin
    if ARows[J].Level < ARows[AIndex].Level then
      Exit(True);
    if ARows[J].Level = ARows[AIndex].Level then
      Exit(False);
  end;
  Result := True;
end;

function BuildTreeLines(AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): TArray<TTreeLine>;
var
  Rows: TArray<TExportRow>;
  R: TExportRow;
  P: TRowProgress;
  AncLast: TArray<Boolean>;     // AncLast[N]: o antepassado ao nivel N era o ultimo da sua pasta?
  I, K, MaxLevel: Integer;
  Line, Guides, Note: string;
  Last: Boolean;
  L: TTreeLine;
begin
  Rows := FlattenStructure(AScan, AOptions.IncludeMethods);
  MaxLevel := 0;
  for R in Rows do
    if R.Level > MaxLevel then
      MaxLevel := R.Level;
  SetLength(AncLast, MaxLevel + 1);
  SetLength(Result, Length(Rows));
  for I := 0 to High(Rows) do
  begin
    R := Rows[I];
    P := RowProgress(R, AState);
    Last := IsLastSibling(Rows, I);
    Guides := '';
    for K := 0 to R.Level - 1 do
      if AncLast[K] then
        Guides := Guides + '    '
      else
        Guides := Guides + '|   ';
    AncLast[R.Level] := Last;

    Line := '';
    if AOptions.IncludeProgress and (R.Kind <> xkDir) then
    begin
      if P.Done then
        Line := '[x] '
      else
        Line := '[ ] ';
    end;
    case R.Kind of
      xkDir: Line := Line + R.Name + '/';
      xkFile:
        begin
          Line := Line + R.Name;
          if (not AOptions.IncludeMethods) and (Length(R.U.Methods) > 0) then
            Line := Line + '  (' + Plural(Length(R.U.Methods), 'método', 'métodos') + ')';
        end;
      xkMethod: Line := Line + R.U.Methods[R.MIndex].Sig;
    end;
    if AOptions.IncludeProgress and (R.Kind <> xkDir) then
    begin
      if P.Compila then Line := Line + ' [Compila]';
      if P.Sonar then Line := Line + ' [Sonar]';
      if P.Star then Line := Line + ' (prioritário)';
      Note := OneLine(P.Note);
      if Note <> '' then
        Line := Line + '  -- nota: ' + Note;
    end;

    L.Row := R;
    if Last then
    begin
      L.Prefix := Guides + '\-- ';
      L.ContPrefix := Guides + '        ';
    end
    else
    begin
      L.Prefix := Guides + '+-- ';
      L.ContPrefix := Guides + '|       ';
    end;
    L.Text := Line;
    Result[I] := L;
  end;
end;

function BuildText(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
var
  SB: TStringBuilder;
  L: TTreeLine;
  Line: string;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('Estrutura do código — ' + AProfile.Name);
    for Line in ExportHeaderLines(AScan, AState, AOptions) do
      SB.AppendLine(Line);
    SB.AppendLine;
    SB.AppendLine(AProfile.Name + '/');
    for L in BuildTreeLines(AScan, AState, AOptions) do
      SB.AppendLine(L.Prefix + L.Text);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---------------------------------------------------------------- CSV }

// separador ';' (o Excel em portugues abre-o em colunas); campos com ; " ou quebras vao entre aspas
function CsvField(const AText: string): string;
begin
  Result := AText;
  // evita que o Excel interprete um texto como formula
  if (Result <> '') and CharInSet(Result[1], ['=', '+', '-', '@']) then
    Result := '''' + Result;
  if Result.Contains(';') or Result.Contains('"') or Result.Contains(#10) or Result.Contains(#13) then
    Result := '"' + Result.Replace('"', '""') + '"';
end;

function CsvLine(const AFields: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AFields) do
  begin
    if I > 0 then
      Result := Result + ';';
    Result := Result + CsvField(AFields[I]);
  end;
  Result := Result + #13#10;
end;

// linhas / complexidade: vazio quando o metodo nao tem corpo medido
function MeasureField(AValue: Integer): string;
begin
  if AValue > 0 then Result := IntToStr(AValue) else Result := '';
end;

function BuildCsv(AScan: TProjectScan; AState: TProgressState; const AOptions: TExportOptions): string;
var
  SB: TStringBuilder;
  R: TExportRow;
  P: TRowProgress;
  M: TMethodInfo;
  Fields: TList<string>;
begin
  SB := TStringBuilder.Create;
  Fields := TList<string>.Create;
  try
    Fields.AddRange(['Nível', 'Pasta', 'Ficheiro', 'Camada', 'Classe', 'Método', 'Tipo', 'Assinatura', 'Linhas',
      'Complexidade']);
    if AOptions.IncludeProgress then
      Fields.AddRange(['Concluído', 'Compila', 'Sonar', 'Prioritário', 'Nota']);
    SB.Append(CsvLine(Fields.ToArray));
    for R in FlattenStructure(AScan, AOptions.IncludeMethods) do
    begin
      if R.Kind = xkDir then
        Continue;
      P := RowProgress(R, AState);
      Fields.Clear;
      if R.Kind = xkFile then
        Fields.AddRange(['Ficheiro', R.U.Dir, R.U.FileName, R.U.Layer, '', '', '', '', '', ''])
      else
      begin
        M := R.U.Methods[R.MIndex];
        Fields.AddRange(['Método', R.U.Dir, R.U.FileName, R.U.Layer, M.Owner, M.Name, M.Kind, M.Sig,
          MeasureField(M.Lines), MeasureField(M.Complexity)]);
      end;
      if AOptions.IncludeProgress then
      begin
        Fields.AddRange([YesNo(P.Done), YesNo(P.Compila), YesNo(P.Sonar)]);
        if R.Kind = xkFile then
          Fields.AddRange([YesNo(P.Star), OneLine(P.Note)])
        else
          Fields.AddRange(['', '']);
      end;
      SB.Append(CsvLine(Fields.ToArray));
    end;
    Result := SB.ToString;
  finally
    Fields.Free;
    SB.Free;
  end;
end;

{ ---------------------------------------------------------------- JSON }

procedure AddProgressJson(AObj: TJSONObject; const AProgress: TRowProgress; AIsFile: Boolean);
begin
  AObj.AddPair('done', TJSONBool.Create(AProgress.Done));
  AObj.AddPair('compila', TJSONBool.Create(AProgress.Compila));
  AObj.AddPair('sonar', TJSONBool.Create(AProgress.Sonar));
  if AIsFile then
  begin
    AObj.AddPair('star', TJSONBool.Create(AProgress.Star));
    AObj.AddPair('note', AProgress.Note);
  end;
end;

function BuildJson(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): string;
var
  Root, Totals, Prog, Obj: TJSONObject;
  Tree, Excl, Kids: TJSONArray;
  Stack: TList<TJSONArray>;
  R: TExportRow;
  P: TRowProgress;
  St: TStats;
  M: TMethodInfo;
  S: string;
begin
  Root := TJSONObject.Create;
  Stack := TList<TJSONArray>.Create;
  try
    Root.AddPair('project', AProfile.Name);
    Root.AddPair('root', AScan.Root);
    Root.AddPair('generatedAt', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    Excl := TJSONArray.Create;
    for S in AScan.ExcludeDirs do
      Excl.Add(S);
    Root.AddPair('excludedFolders', Excl);
    Root.AddPair('includesMethods', TJSONBool.Create(AOptions.IncludeMethods));
    Root.AddPair('includesProgress', TJSONBool.Create(AOptions.IncludeProgress));
    Totals := TJSONObject.Create;
    Totals.AddPair('folders', TJSONNumber.Create(AScan.Folders));
    Totals.AddPair('files', TJSONNumber.Create(AScan.Units.Count));
    Totals.AddPair('methods', TJSONNumber.Create(AScan.TotalMethods));
    Root.AddPair('totals', Totals);
    if AOptions.IncludeProgress then
    begin
      St := ComputeStats(AScan, AState);
      Prog := TJSONObject.Create;
      Prog.AddPair('doneFiles', TJSONNumber.Create(St.DoneFiles));
      Prog.AddPair('doneMethods', TJSONNumber.Create(St.DoneMethods));
      Root.AddPair('progress', Prog);
    end;
    Tree := TJSONArray.Create;
    Root.AddPair('tree', Tree);

    // Stack[N] = lista onde entram os filhos das linhas de nivel N (as linhas vem em pre-ordem)
    Stack.Add(Tree);
    for R in FlattenStructure(AScan, AOptions.IncludeMethods) do
    begin
      while Stack.Count > R.Level + 1 do
        Stack.Delete(Stack.Count - 1);
      Obj := TJSONObject.Create;
      case R.Kind of
        xkDir:
          begin
            Obj.AddPair('type', 'folder');
            Obj.AddPair('name', R.Name);
            Obj.AddPair('path', R.Path);
            Obj.AddPair('files', TJSONNumber.Create(R.FileCount));
            Kids := TJSONArray.Create;
            Obj.AddPair('children', Kids);
            Stack.Add(Kids);
          end;
        xkFile:
          begin
            P := RowProgress(R, AState);
            Obj.AddPair('type', 'file');
            Obj.AddPair('name', R.Name);
            Obj.AddPair('path', R.Path);
            Obj.AddPair('layer', R.U.Layer);
            Obj.AddPair('methodCount', TJSONNumber.Create(Length(R.U.Methods)));
            if AOptions.IncludeProgress then
              AddProgressJson(Obj, P, True);
            if AOptions.IncludeMethods then
            begin
              Kids := TJSONArray.Create;
              Obj.AddPair('methods', Kids);
              Stack.Add(Kids);
            end;
          end;
        xkMethod:
          begin
            M := R.U.Methods[R.MIndex];
            Obj.AddPair('name', M.Name);
            Obj.AddPair('owner', M.Owner);
            Obj.AddPair('kind', M.Kind);
            Obj.AddPair('signature', M.Sig);
            if M.Lines > 0 then
            begin
              Obj.AddPair('lines', TJSONNumber.Create(M.Lines));
              Obj.AddPair('complexity', TJSONNumber.Create(M.Complexity));
            end;
            if AOptions.IncludeProgress then
              AddProgressJson(Obj, RowProgress(R, AState), False);
          end;
      end;
      Stack[R.Level].AddElement(Obj);
    end;
    Result := Root.Format(2);
  finally
    Stack.Free;
    Root.Free;
  end;
end;

{ ---------------------------------------------------------------- entrada }

function BuildExport(AFormat: TExportFormat; AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOptions: TExportOptions): string;
begin
  case AFormat of
    efMarkdown: Result := BuildMarkdown(AProfile, AScan, AState, AOptions);
    efText: Result := BuildText(AProfile, AScan, AState, AOptions);
    efCsv: Result := BuildCsv(AScan, AState, AOptions);
    efJson: Result := BuildJson(AProfile, AScan, AState, AOptions);
  end;
end;

procedure ExportToFile(AFormat: TExportFormat; AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOptions: TExportOptions; const AFileName: string);
var
  Text, Dir: string;
  Enc: TEncoding;
begin
  Text := BuildExport(AFormat, AProfile, AScan, AState, AOptions);
  Dir := TPath.GetDirectoryName(AFileName);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  // TXT e CSV com BOM, para o Bloco de Notas e o Excel reconhecerem o UTF-8
  Enc := TUTF8Encoding.Create(AFormat in [efText, efCsv]);
  try
    TFile.WriteAllText(AFileName, Text, Enc);
  finally
    Enc.Free;
  end;
end;

end.
