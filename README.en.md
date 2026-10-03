<div align="center">

# CodeManager

**Review, track and plan Delphi projects — folder by folder, file by file, method by method.**

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Delphi 13](https://img.shields.io/badge/Delphi-13-e62329.svg)](docs/DESENVOLVIMENTO.md)
[![Windows](https://img.shields.io/badge/platform-Windows-0078d4.svg)](docs/DESENVOLVIMENTO.md)
[![Português](https://img.shields.io/badge/README-Português-lightgrey.svg)](README.md)

![CodeManager: review checklist and progress dashboard](docs/images/hero.png)

</div>

CodeManager reads the units of a Delphi project and gives you a simple way to **see what you have**, **review what
has been looked at** and **follow progress over time** — without changing a single line of your code. If you have
a document describing what the project *should* contain, it compares the two.

> The application and most of the documentation are in **Portuguese**. This page is a short English summary.

## Features

- **Map** — the folder → file → method tree, with search, statistics and the **lines and complexity** of each method.
- **Checklist** — mark what you reviewed, what is under review or needs changes, what compiles, what passed Sonar, what is a priority; add notes.
  A file is *done* when **all its methods** are reviewed.
- **Dashboard** — numbers and charts for progress and code distribution, including day-by-day evolution.
- **Plan in Markdown** — write the intended structure (and code) in a `.md` file and see what is implemented,
  what is still missing (`PLANEADO`/planned) and what is extra (`EXTRA`). With no code folder, the document is
  analysed on its own, as if it were the code.
- **Follows your IDE** — re-analyses what you change as you save.
- **Exports** to Markdown, TXT, CSV, JSON, offline HTML pages and paper/PDF.
- **Light and dark themes.**

![Code map](docs/images/02-mapa.png)

![Plan × code comparison](docs/images/03-mapa-plano.png)

![Dashboard](docs/images/05-painel.png)

<sub>The evolution history in the screenshots is demo data; everything else is a real analysis of CodeManager's own source.</sub>

## Getting started

You need Windows 10/11 and, to build, **Delphi 13** with the **Chart4D** package (installed from GetIt).

```bat
git clone <repository-url>
cd CodeManager
build.bat
```

The executable is `out\bin\Win64\Release\CodeManager.exe` (a single file, no installer). Then, on the **Project**
page, name the project, pick its root folder and click **Analisar projeto** (*Analyse project*).

## How it works

```mermaid
flowchart LR
    C["Code folder<br/>.pas · .dpr · .dpk"] --> A["Analysis<br/>files → methods"]
    P["Plan .md<br/>(optional)"] --> A
    A --> V["Plan × code view"]
    V --> M["Map"]
    A --> K["Checklist"]
    A --> D["Dashboard"]
    K --> S[("Progress and history<br/>%APPDATA%")]
    D --> S
```

The analysis engine does not depend on the UI or on Windows; the FireMonkey interface is drawn in code and follows
the theme. The application **only reads** the project it analyses. Your progress is stored in
`%APPDATA%\CodeManager`.

## Documentation (Portuguese)

- [User guide](docs/GUIA-DO-UTILIZADOR.md)
- [Plan format](docs/FORMATO-DO-PLANO.md)
- [Architecture](docs/ARQUITETURA.md)
- [Development](docs/DESENVOLVIMENTO.md)
- [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE). Charts use [Chart4D](https://github.com/GDKsoftware/Chart4D) (MIT) — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
