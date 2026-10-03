unit CM.Metrics;

{ Medidas dos corpos das rotinas de uma unit: linhas de codigo e complexidade ciclomatica.

  Trabalha sobre o texto ja "limpo" pelo analisador (comentarios retirados, textos entre apostrofos
  reduzidos a '', mas com as mudancas de linha preservadas) e so olha para a secao implementation.
  Percorre os simbolos, sem compilar nada, por isso e tolerante: o que nao percebe, ignora.

  Linhas: as linhas com codigo entre o inicio do cabecalho e o fim do corpo (inclui rotinas
  aninhadas e a zona de declaracoes locais; nao conta linhas em branco nem de comentarios).

  Complexidade: 1 + decisoes do proprio corpo (sem as rotinas aninhadas): if, while, for, repeat,
  case, "on" dos handlers de excepcao, and e or. Os metodos anonimos contam para quem os contem. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;

type
  TRoutineMetric = record
    Header: string;        // do inicio do cabecalho ('procedure TFoo.Bar(A: Integer)') ate ao ';'
    Lines: Integer;
    Complexity: Integer;
  end;

  // 1..10 simples, 11..20 moderada, acima disso alta (os limites habituais de McCabe)
  TComplexityLevel = (cxNone, cxLow, cxModerate, cxHigh);

function ComplexityLevel(AComplexity: Integer): TComplexityLevel;
// 'N linhas · complexidade M' (vazio sem corpo medido)
function MetricsText(ALines, AComplexity: Integer): string;
// mede as rotinas com corpo de ACleanImpl (texto limpo da secao implementation)
procedure MeasureRoutines(const ACleanImpl: string; AResult: TList<TRoutineMetric>);

implementation


uses
  CM.Lang;
type
  TToken = record
    Text: string;          // minusculas; '' para um texto entre apostrofos
    Pos: Integer;          // posicao do primeiro carcter no texto
    Line: Integer;         // linha (a partir de 0)
    IsWord: Boolean;
  end;

  // uma rotina em analise: o corpo comeca em 'begin' ou 'asm'
  TRoutine = class
  public
    Header: string;
    StartPos: Integer;       // posicao do inicio do cabecalho no texto
    InBody: Boolean;
    Depth: Integer;
    Complexity: Integer;
    constructor Create;
  end;

function ComplexityLevel(AComplexity: Integer): TComplexityLevel;
begin
  if AComplexity <= 0 then
    Result := cxNone
  else if AComplexity <= 10 then
    Result := cxLow
  else if AComplexity <= 20 then
    Result := cxModerate
  else
    Result := cxHigh;
end;

function MetricsText(ALines, AComplexity: Integer): string;
begin
  if ALines <= 0 then
    Result := ''
  else if ALines = 1 then
    Result := Format(Tr('1 linha · complexidade %d'), [AComplexity])
  else
    Result := Format(Tr('%d linhas · complexidade %d'), [ALines, AComplexity]);
end;

constructor TRoutine.Create;
begin
  inherited;
  Complexity := 1;
end;

function IsWordStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']);
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_', '0'..'9']);
end;

procedure Tokenize(const AText: string; ATokens: TList<TToken>);
var
  I, N, Line: Integer;
  T: TToken;
begin
  N := Length(AText);
  I := 1;
  Line := 0;
  while I <= N do
  begin
    if AText[I] = #10 then
    begin
      Inc(Line);
      Inc(I);
    end
    else if AText[I] <= ' ' then
      Inc(I)
    else if IsWordStart(AText[I]) then
    begin
      T.Pos := I;
      T.Line := Line;
      T.IsWord := True;
      while (I <= N) and IsWordChar(AText[I]) do
        Inc(I);
      T.Text := LowerCase(Copy(AText, T.Pos, I - T.Pos));
      ATokens.Add(T);
    end
    else if AText[I] = '''' then
    begin
      // o analisador reduz os textos a '' e nunca os deixa atravessar linhas
      T.Pos := I;
      T.Line := Line;
      T.IsWord := False;
      T.Text := '';
      Inc(I);
      while (I <= N) and (AText[I] <> '''') and (AText[I] <> #10) do
        Inc(I);
      if (I <= N) and (AText[I] = '''') then
        Inc(I);
      ATokens.Add(T);
    end
    else
    begin
      T.Pos := I;
      T.Line := Line;
      T.IsWord := False;
      T.Text := AText[I];
      Inc(I);
      ATokens.Add(T);
    end;
  end;
end;

function IsRoutineKeyword(const AText: string): Boolean;
begin
  Result := (AText = 'procedure') or (AText = 'function') or (AText = 'constructor') or
    (AText = 'destructor');
end;

function IsDirective(const AText: string): Boolean;
const
  Directives: array[0..20] of string = ('overload', 'inline', 'stdcall', 'cdecl', 'register',
    'pascal', 'safecall', 'forward', 'external', 'assembler', 'deprecated', 'platform',
    'reintroduce', 'virtual', 'override', 'abstract', 'final', 'static', 'dynamic', 'message',
    'experimental');
var
  D: string;
begin
  for D in Directives do
    if AText = D then
      Exit(True);
  Result := False;
end;

// linhas com codigo entre duas linhas (inclusive)
function CodeLines(const AText: string; AFromPos, AToPos: Integer): Integer;
var
  I: Integer;
  HasCode: Boolean;
begin
  Result := 0;
  HasCode := False;
  for I := AFromPos to AToPos do
    if AText[I] = #10 then
    begin
      if HasCode then
        Inc(Result);
      HasCode := False;
    end
    else if AText[I] > ' ' then
      HasCode := True;
  if HasCode then
    Inc(Result);
end;

// "on E: Exception do" / "on Exception do": um handler de excepcao (e nao um identificador qualquer)
function IsExceptionHandler(ATokens: TList<TToken>; AIndex: Integer): Boolean;
var
  J: Integer;
begin
  Result := False;
  for J := AIndex + 1 to Min(AIndex + 8, ATokens.Count - 1) do
  begin
    if ATokens[J].Text = 'do' then
      Exit(True);
    if (ATokens[J].Text = ';') or (ATokens[J].Text = 'begin') then
      Exit(False);
  end;
end;

procedure MeasureRoutines(const ACleanImpl: string; AResult: TList<TRoutineMetric>);
var
  Tokens: TList<TToken>;
  Stack: TObjectList<TRoutine>;
  I, J, Paren, TypeDepth: Integer;
  T: TToken;
  R: TRoutine;
  Metric: TRoutineMetric;
  HeaderEnd: Integer;
  IsForward: Boolean;

  function Top: TRoutine;
  begin
    if Stack.Count > 0 then
      Result := Stack.Last
    else
      Result := nil;
  end;

  // 'procedure Nome' (com nome): um cabecalho, e nao um tipo procedimental nem um metodo anonimo
  function StartsHeader(AIndex: Integer): Boolean;
  begin
    Result := IsRoutineKeyword(Tokens[AIndex].Text) and (AIndex + 1 < Tokens.Count) and
      Tokens[AIndex + 1].IsWord and
      (Tokens[AIndex + 1].Text <> 'of') and (Tokens[AIndex + 1].Text <> 'to');
  end;

  // '= class|record|object|interface' que abre um tipo com corpo ('= class;' e '= class of' nao)
  function OpensType(AIndex: Integer): Boolean;
  var
    K: Integer;
    W: string;
  begin
    Result := False;
    if Tokens[AIndex].Text <> '=' then
      Exit;
    K := AIndex + 1;
    while (K < Tokens.Count) and ((Tokens[K].Text = 'packed')) do
      Inc(K);
    if K >= Tokens.Count then
      Exit;
    W := Tokens[K].Text;
    if not ((W = 'class') or (W = 'record') or (W = 'object') or (W = 'interface') or
            (W = 'dispinterface')) then
      Exit;
    Inc(K);
    if K >= Tokens.Count then
      Exit;
    if Tokens[K].Text = 'of' then
      Exit;                                  // 'class of TFoo'
    if Tokens[K].Text = ';' then
      Exit;                                  // declaracao antecipada
    if Tokens[K].Text = '(' then
    begin
      // '= class(TBar);' tambem e antecipada
      while (K < Tokens.Count) and (Tokens[K].Text <> ')') do
        Inc(K);
      Inc(K);
      if (K < Tokens.Count) and (Tokens[K].Text = ';') then
        Exit;
    end;
    Result := True;
  end;

begin
  Tokens := TList<TToken>.Create;
  Stack := TObjectList<TRoutine>.Create(True);
  try
    Tokenize(ACleanImpl, Tokens);
    TypeDepth := 0;
    I := 0;
    while I < Tokens.Count do
    begin
      T := Tokens[I];
      R := Top;

      if (R <> nil) and R.InBody then
      begin
        // dentro de um corpo: so conta decisoes e acompanha begin/end
        if (T.Text = 'begin') or (T.Text = 'try') or (T.Text = 'case') or (T.Text = 'asm') then
          Inc(R.Depth);
        if (T.Text = 'if') or (T.Text = 'while') or (T.Text = 'for') or (T.Text = 'repeat') or
           (T.Text = 'case') or (T.Text = 'and') or (T.Text = 'or') then
          Inc(R.Complexity)
        else if (T.Text = 'on') and IsExceptionHandler(Tokens, I) then
          Inc(R.Complexity);
        if T.Text = 'end' then
        begin
          Dec(R.Depth);
          if R.Depth <= 0 then
          begin
            Metric.Header := R.Header;
            Metric.Lines := CodeLines(ACleanImpl, R.StartPos, T.Pos + 2);
            Metric.Complexity := R.Complexity;
            AResult.Add(Metric);
            Stack.Delete(Stack.Count - 1);
          end;
        end;
        Inc(I);
        Continue;
      end;

      // fora de corpos (ou nas declaracoes locais de uma rotina): tipos, cabecalhos e o 'begin'
      if TypeDepth > 0 then
      begin
        if OpensType(I) then
          Inc(TypeDepth)
        else if T.Text = 'end' then
          Dec(TypeDepth);
      end
      else if OpensType(I) then
        Inc(TypeDepth)
      else if StartsHeader(I) then
      begin
        // le o cabecalho ate ao ';' fora de parenteses
        Paren := 0;
        J := I + 1;
        while J < Tokens.Count do
        begin
          if Tokens[J].Text = '(' then
            Inc(Paren)
          else if Tokens[J].Text = ')' then
            Dec(Paren)
          else if (Tokens[J].Text = ';') and (Paren <= 0) then
            Break;
          Inc(J);
        end;
        if J >= Tokens.Count then
          Break;
        HeaderEnd := J;
        // directivas ('overload;', 'inline;'...); 'forward' e 'external' dispensam corpo
        IsForward := False;
        while (J + 1 < Tokens.Count) and Tokens[J + 1].IsWord and IsDirective(Tokens[J + 1].Text) do
        begin
          if (Tokens[J + 1].Text = 'forward') or (Tokens[J + 1].Text = 'external') then
            IsForward := True;
          Inc(J);
          while (J < Tokens.Count) and (Tokens[J].Text <> ';') do
            Inc(J);
        end;
        if not IsForward then
        begin
          R := TRoutine.Create;
          R.Header := Trim(Copy(ACleanImpl, T.Pos, Tokens[HeaderEnd].Pos - T.Pos));
          R.StartPos := T.Pos;
          Stack.Add(R);
        end;
        I := J;                                // continua depois do ultimo ';' do cabecalho
      end
      else if (R <> nil) and ((T.Text = 'begin') or (T.Text = 'asm')) then
      begin
        R.InBody := True;
        R.Depth := 1;
      end;
      Inc(I);
    end;
  finally
    Stack.Free;
    Tokens.Free;
  end;
end;

end.
