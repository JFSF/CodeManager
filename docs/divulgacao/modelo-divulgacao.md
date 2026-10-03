# Modelo de divulgação — CodeManager 1.0.0

Material pronto para publicar nos grupos de **WhatsApp** e **Telegram**.

| Ficheiro | Para quê |
|---|---|
| [`cartaz-1.0.0.png`](cartaz-1.0.0.png) | A imagem (1600 × 900) |
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
*CodeManager 1.0.0* 🚀
_Mapa e checklist de código-fonte Delphi_

Já saiu a primeira versão pública! Lê as units do teu projeto Delphi e ajuda-te a ver o que tens, rever o que já foi visto e acompanhar o progresso, sem alterar uma linha do código.

✅ Mapa pastas → ficheiros → métodos, com linhas e complexidade
✅ Checklist com estados de revisão (por rever, em revisão, a alterar, concluído)
✅ Avisa quando um ficheiro mudou desde a revisão (Git)
✅ SonarQube opcional: problemas abertos por ficheiro
✅ Compara o código com um plano em Markdown

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
```

### Mensagem completa

```text
*CodeManager 1.0.0* 🚀
_Mapa e checklist de código-fonte Delphi_

Já está disponível a primeira versão pública do *CodeManager*, uma aplicação para Windows que lê as units de um projeto Delphi e te dá uma forma simples de:

• *ver o que tens* — pastas, ficheiros e métodos, com as linhas e a complexidade de cada método;
• *rever o que já foi visto* — checklist com estados (por rever, em revisão, precisa de alteração, concluído), Compila, Sonar, prioridade e notas;
• *acompanhar o progresso* — painel com gráficos e evolução dia a dia.

Também:
• avisa quando um ficheiro que já revistes mudou desde então (usa o Git, só em leitura);
• liga ao SonarQube *se quiseres* — é opcional e cada utilizador decide; o token fica cifrado;
• compara o código com um plano em Markdown (o que está feito, o que falta, o que sobra);
• exporta para Markdown, CSV, JSON, páginas HTML offline e PDF.

O CodeManager *não altera o teu código*. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

_Nota:_ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Telegram

Formatação: `**negrito**`, `__itálico__` (escreve o texto com estes símbolos e o Telegram aplica o estilo). As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
**CodeManager 1.0.0** 🚀
__Mapa e checklist de código-fonte Delphi__

Já saiu a primeira versão pública! Lê as units do teu projeto Delphi e ajuda-te a ver o que tens, rever o que já foi visto e acompanhar o progresso, sem alterar uma linha do código.

✅ Mapa pastas → ficheiros → métodos, com linhas e complexidade
✅ Checklist com estados de revisão (por rever, em revisão, a alterar, concluído)
✅ Avisa quando um ficheiro mudou desde a revisão (Git)
✅ SonarQube opcional: problemas abertos por ficheiro
✅ Compara o código com um plano em Markdown

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
```

### Mensagem completa

```text
**CodeManager 1.0.0** 🚀
__Mapa e checklist de código-fonte Delphi__

Já está disponível a primeira versão pública do **CodeManager**, uma aplicação para Windows que lê as units de um projeto Delphi e te dá uma forma simples de:

• **ver o que tens** — pastas, ficheiros e métodos, com as linhas e a complexidade de cada método;
• **rever o que já foi visto** — checklist com estados (por rever, em revisão, precisa de alteração, concluído), Compila, Sonar, prioridade e notas;
• **acompanhar o progresso** — painel com gráficos e evolução dia a dia.

Também:
• avisa quando um ficheiro que já revistes mudou desde então (usa o Git, só em leitura);
• liga ao SonarQube __se quiseres__ — é opcional e cada utilizador decide; o token fica cifrado;
• compara o código com um plano em Markdown (o que está feito, o que falta, o que sobra);
• exporta para Markdown, CSV, JSON, páginas HTML offline e PDF.

O CodeManager **não altera o teu código**. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

__Nota:__ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Para as próximas versões

Troca `1.0.0` pelo número novo (na legenda, no texto e na ligação da release) e acrescenta, em vez da lista geral, as
novidades da versão — o CHANGELOG tem-nas. A imagem pode ser refeita com as capturas de `docs/images`.
