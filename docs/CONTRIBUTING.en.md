# Contributing to CodeManager

Thanks for your interest in improving CodeManager! Issues and pull requests in English or Portuguese are welcome.

## Reporting a bug

Open an issue and include the observed behaviour, expected behaviour, reproduction steps, application version, Windows version, and whether you used a downloaded release or a local build. For project-specific issues, provide the smallest reproducible Delphi example you can share. Never publish private project code, personal data, credentials or SonarQube tokens.

## Suggesting a feature

Describe the underlying problem, its impact on a Delphi workflow and the expected outcome. For major work, open an issue first to discuss the approach.

## Sending a pull request

1. Fork the repository and create a branch from `master`.
2. Follow the [English build guide](INSTALLATION.en.md) to set up Delphi 13 and Chart4D.
3. Follow existing source conventions. Delphi `.pas` files are UTF-8 with BOM and CRLF; existing comments and UI strings follow Portuguese conventions.
4. Include or update DUnitX tests when changing logic in Core or Services.
5. Run `ci.bat` on a configured Windows/Delphi machine.
6. Update relevant documentation and `CHANGELOG.md` for user-visible changes.
7. Describe what changed, why it matters, and what testing you performed. Include screenshots for UI changes and check both themes.

Preserve architectural boundaries: Core depends on RTL; Services must not import UI. See [development conventions (Portuguese)](DESENVOLVIMENTO.md) for the authoritative details.

## Conduct and license

Be respectful and constructive. Contributions are submitted under the repository's [MIT License](../LICENSE).
