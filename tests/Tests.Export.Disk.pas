unit Tests.Export.Disk;

// Testes do despacho por formato (BuildExport) e da escrita em disco (ExportToFile): criacao de
// pastas em falta e o BOM UTF-8 em TXT/CSV mas nao em Markdown/JSON.

interface

uses
  System.SysUtils, System.IOUtils, DUnitX.TestFramework,
  CM.Analyzer, CM.Store, CM.Export, Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  TBuildExportDispatchTests = class
  public
    [Test] procedure MarkdownDispatchesToBuildMarkdown;
    [Test] procedure TextDispatchesToBuildText;
    [Test] procedure CsvDispatchesToBuildCsv;
    [Test] procedure JsonDispatchesToBuildJson;
  end;

  [TestFixture]
  TExportToFileTests = class
  private
    FDir: TTempDir;
    FScan: TProjectScan;
    FState: TProgressState;
    FProfile: TProjectProfile;
    FOpt: TExportOptions;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure WrittenContentMatchesBuildExport;
    [Test] procedure TextAndCsvGetAUtf8Bom;
    [Test] procedure MarkdownAndJsonHaveNoBom;
    [Test] procedure MissingDirectoriesAreCreated;
    [Test] procedure AnAlreadyExistingDirectoryIsNotAProblem;
    [Test] procedure OverwritesAnExistingFile;
  end;

implementation

const
  Utf8Bom: array[0..2] of Byte = ($EF, $BB, $BF);

function StartsWithBom(const AFileName: string): Boolean;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  Result := (Length(Bytes) >= 3) and (Bytes[0] = Utf8Bom[0]) and (Bytes[1] = Utf8Bom[1]) and
    (Bytes[2] = Utf8Bom[2]);
end;

{ TBuildExportDispatchTests }

procedure TBuildExportDispatchTests.MarkdownDispatchesToBuildMarkdown;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual(BuildMarkdown(P, Scan, St, Opt), BuildExport(efMarkdown, P, Scan, St, Opt));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildExportDispatchTests.TextDispatchesToBuildText;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual(BuildText(P, Scan, St, Opt), BuildExport(efText, P, Scan, St, Opt));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildExportDispatchTests.CsvDispatchesToBuildCsv;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual(BuildCsv(Scan, St, Opt), BuildExport(efCsv, P, Scan, St, Opt));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TBuildExportDispatchTests.JsonDispatchesToBuildJson;
var
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Opt: TExportOptions;
begin
  Scan := BuildSampleScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  try
    Opt := Default(TExportOptions);
    Assert.AreEqual(BuildJson(P, Scan, St, Opt), BuildExport(efJson, P, Scan, St, Opt));
  finally
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

{ TExportToFileTests }

procedure TExportToFileTests.Setup;
begin
  FDir := TTempDir.Create;
  FScan := BuildSampleScan;
  FState := TProgressState.Create;
  FProfile := NewProfile('Projeto X');
  FOpt := Default(TExportOptions);
end;

procedure TExportToFileTests.TearDown;
begin
  FProfile.Free;
  FState.Free;
  FScan.Free;
  FDir.Free;
end;

procedure TExportToFileTests.WrittenContentMatchesBuildExport;
var
  FileName, Expected, Actual: string;
begin
  FileName := FDir.Full('out.md');
  Expected := BuildExport(efMarkdown, FProfile, FScan, FState, FOpt);
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, FileName);
  Actual := TFile.ReadAllText(FileName, TEncoding.UTF8);
  Assert.AreEqual(Expected, Actual);
end;

procedure TExportToFileTests.TextAndCsvGetAUtf8Bom;
var
  TxtFile, CsvFile: string;
begin
  TxtFile := FDir.Full('out.txt');
  CsvFile := FDir.Full('out.csv');
  ExportToFile(efText, FProfile, FScan, FState, FOpt, TxtFile);
  ExportToFile(efCsv, FProfile, FScan, FState, FOpt, CsvFile);
  Assert.IsTrue(StartsWithBom(TxtFile), 'TXT deve ter BOM UTF-8');
  Assert.IsTrue(StartsWithBom(CsvFile), 'CSV deve ter BOM UTF-8');
end;

procedure TExportToFileTests.MarkdownAndJsonHaveNoBom;
var
  MdFile, JsonFile: string;
begin
  MdFile := FDir.Full('out.md');
  JsonFile := FDir.Full('out.json');
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, MdFile);
  ExportToFile(efJson, FProfile, FScan, FState, FOpt, JsonFile);
  Assert.IsFalse(StartsWithBom(MdFile), 'Markdown nao deve ter BOM');
  Assert.IsFalse(StartsWithBom(JsonFile), 'JSON nao deve ter BOM');
end;

procedure TExportToFileTests.MissingDirectoriesAreCreated;
var
  FileName: string;
begin
  FileName := FDir.Full('a/b/c/out.md');
  Assert.IsFalse(TDirectory.Exists(FDir.Full('a/b/c')));
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, FileName);
  Assert.IsTrue(TFile.Exists(FileName));
end;

procedure TExportToFileTests.AnAlreadyExistingDirectoryIsNotAProblem;
var
  FileName: string;
begin
  FileName := FDir.Full('out.md');
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, FileName);
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, FileName);   // nao pode levantar excepcao
  Assert.IsTrue(TFile.Exists(FileName));
end;

procedure TExportToFileTests.OverwritesAnExistingFile;
var
  FileName: string;
begin
  FileName := FDir.Full('out.md');
  TFile.WriteAllText(FileName, 'conteudo antigo');
  ExportToFile(efMarkdown, FProfile, FScan, FState, FOpt, FileName);
  Assert.IsTrue(TFile.ReadAllText(FileName, TEncoding.UTF8).StartsWith('# Estrutura do código'));
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildExportDispatchTests);
  TDUnitX.RegisterTestFixture(TExportToFileTests);

end.
