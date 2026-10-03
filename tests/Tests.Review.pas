unit Tests.Review;

// Testes dos estados de revisao alem de "feito" (CM.Stats: ReviewOfMethod, ReviewOfUnit, NextReview,
// SetMethodReview, SetFileReview, estatisticas por estado) e da sua persistencia (CM.Store).
// Os scans sao construidos em memoria (Tests.Helpers).

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.Analyzer, CM.Store, CM.Stats, Tests.Helpers;

type
  [TestFixture]
  TReviewRulesTests = class
  private
    FState: TProgressState;
    FUnit: TUnitInfo;
    function Unit3: TUnitInfo;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure MethodWithoutStateIsPending;
    [Test] procedure MethodStatesAreRead;
    [Test] procedure DoneBeatsTheOtherMarks;
    [Test] procedure FixBeatsWip;
    [Test] procedure SetMethodReviewIsExclusive;
    [Test] procedure SettingBackToPendingClearsEverything;
    [Test] procedure UnitIsDoneWhenAllMethodsAre;
    [Test] procedure SettingTheLastMethodDoneMarksTheFileDone;
    [Test] procedure ReopeningAMethodUnmarksTheFile;
    [Test] procedure UnitNeedsChangeWhenAnyMethodDoes;
    [Test] procedure UnitIsInReviewWhenAnyMethodIsOrPartIsDone;
    [Test] procedure UnitWithMethodsAndNoStateIsPending;
    [Test] procedure UnitWithoutMethodsUsesItsOwnMarks;
    [Test] procedure SetFileReviewIsExclusive;
    [Test] procedure NextReviewCycles;
    [Test] procedure ReviewTextIsInPortuguese;
    [Test] procedure StatsCountFilesAndMethodsPerState;
    [Test] procedure ProgressJsonRoundTripsTheStates;
    [Test] procedure StatesAreOmittedFromJsonWhenAbsent;
    [Test] procedure UnitWithOnlyAReviewMarkIsNotEmpty;
  end;

implementation

procedure TReviewRulesTests.Setup;
begin
  FState := TProgressState.Create;
  FUnit := nil;
end;

procedure TReviewRulesTests.TearDown;
begin
  FUnit.Free;
  FState.Free;
end;

function TReviewRulesTests.Unit3: TUnitInfo;
begin
  if FUnit = nil then
    FUnit := MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Two'), Meth('Three')]);
  Result := FUnit;
end;

procedure TReviewRulesTests.MethodWithoutStateIsPending;
begin
  Assert.AreEqual(Ord(rsPending), Ord(ReviewOfMethod(nil, 'One')));
  Assert.AreEqual(Ord(rsPending), Ord(ReviewOfMethod(FState.Rec('a.pas'), 'One')));
end;

procedure TReviewRulesTests.MethodStatesAreRead;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  S.MDone.Add('One');
  S.MWip.Add('Two');
  S.MFix.Add('Three');
  Assert.AreEqual(Ord(rsDone), Ord(ReviewOfMethod(S, 'One')));
  Assert.AreEqual(Ord(rsInReview), Ord(ReviewOfMethod(S, 'Two')));
  Assert.AreEqual(Ord(rsNeedsChange), Ord(ReviewOfMethod(S, 'Three')));
end;

procedure TReviewRulesTests.DoneBeatsTheOtherMarks;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  S.MDone.Add('One');
  S.MWip.Add('One');
  S.MFix.Add('One');
  Assert.AreEqual(Ord(rsDone), Ord(ReviewOfMethod(S, 'One')), 'ficheiro editado a mao ou vindo de outro lado');
end;

procedure TReviewRulesTests.FixBeatsWip;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  S.MWip.Add('One');
  S.MFix.Add('One');
  Assert.AreEqual(Ord(rsNeedsChange), Ord(ReviewOfMethod(S, 'One')));
end;

procedure TReviewRulesTests.SetMethodReviewIsExclusive;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsInReview);
  Assert.IsTrue(S.MWip.Contains('One'));
  SetMethodReview(Unit3, S, 'One', rsNeedsChange);
  Assert.IsFalse(S.MWip.Contains('One'));
  Assert.IsTrue(S.MFix.Contains('One'));
  SetMethodReview(Unit3, S, 'One', rsDone);
  Assert.IsFalse(S.MFix.Contains('One'));
  Assert.IsTrue(S.MDone.Contains('One'));
end;

procedure TReviewRulesTests.SettingBackToPendingClearsEverything;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsDone);
  SetMethodReview(Unit3, S, 'One', rsPending);
  Assert.AreEqual<NativeInt>(0, S.MDone.Count + S.MWip.Count + S.MFix.Count);
end;

procedure TReviewRulesTests.UnitIsDoneWhenAllMethodsAre;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsDone);
  SetMethodReview(Unit3, S, 'Two', rsDone);
  Assert.AreEqual(Ord(rsInReview), Ord(ReviewOfUnit(Unit3, FState)), 'falta um');
  SetMethodReview(Unit3, S, 'Three', rsDone);
  Assert.AreEqual(Ord(rsDone), Ord(ReviewOfUnit(Unit3, FState)));
end;

procedure TReviewRulesTests.SettingTheLastMethodDoneMarksTheFileDone;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsDone);
  SetMethodReview(Unit3, S, 'Two', rsDone);
  Assert.IsFalse(S.Done);
  SetMethodReview(Unit3, S, 'Three', rsDone);
  Assert.IsTrue(S.Done);
  Assert.IsTrue(S.Ts > 0, 'a hora da conclusao fica registada');
end;

procedure TReviewRulesTests.ReopeningAMethodUnmarksTheFile;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsDone);
  SetMethodReview(Unit3, S, 'Two', rsDone);
  SetMethodReview(Unit3, S, 'Three', rsDone);
  SetMethodReview(Unit3, S, 'Two', rsNeedsChange);
  Assert.IsFalse(S.Done);
  Assert.AreEqual(Ord(rsNeedsChange), Ord(ReviewOfUnit(Unit3, FState)));
end;

procedure TReviewRulesTests.UnitNeedsChangeWhenAnyMethodDoes;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsDone);
  SetMethodReview(Unit3, S, 'Two', rsInReview);
  SetMethodReview(Unit3, S, 'Three', rsNeedsChange);
  Assert.AreEqual(Ord(rsNeedsChange), Ord(ReviewOfUnit(Unit3, FState)), 'tem prioridade sobre "em revisao"');
end;

procedure TReviewRulesTests.UnitIsInReviewWhenAnyMethodIsOrPartIsDone;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  SetMethodReview(Unit3, S, 'One', rsInReview);
  Assert.AreEqual(Ord(rsInReview), Ord(ReviewOfUnit(Unit3, FState)));
  SetMethodReview(Unit3, S, 'One', rsPending);
  SetMethodReview(Unit3, S, 'Two', rsDone);
  Assert.AreEqual(Ord(rsInReview), Ord(ReviewOfUnit(Unit3, FState)), 'parte feita = ja comecou');
end;

procedure TReviewRulesTests.UnitWithMethodsAndNoStateIsPending;
begin
  Assert.AreEqual(Ord(rsPending), Ord(ReviewOfUnit(Unit3, FState)));
end;

procedure TReviewRulesTests.UnitWithoutMethodsUsesItsOwnMarks;
var
  U: TUnitInfo;
  S: TUnitState;
begin
  U := MakeUnitInfo('b.pas', 'Raiz', []);
  try
    Assert.AreEqual(Ord(rsPending), Ord(ReviewOfUnit(U, FState)));
    S := FState.Rec('b.pas');
    S.Wip := True;
    Assert.AreEqual(Ord(rsInReview), Ord(ReviewOfUnit(U, FState)));
    S.Fix := True;
    Assert.AreEqual(Ord(rsNeedsChange), Ord(ReviewOfUnit(U, FState)));
    S.Done := True;
    Assert.AreEqual(Ord(rsDone), Ord(ReviewOfUnit(U, FState)));
  finally
    U.Free;
  end;
end;

procedure TReviewRulesTests.SetFileReviewIsExclusive;
var
  S: TUnitState;
begin
  S := FState.Rec('b.pas');
  SetFileReview(S, rsInReview);
  Assert.IsTrue(S.Wip and not S.Fix and not S.Done);
  SetFileReview(S, rsNeedsChange);
  Assert.IsTrue(S.Fix and not S.Wip and not S.Done);
  SetFileReview(S, rsDone);
  Assert.IsTrue(S.Done and not S.Wip and not S.Fix);
  SetFileReview(S, rsPending);
  Assert.IsFalse(S.Done or S.Wip or S.Fix);
end;

procedure TReviewRulesTests.NextReviewCycles;
begin
  Assert.AreEqual(Ord(rsInReview), Ord(NextReview(rsPending)));
  Assert.AreEqual(Ord(rsNeedsChange), Ord(NextReview(rsInReview)));
  Assert.AreEqual(Ord(rsPending), Ord(NextReview(rsNeedsChange)));
  Assert.AreEqual(Ord(rsNeedsChange), Ord(NextReview(rsDone)), 'reabre um "feito"');
end;

procedure TReviewRulesTests.ReviewTextIsInPortuguese;
begin
  Assert.AreEqual('Por rever', ReviewText(rsPending));
  Assert.AreEqual('Em revisão', ReviewText(rsInReview));
  Assert.AreEqual('Precisa de alteração', ReviewText(rsNeedsChange));
  Assert.AreEqual('Concluído', ReviewText(rsDone));
end;

procedure TReviewRulesTests.StatsCountFilesAndMethodsPerState;
var
  Scan: TProjectScan;
  St: TStats;
  S: TUnitState;
  A, B, C: TUnitInfo;
begin
  A := MakeUnitInfo('a.pas', 'Raiz', [Meth('One'), Meth('Two')]);
  B := MakeUnitInfo('b.pas', 'Raiz', [Meth('X')]);
  C := MakeUnitInfo('c.pas', 'Raiz', []);
  Scan := NewScan(1, [A, B, C]);
  try
    S := FState.Rec('a.pas');
    SetMethodReview(A, S, 'One', rsDone);
    SetMethodReview(A, S, 'Two', rsNeedsChange);
    S := FState.Rec('b.pas');
    SetMethodReview(B, S, 'X', rsInReview);
    SetFileReview(FState.Rec('c.pas'), rsDone);
    St := ComputeStats(Scan, FState);
    Assert.AreEqual(0, St.FilesByReview[rsPending]);
    Assert.AreEqual(1, St.FilesByReview[rsInReview], 'b');
    Assert.AreEqual(1, St.FilesByReview[rsNeedsChange], 'a');
    Assert.AreEqual(1, St.FilesByReview[rsDone], 'c');
    Assert.AreEqual(0, St.MethodsByReview[rsPending]);
    Assert.AreEqual(1, St.MethodsByReview[rsInReview]);
    Assert.AreEqual(1, St.MethodsByReview[rsNeedsChange]);
    Assert.AreEqual(1, St.MethodsByReview[rsDone]);
    Assert.AreEqual(1, St.DoneMethods, 'o "feito" de sempre nao muda');
  finally
    Scan.Free;
  end;
end;

procedure TReviewRulesTests.ProgressJsonRoundTripsTheStates;
var
  Loaded: TProgressState;
  S: TUnitState;
  Json: string;
begin
  S := FState.Rec('a.pas');
  S.Wip := True;
  S.MWip.Add('One');
  S.MFix.Add('Two');
  Json := FState.ToJSONString;
  Loaded := TProgressState.Create;
  try
    Loaded.LoadFromJSONString(Json);
    S := Loaded.Find('a.pas');
    Assert.IsNotNull(S);
    Assert.IsTrue(S.Wip);
    Assert.IsFalse(S.Fix);
    Assert.IsTrue(S.MWip.Contains('One'));
    Assert.IsTrue(S.MFix.Contains('Two'));
  finally
    Loaded.Free;
  end;
end;

procedure TReviewRulesTests.StatesAreOmittedFromJsonWhenAbsent;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  S.Done := True;
  Assert.AreEqual('{"a.pas":{"done":true}}', FState.ToJSONString,
    'o formato de sempre, igual ao das paginas HTML, nao ganha campos novos');
end;

procedure TReviewRulesTests.UnitWithOnlyAReviewMarkIsNotEmpty;
var
  S: TUnitState;
begin
  S := FState.Rec('a.pas');
  Assert.IsTrue(S.IsEmpty);
  S.MFix.Add('One');
  Assert.IsFalse(S.IsEmpty, 'senao seria descartado ao gravar');
end;

end.
