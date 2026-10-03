unit CM.Highlight;

{ Leitura de codigo-fonte Delphi para mostrar: parte o texto em linhas, marca em cada uma os pedacos
  (palavras reservadas, textos, comentarios, numeros, directivas de compilacao) e encontra a linha onde
  uma rotina comeca. Nao compila nada: e tolerante, o que nao percebe fica como texto normal. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TSynKind = (skPlain, skKeyword, skString, skComment, skNumber, skDirective);

  // um pedaco de uma linha: posicao (a partir de 1) e tamanho
  TSynSpan = record
    Start, Len: Integer;
    Kind: TSynKind;
  end;

  TCodeLine = record
    Text: string;                // sem a mudanca de linha, com os TABs trocados por espacos
    Spans: TArray<TSynSpan>;     // por ordem; o que nao esta em nenhum pedaco e texto normal
  end;

  TCodeDoc = class
  private
    FLines: TArray<TCodeLine>;
  public
    constructor Create(const AText: string);
    function Count: Integer;
    function Line(AIndex: Integer): TCodeLine;
    // comprimento da linha mais comprida (em caracteres)
    function LongestLine: Integer;
  end;

const
  TabWidth = 2;

function IsKeyword(const AWord: string): Boolean;
// a linha (a partir de 0) onde comeca a rotina; -1 se nao se encontra. AOwner = classe ('' = rotina livre),
// ASimple = nome sem qualificacao. Prefere a definicao (implementation) a declaracao na classe.
function FindRoutineLine(ADoc: TCodeDoc; const AOwner, ASimple: string): Integer;

implementation

const
  Keywords: array[0..99] of string = (
    'absolute', 'abstract', 'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'external',
    'file', 'finalization', 'finally', 'for', 'forward', 'function', 'goto', 'helper', 'if', 'implementation',
    'in', 'inherited', 'initialization', 'inline', 'interface', 'is', 'label', 'library', 'message', 'mod',
    'nil', 'not', 'object', 'of', 'on', 'operator', 'or', 'out', 'overload', 'override', 'package', 'packed',
    'private', 'procedure', 'program', 'property', 'protected', 'public', 'published', 'raise', 'read',
    'record', 'reintroduce', 'repeat', 'resourcestring', 'sealed', 'set', 'shl', 'shr', 'static', 'strict',
    'then', 'threadvar', 'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'virtual', 'while', 'with',
    'write', 'xor', 'true', 'false', 'self', 'result', 'string', 'integer', 'boolean', 'default', 'index',
    'stdcall', 'cdecl', 'register', 'safecall', 'varargs');

var
  GKeywords: TDictionary<string, Boolean>;

function IsKeyword(const AWord: string): Boolean;
begin
  Result := GKeywords.ContainsKey(LowerCase(AWord));
end;

function ExpandTabs(const AText: string): string;
begin
  Result := AText.Replace(#9, StringOfChar(' ', TabWidth));
end;

function IsWordStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (C > #127);
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := IsWordStart(C) or CharInSet(C, ['0'..'9']);
end;

procedure AddSpan(AList: TList<TSynSpan>; AStart, ALen: Integer; AKind: TSynKind);
var
  S: TSynSpan;
begin
  if ALen <= 0 then
    Exit;
  S.Start := AStart;
  S.Len := ALen;
  S.Kind := AKind;
  AList.Add(S);
end;

type
  TBlock = (bkNone, bkBrace, bkParenStar);

// marca uma linha; ABlock e o comentario de varias linhas que vem da linha anterior (e sai para a seguinte)
function ScanLine(const AText: string; var ABlock: TBlock): TArray<TSynSpan>;
var
  Spans: TList<TSynSpan>;
  I, N, Start: Integer;
  C: Char;

  // ABlock <> bkNone: procura o fim do comentario; I fica depois dele
  procedure CloseBlock;
  begin
    while I <= N do
    begin
      if (ABlock = bkBrace) and (AText[I] = '}') then
      begin
        Inc(I);
        ABlock := bkNone;
        Break;
      end;
      if (ABlock = bkParenStar) and (AText[I] = '*') and (I < N) and (AText[I + 1] = ')') then
      begin
        Inc(I, 2);
        ABlock := bkNone;
        Break;
      end;
      Inc(I);
    end;
  end;

  procedure ScanString;
  begin
    Inc(I);
    while I <= N do
    begin
      if AText[I] = '''' then
      begin
        if (I < N) and (AText[I + 1] = '''') then
          Inc(I, 2)               // '' dentro de um texto
        else
        begin
          Inc(I);
          Break;
        end;
      end
      else
        Inc(I);
    end;
  end;

  procedure ScanNumber;
  begin
    if AText[I] = '$' then
    begin
      Inc(I);
      while (I <= N) and CharInSet(AText[I], ['0'..'9', 'a'..'f', 'A'..'F']) do
        Inc(I);
      Exit;
    end;
    while (I <= N) and CharInSet(AText[I], ['0'..'9', '_']) do
      Inc(I);
    // parte decimal: '1.5' mas nao '1..5'
    if (I < N) and (AText[I] = '.') and CharInSet(AText[I + 1], ['0'..'9']) then
    begin
      Inc(I);
      while (I <= N) and CharInSet(AText[I], ['0'..'9']) do
        Inc(I);
    end;
    // expoente: '1e10', '1.5E-3'
    if (I < N) and CharInSet(AText[I], ['e', 'E']) then
    begin
      if CharInSet(AText[I + 1], ['0'..'9']) then
        Inc(I)
      else if CharInSet(AText[I + 1], ['+', '-']) and (I + 1 < N) and CharInSet(AText[I + 2], ['0'..'9']) then
        Inc(I, 2)
      else
        Exit;
      while (I <= N) and CharInSet(AText[I], ['0'..'9']) do
        Inc(I);
    end;
  end;

begin
  Spans := TList<TSynSpan>.Create;
  try
    N := Length(AText);
    I := 1;
    while I <= N do
    begin
      if ABlock <> bkNone then
      begin
        Start := I;
        CloseBlock;
        AddSpan(Spans, Start, I - Start, skComment);
        Continue;
      end;
      C := AText[I];
      Start := I;
      if C = '{' then
      begin
        if (I < N) and (AText[I + 1] = '$') then
        begin
          // directiva de compilacao: {$IFDEF X}
          while (I <= N) and (AText[I] <> '}') do
            Inc(I);
          if I <= N then
            Inc(I);
          AddSpan(Spans, Start, I - Start, skDirective);
        end
        else
        begin
          ABlock := bkBrace;
          Inc(I);
          CloseBlock;
          AddSpan(Spans, Start, I - Start, skComment);
        end;
      end
      else if (C = '(') and (I < N) and (AText[I + 1] = '*') then
      begin
        ABlock := bkParenStar;
        Inc(I, 2);
        CloseBlock;
        AddSpan(Spans, Start, I - Start, skComment);
      end
      else if (C = '/') and (I < N) and (AText[I + 1] = '/') then
      begin
        AddSpan(Spans, I, N - I + 1, skComment);
        I := N + 1;
      end
      else if C = '''' then
      begin
        ScanString;
        AddSpan(Spans, Start, I - Start, skString);
      end
      else if (C = '#') and (I < N) and CharInSet(AText[I + 1], ['0'..'9', '$']) then
      begin
        Inc(I);
        while (I <= N) and CharInSet(AText[I], ['0'..'9', 'a'..'f', 'A'..'F', '$']) do
          Inc(I);
        AddSpan(Spans, Start, I - Start, skString);
      end
      else if CharInSet(C, ['0'..'9']) or
              ((C = '$') and (I < N) and CharInSet(AText[I + 1], ['0'..'9', 'a'..'f', 'A'..'F'])) then
      begin
        ScanNumber;
        AddSpan(Spans, Start, I - Start, skNumber);
      end
      else if IsWordStart(C) then
      begin
        while (I <= N) and IsWordChar(AText[I]) do
          Inc(I);
        // depois de um ponto e um membro ('Obj.End' nao e uma palavra reservada)
        if IsKeyword(Copy(AText, Start, I - Start)) and not ((Start > 1) and (AText[Start - 1] = '.')) then
          AddSpan(Spans, Start, I - Start, skKeyword);
      end
      else
        Inc(I);
    end;
    Result := Spans.ToArray;
  finally
    Spans.Free;
  end;
end;

{ TCodeDoc }

constructor TCodeDoc.Create(const AText: string);
var
  Raw: TArray<string>;
  I: Integer;
  Block: TBlock;
begin
  inherited Create;
  Raw := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if Length(Raw) = 0 then
    Raw := [''];                  // o Split de um texto vazio nao devolve nada
  // um texto que acaba em mudanca de linha nao tem uma linha vazia a mais
  if (Length(Raw) > 1) and (Raw[High(Raw)] = '') then
    SetLength(Raw, Length(Raw) - 1);
  SetLength(FLines, Length(Raw));
  Block := bkNone;
  for I := 0 to High(Raw) do
  begin
    FLines[I].Text := ExpandTabs(Raw[I]);
    FLines[I].Spans := ScanLine(FLines[I].Text, Block);
  end;
end;

function TCodeDoc.Count: Integer;
begin
  Result := Length(FLines);
end;

function TCodeDoc.Line(AIndex: Integer): TCodeLine;
begin
  Result := FLines[AIndex];
end;

function TCodeDoc.LongestLine: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FLines) do
    if Length(FLines[I].Text) > Result then
      Result := Length(FLines[I].Text);
end;

{ procurar rotinas }

function IsRoutineWord(const AWord: string): Boolean;
begin
  Result := SameText(AWord, 'procedure') or SameText(AWord, 'function') or SameText(AWord, 'constructor') or
    SameText(AWord, 'destructor') or SameText(AWord, 'operator');
end;

// a linha comeca por 'procedure Owner.Simple' (ou 'procedure Simple' se AOwner = '')? Os comentarios nao contam
function LineDefines(const ALine: TCodeLine; const AOwner, ASimple: string): Boolean;
var
  Code, Rest, Name: string;
  I, J: Integer;
begin
  Result := False;
  Code := ALine.Text;
  for I := 0 to High(ALine.Spans) do
    if ALine.Spans[I].Kind = skComment then
      for J := ALine.Spans[I].Start to ALine.Spans[I].Start + ALine.Spans[I].Len - 1 do
        Code[J] := ' ';
  Code := Code.TrimLeft;
  // 'class function ...' e 'class procedure ...'
  if Code.StartsWith('class ', True) then
    Code := Copy(Code, 7, MaxInt).TrimLeft;
  I := 1;
  while (I <= Length(Code)) and IsWordChar(Code[I]) do
    Inc(I);
  if not IsRoutineWord(Copy(Code, 1, I - 1)) then
    Exit;
  Rest := Copy(Code, I, MaxInt).TrimLeft;
  J := 1;
  while (J <= Length(Rest)) and (IsWordChar(Rest[J]) or (Rest[J] = '.')) do
    Inc(J);
  Name := Copy(Rest, 1, J - 1);
  if AOwner <> '' then
    Result := SameText(Name, AOwner + '.' + ASimple) or Name.EndsWith('.' + AOwner + '.' + ASimple, True)
  else
    Result := SameText(Name, ASimple);
end;

function FindRoutineLine(ADoc: TCodeDoc; const AOwner, ASimple: string): Integer;
var
  I, Last: Integer;
begin
  Result := -1;
  if (ADoc = nil) or (ASimple = '') then
    Exit;
  if AOwner <> '' then
  begin
    // 'procedure TFoo.Bar' so aparece na implementation
    for I := 0 to ADoc.Count - 1 do
      if LineDefines(ADoc.Line(I), AOwner, ASimple) then
        Exit(I);
    // so ha a declaracao dentro da classe ('procedure Bar;' ao nivel do tipo)
    for I := 0 to ADoc.Count - 1 do
      if LineDefines(ADoc.Line(I), '', ASimple) then
        Exit(I);
    Exit;
  end;
  // rotina livre: a ultima ocorrencia e a definicao (a primeira pode ser a declaracao na interface)
  Last := -1;
  for I := 0 to ADoc.Count - 1 do
    if LineDefines(ADoc.Line(I), '', ASimple) then
      Last := I;
  Result := Last;
end;

var
  K: string;

initialization
  GKeywords := TDictionary<string, Boolean>.Create;
  for K in Keywords do
    GKeywords.AddOrSetValue(K, True);

finalization
  GKeywords.Free;

end.
