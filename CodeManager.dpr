program CodeManager;

uses
  System.StartUpCopy,
  FMX.Forms,
  CM.Lang.Table in 'src\Core\CM.Lang.Table.pas',
  CM.Lang in 'src\Core\CM.Lang.pas',
  CM.Analyzer in 'src\Core\CM.Analyzer.pas',
  CM.Deps in 'src\Core\CM.Deps.pas',
  CM.Highlight in 'src\Core\CM.Highlight.pas',
  CM.Colors in 'src\Core\CM.Colors.pas',
  CM.AppInfo in 'src\Core\CM.AppInfo.pas',
  CM.SafeFile in 'src\Core\CM.SafeFile.pas',
  CM.Metrics in 'src\Core\CM.Metrics.pas',
  CM.SonarModel in 'src\Core\CM.SonarModel.pas',
  CM.Proc in 'src\Infrastructure\CM.Proc.pas',
  CM.Git in 'src\Infrastructure\CM.Git.pas',
  CM.Svn in 'src\Infrastructure\CM.Svn.pas',
  CM.Hg in 'src\Infrastructure\CM.Hg.pas',
  CM.WidthShare in 'src\Core\CM.WidthShare.pas',
  CM.Vcs in 'src\Infrastructure\CM.Vcs.pas',
  CM.SysInfo in 'src\Infrastructure\CM.SysInfo.pas',
  CM.GitHub in 'src\Infrastructure\CM.GitHub.pas',
  CM.Secrets in 'src\Infrastructure\CM.Secrets.pas',
  CM.Sonar in 'src\Infrastructure\CM.Sonar.pas',
  CM.GitReview in 'src\Services\CM.GitReview.pas',
  CM.Store in 'src\Core\CM.Store.pas',
  CM.Stats in 'src\Core\CM.Stats.pas',
  CM.Html in 'src\Services\CM.Html.pas',
  CM.Export in 'src\Services\CM.Export.pas',
  CM.DepsReport in 'src\Services\CM.DepsReport.pas',
  CM.Print in 'src\Services\CM.Print.pas',
  CM.Watcher in 'src\Infrastructure\CM.Watcher.pas',
  CM.Resources in 'src\Infrastructure\CM.Resources.pas',
  CM.Theme in 'src\UI\CM.Theme.pas',
  CM.Controls in 'src\UI\CM.Controls.pas',
  CM.TreeList in 'src\UI\CM.TreeList.pas',
  CM.GraphView in 'src\UI\CM.GraphView.pas',
  CM.Clicks in 'src\UI\CM.Clicks.pas',
  CM.CodeView in 'src\UI\CM.CodeView.pas',
  CM.Layouts in 'src\UI\CM.Layouts.pas',
  CM.Pages.Host in 'src\UI\Pages\CM.Pages.Host.pas',
  CM.Pages.Project in 'src\UI\Pages\CM.Pages.Project.pas',
  CM.Pages.Map in 'src\UI\Pages\CM.Pages.Map.pas',
  CM.Pages.Checklist in 'src\UI\Pages\CM.Pages.Checklist.pas',
  CM.Pages.Dashboard in 'src\UI\Pages\CM.Pages.Dashboard.pas',
  CM.Pages.Graph in 'src\UI\Pages\CM.Pages.Graph.pas',
  CM.Pages.Code in 'src\UI\Pages\CM.Pages.Code.pas',
  CM.Pages.Appearance in 'src\UI\Pages\CM.Pages.Appearance.pas',
  CM.Pages.About in 'src\UI\Pages\CM.Pages.About.pas',
  CM.MainForm in 'src\UI\CM.MainForm.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
