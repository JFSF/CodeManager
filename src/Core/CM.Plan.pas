unit CM.Plan;

{ Plano do projecto escrito num documento Markdown e cruzamento com o codigo existente.

  ParsePlan le o documento de forma tolerante e devolve uma analise (TProjectScan) igual a que
  o CM.Analyzer produz para uma pasta, para o resto da aplicacao a tratar da mesma maneira.
  Reconhece, no mesmo documento e por qualquer ordem:
    - titulos com o caminho de um ficheiro (## src/Core/CM.X.pas), seguidos de um bloco de codigo
      Delphi (``` pascal) com a unit ou so as declaracoes;
    - blocos de codigo cujo caminho vem na linha de abertura, num comentario inicial ou no
      "unit X;" (nesse caso fica na pasta do ultimo titulo de pasta);
    - arvores de pastas em blocos de texto (├──, └──, │ ou so indentacao);
    - listas Markdown aninhadas com pastas (**`Core/`**), ficheiros (`CM.X.pas`) e assinaturas
      de metodos - incluindo o formato que a propria aplicacao exporta.
  MergePlan cruza o plano com a analise do codigo e marca cada ficheiro e metodo como
  implementado, por implementar (so no plano) ou extra (so no codigo). }

interface

uses
  System.SysUtils, System.Classes, System.Character, System.Generics.Collections,
  System.Generics.Defaults, System.IOUtils, System.Math, System.RegularExpressions, CM.Analyzer;

type
  TPlanSummary = record
    PlannedFiles, ImplementedFiles, MissingFiles, ExtraFiles: Integer;
    PlannedMethods, ImplementedMethods, MissingMethods, ExtraMethods: Integer;
    // percentagem (0..100) do que esta planeado e ja existe; 0 quando o plano esta vazio
    function FilesCoverage: Double;
    function MethodsCoverage: Double;
  end;

// le o texto do plano; AWarnings lista o que foi ignorado (com o numero da linha)
function ParsePlan(const AText: string; out AWarnings: TArray<string>): TProjectScan;
function LoadPlanFile(const AFileName: string; out AWarnings: TArray<string>): TProjectScan;
// vista do codigo cruzada com o plano; a analise do codigo nao e alterada (copia as units).
// O resultado e de quem chama.
function MergePlan(ACode, APlan: TProjectScan; out ASummary: TPlanSummary): TProjectScan;

implementation

type
  TPlanFile = class
  public
    Path: string;
    Code: TStringBuilder;
    constructor Create(const APath: string);
    destructor Destroy; override;
  end;

  TDirLevel = record
    Indent: Integer;
    Path: string;
  end;

constructor TPlanFile.Create(const APath: string);
begin
  inherited Create;
  Path := APath;
  Code := TStringBuilder.Create;
end;

destructor TPlanFile.Destroy;
begin
  Code.Free;
  inherited;
end;

const
  SourceExt = '(?:pas|dpr|dpk)';

var
  GReFilePath: TRegEx;
  GReHeading: TRegEx;
  GReBullet: TRegEx;
  GReFenceOpen: TRegEx;
  GReSig: TRegEx;
  GRePascal: TRegEx;
  GReUnit: TRegEx;
  GReComment: TRegEx;

{ TPlanSummary }

function TPlanSummary.FilesCoverage: Double;
begin
  if PlannedFiles > 0 then Result := 100 * ImplementedFiles / PlannedFiles else Result := 0;
end;

function TPlanSummary.MethodsCoverage: Double;
begin
  if PlannedMethods > 0 then Result := 100 * ImplementedMethods / PlannedMethods else Result := 0;
end;

{ ---------------------------------------------------------------- leitura }

function NormalizePath(const APath: string): string;
begin
  Result := APath.Trim.Replace('\', '/');
  while Result.StartsWith('./') do
    Result := Copy(Result, 3, MaxInt);
  while Result.StartsWith('/') do
    Result := Copy(Result, 2, MaxInt);
  while Result.Contains('//') do
    Result := Result.Replace('//', '/');
end;

function JoinPath(const ADir, AName: string): string;
begin
  if ADir = '' then
    Result := NormalizePath(AName)
  else
    Result := NormalizePath(ADir + '/' + AName);
end;

// tira a decoracao Markdown (**, `, _(n metodos)_, [Compila], estrela, nota) e deixa o texto util
function CleanItem(const AText: string): string;
var
  P: Integer;
begin
  Result := AText.Replace('**', '').Replace('`', '');
  P := Result.IndexOf(' — nota:');
  if P >= 0 then
    Result := Copy(Result, 1, P);
  P := Result.IndexOf(' _(');
  if P >= 0 then
    Result := Copy(Result, 1, P);
  Result := Result.Replace(' [Compila]', '').Replace(' [Sonar]', '').Replace('★', '');
  Result := Result.Trim;
  // enfase simples a volta do texto (_x_ / *x*)
  if (Length(Result) > 2) and CharInSet(Result[1], ['_', '*']) and (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

// o texto e so um nome de pasta ('src/Core/', 'Core/')?
function AsDirToken(const AText: string; out ADir: string): Boolean;
var
  S: string;
begin
  S := AText.Trim;
  Result := (Length(S) > 1) and (S.EndsWith('/') or S.EndsWith('\')) and not S.Contains(' ') and
    not S.Contains('.pas');
  if Result then
    ADir := NormalizePath(S).TrimRight(['/']);
end;

function FirstFileToken(const AText: string; out AToken: string): Boolean;
var
  M: TMatch;
begin
  M := GReFilePath.Match(AText);
  Result := M.Success;
  if Result then
    AToken := M.Value;
end;

function IsSignature(const AText: string): Boolean;
begin
  Result := GReSig.IsMatch(AText);
end;

function IndentOf(const ALine: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(ALine) do
    if ALine[I] = ' ' then
      Inc(Result)
    else if ALine[I] = #9 then
      Inc(Result, 4)
    else
      Break;
end;

type
  TPlanParser = class
  private
    FFiles: TObjectList<TPlanFile>;
    FIndex: TDictionary<string, TPlanFile>;
    FWarnings: TList<string>;
    FHeadingDir: string;
    FCurrent: TPlanFile;
    FPending: string;
    FStack: TList<TDirLevel>;
    function GetFile(const APath: string): TPlanFile;
    function StackPath(AIndent: Integer): string;
    procedure PopTo(AIndent: Integer);
    procedure Warn(ALine: Integer; const AMsg: string);
    procedure ProcessHeading(const AText: string);
    procedure ProcessBullet(const ALine: string; ALineNo: Integer);
    procedure ProcessParagraph(const AText: string);
    procedure ProcessFence(const AInfo: string; ALines: TStrings; ALineNo: Integer);
    procedure AddTree(ALines: TStrings);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(const AText: string);
    function BuildScan: TProjectScan;
    property Warnings: TList<string> read FWarnings;
    property Files: TObjectList<TPlanFile> read FFiles;
  end;

constructor TPlanParser.Create;
begin
  inherited;
  FFiles := TObjectList<TPlanFile>.Create(True);
  FIndex := TDictionary<string, TPlanFile>.Create;
  FWarnings := TList<string>.Create;
  FStack := TList<TDirLevel>.Create;
end;

destructor TPlanParser.Destroy;
begin
  FStack.Free;
  FWarnings.Free;
  FIndex.Free;
  FFiles.Free;
  inherited;
end;

procedure TPlanParser.Warn(ALine: Integer; const AMsg: string);
begin
  FWarnings.Add(Format('Linha %d: %s', [ALine, AMsg]));
end;

function TPlanParser.GetFile(const APath: string): TPlanFile;
var
  Key: string;
begin
  Key := LowerCase(APath);
  if not FIndex.TryGetValue(Key, Result) then
  begin
    Result := TPlanFile.Create(APath);
    FFiles.Add(Result);
    FIndex.Add(Key, Result);
  end;
end;

procedure TPlanParser.PopTo(AIndent: Integer);
begin
  while (FStack.Count > 0) and (FStack[FStack.Count - 1].Indent >= AIndent) do
    FStack.Delete(FStack.Count - 1);
end;

// pasta completa de um item com a indentacao dada: pasta do ultimo titulo + pastas da lista
function TPlanParser.StackPath(AIndent: Integer): string;
begin
  PopTo(AIndent);
  if FStack.Count > 0 then
    Result := FStack[FStack.Count - 1].Path
  else
    Result := FHeadingDir;
end;

procedure TPlanParser.ProcessHeading(const AText: string);
var
  Txt, Tok, Dir: string;
begin
  Txt := CleanItem(AText);
  FStack.Clear;
  if FirstFileToken(Txt, Tok) then
  begin
    if NormalizePath(Tok).Contains('/') then
      Tok := NormalizePath(Tok)
    else
      Tok := JoinPath(FHeadingDir, Tok);
    FCurrent := GetFile(Tok);
    FPending := Tok;
  end
  else
  begin
    FCurrent := nil;
    FPending := '';
    if AsDirToken(Txt, Dir) then
      FHeadingDir := Dir;
  end;
end;

procedure TPlanParser.ProcessBullet(const ALine: string; ALineNo: Integer);
var
  M: TMatch;
  Indent: Integer;
  Txt, Tok, Dir, Base: string;
  L: TDirLevel;
begin
  M := GReBullet.Match(ALine);
  Indent := IndentOf(ALine);
  Txt := CleanItem(M.Groups[2].Value);
  if IsSignature(Txt) then
  begin
    if FCurrent = nil then
      Warn(ALineNo, 'assinatura de método sem ficheiro associado — ignorada: ' + Txt)
    else
    begin
      if not Txt.EndsWith(';') then
        Txt := Txt + ';';
      FCurrent.Code.AppendLine(Txt);
    end;
    Exit;
  end;
  if FirstFileToken(Txt, Tok) and (Txt.StartsWith(Tok)) then
  begin
    Base := StackPath(Indent);
    if NormalizePath(Tok).Contains('/') then
      Tok := NormalizePath(Tok)
    else
      Tok := JoinPath(Base, Tok);
    FCurrent := GetFile(Tok);
    FPending := Tok;
    Exit;
  end;
  if AsDirToken(Txt, Dir) then
  begin
    Base := StackPath(Indent);
    L.Indent := Indent;
    L.Path := JoinPath(Base, Dir);
    FStack.Add(L);
    FCurrent := nil;
    FPending := '';
    Exit;
  end;
  FPending := '';
end;

procedure TPlanParser.ProcessParagraph(const AText: string);
var
  Tok: string;
begin
  if FirstFileToken(CleanItem(AText), Tok) then
  begin
    if not NormalizePath(Tok).Contains('/') then
      Tok := JoinPath(FHeadingDir, Tok)
    else
      Tok := NormalizePath(Tok);
    FPending := Tok;
  end
  else
    FPending := '';
end;

procedure TPlanParser.AddTree(ALines: TStrings);
type
  TEntry = record
    Col: Integer;
    Path: string;
    IsDir: Boolean;
  end;
var
  Entries: TList<TEntry>;
  Levels: TList<TDirLevel>;
  I, Col: Integer;
  Line, Name, Dir: string;
  E: TEntry;
  L: TDirLevel;
  P: Integer;

  function NameStart(const S: string): Integer;
  var
    J: Integer;
  begin
    Result := 0;
    for J := 1 to Length(S) do
      if S[J].IsLetterOrDigit or CharInSet(S[J], ['_', '.']) then
        Exit(J);
  end;

begin
  Entries := TList<TEntry>.Create;
  Levels := TList<TDirLevel>.Create;
  try
    for I := 0 to ALines.Count - 1 do
    begin
      Line := ALines[I];
      // comentarios no fim da linha
      P := Line.IndexOf(' #');
      if P >= 0 then Line := Copy(Line, 1, P);
      P := Line.IndexOf(' //');
      if P >= 0 then Line := Copy(Line, 1, P);
      Col := NameStart(Line);
      if Col = 0 then
        Continue;
      Name := Copy(Line, Col, MaxInt).Trim.Replace('`', '').Replace('**', '');
      if Name = '' then
        Continue;
      E.Col := Col;
      E.IsDir := Name.EndsWith('/') or Name.EndsWith('\');
      Name := Name.TrimRight(['/', '\']);
      if not E.IsDir then
      begin
        // sem extensao = pasta; com extensao so interessam as units
        if TPath.GetExtension(Name) = '' then
          E.IsDir := True
        else if not GReFilePath.IsMatch(Name) then
          Continue;
      end;
      while (Levels.Count > 0) and (Levels[Levels.Count - 1].Indent >= Col) do
        Levels.Delete(Levels.Count - 1);
      if Levels.Count > 0 then
        Dir := Levels[Levels.Count - 1].Path
      else
        Dir := FHeadingDir;
      E.Path := JoinPath(Dir, Name);
      if E.IsDir then
      begin
        L.Indent := Col;
        L.Path := E.Path;
        Levels.Add(L);
      end;
      Entries.Add(E);
    end;
    for E in Entries do
      if not E.IsDir then
        GetFile(E.Path);
  finally
    Levels.Free;
    Entries.Free;
  end;
end;

procedure TPlanParser.ProcessFence(const AInfo: string; ALines: TStrings; ALineNo: Integer);
var
  Lang, Content, Tok, Path, First: string;
  M: TMatch;
  IsCode, HasGlyphs: Boolean;
  FileHits, I: Integer;
  F: TPlanFile;
begin
  Content := ALines.Text;
  Lang := LowerCase(AInfo.Trim);
  if Lang.Contains(' ') then
    Lang := Copy(Lang, 1, Lang.IndexOf(' '));
  IsCode := (Lang = 'pascal') or (Lang = 'delphi') or (Lang = 'pas') or (Lang = 'objectpascal') or
    (Lang = 'dpr') or GRePascal.IsMatch(Content);
  HasGlyphs := Content.Contains('├') or Content.Contains('└') or Content.Contains('│');
  FileHits := 0;
  for I := 0 to ALines.Count - 1 do
    if GReFilePath.IsMatch(ALines[I]) then
      Inc(FileHits);

  if IsCode and not HasGlyphs then
  begin
    Path := '';
    if FirstFileToken(AInfo, Tok) then
      Path := NormalizePath(Tok)
    else if FPending <> '' then
      Path := FPending
    else
    begin
      if ALines.Count > 0 then
      begin
        First := ALines[0];
        M := GReComment.Match(First);
        if M.Success and FirstFileToken(M.Groups[1].Value, Tok) then
          Path := NormalizePath(Tok);
      end;
      if Path = '' then
      begin
        M := GReUnit.Match(Content);
        if M.Success then
          Path := JoinPath(FHeadingDir, M.Groups[1].Value + '.pas')
        else if FCurrent <> nil then
          Path := FCurrent.Path;
      end;
    end;
    if Path = '' then
    begin
      Warn(ALineNo, 'bloco de código sem caminho de ficheiro — ignorado');
      Exit;
    end;
    if not Path.Contains('/') and (FHeadingDir <> '') then
      Path := JoinPath(FHeadingDir, Path);
    F := GetFile(Path);
    FCurrent := F;
    F.Code.AppendLine(Content);
  end
  else if HasGlyphs or (FileHits >= 2) then
    AddTree(ALines);
  FPending := '';
end;

procedure TPlanParser.Run(const AText: string);
var
  Lines: TStringList;
  I, FenceStart: Integer;
  Line, FenceMark, FenceInfo: string;
  M: TMatch;
  InFence: Boolean;
  Block: TStringList;
begin
  Lines := TStringList.Create;
  Block := TStringList.Create;
  try
    Lines.Text := AText.Replace(#13#10, #10).Replace(#13, #10).Replace(#10, sLineBreak);
    InFence := False;
    FenceMark := '';
    FenceStart := 0;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if InFence then
      begin
        if Line.TrimLeft.StartsWith(FenceMark) then
        begin
          ProcessFence(FenceInfo, Block, FenceStart);
          InFence := False;
        end
        else
          Block.Add(Line);
        Continue;
      end;
      M := GReFenceOpen.Match(Line);
      if M.Success then
      begin
        InFence := True;
        FenceMark := Copy(M.Groups[1].Value, 1, 3);
        FenceInfo := M.Groups[2].Value;
        FenceStart := I + 1;
        Block.Clear;
        Continue;
      end;
      if Line.Trim = '' then
        Continue;
      M := GReHeading.Match(Line);
      if M.Success then
      begin
        ProcessHeading(M.Groups[1].Value);
        Continue;
      end;
      if GReBullet.IsMatch(Line) then
      begin
        ProcessBullet(Line, I + 1);
        Continue;
      end;
      ProcessParagraph(Line);
    end;
    if InFence then
      ProcessFence(FenceInfo, Block, FenceStart);   // bloco nao fechado: usa o que ha
  finally
    Block.Free;
    Lines.Free;
  end;
end;

function TPlanParser.BuildScan: TProjectScan;
var
  F: TPlanFile;
  U: TUnitInfo;
begin
  Result := TProjectScan.Create;
  try
    for F in FFiles do
    begin
      U := TUnitInfo.Create;
      Result.Units.Add(U);
      SetUnitPath(U, F.Path);
      if F.Code.Length > 0 then
        try
          U.Methods := ExtractMethodsFromText(F.Code.ToString);
        except
          on E: Exception do
          begin
            U.Methods := nil;
            FWarnings.Add(Format('%s: não foi possível ler o código (%s)', [F.Path, E.Message]));
          end;
        end;
    end;
    Result.Units.Sort(TComparer<TUnitInfo>.Construct(
      function(const A, B: TUnitInfo): Integer
      begin
        Result := CompareText(A.Path, B.Path);
      end));
    RecountScan(Result);
  except
    Result.Free;
    raise;
  end;
end;

function ParsePlan(const AText: string; out AWarnings: TArray<string>): TProjectScan;
var
  Parser: TPlanParser;
begin
  Parser := TPlanParser.Create;
  try
    Parser.Run(AText);
    Result := Parser.BuildScan;
    if Result.Units.Count = 0 then
      Parser.Warnings.Add('O documento não contém nenhum ficheiro (.pas, .dpr ou .dpk).');
    AWarnings := Parser.Warnings.ToArray;
  finally
    Parser.Free;
  end;
end;

function LoadPlanFile(const AFileName: string; out AWarnings: TArray<string>): TProjectScan;
begin
  if not TFile.Exists(AFileName) then
    raise Exception.CreateFmt('O documento do plano não existe: %s', [AFileName]);
  Result := ParsePlan(TFile.ReadAllText(AFileName, TEncoding.UTF8), AWarnings);
end;

{ ---------------------------------------------------------------- cruzamento }

function CloneUnit(U: TUnitInfo): TUnitInfo;
begin
  Result := TUnitInfo.Create;
  Result.Path := U.Path;
  Result.Dir := U.Dir;
  Result.FileName := U.FileName;
  Result.Layer := U.Layer;
  Result.Methods := Copy(U.Methods);
end;

procedure FillStatus(U: TUnitInfo; AStatus: TPlanStatus);
var
  I: Integer;
begin
  SetLength(U.MethodPlan, Length(U.Methods));
  for I := 0 to High(U.MethodPlan) do
    U.MethodPlan[I] := AStatus;
end;

// junta uma unit do codigo com a do plano: metodos do codigo (implementados ou extra) seguidos dos
// que so existem no plano
function MergeUnit(ACode, APlan: TUnitInfo; var ASummary: TPlanSummary): TUnitInfo;
var
  CodeUsed, PlanUsed: TArray<Boolean>;
  I, J, CodeCnt, PlanCnt, Match: Integer;
  Methods: TList<TMethodInfo>;
  Status: TList<TPlanStatus>;
begin
  Result := CloneUnit(ACode);
  Result.PlanStatus := psImplemented;
  // o plano nao detalha os metodos deste ficheiro (ex.: so aparece numa arvore): nada a julgar
  if Length(APlan.Methods) = 0 then
    Exit;
  SetLength(CodeUsed, Length(ACode.Methods));
  SetLength(PlanUsed, Length(APlan.Methods));
  // 1) mesmo nome (TFoo.Bar / TFoo.Bar(Integer))
  for I := 0 to High(ACode.Methods) do
    for J := 0 to High(APlan.Methods) do
      if not PlanUsed[J] and SameText(ACode.Methods[I].Name, APlan.Methods[J].Name) then
      begin
        CodeUsed[I] := True;
        PlanUsed[J] := True;
        Break;
      end;
  // 2) so o nome simples, desde que seja unico dos dois lados (assinatura ligeiramente diferente)
  for I := 0 to High(ACode.Methods) do
    if not CodeUsed[I] then
    begin
      CodeCnt := 0;
      for J := 0 to High(ACode.Methods) do
        if not CodeUsed[J] and SameText(ACode.Methods[J].Simple, ACode.Methods[I].Simple) then
          Inc(CodeCnt);
      PlanCnt := 0;
      Match := -1;
      for J := 0 to High(APlan.Methods) do
        if not PlanUsed[J] and SameText(APlan.Methods[J].Simple, ACode.Methods[I].Simple) then
        begin
          Inc(PlanCnt);
          Match := J;
        end;
      if (CodeCnt = 1) and (PlanCnt = 1) then
      begin
        CodeUsed[I] := True;
        PlanUsed[Match] := True;
      end;
    end;

  Methods := TList<TMethodInfo>.Create;
  Status := TList<TPlanStatus>.Create;
  try
    for I := 0 to High(ACode.Methods) do
    begin
      Methods.Add(ACode.Methods[I]);
      if CodeUsed[I] then
      begin
        Status.Add(psImplemented);
        Inc(ASummary.ImplementedMethods);
      end
      else
      begin
        Status.Add(psExtra);
        Inc(ASummary.ExtraMethods);
      end;
    end;
    for J := 0 to High(APlan.Methods) do
      if not PlanUsed[J] then
      begin
        Methods.Add(APlan.Methods[J]);
        Status.Add(psPlanned);
        Inc(ASummary.MissingMethods);
      end;
    Result.Methods := Methods.ToArray;
    Result.MethodPlan := Status.ToArray;
  finally
    Status.Free;
    Methods.Free;
  end;
  Inc(ASummary.PlannedMethods, Length(APlan.Methods));
end;

// primeira pasta comum a todas as units do plano, quando o codigo nao a usa e retira-la faz
// coincidir pelo menos um caminho (ex.: o plano comeca em "MeuProjeto/src/...", o codigo em "src/...")
function PlanRootPrefix(ACode, APlan: TProjectScan): string;
var
  U, C: TUnitInfo;
  Seg, Rest: string;
  P: Integer;
  Hit: Boolean;
begin
  Result := '';
  if APlan.Units.Count = 0 then
    Exit;
  Seg := APlan.Units[0].Path;
  P := Seg.IndexOf('/');
  if P < 0 then
    Exit;
  Seg := Copy(Seg, 1, P);
  for U in APlan.Units do
    if not U.Path.StartsWith(Seg + '/', True) then
      Exit;
  for C in ACode.Units do
    if C.Path.StartsWith(Seg + '/', True) then
      Exit;
  Hit := False;
  for U in APlan.Units do
  begin
    Rest := Copy(U.Path, Length(Seg) + 2, MaxInt);
    for C in ACode.Units do
      if SameText(C.Path, Rest) then
      begin
        Hit := True;
        Break;
      end;
    if Hit then
      Break;
  end;
  if Hit then
    Result := Seg + '/';
end;

function WithoutPrefix(APlan: TProjectScan; const APrefix: string): TProjectScan;
var
  U, N: TUnitInfo;
begin
  Result := TProjectScan.Create;
  for U in APlan.Units do
  begin
    N := TUnitInfo.Create;
    SetUnitPath(N, Copy(U.Path, Length(APrefix) + 1, MaxInt));
    N.Methods := Copy(U.Methods);
    Result.Units.Add(N);
  end;
  RecountScan(Result);
end;

function MergePlan(ACode, APlan: TProjectScan; out ASummary: TPlanSummary): TProjectScan;
var
  Plan: TProjectScan;
  Prefix: string;
  CodeBy: TDictionary<string, TUnitInfo>;
  Pair: TDictionary<TUnitInfo, TUnitInfo>;      // unit do plano -> unit do codigo
  CodeTaken: THashSet<TUnitInfo>;
  PlanNames, CodeNames: TDictionary<string, Integer>;
  P, C: TUnitInfo;
  Key: string;
  N: Integer;
  R: TUnitInfo;
begin
  ASummary := Default(TPlanSummary);
  Result := TProjectScan.Create;
  Plan := APlan;
  Prefix := PlanRootPrefix(ACode, APlan);
  if Prefix <> '' then
    Plan := WithoutPrefix(APlan, Prefix);
  CodeBy := TDictionary<string, TUnitInfo>.Create;
  Pair := TDictionary<TUnitInfo, TUnitInfo>.Create;
  CodeTaken := THashSet<TUnitInfo>.Create;
  PlanNames := TDictionary<string, Integer>.Create;
  CodeNames := TDictionary<string, Integer>.Create;
  try
   try
    Result.Root := ACode.Root;
    Result.ExcludeDirs := ACode.ExcludeDirs;
    for C in ACode.Units do
      CodeBy.AddOrSetValue(LowerCase(C.Path), C);
    // 1) mesmo caminho
    for P in Plan.Units do
      if CodeBy.TryGetValue(LowerCase(P.Path), C) and not CodeTaken.Contains(C) then
      begin
        Pair.Add(P, C);
        CodeTaken.Add(C);
      end;
    // 2) mesmo nome de ficheiro noutra pasta, desde que seja unico entre os que sobram
    for P in Plan.Units do
      if not Pair.ContainsKey(P) then
      begin
        Key := LowerCase(P.FileName);
        PlanNames.TryGetValue(Key, N);
        PlanNames.AddOrSetValue(Key, N + 1);
      end;
    for C in ACode.Units do
      if not CodeTaken.Contains(C) then
      begin
        Key := LowerCase(C.FileName);
        CodeNames.TryGetValue(Key, N);
        CodeNames.AddOrSetValue(Key, N + 1);
      end;
    for P in Plan.Units do
      if not Pair.ContainsKey(P) then
      begin
        Key := LowerCase(P.FileName);
        if (PlanNames[Key] = 1) and CodeNames.TryGetValue(Key, N) and (N = 1) then
          for C in ACode.Units do
            if not CodeTaken.Contains(C) and SameText(C.FileName, P.FileName) then
            begin
              Pair.Add(P, C);
              CodeTaken.Add(C);
              Break;
            end;
      end;

    ASummary.PlannedFiles := Plan.Units.Count;
    for P in Plan.Units do
    begin
      if Pair.TryGetValue(P, C) then
      begin
        R := MergeUnit(C, P, ASummary);
        if not SameText(C.Path, P.Path) then
          R.PlannedPath := P.Path;
        Inc(ASummary.ImplementedFiles);
      end
      else
      begin
        R := CloneUnit(P);
        R.PlanStatus := psPlanned;
        FillStatus(R, psPlanned);
        Inc(ASummary.MissingFiles);
        Inc(ASummary.PlannedMethods, Length(P.Methods));
        Inc(ASummary.MissingMethods, Length(P.Methods));
      end;
      Result.Units.Add(R);
    end;
    for C in ACode.Units do
      if not CodeTaken.Contains(C) then
      begin
        R := CloneUnit(C);
        R.PlanStatus := psExtra;
        FillStatus(R, psExtra);
        Inc(ASummary.ExtraFiles);
        Result.Units.Add(R);
      end;
    Result.Units.Sort(TComparer<TUnitInfo>.Construct(
      function(const A, B: TUnitInfo): Integer
      begin
        Result := CompareText(A.Path, B.Path);
      end));
    RecountScan(Result);
   except
    Result.Free;
    raise;
   end;
  finally
    if Plan <> APlan then
      Plan.Free;
    CodeNames.Free;
    PlanNames.Free;
    CodeTaken.Free;
    Pair.Free;
    CodeBy.Free;
  end;
end;

initialization
  GReFilePath := TRegEx.Create('[\w.\-/\\]+\.' + SourceExt + '\b', [roIgnoreCase]);
  GReHeading := TRegEx.Create('^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$');
  GReBullet := TRegEx.Create('^(\s*)[-*+]\s+(?:\[[ xX]\]\s+)?(.+?)\s*$');
  GReFenceOpen := TRegEx.Create('^\s*(`{3,}|~{3,})\s*(.*)$');
  GReSig := TRegEx.Create('^(?:class\s+)?(?:function|procedure|constructor|destructor|operator)\s+\S',
    [roIgnoreCase]);
  GRePascal := TRegEx.Create('^\s*(?:unit|program|library|package|interface|implementation)\b|' +
    '^\s*(?:class\s+)?(?:function|procedure|constructor|destructor)\s+\S', [roIgnoreCase, roMultiLine]);
  GReUnit := TRegEx.Create('^\s*unit\s+([\w.]+)\s*;', [roIgnoreCase, roMultiLine]);
  GReComment := TRegEx.Create('^\s*(?://|\{|\(\*)\s*(.+?)\s*(?:\}|\*\))?\s*$');

end.
