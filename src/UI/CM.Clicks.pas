unit CM.Clicks;

{ Deteccao de duplo clique para os controlos desenhados a mao: dois cliques no mesmo alvo dentro do tempo de
  duplo clique do Windows. Fica numa unit propria porque Winapi.Windows tem nomes (DrawIcon...) que chocam
  com os do tema. }

interface

type
  TDoubleClickTracker = record
  private
    FKey: string;
    FTick: UInt64;
  public
    // regista um clique em AKey; True se for o segundo clique (e o duplo clique fica gasto: o proximo recomeca)
    function Click(const AKey: string): Boolean;
    procedure Reset;
  end;

// milissegundos desde o arranque do Windows (so serve para comparar cliques)
function TickMs: UInt64;
function DoubleClickMs: Integer;

implementation

uses
  Winapi.Windows;

function TickMs: UInt64;
begin
  Result := GetTickCount64;
end;

function DoubleClickMs: Integer;
begin
  Result := GetDoubleClickTime;
end;

function TDoubleClickTracker.Click(const AKey: string): Boolean;
var
  Now: UInt64;
begin
  Now := TickMs;
  Result := (AKey <> '') and (AKey = FKey) and (Now - FTick <= UInt64(DoubleClickMs));
  if Result then
    Reset
  else
  begin
    FKey := AKey;
    FTick := Now;
  end;
end;

procedure TDoubleClickTracker.Reset;
begin
  FKey := '';
  FTick := 0;
end;

end.
