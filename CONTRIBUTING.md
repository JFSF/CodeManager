# Como contribuir

Obrigado por quereres ajudar! Este guia explica como reportar problemas, propor ideias e enviar alterações.

## Reportar um problema

Abre uma *issue* com o modelo «Relatório de erro». O que mais ajuda:

- o que fizeste, o que esperavas e o que aconteceu;
- a versão do Windows e como obtiveste a aplicação (compilada por ti, versão, etc.);
- se o problema depende de um projeto: um exemplo mínimo (algumas units) ou, num problema com um plano, o `.md`;
- uma captura de ecrã, quando for visual.

Não incluas código ou dados que não possas partilhar.

## Propor uma funcionalidade

Abre uma *issue* com o modelo «Pedido de funcionalidade» e descreve **o problema que queres resolver** antes da
solução. Para mudanças grandes, combina primeiro a abordagem: poupa trabalho a ambos.

## Enviar código

1. Faz *fork* e cria um ramo a partir de `master`.
2. Prepara o ambiente — ver [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md) (Delphi 13 e Chart4D).
3. Faz a alteração, **com testes** quando mexe em lógica (`Core`, `Services`).
4. Corre `ci.bat`. Tem de compilar e passar todos os testes.
5. Atualiza a documentação e o [CHANGELOG](CHANGELOG.md) se a alteração for visível para quem usa a aplicação.
6. Abre o *pull request* a explicar **o quê e porquê**.

### O que pedimos

- **Respeita as camadas.** `Core` só usa a RTL; `Services` não importa `UI`. O teste `Tests.Architecture` verifica.
- **Segue o estilo do código à volta** (ver [convenções](docs/DESENVOLVIMENTO.md#convenções)): UTF-8 com BOM,
  comentários e interface em português, cores sempre pela paleta do tema.
- **Mantém os commits pequenos e com mensagens claras.**
- **Mudanças na interface:** junta uma captura (a aplicação tem um
  [modo de desenvolvimento](docs/DESENVOLVIMENTO.md#modo-de-desenvolvimento---dev) que facilita) e confirma os dois
  temas, claro e escuro.
- **Mudanças no formato do plano:** acrescenta testes em `tests\Tests.Plan.pas` e atualiza
  [docs/FORMATO-DO-PLANO.md](docs/FORMATO-DO-PLANO.md).

## Comportamento

Trata toda a gente com respeito. Críticas ao código são bem-vindas; ataques às pessoas não.

## Licença

Ao contribuíres, aceitas que a tua contribuição seja licenciada sob a [licença MIT](LICENSE) do projeto.
