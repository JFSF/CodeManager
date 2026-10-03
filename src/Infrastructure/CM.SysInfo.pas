unit CM.SysInfo;

{ O que a pagina Acerca vai ler ao sistema: a versao e a data do executavel, a compilacao (Debug ou Release, 32 ou 64
  bits), o Windows e o Delphi que compilou. So le. }

interface

uses
  CM.AppInfo;

// 'major.minor.release.build' do recurso de versao do executavel; '' se nao tiver
function ExeVersionText: string;
// a data da compilacao (a do ficheiro do executavel); 0 se nao se consegue ler
function ExeBuildTime: TDateTime;
function IsDebugBuild: Boolean;
function PlatformText: string;
function CompilerText: string;
function SystemText: string;
// tudo junto, pronto para mostrar e copiar; os campos de idioma, tema e dados vem de quem chama
function CollectAboutInfo(const ALanguage, ATheme, ADataDir: string): TAboutInfo;

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, CM.Git, CM.Svn;

function ExeVersionText: string;
var
  Exe: string;
  Size, Handle, Len: DWORD;
  Buf: TBytes;
  Info: PVSFixedFileInfo;
begin
  Result := '';
  Exe := ParamStr(0);
  Size := GetFileVersionInfoSize(PChar(Exe), Handle);
  if Size = 0 then
    Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(Exe), 0, Size, @Buf[0]) then
    Exit;
  if VerQueryValue(@Buf[0], '\', Pointer(Info), Len) and (Info <> nil) then
    Result := Format('%d.%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
      HiWord(Info.dwFileVersionLS), LoWord(Info.dwFileVersionLS)]);
end;

function ExeBuildTime: TDateTime;
begin
  try
    Result := TFile.GetLastWriteTime(ParamStr(0));
  except
    Result := 0;
  end;
end;

function IsDebugBuild: Boolean;
begin
{$IFDEF DEBUG}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

function PlatformText: string;
begin
{$IFDEF WIN64}
  Result := 'Win64';
{$ELSE}
  Result := 'Win32';
{$ENDIF}
end;

function CompilerText: string;
begin
  Result := DelphiName(CompilerVersion) + ' (VER' + IntToStr(Round(CompilerVersion * 10)) + ')';
end;

function SystemText: string;
begin
  Result := TOSVersion.ToString;
end;

function CollectAboutInfo(const ALanguage, ATheme, ADataDir: string): TAboutInfo;
var
  V: TAppVersion;
  T: TDateTime;
begin
  Result := Default(TAboutInfo);
  V := ParseAppVersion(ExeVersionText);
  if V.Valid then
    Result.Version := VersionToText(V, 3)
  else
    Result.Version := '?';
  if IsDebugBuild then Result.BuildKind := 'Debug' else Result.BuildKind := 'Release';
  Result.PlatformName := PlatformText;
  T := ExeBuildTime;
  if T > 0 then
    Result.BuildDate := FormatDateTime('yyyy-mm-dd hh:nn', T)
  else
    Result.BuildDate := '?';
  Result.Compiler := CompilerText;
  Result.SystemName := SystemText;
  Result.Language := ALanguage;
  Result.Theme := ATheme;
  Result.DataDir := ADataDir;
  Result.GitAvailable := GitAvailable;
  Result.SvnAvailable := SvnAvailable;
end;

end.
