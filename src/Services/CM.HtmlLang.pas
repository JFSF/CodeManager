unit CM.HtmlLang;

{ O que as paginas HTML exportadas com seletor de idioma partilham (relatorio de dependencias, SBOM): a tabela de frases nos
  quatro idiomas, os botoes PT/EN/FR/DE, o CSS deles e o JavaScript que troca o texto sem recarregar.

  Cada elemento traduzivel leva data-k com o indice da frase; os que levam numeros usam data-a (os numeros, separados por
  virgulas) e as frases com %d; data-pre / data-suf juntam texto fixo (o nome do projecto) antes e depois; data-ph traduz o
  placeholder de um campo. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TStrTable = class
  private
    FKeys: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function Idx(const APt: string): Integer;
    // <ATag ...AAttrs data-k="n">frase no idioma activo</ATag>
    function El(const ATag, APt: string; const AAttrs: string = ''): string;
    // data-k="n" para um elemento cujo texto o chamador escreve
    function Attr(const APt: string): string;
    // {"pt":[...],"en":[...],"fr":[...],"de":[...]} (JavaScript)
    function Json: string;
  end;

const
  // o CSS dos botoes de idioma e da barra do topo
  LangBarCss =
    '.top{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;flex-wrap:wrap}' +
    '.lang{display:flex;gap:4px}.lang button{font:600 12px "Segoe UI",system-ui,sans-serif;padding:4px 10px;' +
    'border:1px solid var(--border);border-radius:8px;background:var(--surface);color:var(--dim);cursor:pointer}' +
    '.lang button.on{background:var(--accent2);border-color:var(--accent);color:var(--accent)}';

  // o JavaScript do seletor: a variavel T (a tabela de frases) tem de estar definida antes dele
  LangSwitchJs =
    '(function(){function fmt(s,a){var k=0;return s.replace(/%(?:(\d+):)?d/g,function(m,i){return a[i!==undefined?+i:k++]})}' +
    'var bs=document.querySelectorAll(".lang button");' +
    'function ap(l){var tr=T[l];if(!tr)return;document.documentElement.lang=l;' +
    'document.querySelectorAll("[data-k]").forEach(function(e){var s=tr[+e.dataset.k];' +
    'if(e.dataset.a)s=fmt(s,e.dataset.a.split(","));e.textContent=(e.dataset.pre||"")+s+(e.dataset.suf||"")});' +
    'document.querySelectorAll("[data-ph]").forEach(function(e){e.placeholder=tr[+e.dataset.ph]});' +
    'bs.forEach(function(b){b.classList.toggle("on",b.dataset.l===l)})}' +
    'bs.forEach(function(b){b.addEventListener("click",function(){ap(b.dataset.l)})})})();';

function HtmlEscape(const AText: string): string;
// <div class="lang"> com um botao por idioma, o activo marcado
function LangButtonsHtml: string;

implementation

uses
  CM.Lang;

function HtmlEscape(const AText: string): string;
begin
  Result := AText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function LangButtonsHtml: string;
var
  SB: TStringBuilder;
  L: TLang;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<div class="lang">');
    for L := Low(TLang) to High(TLang) do
    begin
      SB.Append('<button type="button" data-l="').Append(LangCodes[L]).Append('" title="').Append(HtmlEscape(LangNames[L]))
        .Append('"');
      if L = CurrentLang then
        SB.Append(' class="on"');
      SB.Append('>').Append(UpperCase(LangCodes[L])).AppendLine('</button>');
    end;
    SB.Append('</div>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TStrTable }

constructor TStrTable.Create;
begin
  inherited;
  FKeys := TList<string>.Create;
end;

destructor TStrTable.Destroy;
begin
  FKeys.Free;
  inherited;
end;

function TStrTable.Idx(const APt: string): Integer;
begin
  Result := FKeys.IndexOf(APt);
  if Result < 0 then
    Result := FKeys.Add(APt);
end;

function TStrTable.Attr(const APt: string): string;
begin
  Result := 'data-k="' + IntToStr(Idx(APt)) + '"';
end;

function TStrTable.El(const ATag, APt, AAttrs: string): string;
begin
  Result := '<' + ATag + ' ';
  if AAttrs <> '' then
    Result := Result + AAttrs + ' ';
  Result := Result + Attr(APt) + '>' + HtmlEscape(Tr(APt)) + '</' + ATag + '>';
end;

// texto entre aspas para JavaScript (e sem nenhum "<" para nunca fechar o <script>)
function JsLit(const AText: string): string;
var
  C: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('"');
    for C in AText do
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        #10: SB.Append('\n');
        #13: SB.Append('\r');
        #9: SB.Append('\t');
        '<': SB.Append('\u003c');
      else
        if C < ' ' then
          SB.Append('\u').Append(IntToHex(Ord(C), 4))
        else
          SB.Append(C);
      end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TStrTable.Json: string;
var
  SB: TStringBuilder;
  L: TLang;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    for L := Low(TLang) to High(TLang) do
    begin
      if L > Low(TLang) then
        SB.Append(',');
      SB.Append('"').Append(LangCodes[L]).Append('":[');
      for I := 0 to FKeys.Count - 1 do
      begin
        if I > 0 then
          SB.Append(',');
        SB.Append(JsLit(TranslateTo(L, FKeys[I])));
      end;
      SB.Append(']');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
