unit Tests.Svn;

// Testes da integracao com o Subversion (CM.Svn) e da escolha do sistema de controlo de versoes (CM.Vcs).
// Os analisadores do XML do svn testam-se com textos de exemplo. Os restantes usam um repositorio temporario criado
// com o proprio "svnadmin" e uma copia de trabalho feita com o "svn"; sem o Subversion instalado esses testes passam
// sem verificar nada.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, DUnitX.TestFramework,
  CM.Stats, CM.Proc, CM.Svn, CM.Vcs, Tests.Helpers;

type
  [TestFixture]
  TSvnParserTests = class
  public
    [Test] procedure LogEntriesCarryRevisionAuthorDateAndMessage;
    [Test] procedure LogEntriesCarryTheirPaths;
    [Test] procedure XmlEntitiesAreDecoded;
    [Test] procedure LogWithoutEntriesIsEmpty;
    [Test] procedure GarbageIsNotALog;
    [Test] procedure StatusKeepsOnlyRealChanges;
    [Test] procedure StatusPathsUseForwardSlashes;
    [Test] procedure IsoDatesBecomeUnixTimes;
    [Test] procedure BadIsoDatesAreRejected;
    [Test] procedure RepoPathIsDecodedAndTrimmed;
    [Test] procedure PathsAreMadeRelativeToTheProject;
    [Test] procedure ProjectAtTheRepositoryRootKeepsEveryPath;
  end;

  [TestFixture]
  TVcsDetectTests = class
  private
    FDir: TTempDir;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NoMarkerMeansNoVcs;
    [Test] procedure GitFolderIsGit;
    [Test] procedure GitFileOfAWorktreeIsGit;
    [Test] procedure SvnFolderIsSvn;
    [Test] procedure MarkersAreFoundInParentFolders;
    [Test] procedure TheNearestMarkerWins;
    [Test] procedure NamesAreReadable;
    [Test] procedure EmptyPathIsNone;
  end;

  [TestFixture]
  TSvnRepoTests = class
  private
    FRepo, FWork: TTempDir;
    FReady: Boolean;
    function Tool(const ACmd, AWorkDir: string): Boolean;
    function UrlOfRepo: string;
    function Wc: string;
    procedure Commit(const AMessage: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TheTestRepositoryIsCreated;
    [Test] procedure OutsideACopyThereIsNoHead;
    [Test] procedure HeadIsTheRevisionOfTheCopy;
    [Test] procedure TimelineIsNewestFirst;
    [Test] procedure ChangedSinceListsCommittedAndUncommittedChanges;
    [Test] procedure ChangedSinceTheCurrentRevisionListsOnlyLocalChanges;
    [Test] procedure ChangedSinceUnknownRevisionIsFalse;
    [Test] procedure PathsAreRelativeToTheProjectFolder;
    [Test] procedure CommitsSinceListsTheOnesThatTouchedTheFile;
    [Test] procedure CommitsSinceKeepsAccentsInTheMessage;
    [Test] procedure VcsDispatchesToSubversion;
  end;

implementation

const
  LogXml =
    '<?xml version="1.0" encoding="UTF-8"?><log>' +
    '<logentry revision="12"><author>ana</author><date>2026-10-03T12:30:45.123456Z</date><msg>Corrige o erro</msg></logentry>' +
    '<logentry revision="11"><author>rui</author><date>2026-10-02T08:00:00.000000Z</date>' +
    '<paths><path action="M" prop-mods="false" text-mods="true" kind="file">/trunk/proj/src/a.pas</path>' +
    '<path action="A" kind="file">/trunk/proj/src/b.pas</path></paths><msg>Duas linhas</msg></logentry></log>';

{ TSvnParserTests }

procedure TSvnParserTests.LogEntriesCarryRevisionAuthorDateAndMessage;
var
  E: TArray<TSvnEntry>;
begin
  E := SvnParseLog(LogXml);
  Assert.AreEqual<NativeInt>(2, Length(E));
  Assert.AreEqual(12, E[0].Revision);
  Assert.AreEqual('ana', E[0].Author);
  Assert.AreEqual('2026-10-03T12:30:45.123456Z', E[0].Date);
  Assert.AreEqual('Corrige o erro', E[0].Msg);
  Assert.AreEqual(11, E[1].Revision);
end;

procedure TSvnParserTests.LogEntriesCarryTheirPaths;
var
  E: TArray<TSvnEntry>;
begin
  E := SvnParseLog(LogXml);
  Assert.AreEqual<NativeInt>(0, Length(E[0].Paths), 'sem -v nao ha caminhos');
  Assert.AreEqual<NativeInt>(2, Length(E[1].Paths));
  Assert.AreEqual('/trunk/proj/src/a.pas', E[1].Paths[0]);
  Assert.AreEqual('/trunk/proj/src/b.pas', E[1].Paths[1]);
end;

procedure TSvnParserTests.XmlEntitiesAreDecoded;
var
  E: TArray<TSvnEntry>;
begin
  E := SvnParseLog('<log><logentry revision="3"><author>a&amp;b</author><date>2026-01-01T00:00:00.000000Z</date>' +
    '<paths><path action="M">/x/a&amp;b.pas</path></paths><msg>x &lt; y &quot;ok&quot; &apos;z&apos;</msg></logentry></log>');
  Assert.AreEqual('a&b', E[0].Author);
  Assert.AreEqual('/x/a&b.pas', E[0].Paths[0]);
  Assert.AreEqual('x < y "ok" ''z''', E[0].Msg);
end;

procedure TSvnParserTests.LogWithoutEntriesIsEmpty;
begin
  Assert.AreEqual<NativeInt>(0, Length(SvnParseLog('<?xml version="1.0"?><log></log>')));
end;

procedure TSvnParserTests.GarbageIsNotALog;
begin
  Assert.AreEqual<NativeInt>(0, Length(SvnParseLog('svn: E155007: nao e uma copia de trabalho')));
  Assert.AreEqual<NativeInt>(0, Length(SvnParseStatus('')));
end;

procedure TSvnParserTests.StatusKeepsOnlyRealChanges;
var
  P: TArray<string>;
begin
  P := SvnParseStatus(
    '<status><target path="."><entry path="a.pas"><wc-status item="modified" props="none"></wc-status></entry>' +
    '<entry path="b.pas"><wc-status item="added" props="none"></wc-status></entry>' +
    '<entry path="c.pas"><wc-status item="deleted" props="none"></wc-status></entry>' +
    '<entry path="d.pas"><wc-status item="unversioned" props="none"></wc-status></entry>' +
    '<entry path="e.pas"><wc-status item="normal" props="modified"></wc-status></entry>' +
    '<entry path="f.pas"><wc-status item="conflicted" props="none"></wc-status></entry>' +
    '<entry path="g.pas"><wc-status item="missing" props="none"></wc-status></entry>' +
    '<entry path="h.pas"><wc-status item="replaced" props="none"></wc-status></entry>' +
    '<entry path="i.pas"><wc-status item="ignored" props="none"></wc-status></entry></target></status>');
  Assert.AreEqual<NativeInt>(6, Length(P));
  Assert.AreEqual('a.pas', P[0]);
  Assert.AreEqual('h.pas', P[5]);
end;

procedure TSvnParserTests.StatusPathsUseForwardSlashes;
var
  P: TArray<string>;
begin
  P := SvnParseStatus('<status><target path="."><entry path="src\Core\a&amp;b.pas"><wc-status item="modified"></wc-status></entry></target></status>');
  Assert.AreEqual<NativeInt>(1, Length(P));
  Assert.AreEqual('src/Core/a&b.pas', P[0]);
end;

procedure TSvnParserTests.IsoDatesBecomeUnixTimes;
var
  T: Int64;
begin
  Assert.IsTrue(SvnIsoToUnix('1970-01-01T00:00:00.000000Z', T));
  Assert.AreEqual<Int64>(0, T);
  Assert.IsTrue(SvnIsoToUnix('2026-10-03T12:30:45.123456Z', T));
  Assert.AreEqual<Int64>(1791030645, T);
end;

procedure TSvnParserTests.BadIsoDatesAreRejected;
var
  T: Int64;
begin
  Assert.IsFalse(SvnIsoToUnix('', T));
  Assert.IsFalse(SvnIsoToUnix('ontem', T));
  Assert.IsFalse(SvnIsoToUnix('2026-13-45T99:99:99Z', T));
end;

procedure TSvnParserTests.RepoPathIsDecodedAndTrimmed;
begin
  Assert.AreEqual('/trunk/Meu Projeto', SvnRepoPathOf('^/trunk/Meu%20Projeto'#10));
  Assert.AreEqual('/trunk/a+b', SvnRepoPathOf('^/trunk/a+b'), 'o + e um +, nao um espaco');
  Assert.AreEqual('/trunk', SvnRepoPathOf('^/trunk/'));
  Assert.AreEqual('/', SvnRepoPathOf('^/'));
end;

procedure TSvnParserTests.PathsAreMadeRelativeToTheProject;
begin
  Assert.AreEqual('src/a.pas', SvnRelativeToProject('/trunk/proj/src/a.pas', '/trunk/proj'));
  Assert.AreEqual('', SvnRelativeToProject('/trunk/outro/a.pas', '/trunk/proj'), 'fora do projecto');
  Assert.AreEqual('', SvnRelativeToProject('/trunk/proj', '/trunk/proj'), 'a propria pasta nao e um ficheiro');
  Assert.AreEqual('', SvnRelativeToProject('/trunk/project2/a.pas', '/trunk/proj'), 'nao confundir prefixos de nomes');
end;

procedure TSvnParserTests.ProjectAtTheRepositoryRootKeepsEveryPath;
begin
  Assert.AreEqual('src/a.pas', SvnRelativeToProject('/src/a.pas', '/'));
  Assert.AreEqual('src/a.pas', SvnRelativeToProject('/src/a.pas', ''));
end;

{ TVcsDetectTests }

procedure TVcsDetectTests.Setup;
begin
  FDir := TTempDir.Create;
end;

procedure TVcsDetectTests.TearDown;
begin
  FDir.Free;
end;

procedure TVcsDetectTests.NoMarkerMeansNoVcs;
begin
  TDirectory.CreateDirectory(FDir.Full('proj'));
  Assert.AreEqual(Ord(vkNone), Ord(DetectVcs(FDir.Full('proj'))));
end;

procedure TVcsDetectTests.GitFolderIsGit;
begin
  TDirectory.CreateDirectory(FDir.Full('.git'));
  Assert.AreEqual(Ord(vkGit), Ord(DetectVcs(FDir.Path)));
end;

procedure TVcsDetectTests.GitFileOfAWorktreeIsGit;
begin
  TFile.WriteAllText(FDir.Full('.git'), 'gitdir: ../outro/.git/worktrees/x');
  Assert.AreEqual(Ord(vkGit), Ord(DetectVcs(FDir.Path)));
end;

procedure TVcsDetectTests.SvnFolderIsSvn;
begin
  TDirectory.CreateDirectory(FDir.Full('.svn'));
  Assert.AreEqual(Ord(vkSvn), Ord(DetectVcs(FDir.Path)));
end;

procedure TVcsDetectTests.MarkersAreFoundInParentFolders;
begin
  TDirectory.CreateDirectory(FDir.Full('.svn'));
  TDirectory.CreateDirectory(FDir.Full('a/b/c'));
  Assert.AreEqual(Ord(vkSvn), Ord(DetectVcs(FDir.Full('a/b/c'))), 'a copia SVN 1.7+ so tem .svn na raiz');
  Assert.AreEqual(Ord(vkSvn), Ord(DetectVcs(FDir.Full('a/b/c') + PathDelim)), 'com a barra no fim');
end;

procedure TVcsDetectTests.TheNearestMarkerWins;
begin
  TDirectory.CreateDirectory(FDir.Full('.git'));
  TDirectory.CreateDirectory(FDir.Full('svnproj/.svn'));
  TDirectory.CreateDirectory(FDir.Full('svnproj/src'));
  Assert.AreEqual(Ord(vkSvn), Ord(DetectVcs(FDir.Full('svnproj/src'))), 'copia SVN dentro de um repositorio Git');
  Assert.AreEqual(Ord(vkGit), Ord(DetectVcs(FDir.Path)));
end;

procedure TVcsDetectTests.NamesAreReadable;
begin
  Assert.AreEqual('Git', VcsName(vkGit));
  Assert.AreEqual('Subversion', VcsName(vkSvn));
  Assert.AreEqual('', VcsName(vkNone));
end;

procedure TVcsDetectTests.EmptyPathIsNone;
begin
  Assert.AreEqual(Ord(vkNone), Ord(DetectVcs('')));
  Assert.AreEqual(Ord(vkNone), Ord(DetectVcs('   ')));
end;

{ TSvnRepoTests }

function TSvnRepoTests.Tool(const ACmd, AWorkDir: string): Boolean;
var
  Output: string;
begin
  Result := RunProcess(ACmd, AWorkDir, Output, 60000);
end;

function TSvnRepoTests.UrlOfRepo: string;
begin
  Result := 'file:///' + FRepo.Path.Replace('\', '/').Replace(' ', '%20');
end;

function TSvnRepoTests.Wc: string;
begin
  Result := FWork.Path;
end;

procedure TSvnRepoTests.Setup;
begin
  FReady := False;
  FRepo := TTempDir.Create;
  FWork := TTempDir.Create;
  if not SvnAvailable then
    Exit;
  // o repositorio fica numa pasta propria dentro da temporaria: o svnadmin exige uma pasta vazia ou nova
  FReady := Tool('svnadmin create ' + QuoteArg(FRepo.Path), '') and
    Tool('svn --non-interactive checkout ' + QuoteArg(UrlOfRepo) + ' ' + QuoteArg(Wc), '');
end;

procedure TSvnRepoTests.TearDown;
begin
  FWork.Free;
  FRepo.Free;
end;

procedure TSvnRepoTests.Commit(const AMessage: string);
begin
  Tool('svn --non-interactive add --force --quiet .', Wc);
  Tool('svn --non-interactive commit -m ' + QuoteArg(AMessage), Wc);
end;

// sem isto, uma falha a criar o repositorio faria passar todos os outros testes sem verificarem nada
procedure TSvnRepoTests.TheTestRepositoryIsCreated;
begin
  if not SvnAvailable then
    Exit;
  Assert.IsTrue(FReady, 'o svnadmin/svn nao conseguiram criar o repositorio de teste');
  Assert.IsTrue(TDirectory.Exists(TPath.Combine(Wc, '.svn')));
end;

procedure TSvnRepoTests.OutsideACopyThereIsNoHead;
var
  Plain: TTempDir;
begin
  if not SvnAvailable then
    Exit;
  Plain := TTempDir.Create;
  try
    Assert.AreEqual('', SvnHead(Plain.Path));
    Assert.AreEqual<NativeInt>(0, Length(SvnTimeline(Plain.Path)));
  finally
    Plain.Free;
  end;
end;

procedure TSvnRepoTests.HeadIsTheRevisionOfTheCopy;
begin
  if not FReady then
    Exit;
  Assert.AreEqual('0', SvnHead(Wc), 'copia recem feita, sem commits');
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b;');
  Commit('segunda');
  Tool('svn --non-interactive update', Wc);
  Assert.AreEqual('2', SvnHead(Wc));
end;

procedure TSvnRepoTests.TimelineIsNewestFirst;
var
  T: TArray<TCommitTime>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b;');
  Commit('segunda');
  Tool('svn --non-interactive update', Wc);
  T := SvnTimeline(Wc);
  Assert.AreEqual<NativeInt>(2, Length(T));
  Assert.AreEqual('2', T[0].Hash);
  Assert.AreEqual('1', T[1].Hash);
  Assert.IsTrue(T[0].Time >= T[1].Time);
  Assert.IsTrue(T[0].Time > 1700000000, 'uma hora de Unix com sentido');
end;

procedure TSvnRepoTests.ChangedSinceListsCommittedAndUncommittedChanges;
var
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  TFile.WriteAllText(TPath.Combine(Wc, 'c.pas'), 'unit c;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b;');
  Commit('segunda');
  Tool('svn --non-interactive update', Wc);
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a; // mudou por gravar');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(SvnChangedSince(Wc, '1', Changed));
    Assert.IsTrue(Changed.Contains('b.pas'), 'enviado depois da revisao 1');
    Assert.IsTrue(Changed.Contains('a.pas'), 'alterado e ainda por enviar');
    Assert.IsFalse(Changed.Contains('c.pas'), 'nao mudou');
  finally
    Changed.Free;
  end;
end;

procedure TSvnRepoTests.ChangedSinceTheCurrentRevisionListsOnlyLocalChanges;
var
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b;');
  Commit('primeira');
  Tool('svn --non-interactive update', Wc);
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b; // local');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(SvnChangedSince(Wc, '1', Changed));
    Assert.AreEqual<NativeInt>(1, Changed.Count);
    Assert.IsTrue(Changed.Contains('b.pas'));
  finally
    Changed.Free;
  end;
end;

procedure TSvnRepoTests.ChangedSinceUnknownRevisionIsFalse;
var
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  Commit('primeira');
  Tool('svn --non-interactive update', Wc);
  Changed := THashSet<string>.Create;
  try
    Assert.IsFalse(SvnChangedSince(Wc, '99', Changed), 'a copia nao conhece a revisao 99');
    Assert.IsFalse(SvnChangedSince(Wc, 'abc123def', Changed), 'um hash do Git nao e uma revisao');
    Assert.IsFalse(SvnChangedSince(Wc, '', Changed));
  finally
    Changed.Free;
  end;
end;

procedure TSvnRepoTests.PathsAreRelativeToTheProjectFolder;
var
  Changed: THashSet<string>;
  Proj: string;
begin
  if not FReady then
    Exit;
  TDirectory.CreateDirectory(TPath.Combine(Wc, 'proj/src'));
  TDirectory.CreateDirectory(TPath.Combine(Wc, 'outro'));
  TFile.WriteAllText(TPath.Combine(Wc, 'proj/src/x.pas'), 'unit x;');
  TFile.WriteAllText(TPath.Combine(Wc, 'outro/y.pas'), 'unit y;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'proj/src/x.pas'), 'unit x; // v2');
  TFile.WriteAllText(TPath.Combine(Wc, 'outro/y.pas'), 'unit y; // v2');
  Commit('segunda');
  Tool('svn --non-interactive update', Wc);
  Proj := TPath.Combine(Wc, 'proj');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(SvnChangedSince(Proj, '1', Changed));
    Assert.IsTrue(Changed.Contains('src/x.pas'), 'relativo ao projecto, nao ao repositorio');
    Assert.IsFalse(Changed.Contains('outro/y.pas'));
    Assert.IsFalse(Changed.Contains('y.pas'));
    Assert.AreEqual<NativeInt>(1, Changed.Count);
  finally
    Changed.Free;
  end;
end;

procedure TSvnRepoTests.CommitsSinceListsTheOnesThatTouchedTheFile;
var
  C: TArray<TVcsCommit>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a; // 2');
  Commit('mexe no a');
  TFile.WriteAllText(TPath.Combine(Wc, 'b.pas'), 'unit b; // 2');
  Commit('mexe no b');
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a; // 3');
  Commit('outra vez no a');
  Tool('svn --non-interactive update', Wc);
  C := SvnCommitsSince(Wc, '1', 'a.pas', 5);
  Assert.AreEqual<NativeInt>(2, Length(C), 'so os que tocaram em a.pas');
  Assert.AreEqual('r4', C[0].Hash);
  Assert.AreEqual('outra vez no a', C[0].Subject);
  Assert.AreEqual('r2', C[1].Hash);
  Assert.AreEqual(10, Length(C[0].Date));
  Assert.IsTrue(C[0].Author <> '', 'o autor e o utilizador do Windows');
  Assert.AreEqual<NativeInt>(1, Length(SvnCommitsSince(Wc, '1', 'a.pas', 1)), 'o maximo conta');
  Assert.AreEqual<NativeInt>(0, Length(SvnCommitsSince(Wc, '4', 'a.pas', 5)), 'nada depois da revisao actual');
end;

procedure TSvnRepoTests.CommitsSinceKeepsAccentsInTheMessage;
var
  C: TArray<TVcsCommit>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  Commit('primeira');
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a; // 2');
  Commit('Correção da acentuação');
  Tool('svn --non-interactive update', Wc);
  C := SvnCommitsSince(Wc, '1', 'a.pas', 3);
  Assert.AreEqual<NativeInt>(1, Length(C));
  Assert.AreEqual('Correção da acentuação', C[0].Subject);
end;

procedure TSvnRepoTests.VcsDispatchesToSubversion;
var
  T: TArray<TCommitTime>;
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a;');
  Commit('primeira');
  Tool('svn --non-interactive update', Wc);
  Assert.AreEqual(Ord(vkSvn), Ord(DetectVcs(Wc)));
  Assert.AreEqual('1', VcsHead(Wc));
  T := VcsTimeline(Wc);
  Assert.AreEqual<NativeInt>(1, Length(T));
  TFile.WriteAllText(TPath.Combine(Wc, 'a.pas'), 'unit a; // 2');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(VcsChangedSince(Wc, '1', Changed));
    Assert.IsTrue(Changed.Contains('a.pas'));
  finally
    Changed.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSvnParserTests);
  TDUnitX.RegisterTestFixture(TVcsDetectTests);
  TDUnitX.RegisterTestFixture(TSvnRepoTests);

end.
