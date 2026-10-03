unit CM.Lang;

{ Idiomas da aplicacao (pt, en, fr, de). O texto original em portugues serve de chave:
  Tr('Mapa de código') devolve a traducao para o idioma activo e, se nao houver (ou se o idioma
  for o portugues), o proprio texto. As traducoes estao em CM.Lang.Table, gerada a partir de
  tools\i18n\translations.tsv por tools\i18n\generate-lang-table.ps1. }

interface

type
  TLang = (lgPt, lgEn, lgFr, lgDe);

const
  LangCodes: array[TLang] of string = ('pt', 'en', 'fr', 'de');
  // o nome de cada idioma na sua propria lingua
  LangNames: array[TLang] of string = ('Português', 'English', 'Français', 'Deutsch');

function CurrentLang: TLang;
procedure SetLang(ALang: TLang);
// 'pt' | 'en' | 'fr' | 'de' (so as duas primeiras letras contam, sem distinguir maiusculas)
function LangFromCode(const ACode: string; ADefault: TLang): TLang;

// traduz um texto escrito em portugues
function Tr(const APt: string): string;
// Format(Tr(APt), AArgs)
function TrF(const APt: string; const AArgs: array of const): string;
// ex.: Plural(3, 'ficheiro', 'ficheiros') -> '3 files'
function TrCount(ACount: Integer; const ASingularPt, APluralPt: string): string;

// todas as versoes (pt e traducoes distintas) de um texto: para reconhecer documentos escritos noutro idioma
function TranslateAll(const APt: string): TArray<string>;

// textos para testes: devolve a traducao de um idioma especifico, ou o original se nao existir
function TranslateTo(ALang: TLang; const APt: string): string;
function TranslationCount: Integer;

implementation

uses
  System.SysUtils, System.Generics.Collections, CM.Lang.Table;

var
  GLang: TLang = lgPt;
  GTables: array[TLang] of TDictionary<string, string>;

procedure BuildTables;
var
  L: TLang;
  I: Integer;
begin
  for L := lgEn to lgDe do
    GTables[L] := TDictionary<string, string>.Create(Length(LangRows));
  for I := Low(LangRows) to High(LangRows) do
    for L := lgEn to lgDe do
      if LangRows[I][Ord(L)] <> '' then
        GTables[L].AddOrSetValue(LangRows[I][0], LangRows[I][Ord(L)]);
end;

function CurrentLang: TLang;
begin
  Result := GLang;
end;

// meses e dias na lingua activa (os graficos e FormatDateTime leem FormatSettings)
procedure ApplyLocaleNames(ALang: TLang);
const
  ShortM: array[TLang] of array[1..12] of string = (
    ('jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'),
    ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'),
    ('janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'),
    ('Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'));
  LongM: array[TLang] of array[1..12] of string = (
    ('janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
     'novembro', 'dezembro'),
    ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
     'November', 'December'),
    ('janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre',
     'novembre', 'décembre'),
    ('Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober',
     'November', 'Dezember'));
var
  I: Integer;
begin
  for I := 1 to 12 do
  begin
    FormatSettings.ShortMonthNames[I] := ShortM[ALang][I];
    FormatSettings.LongMonthNames[I] := LongM[ALang][I];
  end;
end;

procedure SetLang(ALang: TLang);
begin
  GLang := ALang;
  ApplyLocaleNames(ALang);
end;

function LangFromCode(const ACode: string; ADefault: TLang): TLang;
var
  L: TLang;
  Code: string;
begin
  Code := LowerCase(Copy(Trim(ACode), 1, 2));
  for L := Low(TLang) to High(TLang) do
    if LangCodes[L] = Code then
      Exit(L);
  Result := ADefault;
end;

function TranslateTo(ALang: TLang; const APt: string): string;
begin
  if (ALang = lgPt) or not GTables[ALang].TryGetValue(APt, Result) then
    Result := APt;
end;

function Tr(const APt: string): string;
begin
  Result := TranslateTo(GLang, APt);
end;

function TrF(const APt: string; const AArgs: array of const): string;
begin
  Result := Format(Tr(APt), AArgs);
end;

function TrCount(ACount: Integer; const ASingularPt, APluralPt: string): string;
begin
  if ACount = 1 then
    Result := '1 ' + Tr(ASingularPt)
  else
    Result := IntToStr(ACount) + ' ' + Tr(APluralPt);
end;

function TranslateAll(const APt: string): TArray<string>;
var
  L: TLang;
  S: string;
  I: Integer;
  Dup: Boolean;
begin
  Result := [APt];
  for L := lgEn to lgDe do
  begin
    S := TranslateTo(L, APt);
    Dup := False;
    for I := 0 to High(Result) do
      if Result[I] = S then
        Dup := True;
    if not Dup then
      Result := Result + [S];
  end;
end;

function TranslationCount: Integer;
begin
  Result := Length(LangRows);
end;

initialization
  BuildTables;

finalization
  GTables[lgEn].Free;
  GTables[lgFr].Free;
  GTables[lgDe].Free;

end.
