unit CM.History;

{ Historico do progresso de um projecto: um registo por dia (o ultimo do dia substitui o anterior)
  com os totais e o que ja esta concluido, para mostrar a evolucao no tempo.
  Fica num ficheiro proprio (history-<id>.json), separado do progresso, que tem de manter o
  formato das paginas HTML. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.IOUtils, System.JSON, CM.Stats, CM.SafeFile;

type
  TSnapshot = record
    Date: string;                 // 'yyyy-mm-dd'
    Files, DoneFiles: Integer;
    Methods, DoneMethods: Integer;
    FilesCompila, FilesSonar: Integer;
    MethodsCompila, MethodsSonar: Integer;
    class function FromStats(const ADate: string; const St: TStats): TSnapshot; static;
    function SameValues(const AOther: TSnapshot): Boolean;
    // percentagem (0..100) de ficheiros concluidos / metodos revistos; 0 quando nao ha total
    function PercentFiles: Double;
    function PercentMethods: Double;
    function PercentFilesCompila: Double;
    function PercentFilesSonar: Double;
    // o dia como TDateTime (False se a data for invalida)
    function TryDay(out ADay: TDateTime): Boolean;
  end;

  THistory = class
  private
    FItems: TList<TSnapshot>;
    FRecovered: Boolean;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TSnapshot;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    // junta o registo do dia (substitui o do mesmo dia; mantem a ordem por data).
    // Devolve False quando nada mudou (mesmo dia com os mesmos valores).
    function Capture(const ASnapshot: TSnapshot): Boolean;
    function ToJSONString: string;
    procedure LoadFromJSONString(const AJson: string);
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
    // a ultima leitura teve de usar a copia de seguranca (o ficheiro estava danificado)
    property RecoveredFromBackup: Boolean read FRecovered;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TSnapshot read GetItem; default;
  end;

// 'yyyy-mm-dd' -> data; False se o texto nao for uma data valida
function TryParseDay(const AText: string; out ADay: TDateTime): Boolean;
function DayText(ADay: TDateTime): string;

implementation

function TryParseDay(const AText: string; out ADay: TDateTime): Boolean;
var
  Y, M, D: Integer;
begin
  Result := (Length(AText) = 10) and (AText[5] = '-') and (AText[8] = '-') and
    TryStrToInt(Copy(AText, 1, 4), Y) and TryStrToInt(Copy(AText, 6, 2), M) and
    TryStrToInt(Copy(AText, 9, 2), D) and TryEncodeDate(Y, M, D, ADay);
end;

function DayText(ADay: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd', ADay);
end;

{ TSnapshot }

class function TSnapshot.FromStats(const ADate: string; const St: TStats): TSnapshot;
begin
  Result.Date := ADate;
  Result.Files := St.Files;
  Result.DoneFiles := St.DoneFiles;
  Result.Methods := St.Methods;
  Result.DoneMethods := St.DoneMethods;
  Result.FilesCompila := St.FilesCompila;
  Result.FilesSonar := St.FilesSonar;
  Result.MethodsCompila := St.MethodsCompila;
  Result.MethodsSonar := St.MethodsSonar;
end;

function TSnapshot.SameValues(const AOther: TSnapshot): Boolean;
begin
  Result := (Date = AOther.Date) and (Files = AOther.Files) and (DoneFiles = AOther.DoneFiles) and
    (Methods = AOther.Methods) and (DoneMethods = AOther.DoneMethods) and
    (FilesCompila = AOther.FilesCompila) and (FilesSonar = AOther.FilesSonar) and
    (MethodsCompila = AOther.MethodsCompila) and (MethodsSonar = AOther.MethodsSonar);
end;

function TSnapshot.PercentFiles: Double;
begin
  if Files > 0 then Result := 100 * DoneFiles / Files else Result := 0;
end;

function TSnapshot.PercentMethods: Double;
begin
  if Methods > 0 then Result := 100 * DoneMethods / Methods else Result := 0;
end;

function TSnapshot.PercentFilesCompila: Double;
begin
  if Files > 0 then Result := 100 * FilesCompila / Files else Result := 0;
end;

function TSnapshot.PercentFilesSonar: Double;
begin
  if Files > 0 then Result := 100 * FilesSonar / Files else Result := 0;
end;

function TSnapshot.TryDay(out ADay: TDateTime): Boolean;
begin
  Result := TryParseDay(Date, ADay);
end;

{ THistory }

constructor THistory.Create;
begin
  inherited;
  FItems := TList<TSnapshot>.Create;
end;

destructor THistory.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure THistory.Clear;
begin
  FItems.Clear;
end;

function THistory.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function THistory.GetItem(AIndex: Integer): TSnapshot;
begin
  Result := FItems[AIndex];
end;

function THistory.Capture(const ASnapshot: TSnapshot): Boolean;
var
  I: Integer;
begin
  // 'yyyy-mm-dd' ordena por texto como ordena por data
  for I := 0 to FItems.Count - 1 do
  begin
    if FItems[I].Date = ASnapshot.Date then
    begin
      Result := not FItems[I].SameValues(ASnapshot);
      if Result then
        FItems[I] := ASnapshot;
      Exit;
    end;
    if FItems[I].Date > ASnapshot.Date then
    begin
      FItems.Insert(I, ASnapshot);
      Exit(True);
    end;
  end;
  FItems.Add(ASnapshot);
  Result := True;
end;

function THistory.ToJSONString: string;
var
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  S: TSnapshot;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr := TJSONArray.Create;
    Root.AddPair('snapshots', Arr);
    for S in FItems do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('date', S.Date);
      Obj.AddPair('files', TJSONNumber.Create(S.Files));
      Obj.AddPair('doneFiles', TJSONNumber.Create(S.DoneFiles));
      Obj.AddPair('methods', TJSONNumber.Create(S.Methods));
      Obj.AddPair('doneMethods', TJSONNumber.Create(S.DoneMethods));
      Obj.AddPair('filesCompila', TJSONNumber.Create(S.FilesCompila));
      Obj.AddPair('filesSonar', TJSONNumber.Create(S.FilesSonar));
      Obj.AddPair('methodsCompila', TJSONNumber.Create(S.MethodsCompila));
      Obj.AddPair('methodsSonar', TJSONNumber.Create(S.MethodsSonar));
      Arr.AddElement(Obj);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure THistory.LoadFromJSONString(const AJson: string);
var
  Root: TJSONValue;
  Arr: TJSONArray;
  Item: TJSONValue;
  Obj: TJSONObject;
  S: TSnapshot;
  Day: TDateTime;

  function Num(const AName: string): Integer;
  begin
    Result := Obj.GetValue<Integer>(AName, 0);
    if Result < 0 then
      Result := 0;
  end;

begin
  FItems.Clear;
  Root := TJSONObject.ParseJSONValue(AJson);
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    if not TJSONObject(Root).TryGetValue<TJSONArray>('snapshots', Arr) then
      Exit;
    for Item in Arr do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Obj := TJSONObject(Item);
      S.Date := Obj.GetValue<string>('date', '');
      if not TryParseDay(S.Date, Day) then
        Continue;
      S.Files := Num('files');
      S.DoneFiles := Num('doneFiles');
      S.Methods := Num('methods');
      S.DoneMethods := Num('doneMethods');
      S.FilesCompila := Num('filesCompila');
      S.FilesSonar := Num('filesSonar');
      S.MethodsCompila := Num('methodsCompila');
      S.MethodsSonar := Num('methodsSonar');
      Capture(S);              // mantem a ordem e junta datas repetidas (fica a ultima)
    end;
  finally
    Root.Free;
  end;
end;

procedure THistory.LoadFromFile(const AFileName: string);
begin
  LoadFromJSONString(ReadJsonFile(AFileName, FRecovered));
end;

procedure THistory.SaveToFile(const AFileName: string);
begin
  WriteFileAtomic(AFileName, ToJSONString, TUTF8Encoding.Create(False));
end;

end.
