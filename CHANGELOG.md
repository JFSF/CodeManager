# Registo de alterações

Todas as alterações relevantes ficam registadas aqui. O formato segue o
[Keep a Changelog](https://keepachangelog.com/pt-PT/1.1.0/) e o projeto usa
[versionamento semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Funcionalidades

- **Grafo de dependências:** nova página com o mapa visual de quem usa quem (cláusulas `uses` da *interface* e da
  *implementation*), acoplamento, instabilidade, **ciclos**, filtro, simplificação e relatório em HTML (mapa em SVG)
  ou Markdown.
- **Idiomas:** português, inglês, francês e alemão, escolhidos na página Projeto; os relatórios exportados seguem o
  idioma. Na primeira execução usa o idioma do Windows.
- **Repositórios do GitHub:** analisar um repositório em vez de uma pasta; clona-se só a última versão para uma cache
  própria (só leitura) e há «Atualizar do GitHub».

## [1.0.0] - 2026-10-03

Primeira versão pública.

### Funcionalidades

- **Projeto:** vários projetos, cada um com o seu progresso; análise em segundo plano de `.pas`, `.dpr` e `.dpk`;
  pastas ignoradas configuráveis; fechar um projeto como finalizado.
- **Mapa:** árvore pastas → ficheiros → métodos, pesquisa, estatísticas, caixas Compila/Sonar, dicas com o texto completo;
  **linhas de código e complexidade ciclomática** de cada método (`cx`, a âmbar acima de 10 e a vermelho acima de 20).
- **Checklist:** conclusão automática por ficheiro quando todos os métodos estão revistos; **estados de revisão**
  (por rever, em revisão, precisa de alteração, concluído) com filtros e contagens; prioridade, notas e filtros por
  camada; importar/exportar progresso (formato compatível com as páginas HTML); cópia em Markdown.
- **Git (só leitura):** os ficheiros revistos que mudaram desde a revisão levam a etiqueta «ALTERADO», com a dica dos
  últimos commits, o filtro «Só alterados» e «Voltar a por rever».
- **SonarQube (opcional e por utilizador):** problemas abertos por ficheiro («Sonar N»), *quality gate* e
  «Sincronizar S». O interruptor, o endereço e o token (cifrado com o DPAPI do Windows) são de cada utilizador; a
  chave é de cada projeto. As consultas correm em segundo plano.
- **Painel:** cartões de números e gráficos (Chart4D) — evolução do progresso, progresso por camada, estado dos
  ficheiros (incluindo em revisão e a alterar), maiores units, métodos por camada, distribuição de métodos, Compila e
  Sonar por camada, métodos mais complexos e complexidade dos métodos, e a cobertura do plano. Segue o tema e
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
- Mais de 490 testes DUnitX (incluindo os da integração com o Git, contra um repositório temporário real).
- Contraste do texto com pelo menos 4,5:1 nos dois temas.

[Não lançado]: https://github.com/JFSF/CodeManager/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
