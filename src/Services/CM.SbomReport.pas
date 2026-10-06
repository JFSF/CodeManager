unit CM.SbomReport;

{ Relatorio legivel do SBOM: uma pagina HTML autonoma (sem servidor, com tabela ordenavel e filtro, e frases nos quatro
  idiomas com um seletor na propria pagina) e um Markdown no idioma activo. Serve a auditoria: mostra o projecto, os
  numeros por origem, todos os componentes com a confianca de cada um e o que ainda esta por confirmar.

  Adaptado dos relatorios do DX.Comply (MIT, Olaf Monien): https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils, CM.Sbom;

function SbomMarkdown(ASbom: TSbom; const ARootDisplay: string): string;
function SbomHtml(ASbom: TSbom; const ARootDisplay: string): string;
// <nome-do-projecto>-sbom-relatorio.html / .md
function SbomReportFileName(const AProjectName, AExt: string): string;
// os nomes da origem, da confianca e da evidencia no idioma activo (para as listas da interface)
function OriginText(AOrigin: TSbomOrigin): string;
function ConfidenceText(AConfidence: TSbomConfidence): string;
function EvidenceText(AEvidence: TSbomEvidence): string;

implementation

uses
  System.Classes, System.Math, CM.Lang, CM.HtmlLang;

const
  ReportCss =
    ':root{--bg:#f6f7f4;--surface:#fff;--surface2:#eef0eb;--border:#dcded7;--text:#1b1d1a;--dim:#5a5f58;--faint:#8b908a;' +
    '--accent:#216b59;--accent2:#e0ece8;--danger:#c5523d;--warn:#a8741a;--blue:#3f7fe0}' +
    '@media(prefers-color-scheme:dark){:root{--bg:#121514;--surface:#1a1e1d;--surface2:#222726;--border:#2e3433;' +
    '--text:#e8ebe8;--dim:#a3aaa5;--faint:#6f7772;--accent:#4fb89b;--accent2:#1e2f2b;--danger:#e0705a;--warn:#e0b050;--blue:#6fa8ff}}' +
    '*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 "Segoe UI",system-ui,sans-serif}' +
    '.wrap{max-width:1180px;margin:0 auto;padding:28px 24px 60px}h1{margin:0 0 4px;font-size:26px}' +
    'h2{margin:34px 0 12px;font-size:18px}.sub{color:var(--dim);margin:0 0 20px}p.note{color:var(--dim);max-width:900px}' +
    '.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}' +
    '.card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:14px 16px}' +
    '.card b{display:block;font:700 26px Consolas,monospace}.card span{color:var(--dim);font-size:12.5px}' +
    'table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:12px;' +
    'overflow:hidden}th,td{padding:7px 12px;text-align:left;border-bottom:1px solid var(--border);font-size:13px;vertical-align:top}' +
    'th{background:var(--surface2);color:var(--dim);font-weight:600;cursor:pointer;user-select:none;white-space:nowrap}' +
    'table.kv th{cursor:default;width:220px;background:var(--surface)}' +
    'td.n,th.n{text-align:right;font-family:Consolas,monospace}td.m{font-family:Consolas,monospace}' +
    'tr:last-child td{border-bottom:0}.tag{display:inline-block;padding:1px 8px;border-radius:9px;font-size:11.5px;' +
    'background:var(--accent2);color:var(--accent)}.tag.warn{background:transparent;border:1px solid var(--warn);color:var(--warn)}' +
    '.tag.weak{background:transparent;border:1px solid var(--danger);color:var(--danger)}' +
    'input.f{width:100%;max-width:340px;padding:8px 12px;border:1px solid var(--border);border-radius:9px;background:var(--surface);' +
    'color:var(--text);margin-bottom:10px}.names{color:var(--dim);font-family:Consolas,monospace;font-size:12.5px}' +
    'ul.attn{margin:0;padding-left:20px;color:var(--dim)}';

  // ordenar por coluna e filtrar a tabela dos componentes
  ReportJs =
    '(function(){document.querySelectorAll("table.sort").forEach(function(t){var h=t.querySelectorAll("th");h.forEach(function(th,ci){' +
    'th.addEventListener("click",function(){var rows=[].slice.call(t.tBodies[0].rows),asc=th.dataset.asc!=="1";th.dataset.asc=asc?"1":"0";' +
    'var num=th.classList.contains("n");rows.sort(function(a,b){var x=a.cells[ci].dataset.v||a.cells[ci].textContent,y=b.cells[ci].dataset.v||b.cells[ci].textContent;' +
    'if(num){x=parseFloat(x)||0;y=parseFloat(y)||0}else{x=x.toLowerCase();y=y.toLowerCase()}return(x<y?-1:x>y?1:0)*(asc?1:-1)});' +
    'rows.forEach(function(r){t.tBodies[0].appendChild(r)})})})});' +
    'var f=document.getElementById("flt");if(f)f.addEventListener("input",function(){var q=f.value.toLowerCase();' +
    'document.querySelectorAll("#all tbody tr").forEach(function(r){r.style.display=r.textContent.toLowerCase().indexOf(q)<0?"none":""})});})();';

  AttnLimit = 40;

function OriginKey(AOrigin: TSbomOrigin): string;
begin
  case AOrigin of
    soProject: Result := 'Projeto local';
    soRtl: Result := 'RTL da Embarcadero';
    soVcl: Result := 'VCL da Embarcadero';
    soFmx: Result := 'FMX da Embarcadero';
  else
    Result := 'Terceiros';
  end;
end;

function ConfidenceKey(AConfidence: TSbomConfidence): string;
begin
  case AConfidence of
    scStrong: Result := 'Forte';
    scMedium: Result := 'Média';
  else
    Result := 'Fraca';
  end;
end;

function EvidenceKey(AEvidence: TSbomEvidence): string;
begin
  case AEvidence of
    seFile: Result := 'Ficheiro';
    seMap: Result := 'Mapa de ligação';
  else
    Result := 'Cláusula uses';
  end;
end;

function OriginText(AOrigin: TSbomOrigin): string;
begin
  Result := Tr(OriginKey(AOrigin));
end;

function ConfidenceText(AConfidence: TSbomConfidence): string;
begin
  Result := Tr(ConfidenceKey(AConfidence));
end;

function EvidenceText(AEvidence: TSbomEvidence): string;
begin
  Result := Tr(EvidenceKey(AEvidence));
end;

function MdCell(const AText: string): string;
begin
  Result := AText.Replace('|', '\|').Replace(#13, ' ').Replace(#10, ' ');
end;

function ShortHash(const AHash: string): string;
begin
  if AHash = '' then
    Result := '—'
  else
    Result := Copy(AHash, 1, 16);
end;

function EmbarcaderoCount(ASbom: TSbom): Integer;
begin
  Result := ASbom.CountOf(soRtl) + ASbom.CountOf(soVcl) + ASbom.CountOf(soFmx);
end;

// os componentes de terceiros de que so se conhece o nome (confianca fraca)
function Unconfirmed(ASbom: TSbom): Integer;
begin
  Result := ASbom.CountByConfidence(scWeak);
end;

function UserList(C: TSbomComponent; AMax: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Min(AMax, Length(C.UsedBy)) - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + C.UsedBy[I];
  end;
  if Length(C.UsedBy) > AMax then
    Result := Result + ', …';
end;

function SbomReportFileName(const AProjectName, AExt: string): string;
var
  C: Char;
  Slug: string;
begin
  Slug := '';
  for C in LowerCase(Trim(AProjectName)) do
    if CharInSet(C, ['a'..'z', '0'..'9']) then
      Slug := Slug + C
    else if (Slug <> '') and (Slug[Length(Slug)] <> '-') then
      Slug := Slug + '-';
  Slug := Slug.TrimRight(['-']);
  if Slug = '' then
    Slug := 'projeto';
  Result := Slug + Tr('-sbom-relatorio') + AExt;
end;

{ Markdown }

function SbomMarkdown(ASbom: TSbom; const ARootDisplay: string): string;
var
  SB: TStringBuilder;
  P: TSbomProject;
  O: TSbomOrigin;
  C: TSbomComponent;
  Shown: Integer;
begin
  P := ASbom.Project;
  SB := TStringBuilder.Create;
  try
    SB.Append('# ').Append(Tr('Lista de materiais de software (SBOM)')).Append(' — ').AppendLine(P.Name).AppendLine;
    SB.Append(Tr('Gerado em: ')).Append(FormatDateTime('yyyy-mm-dd hh:nn', ASbom.Generated));
    if ARootDisplay <> '' then
      SB.Append(' · ').Append(ARootDisplay);
    SB.AppendLine.AppendLine;

    SB.Append('## ').AppendLine(Tr('Resumo')).AppendLine;
    SB.Append('- ').Append(Tr('Componentes')).Append(': ').AppendLine(IntToStr(ASbom.Components.Count));
    SB.Append('- ').Append(Tr('Com ficheiro encontrado')).Append(': ').AppendLine(IntToStr(ASbom.ResolvedCount));
    SB.Append('- ').Append(Tr('Da Embarcadero')).Append(': ').AppendLine(IntToStr(EmbarcaderoCount(ASbom)));
    SB.Append('- ').Append(Tr('De terceiros')).Append(': ').AppendLine(IntToStr(ASbom.CountOf(soThirdParty)));
    SB.Append('- ').Append(Tr('Do projeto')).Append(': ').AppendLine(IntToStr(ASbom.CountOf(soProject)));
    SB.Append('- ').Append(Tr('Por confirmar')).Append(': ').AppendLine(IntToStr(Unconfirmed(ASbom)));
    if ASbom.MapFile <> '' then
      SB.Append('- ').Append(Tr('Fora do mapa')).Append(': ').AppendLine(IntToStr(ASbom.NotLinkedCount));
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Projeto')).AppendLine;
    SB.Append('| ').Append(Tr('Campo')).Append(' | ').Append(Tr('Valor')).AppendLine(' |');
    SB.AppendLine('|---|---|');
    SB.Append('| ').Append(Tr('Nome')).Append(' | ').Append(MdCell(P.Name)).AppendLine(' |');
    if P.Version <> '' then
      SB.Append('| ').Append(Tr('Versão')).Append(' | ').Append(MdCell(P.Version)).AppendLine(' |');
    if P.Company <> '' then
      SB.Append('| ').Append(Tr('Empresa')).Append(' | ').Append(MdCell(P.Company)).AppendLine(' |');
    if P.Description <> '' then
      SB.Append('| ').Append(Tr('Descrição')).Append(' | ').Append(MdCell(P.Description)).AppendLine(' |');
    if P.FrameworkType <> '' then
      SB.Append('| Framework | ').Append(MdCell(P.FrameworkType)).AppendLine(' |');
    if P.Platform <> '' then
      SB.Append('| ').Append(Tr('Plataforma')).Append(' | ').Append(MdCell(P.Platform)).AppendLine(' |');
    if P.Configuration <> '' then
      SB.Append('| ').Append(Tr('Configuração de compilação')).Append(' | ').Append(MdCell(P.Configuration)).AppendLine(' |');
    if ASbom.MapFile <> '' then
      SB.Append('| ').Append(Tr('Mapa de ligação')).Append(' | ').Append(MdCell(ExtractFileName(ASbom.MapFile))).AppendLine(' |');
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Resumo por origem')).AppendLine;
    SB.Append('| ').Append(Tr('Origem')).Append(' | ').Append(Tr('Componentes')).Append(' | ').Append(Tr('Com ficheiro encontrado'))
      .AppendLine(' |');
    SB.AppendLine('|---|---:|---:|');
    for O := Low(TSbomOrigin) to High(TSbomOrigin) do
      if ASbom.CountOf(O) > 0 then
      begin
        Shown := 0;
        for C in ASbom.Components do
          if (C.Origin = O) and (C.Path <> '') then
            Inc(Shown);
        SB.Append('| ').Append(Tr(OriginKey(O))).Append(' | ').Append(ASbom.CountOf(O)).Append(' | ').Append(Shown).AppendLine(' |');
      end;
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Componentes')).AppendLine;
    SB.Append('| ').Append(Tr('Unit')).Append(' | ').Append(Tr('Origem')).Append(' | ').Append(Tr('Evidência')).Append(' | ')
      .Append(Tr('Confiança')).Append(' | ').Append(Tr('Usada por')).AppendLine(' | SHA-256 |');
    SB.AppendLine('|---|---|---|---|---:|---|');
    for C in ASbom.Components do
      SB.Append('| `').Append(C.Name).Append('` | ').Append(Tr(OriginKey(C.Origin))).Append(' | ').Append(Tr(EvidenceKey(C.Evidence)))
        .Append(' | ').Append(Tr(ConfidenceKey(C.Confidence))).Append(' | ').Append(Length(C.UsedBy)).Append(' | ')
        .Append(ShortHash(C.Hash)).AppendLine(' |');
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Pontos de atenção')).AppendLine;
    if (Unconfirmed(ASbom) = 0) and (ASbom.NotLinkedCount = 0) then
      SB.AppendLine(Tr('Nada a assinalar: todos os componentes foram confirmados.')).AppendLine;
    if Unconfirmed(ASbom) > 0 then
    begin
      SB.AppendLine(Tr('Units de terceiros sem ficheiro encontrado: só se conhecem pelo nome. Acrescenta as pastas das bibliotecas aos caminhos de procura do projeto para as confirmar.')).AppendLine;
      Shown := 0;
      for C in ASbom.Components do
        if C.Confidence = scWeak then
        begin
          if Shown >= AttnLimit then
          begin
            SB.Append('- … ').AppendLine(IntToStr(Unconfirmed(ASbom) - AttnLimit));
            Break;
          end;
          SB.Append('- `').Append(C.Name).Append('` — ').AppendLine(UserList(C, 4));
          Inc(Shown);
        end;
      SB.AppendLine;
    end;
    if ASbom.NotLinkedCount > 0 then
    begin
      SB.AppendLine(Tr('Referenciadas no código mas ausentes do mapa de ligação (podem não ficar no executável):')).AppendLine;
      Shown := 0;
      for C in ASbom.Components do
        if (C.Origin <> soProject) and not C.InMap then
        begin
          if Shown >= AttnLimit then
          begin
            SB.Append('- … ').AppendLine(IntToStr(ASbom.NotLinkedCount - AttnLimit));
            Break;
          end;
          SB.Append('- `').Append(C.Name).AppendLine('`');
          Inc(Shown);
        end;
      SB.AppendLine;
    end;

    SB.Append('## ').AppendLine(Tr('Como ler este relatório')).AppendLine;
    SB.AppendLine(Tr('Um SBOM lista o que entra no teu software: aqui, as units que o projeto usa e de onde vêm.')).AppendLine;
    SB.AppendLine(Tr('Confiança forte: o ficheiro da unit foi encontrado (e tem hash SHA-256). Média: só se conhece pelo nome, mas é uma biblioteca da Embarcadero. Fraca: só se conhece pelo nome e não se sabe de onde vem.')).AppendLine;
    SB.AppendLine(Tr('O relatório vem da análise do código-fonte (cláusulas uses e .dproj), sem compilar: uma unit referenciada pode não ficar no executável. Com um ficheiro .map as units realmente ligadas ficam confirmadas.'));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ HTML }

function SbomHtml(ASbom: TSbom; const ARootDisplay: string): string;
var
  SB: TStringBuilder;
  Tbl: TStrTable;
  P: TSbomProject;
  O: TSbomOrigin;
  C: TSbomComponent;
  Resolved, Shown: Integer;

  procedure Card(const ALabel: string; AValue: Integer);
  begin
    SB.Append('<div class="card"><b>').Append(AValue).Append('</b>').Append(Tbl.El('span', ALabel)).AppendLine('</div>');
  end;

  procedure KvRow(const ALabelKey, AValue: string);
  begin
    if AValue = '' then
      Exit;
    SB.Append('<tr>').Append(Tbl.El('th', ALabelKey)).Append('<td>').Append(HtmlEscape(AValue)).AppendLine('</td></tr>');
  end;

  function ConfidenceTag(AConfidence: TSbomConfidence): string;
  var
    Cls: string;
  begin
    case AConfidence of
      scStrong: Cls := 'tag';
      scMedium: Cls := 'tag warn';
    else
      Cls := 'tag weak';
    end;
    Result := Tbl.El('span', ConfidenceKey(AConfidence), 'class="' + Cls + '"');
  end;

begin
  P := ASbom.Project;
  SB := TStringBuilder.Create;
  Tbl := TStrTable.Create;
  try
    SB.Append('<!doctype html><html lang="').Append(LangCodes[CurrentLang]).AppendLine('"><head><meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">');
    SB.Append('<title ').Append(Tbl.Attr('Lista de materiais de software (SBOM)')).Append(' data-pre="')
      .Append(HtmlEscape(P.Name + ' — ')).Append('">').Append(HtmlEscape(P.Name)).Append(' — ')
      .Append(HtmlEscape(Tr('Lista de materiais de software (SBOM)'))).AppendLine('</title>');
    SB.Append('<style>').Append(ReportCss).Append(LangBarCss).AppendLine('</style></head><body><div class="wrap">');
    SB.AppendLine('<div class="top"><div>');
    SB.Append('<h1 ').Append(Tbl.Attr('Lista de materiais de software (SBOM)')).Append(' data-suf="')
      .Append(HtmlEscape(' — ' + P.Name)).Append('">').Append(HtmlEscape(Tr('Lista de materiais de software (SBOM)')))
      .Append(' — ').Append(HtmlEscape(P.Name)).AppendLine('</h1>');
    SB.Append('<p class="sub">').Append(Tbl.El('span', 'Gerado em: ')).Append(FormatDateTime('yyyy-mm-dd hh:nn', ASbom.Generated));
    if ARootDisplay <> '' then
      SB.Append(' · ').Append(HtmlEscape(ARootDisplay));
    SB.AppendLine('</p>');
    SB.AppendLine('</div>');
    SB.AppendLine(LangButtonsHtml);
    SB.AppendLine('</div>');

    SB.AppendLine('<div class="cards">');
    Card('Componentes', ASbom.Components.Count);
    Card('Com ficheiro encontrado', ASbom.ResolvedCount);
    Card('Da Embarcadero', EmbarcaderoCount(ASbom));
    Card('De terceiros', ASbom.CountOf(soThirdParty));
    Card('Do projeto', ASbom.CountOf(soProject));
    Card('Por confirmar', Unconfirmed(ASbom));
    if ASbom.MapFile <> '' then
      Card('Fora do mapa', ASbom.NotLinkedCount);
    SB.AppendLine('</div>');

    // projecto
    SB.AppendLine(Tbl.El('h2', 'Projeto'));
    SB.AppendLine('<table class="kv"><tbody>');
    KvRow('Nome', P.Name);
    KvRow('Versão', P.Version);
    KvRow('Empresa', P.Company);
    KvRow('Descrição', P.Description);
    if P.FrameworkType <> '' then
      SB.Append('<tr><th>Framework</th><td>').Append(HtmlEscape(P.FrameworkType)).AppendLine('</td></tr>');
    KvRow('Plataforma', P.Platform);
    KvRow('Configuração de compilação', P.Configuration);
    if ASbom.MapFile <> '' then
      KvRow('Mapa de ligação', ExtractFileName(ASbom.MapFile));
    SB.AppendLine('</tbody></table>');

    // por origem
    SB.AppendLine(Tbl.El('h2', 'Resumo por origem'));
    SB.Append('<table><thead><tr>').Append(Tbl.El('th', 'Origem')).Append(Tbl.El('th', 'Componentes', 'class="n"'))
      .Append(Tbl.El('th', 'Com ficheiro encontrado', 'class="n"')).AppendLine('</tr></thead><tbody>');
    for O := Low(TSbomOrigin) to High(TSbomOrigin) do
      if ASbom.CountOf(O) > 0 then
      begin
        Resolved := 0;
        for C in ASbom.Components do
          if (C.Origin = O) and (C.Path <> '') then
            Inc(Resolved);
        SB.Append('<tr><td>').Append(Tbl.El('span', OriginKey(O))).Append('</td><td class="n">').Append(ASbom.CountOf(O))
          .Append('</td><td class="n">').Append(Resolved).AppendLine('</td></tr>');
      end;
    SB.AppendLine('</tbody></table>');

    // pontos de atencao
    SB.AppendLine(Tbl.El('h2', 'Pontos de atenção'));
    if (Unconfirmed(ASbom) = 0) and (ASbom.NotLinkedCount = 0) then
      SB.AppendLine(Tbl.El('p', 'Nada a assinalar: todos os componentes foram confirmados.', 'class="note"'));
    if Unconfirmed(ASbom) > 0 then
    begin
      SB.AppendLine(Tbl.El('p', 'Units de terceiros sem ficheiro encontrado: só se conhecem pelo nome. Acrescenta as pastas das bibliotecas aos caminhos de procura do projeto para as confirmar.', 'class="note"'));
      SB.AppendLine('<ul class="attn">');
      Shown := 0;
      for C in ASbom.Components do
        if C.Confidence = scWeak then
        begin
          if Shown >= AttnLimit then
          begin
            SB.Append('<li>… ').Append(Unconfirmed(ASbom) - AttnLimit).AppendLine('</li>');
            Break;
          end;
          SB.Append('<li><span class="names">').Append(HtmlEscape(C.Name)).Append('</span> — ')
            .Append(HtmlEscape(UserList(C, 4))).AppendLine('</li>');
          Inc(Shown);
        end;
      SB.AppendLine('</ul>');
    end;
    if ASbom.NotLinkedCount > 0 then
    begin
      SB.AppendLine(Tbl.El('p', 'Referenciadas no código mas ausentes do mapa de ligação (podem não ficar no executável):', 'class="note"'));
      SB.AppendLine('<ul class="attn">');
      Shown := 0;
      for C in ASbom.Components do
        if (C.Origin <> soProject) and not C.InMap then
        begin
          if Shown >= AttnLimit then
          begin
            SB.Append('<li>… ').Append(ASbom.NotLinkedCount - AttnLimit).AppendLine('</li>');
            Break;
          end;
          SB.Append('<li><span class="names">').Append(HtmlEscape(C.Name)).AppendLine('</span></li>');
          Inc(Shown);
        end;
      SB.AppendLine('</ul>');
    end;

    // componentes
    SB.AppendLine(Tbl.El('h2', 'Componentes'));
    SB.Append('<input class="f" id="flt" type="search" data-ph="').Append(Tbl.Idx('Filtrar por unit ou origem…'))
      .Append('" placeholder="').Append(HtmlEscape(Tr('Filtrar por unit ou origem…'))).AppendLine('">');
    SB.Append('<table class="sort" id="all"><thead><tr>').Append(Tbl.El('th', 'Unit')).Append(Tbl.El('th', 'Origem'))
      .Append(Tbl.El('th', 'Evidência')).Append(Tbl.El('th', 'Confiança')).Append(Tbl.El('th', 'Usada por', 'class="n"'))
      .AppendLine('<th>SHA-256</th></tr></thead><tbody>');
    for C in ASbom.Components do
    begin
      SB.Append('<tr><td class="m">').Append(HtmlEscape(C.Name)).Append('</td><td>').Append(Tbl.El('span', OriginKey(C.Origin)))
        .Append('</td><td>').Append(Tbl.El('span', EvidenceKey(C.Evidence))).Append('</td><td>')
        .Append(ConfidenceTag(C.Confidence)).Append('</td><td class="n" title="').Append(HtmlEscape(UserList(C, 12))).Append('">')
        .Append(Length(C.UsedBy)).Append('</td><td class="m" title="').Append(HtmlEscape(C.Hash)).Append('">')
        .Append(HtmlEscape(ShortHash(C.Hash))).AppendLine('</td></tr>');
    end;
    SB.AppendLine('</tbody></table>');

    // como ler
    SB.AppendLine(Tbl.El('h2', 'Como ler este relatório'));
    SB.AppendLine(Tbl.El('p', 'Um SBOM lista o que entra no teu software: aqui, as units que o projeto usa e de onde vêm.', 'class="note"'));
    SB.AppendLine(Tbl.El('p', 'Confiança forte: o ficheiro da unit foi encontrado (e tem hash SHA-256). Média: só se conhece pelo nome, mas é uma biblioteca da Embarcadero. Fraca: só se conhece pelo nome e não se sabe de onde vem.', 'class="note"'));
    SB.AppendLine(Tbl.El('p', 'O relatório vem da análise do código-fonte (cláusulas uses e .dproj), sem compilar: uma unit referenciada pode não ficar no executável. Com um ficheiro .map as units realmente ligadas ficam confirmadas.', 'class="note"'));

    SB.Append('</div><script>var T=').Append(Tbl.Json).Append(';').Append(LangSwitchJs).Append(ReportJs)
      .AppendLine('</script></body></html>');
    Result := SB.ToString;
  finally
    Tbl.Free;
    SB.Free;
  end;
end;

end.
