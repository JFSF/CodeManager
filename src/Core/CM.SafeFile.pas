unit CM.SafeFile;

{ Gravacao e leitura segura dos ficheiros de dados da aplicacao (definicoes, progresso, historico).

  Gravar: o texto vai primeiro para "<ficheiro>.tmp" e so depois substitui o ficheiro de forma
  atomica (ReplaceFile do Windows), que guarda a versao anterior em "<ficheiro>.bak". Assim, uma
  falha a meio da gravacao nunca deixa o ficheiro cortado ou vazio.

  Ler: se o ficheiro estiver ilegivel ou nao for JSON valido, usa a copia ".bak"; nesse caso o
  ficheiro danificado fica guardado como ".corrupt" e a copia boa e restaurada. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON;

type
  // o ficheiro esta danificado e nao ha copia de seguranca valida
  EDataFileCorrupt = class(Exception);

const
  BackupExt = '.bak';
  CorruptExt = '.corrupt';
  TempExt = '.tmp';

// grava AText em AFileName de forma atomica, mantendo a versao anterior em .bak
procedure WriteFileAtomic(const AFileName, AText: string; AEncoding: TEncoding);
// devolve o texto JSON (um objecto) de AFileName ou, se este estiver danificado, da copia .bak.
// ARecovered = True quando foi preciso usar a copia (o ficheiro principal ja foi restaurado).
// Levanta EDataFileCorrupt se nenhum dos dois for valido.
function ReadJsonFile(const AFileName: string; out ARecovered: Boolean): string;
// existe o ficheiro ou, pelo menos, a sua copia de seguranca?
function DataFileExists(const AFileName: string): Boolean;
// apaga o ficheiro e as suas copias (.bak, .corrupt, .tmp)
procedure DeleteDataFile(const AFileName: string);

implementation


uses
  CM.Lang;
function IsJsonObject(const AText: string): Boolean;
var
  V: TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(AText);
  try
    Result := V is TJSONObject;
  finally
    V.Free;
  end;
end;

procedure WriteFileAtomic(const AFileName, AText: string; AEncoding: TEncoding);
var
  Tmp, Bak, Dir: string;
begin
  Dir := TPath.GetDirectoryName(AFileName);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  Tmp := AFileName + TempExt;
  Bak := AFileName + BackupExt;
  TFile.WriteAllText(Tmp, AText, AEncoding);
  if TFile.Exists(AFileName) then
    TFile.Replace(Tmp, AFileName, Bak)       // atomico; a versao anterior fica em .bak
  else
    TFile.Move(Tmp, AFileName);
end;

function DataFileExists(const AFileName: string): Boolean;
begin
  Result := TFile.Exists(AFileName) or TFile.Exists(AFileName + BackupExt);
end;

function ReadJsonFile(const AFileName: string; out ARecovered: Boolean): string;
var
  Text, BakText, Bak: string;
begin
  ARecovered := False;
  if TFile.Exists(AFileName) then
    try
      Text := TFile.ReadAllText(AFileName, TEncoding.UTF8);
      if IsJsonObject(Text) then
        Exit(Text);
    except
      on Exception do ;      // ilegivel: tenta a copia
    end;

  Bak := AFileName + BackupExt;
  if TFile.Exists(Bak) then
    try
      BakText := TFile.ReadAllText(Bak, TEncoding.UTF8);
      if IsJsonObject(BakText) then
      begin
        if TFile.Exists(AFileName) then
          TFile.Copy(AFileName, AFileName + CorruptExt, True);   // guarda o danificado para analise
        TFile.Copy(Bak, AFileName, True);                         // restaura a copia boa
        ARecovered := True;
        Exit(BakText);
      end;
    except
      on Exception do ;
    end;

  if TFile.Exists(AFileName) then
  begin
    try
      TFile.Copy(AFileName, AFileName + CorruptExt, True);
    except
      on Exception do ;
    end;
    raise EDataFileCorrupt.CreateFmt(
      Tr('O ficheiro "%s" esta danificado e nao ha uma copia de seguranca valida.'),
      [TPath.GetFileName(AFileName)]);
  end;
  raise EFileNotFoundException.CreateFmt(Tr('O ficheiro "%s" nao existe.'), [TPath.GetFileName(AFileName)]);
end;

procedure DeleteDataFile(const AFileName: string);
var
  Ext: string;
begin
  for Ext in ['', BackupExt, CorruptExt, TempExt] do
    if TFile.Exists(AFileName + Ext) then
      TFile.Delete(AFileName + Ext);
end;

end.
