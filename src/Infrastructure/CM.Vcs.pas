unit CM.Vcs;

{ O sistema de controlo de versoes de um projecto: descobre se a pasta esta num repositorio Git, numa copia de
  trabalho do Subversion ou num repositorio Mercurial e despacha para o cliente certo (CM.Git, CM.Svn, CM.Hg). Tudo so de leitura. Sem sistema, ou sem o
  programa instalado, as funcoes devolvem vazio / False e quem as usa limita-se a nao mostrar nada.

  Procura-se do directorio do projecto para cima, e ganha o marcador mais proximo: ".git" (pasta ou ficheiro, nos
  worktrees e submodulos), ".svn" ou ".hg". Um projecto Subversion ou Mercurial dentro de um repositorio Git usa o
  Subversion ou o Mercurial. }

interface

uses
  System.SysUtils, System.Generics.Collections, CM.Stats;

type
  TVcsKind = (vkNone, vkGit, vkSvn, vkHg);

// o sistema de ARoot (so olha para as pastas; nao corre nenhum programa)
function DetectVcs(const ARoot: string): TVcsKind;
// 'Git' | 'Subversion' | 'Mercurial' ('' sem sistema)
function VcsName(AKind: TVcsKind): string;
// a revisao actual: o commit (Git, Mercurial) ou o numero da revisao da copia de trabalho (Subversion); '' se nao houver
function VcsHead(const ARoot: string): string;
// o historico com a hora de cada revisao, da mais recente para a mais antiga
function VcsTimeline(const ARoot: string): TArray<TCommitTime>;
// junta a AChanged os ficheiros diferentes de ARev (incluindo o que ainda nao foi gravado); False se ARev nao existe
function VcsChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
// as (no maximo AMax) revisoes depois de ARev que tocaram em ARelPath, da mais recente para a mais antiga
function VcsCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;

implementation

uses
  System.IOUtils, CM.Git, CM.Svn, CM.Hg;

function DetectVcs(const ARoot: string): TVcsKind;
var
  Dir, Parent: string;
begin
  Result := vkNone;
  if Trim(ARoot) = '' then
    Exit;
  Dir := TPath.GetFullPath(ExcludeTrailingPathDelimiter(ARoot));
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.svn')) then
      Exit(vkSvn);
    if TDirectory.Exists(TPath.Combine(Dir, '.hg')) then
      Exit(vkHg);
    if TDirectory.Exists(TPath.Combine(Dir, '.git')) or TFile.Exists(TPath.Combine(Dir, '.git')) then
      Exit(vkGit);
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = '') or SameText(Parent, Dir) then
      Break;
    Dir := Parent;
  end;
end;

function VcsName(AKind: TVcsKind): string;
begin
  case AKind of
    vkGit: Result := 'Git';
    vkSvn: Result := 'Subversion';
    vkHg: Result := 'Mercurial';
  else
    Result := '';
  end;
end;

function VcsHead(const ARoot: string): string;
begin
  case DetectVcs(ARoot) of
    vkGit: Result := GitHead(ARoot);
    vkSvn: Result := SvnHead(ARoot);
    vkHg: Result := HgHead(ARoot);
  else
    Result := '';
  end;
end;

function VcsTimeline(const ARoot: string): TArray<TCommitTime>;
begin
  case DetectVcs(ARoot) of
    vkGit: Result := GitTimeline(ARoot);
    vkSvn: Result := SvnTimeline(ARoot);
    vkHg: Result := HgTimeline(ARoot);
  else
    Result := nil;
  end;
end;

function VcsChangedSince(const ARoot, ARev: string; AChanged: THashSet<string>): Boolean;
begin
  case DetectVcs(ARoot) of
    vkGit: Result := GitChangedSince(ARoot, ARev, AChanged);
    vkSvn: Result := SvnChangedSince(ARoot, ARev, AChanged);
    vkHg: Result := HgChangedSince(ARoot, ARev, AChanged);
  else
    Result := False;
  end;
end;

function VcsCommitsSince(const ARoot, ARev, ARelPath: string; AMax: Integer): TArray<TVcsCommit>;
begin
  case DetectVcs(ARoot) of
    vkGit: Result := GitCommitsSince(ARoot, ARev, ARelPath, AMax);
    vkSvn: Result := SvnCommitsSince(ARoot, ARev, ARelPath, AMax);
    vkHg: Result := HgCommitsSince(ARoot, ARev, ARelPath, AMax);
  else
    Result := nil;
  end;
end;

end.
