unit Tests.SonarMeasures;

// Testes das medidas do SonarQube alem dos problemas por ficheiro: medidas por ficheiro e do projecto,
// detalhe dos problemas (linha, tipo, regra), security hotspots, classificacoes e dividas. As respostas da API
// sao textos de exemplo, no formato do SonarQube; nenhum teste precisa de um servidor.

interface

uses
  System.SysUtils, DUnitX.TestFramework, CM.SonarModel, CM.Sonar;

type
  [TestFixture]
  TSonarMeasuresTests = class
  private
    FSnap: TSonarSnapshot;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FileMeasuresAreReadFromTheComponentTree;
    [Test] procedure MissingMeasuresStayUnknown;
    [Test] procedure FilesWithoutMeasuresKeepWorkingAsBefore;
    [Test] procedure ProjectMeasuresIncludeTheRatings;
    [Test] procedure ProjectMeasuresOfGarbageAreNotKnown;
    [Test] procedure ProjectMeasuresWithoutMeasuresAreNotKnown;
    [Test] procedure IssueDetailsKeepLineTypeRuleAndMessage;
    [Test] procedure IssueLineFallsBackToTheTextRange;
    [Test] procedure IssuesOfAreSortedByLineThenSeverity;
    [Test] procedure IssuesOfUsesTheSamePathMatchingAsFind;
    [Test] procedure HotspotsAreReadAndSorted;
    [Test] procedure HotspotsOfProjectLevelComponentsAreSkipped;
    [Test] procedure HotspotsPageOfGarbageAddsNothing;
    [Test] procedure SetFileMeasuresKeepsTheIssueCounts;
    [Test] procedure RatingLettersAndDebtText;
    [Test] procedure RequestedMetricsFitTheApiLimit;
    [Test] procedure ProjectLinesAreEmptyWithoutMeasures;
    [Test] procedure ProjectLinesShowTheValuesAndDashesForMissingOnes;
    [Test] procedure ProjectLinesHighlightWhatIsGood;
    [Test] procedure FileTextJoinsWhatIsKnown;
    [Test] procedure FileTextIsEmptyWithoutMeasures;
  end;

implementation

const
  TreeJson =
    '{"paging":{"pageIndex":1,"pageSize":500,"total":2},"components":[' +
    '{"key":"K:src/a.pas","path":"src/a.pas","qualifier":"FIL","measures":[' +
    '{"metric":"ncloc","value":"120"},{"metric":"coverage","value":"85.5"},' +
    '{"metric":"duplicated_lines_density","value":"3.2"},{"metric":"sqale_index","value":"185"},' +
    '{"metric":"complexity","value":"40"},{"metric":"cognitive_complexity","value":"22"},' +
    '{"metric":"bugs","value":"1"},{"metric":"vulnerabilities","value":"2"},' +
    '{"metric":"code_smells","value":"7"},{"metric":"security_hotspots","value":"3"}]},' +
    '{"key":"K:src/b.pas","path":"src/b.pas","qualifier":"FIL","measures":[{"metric":"ncloc","value":"10"}]}]}';

  ProjectJson =
    '{"component":{"key":"K","measures":[{"metric":"ncloc","value":"5000"},{"metric":"coverage","value":"61.3"},' +
    '{"metric":"duplicated_lines_density","value":"1.5"},{"metric":"sqale_index","value":"2400"},' +
    '{"metric":"bugs","value":"4"},{"metric":"vulnerabilities","value":"1"},{"metric":"code_smells","value":"150"},' +
    '{"metric":"security_hotspots","value":"6"},{"metric":"reliability_rating","value":"2.0"},' +
    '{"metric":"security_rating","value":"1.0"},{"metric":"sqale_rating","value":"1.0"},' +
    '{"metric":"security_review_rating","value":"5.0"}]}}';

  IssuesJson =
    '{"paging":{"total":4},"issues":[' +
    '{"component":"K:src/a.pas","severity":"MINOR","type":"CODE_SMELL","rule":"delphi:Unused","line":30,"message":"Remove this unused variable."},' +
    '{"component":"K:src/a.pas","severity":"CRITICAL","type":"BUG","rule":"delphi:NilDeref","line":30,"message":"Possible nil dereference."},' +
    '{"component":"K:src/a.pas","severity":"MAJOR","type":"VULNERABILITY","rule":"delphi:Sql","line":5,"message":"SQL built from input."},' +
    '{"component":"K:src/a.pas","severity":"INFO","type":"CODE_SMELL","rule":"delphi:Todo","message":"A todo."}]}';

procedure TSonarMeasuresTests.Setup;
begin
  FSnap := TSonarSnapshot.Create;
end;

procedure TSonarMeasuresTests.TearDown;
begin
  FSnap.Free;
end;

procedure TSonarMeasuresTests.FileMeasuresAreReadFromTheComponentTree;
var
  Total: Integer;
  F: TSonarFile;
begin
  Assert.AreEqual(2, ParseMeasuresPage(TreeJson, FSnap, Total));
  Assert.AreEqual(2, Total);
  Assert.IsTrue(FSnap.Find('src/a.pas', F));
  Assert.IsTrue(F.HasMeasures);
  Assert.AreEqual(120, F.Lines);
  Assert.AreEqual(85.5, F.Coverage, 0.001);
  Assert.AreEqual(3.2, F.DupDensity, 0.001);
  Assert.AreEqual(185, F.DebtMin);
  Assert.AreEqual(40, F.Complexity);
  Assert.AreEqual(22, F.Cognitive);
  Assert.AreEqual(1, F.Bugs);
  Assert.AreEqual(2, F.Vulns);
  Assert.AreEqual(7, F.Smells);
  Assert.AreEqual(3, F.Hotspots);
end;

procedure TSonarMeasuresTests.MissingMeasuresStayUnknown;
var
  Total: Integer;
  F: TSonarFile;
begin
  ParseMeasuresPage(TreeJson, FSnap, Total);
  Assert.IsTrue(FSnap.Find('src/b.pas', F));
  Assert.AreEqual(10, F.Lines);
  Assert.IsTrue(F.Coverage < 0, 'sem cobertura: nao e 0 %');
  Assert.IsTrue(F.DupDensity < 0);
  Assert.AreEqual(0, F.DebtMin);
end;

procedure TSonarMeasuresTests.FilesWithoutMeasuresKeepWorkingAsBefore;
var
  Total: Integer;
  F: TSonarFile;
begin
  ParseMeasuresPage('{"components":[{"path":"src/c.pas","measures":[{"metric":"ncloc","value":"7"}]}],"paging":{"total":1}}',
    FSnap, Total);
  Assert.IsTrue(FSnap.Find('src/c.pas', F));
  Assert.AreEqual(7, F.Lines);
  Assert.AreEqual(0, F.Issues);
end;

procedure TSonarMeasuresTests.ProjectMeasuresIncludeTheRatings;
var
  P: TSonarProject;
begin
  Assert.IsTrue(ParseProjectMeasures(ProjectJson, FSnap));
  P := FSnap.Project;
  Assert.IsTrue(P.Known);
  Assert.AreEqual(5000, P.Lines);
  Assert.AreEqual(61.3, P.Coverage, 0.001);
  Assert.AreEqual(1.5, P.DupDensity, 0.001);
  Assert.AreEqual(2400, P.DebtMin);
  Assert.AreEqual(4, P.Bugs);
  Assert.AreEqual(1, P.Vulns);
  Assert.AreEqual(150, P.Smells);
  Assert.AreEqual(6, P.Hotspots);
  Assert.AreEqual(2, P.ReliabilityRating);
  Assert.AreEqual(1, P.SecurityRating);
  Assert.AreEqual(1, P.MaintainabilityRating);
  Assert.AreEqual(5, P.ReviewRating);
end;

procedure TSonarMeasuresTests.ProjectMeasuresOfGarbageAreNotKnown;
begin
  Assert.IsFalse(ParseProjectMeasures('isto nao e json', FSnap));
  Assert.IsFalse(FSnap.Project.Known);
  Assert.IsTrue(FSnap.Project.Coverage < 0);
end;

procedure TSonarMeasuresTests.ProjectMeasuresWithoutMeasuresAreNotKnown;
begin
  Assert.IsFalse(ParseProjectMeasures('{"component":{"key":"K","measures":[]}}', FSnap));
  Assert.IsFalse(FSnap.Project.Known);
end;

procedure TSonarMeasuresTests.IssueDetailsKeepLineTypeRuleAndMessage;
var
  Total: Integer;
  Issues: TArray<TSonarIssue>;
  F: TSonarFile;
begin
  Assert.AreEqual(4, ParseIssuesPage(IssuesJson, 'K', FSnap, Total));
  Issues := FSnap.IssuesOf('src/a.pas');
  Assert.AreEqual<NativeInt>(4, Length(Issues));
  Assert.IsTrue(FSnap.Find('src/a.pas', F));
  Assert.AreEqual(4, F.Issues, 'as contagens de sempre continuam a funcionar');
  Assert.AreEqual(Ord(ssCritical), Ord(F.Worst));
  Assert.AreEqual('SQL built from input.', Issues[1].Message);
  Assert.AreEqual('VULNERABILITY', Issues[1].Kind);
  Assert.AreEqual('delphi:Sql', Issues[1].Rule);
  Assert.AreEqual(5, Issues[1].Line);
end;

procedure TSonarMeasuresTests.IssueLineFallsBackToTheTextRange;
var
  Total: Integer;
  Issues: TArray<TSonarIssue>;
begin
  ParseIssuesPage('{"issues":[{"component":"K:src/a.pas","severity":"MAJOR","textRange":{"startLine":42,"endLine":44},' +
    '"message":"m"}],"paging":{"total":1}}', 'K', FSnap, Total);
  Issues := FSnap.IssuesOf('src/a.pas');
  Assert.AreEqual(42, Issues[0].Line);
end;

procedure TSonarMeasuresTests.IssuesOfAreSortedByLineThenSeverity;
var
  Total: Integer;
  Issues: TArray<TSonarIssue>;
begin
  ParseIssuesPage(IssuesJson, 'K', FSnap, Total);
  Issues := FSnap.IssuesOf('src/a.pas');
  Assert.AreEqual(0, Issues[0].Line, 'sem linha: no principio');
  Assert.AreEqual(5, Issues[1].Line);
  Assert.AreEqual(30, Issues[2].Line);
  Assert.AreEqual(Ord(ssCritical), Ord(Issues[2].Severity), 'na mesma linha, a mais grave primeiro');
  Assert.AreEqual(Ord(ssMinor), Ord(Issues[3].Severity));
end;

procedure TSonarMeasuresTests.IssuesOfUsesTheSamePathMatchingAsFind;
var
  Total: Integer;
begin
  ParseIssuesPage(IssuesJson, 'K', FSnap, Total);
  Assert.AreEqual<NativeInt>(4, Length(FSnap.IssuesOf('a.pas')), 'o Sonar tem o caminho mais comprido');
  Assert.AreEqual<NativeInt>(4, Length(FSnap.IssuesOf('SRC\A.PAS')), 'maiusculas e barras invertidas');
  Assert.AreEqual<NativeInt>(0, Length(FSnap.IssuesOf('src/zzz.pas')));
end;

procedure TSonarMeasuresTests.HotspotsAreReadAndSorted;
var
  Total: Integer;
  Spots: TArray<TSonarHotspot>;
begin
  Assert.AreEqual(2, ParseHotspotsPage(
    '{"paging":{"total":2},"hotspots":[' +
    '{"component":"K:src/a.pas","line":80,"message":"Make sure this is safe.","vulnerabilityProbability":"medium","status":"TO_REVIEW"},' +
    '{"component":"K:src/a.pas","line":12,"message":"Weak hash.","vulnerabilityProbability":"HIGH"}]}',
    'K', FSnap, Total));
  Assert.AreEqual(2, Total);
  Assert.AreEqual(2, FSnap.HotspotCount);
  Spots := FSnap.HotspotsOf('src/a.pas');
  Assert.AreEqual(12, Spots[0].Line);
  Assert.AreEqual('HIGH', Spots[0].Probability);
  Assert.AreEqual('MEDIUM', Spots[1].Probability, 'em maiusculas');
  Assert.AreEqual('Make sure this is safe.', Spots[1].Message);
end;

procedure TSonarMeasuresTests.HotspotsOfProjectLevelComponentsAreSkipped;
var
  Total: Integer;
begin
  Assert.AreEqual(0, ParseHotspotsPage('{"hotspots":[{"component":"K","line":1,"message":"x"}],"paging":{"total":1}}',
    'K', FSnap, Total));
  Assert.AreEqual(0, FSnap.HotspotCount);
end;

procedure TSonarMeasuresTests.HotspotsPageOfGarbageAddsNothing;
var
  Total: Integer;
begin
  Assert.AreEqual(0, ParseHotspotsPage('lixo', 'K', FSnap, Total));
  Assert.AreEqual(0, Total);
  Assert.AreEqual(0, FSnap.HotspotCount);
end;

procedure TSonarMeasuresTests.SetFileMeasuresKeepsTheIssueCounts;
var
  Total: Integer;
  F: TSonarFile;
begin
  ParseIssuesPage(IssuesJson, 'K', FSnap, Total);
  ParseMeasuresPage(TreeJson, FSnap, Total);
  Assert.IsTrue(FSnap.Find('src/a.pas', F));
  Assert.AreEqual(4, F.Issues, 'as medidas nao apagam os problemas contados antes');
  Assert.AreEqual(Ord(ssCritical), Ord(F.Worst));
  Assert.AreEqual(120, F.Lines);
end;

procedure TSonarMeasuresTests.RatingLettersAndDebtText;
begin
  Assert.AreEqual('A', RatingLetter(1));
  Assert.AreEqual('E', RatingLetter(5));
  Assert.AreEqual('', RatingLetter(0));
  Assert.AreEqual('', RatingLetter(6));
  Assert.AreEqual('0', DebtText(0));
  Assert.AreEqual('45min', DebtText(45));
  Assert.AreEqual('1h', DebtText(60));
  Assert.AreEqual('1h 20min', DebtText(80));
  Assert.AreEqual('1d', DebtText(480));
  Assert.AreEqual('2d 3h', DebtText(2 * 480 + 3 * 60 + 15), 'com dias, os minutos nao contam');
  Assert.AreEqual('5d', DebtText(2400));
end;

procedure TSonarMeasuresTests.RequestedMetricsFitTheApiLimit;
begin
  Assert.IsTrue(Length(FileMetricKeys.Split([','])) <= 15, 'a API do Sonar aceita ate 15 medidas por pedido');
  Assert.IsTrue(Length(ProjectMetricKeys.Split([','])) <= 15);
end;

function FindLine(const ALines: TArray<TSonarLine>; const ACaption: string): TSonarLine;
var
  L: TSonarLine;
begin
  for L in ALines do
    if L.Caption = ACaption then
      Exit(L);
  Result := Default(TSonarLine);
  Assert.Fail('linha nao encontrada: ' + ACaption);
end;

procedure TSonarMeasuresTests.ProjectLinesAreEmptyWithoutMeasures;
begin
  Assert.AreEqual<NativeInt>(0, Length(SonarProjectLines(NewSonarProject)));
end;

procedure TSonarMeasuresTests.ProjectLinesShowTheValuesAndDashesForMissingOnes;
var
  Lines: TArray<TSonarLine>;
  P: TSonarProject;
begin
  ParseProjectMeasures(ProjectJson, FSnap);
  Lines := SonarProjectLines(FSnap.Project);
  Assert.AreEqual('61,3%'.Replace(',', FormatSettings.DecimalSeparator), FindLine(Lines, 'Cobertura de testes').Value);
  Assert.AreEqual('1,5%'.Replace(',', FormatSettings.DecimalSeparator), FindLine(Lines, 'Duplicação').Value);
  Assert.AreEqual('5d', FindLine(Lines, 'Dívida técnica').Value);
  Assert.AreEqual('B', FindLine(Lines, 'Fiabilidade').Value);
  Assert.AreEqual('E', FindLine(Lines, 'Revisão de hotspots').Value);
  P := NewSonarProject;
  P.Known := True;
  Lines := SonarProjectLines(P);
  Assert.AreEqual('—', FindLine(Lines, 'Cobertura de testes').Value, 'sem cobertura: um traco, nao 0 %');
  Assert.AreEqual('—', FindLine(Lines, 'Fiabilidade').Value, 'sem classificacao');
end;

procedure TSonarMeasuresTests.ProjectLinesHighlightWhatIsGood;
var
  Lines: TArray<TSonarLine>;
begin
  ParseProjectMeasures(ProjectJson, FSnap);
  Lines := SonarProjectLines(FSnap.Project);
  Assert.IsFalse(FindLine(Lines, 'Cobertura de testes').Good, '61 % nao chega a 80 %');
  Assert.IsTrue(FindLine(Lines, 'Duplicação').Good, '1,5 % e baixo');
  Assert.IsFalse(FindLine(Lines, 'Bugs').Good, 'ha bugs');
  Assert.IsTrue(FindLine(Lines, 'Segurança').Good, 'A');
  Assert.IsFalse(FindLine(Lines, 'Fiabilidade').Good, 'B nao e A');
end;

procedure TSonarMeasuresTests.FileTextJoinsWhatIsKnown;
var
  F: TSonarFile;
  Text: string;
begin
  F := NewSonarFile('a.pas');
  F.HasMeasures := True;
  F.Coverage := 80;
  F.DebtMin := 125;
  F.Cognitive := 9;
  Text := SonarFileText(F);
  Assert.IsTrue(Text.StartsWith('cobertura 80%'));
  Assert.IsTrue(Text.Contains('dívida 2h 5min'));
  Assert.IsTrue(Text.Contains('complexidade cognitiva 9'));
  Assert.IsFalse(Text.Contains('duplicação'), 'sem valor: nao aparece');
end;

procedure TSonarMeasuresTests.FileTextIsEmptyWithoutMeasures;
begin
  Assert.AreEqual('', SonarFileText(NewSonarFile('a.pas')));
end;

initialization
  TDUnitX.RegisterTestFixture(TSonarMeasuresTests);

end.
