# Modelo de divulgação — CodeManager 1.0.1

Material pronto para publicar nos grupos de **WhatsApp** e **Telegram**.

| Ficheiro | Para quê |
|---|---|
| [`cartaz-1.0.1.png`](cartaz-1.0.1.png) | A imagem (1600 × 900) |
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
*CodeManager 1.0.1* 🚀
_Mapa e checklist de código-fonte Delphi_

Nova versão! Novas páginas e mais integrações, sempre sem alterar uma linha do teu código.

✅ Grafo: quem usa quem entre as units, com ciclos e relatório
✅ Código: lê o ficheiro (ou o método) com duplo clique, com realce e ligaduras
✅ SonarQube: cobertura, dívida técnica e problemas na margem das linhas
✅ Git e Subversion: avisa o que mudou desde a revisão
✅ Aspeto à tua maneira e em 4 idiomas (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.1
```

### Mensagem completa

```text
*CodeManager 1.0.1* 🚀
_Mapa e checklist de código-fonte Delphi_

Já está disponível a versão 1.0.1 do *CodeManager*, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• *Grafo* — o mapa de dependências entre as units (quem usa quem), com acoplamento, ciclos e relatório em HTML ou Markdown;
• *Código* — um duplo clique num ficheiro ou método abre o código para leitura, em separadores, com realce Delphi, salto para o método e fonte moderna com ligaduras;
• *SonarQube* — cobertura, duplicação, dívida técnica e classificações A–E, mais os problemas e hotspots na margem das linhas (continua a ser opcional);
• *Subversion* — o aviso «mudou desde a revisão» funciona agora também em cópias de trabalho do Subversion, além do Git;
• *Aspeto* — escolhe a cor de destaque, as fontes e o tamanho do texto;
• *Idiomas* — português, inglês, francês e alemão;
• mais métricas por método (parâmetros e aninhamento), repositórios do GitHub e uma página *Acerca*.

O CodeManager *não altera o teu código*. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.1
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

_Nota:_ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Telegram

Formatação: `**negrito**`, `__itálico__` (escreve o texto com estes símbolos e o Telegram aplica o estilo). As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
**CodeManager 1.0.1** 🚀
__Mapa e checklist de código-fonte Delphi__

Nova versão! Novas páginas e mais integrações, sempre sem alterar uma linha do teu código.

✅ Grafo: quem usa quem entre as units, com ciclos e relatório
✅ Código: lê o ficheiro (ou o método) com duplo clique, com realce e ligaduras
✅ SonarQube: cobertura, dívida técnica e problemas na margem das linhas
✅ Git e Subversion: avisa o que mudou desde a revisão
✅ Aspeto à tua maneira e em 4 idiomas (PT · EN · FR · DE)

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.1
```

### Mensagem completa

```text
**CodeManager 1.0.1** 🚀
__Mapa e checklist de código-fonte Delphi__

Já está disponível a versão 1.0.1 do **CodeManager**, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• **Grafo** — o mapa de dependências entre as units (quem usa quem), com acoplamento, ciclos e relatório em HTML ou Markdown;
• **Código** — um duplo clique num ficheiro ou método abre o código para leitura, em separadores, com realce Delphi, salto para o método e fonte moderna com ligaduras;
• **SonarQube** — cobertura, duplicação, dívida técnica e classificações A–E, mais os problemas e hotspots na margem das linhas (continua a ser opcional);
• **Subversion** — o aviso «mudou desde a revisão» funciona agora também em cópias de trabalho do Subversion, além do Git;
• **Aspeto** — escolhe a cor de destaque, as fontes e o tamanho do texto;
• **Idiomas** — português, inglês, francês e alemão;
• mais métricas por método (parâmetros e aninhamento), repositórios do GitHub e uma página **Acerca**.

O CodeManager **não altera o teu código**. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.1
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

__Nota:__ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Para as próximas versões

Troca `1.0.1` pelo número novo (na legenda, no texto e na ligação da release) e acrescenta as novidades da versão — o
CHANGELOG tem-nas. O cartaz refaz-se com `python tools/make-cartaz.py <versão> pt` (e `en`): edita os textos e as duas
capturas no início do `tools/make-cartaz.py` (as capturas vêm de `docs/images`).
