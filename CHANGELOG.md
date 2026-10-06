# Registo de alterações

Todas as alterações relevantes ficam registadas aqui. O formato segue o
[Keep a Changelog](https://keepachangelog.com/pt-PT/1.1.0/) e o projeto usa
[versionamento semântico](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Funcionalidades

- **SBOM:** nova página que gera a **lista de materiais de software** do projeto a partir do código-fonte e do `.dproj`
  (sem compilar): as units de fora que o projeto usa, a origem de cada uma (RTL, VCL, FMX da Embarcadero ou terceiros), a
  evidência e a confiança (forte, média, fraca) e o SHA-256 dos ficheiros achados. Usa o ficheiro `.map` se existir
  (confirma as units ligadas, acrescenta as que só o mapa conhece e assinala as que ficam fora). Exporta **CycloneDX 1.5**
  e **SPDX 2.3** (JSON, validados antes de gravar) e um **relatório** HTML (quatro idiomas, com seletor na página) ou
  Markdown. Nenhum caminho completo vai para os ficheiros. Adapta ideias e regras do
  [DX.Comply](https://github.com/omonien/DX.Comply) (MIT, Olaf Monien).

## [1.0.2] - 2026-10-06

Mercurial, complexidade cognitiva, mais métricas por método e relatório de dependências em quatro idiomas.

### Funcionalidades

- **Mercurial:** a deteção de «alterado desde a revisão» funciona também em repositórios Mercurial (com o `hg` da
  linha de comandos, por exemplo o do TortoiseHg): guarda o identificador completo do conjunto de alterações, junta
  o que foi gravado depois com o que ainda não foi, e a dica mostra os conjuntos que tocaram no ficheiro. A página
  Acerca indica se o `hg` foi encontrado. O Git e o Subversion continuam como antes.

- **Complexidade cognitiva:** nova medida por método (regras da SonarSource, aproximadas ao nível dos símbolos): as
  estruturas de controlo somam 1 mais o aninhamento, `else if` não aninha, cada sequência de `and`/`or` soma 1 e os
  métodos anónimos aninham. Aparece no Mapa e na Checklist (`cg 25`, âmbar acima de 15 e vermelha acima de 25), na dica,
  nas páginas HTML, no CSV e no JSON, e no Painel (os 10 mais difíceis de ler e a distribuição por nível).

- **Relatório de dependências multi-idioma:** a página HTML leva as frases em português, inglês, francês e alemão e
  um seletor **PT · EN · FR · DE**; troca o texto na própria página (título, cartões, tabelas, dicas do mapa e filtro),
  sem recarregar. Nasce no idioma ativo da aplicação.

### Correções

- **Idiomas:** revistos página a página em alemão e francês (e as exportações nos três idiomas).
  - Os botões de texto comprido já não ficam cortados («Vereinfachen», «Anpassen» no Grafo; «HTML exportieren» na
    Checklist): uma linha de botões dá agora a largura natural a quem precisa e reparte o resto pelos outros.
  - O eixo de datas do Painel já escreve os meses no idioma ativo (estava fixo em português: «6 out» em alemão).
  - O exemplo de endereço do repositório GitHub está traduzido e a linha de ajuda da página Projeto quebra em duas
    linhas em vez de ser cortada.

### Melhorias

- **Mapa:** os **parâmetros** (`p 3`) e o **aninhamento** (`n 2`) de cada método aparecem ao lado das linhas e da
  complexidade (só quando não são zero), com cor de aviso: parâmetros âmbar a partir de 5 e vermelho acima de 7;
  aninhamento âmbar a partir de 4 e vermelho acima de 5.
- **Páginas HTML exportadas:** o mapa e a checklist mostram as linhas, a complexidade, os parâmetros e o
  aninhamento de cada método, com as mesmas cores de aviso e dicas traduzidas.
- **Painel:** dois gráficos novos, **Métodos com mais parâmetros** e **Métodos mais aninhados** (os 10 de cada).

## [1.0.1] - 2026-10-03

Novas páginas (Grafo, Código, Aspeto, Acerca), mais métricas por método, mais do SonarQube, Subversion, quatro idiomas e
repositórios do GitHub.

### Funcionalidades

- **Grafo de dependências:** nova página com o mapa visual de quem usa quem (cláusulas `uses` da *interface* e da
  *implementation*), acoplamento, instabilidade, **ciclos**, filtro, simplificação e relatório em HTML (mapa em SVG)
  ou Markdown.
- **Acerca:** nova opção na barra lateral com a versão (lida do executável), a compilação (Release ou Debug, 32 ou 64
  bits, data), o Delphi, o Windows, o idioma, a pasta de dados, ligações (repositório, novidades, reportar um problema)
  e os créditos; «Copiar informação» dá um texto de diagnóstico para as *issues*.
- **Aspeto:** nova página para escolher a **cor de destaque** (cores prontas ou `#RRGGBB`, com as variantes e o texto
  por cima calculados para se lerem nos dois temas), as **fontes** (interface, texto técnico e código), a **escala do
  texto** (90 % a 125 %) e o **tamanho do código**, com pré-visualização e «Repor». Guardado por utilizador.
- **Subversion:** a deteção de «alterado desde a revisão» funciona também numa cópia de trabalho do Subversion
  (com o `svn` da linha de comandos): guarda o número da revisão, junta as revisões seguintes com as alterações
  ainda por enviar, e a dica mostra as revisões (`r1234`) que tocaram no ficheiro. O Git continua como antes.
- **Mais do SonarQube:** cada consulta traz agora as medidas do projeto e de cada ficheiro (linhas, cobertura,
  duplicação, dívida técnica, complexidade, bugs, vulnerabilidades, *code smells*, *hotspots*, classificações A–E), o
  detalhe dos problemas (linha, tipo, regra, mensagem) e os *security hotspots* por rever. Mostram-se no cartão do Mapa,
  na dica dos ficheiros, na página Código (marcadores na margem e lista de problemas) e numa secção nova do Painel.
- **Mais métricas por método:** número de **parâmetros** e **aninhamento** de blocos (`begin`, `try`, `case`,
  `repeat`), na dica do método e nas colunas/campos do CSV e do JSON.
- **Leitura do código:** nova página **Código**, aberta por duplo clique numa unit do Grafo ou num ficheiro ou método do
  Mapa e da Checklist; separadores só de leitura com números de linha, realce de sintaxe Delphi, salto para o método
  e fonte moderna (JetBrains Mono, Fira Code, Cascadia Code…) com **ligaduras** ligáveis e desligáveis.
- **Idiomas:** português, inglês, francês e alemão, escolhidos na página Projeto; os relatórios exportados seguem o
  idioma, incluindo as **páginas HTML offline** (mapa e checklist). Na primeira execução usa o idioma do Windows.
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

[Não lançado]: https://github.com/JFSF/CodeManager/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/JFSF/CodeManager/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/JFSF/CodeManager/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/JFSF/CodeManager/releases/tag/v1.0.0
