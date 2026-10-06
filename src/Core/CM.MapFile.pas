unit CM.MapFile;

{ Le os nomes das units de um ficheiro .map detalhado do compilador do Delphi (DCC_MapFile=3). O mapa so tem as units que
  ficaram mesmo ligadas ao executavel, por isso confirma o que as clausulas uses so sugerem e traz as units que ninguem
  nomeia no codigo (as que a RTL e as bibliotecas usam entre si).

  Procura dois tipos de linhas: as entradas da secao "Detailed map of segments" ("... M=Nome ...") e os cabecalhos
  "Line numbers for Nome(Nome.pas) ...".

  Adaptado do DX.Comply.MapFile.Reader (MIT, Olaf Monien): https://github.com/omonien/DX.Comply }

interface

uses
  System.SysUtils;

// os nomes de units (sem repeticoes, sem distinguir maiusculas) de um .map; a primeira forma que aparece e a que fica
function ParseMapUnits(const AText: string): TArray<string>;
// o mesmo, de um ficheiro (vazio se nao existe ou nao se le)
function LoadMapUnits(const AFileName: string): TArray<string>;

implementation

uses
  System.Classes, System.IOUtils, System.RegularExpressions, System.Generics.Collections;

function ParseMapUnits(const AText: string): TArray<string>;
var
  List: TList<string>;
  Seen: TDictionary<string, Boolean>;
  Line, Name: string;
  M: TMatch;
begin
  List := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Line in AText.Replace(#13, '').Split([#10]) do
    begin
      Name := '';
      // um mapa detalhado tem centenas de milhares de linhas: so as que podem trazer uma unit passam pela expressao regular
      if Pos('Line numbers for', Line) > 0 then
      begin
        M := TRegEx.Match(Line, '^\s*Line numbers for\s+([A-Za-z0-9_\.]+)\s*\(', [roIgnoreCase]);
        if M.Success then
          Name := M.Groups[1].Value;
      end
      else if Pos(' M=', Line) > 0 then
      begin
        M := TRegEx.Match(Line, '\bM=([A-Za-z0-9_\.]+)\b');
        if M.Success then
          Name := M.Groups[1].Value;
      end;
      if (Name <> '') and Seen.TryAdd(LowerCase(Name), True) then
        List.Add(Name);
    end;
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function LoadMapUnits(const AFileName: string): TArray<string>;
var
  Text: string;
begin
  Result := nil;
  if (AFileName = '') or not TFile.Exists(AFileName) then
    Exit;
  try
    // o mapa vem na pagina de codigo do Windows: nomes de units sao ASCII, por isso qualquer leitura serve
    Text := TFile.ReadAllText(AFileName, TEncoding.ANSI);
  except
    on Exception do
      Exit;
  end;
  Result := ParseMapUnits(Text);
end;

end.
