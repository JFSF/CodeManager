unit Tests.Sonar;

// Testes da integracao opcional com o SonarQube: modelo e associacao de caminhos (CM.SonarModel), analisadores
// das respostas da API (CM.Sonar), cifra do token (CM.Secrets) e as definicoes por utilizador (CM.Store).
// Nenhum teste precisa de um servidor Sonar: as respostas sao textos de exemplo.

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, DUnitX.TestFramework, CM.Analyzer, CM.Store, CM.SonarModel, CM.Sonar,
  CM.Secrets, Tests.Helpers;

type
  [TestFixture]
  TSonarModelTests = class
  private
    FSnap: TSonarSnapshot;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure IssuesAccumulatePerFileAndKeepTheWorstSeverity;
    [Test] procedure FileWithoutIssuesIsStillKnown;
    [Test] procedure FindMatchesTheExactPath;
    [Test] procedure FindIgnoresCaseAndBackslashes;
    [Test] procedure FindMatchesWhenSonarPathIsLongerThanTheUnitPath;
    [Test] procedure FindMatchesWhenTheUnitPathIsLongerThanTheSonarPath;
    [Test] procedure FindPrefersTheLongestMatch;
    [Test] procedure FindDoesNotMatchPartialNames;
    [Test] procedure FindSeesFilesAddedAfterAFailedLookup;
    [Test] procedure SeverityParsingAndText;
    [Test] procedure SyncMarksCleanFilesAndClearsFilesWithIssues;
    [Test] procedure SyncLeavesUnknownFilesAlone;
    [Test] procedure SyncCreatesNoRecordsWhenNothingChanges;
    [Test] procedure SyncWithoutSnapshotDoesNothing;
  end;

  [TestFixture]
  TSonarClientTests = class
  public
    [Test] procedure NormalizeUrlAddsSchemeAndTrimsSlashes;
    [Test] procedure GateStatusIsReadAndUpperCased;
    [Test] procedure GateStatusOfGarbageIsEmpty;
    [Test] procedure IssuesPageAddsIssuesAndStripsTheProjectKey;
    [Test] procedure IssuesPageSkipsProjectLevelIssues;
    [Test] procedure IssuesPageFallsBackToImpacts;
    [Test] procedure IssuesPageOfGarbageAddsNothing;
    [Test] procedure MeasuresPageAddsFilesWithLines;
    [Test] procedure MeasuresPageWithoutNclocKeepsZeroLines;
    [Test] procedure ConnectionFailureHasAClearMessage;
    [Test] procedure MissingUrlIsReported;
    [Test] procedure MissingPiecesAreNamed;
    [Test] procedure BackgroundTestReportsTheFailureWithoutBlocking;
    [Test] procedure BackgroundFetchFailsCleanlyAndGivesNoSnapshot;
    [Test] procedure DroppingAJobBeforeItFinishesIsSafe;
  end;

  [TestFixture]
  TSecretsTests = class
  public
    [Test] procedure ProtectedTextRoundTrips;
    [Test] procedure ProtectedTextIsNotThePlainText;
    [Test] procedure EmptyStaysEmpty;
    [Test] procedure GarbageOrForeignTextGivesEmpty;
    [Test] procedure UnicodeSurvives;
  end;

  [TestFixture]
  TSonarSettingsTests = class
  public
    [Test] procedure DefaultsAreOff;
    [Test] procedure SettingsRoundTrip;
    [Test] procedure NothingIsWrittenWhenUnused;
    [Test] procedure ProjectKeyRoundTripsPerProject;
    [Test] procedure PlainTokenIsNeverWrittenByTheStore;
  end;

implementation

{ TSonarModelTests }

procedure TSonarModelTests.Setup;
begin
  FSnap := TSonarSnapshot.Create;
end;

procedure TSonarModelTests.TearDown;
begin
  FSnap.Free;
end;

procedure TSonarModelTests.IssuesAccumulatePerFileAndKeepTheWorstSeverity;
var
  F: TSonarFile;
begin
  FSnap.AddIssue('src/a.pas', ssMinor);
  FSnap.AddIssue('src/a.pas', ssCritical);
  FSnap.AddIssue('src/a.pas', ssMajor);
  Assert.IsTrue(FSnap.Find('src/a.pas', F));
  Assert.AreEqual(3, F.Issues);
  Assert.AreEqual(Ord(ssCritical), Ord(F.Worst));
  Assert.AreEqual(3, FSnap.TotalIssues);
end;

procedure TSonarModelTests.FileWithoutIssuesIsStillKnown;
var
  F: TSonarFile;
begin
  FSnap.AddFile('src/a.pas', 120);
  Assert.IsTrue(FSnap.Find('src/a.pas', F));
  Assert.AreEqual(0, F.Issues);
  Assert.AreEqual(120, F.Lines);
  Assert.AreEqual(1, FSnap.FileCount);
end;

procedure TSonarModelTests.FindMatchesTheExactPath;
var
  F: TSonarFile;
begin
  FSnap.AddFile('src/Core/a.pas', 10);
  Assert.IsTrue(FSnap.Find('src/Core/a.pas', F));
  Assert.AreEqual('src/Core/a.pas', F.Path);
end;

procedure TSonarModelTests.FindIgnoresCaseAndBackslashes;
var
  F: TSonarFile;
begin
  FSnap.AddFile('src/Core/A.pas', 10);
  Assert.IsTrue(FSnap.Find('SRC\core\a.PAS', F));
end;

procedure TSonarModelTests.FindMatchesWhenSonarPathIsLongerThanTheUnitPath;
var
  F: TSonarFile;
begin
  FSnap.AddFile('src/Core/a.pas', 10);      // o Sonar analisa a raiz do repositorio
  Assert.IsTrue(FSnap.Find('Core/a.pas', F), 'o CodeManager analisa so a pasta "src"');
end;

procedure TSonarModelTests.FindMatchesWhenTheUnitPathIsLongerThanTheSonarPath;
var
  F: TSonarFile;
begin
  FSnap.AddFile('Core/a.pas', 10);          // o Sonar analisa a pasta "src"
  Assert.IsTrue(FSnap.Find('src/Core/a.pas', F), 'o CodeManager analisa a raiz do repositorio');
end;

procedure TSonarModelTests.FindPrefersTheLongestMatch;
var
  F: TSonarFile;
begin
  FSnap.AddFile('a.pas', 1);
  FSnap.AddFile('lib/a.pas', 2);
  Assert.IsTrue(FSnap.Find('app/lib/a.pas', F));
  Assert.AreEqual(2, F.Lines, 'lib/a.pas e mais especifico que a.pas');
end;

procedure TSonarModelTests.FindDoesNotMatchPartialNames;
var
  F: TSonarFile;
begin
  FSnap.AddFile('src/MyCore/a.pas', 10);
  Assert.IsFalse(FSnap.Find('Core/a.pas', F), '"MyCore" nao e "Core"');
  Assert.IsFalse(FSnap.Find('Core/b.pas', F));
end;

procedure TSonarModelTests.FindSeesFilesAddedAfterAFailedLookup;
var
  F: TSonarFile;
begin
  Assert.IsFalse(FSnap.Find('a.pas', F));
  FSnap.AddFile('a.pas', 5);
  Assert.IsTrue(FSnap.Find('a.pas', F), 'a falha nao pode ficar em cache');
end;

procedure TSonarModelTests.SeverityParsingAndText;
begin
  Assert.AreEqual(Ord(ssBlocker), Ord(SeverityFromText('BLOCKER')));
  Assert.AreEqual(Ord(ssCritical), Ord(SeverityFromText('critical')));
  Assert.AreEqual(Ord(ssMajor), Ord(SeverityFromText('MAJOR')));
  Assert.AreEqual(Ord(ssMinor), Ord(SeverityFromText('MINOR')));
  Assert.AreEqual(Ord(ssInfo), Ord(SeverityFromText('')));
  Assert.AreEqual(Ord(ssInfo), Ord(SeverityFromText('whatever')));
  Assert.AreEqual('crítica', SeverityText(ssCritical));
  Assert.AreEqual('bloqueante', SeverityText(ssBlocker));
end;

procedure TSonarModelTests.SyncMarksCleanFilesAndClearsFilesWithIssues;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TSonarSync;
begin
  Scan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', []), MakeUnitInfo('b.pas', 'Raiz', []),
    MakeUnitInfo('c.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    FSnap.AddFile('a.pas', 10);              // limpo, ainda sem "S"
    FSnap.AddIssue('b.pas', ssMajor);        // com problemas, tem "S" marcado a mao
    FSnap.AddFile('c.pas', 5);               // limpo, ja tem "S"
    St.Rec('b.pas').Sonar := True;
    St.Rec('c.pas').Sonar := True;
    R := SyncSonarFlags(Scan, St, FSnap);
    Assert.AreEqual(1, R.Marked);
    Assert.AreEqual(1, R.Cleared);
    Assert.IsTrue(St.Find('a.pas').Sonar);
    Assert.IsFalse(St.Find('b.pas').Sonar);
    Assert.IsTrue(St.Find('c.pas').Sonar);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TSonarModelTests.SyncLeavesUnknownFilesAlone;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TSonarSync;
begin
  Scan := NewScan(1, [MakeUnitInfo('x.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    St.Rec('x.pas').Sonar := True;           // marcado a mao e o Sonar nao conhece o ficheiro
    R := SyncSonarFlags(Scan, St, FSnap);
    Assert.AreEqual(0, R.Marked + R.Cleared);
    Assert.IsTrue(St.Find('x.pas').Sonar);
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TSonarModelTests.SyncCreatesNoRecordsWhenNothingChanges;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TSonarSync;
begin
  Scan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    FSnap.AddIssue('a.pas', ssMinor);        // com problemas e sem "S": nada a tirar
    R := SyncSonarFlags(Scan, St, FSnap);
    Assert.AreEqual(0, R.Marked + R.Cleared);
    Assert.IsNull(St.Find('a.pas'), 'nao cria registos a toa');
  finally
    St.Free;
    Scan.Free;
  end;
end;

procedure TSonarModelTests.SyncWithoutSnapshotDoesNothing;
var
  Scan: TProjectScan;
  St: TProgressState;
  R: TSonarSync;
begin
  Scan := NewScan(1, [MakeUnitInfo('a.pas', 'Raiz', [])]);
  St := TProgressState.Create;
  try
    R := SyncSonarFlags(Scan, St, nil);
    Assert.AreEqual(0, R.Marked + R.Cleared);
  finally
    St.Free;
    Scan.Free;
  end;
end;

{ TSonarClientTests }

procedure TSonarClientTests.NormalizeUrlAddsSchemeAndTrimsSlashes;
begin
  Assert.AreEqual('', NormalizeSonarUrl(''));
  Assert.AreEqual('', NormalizeSonarUrl('   '));
  Assert.AreEqual('http://localhost:5000', NormalizeSonarUrl('localhost:5000'));
  Assert.AreEqual('http://localhost:5000', NormalizeSonarUrl(' http://localhost:5000/ '));
  Assert.AreEqual('https://sonar.exemplo.pt', NormalizeSonarUrl('https://sonar.exemplo.pt//'));
  Assert.AreEqual('HTTP://X', NormalizeSonarUrl('HTTP://X'), 'o esquema ja la esta (maiusculas incluidas)');
end;

procedure TSonarClientTests.GateStatusIsReadAndUpperCased;
begin
  Assert.AreEqual('OK', ParseGateStatus('{"projectStatus":{"status":"OK","conditions":[]}}'));
  Assert.AreEqual('ERROR', ParseGateStatus('{"projectStatus":{"status":"error"}}'));
  Assert.AreEqual('NONE', ParseGateStatus('{"projectStatus":{"status":"NONE"}}'));
end;

procedure TSonarClientTests.GateStatusOfGarbageIsEmpty;
begin
  Assert.AreEqual('', ParseGateStatus(''));
  Assert.AreEqual('', ParseGateStatus('nao e json'));
  Assert.AreEqual('', ParseGateStatus('{"outro":1}'));
  Assert.AreEqual('', ParseGateStatus('[1,2]'));
end;

procedure TSonarClientTests.IssuesPageAddsIssuesAndStripsTheProjectKey;
var
  Snap: TSonarSnapshot;
  F: TSonarFile;
  Total, N: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    N := ParseIssuesPage(
      '{"paging":{"pageIndex":1,"pageSize":500,"total":3},"issues":[' +
      '{"component":"CodeManager:src/Core/a.pas","severity":"MAJOR"},' +
      '{"component":"CodeManager:src/Core/a.pas","severity":"BLOCKER"},' +
      '{"component":"CodeManager:src/UI/b.pas","severity":"MINOR"}]}',
      'CodeManager', Snap, Total);
    Assert.AreEqual(3, N);
    Assert.AreEqual(3, Total);
    Assert.IsTrue(Snap.Find('src/Core/a.pas', F));
    Assert.AreEqual(2, F.Issues);
    Assert.AreEqual(Ord(ssBlocker), Ord(F.Worst));
    Assert.IsTrue(Snap.Find('src/UI/b.pas', F));
    Assert.AreEqual(Ord(ssMinor), Ord(F.Worst));
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.IssuesPageSkipsProjectLevelIssues;
var
  Snap: TSonarSnapshot;
  Total: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    Assert.AreEqual(0, ParseIssuesPage('{"paging":{"total":1},"issues":[{"component":"CodeManager","severity":"MAJOR"}]}',
      'CodeManager', Snap, Total));
    Assert.AreEqual(0, Snap.FileCount);
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.IssuesPageFallsBackToImpacts;
var
  Snap: TSonarSnapshot;
  F: TSonarFile;
  Total: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    ParseIssuesPage('{"paging":{"total":1},"issues":[{"component":"K:a.pas","impacts":[{"softwareQuality":"RELIABILITY","severity":"HIGH"}]}]}',
      'K', Snap, Total);
    Assert.IsTrue(Snap.Find('a.pas', F));
    Assert.AreEqual(Ord(ssCritical), Ord(F.Worst), 'HIGH conta como critica');
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.IssuesPageOfGarbageAddsNothing;
var
  Snap: TSonarSnapshot;
  Total: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    Assert.AreEqual(0, ParseIssuesPage('', 'K', Snap, Total));
    Assert.AreEqual(0, ParseIssuesPage('{"errors":[{"msg":"x"}]}', 'K', Snap, Total));
    Assert.AreEqual(0, Total);
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.MeasuresPageAddsFilesWithLines;
var
  Snap: TSonarSnapshot;
  F: TSonarFile;
  Total, N: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    N := ParseMeasuresPage(
      '{"paging":{"total":2},"components":[' +
      '{"key":"K:src/a.pas","path":"src/a.pas","qualifier":"FIL","measures":[{"metric":"ncloc","value":"120"}]},' +
      '{"key":"K:src/b.pas","path":"src/b.pas","qualifier":"FIL","measures":[{"metric":"ncloc","value":"7"}]}]}',
      Snap, Total);
    Assert.AreEqual(2, N);
    Assert.AreEqual(2, Total);
    Assert.IsTrue(Snap.Find('src/a.pas', F));
    Assert.AreEqual(120, F.Lines);
    Assert.AreEqual(0, F.Issues);
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.MeasuresPageWithoutNclocKeepsZeroLines;
var
  Snap: TSonarSnapshot;
  F: TSonarFile;
  Total: Integer;
begin
  Snap := TSonarSnapshot.Create;
  try
    ParseMeasuresPage('{"paging":{"total":1},"components":[{"path":"a.pas","measures":[]}]}', Snap, Total);
    Assert.IsTrue(Snap.Find('a.pas', F));
    Assert.AreEqual(0, F.Lines);
  finally
    Snap.Free;
  end;
end;

procedure TSonarClientTests.ConnectionFailureHasAClearMessage;
var
  C: TSonarConfig;
  Msg: string;
begin
  C.Url := 'http://127.0.0.1:1';             // nada a ouvir
  C.Token := '';
  C.ProjectKey := 'x';
  Assert.IsFalse(SonarTest(C, Msg));
  Assert.IsTrue(Msg.StartsWith('Não foi possível ligar a http://127.0.0.1:1'), Msg);
end;

procedure TSonarClientTests.MissingUrlIsReported;
var
  C: TSonarConfig;
  Msg: string;
begin
  C := Default(TSonarConfig);
  Assert.IsFalse(SonarTest(C, Msg));
  Assert.AreEqual('Indica o endereço do servidor.', Msg);
end;

function Wait(const AJob: ISonarJob; ATimeoutMs: Integer): Boolean;
var
  T: UInt64;
begin
  T := TThread.GetTickCount64;
  while not AJob.Done and (TThread.GetTickCount64 - T < UInt64(ATimeoutMs)) do
    Sleep(10);
  Result := AJob.Done;
end;

procedure TSonarClientTests.MissingPiecesAreNamed;
var
  C: TSonarConfig;
begin
  C := Default(TSonarConfig);
  Assert.AreEqual('Indica o endereço do servidor.', SonarMissing(C));
  C.Url := 'localhost:5000';
  Assert.AreEqual('Indica a chave do projeto no SonarQube.', SonarMissing(C));
  C.ProjectKey := 'X';
  Assert.AreEqual('', SonarMissing(C));
end;

procedure TSonarClientTests.BackgroundTestReportsTheFailureWithoutBlocking;
var
  C: TSonarConfig;
  Job: ISonarJob;
begin
  C.Url := 'http://127.0.0.1:1';
  C.ProjectKey := 'x';
  C.Token := '';
  Job := StartSonarTest(C);
  Assert.IsTrue(Wait(Job, 15000), 'devia terminar');
  Assert.IsFalse(Job.Success);
  Assert.IsTrue(Job.Message.StartsWith('Não foi possível ligar'), Job.Message);
  Assert.IsNull(Job.TakeSnapshot);
end;

procedure TSonarClientTests.BackgroundFetchFailsCleanlyAndGivesNoSnapshot;
var
  C: TSonarConfig;
  Job: ISonarJob;
begin
  C.Url := 'http://127.0.0.1:1';
  C.ProjectKey := 'x';
  C.Token := '';
  Job := StartSonarFetch(C);
  Assert.IsTrue(Wait(Job, 15000));
  Assert.IsFalse(Job.Success);
  Assert.IsNull(Job.TakeSnapshot, 'numa falha nao ha snapshot');
  Assert.IsTrue(Job.Message <> '');
end;

procedure TSonarClientTests.DroppingAJobBeforeItFinishesIsSafe;
var
  C: TSonarConfig;
  Job: ISonarJob;
begin
  C.Url := 'http://127.0.0.1:1';
  C.ProjectKey := 'x';
  C.Token := '';
  Job := StartSonarTest(C);
  Job := nil;                    // a janela fechou: a thread acaba sozinha, sem tocar em memoria libertada
  Sleep(1500);
  Assert.Pass;
end;

{ TSecretsTests }

procedure TSecretsTests.ProtectedTextRoundTrips;
begin
  Assert.AreEqual('squ_0123456789abcdef', UnprotectText(ProtectText('squ_0123456789abcdef')));
end;

procedure TSecretsTests.ProtectedTextIsNotThePlainText;
var
  C: string;
begin
  C := ProtectText('squ_segredo');
  Assert.IsTrue(C.StartsWith('dpapi:'));
  Assert.IsFalse(C.Contains('segredo'), 'o token nao pode aparecer em claro');
end;

procedure TSecretsTests.EmptyStaysEmpty;
begin
  Assert.AreEqual('', ProtectText(''));
  Assert.AreEqual('', UnprotectText(''));
end;

procedure TSecretsTests.GarbageOrForeignTextGivesEmpty;
begin
  Assert.AreEqual('', UnprotectText('squ_em_claro'), 'sem o prefixo nao e nosso');
  Assert.AreEqual('', UnprotectText('dpapi:isto-nao-e-base64!!'));
  Assert.AreEqual('', UnprotectText('dpapi:AAAA'), 'base64 valido mas nao e um bloco DPAPI');
end;

procedure TSecretsTests.UnicodeSurvives;
begin
  Assert.AreEqual('chave-ção-ñ-日本', UnprotectText(ProtectText('chave-ção-ñ-日本')));
end;

{ TSonarSettingsTests }

procedure TSonarSettingsTests.DefaultsAreOff;
var
  S: TAppSettings;
  Data: TIsolatedAppData;
begin
  Data := TIsolatedAppData.Create;
  S := TAppSettings.Create;
  try
    S.Load;
    Assert.IsFalse(S.SonarEnabled);
    Assert.AreEqual('', S.SonarUrl);
    Assert.AreEqual('', S.SonarTokenCipher);
  finally
    S.Free;
    Data.Free;
  end;
end;

procedure TSonarSettingsTests.SettingsRoundTrip;
var
  Saved, Loaded: TAppSettings;
  Data: TIsolatedAppData;
begin
  Data := TIsolatedAppData.Create;
  Saved := TAppSettings.Create;
  Loaded := TAppSettings.Create;
  try
    Saved.SonarEnabled := True;
    Saved.SonarUrl := 'http://localhost:5000';
    Saved.SonarTokenCipher := 'dpapi:ABCD';
    Saved.Save;
    Loaded.Load;
    Assert.IsTrue(Loaded.SonarEnabled);
    Assert.AreEqual('http://localhost:5000', Loaded.SonarUrl);
    Assert.AreEqual('dpapi:ABCD', Loaded.SonarTokenCipher);
  finally
    Loaded.Free;
    Saved.Free;
    Data.Free;
  end;
end;

procedure TSonarSettingsTests.NothingIsWrittenWhenUnused;
var
  S: TAppSettings;
  Data: TIsolatedAppData;
  Text: string;
begin
  Data := TIsolatedAppData.Create;
  S := TAppSettings.Create;
  try
    S.Save;
    Text := TFile.ReadAllText(TPath.Combine(AppDataDir, 'settings.json'), TEncoding.UTF8);
    Assert.IsFalse(Text.Contains('sonar'), 'quem nao usa o Sonar nao ganha campos novos');
  finally
    S.Free;
    Data.Free;
  end;
end;

procedure TSonarSettingsTests.ProjectKeyRoundTripsPerProject;
var
  Saved, Loaded: TAppSettings;
  Data: TIsolatedAppData;
begin
  Data := TIsolatedAppData.Create;
  Saved := TAppSettings.Create;
  Loaded := TAppSettings.Create;
  try
    Saved.AddProject.SonarKey := 'MeuProjeto';
    Saved.AddProject;                            // este nao usa o Sonar
    Saved.Save;
    Loaded.Load;
    Assert.AreEqual<NativeInt>(2, Loaded.Projects.Count);
    Assert.AreEqual('MeuProjeto', Loaded.Projects[0].SonarKey);
    Assert.AreEqual('', Loaded.Projects[1].SonarKey);
  finally
    Loaded.Free;
    Saved.Free;
    Data.Free;
  end;
end;

procedure TSonarSettingsTests.PlainTokenIsNeverWrittenByTheStore;
var
  S: TAppSettings;
  Data: TIsolatedAppData;
  Text: string;
begin
  Data := TIsolatedAppData.Create;
  S := TAppSettings.Create;
  try
    S.SonarEnabled := True;
    S.SonarTokenCipher := ProtectText('squ_token_secreto');
    S.Save;
    Text := TFile.ReadAllText(TPath.Combine(AppDataDir, 'settings.json'), TEncoding.UTF8);
    Assert.IsFalse(Text.Contains('squ_token_secreto'));
    Assert.IsTrue(Text.Contains('dpapi:'));
  finally
    S.Free;
    Data.Free;
  end;
end;

end.
