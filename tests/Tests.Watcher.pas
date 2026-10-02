unit Tests.Watcher;

// Testes de CM.Watcher: TFolderWatcher a vigiar uma pasta temporaria. A thread so regista
// caminhos relativos (com '/'); os testes escrevem ficheiros e esperam (com limite) que apareçam
// em TakeChanges. O sinal para a thread principal usa TThread.Queue, por isso a espera chama
// CheckSynchronize (numa aplicacao de consola ninguem o faz).

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  DUnitX.TestFramework, CM.Watcher, Tests.Helpers;

type
  [TestFixture]
  TFolderWatcherTests = class
  private
    FDir: TTempDir;
    FWatcher: TFolderWatcher;
    FSignals: Integer;
    procedure OnSignal(Sender: TObject);
    // acumula TakeChanges ate ver ARel (ou esgotar o tempo); devolve tudo o que viu
    function WaitFor(const ARel: string; ATimeoutMs: Integer = 5000): TArray<string>;
    function Contains(const AList: TArray<string>; const AItem: string): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NewFileIsReported;
    [Test] procedure ChangeInSubfolderUsesForwardSlashes;
    [Test] procedure DeletedFileIsReported;
    [Test] procedure SignalIsRaisedOnTheMainThread;
    [Test] procedure TakeChangesForgetsWhatItReturned;
    [Test] procedure MissingFolderDoesNotRaiseNorReport;
    [Test] procedure FreeRightAfterCreateDoesNotHang;
  end;

implementation

procedure TFolderWatcherTests.Setup;
begin
  FDir := TTempDir.Create;
  FSignals := 0;
  FWatcher := TFolderWatcher.Create(FDir.Path, OnSignal);
  // a thread precisa de um instante para armar o ReadDirectoryChangesW
  Sleep(300);
end;

procedure TFolderWatcherTests.TearDown;
begin
  FWatcher.Free;
  FDir.Free;
end;

procedure TFolderWatcherTests.OnSignal(Sender: TObject);
begin
  Inc(FSignals);
end;

function TFolderWatcherTests.Contains(const AList: TArray<string>; const AItem: string): Boolean;
var
  S: string;
begin
  for S in AList do
    if SameText(S, AItem) then
      Exit(True);
  Result := False;
end;

function TFolderWatcherTests.WaitFor(const ARel: string; ATimeoutMs: Integer): TArray<string>;
var
  Seen: TList<string>;
  Got: TArray<string>;
  Overflow: Boolean;
  Waited: Integer;
begin
  Seen := TList<string>.Create;
  try
    Waited := 0;
    repeat
      CheckSynchronize;
      FWatcher.TakeChanges(Got, Overflow);
      Seen.AddRange(Got);
      if Contains(Seen.ToArray, ARel) then
        Break;
      Sleep(50);
      Inc(Waited, 50);
    until Waited >= ATimeoutMs;
    Result := Seen.ToArray;
  finally
    Seen.Free;
  end;
end;

procedure TFolderWatcherTests.NewFileIsReported;
begin
  FDir.Write('a.pas', 'unit a;');
  Assert.IsTrue(Contains(WaitFor('a.pas'), 'a.pas'));
end;

procedure TFolderWatcherTests.ChangeInSubfolderUsesForwardSlashes;
begin
  FDir.Write('Core/Sub/b.pas', 'unit b;');
  Assert.IsTrue(Contains(WaitFor('Core/Sub/b.pas'), 'Core/Sub/b.pas'));
end;

procedure TFolderWatcherTests.DeletedFileIsReported;
var
  Seen: TArray<string>;
begin
  FDir.Write('gone.pas', 'unit gone;');
  WaitFor('gone.pas');                       // consome a criacao
  Sleep(200);
  FDir.Delete('gone.pas');
  Seen := WaitFor('gone.pas');
  Assert.IsTrue(Contains(Seen, 'gone.pas'));
end;

procedure TFolderWatcherTests.SignalIsRaisedOnTheMainThread;
begin
  FDir.Write('s.pas', 'unit s;');
  WaitFor('s.pas');
  CheckSynchronize;
  Assert.IsTrue(FSignals >= 1, 'o OnSignal devia ter corrido pelo menos uma vez');
end;

procedure TFolderWatcherTests.TakeChangesForgetsWhatItReturned;
var
  Paths: TArray<string>;
  Overflow: Boolean;
begin
  FDir.Write('once.pas', 'unit once;');
  WaitFor('once.pas');
  Sleep(300);                                // deixa assentar eventos repetidos da mesma gravacao
  FWatcher.TakeChanges(Paths, Overflow);
  FWatcher.TakeChanges(Paths, Overflow);
  Assert.AreEqual(0, Integer(Length(Paths)), 'segunda chamada seguida nao devolve nada');
  Assert.IsFalse(Overflow);
end;

procedure TFolderWatcherTests.MissingFolderDoesNotRaiseNorReport;
var
  W: TFolderWatcher;
  Paths: TArray<string>;
  Overflow: Boolean;
begin
  W := TFolderWatcher.Create(FDir.Full('nao-existe'), nil);
  try
    Sleep(200);
    W.TakeChanges(Paths, Overflow);
    Assert.AreEqual(0, Integer(Length(Paths)));
    Assert.IsFalse(Overflow);
  finally
    W.Free;
  end;
end;

procedure TFolderWatcherTests.FreeRightAfterCreateDoesNotHang;
var
  W: TFolderWatcher;
begin
  W := TFolderWatcher.Create(FDir.Path, nil);
  W.Free;                                    // se bloquear, o DUnitX nunca termina
  Assert.Pass;
end;

end.
