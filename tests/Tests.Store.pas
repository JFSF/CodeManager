unit Tests.Store;

// Testes de CM.Store: TProjectProfile (id gerado), TAppSettings (persistencia de settings.json
// e dos perfis de projecto), TUnitState.IsEmpty e TProgressState (o JSON de progresso, compativel
// com o das paginas HTML exportadas). AppDataDir e isolada numa pasta temporaria por teste
// (Tests.Helpers.TIsolatedAppData), nunca tocando na pasta real do utilizador.

interface

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions, System.DateUtils,
  DUnitX.TestFramework, CM.Store, Tests.Helpers;

type
  [TestFixture]
  TProjectProfileTests = class
  public
    [Test] procedure NewIdIsLowerHex32Chars;
    [Test] procedure NewIdsAreUnique;
  end;

  [TestFixture]
  TAppDataTests = class
  private
    FIso: TIsolatedAppData;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure AppDataDirUsesTheOverrideAndCreatesIt;
    [Test] procedure ProgressFileForBuildsExpectedName;
    [Test] procedure NowMillisIsCloseToTheCurrentTime;
  end;

  [TestFixture]
  TAppSettingsTests = class
  private
    FIso: TIsolatedAppData;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure AddProjectGeneratesAUniqueId;
    [Test] procedure FindProjectByIdReturnsNilWhenMissing;
    [Test] procedure FindProjectByIdReturnsTheProfile;
    [Test] procedure RemoveProjectDeletesItsProgressFile;
    [Test] procedure RemoveProjectWithoutProgressFileDoesNotRaise;
    [Test] procedure LoadWithoutAFileLeavesDefaults;
    [Test] procedure SaveThenLoadRoundTripsSettingsAndProjects;
    [Test] procedure LoadIgnoresANonObjectFile;
    [Test] procedure LoadSkipsNonObjectProjectEntries;
    [Test] procedure LoadDefaultsMissingBooleanFields;
    [Test] procedure LoadReplacesThePreviousProjectList;
    [Test] procedure LoadWithoutAFileDoesNotTouchInMemoryProjects;
  end;

  [TestFixture]
  TUnitStateTests = class
  public
    [Test] procedure NewStateIsEmpty;
    [Test] procedure DoneMakesItNonEmpty;
    [Test] procedure StarMakesItNonEmpty;
    [Test] procedure CompilaMakesItNonEmpty;
    [Test] procedure SonarMakesItNonEmpty;
    [Test] procedure NoteMakesItNonEmpty;
    [Test] procedure MDoneMakesItNonEmpty;
    [Test] procedure MCompilaMakesItNonEmpty;
    [Test] procedure MSonarMakesItNonEmpty;
  end;

  [TestFixture]
  TProgressStateTests = class
  public
    [Test] procedure FindReturnsNilForUnknownPath;
    [Test] procedure RecCreatesThenReusesTheSameInstance;
    [Test] procedure ClearRemovesEverything;
    [Test] procedure EmptyRecordsAreOmittedFromJson;
    [Test] procedure ToJSONStringRoundTripsAllFields;
    [Test] procedure LoadAcceptsThePlainFormat;
    [Test] procedure LoadAcceptsTheWrappedExportedFormat;
    [Test] procedure LoadDefaultsMissingBooleans;
    [Test] procedure LoadIgnoresNonObjectEntries;
    [Test] procedure LoadReplacesThePreviousState;
    [Test] procedure LoadRaisesOnInvalidJson;
    [Test] procedure LoadRaisesWhenRootIsAnArray;
    [Test] procedure TimestampRoundTripsExactly;
    [Test] procedure TimestampAloneDoesNotSurviveARoundTrip;
    [Test] procedure MethodSetsWithSpecialCharactersRoundTrip;
    [Test] procedure FalseFlagsInASetAreNotAdded;
    [Test] procedure NonBooleanValuesInASetAreIgnored;
    [Test] procedure SaveToFileThenLoadFromFileRoundTrips;
  end;

implementation

{ TProjectProfileTests }

procedure TProjectProfileTests.NewIdIsLowerHex32Chars;
var
  P: TProjectProfile;
begin
  P := TProjectProfile.Create;
  try
    Assert.IsTrue(TRegEx.IsMatch(P.Id, '^[0-9a-f]{32}$'), P.Id);
  finally
    P.Free;
  end;
end;

procedure TProjectProfileTests.NewIdsAreUnique;
var
  A, B: TProjectProfile;
begin
  A := TProjectProfile.Create;
  B := TProjectProfile.Create;
  try
    Assert.AreNotEqual(A.Id, B.Id);
  finally
    A.Free;
    B.Free;
  end;
end;

{ TAppDataTests }

procedure TAppDataTests.Setup;
begin
  FIso := TIsolatedAppData.Create;
end;

procedure TAppDataTests.TearDown;
begin
  FIso.Free;
end;

procedure TAppDataTests.AppDataDirUsesTheOverrideAndCreatesIt;
begin
  Assert.AreEqual(FIso.Path, AppDataDir);
  Assert.IsTrue(TDirectory.Exists(AppDataDir));
end;

procedure TAppDataTests.ProgressFileForBuildsExpectedName;
begin
  Assert.AreEqual(TPath.Combine(FIso.Path, 'progress-abc123.json'), ProgressFileFor('abc123'));
end;

procedure TAppDataTests.NowMillisIsCloseToTheCurrentTime;
var
  Before, After, Now1: Int64;
begin
  Before := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(System.SysUtils.Now), True) * 1000;
  Now1 := NowMillis;
  After := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(System.SysUtils.Now), True) * 1000;
  Assert.IsTrue((Now1 >= Before - 1000) and (Now1 <= After + 1000), 'NowMillis deve rondar a hora actual');
end;

{ TAppSettingsTests }

procedure TAppSettingsTests.Setup;
begin
  FIso := TIsolatedAppData.Create;
end;

procedure TAppSettingsTests.TearDown;
begin
  FIso.Free;
end;

procedure TAppSettingsTests.AddProjectGeneratesAUniqueId;
var
  S: TAppSettings;
  P: TProjectProfile;
begin
  S := TAppSettings.Create;
  try
    P := S.AddProject;
    Assert.AreEqual<NativeInt>(1, S.Projects.Count);
    Assert.AreEqual(P, S.Projects[0]);
    Assert.IsTrue(P.Id <> '');
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.FindProjectByIdReturnsNilWhenMissing;
var
  S: TAppSettings;
begin
  S := TAppSettings.Create;
  try
    Assert.IsNull(S.FindProject('nao-existe'));
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.FindProjectByIdReturnsTheProfile;
var
  S: TAppSettings;
  P: TProjectProfile;
begin
  S := TAppSettings.Create;
  try
    P := S.AddProject;
    Assert.AreEqual(P, S.FindProject(P.Id));
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.RemoveProjectDeletesItsProgressFile;
var
  S: TAppSettings;
  P: TProjectProfile;
  F: string;
begin
  S := TAppSettings.Create;
  try
    P := S.AddProject;
    F := ProgressFileFor(P.Id);
    TFile.WriteAllText(F, '{}');
    Assert.IsTrue(TFile.Exists(F));
    S.RemoveProject(P);
    Assert.IsFalse(TFile.Exists(F));
    Assert.AreEqual<NativeInt>(0, S.Projects.Count);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.RemoveProjectWithoutProgressFileDoesNotRaise;
var
  S: TAppSettings;
  P: TProjectProfile;
begin
  S := TAppSettings.Create;
  try
    P := S.AddProject;
    S.RemoveProject(P);
    Assert.AreEqual<NativeInt>(0, S.Projects.Count);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.LoadWithoutAFileLeavesDefaults;
var
  S: TAppSettings;
begin
  S := TAppSettings.Create;
  try
    S.Load;
    Assert.AreEqual('', S.Theme);
    Assert.AreEqual('', S.ActiveProjectId);
    Assert.IsTrue(S.OpenAfterExport);
    Assert.AreEqual<NativeInt>(0, S.Projects.Count);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.SaveThenLoadRoundTripsSettingsAndProjects;
var
  Saved, Loaded: TAppSettings;
  P: TProjectProfile;
begin
  Saved := TAppSettings.Create;
  try
    Saved.Theme := 'dark';
    Saved.ActiveProjectId := 'xyz';
    Saved.OpenAfterExport := False;
    P := Saved.AddProject;
    P.Name := 'Meu Projeto';
    P.RootPath := 'C:\Proj';
    P.OutputFolder := 'C:\Proj\out';
    P.ExcludeDirs := 'bin, obj';
    P.Watch := True;
    P.Finalized := True;
    P.FinalizedAt := '2026-01-02T03:04:05';
    Saved.Save;
  finally
    Saved.Free;
  end;

  Loaded := TAppSettings.Create;
  try
    Loaded.Load;
    Assert.AreEqual('dark', Loaded.Theme);
    Assert.AreEqual('xyz', Loaded.ActiveProjectId);
    Assert.IsFalse(Loaded.OpenAfterExport);
    Assert.AreEqual<NativeInt>(1, Loaded.Projects.Count);
    Assert.AreEqual(P.Id, Loaded.Projects[0].Id);
    Assert.AreEqual('Meu Projeto', Loaded.Projects[0].Name);
    Assert.AreEqual('C:\Proj', Loaded.Projects[0].RootPath);
    Assert.AreEqual('C:\Proj\out', Loaded.Projects[0].OutputFolder);
    Assert.AreEqual('bin, obj', Loaded.Projects[0].ExcludeDirs);
    Assert.IsTrue(Loaded.Projects[0].Watch);
    Assert.IsTrue(Loaded.Projects[0].Finalized);
    Assert.AreEqual('2026-01-02T03:04:05', Loaded.Projects[0].FinalizedAt);
  finally
    Loaded.Free;
  end;
end;

procedure TAppSettingsTests.LoadIgnoresANonObjectFile;
var
  S: TAppSettings;
begin
  TFile.WriteAllText(TPath.Combine(FIso.Path, 'settings.json'), '[1, 2, 3]');
  S := TAppSettings.Create;
  try
    S.Load;   // nao pode levantar excepcao; fica com os valores por omissao
    Assert.AreEqual('', S.Theme);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.LoadSkipsNonObjectProjectEntries;
var
  S: TAppSettings;
begin
  TFile.WriteAllText(TPath.Combine(FIso.Path, 'settings.json'),
    '{"projects": [123, {"id": "aaa", "name": "Real"}, "texto"]}');
  S := TAppSettings.Create;
  try
    S.Load;
    Assert.AreEqual<NativeInt>(1, S.Projects.Count);
    Assert.AreEqual('Real', S.Projects[0].Name);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.LoadDefaultsMissingBooleanFields;
var
  S: TAppSettings;
begin
  TFile.WriteAllText(TPath.Combine(FIso.Path, 'settings.json'),
    '{"projects": [{"id": "aaa"}]}');
  S := TAppSettings.Create;
  try
    S.Load;
    Assert.IsTrue(S.OpenAfterExport, 'omitido no ficheiro: mantem-se True');
    Assert.IsFalse(S.Projects[0].Watch);
    Assert.IsFalse(S.Projects[0].Finalized);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.LoadReplacesThePreviousProjectList;
var
  Base, S: TAppSettings;
begin
  // ficheiro em disco com 1 projecto
  Base := TAppSettings.Create;
  try
    Base.AddProject;
    Base.Save;
  finally
    Base.Free;
  end;

  S := TAppSettings.Create;
  try
    S.AddProject;
    S.AddProject;
    Assert.AreEqual<NativeInt>(2, S.Projects.Count);
    S.Load;   // o ficheiro tem 1 projecto: substitui a lista em memoria, nao a soma
    Assert.AreEqual<NativeInt>(1, S.Projects.Count);
  finally
    S.Free;
  end;
end;

procedure TAppSettingsTests.LoadWithoutAFileDoesNotTouchInMemoryProjects;
var
  S: TAppSettings;
begin
  // Load() sai logo se settings.json nao existir - nao chega a limpar FProjects.
  // Documenta este comportamento (util quando se chama Load antes de qualquer Save).
  S := TAppSettings.Create;
  try
    S.AddProject;
    S.Load;
    Assert.AreEqual<NativeInt>(1, S.Projects.Count);
  finally
    S.Free;
  end;
end;

{ TUnitStateTests }

procedure TUnitStateTests.NewStateIsEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    Assert.IsTrue(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.DoneMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.Done := True;
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.StarMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.Star := True;
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.CompilaMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.Compila := True;
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.SonarMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.Sonar := True;
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.NoteMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.Note := 'x';
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.MDoneMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.MDone.Add('TFoo.Bar');
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.MCompilaMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.MCompila.Add('TFoo.Bar');
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

procedure TUnitStateTests.MSonarMakesItNonEmpty;
var
  S: TUnitState;
begin
  S := TUnitState.Create;
  try
    S.MSonar.Add('TFoo.Bar');
    Assert.IsFalse(S.IsEmpty);
  finally
    S.Free;
  end;
end;

{ TProgressStateTests }

procedure TProgressStateTests.FindReturnsNilForUnknownPath;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    Assert.IsNull(St.Find('a.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.RecCreatesThenReusesTheSameInstance;
var
  St: TProgressState;
  S1, S2: TUnitState;
begin
  St := TProgressState.Create;
  try
    S1 := St.Rec('a.pas');
    S2 := St.Rec('a.pas');
    Assert.AreEqual(S1, S2);
    Assert.AreEqual(S1, St.Find('a.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.ClearRemovesEverything;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Done := True;
    St.Clear;
    Assert.IsNull(St.Find('a.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.EmptyRecordsAreOmittedFromJson;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.Rec('a.pas');   // cria o registo mas nao marca nada: fica vazio
    Assert.AreEqual('{}', St.ToJSONString);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.ToJSONStringRoundTripsAllFields;
var
  Saved, Loaded: TProgressState;
  S: TUnitState;
  Json: string;
begin
  Saved := TProgressState.Create;
  Loaded := TProgressState.Create;
  try
    S := Saved.Rec('Core/a.pas');
    S.Done := True;
    S.Star := True;
    S.Compila := True;
    S.Sonar := True;
    S.Note := 'nota com acento: e-mail';
    S.Ts := 1700000000123;
    S.MDone.Add('TFoo.Bar');
    S.MCompila.Add('TFoo.Baz');
    S.MSonar.Add('TFoo.Qux');

    Json := Saved.ToJSONString;
    Loaded.LoadFromJSONString(Json);

    S := Loaded.Find('Core/a.pas');
    Assert.IsNotNull(S);
    Assert.IsTrue(S.Done);
    Assert.IsTrue(S.Star);
    Assert.IsTrue(S.Compila);
    Assert.IsTrue(S.Sonar);
    Assert.AreEqual('nota com acento: e-mail', S.Note);
    Assert.AreEqual(Int64(1700000000123), S.Ts);
    Assert.IsTrue(S.MDone.Contains('TFoo.Bar'));
    Assert.IsTrue(S.MCompila.Contains('TFoo.Baz'));
    Assert.IsTrue(S.MSonar.Contains('TFoo.Qux'));
  finally
    Saved.Free;
    Loaded.Free;
  end;
end;

procedure TProgressStateTests.LoadAcceptsThePlainFormat;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.LoadFromJSONString('{"a.pas": {"done": true}}');
    Assert.IsTrue(St.Find('a.pas').Done);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadAcceptsTheWrappedExportedFormat;
var
  St: TProgressState;
begin
  // formato das paginas HTML exportadas: {version, exportedAt, state: {...}}
  St := TProgressState.Create;
  try
    St.LoadFromJSONString(
      '{"version": 1, "exportedAt": "2026-01-01", "state": {"a.pas": {"done": true, "star": true}}}');
    Assert.IsTrue(St.Find('a.pas').Done);
    Assert.IsTrue(St.Find('a.pas').Star);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadDefaultsMissingBooleans;
var
  St: TProgressState;
  S: TUnitState;
begin
  St := TProgressState.Create;
  try
    St.LoadFromJSONString('{"a.pas": {"note": "x"}}');
    S := St.Find('a.pas');
    Assert.IsFalse(S.Done);
    Assert.IsFalse(S.Star);
    Assert.IsFalse(S.Compila);
    Assert.IsFalse(S.Sonar);
    Assert.AreEqual(Int64(0), S.Ts);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadIgnoresNonObjectEntries;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.LoadFromJSONString('{"a.pas": {"done": true}, "b.pas": "nao e um objecto", "c.pas": 123}');
    Assert.IsNotNull(St.Find('a.pas'));
    Assert.IsNull(St.Find('b.pas'));
    Assert.IsNull(St.Find('c.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadReplacesThePreviousState;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.Rec('old.pas').Done := True;
    St.LoadFromJSONString('{"new.pas": {"done": true}}');
    Assert.IsNull(St.Find('old.pas'));
    Assert.IsNotNull(St.Find('new.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadRaisesOnInvalidJson;
var
  St: TProgressState;
  Raised: Boolean;
begin
  St := TProgressState.Create;
  try
    Raised := False;
    try
      St.LoadFromJSONString('isto nao e json');
    except
      on Exception do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.LoadRaisesWhenRootIsAnArray;
var
  St: TProgressState;
  Raised: Boolean;
begin
  St := TProgressState.Create;
  try
    Raised := False;
    try
      St.LoadFromJSONString('[1, 2, 3]');
    except
      on Exception do
        Raised := True;
    end;
    Assert.IsTrue(Raised);
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.TimestampRoundTripsExactly;
var
  St: TProgressState;
  Ts: Int64;
begin
  St := TProgressState.Create;
  try
    Ts := NowMillis;
    // Ts acompanha sempre uma alteracao real (Done/MDone: ve-se em CM.TreeList.ToggleElem);
    // sozinho, o registo conta como vazio e nem chega a ser gravado (ver o teste seguinte)
    St.Rec('a.pas').Done := True;
    St.Rec('a.pas').Ts := Ts;
    St.LoadFromJSONString(St.ToJSONString);
    Assert.AreEqual(Ts, St.Find('a.pas').Ts, 'sem perda de precisao ao passar por Double/TJSONNumber');
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.TimestampAloneDoesNotSurviveARoundTrip;
var
  St: TProgressState;
begin
  // TUnitState.IsEmpty nao olha para Ts: um registo so com timestamp conta como vazio,
  // fica de fora do JSON gravado e desaparece ao recarregar. Inofensivo no uso real (o Ts
  // nunca e a unica coisa marcada), mas documenta o comportamento para nao voltar a
  // surpreender (ja causou um acesso a nil num teste anterior desta suite).
  St := TProgressState.Create;
  try
    St.Rec('a.pas').Ts := NowMillis;
    Assert.AreEqual('{}', St.ToJSONString);
    St.LoadFromJSONString(St.ToJSONString);
    Assert.IsNull(St.Find('a.pas'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.MethodSetsWithSpecialCharactersRoundTrip;
var
  St: TProgressState;
  Name: string;
begin
  Name := 'TFoo<T>.Bar(Integer, string)';
  St := TProgressState.Create;
  try
    St.Rec('a.pas').MDone.Add(Name);
    St.LoadFromJSONString(St.ToJSONString);
    Assert.IsTrue(St.Find('a.pas').MDone.Contains(Name));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.FalseFlagsInASetAreNotAdded;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.LoadFromJSONString('{"a.pas": {"m": {"TFoo.Bar": false, "TFoo.Baz": true}}}');
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('TFoo.Bar'));
    Assert.IsTrue(St.Find('a.pas').MDone.Contains('TFoo.Baz'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.NonBooleanValuesInASetAreIgnored;
var
  St: TProgressState;
begin
  St := TProgressState.Create;
  try
    St.LoadFromJSONString('{"a.pas": {"m": {"TFoo.Bar": "true", "TFoo.Baz": 1}}}');
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('TFoo.Bar'));
    Assert.IsFalse(St.Find('a.pas').MDone.Contains('TFoo.Baz'));
  finally
    St.Free;
  end;
end;

procedure TProgressStateTests.SaveToFileThenLoadFromFileRoundTrips;
var
  Dir: TTempDir;
  Saved, Loaded: TProgressState;
  FileName: string;
begin
  Dir := TTempDir.Create;
  Saved := TProgressState.Create;
  Loaded := TProgressState.Create;
  try
    Saved.Rec('a.pas').Done := True;
    Saved.Rec('a.pas').MDone.Add('TFoo.Bar');
    FileName := Dir.Full('progress.json');
    Saved.SaveToFile(FileName);
    Assert.IsTrue(TFile.Exists(FileName));
    Loaded.LoadFromFile(FileName);
    Assert.IsTrue(Loaded.Find('a.pas').Done);
    Assert.IsTrue(Loaded.Find('a.pas').MDone.Contains('TFoo.Bar'));
  finally
    Saved.Free;
    Loaded.Free;
    Dir.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectProfileTests);
  TDUnitX.RegisterTestFixture(TAppDataTests);
  TDUnitX.RegisterTestFixture(TAppSettingsTests);
  TDUnitX.RegisterTestFixture(TUnitStateTests);
  TDUnitX.RegisterTestFixture(TProgressStateTests);

end.
