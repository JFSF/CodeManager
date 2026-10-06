unit CM.WidthShare;

{ Reparte a largura de uma linha de botoes. Por omissao a largura e dividida por igual; mas um botao cujo texto nao
  cabe na sua parte (os idiomas mais compridos, como o alemao) fica com a largura que o texto pede e os outros
  repartem o que sobra. Pura (sem FMX), por isso testa-se sozinha. }

interface

// AAvail: a largura disponivel (ja sem os intervalos entre botoes). ANatural[i]: a largura que o botao i pede, ou 0
// se se contenta com uma parte igual (por exemplo, os botoes so com icone). O resultado soma sempre AAvail.
function ShareWidths(AAvail: Single; const ANatural: TArray<Single>): TArray<Single>;

implementation

function ShareWidths(AAvail: Single; const ANatural: TArray<Single>): TArray<Single>;
var
  N, I, Others: Integer;
  Long: TArray<Boolean>;
  SumLong, Share: Single;
  Changed: Boolean;
begin
  N := Length(ANatural);
  SetLength(Result, N);
  if N = 0 then
    Exit;
  SetLength(Long, N);
  // os botoes que nao cabem numa parte igual passam a "longos"; isso encolhe a parte dos outros, que por sua vez
  // podem deixar de caber: repete-se ate estabilizar
  repeat
    Changed := False;
    SumLong := 0;
    Others := 0;
    for I := 0 to N - 1 do
      if Long[I] then
        SumLong := SumLong + ANatural[I]
      else
        Inc(Others);
    if Others > 0 then
      Share := (AAvail - SumLong) / Others
    else
      Share := 0;
    for I := 0 to N - 1 do
      if (not Long[I]) and (ANatural[I] > Share) then
      begin
        Long[I] := True;
        Changed := True;
      end;
  until not Changed;
  if (SumLong > AAvail) or (Others = 0) then
  begin
    // nem assim cabem (se todos pedem mais do que a sua parte, a soma passa sempre o total): divisao por igual
    for I := 0 to N - 1 do
      Result[I] := AAvail / N;
    Exit;
  end;
  for I := 0 to N - 1 do
    if Long[I] then
      Result[I] := ANatural[I]
    else
      Result[I] := Share;
end;

end.
