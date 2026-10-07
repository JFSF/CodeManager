unit CM.Licenses;

{ Licencas e versoes das bibliotecas de terceiros, a partir do texto dos ficheiros que as acompanham (so texto, sem
  tocar em disco): reconhece a licenca de um ficheiro LICENSE pelo texto, normaliza o que um boss.json diz para um
  identificador SPDX, le o boss.json e o boss-lock.json do gestor de pacotes Boss e tira o nome e a versao do nome de uma
  pasta do GetIt ('Spring4D-2.0'). O reconhecimento e prudente: so devolve um identificador quando o texto o justifica;
  o resto fica por declarar, e nunca se inventa uma licenca. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  // o que interessa de um boss.json (os campos em falta ficam vazios)
  TBossInfo = record
    Name: string;
    Version: string;
    License: string;               // tal como esta escrito no ficheiro
    HomePage: string;
  end;

// o identificador SPDX da licenca que o texto de um ficheiro LICENSE / COPYING traz; '' se nao se reconhece
function DetectLicenseId(const ALicenseText: string): string;
// o identificador SPDX para o que alguem escreveu num campo de licenca ('MIT', 'apache 2.0', 'LGPL-3.0'...); '' se nao se reconhece
function NormalizeLicenseId(const AValue: string): string;
function ParseBossJson(const AText: string; out AInfo: TBossInfo): Boolean;
// as versoes instaladas que o boss-lock.json regista: nome da biblioteca (sem o caminho 'github.com/dono/', em minusculas) -> versao
function ParseBossLock(const AText: string): TDictionary<string, string>;
// 'Spring4D-2.0' -> 'Spring4D' e '2.0'; False se o nome da pasta nao acaba numa versao
function SplitVersionedFolder(const AFolder: string; out AName, AVersion: string): Boolean;
// uma pasta que e so uma versao ('1.2.0'): o nome da biblioteca esta na pasta de cima
function IsVersionFolder(const AFolder: string): Boolean;
// 'Chart4D-13' -> 'Chart4D' (o GetIt junta ao nome a versao do Delphi); o que nao acaba assim fica igual
function StripDelphiSuffix(const AFolder: string): string;

implementation

uses
  System.Classes, System.JSON, System.RegularExpressions;

// minusculas, com os espacos e as mudancas de linha reduzidos a um espaco: para procurar frases no texto
function Squash(const AText: string): string;
var
  C: Char;
  Last: Boolean;
begin
  Result := '';
  Last := False;
  for C in LowerCase(AText) do
    if CharInSet(C, [#9, #10, #13, ' ', #160]) then
    begin
      if not Last then
        Result := Result + ' ';
      Last := True;
    end
    else
    begin
      Result := Result + C;
      Last := False;
    end;
end;

function Has(const AText, APhrase: string): Boolean;
begin
  Result := Pos(APhrase, AText) > 0;
end;

function DetectLicenseId(const ALicenseText: string): string;
var
  T: string;
  PosAgpl, PosLgpl, PosGpl: Integer;
begin
  T := Squash(Copy(ALicenseText, 1, 20000));
  Result := '';
  if T = '' then
    Exit;
  // as licencas que citam outras (a MPL cita a GPL, a GPL-3 cita a AGPL): primeiro as que se reconhecem sem ambiguidade
  if Has(T, 'apache license') and Has(T, 'version 2.0') then
    Exit('Apache-2.0');
  if Has(T, 'mozilla public license') then
  begin
    if Has(T, 'version 2.0') then
      Exit('MPL-2.0');
    if Has(T, 'version 1.1') then
      Exit('MPL-1.1');
    Exit;
  end;
  if Has(T, 'eclipse public license') then
  begin
    if Has(T, 'version 2.0') then
      Exit('EPL-2.0');
    if Has(T, 'version 1.0') then
      Exit('EPL-1.0');
    Exit;
  end;
  // as da GNU: vale a que o texto nomeia primeiro (o titulo)
  PosAgpl := Pos('gnu affero general public license', T);
  PosLgpl := Pos('gnu lesser general public license', T);
  PosGpl := Pos('gnu general public license', T);
  if (PosAgpl > 0) and ((PosLgpl = 0) or (PosAgpl < PosLgpl)) and ((PosGpl = 0) or (PosAgpl < PosGpl)) then
    Exit('AGPL-3.0-only');
  if (PosLgpl > 0) and ((PosGpl = 0) or (PosLgpl < PosGpl)) then
  begin
    if Has(T, 'version 2.1') then
      Exit('LGPL-2.1-only');
    if Has(T, 'version 3') then
      Exit('LGPL-3.0-only');
    Exit;
  end;
  if PosGpl > 0 then
  begin
    if Has(T, 'version 3') then
      Exit('GPL-3.0-only');
    if Has(T, 'version 2') then
      Exit('GPL-2.0-only');
    Exit;
  end;
  if Has(T, 'boost software license') then
    Exit('BSL-1.0');
  if Has(T, 'this is free and unencumbered software released into the public domain') then
    Exit('Unlicense');
  if Has(T, 'cc0 1.0 universal') or Has(T, 'creative commons zero') then
    Exit('CC0-1.0');
  if Has(T, 'do what the fuck you want to public license') then
    Exit('WTFPL');
  // as que se reconhecem pelas frases tipicas
  if Has(T, 'permission is hereby granted, free of charge, to any person obtaining a copy') then
  begin
    if Has(T, 'the software is provided "as is"') or Has(T, 'the software is provided ''as is''') then
      Exit('MIT');
    Exit;
  end;
  if Has(T, 'permission to use, copy, modify, and/or distribute this software for any purpose with or without fee') or
     Has(T, 'isc license') then
    Exit('ISC');
  if Has(T, 'redistribution and use in source and binary forms') then
  begin
    if Has(T, 'all advertising materials mentioning features') then
      Exit('BSD-4-Clause');
    if Has(T, 'neither the name of') then
      Exit('BSD-3-Clause');
    Exit('BSD-2-Clause');
  end;
  if Has(T, 'altered source versions must be plainly marked as such') then
    Exit('Zlib');
  if Has(T, 'mit license') and Has(T, 'permission is hereby granted') then
    Exit('MIT');
end;

function NormalizeLicenseId(const AValue: string): string;
var
  V: string;
begin
  Result := '';
  V := LowerCase(Trim(AValue)).Replace('_', '-').Replace(' ', '-');
  if V = '' then
    Exit;
  if (V = 'mit') or (V = 'mit-license') then
    Exit('MIT');
  if (V = 'isc') then
    Exit('ISC');
  if (V = 'unlicense') then
    Exit('Unlicense');
  if (V = 'zlib') or (V = 'zlib-license') then
    Exit('Zlib');
  if (V = 'bsl-1.0') or (V = 'boost') then
    Exit('BSL-1.0');
  if (V = 'cc0-1.0') or (V = 'cc0') then
    Exit('CC0-1.0');
  if (V = 'apache-2.0') or (V = 'apache-2') or (V = 'apache2') or (V = 'apache') or (V = 'apache-license-2.0') or (V = 'apache-license') then
    Exit('Apache-2.0');
  if (V = 'bsd-2-clause') or (V = 'bsd-2') then
    Exit('BSD-2-Clause');
  if (V = 'bsd-3-clause') or (V = 'bsd-3') or (V = 'bsd') or (V = 'new-bsd') then
    Exit('BSD-3-Clause');
  if (V = 'mpl-2.0') or (V = 'mpl2') or (V = 'mpl-2') or (V = 'mpl') then
    Exit('MPL-2.0');
  if (V = 'mpl-1.1') then
    Exit('MPL-1.1');
  if (V = 'epl-2.0') then
    Exit('EPL-2.0');
  if (V = 'epl-1.0') then
    Exit('EPL-1.0');
  if (V = 'lgpl-3.0') or (V = 'lgpl-3.0-only') or (V = 'lgpl-3') or (V = 'lgplv3') or (V = 'lgpl') then
    Exit('LGPL-3.0-only');
  if (V = 'lgpl-2.1') or (V = 'lgpl-2.1-only') then
    Exit('LGPL-2.1-only');
  if (V = 'gpl-3.0') or (V = 'gpl-3.0-only') or (V = 'gpl-3') or (V = 'gplv3') or (V = 'gpl') then
    Exit('GPL-3.0-only');
  if (V = 'gpl-2.0') or (V = 'gpl-2.0-only') or (V = 'gpl-2') or (V = 'gplv2') then
    Exit('GPL-2.0-only');
  if (V = 'agpl-3.0') or (V = 'agpl-3.0-only') or (V = 'agpl') then
    Exit('AGPL-3.0-only');
  if (V = 'wtfpl') then
    Exit('WTFPL');
end;

function StringField(AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := AObj.GetValue(AName);
  if (V <> nil) and (V is TJSONString) then
    Result := Trim(TJSONString(V).Value);
end;

function ParseBossJson(const AText: string; out AInfo: TBossInfo): Boolean;
var
  V: TJSONValue;
  Obj: TJSONObject;
begin
  AInfo := Default(TBossInfo);
  Result := False;
  try
    V := TJSONObject.ParseJSONValue(AText);
  except
    Exit;
  end;
  if V = nil then
    Exit;
  try
    if not (V is TJSONObject) then
      Exit;
    Obj := TJSONObject(V);
    AInfo.Name := StringField(Obj, 'name');
    AInfo.Version := StringField(Obj, 'version');
    AInfo.License := StringField(Obj, 'license');
    AInfo.HomePage := StringField(Obj, 'homepage');
    Result := True;
  finally
    V.Free;
  end;
end;

function LastSegment(const APath: string): string;
var
  P: Integer;
begin
  Result := APath;
  P := LastDelimiter('/\', Result);
  if P > 0 then
    Result := Copy(Result, P + 1, MaxInt);
end;

function ParseBossLock(const AText: string): TDictionary<string, string>;
var
  V, Modules: TJSONValue;
  Pair: TJSONPair;
  Item: TJSONObject;
  Ver, Name: string;
begin
  Result := TDictionary<string, string>.Create;
  try
    V := TJSONObject.ParseJSONValue(AText);
  except
    Exit;
  end;
  if V = nil then
    Exit;
  try
    if not (V is TJSONObject) then
      Exit;
    Modules := TJSONObject(V).GetValue('installedModules');
    if not (Modules is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Modules) do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      Item := TJSONObject(Pair.JsonValue);
      Ver := StringField(Item, 'version');
      if Ver = '' then
        Continue;
      Name := LowerCase(LastSegment(Pair.JsonString.Value));
      if Name <> '' then
        Result.AddOrSetValue(Name, Ver);
    end;
  finally
    V.Free;
  end;
end;

function SplitVersionedFolder(const AFolder: string; out AName, AVersion: string): Boolean;
var
  M: TMatch;
begin
  AName := '';
  AVersion := '';
  M := TRegEx.Match(AFolder, '^(.+?)[-_ ]v?(\d+(?:\.\d+){0,3}(?:[-+][0-9A-Za-z.]+)?)$');
  Result := M.Success;
  if Result then
  begin
    AName := M.Groups[1].Value;
    AVersion := M.Groups[2].Value;
  end;
end;

function IsVersionFolder(const AFolder: string): Boolean;
begin
  Result := TRegEx.IsMatch(AFolder, '^v?\d+(\.\d+){1,3}$');
end;

function StripDelphiSuffix(const AFolder: string): string;
begin
  Result := TRegEx.Replace(AFolder, '-\d+$', '');
  if Result = '' then
    Result := AFolder;
end;

end.
