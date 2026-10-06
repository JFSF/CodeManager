unit CM.Hg;

{ Acesso minimo ao Mercurial: corre o "hg" da linha de comandos (sem janela) e le o resultado. So le: nunca altera
  o repositorio. Sem o hg instalado (e no PATH), ou fora de um repositorio, as funcoes devolvem vazio / False.

  As revisoes sao os identificadores completos dos conjuntos de alteracoes (40 hexadecimais): os numeros locais do
  Mercurial mudam de um clone para outro e nao servem para guardar. "O commit actual" e o pai da copia de trabalho.
  Os caminhos devolvidos sao relativos a pasta ARoot (que pode ser uma subpasta do repositorio), com '/'.

  Corre-se com HGPLAIN (sem aliases nem opcoes do utilizador a mudar a saida) e com --encoding utf-8.
  Os analisadores (HgParseXxx) sao puros e testam-se sem o hg. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, CM.Stats, CM.Proc;

function HgAvailable: Boolean;
// corre "hg AArgs" em ARoot; True se terminou com codigo 0
function RunHg(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer = 30000): Boolean;
// o conjunto de alteracoes actual da copia de trabalho de ARoot ('' se nao houver repositorio ou ainda nao ha commits)
function HgHead(const ARoot: string): string;
// o historico do ramo actual com a hora de cada revisao, da mais recente para a mais antiga
function HgTimeline(const ARoot: string): TArray<TCommitTime>;
// junta a AChanged os ficheiros diferentes da revisao ARev (as revisoes seguintes e o que ainda nao foi gravado).
// False se ARev nao e uma revisao conhecida
function HgChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
// as (no maximo AMax) revisoes feitas depois de ARev que tocaram em ARelPath, da mais recente para a mais antiga
function HgCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;

// analisadores da saida do hg (puros)
// linhas "<no> <segundos Unix> <desvio horario>" (modelo "{node} {date|hgdate}")
function HgParseTimeline(const AText: string): TArray<TCommitTime>;
// linhas "<M|A|R|!> <caminho>" de "hg status": modificado, adicionado, removido e em falta contam como alterados
function HgParseStatus(const AText: string): TArray<string>;
// linhas "<no curto><TAB><autor><TAB><aaaa-mm-dd><TAB><assunto>"
function HgParseCommits(const AText: string): TArray<TVcsCommit>;
// o no (40 hexadecimais) tal como o hg o escreve; '' se nao e um no valido ou e o no nulo (repositorio sem commits)
function HgNodeOf(const AText: string): string;
// True se AText pode ir na linha de comandos como revisao (so hexadecimais: nao pode passar por uma opcao)
function HgIsRevision(const AText: string): Boolean;

implementation

uses
  System.RegularExpressions, Winapi.Windows;

var
  GAvailable: Integer = -1;       // -1 = ainda nao se sabe
  GPlainSet: Boolean;

function RunHg(const ARoot, AArgs: string; out AOutput: string; ATimeoutMs: Integer): Boolean;
begin
  if not GPlainSet then
  begin
    SetEnvironmentVariable('HGPLAIN', '1');
    GPlainSet := True;
  end;
  Result := RunProcess('hg --noninteractive --encoding utf-8 --pager never --config ui.relative-paths=true ' + AArgs,
    ARoot, AOutput, ATimeoutMs);
end;

function HgAvailable: Boolean;
var
  Output: string;
begin
  if GAvailable < 0 then
  begin
    if RunHg(GetCurrentDir, '--version --quiet', Output, 5000) and (Trim(Output) <> '') then
      GAvailable := 1
    else
      GAvailable := 0;
  end;
  Result := GAvailable = 1;
end;

function SplitLines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13, '').Split([#10], TStringSplitOptions.ExcludeEmpty);
end;

function HgIsRevision(const AText: string): Boolean;
begin
  Result := TRegEx.IsMatch(AText, '^[0-9a-f]{6,40}$');
end;

function HgNodeOf(const AText: string): string;
begin
  Result := Trim(AText);
  if (Length(Result) <> 40) or not HgIsRevision(Result) or (Result = StringOfChar('0', 40)) then
    Result := '';
end;

function HgParseTimeline(const AText: string): TArray<TCommitTime>;
var
  List: TList<TCommitTime>;
  Line: string;
  Parts: TArray<string>;
  C: TCommitTime;
begin
  List := TList<TCommitTime>.Create;
  try
    for Line in SplitLines(AText) do
    begin
      Parts := Line.Trim.Split([' ']);
      if (Length(Parts) >= 2) and HgIsRevision(Parts[0]) and TryStrToInt64(Parts[1], C.Time) then
      begin
        C.Hash := Parts[0];
        List.Add(C);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function HgParseStatus(const AText: string): TArray<string>;
var
  List: TList<string>;
  Line: string;
begin
  List := TList<string>.Create;
  try
    for Line in SplitLines(AText) do
      if (Length(Line) > 2) and CharInSet(Line[1], ['M', 'A', 'R', '!']) and (Line[2] = ' ') then
        List.Add(Copy(Line, 3, MaxInt).Replace('\', '/'));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function HgParseCommits(const AText: string): TArray<TVcsCommit>;
var
  List: TList<TVcsCommit>;
  Line: string;
  Parts: TArray<string>;
  C: TVcsCommit;
begin
  List := TList<TVcsCommit>.Create;
  try
    for Line in SplitLines(AText) do
    begin
      Parts := Line.Split([#9]);
      if Length(Parts) >= 4 then
      begin
        C.Hash := Parts[0];
        C.Author := Parts[1];
        C.Date := Parts[2];
        C.Subject := Parts[3];
        List.Add(C);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function HgHead(const ARoot: string): string;
var
  Output: string;
begin
  Result := '';
  if not HgAvailable then
    Exit;
  if RunHg(ARoot, 'log -r . -T "{node}"', Output) then
    Result := HgNodeOf(Output);
end;

function HgTimeline(const ARoot: string): TArray<TCommitTime>;
var
  Output: string;
begin
  Result := nil;
  if not HgAvailable then
    Exit;
  if RunHg(ARoot, 'log -r "reverse(::.)" -T "{node} {date|hgdate}\n"', Output, 120000) then
    Result := HgParseTimeline(Output);
end;

function HgChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
var
  Output, P: string;
begin
  Result := False;
  if not HgAvailable or not HgIsRevision(ARev) then
    Exit;
  // compara a copia de trabalho com ARev: apanha o que ja foi gravado depois e o que ainda nao foi
  if not RunHg(ARoot, 'status --rev ' + ARev + ' -mard .', Output, 120000) then
    Exit;
  for P in HgParseStatus(Output) do
    AChanged.Add(P);
  Result := True;
end;

function HgCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;
var
  Output: string;
begin
  Result := nil;
  if not HgAvailable or not HgIsRevision(ARev) then
    Exit;
  if RunHg(ARoot, Format('log -l %d -r "reverse(only(.,%s))" -T "{node|short}\t{author|person}\t{date|shortdate}\t{desc|firstline}\n" -- %s',
       [AMax, ARev, QuoteArg('relpath:' + ARelPath)]), Output) then
    Result := HgParseCommits(Output);
end;

end.
