# Promotion template — CodeManager 1.0.3 (English)

Ready-to-post material for **WhatsApp** and **Telegram** groups. Portuguese version: [`modelo-divulgacao.md`](modelo-divulgacao.md).

| File | Purpose |
|---|---|
| [`cartaz-1.0.3-en.png`](cartaz-1.0.3-en.png) | The image (1600 × 900) |
| This document | The texts, already formatted for each app |

> The screenshots in the image show the Portuguese interface (the app is also available in English, French and German).

## How to post

1. Send the **image** first and paste the **short caption** as its caption (fits both apps' limits).
2. If the group prefers text, send the **full message** without the image (or after it).
3. Pin the message in the group if you can.

> **Before posting**, check that the release link opens and that the group allows links and files.
> Formatting differs between the two apps — use the right block.

---

## WhatsApp

Formatting: `*bold*`, `_italic_`. Links become clickable on their own.

### Short caption (for the image)

```text
*CodeManager 1.0.3* 🚀
_Delphi source-code map and checklist_

New version! The software bill of materials (SBOM), still without changing a single line of your code.

✅ SBOM: the outside units the project uses, in CycloneDX and SPDX
✅ Where each one comes from (Embarcadero or third party) and how sure we are
✅ SHA-256 of the files found, without compiling
✅ Uses the .map file, if any, to confirm what ends up in the executable
✅ Report in HTML and Markdown, in 4 languages (PT · EN · FR · DE)

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
```

### Full message

```text
*CodeManager 1.0.3* 🚀
_Delphi source-code map and checklist_

Version 1.0.3 of *CodeManager* is out: the Windows app that reads the units of a Delphi project and helps you see what you have, review what has been looked at and track progress.

What's new:
• *SBOM* — a new page with the project's software bill of materials: the outside units it uses, where each comes from (Embarcadero or third party) and how sure we are, with the SHA-256 of the files;
• *Standard formats* — exports CycloneDX 1.5 and SPDX 2.3 (JSON), handy for audits and for the Cyber Resilience Act;
• *No compiling* — it starts from the source code and the .dproj, and uses the .map file, if any, to confirm what ends up in the executable;
• *Report* — in HTML (with a PT · EN · FR · DE switcher in the page) or Markdown, without the full paths of your folders.

CodeManager *never changes your code*. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
📖 Guide and source code: https://github.com/JFSF/CodeManager

_Note:_ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can check the file against the SHA-256 in the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## Telegram

Formatting: `**bold**`, `__italic__` (type the text with these symbols and Telegram applies the style). Links become clickable on their own.

### Short caption (for the image)

```text
**CodeManager 1.0.3** 🚀
__Delphi source-code map and checklist__

New version! The software bill of materials (SBOM), still without changing a single line of your code.

✅ SBOM: the outside units the project uses, in CycloneDX and SPDX
✅ Where each one comes from (Embarcadero or third party) and how sure we are
✅ SHA-256 of the files found, without compiling
✅ Uses the .map file, if any, to confirm what ends up in the executable
✅ Report in HTML and Markdown, in 4 languages (PT · EN · FR · DE)

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
```

### Full message

```text
**CodeManager 1.0.3** 🚀
__Delphi source-code map and checklist__

Version 1.0.3 of **CodeManager** is out: the Windows app that reads the units of a Delphi project and helps you see what you have, review what has been looked at and track progress.

What's new:
• **SBOM** — a new page with the project's software bill of materials: the outside units it uses, where each comes from (Embarcadero or third party) and how sure we are, with the SHA-256 of the files;
• **Standard formats** — exports CycloneDX 1.5 and SPDX 2.3 (JSON), handy for audits and for the Cyber Resilience Act;
• **No compiling** — it starts from the source code and the .dproj, and uses the .map file, if any, to confirm what ends up in the executable;
• **Report** — in HTML (with a PT · EN · FR · DE switcher in the page) or Markdown, without the full paths of your folders.

CodeManager **never changes your code**. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
📖 Guide and source code: https://github.com/JFSF/CodeManager

__Note:__ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can check the file against the SHA-256 in the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## For future versions

Replace `1.0.3` with the new number (in the caption, the text and the release link) and add the version's highlights —
the CHANGELOG has them. Remake the image with `python tools/make-cartaz.py <version> en` (and `pt`): edit the texts and
the two screenshots at the top of `tools/make-cartaz.py` (the screenshots come from `docs/images`).
