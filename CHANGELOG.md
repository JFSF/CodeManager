# Registo de alterações

Todas as alterações relevantes ficam registadas aqui. O formato segue o
[Keep a Changelog](https://keepachangelog.com/pt-PT/1.1.0/) e o projeto usa
[versionamento semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

Primeira versão pública.

### Funcionalidades

- **Projeto:** vários projetos, cada um com o seu progresso; análise em segundo plano de `.pas`, `.dpr` e `.dpk`;
  pastas ignoradas configuráveis; fechar um projeto como finalizado.
- **Mapa:** árvore pastas → ficheiros → métodos, pesquisa, estatísticas, caixas Compila/Sonar, dicas com o texto completo.
- **Checklist:** conclusão automática por ficheiro quando todos os métodos estão revistos, prioridade, notas, filtros por
  camada, importar/exportar progresso (formato compatível com as páginas HTML), cópia em Markdown.
- **Painel:** cartões de números e gráficos (Chart4D) — evolução do progresso, progresso por camada, estado dos
  ficheiros, maiores units, métodos por camada, distribuição de métodos, Compila e Sonar por camada. Segue o tema e
  adapta-se à largura da janela.
- **Histórico:** um registo por dia por projeto, para mostrar a evolução ao longo do tempo.
- **Plano em Markdown:** leitura tolerante de um documento com a estrutura e o código previstos e cruzamento com o
  código (`PLANEADO`, `EXTRA`, `MOVIDO`, cobertura do plano no Mapa, na Checklist e no
  Painel, por camada), ou análise só do documento.
- **Acompanhar alterações:** reanálise automática do que muda na pasta do projeto, sem perder o scroll.
- **Exportar e imprimir:** estrutura em Markdown, TXT, CSV e JSON; páginas HTML offline; impressão com paginação.
- **Tema claro e escuro**, que segue o Windows na primeira execução.
- **Gravação segura:** definições, progresso e histórico são gravados de forma atómica, com cópia `.bak`;
  se um ficheiro ficar danificado, a cópia é restaurada automaticamente e a aplicação avisa.

### Qualidade

- Código organizado em camadas (`Core`, `Infrastructure`, `Services`, `UI`) com a regra de dependência verificada por
  testes automáticos.
- Mais de 350 testes DUnitX.
- Contraste do texto com pelo menos 4,5:1 nos dois temas.
