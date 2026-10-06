unit CM.Dproj;

{ Le o minimo de um projecto Delphi (.dproj) para o SBOM: nome e versao, a descricao e a empresa (VerInfo_Keys), os
  caminhos de procura de units, os espacos de nomes e se o compilador gera o ficheiro .map.

  O .dproj e XML do MSBuild: varios PropertyGroup, cada um com uma condicao ("Base", "Cfg_1", "Cfg_2_Win64"...). Escolhe-se uma
  configuracao e uma plataforma, juntam-se por ordem os grupos que lhes dizem respeito (o ultimo valor ganha; um valor que
  usa $(Nome) leva o valor anterior da propria propriedade, como faz o MSBuild) e expandem-se as variaveis conhecidas.
  Le-se com expressoes regulares, sem MSXML, por isso funciona em qualquer lado.

  Adaptado da ideia do DX.Comply.ProjectScanner (MIT, Olaf Monien): https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults;

type
  TDprojInfo = record
    Found: Boolean;
    FileName: string;                 // caminho completo do .dproj
    ProjectName: string;              // sem extensao
    ProjectVersion: string;           // '20.3' (a versao do formato do Delphi)
    FrameworkType: string;            // 'VCL', 'FMX' ou ''
    MainSource: string;               // 'CodeManager.dpr'
    Config: string;                   // a configuracao escolhida ('Release')
    Platform: string;                 // a plataforma escolhida ('Win64')
    Configs: TArray<string>;          // as configuracoes do projecto
    Platforms: TArray<string>;        // as plataformas activas
    FileVersion: string;              // de VerInfo_Keys
    Description: string;
    Company: string;
    Copyright: string;
    UnitSearchPath: TArray<string>;   // sem entradas vazias nem repeticoes, como estao escritas (relativas ao projecto)
    Namespaces: TArray<string>;
    MapFileMode: Integer;             // DCC_MapFile: 0 nenhum, 1 segmentos, 2 publicos, 3 detalhado
    ExeOutput: string;                // DCC_ExeOutput, com as variaveis expandidas ('' = pasta do projecto)
    IsPackage: Boolean;               // o projecto principal e um .dpk
  end;

// os valores de variaveis que se conhecem (por omissao, so as do ambiente e as proprias do projecto); Vars pode ser nil
procedure ParseDproj(const AXml, AFileName, AConfig, APlatform: string; AVars: TDictionary<string, string>;
  out AInfo: TDprojInfo);
// procura o .dproj de um projecto: em ARoot e, se nao houver, nas pastas acima (ate 3); '' se nao encontra.
// Com varios, prefere o que tem o nome de APreferredName e depois o primeiro por ordem alfabetica
function FindDprojFile(const ARoot, APreferredName: string): string;
// le o ficheiro e interpreta-o (AInfo.Found = False se nao existe ou nao se le)
procedure LoadDproj(const AFileName, AConfig, APlatform: string; AVars: TDictionary<string, string>;
  out AInfo: TDprojInfo);

implementation

uses
  System.IOUtils, System.RegularExpressions, System.StrUtils;

function XmlDecode(const AText: string): string;
begin
  Result := AText.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"').Replace('&apos;', '''')
    .Replace('&amp;', '&');
end;

// os pares chave=valor de VerInfo_Keys ('CompanyName=X;FileDescription=Y;...')
function VerInfoValue(const AKeys, AName: string): string;
var
  Part: string;
  P: Integer;
begin
  Result := '';
  for Part in AKeys.Split([';']) do
  begin
    P := Pos('=', Part);
    if (P > 0) and SameText(Trim(Copy(Part, 1, P - 1)), AName) then
      Exit(Trim(Copy(Part, P + 1, MaxInt)));
  end;
end;

function SplitList(const AValue: string): TArray<string>;
var
  List: TList<string>;
  S, T: string;
  Seen: TDictionary<string, Boolean>;
begin
  List := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for S in AValue.Split([';']) do
    begin
      T := Trim(S);
      if (T <> '') and not T.Contains('$(DCC_') and Seen.TryAdd(LowerCase(T), True) then
        List.Add(T);
    end;
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

// expande $(Nome): primeiro as variaveis dadas, depois as do ambiente e por fim as que o proprio projecto define (um valor
// por omissao, como "<Chart4DDir Condition=...>"); o que nao se conhece fica como esta. Os valores do projecto podem usar
// outras variaveis, por isso expandem-se de novo (ate 4 niveis)
function Expand(const AText: string; AVars, AProps: TDictionary<string, string>; ADepth: Integer = 0): string;
var
  M: TMatch;
  Value: string;
  SB: TStringBuilder;
  Last: Integer;
begin
  SB := TStringBuilder.Create;
  try
    Last := 1;
    for M in TRegEx.Matches(AText, '\$\(([A-Za-z0-9_]+)\)') do
    begin
      SB.Append(Copy(AText, Last, M.Index - Last));
      if Assigned(AVars) and AVars.TryGetValue(LowerCase(M.Groups[1].Value), Value) then
        SB.Append(Value)
      else
      begin
        Value := GetEnvironmentVariable(M.Groups[1].Value);
        if (Value = '') and Assigned(AProps) and (ADepth < 4) and AProps.TryGetValue(LowerCase(M.Groups[1].Value), Value) then
          Value := Expand(Value, AVars, AProps, ADepth + 1);
        if Value <> '' then
          SB.Append(Value)
        else
          SB.Append(M.Value);
      end;
      Last := M.Index + M.Length;
    end;
    SB.Append(Copy(AText, Last, MaxInt));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// a condicao de um PropertyGroup esta satisfeita para esta configuracao e plataforma?
function ConditionHolds(const ACondition, AConfig: string; AFlags: TDictionary<string, Boolean>): Boolean;
var
  M: TMatch;
begin
  if Trim(ACondition) = '' then
    Exit(True);
  for M in TRegEx.Matches(ACondition, '''\$\(([A-Za-z0-9_]+)\)''\s*!=\s*''''') do
    if AFlags.ContainsKey(LowerCase(M.Groups[1].Value)) then
      Exit(True);
  for M in TRegEx.Matches(ACondition, '''\$\(Config\)''\s*==\s*''([^'']*)''') do
    if SameText(M.Groups[1].Value, AConfig) then
      Exit(True);
  Result := False;
end;

procedure ParseDproj(const AXml, AFileName, AConfig, APlatform: string; AVars: TDictionary<string, string>;
  out AInfo: TDprojInfo);
var
  Props: TDictionary<string, string>;
  Flags: TDictionary<string, Boolean>;
  Vars: TDictionary<string, string>;
  Groups: TMatchCollection;
  G, E, B: TMatch;
  Key, Cfg, Plat, Value, Prev, CfgKey: string;
  CfgList, PlatList: TList<string>;

  function Prop(const AName: string): string;
  begin
    if not Props.TryGetValue(LowerCase(AName), Result) then
      Result := '';
  end;

begin
  AInfo := Default(TDprojInfo);
  AInfo.FileName := AFileName;
  AInfo.ProjectName := TPath.GetFileNameWithoutExtension(AFileName);
  AInfo.Found := AXml <> '';
  if not AInfo.Found then
    Exit;
  Props := TDictionary<string, string>.Create;
  Flags := TDictionary<string, Boolean>.Create;
  Vars := TDictionary<string, string>.Create;
  CfgList := TList<string>.Create;
  PlatList := TList<string>.Create;
  try
    // configuracoes e a chave de cada uma (Release -> Cfg_2)
    CfgKey := '';
    Cfg := AConfig;
    for B in TRegEx.Matches(AXml, '<BuildConfiguration\s+Include="([^"]+)"[^>]*>(.*?)</BuildConfiguration>',
        [roSingleLine]) do
    begin
      if not SameText(B.Groups[1].Value, 'Base') then
        CfgList.Add(B.Groups[1].Value);
      E := TRegEx.Match(B.Groups[2].Value, '<Key>([^<]*)</Key>');
      if E.Success and (Cfg <> '') and SameText(B.Groups[1].Value, Cfg) then
        CfgKey := E.Groups[1].Value;
    end;
    // plataformas activas
    for B in TRegEx.Matches(AXml, '<Platform\s+value="([^"]+)">\s*True\s*</Platform>', [roIgnoreCase]) do
      PlatList.Add(B.Groups[1].Value);
    // a configuracao e a plataforma por omissao do proprio ficheiro
    if Cfg = '' then
    begin
      // sem configuracao pedida: a que se entrega (Release), senao a do proprio ficheiro, senao a primeira
      if CfgList.IndexOf('Release') >= 0 then
        Cfg := 'Release'
      else
      begin
        E := TRegEx.Match(AXml, '<Config\s+Condition="[^"]*">([^<]*)</Config>');
        if E.Success and (CfgList.IndexOf(Trim(E.Groups[1].Value)) >= 0) then
          Cfg := Trim(E.Groups[1].Value)
        else if CfgList.Count > 0 then
          Cfg := CfgList[0];
      end;
      for B in TRegEx.Matches(AXml, '<BuildConfiguration\s+Include="([^"]+)"[^>]*>(.*?)</BuildConfiguration>',
          [roSingleLine]) do
        if SameText(B.Groups[1].Value, Cfg) then
        begin
          E := TRegEx.Match(B.Groups[2].Value, '<Key>([^<]*)</Key>');
          if E.Success then
            CfgKey := E.Groups[1].Value;
        end;
    end;
    Plat := APlatform;
    if Plat = '' then
    begin
      E := TRegEx.Match(AXml, '<Platform\s+Condition="[^"]*">([^<]*)</Platform>');
      if E.Success then
        Plat := Trim(E.Groups[1].Value);
      if (Plat = '') or ((PlatList.Count > 0) and (PlatList.IndexOf(Plat) < 0)) then
      begin
        if PlatList.IndexOf('Win64') >= 0 then
          Plat := 'Win64'
        else if PlatList.Count > 0 then
          Plat := PlatList[0]
        else
          Plat := 'Win32';
      end;
    end;

    // as marcas que as condicoes dos grupos testam
    Flags.Add('base', True);
    Flags.Add('base_' + LowerCase(Plat), True);
    if CfgKey <> '' then
    begin
      Flags.Add(LowerCase(CfgKey), True);
      Flags.Add(LowerCase(CfgKey) + '_' + LowerCase(Plat), True);
    end;

    // variaveis proprias do projecto
    if Assigned(AVars) then
      for Key in AVars.Keys do
        Vars.AddOrSetValue(LowerCase(Key), AVars[Key]);
    Vars.AddOrSetValue('platform', Plat);
    Vars.AddOrSetValue('config', Cfg);
    Vars.AddOrSetValue('msbuildprojectname', AInfo.ProjectName);

    // os grupos, por ordem: o ultimo valor ganha; "$(Nome)" na propria propriedade leva o valor anterior
    Groups := TRegEx.Matches(AXml, '<PropertyGroup(?:\s+Condition="([^"]*)")?\s*>(.*?)</PropertyGroup>', [roSingleLine]);
    for G in Groups do
    begin
      if not ConditionHolds(XmlDecode(G.Groups[1].Value), Cfg, Flags) then
        Continue;
      for E in TRegEx.Matches(G.Groups[2].Value, '<([A-Za-z_][A-Za-z0-9_]*)(?:\s[^>]*)?>([^<]*)</\1>') do
      begin
        Key := LowerCase(E.Groups[1].Value);
        Value := XmlDecode(E.Groups[2].Value);
        if not Props.TryGetValue(Key, Prev) then
          Prev := '';
        Value := Value.Replace('$(' + E.Groups[1].Value + ')', Prev);
        Props.AddOrSetValue(Key, Value);
      end;
    end;

    AInfo.ProjectVersion := Prop('ProjectVersion');
    AInfo.FrameworkType := Prop('FrameworkType');
    AInfo.MainSource := Prop('MainSource');
    AInfo.IsPackage := SameText(ExtractFileExt(AInfo.MainSource), '.dpk');
    AInfo.Config := Cfg;
    AInfo.Platform := Plat;
    AInfo.Configs := CfgList.ToArray;
    AInfo.Platforms := PlatList.ToArray;
    Value := Prop('VerInfo_Keys');
    AInfo.FileVersion := VerInfoValue(Value, 'FileVersion');
    AInfo.Description := VerInfoValue(Value, 'FileDescription');
    AInfo.Company := VerInfoValue(Value, 'CompanyName');
    AInfo.Copyright := VerInfoValue(Value, 'LegalCopyright');
    AInfo.UnitSearchPath := SplitList(Expand(Prop('DCC_UnitSearchPath'), Vars, Props));
    AInfo.Namespaces := SplitList(Expand(Prop('DCC_Namespace'), Vars, Props));
    AInfo.MapFileMode := StrToIntDef(Trim(Prop('DCC_MapFile')), 0);
    AInfo.ExeOutput := Trim(Expand(Prop('DCC_ExeOutput'), Vars, Props));
  finally
    PlatList.Free;
    CfgList.Free;
    Vars.Free;
    Flags.Free;
    Props.Free;
  end;
end;

function FindDprojFile(const ARoot, APreferredName: string): string;
var
  Dir, Parent: string;
  Files: TArray<string>;
  F: string;
  Level: Integer;
begin
  Result := '';
  if Trim(ARoot) = '' then
    Exit;
  Dir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(ARoot));
  for Level := 0 to 3 do
  begin
    if not TDirectory.Exists(Dir) then
      Break;
    Files := TDirectory.GetFiles(Dir, '*.dproj', TSearchOption.soTopDirectoryOnly);
    if Length(Files) > 0 then
    begin
      TArray.Sort<string>(Files);
      for F in Files do
        if SameText(TPath.GetFileNameWithoutExtension(F), APreferredName) then
          Exit(F);
      Exit(Files[0]);
    end;
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = '') or SameText(Parent, Dir) then
      Break;
    Dir := Parent;
  end;
end;

procedure LoadDproj(const AFileName, AConfig, APlatform: string; AVars: TDictionary<string, string>;
  out AInfo: TDprojInfo);
var
  Xml: string;
begin
  Xml := '';
  if (AFileName <> '') and TFile.Exists(AFileName) then
    try
      Xml := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    except
      on Exception do
        Xml := '';
    end;
  ParseDproj(Xml, AFileName, AConfig, APlatform, AVars, AInfo);
end;

end.
