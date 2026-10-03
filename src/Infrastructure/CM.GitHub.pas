unit CM.GitHub;

{ Projecto lido a partir de um repositorio do GitHub: o repositorio e clonado (so a ultima versao,
  "--depth 1") para uma pasta de cache do CodeManager e essa pasta e analisada como qualquer outra.
  Nunca se escreve no repositorio remoto nem nas pastas do utilizador; a cache e do CodeManager e
  e apagada quando o projecto e removido.

  O endereco aceita as formas habituais (https://github.com/dono/repo, ...repo.git, git@github.com:dono/repo,
  github.com/dono/repo, dono/repo, e ...repo/tree/ramo/pasta). So se clona de github.com: o endereco de
  clonagem e sempre montado aqui, a partir do dono, do repositorio e do ramo validados. }

interface

type
  TRepoRef = record
    Owner: string;
    Name: string;
    Branch: string;       // '' = o ramo por omissao do repositorio
    SubPath: string;      // pasta dentro do repositorio ('' = a raiz), com '/'
    function CloneUrl: string;
    function WebUrl: string;
    function Display: string;       // dono/repositorio[@ramo]
  end;

// interpreta o texto escrito pelo utilizador; False (e AError) se nao for um repositorio do GitHub
function ParseRepoUrl(const AText: string; out ARef: TRepoRef; out AError: string): Boolean;

// pasta de cache do projecto: <dados da aplicacao>\repos\<id do projecto>
function RepoCacheDir(const AProjectId: string): string;
// pasta que se analisa: a cache, ou a subpasta pedida no endereco
function RepoWorkDir(const AProjectId: string; const ARef: TRepoRef): string;

// obtem (clona) ou actualiza a cache; devolve True se correu bem, ou AMessage com o motivo.
// Bloqueia ate acabar: chamar fora da thread da interface
function SyncRepo(const AProjectId: string; const ARef: TRepoRef; out AMessage: string): Boolean;
// apaga a cache do projecto (nao toca em mais nada)
procedure DeleteRepoCache(const AProjectId: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions, Winapi.Windows, CM.Lang, CM.Store, CM.Git;

const
  ReposFolder = 'repos';
  CloneTimeoutMs = 10 * 60 * 1000;

function TRepoRef.CloneUrl: string;
begin
  Result := 'https://github.com/' + Owner + '/' + Name + '.git';
end;

function TRepoRef.WebUrl: string;
begin
  Result := 'https://github.com/' + Owner + '/' + Name;
end;

function TRepoRef.Display: string;
begin
  Result := Owner + '/' + Name;
  if Branch <> '' then
    Result := Result + '@' + Branch;
end;

function ValidName(const AText: string): Boolean;
begin
  Result := TRegEx.IsMatch(AText, '^[A-Za-z0-9._-]+$') and (AText <> '.') and (AText <> '..') and
    not AText.StartsWith('-');
end;

function ValidBranch(const AText: string): Boolean;
begin
  Result := TRegEx.IsMatch(AText, '^[A-Za-z0-9._/-]+$') and not AText.StartsWith('-') and
    not AText.StartsWith('/') and not AText.EndsWith('/') and not AText.Contains('..') and
    not AText.Contains('//');
end;

function ParseRepoUrl(const AText: string; out ARef: TRepoRef; out AError: string): Boolean;
var
  S, Path: string;
  Parts: TArray<string>;
  Hash: Integer;
  Branch: string;
begin
  ARef := Default(TRepoRef);
  AError := '';
  Result := False;
  S := Trim(AText);
  Branch := '';
  // "...#ramo" tambem serve para indicar o ramo
  Hash := S.IndexOf('#');
  if Hash >= 0 then
  begin
    Branch := Trim(Copy(S, Hash + 2, MaxInt));
    S := Trim(Copy(S, 1, Hash));
  end;
  if S = '' then
  begin
    AError := Tr('Indique o endereço do repositório no GitHub.');
    Exit;
  end;

  // git@github.com:dono/repo.git
  if S.StartsWith('git@github.com:', True) then
    Path := Copy(S, Length('git@github.com:') + 1, MaxInt)
  else
  begin
    // tira o esquema e o "www."
    if S.StartsWith('https://', True) then
      S := Copy(S, 9, MaxInt)
    else if S.StartsWith('http://', True) then
      S := Copy(S, 8, MaxInt);
    if S.StartsWith('www.', True) then
      S := Copy(S, 5, MaxInt);
    if S.StartsWith('github.com/', True) then
      Path := Copy(S, Length('github.com/') + 1, MaxInt)
    else if S.Contains(':') or (Pos('.', Copy(S, 1, Pos('/', S + '/') - 1)) > 0) then
    begin
      // outro servidor (gitlab.com/..., ssh://...): os donos do GitHub nao tem pontos no nome
      AError := Tr('Só são aceites repositórios do GitHub (github.com).');
      Exit;
    end
    else
      Path := S;                       // "dono/repo"
  end;
  Path := Path.Trim(['/']);
  if Path.Contains('?') then
    Path := Copy(Path, 1, Path.IndexOf('?'));

  Parts := Path.Split(['/']);
  if (Length(Parts) < 2) or (Parts[0] = '') or (Parts[1] = '') then
  begin
    AError := Tr('O endereço deve ser da forma https://github.com/dono/repositorio.');
    Exit;
  end;
  ARef.Owner := Parts[0];
  ARef.Name := Parts[1];
  if ARef.Name.EndsWith('.git', True) then
    ARef.Name := Copy(ARef.Name, 1, Length(ARef.Name) - 4);
  if not ValidName(ARef.Owner) or not ValidName(ARef.Name) then
  begin
    AError := Tr('O nome do dono ou do repositório tem caracteres inválidos.');
    Exit;
  end;

  // .../tree/<ramo>[/<pasta>]: um ramo com "/" nao se distingue da pasta; fica so o primeiro troco
  if (Length(Parts) >= 4) and ((Parts[2] = 'tree') or (Parts[2] = 'blob')) then
  begin
    if Branch = '' then
      Branch := Parts[3];
    if (Parts[2] = 'tree') and (Length(Parts) > 4) then
      ARef.SubPath := string.Join('/', Copy(Parts, 4, Length(Parts)));
  end;
  if (Branch <> '') and not ValidBranch(Branch) then
  begin
    AError := Tr('O nome do ramo tem caracteres inválidos.');
    Exit;
  end;
  if (ARef.SubPath <> '') and (ARef.SubPath.Contains('..') or not TRegEx.IsMatch(ARef.SubPath, '^[^<>:"|?*\\]+$')) then
    ARef.SubPath := '';
  ARef.Branch := Branch;
  Result := True;
end;

function ReposRoot: string;
begin
  Result := TPath.Combine(AppDataDir, ReposFolder);
end;

function RepoCacheDir(const AProjectId: string): string;
begin
  Result := TPath.Combine(ReposRoot, AProjectId);
end;

function RepoWorkDir(const AProjectId: string; const ARef: TRepoRef): string;
begin
  Result := RepoCacheDir(AProjectId);
  if ARef.SubPath <> '' then
    Result := TPath.Combine(Result, ARef.SubPath.Replace('/', PathDelim));
end;

// so se apaga dentro de <dados>\repos\ e com um id que seja um nome simples
function SafeCacheDir(const AProjectId: string): string;
begin
  Result := '';
  if (AProjectId = '') or not TRegEx.IsMatch(AProjectId, '^[A-Za-z0-9_-]+$') then
    Exit;
  Result := RepoCacheDir(AProjectId);
end;

// os ficheiros do .git sao so de leitura no Windows: sem isto a pasta nao se apaga
procedure DeleteTree(const ADir: string);
var
  F: string;
begin
  if not TDirectory.Exists(ADir) then
    Exit;
  for F in TDirectory.GetFiles(ADir, '*', TSearchOption.soAllDirectories) do
    FileSetAttr(F, faNormal);
  TDirectory.Delete(ADir, True);
end;

// uma frase util do que o git escreveu: a ultima linha com "fatal:" / "error:", ou a ultima linha
function GitFailure(const AOutput: string): string;
var
  Lines: TArray<string>;
  I: Integer;
  L: string;
begin
  Result := '';
  Lines := AOutput.Replace(#13, '').Split([#10]);
  for I := High(Lines) downto 0 do
  begin
    L := Trim(Lines[I]);
    if L.StartsWith('fatal:', True) or L.StartsWith('error:', True) then
      Exit(L);
  end;
  for I := High(Lines) downto 0 do
    if Trim(Lines[I]) <> '' then
      Exit(Trim(Lines[I]));
end;

function FriendlyFailure(const AOutput: string): string;
var
  Text: string;
begin
  Text := AOutput.ToLower;
  if Text.Contains('repository not found') or Text.Contains('could not read username') or
     Text.Contains('authentication failed') or Text.Contains('terminal prompts disabled') then
    Result := Tr('Repositório não encontrado, ou é privado e o Git não tem credenciais para o ler.')
  else if Text.Contains('could not resolve host') or Text.Contains('unable to access') or
          Text.Contains('failed to connect') then
    Result := Tr('Não foi possível ligar ao GitHub. Verifique a ligação à Internet.')
  else if Text.Contains('remote branch') and Text.Contains('not found') then
    Result := Tr('O ramo indicado não existe neste repositório.')
  else
    Result := GitFailure(AOutput);
end;

function SyncRepo(const AProjectId: string; const ARef: TRepoRef; out AMessage: string): Boolean;
var
  Dir, Output, BranchArgs, Target: string;
begin
  Result := False;
  AMessage := '';
  Dir := SafeCacheDir(AProjectId);
  if Dir = '' then
  begin
    AMessage := Tr('Projeto sem identificador válido.');
    Exit;
  end;
  if not GitAvailable then
  begin
    AMessage := Tr('O Git não está instalado (ou não está no PATH): é preciso para ler um repositório.');
    Exit;
  end;
  // nunca pedir credenciais na consola escondida: falha em vez de ficar à espera
  SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0');
  ForceDirectories(ReposRoot);

  if TDirectory.Exists(TPath.Combine(Dir, '.git')) then
  begin
    // ja existe: traz so a ultima versao do ramo e poe a cache igual a ela
    if ARef.Branch <> '' then
      Target := GitQuote(ARef.Branch)
    else
      Target := 'HEAD';
    if not RunGit(Dir, 'remote set-url origin ' + GitQuote(ARef.CloneUrl), Output, 20000) then
    begin
      AMessage := FriendlyFailure(Output);
      Exit;
    end;
    if not RunGit(Dir, 'fetch --depth 1 --force origin ' + Target, Output, CloneTimeoutMs) then
    begin
      AMessage := FriendlyFailure(Output);
      Exit;
    end;
    if not (RunGit(Dir, 'reset --hard FETCH_HEAD', Output, 120000) and
            RunGit(Dir, 'clean -fdq', Output, 120000)) then
    begin
      AMessage := FriendlyFailure(Output);
      Exit;
    end;
    Exit(True);
  end;

  // primeira vez (ou uma cache incompleta de uma tentativa que falhou): recomeca do zero
  DeleteTree(Dir);
  if ARef.Branch <> '' then
    BranchArgs := '--branch ' + GitQuote(ARef.Branch) + ' '
  else
    BranchArgs := '';
  if not RunGit(ReposRoot, '-c core.longpaths=true clone --depth 1 --single-branch ' + BranchArgs + '-- ' +
       GitQuote(ARef.CloneUrl) + ' ' + GitQuote(Dir), Output, CloneTimeoutMs) then
  begin
    AMessage := FriendlyFailure(Output);
    try
      DeleteTree(Dir);
    except
      on Exception do ;
    end;
    Exit;
  end;
  Result := True;
end;

procedure DeleteRepoCache(const AProjectId: string);
var
  Dir: string;
begin
  Dir := SafeCacheDir(AProjectId);
  if (Dir <> '') and TDirectory.Exists(Dir) then
    try
      DeleteTree(Dir);
    except
      on Exception do ;
    end;
end;

end.
