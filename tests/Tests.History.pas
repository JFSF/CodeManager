unit Tests.History;

// Testes de CM.History: registos diarios do progresso (Capture), conversao a partir de TStats,
// percentagens, datas, JSON (ida e volta, entradas invalidas) e o ficheiro history-<id>.json
// (incluindo apagar-se com o projecto).

interface

uses
  System.SysUtils, System.IOUtils, DUnitX.TestFramework, CM.Stats, CM.Store, CM.History, Tests.Helpers;

type
  [TestFixture]
  TSnapshotTests = class
  public
    [Test] procedure FromStatsCopiesEveryField;
    [Test] procedure PercentagesUseDoneOverTotal;
    [Test] procedure PercentagesAreZeroWithoutTotals;
    [Test] procedure CompilaAndSonarPercentagesUseTheFileTotal;
    [Test] procedure TryDayAcceptsOnlyRealDates;
    [Test] procedure DayTextIsIsoFormat;
  end;

  [TestFixture]
  THistoryCaptureTests = class
  private
    FHistory: THistory;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FirstCaptureAddsAnItem;
    [Test] procedure SameDayReplacesTheItem;
    [Test] procedure SameDayWithSameValuesReportsNoChange;
    [Test] procedure OutOfOrderDatesAreKeptSorted;
    [Test] procedure ClearEmptiesTheHistory;
  end;

  [TestFixture]
  THistoryJsonTests = class
  private
    FHistory: THistory;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure RoundTripKeepsEveryValue;
    [Test] procedure InvalidJsonLeavesItEmpty;
    [Test] procedure RootWithoutSnapshotsLeavesItEmpty;
    [Test] procedure EntriesWithBadDateOrShapeAreSkipped;
    [Test] procedure MissingAndNegativeNumbersBecomeZero;
    [Test] procedure DuplicateDatesKeepTheLast;
    [Test] procedure LoadReplacesPreviousContent;
    [Test] procedure FileRoundTrip;
  end;

  [TestFixture]
  THistoryFileTests = class
  public
    [Test] procedure HistoryFileUsesTheProjectId;
    [Test] procedure RemovingAProjectDeletesItsProgressAndHistory;
  end;

implementation

function Snap(const ADate: string; AFiles, ADone: Integer; AMethods: Integer = 0;
  AMethodsDone: Integer = 0): TSnapshot;
begin
  Result := Default(TSnapshot);
  Result.Date := ADate;
  Result.Files := AFiles;
  Result.DoneFiles := ADone;
  Result.Methods := AMethods;
  Result.DoneMethods := AMethodsDone;
end;

{ TSnapshotTests }

procedure TSnapshotTests.FromStatsCopiesEveryField;
var
  St: TStats;
  S: TSnapshot;
begin
  St := Default(TStats);
  St.Files := 11;
  St.DoneFiles := 4;
  St.Methods := 300;
  St.DoneMethods := 120;
  St.FilesCompila := 5;
  St.FilesSonar := 3;
  St.MethodsCompila := 200;
  St.MethodsSonar := 90;
  S := TSnapshot.FromStats('2026-10-02', St);
  Assert.AreEqual('2026-10-02', S.Date);
  Assert.AreEqual(11, S.Files);
  Assert.AreEqual(4, S.DoneFiles);
  Assert.AreEqual(300, S.Methods);
  Assert.AreEqual(120, S.DoneMethods);
  Assert.AreEqual(5, S.FilesCompila);
  Assert.AreEqual(3, S.FilesSonar);
  Assert.AreEqual(200, S.MethodsCompila);
  Assert.AreEqual(90, S.MethodsSonar);
end;

procedure TSnapshotTests.PercentagesUseDoneOverTotal;
var
  S: TSnapshot;
begin
  S := Snap('2026-10-02', 8, 2, 200, 50);
  Assert.AreEqual(25.0, S.PercentFiles, 0.0001);
  Assert.AreEqual(25.0, S.PercentMethods, 0.0001);
  S := Snap('2026-10-02', 3, 1);
  Assert.AreEqual(100 / 3, S.PercentFiles, 0.0001);
end;

procedure TSnapshotTests.PercentagesAreZeroWithoutTotals;
var
  S: TSnapshot;
begin
  S := Snap('2026-10-02', 0, 0);
  Assert.AreEqual(0.0, S.PercentFiles, 0.0001);
  Assert.AreEqual(0.0, S.PercentMethods, 0.0001);
end;

procedure TSnapshotTests.CompilaAndSonarPercentagesUseTheFileTotal;
var
  S: TSnapshot;
begin
  S := Snap('2026-10-02', 8, 0);
  S.FilesCompila := 6;
  S.FilesSonar := 2;
  Assert.AreEqual(75.0, S.PercentFilesCompila, 0.0001);
  Assert.AreEqual(25.0, S.PercentFilesSonar, 0.0001);
  S.Files := 0;
  Assert.AreEqual(0.0, S.PercentFilesCompila, 0.0001, 'sem ficheiros');
  Assert.AreEqual(0.0, S.PercentFilesSonar, 0.0001, 'sem ficheiros');
end;

procedure TSnapshotTests.TryDayAcceptsOnlyRealDates;
var
  D: TDateTime;
begin
  Assert.IsTrue(TryParseDay('2026-10-02', D));
  Assert.AreEqual(EncodeDate(2026, 10, 2), D, 0.0001);
  Assert.IsTrue(TryParseDay('2028-02-29', D), 'ano bissexto');
  Assert.IsFalse(TryParseDay('2026-02-30', D), 'dia inexistente');
  Assert.IsFalse(TryParseDay('2026-13-01', D), 'mes inexistente');
  Assert.IsFalse(TryParseDay('2026-1-5', D), 'sem zeros a esquerda');
  Assert.IsFalse(TryParseDay('abcd-ef-gh', D));
  Assert.IsFalse(TryParseDay('', D));
end;

procedure TSnapshotTests.DayTextIsIsoFormat;
begin
  Assert.AreEqual('2026-01-05', DayText(EncodeDate(2026, 1, 5)));
end;

{ THistoryCaptureTests }

procedure THistoryCaptureTests.Setup;
begin
  FHistory := THistory.Create;
end;

procedure THistoryCaptureTests.TearDown;
begin
  FHistory.Free;
end;

procedure THistoryCaptureTests.FirstCaptureAddsAnItem;
begin
  Assert.IsTrue(FHistory.Capture(Snap('2026-10-01', 10, 1)));
  Assert.AreEqual(1, FHistory.Count);
  Assert.AreEqual('2026-10-01', FHistory[0].Date);
end;

procedure THistoryCaptureTests.SameDayReplacesTheItem;
begin
  FHistory.Capture(Snap('2026-10-01', 10, 1));
  Assert.IsTrue(FHistory.Capture(Snap('2026-10-01', 10, 4)), 'valores diferentes: mudou');
  Assert.AreEqual(1, FHistory.Count);
  Assert.AreEqual(4, FHistory[0].DoneFiles);
end;

procedure THistoryCaptureTests.SameDayWithSameValuesReportsNoChange;
begin
  FHistory.Capture(Snap('2026-10-01', 10, 1));
  Assert.IsFalse(FHistory.Capture(Snap('2026-10-01', 10, 1)));
  Assert.AreEqual(1, FHistory.Count);
end;

procedure THistoryCaptureTests.OutOfOrderDatesAreKeptSorted;
begin
  FHistory.Capture(Snap('2026-10-03', 10, 3));
  FHistory.Capture(Snap('2026-10-01', 10, 1));
  FHistory.Capture(Snap('2026-10-02', 10, 2));
  FHistory.Capture(Snap('2026-11-01', 10, 9));
  Assert.AreEqual(4, FHistory.Count);
  Assert.AreEqual('2026-10-01', FHistory[0].Date);
  Assert.AreEqual('2026-10-02', FHistory[1].Date);
  Assert.AreEqual('2026-10-03', FHistory[2].Date);
  Assert.AreEqual('2026-11-01', FHistory[3].Date);
end;

procedure THistoryCaptureTests.ClearEmptiesTheHistory;
begin
  FHistory.Capture(Snap('2026-10-01', 10, 1));
  FHistory.Clear;
  Assert.AreEqual(0, FHistory.Count);
end;

{ THistoryJsonTests }

procedure THistoryJsonTests.Setup;
begin
  FHistory := THistory.Create;
end;

procedure THistoryJsonTests.TearDown;
begin
  FHistory.Free;
end;

procedure THistoryJsonTests.RoundTripKeepsEveryValue;
var
  Other: THistory;
  S: TSnapshot;
begin
  S := Snap('2026-10-01', 11, 4, 300, 120);
  S.FilesCompila := 5;
  S.FilesSonar := 3;
  S.MethodsCompila := 200;
  S.MethodsSonar := 90;
  FHistory.Capture(S);
  FHistory.Capture(Snap('2026-10-02', 12, 6, 310, 150));
  Other := THistory.Create;
  try
    Other.LoadFromJSONString(FHistory.ToJSONString);
    Assert.AreEqual(2, Other.Count);
    Assert.IsTrue(Other[0].SameValues(S));
    Assert.AreEqual('2026-10-02', Other[1].Date);
    Assert.AreEqual(150, Other[1].DoneMethods);
  finally
    Other.Free;
  end;
end;

procedure THistoryJsonTests.InvalidJsonLeavesItEmpty;
begin
  FHistory.Capture(Snap('2026-10-01', 1, 1));
  FHistory.LoadFromJSONString('isto nao e json {');
  Assert.AreEqual(0, FHistory.Count);
end;

procedure THistoryJsonTests.RootWithoutSnapshotsLeavesItEmpty;
begin
  FHistory.LoadFromJSONString('{"version":1}');
  Assert.AreEqual(0, FHistory.Count);
  FHistory.LoadFromJSONString('[1,2,3]');
  Assert.AreEqual(0, FHistory.Count);
end;

procedure THistoryJsonTests.EntriesWithBadDateOrShapeAreSkipped;
begin
  FHistory.LoadFromJSONString('{"snapshots":[' +
    '{"date":"2026-10-01","files":5},' +
    '{"date":"2026-02-30","files":9},' +
    '{"files":7},' +
    '"texto",' +
    '{"date":"2026-10-02","files":6}]}');
  Assert.AreEqual(2, FHistory.Count);
  Assert.AreEqual('2026-10-01', FHistory[0].Date);
  Assert.AreEqual('2026-10-02', FHistory[1].Date);
end;

procedure THistoryJsonTests.MissingAndNegativeNumbersBecomeZero;
begin
  FHistory.LoadFromJSONString('{"snapshots":[{"date":"2026-10-01","files":-4,"doneFiles":3}]}');
  Assert.AreEqual(1, FHistory.Count);
  Assert.AreEqual(0, FHistory[0].Files, 'negativo');
  Assert.AreEqual(3, FHistory[0].DoneFiles);
  Assert.AreEqual(0, FHistory[0].Methods, 'em falta');
end;

procedure THistoryJsonTests.DuplicateDatesKeepTheLast;
begin
  FHistory.LoadFromJSONString('{"snapshots":[' +
    '{"date":"2026-10-01","files":5,"doneFiles":1},' +
    '{"date":"2026-10-01","files":5,"doneFiles":4}]}');
  Assert.AreEqual(1, FHistory.Count);
  Assert.AreEqual(4, FHistory[0].DoneFiles);
end;

procedure THistoryJsonTests.LoadReplacesPreviousContent;
begin
  FHistory.Capture(Snap('2026-09-01', 1, 1));
  FHistory.LoadFromJSONString('{"snapshots":[{"date":"2026-10-01","files":5}]}');
  Assert.AreEqual(1, FHistory.Count);
  Assert.AreEqual('2026-10-01', FHistory[0].Date);
end;

procedure THistoryJsonTests.FileRoundTrip;
var
  Dir: TTempDir;
  Other: THistory;
begin
  Dir := TTempDir.Create;
  Other := THistory.Create;
  try
    FHistory.Capture(Snap('2026-10-01', 11, 4, 300, 120));
    FHistory.SaveToFile(Dir.Full('h.json'));
    Other.LoadFromFile(Dir.Full('h.json'));
    Assert.AreEqual(1, Other.Count);
    Assert.AreEqual(120, Other[0].DoneMethods);
  finally
    Other.Free;
    Dir.Free;
  end;
end;

{ THistoryFileTests }

procedure THistoryFileTests.HistoryFileUsesTheProjectId;
var
  Data: TIsolatedAppData;
begin
  Data := TIsolatedAppData.Create;
  try
    Assert.AreEqual(TPath.Combine(Data.Path, 'history-abc123.json'), HistoryFileFor('abc123'));
  finally
    Data.Free;
  end;
end;

procedure THistoryFileTests.RemovingAProjectDeletesItsProgressAndHistory;
var
  Data: TIsolatedAppData;
  Settings: TAppSettings;
  P: TProjectProfile;
  H: THistory;
  State: TProgressState;
  Id: string;
begin
  Data := TIsolatedAppData.Create;
  Settings := TAppSettings.Create;
  H := THistory.Create;
  State := TProgressState.Create;
  try
    P := Settings.AddProject;
    Id := P.Id;                    // RemoveProject liberta o perfil
    State.SaveToFile(ProgressFileFor(Id));
    H.Capture(Snap('2026-10-01', 1, 1));
    H.SaveToFile(HistoryFileFor(Id));
    Assert.IsTrue(TFile.Exists(ProgressFileFor(Id)));
    Assert.IsTrue(TFile.Exists(HistoryFileFor(Id)));
    Settings.RemoveProject(P);
    Assert.IsFalse(TFile.Exists(ProgressFileFor(Id)), 'progresso apagado');
    Assert.IsFalse(TFile.Exists(HistoryFileFor(Id)), 'historico apagado');
  finally
    State.Free;
    H.Free;
    Settings.Free;
    Data.Free;
  end;
end;

end.
