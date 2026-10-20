# Installation and build guide (English)

## Install the released application

CodeManager is a standalone Windows application, not a design-time component or RAD Studio extension.

1. Visit https://github.com/JFSF/CodeManager/releases/latest.
2. Download the Win64 `.exe` asset and the accompanying `SHA256SUMS.txt`.
3. Compare the executable checksum using `Get-FileHash .\CodeManager-1.0.4-win64.exe -Algorithm SHA256` (adjust the file name for newer releases).
4. Run the executable from a directory of your choice; no installer is required.
5. On the Project page, name a project, select its root folder and start the analysis.

**Runtime:** Windows 10/11 64-bit. Git, SVN, Mercurial and SonarQube are optional. The current published executable is unsigned; signing and Windows SmartScreen reputation are separate concerns. Do not bypass warnings unless you trust the official download and have verified its hash.

## Build from source

- RAD Studio / Delphi 13 with the Win64 compiler
- Windows 10/11
- Chart4D 1.2.0, installed using the RAD Studio GetIt Package Manager
- DUnitX (bundled with Delphi) for tests

```bat
git clone https://github.com/JFSF/CodeManager.git
cd CodeManager
build.bat Release Win64
```

Output: `out\bin\Win64\Release\CodeManager.exe`.

`build.bat` defaults to a Delphi installation at `C:\Program Files (x86)\Embarcadero\Studio\37.0`; override with `CM_RSVARS` pointing to another `rsvars.bat` if needed. The `.dproj` defaults to Chart4D under `%USERPROFILE%\Documents\Embarcadero\Studio\37.0\CatalogRepository\Chart4D-13\1.2.0`. If Chart4D is elsewhere, set `Chart4DDir` to its root folder (the one containing `Source`).

Chart4D is compiled into the executable from source and is **not an additional runtime package** required by users of the published binary.

## Tests

```bat
tests\run-tests.bat
ci.bat
```

`ci.bat` builds the Win64 Release executable and runs the test suite; optional `ci.bat sonar` runs SonarQube analysis if configured. The repository also contains a GitHub Actions workflow intended for a self-hosted Windows runner with Delphi installed. Tests and compilation have **not** been independently executed as part of this documentation change.

## Configuration and data

CodeManager stores application progress and preferences in `%APPDATA%\CodeManager`. The analysed project source is read-only; the application may use optional local VCS programs and optional SonarQube requests if configured. For full details see the [Portuguese development guide](DESENVOLVIMENTO.md) and [user guide](GUIA-DO-UTILIZADOR.md).
