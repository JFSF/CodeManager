program CodeManager;

uses
  System.StartUpCopy,
  FMX.Forms,
  CM.Analyzer in 'src\Core\CM.Analyzer.pas',
  CM.Store in 'src\Core\CM.Store.pas',
  CM.Stats in 'src\Core\CM.Stats.pas',
  CM.Html in 'src\Services\CM.Html.pas',
  CM.Export in 'src\Services\CM.Export.pas',
  CM.Print in 'src\Services\CM.Print.pas',
  CM.Watcher in 'src\Infrastructure\CM.Watcher.pas',
  CM.Resources in 'src\Infrastructure\CM.Resources.pas',
  CM.Theme in 'src\UI\CM.Theme.pas',
  CM.Controls in 'src\UI\CM.Controls.pas',
  CM.TreeList in 'src\UI\CM.TreeList.pas',
  CM.Layouts in 'src\UI\CM.Layouts.pas',
  CM.Pages.Host in 'src\UI\Pages\CM.Pages.Host.pas',
  CM.Pages.Project in 'src\UI\Pages\CM.Pages.Project.pas',
  CM.Pages.Map in 'src\UI\Pages\CM.Pages.Map.pas',
  CM.Pages.Checklist in 'src\UI\Pages\CM.Pages.Checklist.pas',
  CM.Pages.Dashboard in 'src\UI\Pages\CM.Pages.Dashboard.pas',
  CM.MainForm in 'src\UI\CM.MainForm.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
