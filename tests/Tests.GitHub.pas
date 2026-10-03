unit Tests.GitHub;
// Testes da leitura de repositorios do GitHub: interpretacao do endereco e seguranca da cache.
// A clonagem em si precisa de rede e nao se testa aqui.

interface

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, DUnitX.TestFramework, CM.GitHub;

type
  [TestFixture]
  TGitHubTests = class
  private
    FOldData: string;
    FDataDir: string;
    function Parse(const AText: string; out ARef: TRepoRef): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ParsesTheWebAddress;
    [Test] procedure ParsesAddressesWithGitSuffixAndSlash;
    [Test] procedure ParsesShortOwnerRepo;
    [Test] procedure ParsesSshAddress;
    [Test] procedure ParsesBranchAndSubFolderFromATreeLink;
    [Test] procedure ParsesBranchAfterHash;
    [Test] procedure RejectsOtherServers;
    [Test] procedure RejectsIncompleteAddresses;
    [Test] procedure RejectsDangerousNames;
    [Test] procedure RejectsDangerousBranches;
    [Test] procedure DropsSubFolderThatEscapesTheRepository;
    [Test] procedure CloneUrlIsAlwaysBuiltFromValidatedParts;
    [Test] procedure CacheDirsLiveUnderTheDataFolder;
    [Test] procedure DeleteRepoCacheOnlyTouchesItsOwnFolder;
  end;

implementation

procedure TGitHubTests.Setup;
begin
  FOldData := GetEnvironmentVariable('CODEMANAGER_DATA');
  FDataDir := TPath.Combine(TPath.GetTempPath, 'cm-github-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(FDataDir);
  SetEnvironmentVariable('CODEMANAGER_DATA', PChar(FDataDir));
end;

procedure TGitHubTests.TearDown;
begin
  if FOldData = '' then
    SetEnvironmentVariable('CODEMANAGER_DATA', nil)
  else
    SetEnvironmentVariable('CODEMANAGER_DATA', PChar(FOldData));
  if TDirectory.Exists(FDataDir) then
    TDirectory.Delete(FDataDir, True);
end;

function TGitHubTests.Parse(const AText: string; out ARef: TRepoRef): Boolean;
var
  Err: string;
begin
  Result := ParseRepoUrl(AText, ARef, Err);
  if not Result then
    Assert.AreNotEqual('', Err, 'um endereco recusado tem de dizer porque');
end;

procedure TGitHubTests.ParsesTheWebAddress;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/JFSF/CodeManager', R));
  Assert.AreEqual('JFSF', R.Owner);
  Assert.AreEqual('CodeManager', R.Name);
  Assert.AreEqual('', R.Branch);
  Assert.AreEqual('', R.SubPath);
  Assert.AreEqual('https://github.com/JFSF/CodeManager.git', R.CloneUrl);
  Assert.AreEqual('https://github.com/JFSF/CodeManager', R.WebUrl);
  Assert.AreEqual('JFSF/CodeManager', R.Display);
end;

procedure TGitHubTests.ParsesAddressesWithGitSuffixAndSlash;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('  https://www.github.com/foo/bar.git/  ', R));
  Assert.AreEqual('foo', R.Owner);
  Assert.AreEqual('bar', R.Name);
  Assert.IsTrue(Parse('http://github.com/foo/bar?tab=readme', R));
  Assert.AreEqual('bar', R.Name);
  Assert.IsTrue(Parse('github.com/Foo/bar.baz', R));
  Assert.AreEqual('bar.baz', R.Name);
end;

procedure TGitHubTests.ParsesShortOwnerRepo;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('foo/bar', R));
  Assert.AreEqual('https://github.com/foo/bar.git', R.CloneUrl);
end;

procedure TGitHubTests.ParsesSshAddress;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('git@github.com:foo/bar.git', R));
  Assert.AreEqual('foo', R.Owner);
  Assert.AreEqual('bar', R.Name);
  Assert.AreEqual('https://github.com/foo/bar.git', R.CloneUrl, 'a clonagem e sempre por https');
end;

procedure TGitHubTests.ParsesBranchAndSubFolderFromATreeLink;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/foo/bar/tree/develop', R));
  Assert.AreEqual('develop', R.Branch);
  Assert.AreEqual('', R.SubPath);
  Assert.IsTrue(Parse('https://github.com/foo/bar/tree/main/src/Core', R));
  Assert.AreEqual('main', R.Branch);
  Assert.AreEqual('src/Core', R.SubPath);
  Assert.AreEqual('foo/bar@main', R.Display);
end;

procedure TGitHubTests.ParsesBranchAfterHash;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/foo/bar#release/1.0', R));
  Assert.AreEqual('release/1.0', R.Branch);
  Assert.AreEqual('bar', R.Name);
end;

procedure TGitHubTests.RejectsOtherServers;
var
  R: TRepoRef;
begin
  Assert.IsFalse(Parse('https://gitlab.com/foo/bar', R));
  Assert.IsFalse(Parse('gitlab.com/foo/bar', R));
  Assert.IsFalse(Parse('ssh://git@example.org/foo/bar.git', R));
  Assert.IsFalse(Parse('git@gitlab.com:foo/bar.git', R));
end;

procedure TGitHubTests.RejectsIncompleteAddresses;
var
  R: TRepoRef;
begin
  Assert.IsFalse(Parse('', R));
  Assert.IsFalse(Parse('   ', R));
  Assert.IsFalse(Parse('https://github.com/', R));
  Assert.IsFalse(Parse('https://github.com/foo', R));
  Assert.IsFalse(Parse('foo', R));
end;

procedure TGitHubTests.RejectsDangerousNames;
var
  R: TRepoRef;
begin
  Assert.IsFalse(Parse('https://github.com/foo/ba r', R));
  Assert.IsFalse(Parse('https://github.com/foo/bar&calc', R));
  Assert.IsFalse(Parse('https://github.com/foo/"bar', R));
  Assert.IsFalse(Parse('https://github.com/-foo/bar', R));
  Assert.IsFalse(Parse('https://github.com/foo/..', R));
  Assert.IsFalse(Parse('https://github.com/../bar', R));
end;

procedure TGitHubTests.RejectsDangerousBranches;
var
  R: TRepoRef;
begin
  Assert.IsFalse(Parse('https://github.com/foo/bar#--upload-pack=calc', R));
  Assert.IsFalse(Parse('https://github.com/foo/bar#a b', R));
  Assert.IsFalse(Parse('https://github.com/foo/bar#a..b', R));
  Assert.IsFalse(Parse('https://github.com/foo/bar#x"y', R));
end;

procedure TGitHubTests.DropsSubFolderThatEscapesTheRepository;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/foo/bar/tree/main/../../etc', R));
  Assert.AreEqual('', R.SubPath);
end;

procedure TGitHubTests.CloneUrlIsAlwaysBuiltFromValidatedParts;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/foo/bar.git', R));
  Assert.IsTrue(R.CloneUrl.StartsWith('https://github.com/'));
  Assert.IsTrue(R.CloneUrl.EndsWith('.git'));
  Assert.IsFalse(R.CloneUrl.Contains(' '));
end;

procedure TGitHubTests.CacheDirsLiveUnderTheDataFolder;
var
  R: TRepoRef;
begin
  Assert.IsTrue(Parse('https://github.com/foo/bar/tree/main/src', R));
  Assert.AreEqual(TPath.Combine(TPath.Combine(FDataDir, 'repos'), 'abc123'), RepoCacheDir('abc123'));
  Assert.AreEqual(TPath.Combine(RepoCacheDir('abc123'), 'src'), RepoWorkDir('abc123', R));
end;

procedure TGitHubTests.DeleteRepoCacheOnlyTouchesItsOwnFolder;
var
  Mine, Other, Outside, Head: string;
begin
  Mine := RepoCacheDir('proj1');
  Other := RepoCacheDir('proj2');
  Outside := TPath.Combine(FDataDir, 'importante');
  TDirectory.CreateDirectory(TPath.Combine(Mine, '.git'));
  TDirectory.CreateDirectory(Other);
  TDirectory.CreateDirectory(Outside);
  Head := TPath.Combine(TPath.Combine(Mine, '.git'), 'HEAD');
  TFile.WriteAllText(Head, 'x');
  FileSetAttr(Head, faReadOnly);   // como os ficheiros do .git no Windows
  DeleteRepoCache('proj1');
  Assert.IsFalse(TDirectory.Exists(Mine), 'apaga a cache do projeto, mesmo com ficheiros so de leitura');
  Assert.IsTrue(TDirectory.Exists(Other));
  // ids que tentam sair da pasta das caches nao fazem nada
  DeleteRepoCache('..\importante');
  DeleteRepoCache('');
  DeleteRepoCache('a/b');
  Assert.IsTrue(TDirectory.Exists(Outside));
end;

initialization
  TDUnitX.RegisterTestFixture(TGitHubTests);

end.
