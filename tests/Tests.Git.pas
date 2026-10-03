unit Tests.Git;

// Testes da integracao com o Git (CM.Git, CM.GitReview). Usam um repositorio temporario criado com o
// proprio "git"; sem Git instalado os testes passam sem verificar nada. As regras puras (CommitAt,
// StaleReviews, ResetReview, BackfillRevisions) estao em Tests.Review.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils, System.DateUtils, DUnitX.TestFramework,
  CM.Analyzer, CM.Store, CM.Stats, CM.Git, CM.GitReview, Tests.Helpers;

type
  [TestFixture]
  TGitTests = class
  private
    FDir: TTempDir;
    function Git(const AArgs: string): string;
    procedure Commit(const AMessage: string);
    function HaveGit: Boolean;
    function Root: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure OutsideARepositoryThereIsNoHead;
    [Test] procedure HeadAfterTheFirstCommit;
    [Test] procedure TimelineIsNewestFirst;
    [Test] procedure ChangedSinceListsCommittedAndUncommittedChanges;
    [Test] procedure ChangedSinceUnknownRevisionIsFalse;
    [Test] procedure PathsAreRelativeToTheProjectFolder;
    [Test] procedure CommitsSinceListsTheOnesThatTouchedTheFile;
    [Test] procedure FileNamesWithAccentsComeBackIntact;
    [Test] procedure StaleReviewsFindsReviewedFilesThatChanged;
    [Test] procedure ReviewingAgainAtTheNewHeadClearsTheFlag;
    [Test] procedure PendingFilesAreNeverStale;
    [Test] procedure OldReviewsGetACommitFromTheirTime;
    [Test] procedure NoRepositoryMeansNothingStale;
    [Test] procedure StaleHintMentionsTheCommits;
    [Test] procedure StaleHintForUncommittedChanges;
  end;

implementation

function TGitTests.HaveGit: Boolean;
begin
  Result := GitAvailable;
end;

function TGitTests.Root: string;
begin
  Result := FDir.Path;
end;

function TGitTests.Git(const AArgs: string): string;
begin
  RunGit(Root, AArgs, Result);
end;

procedure TGitTests.Commit(const AMessage: string);
begin
  Git('add -A');
  Git('-c user.name=Teste -c user.email=teste@exemplo.pt commit -q -m ' + GitQuote(AMessage));
end;

procedure TGitTests.Setup;
begin
  FDir := TTempDir.Create;
end;

procedure TGitTests.TearDown;
begin
  FDir.Free;
end;

procedure TGitTests.OutsideARepositoryThereIsNoHead;
begin
  if not HaveGit then Exit;
  Assert.AreEqual('', GitHead(Root));
  Assert.AreEqual<NativeInt>(0, Length(GitTimeline(Root)));
end;

procedure TGitTests.HeadAfterTheFirstCommit;
begin
  if not HaveGit then Exit;
  Git('init -q');
  Assert.AreEqual('', GitHead(Root), 'sem commits');
  FDir.Write('a.pas', 'unit a;');
  Commit('primeiro');
  Assert.AreEqual<NativeInt>(40, Length(GitHead(Root)));
end;

procedure TGitTests.TimelineIsNewestFirst;
var
  T: TArray<TCommitTime>;
  First: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  Commit('um');
  First := GitHead(Root);
  FDir.Write('a.pas', 'unit a; // 2');
  Commit('dois');
  T := GitTimeline(Root);
  Assert.AreEqual<NativeInt>(2, Length(T));
  Assert.AreEqual(GitHead(Root), T[0].Hash, 'o mais recente primeiro');
  Assert.AreEqual(First, T[1].Hash);
  Assert.IsTrue(T[0].Time >= T[1].Time);
end;

procedure TGitTests.ChangedSinceListsCommittedAndUncommittedChanges;
var
  Rev: string;
  Changed: THashSet<string>;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  FDir.Write('b.pas', 'unit b;');
  FDir.Write('c.pas', 'unit c;');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('b.pas', 'unit b; // mudou e gravado');
  Commit('muda b');
  FDir.Write('c.pas', 'unit c; // mudou, por gravar');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(GitChangedSince(Root, Rev, Changed));
    Assert.IsFalse(Changed.Contains('a.pas'), 'nao mudou');
    Assert.IsTrue(Changed.Contains('b.pas'), 'commit');
    Assert.IsTrue(Changed.Contains('c.pas'), 'alteracao por gravar');
  finally
    Changed.Free;
  end;
end;

procedure TGitTests.ChangedSinceUnknownRevisionIsFalse;
var
  Changed: THashSet<string>;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  Commit('base');
  Changed := THashSet<string>.Create;
  try
    Assert.IsFalse(GitChangedSince(Root, '0123456789abcdef0123456789abcdef01234567', Changed));
    Assert.AreEqual<NativeInt>(0, Changed.Count);
    Assert.IsFalse(GitChangedSince(Root, '', Changed));
  finally
    Changed.Free;
  end;
end;

procedure TGitTests.PathsAreRelativeToTheProjectFolder;
var
  Rev: string;
  Changed: THashSet<string>;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('src/Core/a.pas', 'unit a;');
  FDir.Write('outro.txt', 'x');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('src/Core/a.pas', 'unit a; // mudou');
  FDir.Write('outro.txt', 'y');
  Changed := THashSet<string>.Create;
  try
    // o projecto e a subpasta "src": os caminhos vem relativos a ela e o que esta fora nao aparece
    Assert.IsTrue(GitChangedSince(TPath.Combine(Root, 'src'), Rev, Changed));
    Assert.IsTrue(Changed.Contains('Core/a.pas'));
    Assert.IsFalse(Changed.Contains('outro.txt'));
    Assert.IsFalse(Changed.Contains('src/Core/a.pas'));
  finally
    Changed.Free;
  end;
end;

procedure TGitTests.CommitsSinceListsTheOnesThatTouchedTheFile;
var
  Rev: string;
  C: TArray<TGitCommit>;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  FDir.Write('b.pas', 'unit b;');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('a.pas', 'unit a; // 1');
  Commit('altera a');
  FDir.Write('b.pas', 'unit b; // 1');
  Commit('altera b');
  FDir.Write('a.pas', 'unit a; // 2');
  Commit('altera a outra vez');
  C := GitCommitsSince(Root, Rev, 'a.pas', 5);
  Assert.AreEqual<NativeInt>(2, Length(C), 'so os que tocaram em a.pas');
  Assert.AreEqual('altera a outra vez', C[0].Subject, 'o mais recente primeiro');
  Assert.AreEqual('Teste', C[0].Author);
  Assert.AreEqual<NativeInt>(10, Length(C[0].Date), 'aaaa-mm-dd');
  Assert.AreEqual<NativeInt>(1, Length(GitCommitsSince(Root, Rev, 'a.pas', 1)), 'respeita o maximo');
end;

procedure TGitTests.FileNamesWithAccentsComeBackIntact;
var
  Rev: string;
  Changed: THashSet<string>;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('Configuração.pas', 'unit c;');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('Configuração.pas', 'unit c; // mudou');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(GitChangedSince(Root, Rev, Changed));
    Assert.IsTrue(Changed.Contains('Configuração.pas'), 'sem escapes octais nem aspas');
  finally
    Changed.Free;
  end;
end;

procedure TGitTests.StaleReviewsFindsReviewedFilesThatChanged;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TGitReviewResult;
  Head: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin end;'));
  FDir.Write('b.pas', WrapUnit('procedure B;', 'procedure B; begin end;'));
  Commit('base');
  Head := GitHead(Root);
  Scan := ScanProject(Root, nil);
  St := TProgressState.Create;
  try
    SetMethodReview(Scan.Units[0], St.Rec('a.pas'), 'A', rsDone);
    St.Rec('a.pas').Rev := Head;
    SetMethodReview(Scan.Units[1], St.Rec('b.pas'), 'B', rsInReview);
    St.Rec('b.pas').Rev := Head;
    FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin Writeln(1); end;'));
    R := FindStaleReviews(Root, Scan, St);
    try
      Assert.AreEqual(Head, R.Head);
      Assert.IsTrue(R.Stale.Contains('a.pas'));
      Assert.IsFalse(R.Stale.Contains('b.pas'), 'nao mudou');
    finally
      R.Stale.Free;
    end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TGitTests.ReviewingAgainAtTheNewHeadClearsTheFlag;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TGitReviewResult;
  First: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin end;'));
  Commit('base');
  First := GitHead(Root);
  Scan := ScanProject(Root, nil);
  St := TProgressState.Create;
  try
    SetMethodReview(Scan.Units[0], St.Rec('a.pas'), 'A', rsDone);
    St.Rec('a.pas').Rev := First;
    FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin Writeln(1); end;'));
    Commit('muda a');
    R := FindStaleReviews(Root, Scan, St);
    Assert.IsTrue(R.Stale.Contains('a.pas'));
    R.Stale.Free;
    St.Rec('a.pas').Rev := GitHead(Root);       // revisto de novo, ja com a alteracao
    R := FindStaleReviews(Root, Scan, St);
    try
      Assert.AreEqual<NativeInt>(0, R.Stale.Count);
    finally
      R.Stale.Free;
    end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TGitTests.PendingFilesAreNeverStale;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TGitReviewResult;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin end;'));
  Commit('base');
  Scan := ScanProject(Root, nil);
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Rev := GitHead(Root);          // tem commit mas esta por rever
    FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin Writeln(1); end;'));
    R := FindStaleReviews(Root, Scan, St);
    try
      Assert.AreEqual<NativeInt>(0, R.Stale.Count);
    finally
      R.Stale.Free;
    end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TGitTests.OldReviewsGetACommitFromTheirTime;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TGitReviewResult;
  Head: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin end;'));
  Commit('base');
  Head := GitHead(Root);
  Scan := ScanProject(Root, nil);
  St := TProgressState.Create;
  try
    SetMethodReview(Scan.Units[0], St.Rec('a.pas'), 'A', rsDone);
    St.Rec('a.pas').Rev := '';
    St.Rec('a.pas').Ts := (DateTimeToUnix(Now, False) + 3600) * 1000;   // concluida "depois" do commit
    R := FindStaleReviews(Root, Scan, St);
    try
      Assert.AreEqual(1, R.Backfilled);
      Assert.AreEqual(Head, St.Find('a.pas').Rev);
      Assert.AreEqual<NativeInt>(0, R.Stale.Count, 'ainda nao mudou');
    finally
      R.Stale.Free;
    end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TGitTests.NoRepositoryMeansNothingStale;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TGitReviewResult;
begin
  if not HaveGit then Exit;
  FDir.Write('a.pas', WrapUnit('procedure A;', 'procedure A; begin end;'));
  Scan := ScanProject(Root, nil);
  St := TProgressState.Create;
  try
    R := FindStaleReviews(Root, Scan, St);
    try
      Assert.AreEqual('', R.Head);
      Assert.AreEqual<NativeInt>(0, R.Stale.Count);
    finally
      R.Stale.Free;
    end;
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TGitTests.StaleHintMentionsTheCommits;
var
  Rev, Hint: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('a.pas', 'unit a; // 1');
  Commit('corrige o erro');
  Hint := StaleHint(Root, Rev, 'a.pas');
  Assert.IsTrue(Hint.StartsWith('Mudou desde a revisão'), Hint);
  Assert.IsTrue(Hint.Contains('Teste'), Hint);
  Assert.IsTrue(Hint.Contains('corrige o erro'), Hint);
end;

procedure TGitTests.StaleHintForUncommittedChanges;
var
  Rev: string;
begin
  if not HaveGit then Exit;
  Git('init -q');
  FDir.Write('a.pas', 'unit a;');
  Commit('base');
  Rev := GitHead(Root);
  FDir.Write('a.pas', 'unit a; // por gravar');
  Assert.IsTrue(StaleHint(Root, Rev, 'a.pas').Contains('por gravar no Git'));
end;

end.
