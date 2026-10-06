# Modelo de divulgação — CodeManager 1.0.3

Material pronto para publicar nos grupos de **WhatsApp** e **Telegram**.

| Ficheiro | Para quê |
|---|---|
| [`cartaz-1.0.3.png`](cartaz-1.0.3.png) | A imagem (1600 × 900) |
| Este documento | Os textos, já com a formatação de cada aplicação |

## Como publicar

1. Envia primeiro a **imagem** e cola a **legenda curta** na legenda (cabe nos limites das duas aplicações).
2. Se o grupo preferir texto, envia a **mensagem completa** sem imagem (ou depois dela).
3. Fixa a mensagem no grupo, se puderes.

> **Antes de publicar**, confirma que a ligação da release abre e que o grupo permite ligações e ficheiros.
> A formatação é diferente nas duas aplicações — usa o bloco certo.

---

## WhatsApp

Formatação: `*negrito*`, `_itálico_`. As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
*CodeManager 1.0.3* 🚀
_Mapa e checklist de código-fonte Delphi_

Nova versão! A lista de materiais de software (SBOM), sempre sem alterar uma linha do teu código.

✅ SBOM: as units de fora que o projeto usa, em CycloneDX e SPDX
✅ De onde vem cada uma (Embarcadero ou terceiros) e com que confiança
✅ SHA-256 dos ficheiros achados, sem compilar
✅ Usa o ficheiro .map, se existir, para confirmar o que fica no executável
✅ Relatório em HTML e Markdown, em 4 idiomas (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
```

### Mensagem completa

```text
*CodeManager 1.0.3* 🚀
_Mapa e checklist de código-fonte Delphi_

Já está disponível a versão 1.0.3 do *CodeManager*, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• *SBOM* — uma página nova com a lista de materiais de software do projeto: as units de fora que usa, a origem de cada uma (Embarcadero ou terceiros) e a confiança, com o SHA-256 dos ficheiros;
• *Formatos padrão* — exporta CycloneDX 1.5 e SPDX 2.3 (JSON), úteis para auditorias e para o Cyber Resilience Act;
• *Sem compilar* — parte do código-fonte e do .dproj, e usa o ficheiro .map, se existir, para confirmar o que fica no executável;
• *Relatório* — em HTML (com seletor PT · EN · FR · DE na própria página) ou Markdown, sem caminhos completos das tuas pastas.

O CodeManager *não altera o teu código*. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

_Nota:_ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Telegram

Formatação: `**negrito**`, `__itálico__` (escreve o texto com estes símbolos e o Telegram aplica o estilo). As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
**CodeManager 1.0.3** 🚀
__Mapa e checklist de código-fonte Delphi__

Nova versão! A lista de materiais de software (SBOM), sempre sem alterar uma linha do teu código.

✅ SBOM: as units de fora que o projeto usa, em CycloneDX e SPDX
✅ De onde vem cada uma (Embarcadero ou terceiros) e com que confiança
✅ SHA-256 dos ficheiros achados, sem compilar
✅ Usa o ficheiro .map, se existir, para confirmar o que fica no executável
✅ Relatório em HTML e Markdown, em 4 idiomas (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
```

### Mensagem completa

```text
**CodeManager 1.0.3** 🚀
__Mapa e checklist de código-fonte Delphi__

Já está disponível a versão 1.0.3 do **CodeManager**, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• **SBOM** — uma página nova com a lista de materiais de software do projeto: as units de fora que usa, a origem de cada uma (Embarcadero ou terceiros) e a confiança, com o SHA-256 dos ficheiros;
• **Formatos padrão** — exporta CycloneDX 1.5 e SPDX 2.3 (JSON), úteis para auditorias e para o Cyber Resilience Act;
• **Sem compilar** — parte do código-fonte e do .dproj, e usa o ficheiro .map, se existir, para confirmar o que fica no executável;
• **Relatório** — em HTML (com seletor PT · EN · FR · DE na própria página) ou Markdown, sem caminhos completos das tuas pastas.

O CodeManager **não altera o teu código**. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.3
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

__Nota:__ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Para as próximas versões

Troca `1.0.3` pelo número novo (na legenda, no texto e na ligação da release) e acrescenta as novidades da versão — o
CHANGELOG tem-nas. O cartaz refaz-se com `python tools/make-cartaz.py <versão> pt` (e `en`): edita os textos e as duas
capturas no início do `tools/make-cartaz.py` (as capturas vêm de `docs/images`).
