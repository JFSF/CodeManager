# Plano do CodeManager

Estrutura prevista em camadas.

## src/Core/CM.Analyzer.pas

```pascal
unit CM.Analyzer;

interface

function ScanProject(const ARoot: string; const AExclude: TArray<string>;
  const AProgress: TScanProgress = nil): TProjectScan;
function ExtractMethodsFromText(const AText: string): TArray<TMethodInfo>;
procedure SincronizarComGit;

implementation
end.
```

## src/Core/CM.Plan.pas

- `function ParsePlan(const AText: string): TProjectScan;`
- `function MergePlan(ACode, APlan: TProjectScan): TProjectScan;`

## Resto da estrutura

```text
src/
├── Services/
│   ├── CM.Export.pas
│   └── CM.Pdf.pas        # exportação direta para PDF
└── UI/
    └── CM.MainForm.pas
```
