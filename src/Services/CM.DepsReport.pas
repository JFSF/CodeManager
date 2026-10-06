unit CM.DepsReport;

{ Relatorio de dependencias entre as units: Markdown e uma pagina HTML autonoma (sem servidor, com o mapa em SVG,
  tabelas ordenaveis e filtro). O Markdown segue o idioma activo (CM.Lang). A pagina HTML nasce no idioma activo mas
  leva as frases nos quatro idiomas (pt, en, fr, de) e um seletor de idioma, para quem a abrir noutro idioma. }

interface

uses
  System.SysUtils, CM.Deps;

function DepsMarkdown(AGraph: TDepGraph; const AProjectName: string): string;
function DepsHtml(AGraph: TDepGraph; const AProjectName, ARootDisplay: string): string;
// <nome-do-projecto>-dependencias.md / .html
function DepsDefaultFileName(const AProjectName, AExt: string): string;
procedure SaveDepsReport(const AFileName, AContent: string);

implementation

uses
  System.Classes, System.IOUtils, System.Math, System.Generics.Collections, System.Generics.Defaults,
  CM.Lang, CM.Analyzer, CM.HtmlLang;

const
  // medidas do mapa em SVG (as mesmas do mapa da aplicacao)
  ColW = 300;
  RowH = 46;
  NodeW = 232;
  NodeH = 34;
  Margin = 40;

function HtmlEsc(const AText: string): string;
begin
  Result := AText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function MdCell(const AText: string): string;
begin
  Result := AText.Replace('|', '\|').Replace(#13, ' ').Replace(#10, ' ');
end;

function Pct(AValue: Double): string;
begin
  Result := FormatFloat('0.00', AValue);
end;

function ColorHex(AColor: Cardinal): string;
begin
  Result := '#' + IntToHex(AColor and $FFFFFF, 6);
end;

function LayerColorOf(AGraph: TDepGraph; const ALayer: string): string;
var
  Layers: TArray<string>;
  I: Integer;
begin
  Layers := AGraph.Layers;
  for I := 0 to High(Layers) do
    if Layers[I] = ALayer then
      Exit(ColorHex(DepLayerPalette[I mod Length(DepLayerPalette)]));
  Result := '#8A94A6';
end;

function NameList(AGraph: TDepGraph; const AIdx: TArray<Integer>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AIdx) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + AGraph.Nodes[AIdx[I]].Name;
  end;
end;

// units de fora do projecto, da mais usada para a menos; Names/Counts em paralelo
procedure ExternalUsage(AGraph: TDepGraph; out ANames: TArray<string>; out ACounts: TArray<Integer>);
var
  D: TDictionary<string, Integer>;
  N: TDepNode;
  S: string;
  P: TPair<string, Integer>;
  L: TList<TPair<string, Integer>>;
  I: Integer;
  C: Integer;
begin
  D := TDictionary<string, Integer>.Create;
  L := TList<TPair<string, Integer>>.Create;
  try
    for N in AGraph.Nodes do
      for S in N.External do
        if D.TryGetValue(S, C) then
          D[S] := C + 1
        else
          D.Add(S, 1);
    for P in D do
      L.Add(P);
    L.Sort(TComparer<TPair<string, Integer>>.Construct(
      function(const A, B: TPair<string, Integer>): Integer
      begin
        Result := B.Value - A.Value;
        if Result = 0 then
          Result := CompareText(A.Key, B.Key);
      end));
    SetLength(ANames, L.Count);
    SetLength(ACounts, L.Count);
    for I := 0 to L.Count - 1 do
    begin
      ANames[I] := L[I].Key;
      ACounts[I] := L[I].Value;
    end;
  finally
    L.Free;
    D.Free;
  end;
end;

function Density(AGraph: TDepGraph): Double;
begin
  if AGraph.Nodes.Count = 0 then
    Result := 0
  else
    Result := AGraph.Edges.Count / AGraph.Nodes.Count;
end;

{ Markdown }

function DepsMarkdown(AGraph: TDepGraph; const AProjectName: string): string;
var
  SB: TStringBuilder;
  N: TDepNode;
  I, K, Shown: Integer;
  Top: TArray<TDepNode>;
  Links: TArray<TLayerLink>;
  Names: TArray<string>;
  Counts: TArray<Integer>;
  Unused: TArray<TDepNode>;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('# ').Append(Tr('Dependências entre units')).Append(' — ').Append(AProjectName).AppendLine.AppendLine;
    SB.Append('- ').Append(Tr('Gerado em: ')).AppendLine(FormatDateTime('yyyy-mm-dd hh:nn', Now));
    SB.Append('- ').Append(Tr('Units')).Append(': ').Append(AGraph.Nodes.Count).AppendLine;
    SB.Append('- ').Append(Tr('Ligações')).Append(': ').Append(AGraph.Edges.Count).AppendLine;
    SB.Append('- ').Append(Tr('Units externas')).Append(': ').Append(AGraph.ExternalCount).AppendLine;
    SB.Append('- ').Append(Tr('Ciclos')).Append(': ').Append(Length(AGraph.Cycles)).AppendLine;
    SB.Append('- ').Append(Tr('Colunas do mapa')).Append(': ').Append(AGraph.LevelCount).AppendLine;
    SB.Append('- ').Append(Tr('Ligações por unit')).Append(': ').AppendLine(Pct(Density(AGraph))).AppendLine;

    SB.Append('## ').AppendLine(Tr('Ciclos')).AppendLine;
    if Length(AGraph.Cycles) = 0 then
      SB.AppendLine(Tr('Nenhum ciclo: as units não se usam em círculo.')).AppendLine
    else
    begin
      for I := 0 to High(AGraph.Cycles) do
        SB.Append(Format('%d. ', [I + 1])).Append(Tr('Units que se usam umas às outras')).Append(': ')
          .AppendLine(NameList(AGraph, AGraph.Cycles[I]));
      SB.AppendLine;
    end;

    SB.Append('## ').AppendLine(Tr('Mais usadas')).AppendLine;
    SB.Append('| ').Append(Tr('Unit')).Append(' | ').Append(Tr('Camada')).Append(' | ').Append(Tr('Usada por'))
      .AppendLine(' |');
    SB.AppendLine('|---|---|---:|');
    Top := AGraph.TopFanIn(10);
    for N in Top do
      if N.FanIn > 0 then
        SB.Append('| `').Append(N.Name).Append('` | ').Append(MdCell(N.Layer)).Append(' | ').Append(N.FanIn).AppendLine(' |');
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Mais dependentes')).AppendLine;
    SB.Append('| ').Append(Tr('Unit')).Append(' | ').Append(Tr('Camada')).Append(' | ').Append(Tr('Usa'))
      .AppendLine(' |');
    SB.AppendLine('|---|---|---:|');
    Top := AGraph.TopFanOut(10);
    for N in Top do
      if N.FanOut > 0 then
        SB.Append('| `').Append(N.Name).Append('` | ').Append(MdCell(N.Layer)).Append(' | ').Append(N.FanOut).AppendLine(' |');
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Ligações entre camadas')).AppendLine;
    Links := AGraph.LayerLinks;
    if Length(Links) = 0 then
      SB.AppendLine(Tr('Não há ligações entre camadas diferentes.')).AppendLine
    else
    begin
      SB.Append('| ').Append(Tr('De')).Append(' | ').Append(Tr('Para')).Append(' | ').Append(Tr('Ligações'))
        .AppendLine(' |');
      SB.AppendLine('|---|---|---:|');
      for I := 0 to High(Links) do
        SB.Append('| ').Append(MdCell(Links[I].FromLayer)).Append(' | ').Append(MdCell(Links[I].ToLayer)).Append(' | ')
          .Append(Links[I].Count).AppendLine(' |');
      SB.AppendLine;
    end;

    SB.Append('## ').AppendLine(Tr('Units sem uso')).AppendLine;
    Unused := AGraph.Unused;
    if Length(Unused) = 0 then
      SB.AppendLine(Tr('Todas as units são usadas por outra.')).AppendLine
    else
    begin
      for N in Unused do
        SB.Append('- `').Append(N.Name).Append('` (').Append(MdCell(N.Layer)).AppendLine(')');
      SB.AppendLine;
    end;

    SB.Append('## ').AppendLine(Tr('Units de fora mais usadas')).AppendLine;
    ExternalUsage(AGraph, Names, Counts);
    SB.Append('| ').Append(Tr('Unit')).Append(' | ').Append(Tr('Usada por')).AppendLine(' |');
    SB.AppendLine('|---|---:|');
    Shown := Min(15, Length(Names));
    for K := 0 to Shown - 1 do
      SB.Append('| `').Append(Names[K]).Append('` | ').Append(Counts[K]).AppendLine(' |');
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Todas as units')).AppendLine;
    SB.Append('| ').Append(Tr('Unit')).Append(' | ').Append(Tr('Camada')).Append(' | ').Append(Tr('Métodos'))
      .Append(' | ').Append(Tr('Linhas')).Append(' | ').Append(Tr('Complexidade')).Append(' | ').Append(Tr('Usa'))
      .Append(' | ').Append(Tr('Usada por')).Append(' | ').Append(Tr('Instabilidade')).AppendLine(' |');
    SB.AppendLine('|---|---|---:|---:|---:|---:|---:|---:|');
    for N in AGraph.Nodes do
      SB.Append('| `').Append(N.Name).Append('` | ').Append(MdCell(N.Layer)).Append(' | ').Append(N.Methods)
        .Append(' | ').Append(N.Lines).Append(' | ').Append(N.MaxComplexity).Append(' | ').Append(N.FanOut)
        .Append(' | ').Append(N.FanIn).Append(' | ').Append(Pct(N.Instability)).AppendLine(' |');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ HTML + SVG }

const
  HtmlCss =
    ':root{--bg:#f6f7f4;--surface:#fff;--surface2:#eef0eb;--border:#dcded7;--text:#1b1d1a;--dim:#5a5f58;--faint:#8b908a;' +
    '--accent:#216b59;--accent2:#e0ece8;--danger:#c5523d;--blue:#3f7fe0}' +
    '@media(prefers-color-scheme:dark){:root{--bg:#121514;--surface:#1a1e1d;--surface2:#222726;--border:#2e3433;' +
    '--text:#e8ebe8;--dim:#a3aaa5;--faint:#6f7772;--accent:#4fb89b;--accent2:#1e2f2b;--danger:#e0705a;--blue:#6fa8ff}}' +
    '*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 "Segoe UI",system-ui,sans-serif}' +
    '.wrap{max-width:1280px;margin:0 auto;padding:28px 24px 60px}h1{margin:0 0 4px;font-size:26px}' +
    'h2{margin:34px 0 12px;font-size:18px}.sub{color:var(--dim);margin:0 0 20px}' +
    '.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}' +
    '.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 16px}' +
    '.card b{display:block;font:700 26px Consolas,monospace}.card span{color:var(--dim);font-size:12.5px}' +
    '.map{background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:auto;max-height:78vh}' +
    '.map svg{display:block}.legend{display:flex;flex-wrap:wrap;gap:14px;margin:10px 0;color:var(--dim);font-size:12.5px}' +
    '.legend i{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:6px;vertical-align:-1px}' +
    'table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:12px;' +
    'overflow:hidden}th,td{padding:7px 12px;text-align:left;border-bottom:1px solid var(--border);font-size:13px}' +
    'th{background:var(--surface2);color:var(--dim);font-weight:600;cursor:pointer;user-select:none;white-space:nowrap}' +
    'td.n,th.n{text-align:right;font-family:Consolas,monospace}td.m{font-family:Consolas,monospace}' +
    'tr:last-child td{border-bottom:0}.bar{display:inline-block;height:7px;border-radius:4px;background:var(--accent);' +
    'vertical-align:middle;margin-right:6px}.tag{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11.5px;' +
    'background:var(--accent2);color:var(--accent)}.tag.red{background:transparent;border:1px solid var(--danger);color:var(--danger)}' +
    'input.f{width:100%;max-width:340px;padding:8px 12px;border:1px solid var(--border);border-radius:9px;background:var(--surface);' +
    'color:var(--text);margin-bottom:10px}.hint{color:var(--faint);font-size:12.5px;margin:8px 0}' +
    'svg text{font-family:Consolas,monospace;fill:var(--text)}svg .sub{fill:var(--faint);font:9.5px "Segoe UI",sans-serif}' +
    'svg .node rect.b{fill:var(--surface);stroke:var(--border);stroke-width:1}svg .node{cursor:pointer}' +
    'svg .edge{fill:none;stroke:var(--faint);stroke-opacity:.45;stroke-width:1}svg .edge.cyc{stroke:var(--danger);stroke-opacity:.8}' +
    'svg .edge.impl{stroke-dasharray:5 4}svg.sel .edge{stroke-opacity:.08}svg.sel .node{opacity:.3}' +
    'svg.sel .node.on,svg.sel .node.src,svg.sel .node.dst{opacity:1}svg .edge.out{stroke:var(--accent);stroke-opacity:1;stroke-width:2.2}' +
    'svg .edge.in{stroke:var(--blue);stroke-opacity:1;stroke-width:2.2}svg .node.on rect.b{stroke:var(--accent);stroke-width:2}' +
    'svg .node.src rect.b{stroke:var(--blue);stroke-width:2}svg .node.dst rect.b{stroke:var(--accent);stroke-width:2}' +
    '.names{color:var(--dim);font-family:Consolas,monospace;font-size:12.5px}';


  HtmlJs =
    '(function(){var svg=document.getElementById("g");if(!svg)return;var N=svg.querySelectorAll(".node"),E=svg.querySelectorAll(".edge");' +
    'function clear(){svg.classList.remove("sel");N.forEach(function(n){n.classList.remove("on","src","dst")});' +
    'E.forEach(function(e){e.classList.remove("out","in")})}' +
    'var cur=null;N.forEach(function(n){n.addEventListener("click",function(ev){ev.stopPropagation();var i=n.dataset.i;' +
    'if(cur===i){clear();cur=null;return}clear();cur=i;svg.classList.add("sel");n.classList.add("on");' +
    'E.forEach(function(e){if(e.dataset.s===i){e.classList.add("out");svg.querySelector(".node[data-i=''"+e.dataset.t+"'']").classList.add("dst")}' +
    'else if(e.dataset.t===i){e.classList.add("in");svg.querySelector(".node[data-i=''"+e.dataset.s+"'']").classList.add("src")}})})});' +
    'svg.addEventListener("click",function(){clear();cur=null});' +
    'document.querySelectorAll("table.sort").forEach(function(t){var h=t.querySelectorAll("th");h.forEach(function(th,ci){' +
    'th.addEventListener("click",function(){var rows=[].slice.call(t.tBodies[0].rows),asc=th.dataset.asc!=="1";th.dataset.asc=asc?"1":"0";' +
    'var num=th.classList.contains("n");rows.sort(function(a,b){var x=a.cells[ci].dataset.v||a.cells[ci].textContent,y=b.cells[ci].dataset.v||b.cells[ci].textContent;' +
    'if(num){x=parseFloat(x)||0;y=parseFloat(y)||0}else{x=x.toLowerCase();y=y.toLowerCase()}return(x<y?-1:x>y?1:0)*(asc?1:-1)});' +
    'rows.forEach(function(r){t.tBodies[0].appendChild(r)})})})});' +
    'var f=document.getElementById("flt");if(f)f.addEventListener("input",function(){var q=f.value.toLowerCase();' +
    'document.querySelectorAll("#all tbody tr").forEach(function(r){r.style.display=r.textContent.toLowerCase().indexOf(q)<0?"none":""})});})();';

function NodeX(N: TDepNode): Integer;
begin
  Result := Margin + N.Level * ColW;
end;

function BuildSvg(AGraph: TDepGraph; ATable: TStrTable): string;
var
  SB: TStringBuilder;
  ColSizes: TArray<Integer>;
  MaxRows, I, W, H: Integer;
  N, S, T: TDepNode;
  E: TDepEdge;
  X, Y, X1, Y1, X2, Y2, Dx: Double;
  Cls: string;
  Name: string;
  Fmt: TFormatSettings;

  function NodeY(ANode: TDepNode): Double;
  begin
    Result := Margin + ANode.Row * RowH + (MaxRows - ColSizes[ANode.Level]) * RowH / 2;
  end;

  function F(AValue: Double): string;
  begin
    Result := FormatFloat('0.#', AValue, Fmt);
  end;

begin
  Fmt := TFormatSettings.Invariant;
  SetLength(ColSizes, Max(1, AGraph.LevelCount));
  for N in AGraph.Nodes do
    Inc(ColSizes[N.Level]);
  MaxRows := 1;
  for I := 0 to High(ColSizes) do
    MaxRows := Max(MaxRows, ColSizes[I]);
  W := Margin * 2 + Max(0, AGraph.LevelCount - 1) * ColW + NodeW + 90;
  H := Margin * 2 + (MaxRows - 1) * RowH + NodeH;
  SB := TStringBuilder.Create;
  try
    SB.Append('<svg id="g" xmlns="http://www.w3.org/2000/svg" width="').Append(W).Append('" height="').Append(H)
      .Append('" viewBox="0 0 ').Append(W).Append(' ').Append(H).AppendLine('">');
    for E in AGraph.Edges do
    begin
      S := AGraph.Nodes[E.Source];
      T := AGraph.Nodes[E.Target];
      X1 := NodeX(S) + NodeW;
      Y1 := NodeY(S) + NodeH / 2;
      if S.Level = T.Level then
      begin
        X2 := NodeX(T) + NodeW;
        Y2 := NodeY(T) + NodeH / 2;
        SB.Append('<path class="edge');
        Dx := 70;
        if (S.Cycle >= 0) and (S.Cycle = T.Cycle) then
          SB.Append(' cyc');
        if not E.InInterface then
          SB.Append(' impl');
        SB.Append('" data-s="').Append(E.Source).Append('" data-t="').Append(E.Target).Append('" d="M').Append(F(X1))
          .Append(' ').Append(F(Y1)).Append(' C').Append(F(X1 + Dx)).Append(' ').Append(F(Y1)).Append(' ')
          .Append(F(X2 + Dx)).Append(' ').Append(F(Y2)).Append(' ').Append(F(X2)).Append(' ').Append(F(Y2))
          .AppendLine('"/>');
      end
      else
      begin
        X2 := NodeX(T);
        Y2 := NodeY(T) + NodeH / 2;
        Dx := Max(40, (X2 - X1) / 2);
        SB.Append('<path class="edge');
        if (S.Cycle >= 0) and (S.Cycle = T.Cycle) then
          SB.Append(' cyc');
        if not E.InInterface then
          SB.Append(' impl');
        SB.Append('" data-s="').Append(E.Source).Append('" data-t="').Append(E.Target).Append('" d="M').Append(F(X1))
          .Append(' ').Append(F(Y1)).Append(' C').Append(F(X1 + Dx)).Append(' ').Append(F(Y1)).Append(' ')
          .Append(F(X2 - Dx)).Append(' ').Append(F(Y2)).Append(' ').Append(F(X2)).Append(' ').Append(F(Y2))
          .AppendLine('"/>');
      end;
    end;
    for N in AGraph.Nodes do
    begin
      X := NodeX(N);
      Y := NodeY(N);
      Name := HtmlEsc(N.Name);
      Cls := 'node';
      SB.Append('<g class="').Append(Cls).Append('" data-i="').Append(N.Index).Append('"><title ')
        .Append(ATable.Attr('usa %d · usada por %d')).Append(' data-a="').Append(N.FanOut).Append(',').Append(N.FanIn)
        .Append('" data-pre="').Append(HtmlEsc(N.Path + ' — ')).Append('">')
        .Append(HtmlEsc(N.Path)).Append(' — ').Append(HtmlEsc(TrF('usa %d · usada por %d', [N.FanOut, N.FanIn])))
        .Append('</title>');
      SB.Append('<rect class="b" x="').Append(F(X)).Append('" y="').Append(F(Y)).Append('" width="').Append(NodeW)
        .Append('" height="').Append(NodeH).AppendLine('" rx="7"/>');
      SB.Append('<rect x="').Append(F(X + 1)).Append('" y="').Append(F(Y + 6)).Append('" width="5" height="')
        .Append(NodeH - 12).Append('" rx="2" fill="').Append(LayerColorOf(AGraph, N.Layer)).AppendLine('"/>');
      if N.Cycle >= 0 then
        SB.Append('<rect x="').Append(F(X + NodeW - 12)).Append('" y="').Append(F(Y + 5))
          .AppendLine('" width="6" height="6" rx="3" fill="#c5523d"/>');
      SB.Append('<text x="').Append(F(X + 14)).Append('" y="').Append(F(Y + 14)).Append('" font-size="11.5" font-weight="700">')
        .Append(Name).AppendLine('</text>');
      SB.Append('<text class="sub" x="').Append(F(X + 14)).Append('" y="').Append(F(Y + 27)).Append('" ')
        .Append(ATable.Attr('usa %d · usada por %d')).Append(' data-a="').Append(N.FanOut).Append(',').Append(N.FanIn)
        .Append('">').Append(HtmlEsc(TrF('usa %d · usada por %d', [N.FanOut, N.FanIn]))).AppendLine('</text></g>');
    end;
    SB.AppendLine('</svg>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure AppendCard(SB: TStringBuilder; ATable: TStrTable; const ALabel: string; AValue: Integer);
begin
  SB.Append('<div class="card"><b>').Append(AValue).Append('</b>').Append(ATable.El('span', ALabel)).AppendLine('</div>');
end;

procedure AppendTh(SB: TStringBuilder; ATable: TStrTable; const AText: string; ANumeric: Boolean);
begin
  if ANumeric then
    SB.Append(ATable.El('th', AText, 'class="n"'))
  else
    SB.Append(ATable.El('th', AText));
end;

function DepsHtml(AGraph: TDepGraph; const AProjectName, ARootDisplay: string): string;
var
  SB: TStringBuilder;
  N: TDepNode;
  I: Integer;
  Layers: TArray<string>;
  Links: TArray<TLayerLink>;
  Names: TArray<string>;
  Counts: TArray<Integer>;
  Unused: TArray<TDepNode>;
  Top: TArray<TDepNode>;
  MaxFan: Integer;
  Fmt: TFormatSettings;
  Tbl: TStrTable;
begin
  Fmt := TFormatSettings.Invariant;
  MaxFan := 1;
  for N in AGraph.Nodes do
    MaxFan := Max(MaxFan, Max(N.FanIn, N.FanOut));
  SB := TStringBuilder.Create;
  Tbl := TStrTable.Create;
  try
    SB.Append('<!doctype html><html lang="').Append(LangCodes[CurrentLang]).AppendLine('"><head><meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">');
    SB.Append('<title ').Append(Tbl.Attr('Dependências entre units')).Append(' data-pre="')
      .Append(HtmlEsc(AProjectName + ' — ')).Append('">').Append(HtmlEsc(AProjectName)).Append(' — ')
      .Append(HtmlEsc(Tr('Dependências entre units'))).AppendLine('</title>');
    SB.Append('<style>').Append(HtmlCss).Append(LangBarCss).AppendLine('</style></head><body><div class="wrap">');
    SB.AppendLine('<div class="top"><div>');
    SB.Append('<h1 ').Append(Tbl.Attr('Dependências entre units')).Append(' data-suf="')
      .Append(HtmlEsc(' — ' + AProjectName)).Append('">').Append(HtmlEsc(Tr('Dependências entre units'))).Append(' — ')
      .Append(HtmlEsc(AProjectName)).AppendLine('</h1>');
    SB.Append('<p class="sub">').Append(Tbl.El('span', 'Gerado em: ')).Append(FormatDateTime('yyyy-mm-dd hh:nn', Now))
      .Append(' · ').Append(HtmlEsc(ARootDisplay)).AppendLine('</p>');
    SB.AppendLine('</div>');
    SB.AppendLine(LangButtonsHtml);
    SB.AppendLine('</div>');

    SB.AppendLine('<div class="cards">');
    AppendCard(SB, Tbl, 'Units', AGraph.Nodes.Count);
    AppendCard(SB, Tbl, 'Ligações', AGraph.Edges.Count);
    AppendCard(SB, Tbl, 'Units externas', AGraph.ExternalCount);
    AppendCard(SB, Tbl, 'Ciclos', Length(AGraph.Cycles));
    AppendCard(SB, Tbl, 'Colunas do mapa', AGraph.LevelCount);
    AppendCard(SB, Tbl, 'Units sem uso', Length(AGraph.Unused));
    SB.AppendLine('</div>');

    // mapa
    SB.AppendLine(Tbl.El('h2', 'Mapa de dependências'));
    SB.AppendLine(Tbl.El('p', 'Clique numa unit para realçar o que ela usa (verde) e o que a usa (azul). Linhas a tracejado: só na implementation; a vermelho: ciclos.', 'class="hint"'));
    Layers := AGraph.Layers;
    SB.Append('<div class="legend">');
    for I := 0 to High(Layers) do
      SB.Append('<span><i style="background:').Append(ColorHex(DepLayerPalette[I mod Length(DepLayerPalette)])).Append('"></i>')
        .Append(HtmlEsc(Layers[I])).Append('</span>');
    SB.AppendLine('</div>');
    SB.Append('<div class="map">').Append(BuildSvg(AGraph, Tbl)).AppendLine('</div>');

    // ciclos
    SB.AppendLine(Tbl.El('h2', 'Ciclos'));
    if Length(AGraph.Cycles) = 0 then
      SB.AppendLine(Tbl.El('p', 'Nenhum ciclo: as units não se usam em círculo.', 'class="sub"'))
    else
    begin
      SB.AppendLine('<table><tbody>');
      for I := 0 to High(AGraph.Cycles) do
        SB.Append('<tr><td><span class="tag red">').Append(I + 1).Append('</span></td><td class="names">')
          .Append(HtmlEsc(NameList(AGraph, AGraph.Cycles[I]))).AppendLine('</td></tr>');
      SB.AppendLine('</tbody></table>');
    end;

    // mais usadas / mais dependentes
    SB.AppendLine(Tbl.El('h2', 'Mais usadas'));
    SB.Append('<table><thead><tr>');
    AppendTh(SB, Tbl, 'Unit', False);
    AppendTh(SB, Tbl, 'Camada', False);
    AppendTh(SB, Tbl, 'Usada por', True);
    SB.AppendLine('</tr></thead><tbody>');
    Top := AGraph.TopFanIn(10);
    for N in Top do
      if N.FanIn > 0 then
        SB.Append('<tr><td class="m">').Append(HtmlEsc(N.Name)).Append('</td><td>').Append(HtmlEsc(N.Layer))
          .Append('</td><td class="n"><span class="bar" style="width:').Append(Round(N.FanIn / MaxFan * 120))
          .Append('px"></span>').Append(N.FanIn).AppendLine('</td></tr>');
    SB.AppendLine('</tbody></table>');

    SB.AppendLine(Tbl.El('h2', 'Mais dependentes'));
    SB.Append('<table><thead><tr>');
    AppendTh(SB, Tbl, 'Unit', False);
    AppendTh(SB, Tbl, 'Camada', False);
    AppendTh(SB, Tbl, 'Usa', True);
    SB.AppendLine('</tr></thead><tbody>');
    Top := AGraph.TopFanOut(10);
    for N in Top do
      if N.FanOut > 0 then
        SB.Append('<tr><td class="m">').Append(HtmlEsc(N.Name)).Append('</td><td>').Append(HtmlEsc(N.Layer))
          .Append('</td><td class="n"><span class="bar" style="width:').Append(Round(N.FanOut / MaxFan * 120))
          .Append('px"></span>').Append(N.FanOut).AppendLine('</td></tr>');
    SB.AppendLine('</tbody></table>');

    // camadas
    SB.AppendLine(Tbl.El('h2', 'Ligações entre camadas'));
    Links := AGraph.LayerLinks;
    if Length(Links) = 0 then
      SB.AppendLine(Tbl.El('p', 'Não há ligações entre camadas diferentes.', 'class="sub"'))
    else
    begin
      SB.Append('<table><thead><tr>');
      AppendTh(SB, Tbl, 'De', False);
      AppendTh(SB, Tbl, 'Para', False);
      AppendTh(SB, Tbl, 'Ligações', True);
      SB.AppendLine('</tr></thead><tbody>');
      for I := 0 to High(Links) do
        SB.Append('<tr><td>').Append(HtmlEsc(Links[I].FromLayer)).Append('</td><td>').Append(HtmlEsc(Links[I].ToLayer))
          .Append('</td><td class="n">').Append(Links[I].Count).AppendLine('</td></tr>');
      SB.AppendLine('</tbody></table>');
    end;

    // sem uso
    SB.AppendLine(Tbl.El('h2', 'Units sem uso'));
    Unused := AGraph.Unused;
    if Length(Unused) = 0 then
      SB.AppendLine(Tbl.El('p', 'Todas as units são usadas por outra.', 'class="sub"'))
    else
    begin
      SB.Append('<p class="names">');
      for I := 0 to High(Unused) do
      begin
        if I > 0 then
          SB.Append(', ');
        SB.Append(HtmlEsc(Unused[I].Name));
      end;
      SB.AppendLine('</p>');
    end;

    // externas
    SB.AppendLine(Tbl.El('h2', 'Units de fora mais usadas'));
    ExternalUsage(AGraph, Names, Counts);
    SB.Append('<table><thead><tr>');
    AppendTh(SB, Tbl, 'Unit', False);
    AppendTh(SB, Tbl, 'Usada por', True);
    SB.AppendLine('</tr></thead><tbody>');
    for I := 0 to Min(15, Length(Names)) - 1 do
      SB.Append('<tr><td class="m">').Append(HtmlEsc(Names[I])).Append('</td><td class="n">').Append(Counts[I])
        .AppendLine('</td></tr>');
    SB.AppendLine('</tbody></table>');

    // todas
    SB.AppendLine(Tbl.El('h2', 'Todas as units'));
    SB.Append('<input class="f" id="flt" type="search" data-ph="').Append(Tbl.Idx('Filtrar por unit ou camada…'))
      .Append('" placeholder="').Append(HtmlEsc(Tr('Filtrar por unit ou camada…'))).AppendLine('">');
    SB.Append('<table class="sort" id="all"><thead><tr>');
    AppendTh(SB, Tbl, 'Unit', False);
    AppendTh(SB, Tbl, 'Camada', False);
    AppendTh(SB, Tbl, 'Métodos', True);
    AppendTh(SB, Tbl, 'Linhas', True);
    AppendTh(SB, Tbl, 'Complexidade', True);
    AppendTh(SB, Tbl, 'Usa', True);
    AppendTh(SB, Tbl, 'Usada por', True);
    AppendTh(SB, Tbl, 'Instabilidade', True);
    AppendTh(SB, Tbl, 'Units externas', True);
    SB.AppendLine('</tr></thead><tbody>');
    for N in AGraph.Nodes do
    begin
      SB.Append('<tr><td class="m">').Append(HtmlEsc(N.Name));
      if N.Cycle >= 0 then
        SB.Append(' ').Append(Tbl.El('span', 'ciclo', 'class="tag red"'));
      SB.Append('</td><td>').Append(HtmlEsc(N.Layer)).Append('</td><td class="n">').Append(N.Methods)
        .Append('</td><td class="n">').Append(N.Lines).Append('</td><td class="n">').Append(N.MaxComplexity)
        .Append('</td><td class="n">').Append(N.FanOut).Append('</td><td class="n">').Append(N.FanIn)
        .Append('</td><td class="n">').Append(FormatFloat('0.00', N.Instability, Fmt)).Append('</td><td class="n">')
        .Append(Length(N.External)).AppendLine('</td></tr>');
    end;
    SB.AppendLine('</tbody></table>');
    SB.Append('</div><script>var T=').Append(Tbl.Json).Append(';').Append(LangSwitchJs).Append(HtmlJs)
      .AppendLine('</script></body></html>');
    Result := SB.ToString;
  finally
    Tbl.Free;
    SB.Free;
  end;
end;

function DepsDefaultFileName(const AProjectName, AExt: string): string;
begin
  Result := SlugOf(AProjectName) + Tr('-dependencias') + AExt;
end;

procedure SaveDepsReport(const AFileName, AContent: string);
begin
  ForceDirectories(ExtractFilePath(ExpandFileName(AFileName)));
  TFile.WriteAllText(AFileName, AContent, TEncoding.UTF8);
end;

end.
