# CodeManager

Aplicação Delphi/FMX para **Windows** (Win32/Win64; usa APIs do Windows como `ReadDirectoryChangesW`, DWM e o registo) que junta os dois scripts PowerShell
`gerar_checklist_codigo.ps1` e `gerar_mapa_codigo.ps1` numa só ferramenta, com tema claro/escuro.

## O que faz
- **Projeto** – define o projeto (nome, pasta raiz, pasta de destino, pastas a ignorar), analisa o código
  (`.pas`, `.dpr`, `.dpk`), exporta as páginas HTML, fecha/reabre o projeto como finalizado. Vários projetos,
  cada um com o seu progresso.
- Os métodos são identificados pela classe (`TFoo.Bar`); overloads distinguem-se pelos tipos dos parâmetros
  (`TFoo.Bar(Integer)`). O progresso antigo (só pelo nome) é migrado automaticamente.
- **Mapa** – árvore pastas › ficheiros › métodos (pesquisa, estatísticas, flags **C**ompila / **S**onar).
- **Checklist** – ficheiros agrupados por pasta, conclusão automática quando todos os métodos estão
  marcados, prioridade ★, notas, filtros por camada, progresso por camada, copiar Markdown,
  exportar/importar progresso (`.json` compatível com o das páginas HTML).
- **Acompanhar alterações** (página Projeto) – vigia a pasta do projeto (`ReadDirectoryChangesW`) e, quando uma
  unit é gravada, criada, apagada ou uma pasta é renomeada, volta a analisar só o que mudou e atualiza o Mapa, a
  Checklist e as estatísticas sem perder o scroll nem as pastas abertas. Ficheiros e métodos novos ou alterados
  ficam realçados durante alguns segundos. Vê o que está **gravado em disco** (não o texto por gravar no editor).
- **Exportar estrutura** (página Mapa) – pastas › ficheiros › métodos em **Markdown**, **TXT** (árvore ASCII),
  **CSV** (separador `;`, abre em colunas no Excel) e **JSON** (árvore aninhada). Opções: incluir métodos e incluir
  estado (concluído, Compila, Sonar, prioridade, notas).
- **Imprimir estrutura** (página Mapa › «Imprimir…») – diálogo de impressão do Windows (impressora, cópias,
  orientação e papel em «Preferências»); A4/papel da impressora, letra monoespaçada, quebra de linhas longas com
  guias, cabeçalho corrido e rodapé «Página X de N». Também serve para PDF (impressora «Microsoft Print to PDF»).
- **Exportar HTML** – gera as mesmas páginas offline dos scripts (modelos em `res/templates/`),
  já com o progresso da aplicação embutido como estado inicial.
- Tema claro/escuro (botão na barra lateral; segue o Windows na primeira execução; barra de título incluída).

## Plano (documento .md)
Cada projeto pode ter, além da pasta de código, um **documento Markdown com a estrutura e o código previstos**
(página Projeto › «Documento do plano»). A aplicação lê-o de forma tolerante, por qualquer ordem e misturando estilos:

- **título com o caminho** do ficheiro (`## src/Core/CM.X.pas`) seguido de um bloco `` ```pascal `` com a unit ou só as declarações;
- bloco de código com o caminho na linha de abertura, num comentário inicial (`// src/Core/CM.X.pas`) ou só o `unit X;`
  (fica na pasta do último título de pasta, ex.: `### src/Core/`);
- **árvores de pastas** em blocos de texto (`├──`, `└──`, `│` ou só indentação);
- **listas Markdown** aninhadas com pastas, ficheiros e assinaturas de métodos — inclui o formato que a própria
  aplicação exporta (Mapa › Markdown), por isso o resultado de uma análise pode servir de plano.

Há três modos, conforme o que o projeto tem:

| Pasta de código | Documento | O que a aplicação faz |
|---|---|---|
| sim | não | análise do código, como sempre |
| sim | sim | **cruza** plano e código: o Mapa marca `PLANEADO` (só no plano), `EXTRA` (só no código) e `MOVIDO` (noutra pasta) e mostra a cobertura do plano; as dicas ao pairar explicam cada estado |
| não | sim | analisa o documento como se fosse o código (Mapa, Checklist, Painel), útil para rever o desenho antes de haver código |

Regras do cruzamento: os ficheiros emparelham pelo caminho (ou, se mudaram de pasta, pelo nome quando é único dos dois lados);
os métodos pelo nome qualificado (`TFoo.Bar`) ou, na falta, pelo nome simples quando é único. Se o plano lista um ficheiro
sem métodos (ex.: só numa árvore), os métodos do código não são julgados. Um exemplo está em `docs/plano-exemplo.md`.
Nesta primeira fase a comparação aparece no **Mapa**; Checklist, Painel e exportações usam a análise do código.

## Compilar
Requer o **Chart4D** (GetIt › Chart4D, MIT). O `.dproj` procura-o em `%USERPROFILE%\Documents\Embarcadero\Studio\37.0\CatalogRepository\Chart4D-13\1.2.0`; se estiver noutro sítio, define a variável de ambiente `Chart4DDir` com essa pasta.

`build.bat` (Release/Win64) · `build.bat Debug Win32` · ou abrir `CodeManager.dproj` no IDE.
Saída em `out\bin\<Plataforma>\<Config>\CodeManager.exe` (a que está definida no `.dproj`).
Por omissão usa o Delphi 13 em `C:\Program Files (x86)\Embarcadero\Studio\37.0`; para outra instalação define `CM_RSVARS` com o caminho do `rsvars.bat` (vale também para `tests\run-tests.bat`).

## Dados guardados
`%APPDATA%\CodeManager\settings.json` (projetos, tema) e `progress-<id>.json` (progresso por projeto).

## Estrutura
O código em `src` está separado por camadas; cada camada só depende das anteriores (`Core` ← `Infrastructure` / `Services` ← `UI`).

| Camada | Unit | Papel |
|---|---|---|
| `Core` | `CM.Analyzer` | varrimento de pastas + extração de métodos (porta do motor dos scripts) |
| `Core` | `CM.Store` | definições, projetos e progresso (JSON) |
| `Core` | `CM.Stats` | regras de conclusão e estatísticas |
| `Core` | `CM.History` | histórico diário do progresso (`history-<id>.json`) |
| `Core` | `CM.Plan` | leitura tolerante do documento do plano (`.md`) e cruzamento plano × código |
| `Services` | `CM.Export` | lista plana da estrutura + exportação para Markdown, TXT, CSV e JSON |
| `Infrastructure` | `CM.Watcher` | vigia de pastas numa thread (só regista caminhos; a análise corre na thread principal) |
| `Services` | `CM.Print` | paginação e impressão (`FMX.Printer`); `TStructureDoc` desenha em qualquer canvas |
| `Services` | `CM.Html` | exportação das páginas (modelos embutidos via `templates.res`) |
| `UI` | `CM.Theme` / `CM.Controls` | paletas, ícones vetoriais e controlos pintados a partir da paleta |
| `UI` | `CM.TreeList` | lista virtualizada usada pelas vistas Mapa e Checklist |
| `UI` | `CM.Layouts` | linha de botões, fluxo de «chips» e construtores de cartões/campos |
| `UI` | `CM.MainForm` | janela principal: navegação, tema, persistência, estado partilhado (`IPageHost`) |
| `UI\Pages` | `CM.Pages.Host` | `IPageHost` — o contrato entre a janela e as páginas |
| `UI\Pages` | `CM.Pages.Project` | página Projeto: lista de projetos, configuração, análise, «acompanhar», exportar HTML |
| `UI\Pages` | `CM.Pages.Map` | página Mapa: árvore, estatísticas, exportar/imprimir estrutura |
| `UI\Pages` | `CM.Pages.Checklist` | página Checklist: progresso, filtros por camada, notas, exportar/importar progresso |
| `UI\Pages` | `CM.Pages.Dashboard` | página Painel: cartões de números com mini-curva e gráficos [Chart4D](https://github.com/GDKsoftware/Chart4D) (evolução, progresso por camada, estado, maiores units, distribuição, Compila/Sonar por camada); adapta-se à largura da janela |
| — | `tests\` | testes DUnitX (`Tests.Analyzer.*`, `Tests.Stats`, `Tests.Store`, `Tests.Export.*`, `Tests.Helpers`) |

## Testes
`tests\run-tests.bat` compila (`dcc64`, Win64) e corre os testes DUnitX, que já vêm com o Delphi 13; o código de saída
é 0 se tudo passou. Opções do DUnitX passam-se tal e qual (ex.: `tests\run-tests.bat
--run:Tests.Store.TAppSettingsTests`). Cobrem o `CM.Analyzer` (extração de métodos: comentários/strings,
interface/implementation, overloads, genéricos, tipos aninhados, codificações; `ScanProject`, `RescanFile`,
`ReconcileScan`), o `CM.Stats` (`UnitDone`, `ComputeStats`, `MigrateMethodKeys`), o `CM.Store`
(`TAppSettings`, `TProgressState` — o JSON de progresso, incluindo o formato `{state:{...}}`
das páginas exportadas) e o `CM.Export` (a lista plana `FlattenStructure`, os conectores da árvore
ASCII, e o conteúdo de cada formato — Markdown, TXT, CSV incluindo o escape de campos, e JSON).
Cada teste usa uma pasta temporária própria; os que tocam em `CM.Store` isolam também `AppDataDir`
(variável `CODEMANAGER_DATA`, só em Debug) para nunca ler/escrever a pasta real do utilizador. Os
ficheiros `.pas` de teste têm de levar BOM UTF-8 (tal como os de `src\`) — sem ele o `dcc64` assume
a *codepage* do sistema e corrompe silenciosamente os literais com acentos.

## Modo de desenvolvimento (só Debug)
`CodeManager.exe --dev "page:1;wait:1;click:900,181;shot:out.png;quit"` executa um guião interno
(`page`, `click`, `move`, `wheel`, `search`, `theme`, `select`, `toast`, `exportmap`, `exportck`, `exportstruct`, `printprev`, `printto`, `setproj`, `watch`,
`shot`, `wait`, `quit`) e regista o resultado em `dev.log` (na pasta de trabalho; com `CODEMANAGER_DATA=<pasta>` os dados da aplicação ficam isolados) – útil para testes visuais sem simular o rato do sistema.
