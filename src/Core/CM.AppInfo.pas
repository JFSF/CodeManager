unit CM.AppInfo;

{ O que se sabe sobre a propria aplicacao, sem depender de Windows nem de interface: o nome, os enderecos, a leitura e
  a comparacao de versoes ('1.2.3.4'), o nome do Delphi que compilou e o texto de diagnostico que a pagina Acerca
  copia para quem quer reportar um problema. Quem le o executavel e o sistema e CM.SysInfo (Infrastructure). }

interface

type
  TAppVersion = record
    Valid: Boolean;
    Major, Minor, Release, Build: Integer;
  end;

  // o que a pagina Acerca mostra e copia (tudo ja em texto)
  TAboutInfo = record
    Version: string;            // '1.0.0'
    BuildKind: string;          // 'Release' | 'Debug'
    PlatformName: string;       // 'Win64'
    BuildDate: string;          // '2026-10-03 14:22'
    Compiler: string;           // 'Delphi 13 (VER370)'
    SystemName: string;
    Language: string;
    Theme: string;
    DataDir: string;
    GitAvailable, SvnAvailable, HgAvailable: Boolean;
  end;

const
  AppName = 'CodeManager';
  RepoUrl = 'https://github.com/JFSF/CodeManager';
  ReleasesUrl = RepoUrl + '/releases';
  IssuesUrl = RepoUrl + '/issues/new/choose';
  ChangelogUrl = RepoUrl + '/blob/master/CHANGELOG.md';
  LicenseName = 'MIT';

// '1.0.0.0', '1.2', 'v2.3.4' ou ' 1.0.0 ' -> versao; Valid = False se nao tiver pelo menos um numero
function ParseAppVersion(const AText: string): TAppVersion;
// '1.2.3' (AParts = 3) ou '1.2.3.4' (AParts = 4); os que faltam contam como 0
function VersionToText(const AVersion: TAppVersion; AParts: Integer = 3): string;
// < 0, 0 ou > 0
function CompareVersions(const A, B: TAppVersion): Integer;
// 37.0 -> 'Delphi 13'; um compilador que nao se conhece -> 'Delphi (compilador 99.0)'
function DelphiName(ACompilerVersion: Double): string;
// o texto que se cola numa issue: uma informacao por linha
function BuildAboutText(const AInfo: TAboutInfo): string;

implementation

uses
  System.SysUtils, System.Math;

function ParseAppVersion(const AText: string): TAppVersion;
var
  S: string;
  Parts: TArray<string>;
  I, V: Integer;
  Nums: array[0..3] of Integer;
begin
  Result := Default(TAppVersion);
  S := Trim(AText);
  if S.StartsWith('v', True) then
    S := Copy(S, 2, MaxInt);
  if S = '' then
    Exit;
  Parts := S.Split(['.']);
  if Length(Parts) > 4 then
    Exit;
  FillChar(Nums, SizeOf(Nums), 0);
  for I := 0 to High(Parts) do
  begin
    if not TryStrToInt(Trim(Parts[I]), V) or (V < 0) then
      Exit;
    Nums[I] := V;
  end;
  Result.Major := Nums[0];
  Result.Minor := Nums[1];
  Result.Release := Nums[2];
  Result.Build := Nums[3];
  Result.Valid := True;
end;

function VersionToText(const AVersion: TAppVersion; AParts: Integer): string;
begin
  AParts := EnsureRange(AParts, 1, 4);
  Result := IntToStr(AVersion.Major);
  if AParts >= 2 then Result := Result + '.' + IntToStr(AVersion.Minor);
  if AParts >= 3 then Result := Result + '.' + IntToStr(AVersion.Release);
  if AParts >= 4 then Result := Result + '.' + IntToStr(AVersion.Build);
end;

function CompareVersions(const A, B: TAppVersion): Integer;
begin
  Result := A.Major - B.Major;
  if Result = 0 then Result := A.Minor - B.Minor;
  if Result = 0 then Result := A.Release - B.Release;
  if Result = 0 then Result := A.Build - B.Build;
end;

function DelphiName(ACompilerVersion: Double): string;
begin
  case Round(ACompilerVersion * 10) of
    370: Result := 'Delphi 13';
    360: Result := 'Delphi 12';
    350: Result := 'Delphi 11';
    340: Result := 'Delphi 10.4';
    330: Result := 'Delphi 10.3';
  else
    Result := Format('Delphi (compilador %s)', [FormatFloat('0.0', ACompilerVersion, TFormatSettings.Invariant)]);
  end;
end;

function BuildAboutText(const AInfo: TAboutInfo): string;

  function YesNo(AValue: Boolean): string;
  begin
    if AValue then Result := 'sim' else Result := 'não';
  end;

begin
  Result := AppName + ' ' + AInfo.Version + ' (' + AInfo.BuildKind + ', ' + AInfo.PlatformName + ')' + sLineBreak +
    'Compilado: ' + AInfo.BuildDate + sLineBreak +
    'Compilador: ' + AInfo.Compiler + sLineBreak +
    'Sistema: ' + AInfo.SystemName + sLineBreak +
    'Idioma: ' + AInfo.Language + sLineBreak +
    'Tema: ' + AInfo.Theme + sLineBreak +
    'Dados: ' + AInfo.DataDir + sLineBreak +
    'Git: ' + YesNo(AInfo.GitAvailable) + ' · Subversion: ' + YesNo(AInfo.SvnAvailable) +
    ' · Mercurial: ' + YesNo(AInfo.HgAvailable);
end;

end.
