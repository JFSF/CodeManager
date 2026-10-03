unit Tests.SafeFile;

// Testes de CM.SafeFile e da sua utilizacao pelas definicoes, pelo progresso e pelo historico:
// gravacao atomica com copia .bak, recuperacao de ficheiros danificados e limpeza ao apagar.

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, DUnitX.TestFramework, CM.SafeFile, CM.Store,
  CM.History, Tests.Helpers;

type
  [TestFixture]
  TWriteFileAtomicTests = class
  private
    FDir: TTempDir;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CreatesTheFile;
    [Test] procedure CreatesMissingFolders;
    [Test] procedure KeepsThePreviousVersionAsBak;
    [Test] procedure OnlyTheLastPreviousVersionIsKept;
    [Test] procedure LeavesNoTempFileBehind;
    [Test] procedure KeepsTheRequestedEncoding;
  end;

  [TestFixture]
  TReadJsonFileTests = class
  private
    FDir: TTempDir;
    FFile: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ValidFileIsReturnedWithoutRecovery;
    [Test] procedure CorruptFileFallsBackToTheBackup;
    [Test] procedure RecoveryRestoresTheMainFileAndKeepsTheCorruptOne;
    [Test] procedure EmptyFileCountsAsCorrupt;
    [Test] procedure JsonThatIsNotAnObjectCountsAsCorrupt;
    [Test] procedure MissingMainFileUsesTheBackup;
    [Test] procedure CorruptFileWithoutBackupRaisesAndIsKept;
    [Test] procedure CorruptBackupToo;
    [Test] procedure MissingEverythingRaisesNotFound;
    [Test] procedure DataFileExistsAlsoSeesTheBackup;
    [Test] procedure DeleteDataFileRemovesEveryCopy;
  end;

  [TestFixture]
  TStoredFilesTests = class
  private
    FIso: TIsolatedAppData;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ProgressSavesWithBackupAndRecovers;
    [Test] procedure ProgressImportStaysStrict;
    [Test] procedure HistorySavesWithBackupAndRecovers;
    [Test] procedure SettingsSaveWithBackupAndRecover;
    [Test] procedure SettingsWithBothFilesCorruptRaise;
    [Test] procedure CodeFontAndLigaturesRoundTrip;
    [Test] procedure CodeLigaturesAreOnByDefault;
  end;

implementation

function ReadText(const AFileName: string): string;
begin
  Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
end;

{ TWriteFileAtomicTests }

procedure TWriteFileAtomicTests.Setup;
begin
  FDir := TTempDir.Create;
end;

procedure TWriteFileAtomicTests.TearDown;
begin
  FDir.Free;
end;

procedure TWriteFileAtomicTests.CreatesTheFile;
begin
  WriteFileAtomic(FDir.Full('a.json'), '{"a":1}', TEncoding.UTF8);
  Assert.AreEqual('{"a":1}', ReadText(FDir.Full('a.json')));
  Assert.IsFalse(TFile.Exists(FDir.Full('a.json.bak')), 'sem versao anterior nao ha copia');
end;

procedure TWriteFileAtomicTests.CreatesMissingFolders;
begin
  WriteFileAtomic(FDir.Full('x/y/a.json'), '{}', TEncoding.UTF8);
  Assert.IsTrue(TFile.Exists(FDir.Full('x/y/a.json')));
end;

procedure TWriteFileAtomicTests.KeepsThePreviousVersionAsBak;
begin
  WriteFileAtomic(FDir.Full('a.json'), '{"v":1}', TEncoding.UTF8);
  WriteFileAtomic(FDir.Full('a.json'), '{"v":2}', TEncoding.UTF8);
  Assert.AreEqual('{"v":2}', ReadText(FDir.Full('a.json')));
  Assert.AreEqual('{"v":1}', ReadText(FDir.Full('a.json.bak')));
end;

procedure TWriteFileAtomicTests.OnlyTheLastPreviousVersionIsKept;
begin
  WriteFileAtomic(FDir.Full('a.json'), '{"v":1}', TEncoding.UTF8);
  WriteFileAtomic(FDir.Full('a.json'), '{"v":2}', TEncoding.UTF8);
  WriteFileAtomic(FDir.Full('a.json'), '{"v":3}', TEncoding.UTF8);
  Assert.AreEqual('{"v":3}', ReadText(FDir.Full('a.json')));
  Assert.AreEqual('{"v":2}', ReadText(FDir.Full('a.json.bak')));
end;

procedure TWriteFileAtomicTests.LeavesNoTempFileBehind;
begin
  WriteFileAtomic(FDir.Full('a.json'), '{}', TEncoding.UTF8);
  WriteFileAtomic(FDir.Full('a.json'), '{"x":1}', TEncoding.UTF8);
  Assert.IsFalse(TFile.Exists(FDir.Full('a.json.tmp')));
end;

procedure TWriteFileAtomicTests.KeepsTheRequestedEncoding;
var
  Bytes: TBytes;
begin
  WriteFileAtomic(FDir.Full('bom.json'), '{}', TEncoding.UTF8);
  Bytes := TFile.ReadAllBytes(FDir.Full('bom.json'));
  Assert.IsTrue((Length(Bytes) > 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF), 'com BOM');
  WriteFileAtomic(FDir.Full('nobom.json'), '{}', TUTF8Encoding.Create(False));
  Bytes := TFile.ReadAllBytes(FDir.Full('nobom.json'));
  Assert.AreEqual(2, Integer(Length(Bytes)), 'sem BOM');
end;

{ TReadJsonFileTests }

procedure TReadJsonFileTests.Setup;
begin
  FDir := TTempDir.Create;
  FFile := FDir.Full('d.json');
end;

procedure TReadJsonFileTests.TearDown;
begin
  FDir.Free;
end;

procedure TReadJsonFileTests.ValidFileIsReturnedWithoutRecovery;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '{"ok":true}');
  Assert.AreEqual('{"ok":true}', ReadJsonFile(FFile, Recovered));
  Assert.IsFalse(Recovered);
end;

procedure TReadJsonFileTests.CorruptFileFallsBackToTheBackup;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '{"v":2');                // cortado a meio
  FDir.Write('d.json.bak', '{"v":1}');
  Assert.AreEqual('{"v":1}', ReadJsonFile(FFile, Recovered));
  Assert.IsTrue(Recovered);
end;

procedure TReadJsonFileTests.RecoveryRestoresTheMainFileAndKeepsTheCorruptOne;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', 'lixo');
  FDir.Write('d.json.bak', '{"v":1}');
  ReadJsonFile(FFile, Recovered);
  Assert.AreEqual('{"v":1}', ReadText(FFile), 'o ficheiro principal volta a ser o bom');
  Assert.AreEqual('lixo', ReadText(FFile + '.corrupt'), 'o danificado fica guardado');
end;

procedure TReadJsonFileTests.EmptyFileCountsAsCorrupt;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '');
  FDir.Write('d.json.bak', '{"v":1}');
  Assert.AreEqual('{"v":1}', ReadJsonFile(FFile, Recovered));
  Assert.IsTrue(Recovered);
end;

procedure TReadJsonFileTests.JsonThatIsNotAnObjectCountsAsCorrupt;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '[1,2,3]');
  FDir.Write('d.json.bak', '{"v":1}');
  Assert.AreEqual('{"v":1}', ReadJsonFile(FFile, Recovered));
  Assert.IsTrue(Recovered);
end;

procedure TReadJsonFileTests.MissingMainFileUsesTheBackup;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json.bak', '{"v":1}');
  Assert.AreEqual('{"v":1}', ReadJsonFile(FFile, Recovered));
  Assert.IsTrue(Recovered);
  Assert.IsTrue(TFile.Exists(FFile), 'o principal e recriado');
  Assert.IsFalse(TFile.Exists(FFile + '.corrupt'), 'nao havia nada danificado para guardar');
end;

procedure TReadJsonFileTests.CorruptFileWithoutBackupRaisesAndIsKept;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '{"v":');
  Assert.WillRaise(
    procedure
    begin
      ReadJsonFile(FFile, Recovered);
    end, EDataFileCorrupt);
  Assert.IsTrue(TFile.Exists(FFile + '.corrupt'), 'uma copia do danificado e guardada');
end;

procedure TReadJsonFileTests.CorruptBackupToo;
var
  Recovered: Boolean;
begin
  FDir.Write('d.json', '{"v":');
  FDir.Write('d.json.bak', 'nao sou json');
  Assert.WillRaise(
    procedure
    begin
      ReadJsonFile(FFile, Recovered);
    end, EDataFileCorrupt);
end;

procedure TReadJsonFileTests.MissingEverythingRaisesNotFound;
var
  Recovered: Boolean;
begin
  Assert.WillRaise(
    procedure
    begin
      ReadJsonFile(FFile, Recovered);
    end, EFileNotFoundException);
end;

procedure TReadJsonFileTests.DataFileExistsAlsoSeesTheBackup;
begin
  Assert.IsFalse(DataFileExists(FFile));
  FDir.Write('d.json.bak', '{}');
  Assert.IsTrue(DataFileExists(FFile));
  FDir.Write('d.json', '{}');
  Assert.IsTrue(DataFileExists(FFile));
end;

procedure TReadJsonFileTests.DeleteDataFileRemovesEveryCopy;
begin
  FDir.Write('d.json', '{}');
  FDir.Write('d.json.bak', '{}');
  FDir.Write('d.json.corrupt', 'x');
  FDir.Write('d.json.tmp', 'x');
  DeleteDataFile(FFile);
  Assert.IsFalse(TFile.Exists(FFile));
  Assert.IsFalse(TFile.Exists(FFile + '.bak'));
  Assert.IsFalse(TFile.Exists(FFile + '.corrupt'));
  Assert.IsFalse(TFile.Exists(FFile + '.tmp'));
  DeleteDataFile(FFile);                         // nao falha se ja nao existir
end;

{ TStoredFilesTests }

procedure TStoredFilesTests.Setup;
begin
  FIso := TIsolatedAppData.Create;
end;

procedure TStoredFilesTests.TearDown;
begin
  FIso.Free;
end;

procedure TStoredFilesTests.ProgressSavesWithBackupAndRecovers;
var
  S, L: TProgressState;
  F: string;
begin
  F := ProgressFileFor('p1');
  S := TProgressState.Create;
  L := TProgressState.Create;
  try
    S.Rec('a.pas').Note := 'primeira';
    S.SaveToFile(F);
    S.Rec('a.pas').Note := 'segunda';
    S.SaveToFile(F);
    Assert.IsTrue(TFile.Exists(F + '.bak'));
    TFile.WriteAllText(F, '{ danificado', TEncoding.UTF8);       // o disco ou o antivirus cortaram o ficheiro
    L.LoadStored(F);
    Assert.IsTrue(L.RecoveredFromBackup);
    Assert.AreEqual('primeira', L.Find('a.pas').Note, 'volta a versao anterior (a copia)');
    Assert.IsTrue(TFile.Exists(F + '.corrupt'));
  finally
    L.Free;
    S.Free;
  end;
end;

procedure TStoredFilesTests.ProgressImportStaysStrict;
var
  S: TProgressState;
  F: string;
begin
  // importar um ficheiro escolhido pelo utilizador nao procura copias nem restaura nada
  F := TPath.Combine(FIso.Path, 'importado.json');
  TFile.WriteAllText(F + '.bak', '{"a.pas":{"note":"x"}}', TEncoding.UTF8);
  TFile.WriteAllText(F, 'nao e json', TEncoding.UTF8);
  S := TProgressState.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        S.LoadFromFile(F);
      end);
    Assert.IsFalse(S.RecoveredFromBackup);
  finally
    S.Free;
  end;
end;

procedure TStoredFilesTests.HistorySavesWithBackupAndRecovers;
var
  H, L: THistory;
  F: string;
  Snap: TSnapshot;
begin
  F := HistoryFileFor('p1');
  H := THistory.Create;
  L := THistory.Create;
  try
    Snap := Default(TSnapshot);
    Snap.Date := '2026-10-01';
    Snap.Files := 5;
    H.Capture(Snap);
    H.SaveToFile(F);
    Snap.Date := '2026-10-02';
    H.Capture(Snap);
    H.SaveToFile(F);                              // agora o .bak so tem o dia 1
    TFile.WriteAllText(F, '', TEncoding.UTF8);    // ficheiro esvaziado
    L.LoadFromFile(F);
    Assert.IsTrue(L.RecoveredFromBackup);
    Assert.AreEqual(1, L.Count);
    Assert.AreEqual('2026-10-01', L[0].Date);
  finally
    L.Free;
    H.Free;
  end;
end;

procedure TStoredFilesTests.SettingsSaveWithBackupAndRecover;
var
  S, L: TAppSettings;
  F: string;
begin
  F := TPath.Combine(FIso.Path, 'settings.json');
  S := TAppSettings.Create;
  L := TAppSettings.Create;
  try
    S.Theme := 'dark';
    S.Save;
    S.Theme := 'light';
    S.Save;
    Assert.IsTrue(TFile.Exists(F + '.bak'));
    TFile.WriteAllText(F, '{"theme": "li', TEncoding.UTF8);
    L.Load;
    Assert.IsTrue(L.RecoveredFromBackup);
    Assert.AreEqual('dark', L.Theme, 'a copia tinha o tema anterior');
  finally
    L.Free;
    S.Free;
  end;
end;

procedure TStoredFilesTests.CodeFontAndLigaturesRoundTrip;
var
  S, L: TAppSettings;
begin
  S := TAppSettings.Create;
  L := TAppSettings.Create;
  try
    S.CodeFont := 'Fira Code';
    S.CodeLigatures := False;
    S.Save;
    L.Load;
    Assert.AreEqual('Fira Code', L.CodeFont);
    Assert.IsFalse(L.CodeLigatures);
  finally
    L.Free;
    S.Free;
  end;
end;

procedure TStoredFilesTests.CodeLigaturesAreOnByDefault;
var
  S, L: TAppSettings;
begin
  S := TAppSettings.Create;
  L := TAppSettings.Create;
  try
    Assert.IsTrue(S.CodeLigatures);
    Assert.AreEqual('', S.CodeFont);
    TFile.WriteAllText(TPath.Combine(FIso.Path, 'settings.json'), '{"theme": "dark"}', TEncoding.UTF8);
    L.Load;
    Assert.IsTrue(L.CodeLigatures, 'definicoes antigas, sem o campo, mantem as ligaduras');
    Assert.AreEqual('', L.CodeFont);
  finally
    L.Free;
    S.Free;
  end;
end;

procedure TStoredFilesTests.SettingsWithBothFilesCorruptRaise;
var
  L: TAppSettings;
  F: string;
begin
  F := TPath.Combine(FIso.Path, 'settings.json');
  TFile.WriteAllText(F, 'lixo', TEncoding.UTF8);
  TFile.WriteAllText(F + '.bak', 'mais lixo', TEncoding.UTF8);
  L := TAppSettings.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        L.Load;
      end, EDataFileCorrupt);
  finally
    L.Free;
  end;
end;

end.
