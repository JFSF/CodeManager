# Modelo de divulgação — CodeManager 1.0.2

Material pronto para publicar nos grupos de **WhatsApp** e **Telegram**.

| Ficheiro | Para quê |
|---|---|
| [`cartaz-1.0.2.png`](cartaz-1.0.2.png) | A imagem (1600 × 900) |
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
*CodeManager 1.0.2* 🚀
_Mapa e checklist de código-fonte Delphi_

Nova versão! Mais métricas e o Mercurial, sempre sem alterar uma linha do teu código.

✅ Complexidade cognitiva: mede o esforço de ler cada método
✅ Parâmetros e aninhamento no Mapa, nas páginas HTML e no Painel
✅ Mercurial, além do Git e do Subversion: o que mudou desde a revisão
✅ Relatório de dependências que muda de idioma na própria página
✅ Alemão e francês revistos página a página (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
```

### Mensagem completa

```text
*CodeManager 1.0.2* 🚀
_Mapa e checklist de código-fonte Delphi_

Já está disponível a versão 1.0.2 do *CodeManager*, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• *Mercurial* — o aviso «mudou desde a revisão» funciona agora também em repositórios Mercurial (com o hg da linha de comandos, por exemplo o do TortoiseHg), além do Git e do Subversion;
• *Complexidade cognitiva* — uma medida nova por método (cg) do esforço de _ler_ o código, e não só dos caminhos que tem; no Mapa, na Checklist, no Painel e nas exportações;
• *Parâmetros e aninhamento* — agora também ao lado das linhas e da complexidade no Mapa, nas páginas HTML exportadas e em dois gráficos novos do Painel;
• *Relatório de dependências* — a página HTML troca entre português, inglês, francês e alemão sem recarregar;
• *Idiomas revistos* — botões cortados, meses dos gráficos e textos por traduzir corrigidos em alemão e francês.

O CodeManager *não altera o teu código*. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

_Nota:_ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Telegram

Formatação: `**negrito**`, `__itálico__` (escreve o texto com estes símbolos e o Telegram aplica o estilo). As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
**CodeManager 1.0.2** 🚀
__Mapa e checklist de código-fonte Delphi__

Nova versão! Mais métricas e o Mercurial, sempre sem alterar uma linha do teu código.

✅ Complexidade cognitiva: mede o esforço de ler cada método
✅ Parâmetros e aninhamento no Mapa, nas páginas HTML e no Painel
✅ Mercurial, além do Git e do Subversion: o que mudou desde a revisão
✅ Relatório de dependências que muda de idioma na própria página
✅ Alemão e francês revistos página a página (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
```

### Mensagem completa

```text
**CodeManager 1.0.2** 🚀
__Mapa e checklist de código-fonte Delphi__

Já está disponível a versão 1.0.2 do **CodeManager**, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• **Mercurial** — o aviso «mudou desde a revisão» funciona agora também em repositórios Mercurial (com o hg da linha de comandos, por exemplo o do TortoiseHg), além do Git e do Subversion;
• **Complexidade cognitiva** — uma medida nova por método (cg) do esforço de __ler__ o código, e não só dos caminhos que tem; no Mapa, na Checklist, no Painel e nas exportações;
• **Parâmetros e aninhamento** — agora também ao lado das linhas e da complexidade no Mapa, nas páginas HTML exportadas e em dois gráficos novos do Painel;
• **Relatório de dependências** — a página HTML troca entre português, inglês, francês e alemão sem recarregar;
• **Idiomas revistos** — botões cortados, meses dos gráficos e textos por traduzir corrigidos em alemão e francês.

O CodeManager **não altera o teu código**. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.2
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

__Nota:__ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Para as próximas versões

Troca `1.0.2` pelo número novo (na legenda, no texto e na ligação da release) e acrescenta as novidades da versão — o
CHANGELOG tem-nas. O cartaz refaz-se com `python tools/make-cartaz.py <versão> pt` (e `en`): edita os textos e as duas
capturas no início do `tools/make-cartaz.py` (as capturas vêm de `docs/images`).
