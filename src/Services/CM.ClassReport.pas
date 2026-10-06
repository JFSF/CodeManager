unit CM.ClassReport;

{ O relatorio das classes e da heranca: um Markdown legivel (resumo, as mais profundas, as com mais filhas e a arvore completa)
  e um CSV com uma linha por classe. O Markdown segue o idioma activo; os cabecalhos do CSV tambem. Uma profundidade que e so
  um minimo (a cadeia acima de um ancestral externo e desconhecida) escreve-se com ">=" no Markdown e com a coluna "Exata"
  a "nao" no CSV. }

interface

uses
  System.SysUtils, CM.ClassHierarchy;

function ClassesMarkdown(AHier: THierarchy; const AProjectName: string): string;
function ClassesCsv(AHier: THierarchy): string;
// <nome-do-projecto>-classes.md / .csv
function ClassesFileName(const AProjectName, AExt: string): string;
// a profundidade como se mostra: '3', ou '>=3' quando e um minimo
function DepthText(ANode: TClassNode): string;

implementation

uses
  System.Classes, System.Math, CM.Classes, CM.Lang, CM.Export;

const
  Top = 15;

function DepthText(ANode: TClassNode): string;
begin
  if ANode.Exact then
    Result := IntToStr(ANode.Depth)
  else
    Result := '>=' + IntToStr(ANode.Depth);
end;

function KindText(AKind: TClassKind): string;
begin
  case AKind of
    ckClass: Result := Tr('classe');
    ckInterface: Result := Tr('interface');
    ckObject: Result := Tr('objeto');
  else
    Result := Tr('record');
  end;
end;

function MdCell(const AText: string): string;
begin
  Result := AText.Replace('|', '\|').Replace(#13, ' ').Replace(#10, ' ');
end;

function ClassesFileName(const AProjectName, AExt: string): string;
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
  Result := Slug + '-classes' + AExt;
end;

procedure TableHeader(SB: TStringBuilder);
begin
  SB.Append('| ').Append(Tr('Classe')).Append(' | ').Append(Tr('Tipo')).Append(' | ').Append(Tr('Profundidade')).Append(' | ')
    .Append(Tr('Filhas')).Append(' | ').Append(Tr('Métodos')).Append(' | ').Append(Tr('Ficheiro')).AppendLine(' |');
  SB.AppendLine('|---|---|---:|---:|---:|---|');
end;

procedure TableRow(SB: TStringBuilder; N: TClassNode; AIndent: Boolean);
var
  Name: string;
begin
  Name := N.Name;
  if AIndent and (N.ProjectDepth > 1) then
    Name := StringOfChar('·', N.ProjectDepth - 1) + ' ' + Name;
  SB.Append('| `').Append(Name).Append('` | ').Append(KindText(N.Kind)).Append(' | ').Append(DepthText(N)).Append(' | ')
    .Append(N.Children).Append(' | ').Append(N.Methods).Append(' | ').Append(MdCell(N.UnitPath)).Append(':').Append(N.Line)
    .AppendLine(' |');
end;

function ClassesMarkdown(AHier: THierarchy; const AProjectName: string): string;
var
  SB: TStringBuilder;
  N: TClassNode;
  Inexact, Shown: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('# ').Append(Tr('Classes e herança')).Append(' — ').AppendLine(AProjectName).AppendLine;
    SB.Append('## ').AppendLine(Tr('Resumo')).AppendLine;
    SB.Append('- ').Append(Tr('Classes')).Append(': ').AppendLine(IntToStr(AHier.Count(ckClass) + AHier.Count(ckObject)));
    SB.Append('- ').Append(Tr('Interfaces')).Append(': ').AppendLine(IntToStr(AHier.Count(ckInterface)));
    SB.Append('- ').Append(Tr('Records')).Append(': ').AppendLine(IntToStr(AHier.Records));
    SB.Append('- ').Append(Tr('Profundidade máxima')).Append(': ').AppendLine(IntToStr(AHier.MaxDepth));
    SB.Append('- ').Append(Tr('Profundidade média')).Append(': ').AppendLine(FormatFloat('0.0', AHier.AverageDepth));
    Inexact := 0;
    for N in AHier.Nodes do
      if not N.Exact then
        Inc(Inexact);
    if Inexact > 0 then
      SB.Append('- ').Append(Tr('Com profundidade mínima (cadeia externa desconhecida)')).Append(': ').AppendLine(IntToStr(Inexact));
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Classes mais profundas')).AppendLine;
    TableHeader(SB);
    for N in AHier.Deepest(Top) do
      TableRow(SB, N, False);
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Classes com mais filhas')).AppendLine;
    TableHeader(SB);
    Shown := 0;
    for N in AHier.MostChildren(Top) do
      if N.Children > 0 then
      begin
        TableRow(SB, N, False);
        Inc(Shown);
      end;
    if Shown = 0 then
      SB.Append('| — | | | | | |').AppendLine;
    SB.AppendLine;

    SB.Append('## ').AppendLine(Tr('Árvore de herança')).AppendLine;
    TableHeader(SB);
    for N in AHier.TreeOrder do
      TableRow(SB, N, True);
    SB.AppendLine.AppendLine(Tr('Um «>=» na profundidade quer dizer que a classe herda de uma classe de fora do projeto de que não se conhece a cadeia: a profundidade real é, pelo menos, essa.'));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function YesNo(AValue: Boolean): string;
begin
  if AValue then
    Result := Tr('sim')
  else
    Result := Tr('não');
end;

function ClassesCsv(AHier: THierarchy): string;
var
  SB: TStringBuilder;
  N: TClassNode;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(CsvLine([Tr('Classe'), Tr('Tipo'), Tr('Ancestral'), Tr('Profundidade'), Tr('Exata'), Tr('Profundidade no projeto'),
      Tr('Filhas'), Tr('Descendentes'), Tr('Métodos'), Tr('Interfaces'), Tr('Ficheiro'), Tr('Linha')]));
    for N in AHier.TreeOrder do
      SB.Append(CsvLine([N.Name, KindText(N.Kind), N.Ancestor, IntToStr(N.Depth), YesNo(N.Exact), IntToStr(N.ProjectDepth),
        IntToStr(N.Children), IntToStr(N.Descendants), IntToStr(N.Methods), string.Join(', ', N.Interfaces), N.UnitPath,
        IntToStr(N.Line)]));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
