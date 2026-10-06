unit Tests.Hg;

// Testes da integracao com o Mercurial (CM.Hg) e da sua deteccao em CM.Vcs. Os analisadores testam-se com textos de
// exemplo. Os restantes usam um repositorio temporario criado com o proprio "hg"; sem o Mercurial instalado esses
// testes passam sem verificar nada.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, DUnitX.TestFramework,
  CM.Stats, CM.Proc, CM.Hg, CM.Vcs, Tests.Helpers;

type
  [TestFixture]
  THgParserTests = class
  public
    [Test] procedure TimelineReadsNodesAndUnixSeconds;
    [Test] procedure TimelineSkipsLinesThatAreNotRevisions;
    [Test] procedure StatusKeepsModifiedAddedRemovedAndMissing;
    [Test] procedure StatusPathsUseForwardSlashesAndKeepSpaces;
    [Test] procedure CommitsReadTheFourFields;
    [Test] procedure CommitsSkipShortLines;
    [Test] procedure NodeMustBeFortyHexDigitsAndNotNull;
    [Test] procedure RevisionsAreOnlyHexadecimal;
    [Test] procedure OutputIsDecodedAsUtf8OrTheWindowsCodePage;
  end;

  [TestFixture]
  THgDetectTests = class
  private
    FDir: TTempDir;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure HgFolderIsMercurial;
    [Test] procedure MercurialIsFoundInParentFolders;
    [Test] procedure TheNearestMarkerWinsAmongGitAndMercurial;
    [Test] procedure NameIsReadable;
  end;

  [TestFixture]
  THgRepoTests = class
  private
    FDir: TTempDir;
    FReady: Boolean;
    function Tool(const AArgs: string): Boolean;
    procedure Commit(const AMessage: string; const AUser: string = 'Joao Teste <joao@teste.pt>');
    function Root: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure TheTestRepositoryIsCreated;
    [Test] procedure OutsideARepositoryThereIsNoHead;
    [Test] procedure ARepositoryWithoutCommitsHasNoHead;
    [Test] procedure HeadIsTheFullNode;
    [Test] procedure TimelineIsNewestFirst;
    [Test] procedure ChangedSinceListsCommittedAndUncommittedChanges;
    [Test] procedure ChangedSinceKeepsAccentsAndSpacesInNames;
    [Test] procedure ChangedSincePathsAreRelativeToAProjectSubfolder;
    [Test] procedure ChangedSinceUnknownRevisionIsFalse;
    [Test] procedure ChangedSinceRefusesAnythingButAHash;
    [Test] procedure CommitsSinceListsOnlyThoseThatTouchedThePath;
    [Test] procedure VcsDispatchesToMercurial;
  end;

implementation

const
  Node1 = '8b35747ad229d182d57884da130fb7179e70a6ad';
  Node2 = 'e64dce1da0dd9badd9540ce11b383d8360a51f67';

{ THgParserTests }

procedure THgParserTests.TimelineReadsNodesAndUnixSeconds;
var
  T: TArray<TCommitTime>;
begin
  T := HgParseTimeline(Node1 + ' 1791280595 -3600' + #13#10 + Node2 + ' 1791280594 0' + #10);
  Assert.AreEqual<NativeInt>(2, Length(T));
  Assert.AreEqual(Node1, T[0].Hash);
  Assert.AreEqual<Int64>(1791280595, T[0].Time);
  Assert.AreEqual(Node2, T[1].Hash);
  Assert.AreEqual<Int64>(1791280594, T[1].Time);
end;

procedure THgParserTests.TimelineSkipsLinesThatAreNotRevisions;
begin
  Assert.AreEqual<NativeInt>(0, Length(HgParseTimeline('')));
  Assert.AreEqual<NativeInt>(0, Length(HgParseTimeline('abort: no repository found')));
  Assert.AreEqual<NativeInt>(0, Length(HgParseTimeline(Node1 + ' semtempo')));
  Assert.AreEqual<NativeInt>(1, Length(HgParseTimeline('lixo' + #10 + Node1 + ' 5 0')));
end;

procedure THgParserTests.StatusKeepsModifiedAddedRemovedAndMissing;
var
  P: TArray<string>;
begin
  P := HgParseStatus('M a.pas' + #10 + 'A b.pas' + #10 + 'R c.pas' + #10 + '! d.pas' + #10 + '? e.pas' + #10 +
    'C f.pas' + #10 + 'I g.pas' + #10);
  Assert.AreEqual<NativeInt>(4, Length(P));
  Assert.AreEqual('a.pas', P[0]);
  Assert.AreEqual('b.pas', P[1]);
  Assert.AreEqual('c.pas', P[2]);
  Assert.AreEqual('d.pas', P[3]);
end;

procedure THgParserTests.StatusPathsUseForwardSlashesAndKeepSpaces;
var
  P: TArray<string>;
begin
  P := HgParseStatus('M src\Core\a b.pas' + #13#10);
  Assert.AreEqual<NativeInt>(1, Length(P));
  Assert.AreEqual('src/Core/a b.pas', P[0]);
end;

procedure THgParserTests.CommitsReadTheFourFields;
var
  C: TArray<TVcsCommit>;
begin
  C := HgParseCommits('8b35747ad229' + #9 + 'Maria Silva' + #9 + '2026-10-06' + #9 + 'segundo' + #10);
  Assert.AreEqual<NativeInt>(1, Length(C));
  Assert.AreEqual('8b35747ad229', C[0].Hash);
  Assert.AreEqual('Maria Silva', C[0].Author);
  Assert.AreEqual('2026-10-06', C[0].Date);
  Assert.AreEqual('segundo', C[0].Subject);
end;

procedure THgParserTests.CommitsSkipShortLines;
begin
  Assert.AreEqual<NativeInt>(0, Length(HgParseCommits('abort: erro')));
  Assert.AreEqual<NativeInt>(0, Length(HgParseCommits('a' + #9 + 'b')));
end;

procedure THgParserTests.NodeMustBeFortyHexDigitsAndNotNull;
begin
  Assert.AreEqual(Node1, HgNodeOf(Node1 + #13#10));
  Assert.AreEqual('', HgNodeOf(StringOfChar('0', 40)), 'o no nulo e um repositorio sem commits');
  Assert.AreEqual('', HgNodeOf('8b35747a'), 'curto demais');
  Assert.AreEqual('', HgNodeOf(StringOfChar('g', 40)));
  Assert.AreEqual('', HgNodeOf('abort: no repository found'));
  Assert.AreEqual('', HgNodeOf(''));
end;

procedure THgParserTests.RevisionsAreOnlyHexadecimal;
begin
  Assert.IsTrue(HgIsRevision(Node1));
  Assert.IsTrue(HgIsRevision('8b35747ad229'));
  Assert.IsFalse(HgIsRevision('--config=x'), 'nao pode passar por uma opcao');
  Assert.IsFalse(HgIsRevision('tip'));
  Assert.IsFalse(HgIsRevision('8b35747 "x"'));
  Assert.IsFalse(HgIsRevision('abc'), 'curto demais para ser unico');
  Assert.IsFalse(HgIsRevision(''));
end;

procedure THgParserTests.OutputIsDecodedAsUtf8OrTheWindowsCodePage;
begin
  Assert.AreEqual('ação', DecodeOutput(TEncoding.UTF8.GetBytes('ação')));
  Assert.AreEqual('', DecodeOutput(nil));
  // bytes que nao sao UTF-8 valido (e7 e3 = "ça" em cp1252) nao podem rebentar: leem-se na pagina de codigo local
  Assert.AreEqual<Integer>(3, Length(DecodeOutput(TBytes.Create($61, $E7, $E3))));
end;

{ THgDetectTests }

procedure THgDetectTests.Setup;
begin
  FDir := TTempDir.Create;
end;

procedure THgDetectTests.TearDown;
begin
  FDir.Free;
end;

procedure THgDetectTests.HgFolderIsMercurial;
begin
  TDirectory.CreateDirectory(FDir.Full('.hg'));
  Assert.AreEqual(Ord(vkHg), Ord(DetectVcs(FDir.Path)));
end;

procedure THgDetectTests.MercurialIsFoundInParentFolders;
begin
  TDirectory.CreateDirectory(FDir.Full('.hg'));
  TDirectory.CreateDirectory(FDir.Full('a/b/c'));
  Assert.AreEqual(Ord(vkHg), Ord(DetectVcs(FDir.Full('a/b/c'))));
end;

procedure THgDetectTests.TheNearestMarkerWinsAmongGitAndMercurial;
begin
  TDirectory.CreateDirectory(FDir.Full('.git'));
  TDirectory.CreateDirectory(FDir.Full('hgproj/.hg'));
  TDirectory.CreateDirectory(FDir.Full('hgproj/src'));
  Assert.AreEqual(Ord(vkHg), Ord(DetectVcs(FDir.Full('hgproj/src'))), 'Mercurial dentro de um repositorio Git');
  TDirectory.CreateDirectory(FDir.Full('outer/.hg'));
  TDirectory.CreateDirectory(FDir.Full('outer/gitproj/.git'));
  Assert.AreEqual(Ord(vkGit), Ord(DetectVcs(FDir.Full('outer/gitproj'))), 'Git dentro de um repositorio Mercurial');
end;

procedure THgDetectTests.NameIsReadable;
begin
  Assert.AreEqual('Mercurial', VcsName(vkHg));
end;

{ THgRepoTests }

function THgRepoTests.Root: string;
begin
  Result := FDir.Path;
end;

function THgRepoTests.Tool(const AArgs: string): Boolean;
var
  Output: string;
begin
  Result := RunHg(Root, AArgs, Output, 60000);
end;

procedure THgRepoTests.Commit(const AMessage, AUser: string);
begin
  Tool('add .');
  Tool('commit -u "' + AUser + '" -m "' + AMessage + '"');
end;

procedure THgRepoTests.Setup;
begin
  FDir := TTempDir.Create;
  FReady := HgAvailable and Tool('init');
end;

procedure THgRepoTests.TearDown;
begin
  FDir.Free;
end;

// sem isto, uma falha a criar o repositorio faria passar todos os outros testes sem verificarem nada
procedure THgRepoTests.TheTestRepositoryIsCreated;
begin
  if not HgAvailable then
    Exit;
  Assert.IsTrue(FReady, 'o hg nao conseguiu criar o repositorio de teste');
  Assert.IsTrue(TDirectory.Exists(FDir.Full('.hg')));
end;

procedure THgRepoTests.OutsideARepositoryThereIsNoHead;
var
  Plain: TTempDir;
begin
  if not HgAvailable then
    Exit;
  Plain := TTempDir.Create;
  try
    Assert.AreEqual('', HgHead(Plain.Path));
    Assert.AreEqual<NativeInt>(0, Length(HgTimeline(Plain.Path)));
  finally
    Plain.Free;
  end;
end;

procedure THgRepoTests.ARepositoryWithoutCommitsHasNoHead;
begin
  if not FReady then
    Exit;
  Assert.AreEqual('', HgHead(Root));
end;

procedure THgRepoTests.HeadIsTheFullNode;
var
  Head1: string;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  Head1 := HgHead(Root);
  Assert.AreEqual<Integer>(40, Length(Head1));
  FDir.Write('b.pas', 'unit b;');
  Commit('segunda');
  Assert.AreNotEqual(Head1, HgHead(Root));
end;

procedure THgRepoTests.TimelineIsNewestFirst;
var
  T: TArray<TCommitTime>;
  Head: string;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  FDir.Write('b.pas', 'unit b;');
  Commit('segunda');
  Head := HgHead(Root);
  T := HgTimeline(Root);
  Assert.AreEqual<NativeInt>(2, Length(T));
  Assert.AreEqual(Head, T[0].Hash, 'a mais recente primeiro');
  Assert.IsTrue(T[0].Time >= T[1].Time);
  Assert.IsTrue(T[0].Time > 1700000000, 'uma hora de Unix com sentido');
end;

procedure THgRepoTests.ChangedSinceListsCommittedAndUncommittedChanges;
var
  Changed: THashSet<string>;
  Rev1: string;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  FDir.Write('c.pas', 'unit c;');
  Commit('primeira');
  Rev1 := HgHead(Root);
  FDir.Write('b.pas', 'unit b;');
  Commit('segunda');
  FDir.Write('a.pas', 'unit a; // mudou por gravar');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(HgChangedSince(Root, Rev1, Changed));
    Assert.IsTrue(Changed.Contains('b.pas'), 'gravado depois da revisao 1');
    Assert.IsTrue(Changed.Contains('a.pas'), 'alterado e ainda por gravar');
    Assert.IsFalse(Changed.Contains('c.pas'), 'nao mudou');
  finally
    Changed.Free;
  end;
end;

procedure THgRepoTests.ChangedSinceKeepsAccentsAndSpacesInNames;
var
  Changed: THashSet<string>;
  Rev1: string;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  Rev1 := HgHead(Root);
  FDir.Write('src/ação x.pas', 'unit x;');
  Commit('com acento');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(HgChangedSince(Root, Rev1, Changed));
    Assert.IsTrue(Changed.Contains('src/ação x.pas'));
  finally
    Changed.Free;
  end;
end;

procedure THgRepoTests.ChangedSincePathsAreRelativeToAProjectSubfolder;
var
  Changed: THashSet<string>;
  Rev1: string;
begin
  if not FReady then
    Exit;
  FDir.Write('proj/a.pas', 'unit a;');
  FDir.Write('outro/z.pas', 'unit z;');
  Commit('primeira');
  Rev1 := HgHead(Root);
  FDir.Write('proj/sub/b.pas', 'unit b;');
  FDir.Write('outro/z.pas', 'unit z; // fora do projecto');
  Commit('segunda');
  Changed := THashSet<string>.Create;
  try
    Assert.IsTrue(HgChangedSince(FDir.Full('proj'), Rev1, Changed));
    Assert.IsTrue(Changed.Contains('sub/b.pas'), 'relativo a pasta do projecto');
    Assert.AreEqual<NativeInt>(1, Changed.Count, 'o que esta fora do projecto nao conta');
  finally
    Changed.Free;
  end;
end;

procedure THgRepoTests.ChangedSinceUnknownRevisionIsFalse;
var
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  Changed := THashSet<string>.Create;
  try
    Assert.IsFalse(HgChangedSince(Root, Node1, Changed), 'uma revisao que este repositorio nao tem');
    Assert.AreEqual<NativeInt>(0, Changed.Count);
  finally
    Changed.Free;
  end;
end;

procedure THgRepoTests.ChangedSinceRefusesAnythingButAHash;
var
  Changed: THashSet<string>;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  Changed := THashSet<string>.Create;
  try
    Assert.IsFalse(HgChangedSince(Root, 'tip', Changed));
    Assert.IsFalse(HgChangedSince(Root, '--config=ui.username=x', Changed));
    Assert.IsFalse(HgChangedSince(Root, '', Changed));
  finally
    Changed.Free;
  end;
end;

procedure THgRepoTests.CommitsSinceListsOnlyThoseThatTouchedThePath;
var
  C: TArray<TVcsCommit>;
  Rev1: string;
begin
  if not FReady then
    Exit;
  FDir.Write('src/a.pas', 'unit a;');
  FDir.Write('b.pas', 'unit b;');
  Commit('primeira');
  Rev1 := HgHead(Root);
  FDir.Write('src/a.pas', 'unit a; // um');
  Commit('mexe em a', 'Maria Silva <maria@teste.pt>');
  FDir.Write('b.pas', 'unit b; // dois');
  Commit('mexe em b');
  FDir.Write('src/a.pas', 'unit a; // tres');
  Commit('outra vez a');
  C := HgCommitsSince(Root, Rev1, 'src/a.pas', 10);
  Assert.AreEqual<NativeInt>(2, Length(C));
  Assert.AreEqual('outra vez a', C[0].Subject, 'o mais recente primeiro');
  Assert.AreEqual('mexe em a', C[1].Subject);
  Assert.AreEqual('Maria Silva', C[1].Author);
  Assert.AreEqual<Integer>(12, Length(C[1].Hash));
  Assert.AreEqual<Integer>(10, Length(C[1].Date));
  Assert.AreEqual<NativeInt>(1, Length(HgCommitsSince(Root, Rev1, 'src/a.pas', 1)), 'respeita o maximo');
  Assert.AreEqual<NativeInt>(0, Length(HgCommitsSince(Root, HgHead(Root), 'src/a.pas', 10)), 'nada depois do actual');
end;

procedure THgRepoTests.VcsDispatchesToMercurial;
var
  Head: string;
begin
  if not FReady then
    Exit;
  FDir.Write('a.pas', 'unit a;');
  Commit('primeira');
  Head := HgHead(Root);
  Assert.AreEqual(Ord(vkHg), Ord(DetectVcs(Root)));
  Assert.AreEqual(Head, VcsHead(Root));
  Assert.AreEqual<NativeInt>(1, Length(VcsTimeline(Root)));
end;

end.
