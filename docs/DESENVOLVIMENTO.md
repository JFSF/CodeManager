# Desenvolvimento

Como compilar, testar e contribuir com código para o CodeManager.

- [Requisitos](#requisitos)
- [Compilar](#compilar)
- [Testes](#testes)
- [Integração contínua e Sonar](#integração-contínua-e-sonar)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Convenções](#convenções)
- [Modo de desenvolvimento (`--dev`)](#modo-de-desenvolvimento---dev)
- [Regenerar as imagens da documentação](#regenerar-as-imagens-da-documentação)
- [Receitas](#receitas)

## Requisitos

| O quê | Versão | Notas |
|---|---|---|
| **RAD Studio / Delphi** | 13 (Florence) | Com o compilador de **Win64**. O caminho por omissão é `C:\Program Files (x86)\Embarcadero\Studio\37.0`. |
| **Chart4D** | 1.2.0 | Instala-se pelo **GetIt** do IDE (*Chart4D*). É compilado a partir do código-fonte; **não** é preciso instalar pacotes. |
| **Windows** | 10 ou 11 | A aplicação usa APIs do Windows (`ReadDirectoryChangesW`, DWM, registo). |
| DUnitX | — | Já vem com o Delphi. |

O `.dproj` procura o Chart4D em
`%USERPROFILE%\Documents\Embarcadero\Studio\37.0\CatalogRepository\Chart4D-13\1.2.0`. Se o instalaste noutro sítio,
define a variável de ambiente **`Chart4DDir`** com essa pasta (a que contém `Source\`).

## Compilar

```bat
build.bat                  Release / Win64   (por omissão)
build.bat Debug Win64      Debug  / Win64    (ativa o modo --dev)
build.bat Release Win32
```

Ou abre `CodeManager.dproj` no IDE. A saída vai para:

```text
out\bin\<Plataforma>\<Configuração>\CodeManager.exe
```

É um **único executável**, sem instalação nem BPL. Compilado e testado em **Win64**; o projeto tem também a
configuração Win32.

| Variável | Para quê |
|---|---|
| `CM_RSVARS` | Caminho do `rsvars.bat` de outra instalação do Delphi (afeta `build.bat`, `tests\run-tests.bat` e `ci.bat`). |
| `Chart4DDir` | Pasta do Chart4D (ver acima). |

O `build.bat` também regenera `templates.res` (os modelos das páginas HTML em `res\templates\`) se o `brcc32` existir.

## Testes

```bat
tests\run-tests.bat
tests\run-tests.bat --run:Tests.Store.TAppSettingsTests
```

Compila (`dcc64`, Win64) e corre os testes **DUnitX** em consola; opções do DUnitX passam-se tal e qual. O código
de saída é **0** se tudo passou, **1** se algum teste falhou e **2** se o compilador falhou.

Os testes cobrem o `Core`, os `Services`, o vigia, o cliente do Sonar (com respostas de exemplo, sem servidor), a cifra
do token e as regras de arquitetura (ver [ARQUITETURA.md](ARQUITETURA.md#testes)). A interface não tem testes
automáticos. Os testes do Git (`Tests.Git`) criam um repositório temporário com o `git` do `PATH`; se não houver
`git`, passam sem verificar nada.

## Integração contínua e Sonar

`ci.bat` encadeia compilação (Release/Win64) e testes:

```bat
ci.bat            compila + testes
ci.bat sonar      ... e depois o sonar-scanner
```

| Código de saída | Significado |
|---|---|
| 0 | Tudo bem |
| 1 | Falhou a compilação |
| 2 | Falhou algum teste |
| 3 | Falhou o Sonar |

Para o Sonar define `SONAR_HOST_URL` e `SONAR_TOKEN` (nunca no repositório) e tem o `sonar-scanner` no `PATH` (ou
aponta `SONAR_SCANNER` para o executável). A configuração está em `sonar-project.properties`.

Para o analisador de Delphi (SonarDelphi) o `sonar-project.properties` define `sonar.delphi.installationPath` e
`sonar.delphi.compilerVersion`. Dois cuidados:

- Num ficheiro `.properties` a **barra invertida é escape**: escreve os caminhos do Windows com `/`
  (`C:/Program Files (x86)/Embarcadero/Studio/37.0`). Com `\` o caminho perde as barras e o plugin falha com
  «Path to Delphi standard library is invalid».
- O `installationPath` é o caminho do Delphi **desta máquina**: ajusta-o à tua instalação.

O `sonar-scanner` precisa de um token de **análise** (*Project Analysis Token*) ou de um *User Token* com
«Execute Analysis»; sem `SONAR_TOKEN` falha com `401 Unauthorized`. Este token é diferente do que o CodeManager usa
para **ler** o Sonar (um *User Token*, configurado na página Projeto).

Isto é só para o `ci.bat`. A vista do SonarQube dentro do CodeManager é outra coisa: opcional e configurada por cada
utilizador na página Projeto (ver o [guia](GUIA-DO-UTILIZADOR.md#sonarqube-opcional)); não usa estas variáveis.

O fluxo `.github/workflows/ci.yml` corre o mesmo num *runner* **self-hosted** (Windows com o RAD Studio instalado
e a etiqueta `delphi`), porque os *runners* alojados do GitHub não têm Delphi.

## Estrutura do repositório

```text
CodeManager.dpr / .dproj   projeto da aplicação
src\
  Core\                    motor: análise, medidas, plano, estatísticas, JSON, histórico, modelo do Sonar (só RTL)
  Infrastructure\          vigia de pastas, recursos embutidos, Git, cifra do token, cliente do Sonar
  Services\                exportações, impressão e o cruzamento revisões × Git
  UI\                      janela, controlos pintados, tema
  UI\Pages\                Projeto, Mapa, Checklist, Painel e o IPageHost
res\                       ícone e modelos das páginas HTML
tests\                     testes DUnitX
docs\                      documentação (e docs\images)
tools\                     script de capturas e dados de demonstração
build.bat · ci.bat         compilar · compilar + testar
```

Detalhes e diagramas em [ARQUITETURA.md](ARQUITETURA.md).

## Convenções

- **Camadas.** `Core` só usa a RTL; `Infrastructure` só `Core`; `Services` não importa `UI`. O teste
  `Tests.Architecture` falha se isto for violado. Uma unit nova vai para uma das quatro pastas.
- **Codificação.** Os ficheiros `.pas` são **UTF-8 com BOM** (sem BOM o compilador do Delphi assume ANSI e estraga os
  acentos). Fins de linha CRLF.
- **Estilo.** Segue o código à volta: comentários em português, identificadores e texto da interface em português,
  `T` para tipos, `F` para campos, `A` para parâmetros.
- **A interface é desenhada em código.** Não há `.fmx`/`.dfm`. Os controlos pintam-se a partir de `Pal` (a paleta do
  tema) em `CM.Theme`: **nunca** uses cores fixas num controlo.
- **Contraste.** O texto fraco deve ter pelo menos 4,5:1 sobre as superfícies, nos dois temas.
- **Testes primeiro no Core.** Lógica nova (leitura, cálculo, JSON) vai para o `Core` ou `Services` com testes
  DUnitX. Se a lógica ficar presa a um controlo, é difícil de testar.
- **Mensagens de commit** em português, a dizer *o quê* e *porquê*.

## Modo de desenvolvimento (`--dev`)

As compilações **Debug** aceitam um guião que dirige a aplicação sem intervenção humana — é assim que se verifica
a interface e se geram as imagens desta documentação:

```bat
out\bin\Win64\Debug\CodeManager.exe --dev "page:1;wait:1;shot:mapa.png;quit"
```

Os comandos separam-se por `;`; os argumentos de cada um, por `,`.

| Comando | Faz |
|---|---|
| `wait:N` | Espera N segundos |
| `page:N` | Muda de página: 0 Projeto, 1 Mapa, 2 Checklist, 3 Painel |
| `search:texto` | Escreve na pesquisa da página atual (vazio limpa) |
| `theme:dark` ou `theme:light` | Muda o tema |
| `size:largura,altura` | Redimensiona a área cliente (testar janelas pequenas ou altas) |
| `click:x,y` · `dblclick:x,y` · `move:x,y` · `wheel:x,y,delta` | Rato, em coordenadas da janela (`dblclick` = dois cliques seguidos) |
| `page:7` | A página Acerca (a ordem dos índices é a de `TPage`: 0 Projeto, 1 Mapa, 2 Checklist, 3 Painel, 4 Grafo, 5 Código, 6 Aspeto, 7 Acerca, 8 SBOM, 9 Classes) |
| `sonardemo` | Enche o SonarQube com dados **inventados** (medidas, problemas em linhas reais, hotspots), só para as imagens e para testar a interface |
| `code:caminho[#método]` | Abre o código de uma unit (e salta para o método) na página Código e regista o separador no `dev.log` |
| `hint:x,y` | Põe o rato em (x,y) e regista no `dev.log` a dica que apareceria |
| `shot:ficheiro.png` | Grava uma captura da janela (compõe a árvore de controlos, sem depender do ecrã) |
| `setproj:nome,raiz,saida[,plano.md]` | Preenche o projeto ativo e analisa |
| `watch:0\|1` | Desliga/liga o acompanhamento |
| `select:N` | Seleciona o projeto N da lista |
| `exportmap` · `exportck` | Exporta as páginas HTML |
| `exportsbom:fmt,ficheiro` | Grava o SBOM que a página SBOM já gerou (espera-se com `page:8;wait:N` antes); `fmt` = `cdx`, `spdx`, `html` ou `md` |
| `exportclasses:fmt,ficheiro` | Grava o relatório das classes (a página Classes constrói a hierarquia ao abrir); `fmt` = `md` ou `csv` |
| `exportstruct:fmt,ficheiro,metodos,estado` | Exporta a estrutura; `fmt` = `md`, `txt`, `csv` ou `json`; `metodos` e `estado` = `0` ou `1` |
| `printprev:pagina,dpi,horizontal,ficheiro.png` | Desenha uma página de impressão num bitmap |
| `printto:nome` | Imprime na impressora cujo nome contenha o texto |
| `notetext:texto` · `toast:texto` | Escreve na nota aberta · mostra um aviso |
| `quit` | Termina |

Notas:

- Cada passo grava `ok …` ou `ERRO …` em **`dev.log`** (na pasta de trabalho).
- A variável **`CODEMANAGER_DATA`** redireciona os dados (`settings.json`, progresso, histórico) para outra pasta —
  só nas compilações Debug. Os testes e o script de capturas usam-na para nunca tocar nos dados reais.
- Se lançares a aplicação a partir de um script com `Start-Process -ArgumentList`, os **espaços** partem o argumento:
  não uses espaços no guião (ou lança-a a partir da linha de comandos, com aspas).

## Regenerar as imagens da documentação

```bat
build.bat Debug Win64
powershell -ExecutionPolicy Bypass -File tools\capture-docs.ps1
```

O script `tools\capture-docs.ps1`:

1. arranca a aplicação com uma pasta de dados temporária e um projeto «CodeManager» apontado a **este repositório**
   e ao plano de demonstração `tools\demo\plano-demo.md`;
2. exporta a estrutura (JSON) para conhecer os ficheiros e métodos;
3. semeia um **progresso** e um **histórico de demonstração** (o histórico é inventado: serve só para a imagem), com
   alguns **estados de revisão** e, se o repositório tiver histórico (`HEAD~8`), revisões antigas de alguns ficheiros para
   mostrarem a etiqueta «ALTERADO». O SonarQube fica **desligado** nas imagens (é o estado por omissão);
4. percorre as páginas, em claro e escuro, e grava as capturas em `docs\images` (incluindo as métricas dos métodos, os
   estados de revisão e a configuração do SonarQube), mais a imagem principal `hero.png`.

O caminho do repositório não pode ter espaços.

## Publicar uma versão

1. Sobe o número em `CodeManager.dproj` (`FileVersion` e `ProductVersion` em `VerInfo_Keys`): é o que a página
   **Acerca** mostra.
2. No `CHANGELOG.md`, passa o que está em «Não lançado» para a versão nova (com a data) e acrescenta a ligação de
   comparação no fim; atualiza a secção **Alterações** dos `README` e o «Estado do projeto».
3. `ci.bat` (compila em Release/Win64 e corre os testes); copia `out\bin\Win64\Release\CodeManager.exe` para
   `CodeManager-X.Y.Z-win64.exe` e gera o `SHA256SUMS.txt` com `Get-FileHash`.
4. Refaz o cartaz e os modelos de divulgação (`docs/divulgacao`): `python tools/make-cartaz.py X.Y.Z pt` e `en`.
5. Junta o `develop` ao `master`, cria a etiqueta `vX.Y.Z` e envia tudo; `gh release create vX.Y.Z` com o executável
   e o `SHA256SUMS.txt`.

## Receitas

### Adicionar uma página

1. Cria `src\UI\Pages\CM.Pages.Nome.pas` com uma classe `TNomePage = class(TCMControl)` cujo construtor recebe
   `(AOwner, AParent, const AHost: IPageHost)`.
2. Acrescenta `pgNome` a `TPage` em `CM.Pages.Host` e um item aos arrays `Names`/`Icons` de `BuildRail` em
   `CM.MainForm`.
3. Cria a página em `BuildUI`, regista-a em `FPageBox` e chama o que ela precisar em `UpdateAll`, `ApplyTheme` e
   `ShowPage`.
4. Acrescenta-a a `CodeManager.dpr`/`.dproj`.

### Adicionar um formato de exportação

1. Acrescenta o valor a `TExportFormat` em `CM.Export` e implementa `Build…` (recebe a análise e o estado).
2. Trata-o em `ExportFormatName`, `ExportFormatExt` e `ExportToFile`.
3. Liga um botão em `Pages.Map` e escreve testes em `tests\Tests.Export.Formats.pas`.

### Acrescentar um gráfico ao Painel

Em `CM.Pages.Dashboard`: cria o `TChart4D` com `AddChartCard`, preenche-o numa rotina `Fill…` (chamada por
`Rebuild`) e inclui-o em `StyleAll`. As cores vêm de `Pal` para seguir o tema.

### Traduzir um texto

O português é a chave: no código escreve-se `Tr('Texto em português')` (ou `TrF`, `TrCount`) e as traduções para
inglês, francês e alemão ficam em `tools/i18n/translations.tsv` (colunas separadas por TAB: pt, en, fr, de). Depois
de editar o ficheiro, corre `pwsh tools/i18n/generate-lang-table.ps1`, que regenera `src/Core/CM.Lang.Table.pas`
(não se edita à mão). Os testes avisam de textos marcados com `Tr` que faltam na tabela e de colunas vazias.

Os modelos das páginas HTML (`res/templates`) não usam `Tr`: a secção `#!html` do mesmo `.tsv` lista **trocos
exatos** do modelo e `TranslateHtml` aplica-os, do mais comprido para o mais curto, antes de se preencherem os
marcadores `__XXX__`. Se mudares um texto do modelo, muda também o troco; um teste falha quando um troco deixa de
existir nos modelos.

### Estender a leitura do plano

A leitura está em `CM.Plan` (`TPlanParser`). Cada estilo reconhecido é um método (`ProcessHeading`,
`ProcessBullet`, `ProcessFence`, `AddTree`). Acrescenta o caso e testes em `tests\Tests.Plan.pas`; documenta-o em
[FORMATO-DO-PLANO.md](FORMATO-DO-PLANO.md).
