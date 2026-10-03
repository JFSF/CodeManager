unit CM.Svn;

{ Acesso minimo ao Subversion: corre o "svn" da linha de comandos (sem janela) e le o resultado. So le:
  nunca altera a copia de trabalho nem o repositorio. Sem o svn instalado (e no PATH), ou fora de uma copia de
  trabalho, as funcoes devolvem vazio / False.

  As revisoes do Subversion sao numeros ('1234'); "o commit actual" e a revisao da copia de trabalho. Os
  caminhos devolvidos sao relativos a pasta ARoot (que pode ser uma subpasta da copia), com '/'.

  Os analisadores (SvnParseXxx) sao puros e testam-se sem o svn: o svn escreve XML em UTF-8 com --xml. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, CM.Stats, CM.Proc;

type
  TSvnEntry = record
    Revision: Integer;
    Author: string;
    Date: string;                 // como o svn a escreve: 2026-10-03T12:00:00.000000Z
    Msg: string;
    Paths: TArray<string>;        // caminhos alterados (com -v), a partir da raiz do repositorio
  end;

function SvnAvailable: Boolean;
// corre "svn --non-interactive AArgs" em ARoot; True se terminou com codigo 0
function RunSvn(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer = 30000): Boolean;
// a revisao da copia de trabalho de ARoot ('' se nao for uma copia de trabalho)
function SvnHead(const ARoot: string): string;
// as revisoes ate a actual com a sua hora, da mais recente para a mais antiga
function SvnTimeline(const ARoot: string): TArray<TCommitTime>;
// junta a AChanged os ficheiros diferentes da revisao ARev (as revisoes seguintes e o que ainda nao foi enviado).
// False se ARev nao e uma revisao conhecida
function SvnChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
// as (no maximo AMax) revisoes feitas depois de ARev que tocaram em ARelPath, da mais recente para a mais antiga
function SvnCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;

// analisadores do XML do svn (puros)
function SvnParseLog(const AXml: string): TArray<TSvnEntry>;
// os caminhos de "svn status --xml" que contam como alterados (modificado, adicionado, apagado, substituido, em conflito, em falta)
function SvnParseStatus(const AXml: string): TArray<string>;
// 2026-10-03T12:00:00.000000Z -> segundos Unix; False se nao se entende
function SvnIsoToUnix(const AIso: string; out ATime: Int64): Boolean;
// '^/trunk/Meu%20Projeto' -> '/trunk/Meu Projeto' (o caminho do projecto dentro do repositorio)
function SvnRepoPathOf(const ARelativeUrl: string): string;
// o caminho de um ficheiro alterado (a partir da raiz do repositorio) relativo ao projecto; '' se esta fora dele
function SvnRelativeToProject(const ARepoPath, AProjectRepoPath: string): string;

implementation

uses
  System.RegularExpressions, System.NetEncoding, System.DateUtils;

var
  GAvailable: Integer = -1;       // -1 = ainda nao se sabe

function RunSvn(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer): Boolean;
begin
  Result := RunProcess('svn --non-interactive ' + AArgs, ARoot, AOutput, ATimeoutMs);
end;

function SvnAvailable: Boolean;
var
  Output: string;
begin
  if GAvailable < 0 then
  begin
    if RunSvn(GetCurrentDir, '--version --quiet', Output, 5000) and (Trim(Output) <> '') then
      GAvailable := 1
    else
      GAvailable := 0;
  end;
  Result := GAvailable = 1;
end;

function XmlDecode(const AText: string): string;
begin
  Result := AText.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"').Replace('&apos;', '''')
    .Replace('&amp;', '&');
end;

function SvnIsoToUnix(const AIso: string; out ATime: Int64): Boolean;
var
  M: TMatch;
  D: TDateTime;
begin
  Result := False;
  ATime := 0;
  M := TRegEx.Match(AIso, '^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})');
  if not M.Success then
    Exit;
  if not TryEncodeDateTime(StrToInt(M.Groups[1].Value), StrToInt(M.Groups[2].Value), StrToInt(M.Groups[3].Value),
       StrToInt(M.Groups[4].Value), StrToInt(M.Groups[5].Value), StrToInt(M.Groups[6].Value), 0, D) then
    Exit;
  ATime := DateTimeToUnix(D, True);         // o svn escreve a hora em UTC
  Result := True;
end;

function SvnParseLog(const AXml: string): TArray<TSvnEntry>;
var
  List: TList<TSvnEntry>;
  Entry: TMatch;
  Body, PathText: string;
  E: TSvnEntry;
  M: TMatch;
  P: TMatch;
  Paths: TList<string>;
begin
  List := TList<TSvnEntry>.Create;
  Paths := TList<string>.Create;
  try
    for Entry in TRegEx.Matches(AXml, '<logentry\s+revision="(\d+)"\s*>(.*?)</logentry>', [roSingleLine]) do
    begin
      E := Default(TSvnEntry);
      E.Revision := StrToIntDef(Entry.Groups[1].Value, 0);
      Body := Entry.Groups[2].Value;
      M := TRegEx.Match(Body, '<author>(.*?)</author>', [roSingleLine]);
      if M.Success then
        E.Author := XmlDecode(M.Groups[1].Value);
      M := TRegEx.Match(Body, '<date>(.*?)</date>', [roSingleLine]);
      if M.Success then
        E.Date := M.Groups[1].Value;
      M := TRegEx.Match(Body, '<msg>(.*?)</msg>', [roSingleLine]);
      if M.Success then
        E.Msg := XmlDecode(M.Groups[1].Value);
      Paths.Clear;
      for P in TRegEx.Matches(Body, '<path\b[^>]*>(.*?)</path>', [roSingleLine]) do
      begin
        PathText := XmlDecode(P.Groups[1].Value);
        Paths.Add(PathText);
      end;
      E.Paths := Paths.ToArray;
      List.Add(E);
    end;
    Result := List.ToArray;
  finally
    Paths.Free;
    List.Free;
  end;
end;

function SvnParseStatus(const AXml: string): TArray<string>;
var
  List: TList<string>;
  M: TMatch;
  Item, Path: string;
begin
  List := TList<string>.Create;
  try
    for M in TRegEx.Matches(AXml, '<entry\s+path="([^"]*)"\s*>\s*<wc-status\b[^>]*?\bitem="([a-z]+)"', [roSingleLine]) do
    begin
      Item := M.Groups[2].Value;
      if (Item = 'modified') or (Item = 'added') or (Item = 'deleted') or (Item = 'replaced') or
         (Item = 'conflicted') or (Item = 'missing') then
      begin
        Path := XmlDecode(M.Groups[1].Value).Replace('\', '/');
        List.Add(Path);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SvnRepoPathOf(const ARelativeUrl: string): string;
begin
  Result := Trim(ARelativeUrl);
  if Result.StartsWith('^') then
    Result := Copy(Result, 2, MaxInt);
  Result := TNetEncoding.URL.Decode(Result.Replace('+', '%2B'));
  while (Length(Result) > 1) and Result.EndsWith('/') do
    Result := Copy(Result, 1, Length(Result) - 1);
end;

function SvnRelativeToProject(const ARepoPath, AProjectRepoPath: string): string;
var
  Prefix: string;
begin
  Result := '';
  Prefix := AProjectRepoPath;
  if (Prefix = '') or (Prefix = '/') then
    Exit(Copy(ARepoPath, 2, MaxInt));          // o projecto e a raiz do repositorio
  if ARepoPath.StartsWith(Prefix + '/') then
    Result := Copy(ARepoPath, Length(Prefix) + 2, MaxInt);
end;

function SvnHead(const ARoot: string): string;
var
  Output: string;
begin
  Result := '';
  if not SvnAvailable then
    Exit;
  if RunSvn(ARoot, 'info --show-item revision', Output) then
    Result := Trim(Output);
  if (Result = '') or (StrToIntDef(Result, -1) < 0) then
    Result := '';
end;

function SvnTimeline(const ARoot: string): TArray<TCommitTime>;
var
  Head, Output: string;
  Entry: TSvnEntry;
  List: TList<TCommitTime>;
  C: TCommitTime;
begin
  Result := nil;
  Head := SvnHead(ARoot);
  if Head = '' then
    Exit;
  if not RunSvn(ARoot, Format('log --xml -q -r %s:1', [Head]), Output, 120000) then
    Exit;
  List := TList<TCommitTime>.Create;
  try
    for Entry in SvnParseLog(Output) do
      if SvnIsoToUnix(Entry.Date, C.Time) then
      begin
        C.Hash := IntToStr(Entry.Revision);
        List.Add(C);
      end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SvnChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
var
  Head, Output, Rel, P: string;
  RevNo, HeadNo: Integer;
  RepoPath: string;
  Entry: TSvnEntry;
begin
  Result := False;
  if not SvnAvailable then
    Exit;
  if not TryStrToInt(ARev, RevNo) then
    Exit;
  Head := SvnHead(ARoot);
  if not TryStrToInt(Head, HeadNo) then
    Exit;
  if RevNo > HeadNo then
    Exit;                            // uma revisao que a copia ainda nao conhece
  // o que ja foi enviado depois de ARev (so se a copia de trabalho esta mais a frente)
  if RevNo < HeadNo then
  begin
    if not RunSvn(ARoot, 'info --show-item relative-url', Output) then
      Exit;
    RepoPath := SvnRepoPathOf(Output);
    if not RunSvn(ARoot, Format('log --xml -v -r %d:%d', [RevNo + 1, HeadNo]), Output, 120000) then
      Exit;
    for Entry in SvnParseLog(Output) do
      for P in Entry.Paths do
      begin
        Rel := SvnRelativeToProject(P, RepoPath);
        if Rel <> '' then
          AChanged.Add(Rel);
      end;
  end;
  // e o que ainda nao foi enviado
  if RunSvn(ARoot, 'status --xml', Output, 120000) then
    for P in SvnParseStatus(Output) do
      AChanged.Add(P);
  Result := True;
end;

function SvnCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;
var
  Head, Output: string;
  RevNo, HeadNo: Integer;
  List: TList<TVcsCommit>;
  Entry: TSvnEntry;
  C: TVcsCommit;
  Subject: string;
begin
  Result := nil;
  if not SvnAvailable or not TryStrToInt(ARev, RevNo) then
    Exit;
  Head := SvnHead(ARoot);
  if not TryStrToInt(Head, HeadNo) or (RevNo >= HeadNo) then
    Exit;
  if not RunSvn(ARoot, Format('log --xml -l %d -r %d:%d %s', [AMax, HeadNo, RevNo + 1, QuoteArg(ARelPath)]), Output) then
    Exit;
  List := TList<TVcsCommit>.Create;
  try
    for Entry in SvnParseLog(Output) do
    begin
      Subject := Trim(Entry.Msg);
      if Pos(#10, Subject) > 0 then
        Subject := Trim(Copy(Subject, 1, Pos(#10, Subject) - 1));
      C.Hash := 'r' + IntToStr(Entry.Revision);
      C.Author := Entry.Author;
      C.Date := Copy(Entry.Date, 1, 10);
      C.Subject := Subject.Replace(#13, '');
      List.Add(C);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
