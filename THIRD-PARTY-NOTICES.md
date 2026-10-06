# Software de terceiros

O CodeManager usa os componentes abaixo. Os seus avisos de licença acompanham este repositório.

## Chart4D

Gráficos do Painel. É compilado a partir do código-fonte para dentro do executável.

- Projeto: <https://github.com/GDKsoftware/Chart4D> (instalado pelo GetIt do Delphi)
- Versão usada: 1.2.0
- Licença: MIT

```text
MIT License

Copyright (c) 2026 GDK Software

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## DUnitX

Framework de testes (só usado nos testes, não faz parte do executável). Distribuído com o Delphi.

- Projeto: <https://github.com/VSoftTechnologies/DUnitX>
- Licença: Apache License 2.0

## Material Design Icons

Os ícones da interface (`CM.Theme`) são formas vetoriais dos Material Design Icons da Google.

- Projeto: <https://github.com/google/material-design-icons>
- Licença: Apache License 2.0 (<https://www.apache.org/licenses/LICENSE-2.0>)

## DX.Comply

A funcionalidade **SBOM** (a página SBOM, o relatório e os formatos CycloneDX e SPDX) adapta ideias e regras do DX.Comply:
as regras de classificação da origem das units, a leitura do ficheiro `.map`, a estrutura dos documentos CycloneDX 1.5 e
SPDX 2.3 e o desenho dos relatórios. O código do CodeManager é próprio, escrito para a sua arquitetura (só leitura, sem
IDE nem compilação), e está nas unidades `CM.Sbom`, `CM.Dproj`, `CM.MapFile`, `CM.SbomResolve`, `CM.SbomFormats`,
`CM.SbomReport` e `CM.SbomService`.

- Projeto: <https://github.com/omonien/DX.Comply>
- Autor: Olaf Monien
- Licença: MIT

```text
MIT License

Copyright (c) 2026 Olaf Monien

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## DelphiNodeEditor

A forma dos nós e das ligações em curva do mapa de dependências inspira-se neste projeto; o código do CodeManager é
próprio (não copia o do DelphiNodeEditor).

- Projeto: <https://github.com/HemulGM/DelphiNodeEditor>
- Autor: HemulGM
- Licença: MIT

