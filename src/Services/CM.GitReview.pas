unit CM.GitReview;

{ Cruza as revisoes guardadas com o Git: que ficheiros revistos mudaram desde a revisao.

  Cada ficheiro guarda o commit em que foi revisto (TUnitState.Rev). Aqui comparam-se esses
  commits com o estado actual do repositorio (incluindo o que ainda nao foi gravado no Git). As
  revisoes antigas, feitas antes de existir este registo, ganham o commit que era o actual na hora em
  que foram concluidas. Sem Git, ou fora de um repositorio, nao ha nada para mostrar. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections, CM.Analyzer, CM.Store, CM.Stats, CM.Vcs;

type
  TGitReviewResult = record
    Head: string;                   // commit actual ('' = sem Git / sem repositorio)
    Stale: THashSet<string>;        // caminhos dos ficheiros revistos que mudaram desde a revisao
    Backfilled: Integer;            // revisoes antigas a que se deduziu o commit (o progresso mudou)
  end;

// o resultado e de quem chama (liberta Stale)
function FindStaleReviews(const ARoot: string; AScan: TProjectScan; AState: TProgressState): TGitReviewResult;
// texto para a dica de um ficheiro alterado: quantos commits desde a revisao e o ultimo
function StaleHint(const ARoot, ARev, ARelPath: string): string;

implementation


uses
  CM.Lang;
function FindStaleReviews(const ARoot: string; AScan: TProjectScan; AState: TProgressState): TGitReviewResult;
var
  Groups: TObjectDictionary<string, TList<TUnitInfo>>;
  Pair: TPair<string, TList<TUnitInfo>>;
  U: TUnitInfo;
  S: TUnitState;
  Changed: THashSet<string>;
  Timeline: TArray<TCommitTime>;
  List: TList<TUnitInfo>;
begin
  Result := Default(TGitReviewResult);
  Result.Stale := THashSet<string>.Create;
  if (AScan = nil) or (AState = nil) or (ARoot = '') then
    Exit;
  Result.Head := VcsHead(ARoot);
  if Result.Head = '' then
    Exit;

  Timeline := VcsTimeline(ARoot);
  Result.Backfilled := BackfillRevisions(AScan, AState, Timeline);

  // agrupa por commit de revisao: uma consulta ao Git por commit, nao por ficheiro
  Groups := TObjectDictionary<string, TList<TUnitInfo>>.Create([doOwnsValues]);
  try
    for U in AScan.Units do
    begin
      S := AState.Find(U.Path);
      if (S = nil) or (S.Rev = '') or (ReviewOfUnit(U, AState) = rsPending) then
        Continue;
      if not Groups.TryGetValue(S.Rev, List) then
      begin
        List := TList<TUnitInfo>.Create;
        Groups.Add(S.Rev, List);
      end;
      List.Add(U);
    end;
    for Pair in Groups do
    begin
      Changed := THashSet<string>.Create;
      try
        if VcsChangedSince(ARoot, Pair.Key, Changed) then
          for U in Pair.Value do
            if Changed.Contains(U.Path) then
              Result.Stale.Add(U.Path);
      finally
        Changed.Free;
      end;
    end;
  finally
    Groups.Free;
  end;
end;

function StaleHint(const ARoot, ARev, ARelPath: string): string;
const
  Shown = 3;
var
  Commits: TArray<TVcsCommit>;
  I: Integer;
begin
  Commits := VcsCommitsSince(ARoot, ARev, ARelPath, Shown + 1);
  if Length(Commits) = 0 then
    Exit(TrF('Mudou desde a revisão (alterações ainda por gravar no %s)', [VcsName(DetectVcs(ARoot))]));
  Result := Tr('Mudou desde a revisão:');
  for I := 0 to Min(Shown, Length(Commits)) - 1 do
    Result := Result + sLineBreak + Commits[I].Date + ' · ' + Commits[I].Author + ' · ' + Commits[I].Subject;
  if Length(Commits) > Shown then
    Result := Result + sLineBreak + '…';
end;

end.
