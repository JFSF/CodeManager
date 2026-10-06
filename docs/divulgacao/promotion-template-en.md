# Promotion template — CodeManager 1.0.2 (English)

Ready-to-post material for **WhatsApp** and **Telegram** groups. Portuguese version: [`modelo-divulgacao.md`](modelo-divulgacao.md).

| File | Purpose |
|---|---|
| [`cartaz-1.0.2-en.png`](cartaz-1.0.2-en.png) | The image (1600 × 900) |
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
*CodeManager 1.0.2* 🚀
_Delphi source-code map and checklist_

New version! More metrics and Mercurial, still without changing a single line of your code.

✅ Cognitive complexity: how hard each method is to read
✅ Parameters and nesting on the Map, the HTML pages and the Dashboard
✅ Mercurial, besides Git and Subversion: what changed since the review
✅ Dependency report that switches language inside the page
✅ German and French reviewed page by page (PT · EN · FR · DE)

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
```

### Full message

```text
*CodeManager 1.0.2* 🚀
_Delphi source-code map and checklist_

Version 1.0.2 of *CodeManager* is out: the Windows app that reads the units of a Delphi project and helps you see what you have, review what has been looked at and track progress.

What's new:
• *Mercurial* — the «changed since review» flag now also works in Mercurial repositories (with the command-line hg, for example the one from TortoiseHg), besides Git and Subversion;
• *Cognitive complexity* — a new per-method measure (cg) of how hard the code is to _read_, not just how many paths it has; on the Map, the Checklist, the Dashboard and the exports;
• *Parameters and nesting* — now also next to the lines and complexity on the Map, in the exported HTML pages and in two new Dashboard charts;
• *Dependency report* — the HTML page switches between Portuguese, English, French and German without reloading;
• *Languages reviewed* — cut-off buttons, chart months and untranslated text fixed in German and French.

CodeManager *never changes your code*. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
📖 Guide and source code: https://github.com/JFSF/CodeManager

_Note:_ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can check the file against the SHA-256 in the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## Telegram

Formatting: `**bold**`, `__italic__` (type the text with these symbols and Telegram applies the style). Links become clickable on their own.

### Short caption (for the image)

```text
**CodeManager 1.0.2** 🚀
__Delphi source-code map and checklist__

New version! More metrics and Mercurial, still without changing a single line of your code.

✅ Cognitive complexity: how hard each method is to read
✅ Parameters and nesting on the Map, the HTML pages and the Dashboard
✅ Mercurial, besides Git and Subversion: what changed since the review
✅ Dependency report that switches language inside the page
✅ German and French reviewed page by page (PT · EN · FR · DE)

🪟 Windows 10/11 · free · open source
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
```

### Full message

```text
**CodeManager 1.0.2** 🚀
__Delphi source-code map and checklist__

Version 1.0.2 of **CodeManager** is out: the Windows app that reads the units of a Delphi project and helps you see what you have, review what has been looked at and track progress.

What's new:
• **Mercurial** — the «changed since review» flag now also works in Mercurial repositories (with the command-line hg, for example the one from TortoiseHg), besides Git and Subversion;
• **Cognitive complexity** — a new per-method measure (cg) of how hard the code is to __read__, not just how many paths it has; on the Map, the Checklist, the Dashboard and the exports;
• **Parameters and nesting** — now also next to the lines and complexity on the Map, in the exported HTML pages and in two new Dashboard charts;
• **Dependency report** — the HTML page switches between Portuguese, English, French and German without reloading;
• **Languages reviewed** — cut-off buttons, chart months and untranslated text fixed in German and French.

CodeManager **never changes your code**. It is a single file, no installer.

⬇️ Download: https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
📖 Guide and source code: https://github.com/JFSF/CodeManager

__Note:__ the executable is not signed, so Windows may show a SmartScreen warning the first time ("More info" → "Run anyway"). You can check the file against the SHA-256 in the release.

Suggestions and bug reports are very welcome! 🙏
```

---

## For future versions

Replace `1.0.2` with the new number (in the caption, the text and the release link) and add the version's highlights —
the CHANGELOG has them. Remake the image with `python tools/make-cartaz.py <version> en` (and `pt`): edit the texts and
the two screenshots at the top of `tools/make-cartaz.py` (the screenshots come from `docs/images`).
