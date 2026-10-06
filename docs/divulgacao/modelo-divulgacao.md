# Modelo de divulgação — CodeManager 1.0.4

Material pronto para publicar nos grupos de **WhatsApp** e **Telegram**.

| Ficheiro | Para quê |
|---|---|
| [`cartaz-1.0.4.png`](cartaz-1.0.4.png) | A imagem (1600 × 900) |
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
*CodeManager 1.0.4* 🚀
_Mapa e checklist de código-fonte Delphi_

Nova versão! A profundidade de herança de cada classe, sempre sem alterar uma linha do teu código.

✅ Página Classes: classes e interfaces em árvore, com a profundidade de herança
✅ Filhas, métodos e declaração de cada uma (duplo clique abre o código)
✅ «>=» quando a cadeia sai do projeto para uma classe desconhecida
✅ Painel: as classes mais profundas e a distribuição da profundidade
✅ Exporta Markdown e CSV

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.4
```

### Mensagem completa

```text
*CodeManager 1.0.4* 🚀
_Mapa e checklist de código-fonte Delphi_

Já está disponível a versão 1.0.4 do *CodeManager*, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• *Classes* — uma página nova com as classes, interfaces e records do projeto e a profundidade de herança de cada uma, as filhas e os métodos;
• *Na própria lista* — ordena pelos títulos, filtra, e o duplo clique abre o código na declaração da classe;
• *Profundidade mínima* — quando a cadeia sai do projeto para uma classe que não se conhece, aparece «>=» em vez de um valor falso;
• *Painel e relatórios* — as classes mais profundas, a distribuição da profundidade e a exportação para Markdown e CSV.

O CodeManager *não altera o teu código*. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.4
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

_Nota:_ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Telegram

Formatação: `**negrito**`, `__itálico__` (escreve o texto com estes símbolos e o Telegram aplica o estilo). As ligações ficam clicáveis sozinhas.

### Legenda curta (para a imagem)

```text
**CodeManager 1.0.4** 🚀
__Mapa e checklist de código-fonte Delphi__

Nova versão! A profundidade de herança de cada classe, sempre sem alterar uma linha do teu código.

✅ Página Classes: classes e interfaces em árvore, com a profundidade de herança
✅ Filhas, métodos e declaração de cada uma (duplo clique abre o código)
✅ «>=» quando a cadeia sai do projeto para uma classe desconhecida
✅ Painel: as classes mais profundas e a distribuição da profundidade
✅ Exporta Markdown e CSV

🪟 Windows 10/11 · gratuito · código aberto
⬇️ https://github.com/JFSF/CodeManager/releases/tag/v1.0.4
```

### Mensagem completa

```text
**CodeManager 1.0.4** 🚀
__Mapa e checklist de código-fonte Delphi__

Já está disponível a versão 1.0.4 do **CodeManager**, a aplicação para Windows que lê as units de um projeto Delphi e te ajuda a ver o que tens, rever o que já foi visto e acompanhar o progresso.

O que há de novo:
• **Classes** — uma página nova com as classes, interfaces e records do projeto e a profundidade de herança de cada uma, as filhas e os métodos;
• **Na própria lista** — ordena pelos títulos, filtra, e o duplo clique abre o código na declaração da classe;
• **Profundidade mínima** — quando a cadeia sai do projeto para uma classe que não se conhece, aparece «>=» em vez de um valor falso;
• **Painel e relatórios** — as classes mais profundas, a distribuição da profundidade e a exportação para Markdown e CSV.

O CodeManager **não altera o teu código**. É um único ficheiro, sem instalador.

⬇️ Descarregar: https://github.com/JFSF/CodeManager/releases/tag/v1.0.4
📖 Guia e código-fonte: https://github.com/JFSF/CodeManager

__Nota:__ o executável não está assinado, por isso o Windows pode mostrar um aviso do SmartScreen na primeira vez ("Mais informações" → "Executar mesmo assim"). Podes confirmar o ficheiro com o SHA-256 da release.

Sugestões e erros são muito bem-vindos! 🙏
```

---

## Para as próximas versões

Troca `1.0.4` pelo número novo (na legenda, no texto e na ligação da release) e acrescenta as novidades da versão — o
CHANGELOG tem-nas. O cartaz refaz-se com `python tools/make-cartaz.py <versão> pt` (e `en`): edita os textos e as duas
capturas no início do `tools/make-cartaz.py` (as capturas vêm de `docs/images`).
