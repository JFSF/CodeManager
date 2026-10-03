program CodeManagerTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  CM.Analyzer in '..\src\Core\CM.Analyzer.pas',
  CM.Store in '..\src\Core\CM.Store.pas',
  CM.Stats in '..\src\Core\CM.Stats.pas',
  CM.History in '..\src\Core\CM.History.pas',
  CM.SafeFile in '..\src\Core\CM.SafeFile.pas',
  CM.Metrics in '..\src\Core\CM.Metrics.pas',
  CM.SonarModel in '..\src\Core\CM.SonarModel.pas',
  CM.Git in '..\src\Infrastructure\CM.Git.pas',
  CM.Secrets in '..\src\Infrastructure\CM.Secrets.pas',
  CM.Sonar in '..\src\Infrastructure\CM.Sonar.pas',
  CM.GitReview in '..\src\Services\CM.GitReview.pas',
  CM.Plan in '..\src\Core\CM.Plan.pas',
  CM.Export in '..\src\Services\CM.Export.pas',
  CM.Print in '..\src\Services\CM.Print.pas',
  CM.Resources in '..\src\Infrastructure\CM.Resources.pas',
  CM.Html in '..\src\Services\CM.Html.pas',
  CM.Watcher in '..\src\Infrastructure\CM.Watcher.pas',
  Tests.Helpers in 'Tests.Helpers.pas',
  Tests.Analyzer.Extract in 'Tests.Analyzer.Extract.pas',
  Tests.Analyzer.Scan in 'Tests.Analyzer.Scan.pas',
  Tests.Stats in 'Tests.Stats.pas',
  Tests.Store in 'Tests.Store.pas',
  Tests.Export.Fixtures in 'Tests.Export.Fixtures.pas',
  Tests.Export.Structure in 'Tests.Export.Structure.pas',
  Tests.Export.Formats in 'Tests.Export.Formats.pas',
  Tests.Export.Disk in 'Tests.Export.Disk.pas',
  Tests.Print.WrapLine in 'Tests.Print.WrapLine.pas',
  Tests.Print.Doc in 'Tests.Print.Doc.pas',
  Tests.Architecture in 'Tests.Architecture.pas',
  Tests.Html in 'Tests.Html.pas',
  Tests.Watcher in 'Tests.Watcher.pas',
  Tests.History in 'Tests.History.pas',
  Tests.Plan in 'Tests.Plan.pas',
  Tests.SafeFile in 'Tests.SafeFile.pas',
  Tests.Metrics in 'Tests.Metrics.pas',
  Tests.Review in 'Tests.Review.pas',
  Tests.Git in 'Tests.Git.pas',
  Tests.Sonar in 'Tests.Sonar.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := 1;
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 2;
    end;
  end;
end.
