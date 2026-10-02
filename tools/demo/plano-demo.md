# Plano de demonstração — CodeManager

Este documento descreve a estrutura prevista do próprio CodeManager e serve para mostrar o cruzamento
**plano × código** (ver `docs/FORMATO-DO-PLANO.md`). De propósito:

- `src/Services/CM.Pdf.pas` e `src/Services/CM.Git.pas` estão no plano mas **ainda não existem** (aparecem como `PLANEADO`);
- `src/Infrastructure/CM.Resources.pas` existe no código mas **não está** no plano (aparece como `EXTRA`);
- `CM.Plan` tem um método planeado que ainda não foi escrito.

## Árvore de ficheiros

```text
CodeManager/
├── src/
│   ├── Core/
│   │   ├── CM.Analyzer.pas
│   │   ├── CM.History.pas
│   │   ├── CM.Plan.pas
│   │   ├── CM.Stats.pas
│   │   └── CM.Store.pas
│   ├── Infrastructure/
│   │   └── CM.Watcher.pas
│   ├── Services/
│   │   ├── CM.Export.pas
│   │   ├── CM.Git.pas
│   │   ├── CM.Html.pas
│   │   ├── CM.Pdf.pas
│   │   └── CM.Print.pas
│   └── UI/
│       ├── Pages/
│       │   ├── CM.Pages.Checklist.pas
│       │   ├── CM.Pages.Dashboard.pas
│       │   ├── CM.Pages.Host.pas
│       │   ├── CM.Pages.Map.pas
│       │   └── CM.Pages.Project.pas
│       ├── CM.Controls.pas
│       ├── CM.Layouts.pas
│       ├── CM.MainForm.pas
│       ├── CM.Theme.pas
│       └── CM.TreeList.pas
├── tests/
│   ├── CodeManagerTests.dpr
│   ├── Tests.Analyzer.Extract.pas
│   ├── Tests.Analyzer.Scan.pas
│   ├── Tests.Architecture.pas
│   ├── Tests.Export.Disk.pas
│   ├── Tests.Export.Fixtures.pas
│   ├── Tests.Export.Formats.pas
│   ├── Tests.Export.Structure.pas
│   ├── Tests.Helpers.pas
│   ├── Tests.History.pas
│   ├── Tests.Html.pas
│   ├── Tests.Plan.pas
│   ├── Tests.Print.Doc.pas
│   ├── Tests.Print.WrapLine.pas
│   ├── Tests.Stats.pas
│   ├── Tests.Store.pas
│   └── Tests.Watcher.pas
└── CodeManager.dpr
```

## src/Services/CM.Pdf.pas

Exportação direta para PDF, sem passar pela impressora «Microsoft Print to PDF».

```pascal
unit CM.Pdf;

interface

function ExportStructurePdf(AProfile: TProjectProfile; AScan: TProjectScan;
  const AFileName: string): Boolean;
procedure SetPdfPageSize(AWidthMm, AHeightMm: Single);

implementation
end.
```

## src/Services/CM.Git.pas

- `function ChangedSince(const ARoot, ATag: string): TArray<string>;`
- `function LastCommitOf(const ARoot, ARelPath: string): string;`

## src/Core/CM.Plan.pas

- `function ParsePlan(const AText: string; out AWarnings: TArray<string>): TProjectScan;`
- `function LoadPlanFile(const AFileName: string; out AWarnings: TArray<string>): TProjectScan;`
- `function MergePlan(ACode, APlan: TProjectScan; out ASummary: TPlanSummary): TProjectScan;`
- `function ExportPlanTemplate(AScan: TProjectScan): string;`
