# Formato do plano (documento Markdown)

Um **plano** é um documento Markdown que descreve a estrutura e o código que um projeto *deverá ter*: pastas,
ficheiros e, se quiseres, os métodos de cada um. O CodeManager lê-o e:

- cruza-o com o código real (Mapa: o que está **implementado**, o que está **planeado** e ainda não existe, o que é
  **extra**), ou
- analisa-o sozinho, como se fosse o código, para rever o desenho **antes** de haver código (Mapa, Checklist, Painel).

Não há um formato obrigatório. O leitor é **tolerante**: reconhece vários estilos, que podes misturar no mesmo
documento e por qualquer ordem. Este guia mostra o que é reconhecido, como é interpretado e como evitar surpresas.

- [Começar depressa](#começar-depressa)
- [O que é reconhecido](#o-que-é-reconhecido)
- [Como os blocos de código encontram o ficheiro](#como-os-blocos-de-código-encontram-o-ficheiro)
- [Como o plano é cruzado com o código](#como-o-plano-é-cruzado-com-o-código)
- [Avisos e problemas comuns](#avisos-e-problemas-comuns)
- [Escrever o plano com um assistente de IA](#escrever-o-plano-com-um-assistente-de-ia)
- [Exemplo completo](#exemplo-completo)

## Começar depressa

1. Escreve (ou gera) um `.md` com os ficheiros do projeto. O mínimo útil é uma árvore:

   ````markdown
   ```text
   src/
   ├── Core/
   │   ├── CM.Analyzer.pas
   │   └── CM.Store.pas
   └── UI/
       └── CM.MainForm.pas
   ```
   ````

2. Na página **Projeto**, preenche **Documento do plano (.md)** (ou escolhe o ficheiro com o botão da pasta).
3. Carrega em **Analisar projeto**.

| Pasta de código | Documento | Resultado |
|---|---|---|
| preenchida | vazio | análise do código, como sempre |
| preenchida | preenchido | **cruzamento** no Mapa |
| vazia | preenchido | o documento é analisado como se fosse o código |

> **Dica:** o Markdown que a própria aplicação exporta (Mapa › **Markdown**) já é um plano válido. Podes exportar o
> estado atual, editá-lo (apagar o que já não faz sentido, acrescentar ficheiros e métodos novos) e usá-lo como plano.

## O que é reconhecido

Só se consideram **ficheiros de código Delphi**: `.pas`, `.dpr` e `.dpk`. Outros ficheiros (imagens, `.md`, `.dfm`…)
são ignorados nas árvores.

### 1. Título com o caminho do ficheiro + bloco de código

O estilo mais completo: o título diz que ficheiro é; o bloco diz que métodos tem.

````markdown
## src/Core/CM.Analyzer.pas

```pascal
unit CM.Analyzer;

interface

function ScanProject(const ARoot: string): TProjectScan;
procedure TProjectScan.Recount;

implementation
end.
```
````

O bloco pode ter a unit inteira ou **só as declarações** (sem `unit`, `interface` ou `implementation`). Métodos de
classes (`TProjectScan.Recount`) também são reconhecidos.

### 2. Título com o caminho + lista de assinaturas

Mais leve: só os nomes e assinaturas, sem escrever Pascal completo.

```markdown
## src/Core/CM.Plan.pas

- `function ParsePlan(const AText: string): TProjectScan;`
- `function MergePlan(ACode, APlan: TProjectScan): TProjectScan;`
```

Cada item que comece por `function`, `procedure`, `constructor`, `destructor` ou `operator` (com ou sem `class`) é
uma assinatura e fica associado ao **último ficheiro mencionado**.

### 3. Árvore de pastas

Num bloco de texto, com os caracteres de desenho de árvore (`├──`, `└──`, `│`) ou só com **indentação**:

````markdown
```text
src/
  Core/
    CM.Analyzer.pas   # análise de pastas
    CM.Store.pas
  UI/
    CM.MainForm.pas
```
````

- Nomes terminados em `/`, ou sem extensão, são pastas.
- Comentários no fim da linha (` # …` ou ` // …`) são ignorados.
- Uma árvore só dá ficheiros (sem métodos): combina-a com os estilos 1 e 2 para os detalhar.

### 4. Listas aninhadas

Pastas, ficheiros e assinaturas numa lista Markdown indentada. É o formato que a aplicação exporta:

```markdown
- **`src/`** _(2 ficheiros)_
  - **`Core/`** _(1 ficheiro)_
    - `CM.Analyzer.pas`
      - `function ScanProject(const ARoot: string): TProjectScan;`
  - **`UI/`** _(1 ficheiro)_
    - `CM.MainForm.pas`
```

Também funcionam as caixas de tarefa (`- [ ]` / `- [x]`) e a decoração do export — `**negrito**`, `` `código` ``,
`_(n ficheiros)_`, `[Compila]`, `[Sonar]`, `★` e `— nota: …` — que é retirada antes de interpretar.

**Um item de lista só conta como ficheiro** se depois do caminho vier nada ou uma anotação (`— descrição`,
`# nota`, `(nota)`, `: nota`). Uma frase como «`src/A.pas` existe mas não está no plano» é prosa e é ignorada.

### 5. Pastas por título

Um título que seja só um nome de pasta define a pasta dos ficheiros seguintes que venham sem caminho:

````markdown
### src/Core/

```pascal
unit CM.Plan;
interface
function ParsePlan(const AText: string): TProjectScan;
implementation
end.
```
````

Aqui o ficheiro fica `src/Core/CM.Plan.pas`, deduzido do `unit CM.Plan;`.

## Como os blocos de código encontram o ficheiro

Para cada bloco de código Pascal, o ficheiro é decidido por esta ordem — o primeiro que existir ganha:

| # | De onde vem o caminho | Exemplo |
|---|---|---|
| 1 | Linha de abertura do bloco | ```` ```pascal src/UI/CM.X.pas ```` |
| 2 | Linha anterior: título, item de lista ou parágrafo com um caminho (parágrafos de texto **sem** caminho não interrompem a associação) | `## src/UI/CM.X.pas` |
| 3 | Comentário na primeira linha do bloco | `// src/UI/CM.X.pas` |
| 4 | O último ficheiro mencionado, se o `unit` do bloco coincidir com o nome (ou não houver `unit`) | — |
| 5 | O nome do `unit X;`, na pasta do último título de pasta | `unit CM.X;` → `<pasta>/CM.X.pas` |

Se nenhum se aplicar, o bloco é **ignorado** e aparece um aviso com o número da linha.

Mais regras:

- Caminhos com `\` são normalizados para `/`; maiúsculas e minúsculas não contam.
- Se o mesmo ficheiro for mencionado várias vezes, **junta-se**: os métodos somam-se.
- Um bloco de código não fechado é lido até ao fim do documento.
- O documento é lido em UTF-8.

## Como o plano é cruzado com o código

Quando há pasta de código **e** plano, o Mapa mostra a comparação:

| Etiqueta | Significa |
|---|---|
| *(nenhuma)* | Existe no plano e no código |
| `PLANEADO` | Está no plano e **ainda não existe** no código. Os métodos planeados aparecem em itálico. |
| `EXTRA` | Existe no código mas **não está no plano** |
| `MOVIDO` | Está no código noutra pasta do que o plano prevê (a dica diz onde estava planeado) |

E as estatísticas do Mapa ganham: **Plano · ficheiros** e **Plano · métodos** (implementado / planeado e a
percentagem), **Por implementar** e **Extra no código**.

### Regras de correspondência

- **Ficheiros:** primeiro pelo caminho; os que sobram, pelo nome do ficheiro **se for único** dos dois lados
  (`MOVIDO`).
- **Métodos:** pelo nome qualificado (`TFoo.Bar`, ou `TFoo.Bar(Integer)` num overload); os que sobram, pelo nome
  simples **se for único** dos dois lados. Em caso de dúvida, não adivinha.
- **Nome do projeto na árvore.** Se o plano começa em `MeuProjeto/src/…` e o código em `src/…`, a pasta de topo
  é ignorada automaticamente, desde que o código não a tenha e retirá-la faça coincidir pelo menos um caminho.
- **Ficheiros sem métodos no plano.** Se o plano lista um ficheiro sem detalhar métodos (por exemplo, só numa
  árvore), os métodos do código **não** são julgados nem marcados como extra.
- **Métodos extra** só se contam em ficheiros que existem nos dois lados.

### Cobertura

`cobertura = implementado / planeado`, para ficheiros e para métodos. O que o plano não prevê não a baixa.

## Avisos e problemas comuns

Os avisos da leitura aparecem na barra de estado da página Projeto (a contagem e o primeiro aviso).

| Aviso / sintoma | Causa provável | O que fazer |
|---|---|---|
| «bloco de código sem caminho de ficheiro — ignorado» | O bloco não tem título, caminho na abertura, comentário nem `unit` | Põe um título `## caminho/Ficheiro.pas` antes do bloco |
| «assinatura de método sem ficheiro associado» | Uma lista de assinaturas sem nenhum ficheiro antes | Acrescenta o título do ficheiro |
| «O documento não contém nenhum ficheiro» | Não há nenhum `.pas`, `.dpr` ou `.dpk` | Confirma as extensões e os caminhos |
| Tudo aparece como `EXTRA` e `PLANEADO` | Os caminhos do plano não coincidem com os do código | Compara os caminhos; usa caminhos **relativos à pasta do projeto** |
| Um ficheiro aparece duas vezes | Escrito com dois caminhos diferentes (ex.: com e sem pasta de topo) | Usa sempre o mesmo caminho |
| Métodos do código não aparecem como `EXTRA` | O plano não lista métodos desse ficheiro | É o comportamento esperado: sem métodos no plano, nada é julgado |

O leitor não substitui uma revisão humana: se uma lista de funcionalidades (prosa) tiver itens que começam por um
caminho de ficheiro seguido de texto livre, esse texto invalida o item de propósito, para a prosa não virar ficheiro.

## Escrever o plano com um assistente de IA

Um modelo de linguagem escreve bons planos neste formato. Um pedido que costuma funcionar:

> Escreve o plano de um projeto Delphi chamado *X* em Markdown. Para cada unit, usa um título
> `## caminho/relativo/Unit.pas` seguido de um bloco ```` ```pascal ```` só com as declarações públicas
> (funções, procedimentos e métodos de classes), sem implementação. Agrupa por pastas: `src/Core`, `src/UI`…
> Termina com uma árvore de pastas num bloco de texto.

Depois é só guardar o resultado num `.md` e apontar o projeto para ele. Voltar a analisar atualiza a comparação à
medida que o código vai nascendo.

## Exemplo completo

Há um exemplo pequeno em [`plano-exemplo.md`](plano-exemplo.md) e um mais completo, usado nas imagens desta
documentação, em [`../tools/demo/plano-demo.md`](../tools/demo/plano-demo.md).

````markdown
# Plano do CodeManager

## src/Core/CM.Analyzer.pas

```pascal
unit CM.Analyzer;
interface
function ScanProject(const ARoot: string): TProjectScan;
procedure SincronizarComGit;
implementation
end.
```

## src/Core/CM.Plan.pas

- `function ParsePlan(const AText: string): TProjectScan;`
- `function MergePlan(ACode, APlan: TProjectScan): TProjectScan;`

## Resto da estrutura

```text
src/
├── Services/
│   ├── CM.Export.pas
│   └── CM.Pdf.pas        # exportação direta para PDF
└── UI/
    └── CM.MainForm.pas
```
````

Se o código tiver `ScanProject` e `CM.Export`, mas não `SincronizarComGit` nem `CM.Pdf`, o Mapa mostra
`CM.Pdf.pas` como `PLANEADO` e `SincronizarComGit` como método planeado em `CM.Analyzer.pas`.
