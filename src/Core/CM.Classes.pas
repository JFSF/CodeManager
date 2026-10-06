unit CM.Classes;

{ As declaracoes de tipos de uma unit: classes, interfaces, records e objects antigos, com o ancestral e as interfaces que
  declaram. Le o texto "limpo" do analisador (comentarios retirados, textos entre apostrofos reduzidos a '').

  O ancestral de uma classe e o primeiro nome entre parenteses, a nao ser que seja uma interface ('TFoo = class(IBar)'
  herda de TObject e implementa IBar); os restantes sao interfaces. Os genericos perdem os argumentos ('TFoo<T>' e 'TFoo').
  Nao conta: declaracoes antecipadas ('TFoo = class;'), tipos de classe ('class of'), 'class helper for' e 'record helper for'. }

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  TClassKind = (ckClass, ckInterface, ckRecord, ckObject);

  TClassInfo = record
    Name: string;                  // sem os argumentos de generico
    Kind: TClassKind;
    Ancestor: string;              // o que a declaracao diz ('' = nada: herda de TObject / IInterface)
    Interfaces: TArray<string>;    // as interfaces que uma classe implementa
    Line: Integer;                 // linha da declaracao no texto limpo (a partir de 1)
  end;

function ClassKindName(AKind: TClassKind): string;
// as classes, interfaces, records e objects declarados em ACleanText, pela ordem em que aparecem
function ExtractClasses(const ACleanText: string): TArray<TClassInfo>;
// True se os dois conjuntos de declaracoes sao iguais
function SameClasses(const A, B: TArray<TClassInfo>): Boolean;

implementation

uses
  System.RegularExpressions;

var
  GHead: TRegEx;

function ClassKindName(AKind: TClassKind): string;
begin
  case AKind of
    ckClass: Result := 'class';
    ckInterface: Result := 'interface';
    ckRecord: Result := 'record';
  else
    Result := 'object';
  end;
end;

// 'TFoo<T>', 'Spring.TFoo<T, U>' -> 'TFoo' / 'Spring.TFoo' (so o nome, sem argumentos nem espacos)
function BaseName(const AText: string): string;
var
  P: Integer;
begin
  Result := Trim(AText);
  P := Pos('<', Result);
  if P > 0 then
    Result := Trim(Copy(Result, 1, P - 1));
end;

// parte "A, B<C, D>, E" pelas virgulas de topo
function SplitTop(const AText: string): TArray<string>;
var
  List: TList<string>;
  Depth, I, Start: Integer;
  C: Char;
  Part: string;
begin
  List := TList<string>.Create;
  try
    Depth := 0;
    Start := 1;
    for I := 1 to Length(AText) do
    begin
      C := AText[I];
      if C = '<' then
        Inc(Depth)
      else if C = '>' then
        Dec(Depth)
      else if (C = ',') and (Depth = 0) then
      begin
        Part := BaseName(Copy(AText, Start, I - Start));
        if Part <> '' then
          List.Add(Part);
        Start := I + 1;
      end;
    end;
    Part := BaseName(Copy(AText, Start, MaxInt));
    if Part <> '' then
      List.Add(Part);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

// 'IFoo', 'IInterface', 'IUnknown': nomes de interface (I seguido de maiuscula)
function LooksLikeInterface(const AName: string): Boolean;
var
  N: string;
  P: Integer;
begin
  N := AName;
  P := LastDelimiter('.', N);
  if P > 0 then
    N := Copy(N, P + 1, MaxInt);
  Result := (Length(N) >= 2) and (N[1] = 'I') and (N[2] >= 'A') and (N[2] <= 'Z');
end;

function ExtractClasses(const ACleanText: string): TArray<TClassInfo>;
var
  List: TList<TClassInfo>;
  M: TMatch;
  Info: TClassInfo;
  Kind, Rest: string;
  I, N, Close: Integer;
  Items: TArray<string>;
  Depth: Integer;
  HasParens: Boolean;
  Line, Last: Integer;

  function SkipSpaces(AFrom: Integer): Integer;
  begin
    Result := AFrom;
    while (Result <= N) and (ACleanText[Result] <= ' ') do
      Inc(Result);
  end;

  function NextWord(AFrom: Integer; out AEnd: Integer): string;
  begin
    AEnd := AFrom;
    while (AEnd <= N) and CharInSet(ACleanText[AEnd], ['A'..'Z', 'a'..'z', '_', '0'..'9']) do
      Inc(AEnd);
    Result := LowerCase(Copy(ACleanText, AFrom, AEnd - AFrom));
  end;

var
  W: string;
  WEnd: Integer;
begin
  List := TList<TClassInfo>.Create;
  try
    N := Length(ACleanText);
    Line := 1;
    Last := 1;
    for M in GHead.Matches(ACleanText) do
    begin
      Info := Default(TClassInfo);
      Info.Name := BaseName(M.Groups[1].Value);
      Kind := LowerCase(M.Groups[2].Value);
      if Kind = 'class' then
        Info.Kind := ckClass
      else if Kind = 'record' then
        Info.Kind := ckRecord
      else if Kind = 'object' then
        Info.Kind := ckObject
      else
        Info.Kind := ckInterface;

      // a linha: conta as mudancas de linha desde a ultima declaracao
      for I := Last to M.Index - 1 do
        if ACleanText[I] = #10 then
          Inc(Line);
      Last := M.Index;
      Info.Line := Line;

      I := SkipSpaces(M.Index + M.Length);
      // sealed / abstract e 'helper for' (que nao e um tipo novo)
      repeat
        W := NextWord(I, WEnd);
        if (W = 'sealed') or (W = 'abstract') then
          I := SkipSpaces(WEnd)
        else
          Break;
      until False;
      if (W = 'helper') and (Info.Kind in [ckClass, ckRecord]) then
        Continue;
      HasParens := (I <= N) and (ACleanText[I] = '(');
      Items := nil;
      if HasParens then
      begin
        Depth := 0;
        Close := I;
        while Close <= N do
        begin
          if ACleanText[Close] = '(' then
            Inc(Depth)
          else if ACleanText[Close] = ')' then
          begin
            Dec(Depth);
            if Depth = 0 then
              Break;
          end;
          Inc(Close);
        end;
        Rest := Copy(ACleanText, I + 1, Close - I - 1);
        Items := SplitTop(Rest);
        I := SkipSpaces(Close + 1);
      end;
      // 'TFoo = class;' e 'IFoo = interface;' sao declaracoes antecipadas
      if (not HasParens) and (I <= N) and (ACleanText[I] = ';') then
        Continue;

      case Info.Kind of
        ckClass, ckObject:
          begin
            if Length(Items) > 0 then
            begin
              if (Info.Kind = ckClass) and LooksLikeInterface(Items[0]) then
                Info.Interfaces := Items
              else
              begin
                Info.Ancestor := Items[0];
                Info.Interfaces := Copy(Items, 1, MaxInt);
              end;
            end;
          end;
        ckInterface:
          if Length(Items) > 0 then
            Info.Ancestor := Items[0];
      end;
      List.Add(Info);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function SameClasses(const A, B: TArray<TClassInfo>): Boolean;
var
  I, J: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
  begin
    if (A[I].Name <> B[I].Name) or (A[I].Kind <> B[I].Kind) or (A[I].Ancestor <> B[I].Ancestor) or
       (A[I].Line <> B[I].Line) or (Length(A[I].Interfaces) <> Length(B[I].Interfaces)) then
      Exit(False);
    for J := 0 to High(A[I].Interfaces) do
      if A[I].Interfaces[J] <> B[I].Interfaces[J] then
        Exit(False);
  end;
  Result := True;
end;

initialization
  // TFoo[<T>] = [packed] class|record|object|interface|dispinterface  (nao 'class of')
  GHead := TRegEx.Create(
    '\b([A-Za-z_][A-Za-z0-9_]*(?:\s*<[^=;<>]*(?:<[^=;<>]*>[^=;<>]*)*>)?)\s*=\s*(?:packed\s+)?' +
    '(class|record|object|interface|dispinterface)\b(?!\s+of\b)', [roIgnoreCase]);
end.
