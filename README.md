<div align="center">

# CodeManager

**Revê, acompanha e planeia projetos Delphi — pasta a pasta, ficheiro a ficheiro, método a método.**

[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-green.svg)](LICENSE)
[![Delphi 13](https://img.shields.io/badge/Delphi-13-e62329.svg)](docs/DESENVOLVIMENTO.md#requisitos)
[![Windows](https://img.shields.io/badge/plataforma-Windows-0078d4.svg)](docs/DESENVOLVIMENTO.md#requisitos)
[![Testes: DUnitX](https://img.shields.io/badge/testes-DUnitX-1f6feb.svg)](docs/ARQUITETURA.md#testes)
[![English](https://img.shields.io/badge/README-English-lightgrey.svg)](README.en.md)

![CodeManager: checklist de revisão e painel de progresso](docs/images/hero.png)

</div>

O CodeManager lê as units de um projeto Delphi e dá-te uma forma simples de **ver o que tens**, **rever o que já
foi visto** e **acompanhar o progresso ao longo do tempo** — sem alterar uma linha do teu código. Se tiveres um
documento com o que o projeto *devia* ter, compara os dois.

- 🗺️ **Mapa** — a árvore pastas → ficheiros → métodos, com pesquisa, estatísticas e as **linhas, a complexidade (ciclomática e cognitiva), os parâmetros e o aninhamento** de cada método.
- ✅ **Checklist** — marca o que reviste, o que está em revisão ou precisa de alteração, o que compila, o que passou no Sonar, o que é prioritário; com notas.
- 📊 **Painel** — números e gráficos do progresso e da distribuição do código, incluindo a evolução dia a dia.
- 📝 **Plano em Markdown** — escreve a estrutura prevista num `.md` e vê o que está implementado, o que falta e o que sobra.
- 👀 **Acompanha o IDE** — reanalisa sozinho o que mudas e grava.
- 📤 **Exporta** para Markdown, TXT, CSV, JSON, páginas HTML offline e papel/PDF.
- 🌗 **Tema claro e escuro.**

## Índice

- [Para quem é](#para-quem-é)
- [Começar](#começar)
- [O que podes fazer](#o-que-podes-fazer)
- [Plano × código](#plano--código)
- [Como funciona](#como-funciona)
- [Alterações](#alterações)
- [Documentação](#documentação)
- [Estado do projeto](#estado-do-projeto)
- [Contribuir](#contribuir)
- [Licença e créditos](#licença-e-créditos)

## Para quem é

- Quem faz **revisão de código** ou **auditoria** de um projeto Delphi grande e precisa de saber o que já foi visto.
- Quem **herdou ou migra** uma base de código e quer um mapa e uma lista de trabalho.
- Quem **planeia** a arquitetura antes de escrever (ou com a ajuda de um assistente de IA) e quer ver o código a
  aproximar-se do plano.
- Equipas que querem **acompanhar a qualidade**: compila, passou no Sonar, quantos métodos foram revistos.

## Começar

**Precisas de:** Windows 10/11 e, para compilar, **Delphi 13** com o pacote **Chart4D** (GetIt). Um executável
único, sem instalação.

```bat
git clone <url-do-repositório>
cd CodeManager
build.bat
```

O executável fica em `out\bin\Win64\Release\CodeManager.exe`. Passos detalhados, variáveis de ambiente e como correr
os testes em [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).

**Primeira utilização**

1. Abre o `CodeManager.exe`. Na página **Projeto**, dá um nome e escolhe a pasta raiz do teu projeto.
2. Carrega em **Analisar projeto**.
3. Explora no **Mapa**, revê na **Checklist**, vê o conjunto no **Painel**.

O guia completo, ecrã a ecrã, está em [docs/GUIA-DO-UTILIZADOR.md](docs/GUIA-DO-UTILIZADOR.md).

## O que podes fazer

### Ver o que tens

O **Mapa** mostra todas as pastas, ficheiros e métodos do projeto, com pesquisa (tecla `/`), estatísticas e as
caixas **C** (compila) e **S** (Sonar).

![Mapa de código](docs/images/02-mapa.png)

### Ver as dependências

O **Grafo** desenha quem usa quem, a partir das cláusulas `uses`: colunas por nível, cores por camada, acoplamento
(usa / usada por), **ciclos** assinalados e um relatório em HTML (com o mapa em SVG) ou Markdown.

![Grafo de dependências](docs/images/13-grafo.png)

### Ler o código

Um **duplo clique** numa unit do Grafo, ou num ficheiro ou método do Mapa e da Checklist, abre o código numa página
de **leitura** com separadores, números de linha, realce Delphi e uma fonte moderna com **ligaduras**; num método, salta
para a sua linha.

![Leitura do código](docs/images/14-codigo.png)

### Trazer o SonarQube para dentro do código

Com o SonarQube ligado (opcional e por utilizador), os problemas aparecem na margem das linhas do código, e o Mapa e o
Painel ganham as medidas do servidor: cobertura, duplicação, dívida técnica, classificações A–E e *hotspots*.

![Código com problemas do SonarQube](docs/images/15-codigo-sonar.png)

<sub>A imagem usa dados de demonstração do Sonar.</sub>

### Rever com método

A **Checklist** agrupa os ficheiros por pasta. Um ficheiro fica concluído quando **todos os métodos** estão revistos;
podes marcar prioridades ★, escrever notas, filtrar por camada e dar a cada método um **estado de revisão**
(por rever, em revisão, precisa de alteração, concluído). Num repositório **Git** ou **Mercurial**, ou numa cópia de trabalho **Subversion**, vês que ficheiros mudaram desde
a revisão e podes voltar a pô-los «por rever». Se quiseres, ligas o **SonarQube** (opcional, por utilizador)
para veres os problemas abertos por ficheiro. O progresso exporta-se em JSON, no mesmo formato
das páginas HTML offline.

![Checklist de revisão](docs/images/04-checklist.png)

### Acompanhar o progresso

O **Painel** reúne os números e os gráficos — evolução do progresso, progresso por camada, maiores units,
distribuição de métodos, Compila e Sonar — e segue o tema da aplicação.

![Painel](docs/images/05-painel.png)

<sub>O histórico da evolução nas imagens é de demonstração; o resto são dados reais da análise do próprio CodeManager.</sub>

### Aspeto à tua maneira

A página **Aspeto** muda a **cor de destaque** (cores prontas ou qualquer `#RRGGBB`, com contraste garantido nos dois
temas), as **fontes** da interface e do código, a **escala do texto** e o **tamanho do código**.

![Aspeto](docs/images/18-aspeto-escuro.png)

### Idiomas e repositórios do GitHub

A aplicação fala **português, inglês, francês e alemão** (muda-se na página Projeto, e os relatórios exportados
seguem o idioma). Em vez de uma pasta, podes analisar um **repositório do GitHub**: clona-se só a última versão para
uma cache própria, em modo só leitura.

### Tema claro e escuro

| Mapa | Checklist | Painel |
|---|---|---|
| ![Mapa escuro](docs/images/09-mapa-escuro.png) | ![Checklist escura](docs/images/08-checklist-escuro.png) | ![Painel escuro](docs/images/07-painel-escuro.png) |

### Exportar

| Formato | Para quê |
|---|---|
| **Markdown / TXT** | Colar em documentação ou numa *issue*; o Markdown serve também de plano |
| **CSV** (separador `;`) | Abrir no Excel, em colunas |
| **JSON** | Integrar com outras ferramentas |
| **Páginas HTML offline** | Partilhar o mapa e a checklist interativa, sem instalar nada |
| **Papel / PDF** | Impressão com paginação e rodapé «Página X de N» |

## Plano × código

Escreve o que o projeto *deve* ter num documento Markdown — uma árvore, títulos com blocos de código, uma lista de
assinaturas, ou tudo misturado — e aponta o projeto para ele. Com pasta de código **e** plano, o Mapa compara-os:

![Mapa com o cruzamento plano × código](docs/images/03-mapa-plano.png)

| Etiqueta | Significa |
|---|---|
| `PLANEADO` | Está no plano e ainda não existe no código |
| `EXTRA` | Existe no código mas não está no plano |
| `MOVIDO` | Existe, mas noutra pasta |

Um plano mínimo, só com uma árvore:

````markdown
```text
src/
├── Core/
│   ├── CM.Analyzer.pas
│   └── CM.Plan.pas
└── UI/
    └── CM.MainForm.pas
```
````

Sem pasta de código, o documento é analisado sozinho — útil para rever o desenho antes de haver código. Todos os
estilos aceites, as regras de correspondência e um exemplo estão em [docs/FORMATO-DO-PLANO.md](docs/FORMATO-DO-PLANO.md).

## Como funciona

```mermaid
flowchart LR
    C["Pasta de código<br/>.pas · .dpr · .dpk"] --> A["Análise<br/>ficheiros → métodos"]
    P["Plano .md<br/>(opcional)"] --> A
    A --> V["Vista cruzada<br/>plano × código"]
    V --> M["Mapa"]
    A --> K["Checklist"]
    A --> D["Painel"]
    K --> S[("Progresso e histórico<br/>%APPDATA%")]
    D --> S
    M --> X["Exportar<br/>MD · TXT · CSV · JSON · HTML · papel"]
    K --> X
```

O motor de análise (`Core`) não depende de interface nem do Windows; a interface em FireMonkey é desenhada em
código e segue o tema. As camadas e as suas regras estão explicadas, com diagramas, em
[docs/ARQUITETURA.md](docs/ARQUITETURA.md).

Os teus dados ficam em `%APPDATA%\CodeManager` (`settings.json`, `progress-<id>.json`, `history-<id>.json`). A
aplicação **só lê** os ficheiros do projeto analisado.

## Alterações

O que mudou na **versão 1.0.1** (a lista completa, versão a versão, está no [registo de alterações](CHANGELOG.md)):

**Novas páginas**
- **Grafo** — o mapa visual de quem usa quem (cláusulas `uses`), com acoplamento, instabilidade, ciclos e relatório em HTML ou Markdown.
- **Código** — leitura do código em separadores, aberta por duplo clique no Grafo, no Mapa ou na Checklist; realce Delphi, salto para o método e fonte moderna com ligaduras.
- **Aspeto** — cor de destaque, fontes, escala do texto e tamanho do código, só para ti.
- **Acerca** — versão, compilação, ambiente, ligações úteis e «Copiar informação» para as *issues*.

**Melhorias**
- **Mais métricas por método** — complexidade cognitiva, número de parâmetros e aninhamento de blocos (no Mapa, na dica, no Painel, no CSV, no JSON e nas páginas HTML).
- **SonarQube** — medidas do projeto e de cada ficheiro (cobertura, duplicação, dívida técnica, classificações A–E), o detalhe dos problemas e os *hotspots*; vê-se no Mapa, na página Código e no Painel.
- **Subversion** — «alterado desde a revisão» também em cópias de trabalho do Subversion (além do Git).
- **Idiomas** — português, inglês, francês e alemão, incluindo as páginas HTML exportadas.
- **Repositórios do GitHub** — analisar um repositório em vez de uma pasta (só leitura).

**Nos bastidores**
- Cerca de 200 testes automáticos novos (agora mais de 710), incluindo testes contra um repositório Subversion real.
- Gerador de traduções corrigido, e documentação e imagens atualizadas.

## Documentação

| Documento | Para quê |
|---|---|
| [Guia do utilizador](docs/GUIA-DO-UTILIZADOR.md) | Usar a aplicação, página a página |
| [Formato do plano](docs/FORMATO-DO-PLANO.md) | Escrever o documento de plano e perceber o cruzamento |
| [Arquitetura](docs/ARQUITETURA.md) | Camadas, modelo de dados, fluxos e decisões de desenho |
| [Desenvolvimento](docs/DESENVOLVIMENTO.md) | Compilar, testar, modo `--dev`, receitas para estender |
| [Contribuir](CONTRIBUTING.md) | Reportar erros, propor ideias, enviar código |
| [Registo de alterações](CHANGELOG.md) | O que mudou |

## Estado do projeto

Versão **1.0.1**. Em desenvolvimento ativo, desenvolvido e testado em **Windows / Win64** com **Delphi 13**. Mais de 710 testes
automáticos cobrem o motor, as exportações, o vigia e as regras de arquitetura; a interface é verificada com o
[modo de desenvolvimento](docs/DESENVOLVIMENTO.md#modo-de-desenvolvimento---dev).

Ideias para o futuro: mais métricas por classe (profundidade de herança). Sugestões são bem-vindas.

## Contribuir

Contribuições são bem-vindas — erros, ideias, documentação e código. Começa por [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença e créditos

Distribuído sob a [licença MIT](LICENSE).

Os gráficos do Painel usam o [Chart4D](https://github.com/GDKsoftware/Chart4D) (MIT, GDK Software); os testes usam
o DUnitX. Ver [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

<p align="center">
  <a href="https://www.buymeacoffee.com/joaofsferreira">
    <img
      src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&amp;emoji=&amp;slug=joaofsferreira&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Lato&amp;outline_colour=000000&amp;coffee_colour=ffffff"
      alt="Buy me a coffee">
  </a>
</p>
