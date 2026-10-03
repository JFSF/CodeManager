# Promotion template — CodeManager 1.0.0 (English)

Ready-to-post material for **WhatsApp** and **Telegram** groups. Portuguese version: [`modelo-divulgacao.md`](modelo-divulgacao.md).

| File | Purpose |
|---|---|
| [`cartaz-1.0.0-en.png`](cartaz-1.0.0-en.png) | The image (1600 × 900) |
| This document | The texts, already formatted for each app |

> The screenshots in the image show the Portuguese interface (the app is currently available in Portuguese only).

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
*CodeManager 1.0.0* 🚀
_Delphi source-code map and checklist_

The first public release is out! It reads the units of your Delphi project and helps you see what you have, review what has been looked at and track progress, without changing a single line of code.

✅ Folders → files → methods map, with lines and complexity
✅ Checklist with review states (to review, in review, needs change, done)
✅ Flags when a file changed since it was reviewed (Git)
✅ Optional SonarQube: open issues per file
✅ Compares the code with a Markdown plan

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
```

### Full message

```text
*CodeManager 1.0.0* 🚀
_Delphi source-code map and checklist_

The first public release of *CodeManager* is here: a Windows app that reads the units of a Delphi project and gives you a simple way to:

• *see what you have* — folders, files and methods, with the lines and complexity of each method;
• *review what has been seen* — a checklist with states (to review, in review, needs change, done), Compiles, Sonar, priority and notes;
• *track progress* — a dashboard with charts and day-by-day evolution.

Also:
• flags when a file you already reviewed has changed since (uses Git, read-only);
• connects to SonarQube *if you want* — it is optional and each user decides; the token is stored encrypted;
• compares the code with a Markdown plan (what is done, what is missing, what is extra);
• exports to Markdown, CSV, JSON, offline HTML pages and PDF.

CodeManager *never changes your code*. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
📖 Guide and source code: https://github.com/JFSF/CodeManager

_Note:_ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can verify the file with the SHA-256 published on the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## Telegram

Formatting: `**bold**`, `__italic__` (type the text with these symbols and Telegram applies the style). Links become clickable on their own.

### Short caption (for the image)

```text
**CodeManager 1.0.0** 🚀
__Delphi source-code map and checklist__

The first public release is out! It reads the units of your Delphi project and helps you see what you have, review what has been looked at and track progress, without changing a single line of code.

✅ Folders → files → methods map, with lines and complexity
✅ Checklist with review states (to review, in review, needs change, done)
✅ Flags when a file changed since it was reviewed (Git)
✅ Optional SonarQube: open issues per file
✅ Compares the code with a Markdown plan

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
```

### Full message

```text
**CodeManager 1.0.0** 🚀
__Delphi source-code map and checklist__

The first public release of **CodeManager** is here: a Windows app that reads the units of a Delphi project and gives you a simple way to:

• **see what you have** — folders, files and methods, with the lines and complexity of each method;
• **review what has been seen** — a checklist with states (to review, in review, needs change, done), Compiles, Sonar, priority and notes;
• **track progress** — a dashboard with charts and day-by-day evolution.

Also:
• flags when a file you already reviewed has changed since (uses Git, read-only);
• connects to SonarQube __if you want__ — it is optional and each user decides; the token is stored encrypted;
• compares the code with a Markdown plan (what is done, what is missing, what is extra);
• exports to Markdown, CSV, JSON, offline HTML pages and PDF.

CodeManager **never changes your code**. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
📖 Guide and source code: https://github.com/JFSF/CodeManager

__Note:__ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can verify the file with the SHA-256 published on the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## For future versions

Replace `1.0.0` with the new number (in the caption, the text and the release link) and, instead of the general list,
add the version's highlights — the CHANGELOG has them. The image can be remade from the screenshots in `docs/images`.
