unit Tests.Print.Doc;

// Testes de TStructureDoc (CM.Print): paginacao (incluindo a regra de nao deixar um cabecalho de
// pasta sozinho no fundo da pagina - "KeepWithNext"), largura de coluna (MaxChars) e que DrawPage
// nao rebenta com indices validos. Usa FMX.Graphics.TBitmap como superficie - a mesma tecnica do
// modo --dev (ver TMainForm.DevPrintPreview) - por isso nao precisa de impressora nem de janela.
//
// O TBitmap serve so para medir a fonte (ACanvas.TextWidth) e para desenhar quando se testa
// DrawPage; as dimensoes da "pagina" em si vem de TPageSpec (Width/Height/DPI), que sao
// independentes do tamanho em pixeis do bitmap - por isso usa-se sempre um bitmap pequeno e fixo
// (a impressora tem paginas de milhares de pixeis, mas um TBitmap tao grande excede o limite de
// textura da placa grafica: "Bitmap size too big").

interface

uses
  System.SysUtils, System.Math, System.Generics.Collections, DUnitX.TestFramework, FMX.Graphics,
  CM.Analyzer, CM.Store, CM.Export, CM.Print, Tests.Helpers, Tests.Export.Fixtures;

type
  [TestFixture]
  TPageSpecTests = class
  public
    [Test] procedure MakeCopiesTheThreeFields;
  end;

  [TestFixture]
  TStructureDocTests = class
  public
    [Test] procedure EverythingFitsOnOnePageWhenThePageIsBigEnough;
    [Test] procedure ASmallPageNeedsMoreThanOnePage;
    [Test] procedure MaxCharsNeverDropsBelowTwenty;
    [Test] procedure MaxCharsGrowsWithPageWidth;
    [Test] procedure TitleIsTheFirstItemOnPageZero;
    [Test] procedure AFolderHeadingIsNeverTheLastLineOfAPage;
    [Test] procedure DrawPageDoesNotRaiseForAnyValidIndex;
    [Test] procedure DrawPageDoesNotRaiseForAnOutOfRangeIndex;
    [Test] procedure NarrowPagesWrapLongSignaturesIntoMoreItems;
  end;

implementation

const
  // bitmap so de medida: pequeno e fixo, nunca do tamanho da "pagina" em teste (ver comentario acima)
  MeasureW = 600;
  MeasureH = 400;

function SmallScan: TProjectScan;
begin
  Result := NewScan(1, [MakeUnitInfo('F/a.pas', 'F', [])]);
end;

// PageCount de um documento com uma pagina AWidth x AHeight (pontos/pixeis logicos), a 96 DPI;
// a largura e' generosa (2000) para as linhas nao quebrarem, a nao ser que o teste queira isso
function PageCountAt(AHeight: Integer; AWidth: Integer = 2000): Integer;
var
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
begin
  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(AWidth, AHeight, 96), P, Scan, St, Default(TExportOptions));
    try
      Result := Doc.PageCount;
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

{ TPageSpecTests }

procedure TPageSpecTests.MakeCopiesTheThreeFields;
var
  Spec: TPageSpec;
begin
  Spec := TPageSpec.Make(850, 1100, 100);
  Assert.AreEqual(850, Spec.Width);
  Assert.AreEqual(1100, Spec.Height);
  Assert.AreEqual(100, Spec.DPI);
end;

{ TStructureDocTests }

procedure TStructureDocTests.EverythingFitsOnOnePageWhenThePageIsBigEnough;
begin
  Assert.AreEqual(1, PageCountAt(20000));
end;

procedure TStructureDocTests.ASmallPageNeedsMoreThanOnePage;
begin
  Assert.IsTrue(PageCountAt(150) > 1);
end;

procedure TStructureDocTests.MaxCharsNeverDropsBelowTwenty;
var
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
begin
  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(50, 2000, 96), P, Scan, St, Default(TExportOptions));
    try
      Assert.AreEqual(20, Doc.MaxChars, 'largura ridiculamente pequena: usa o minimo de 20');
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TStructureDocTests.MaxCharsGrowsWithPageWidth;

  function MaxCharsAt(AWidth: Integer): Integer;
  var
    Bmp: TBitmap;
    Scan: TProjectScan;
    St: TProgressState;
    P: TProjectProfile;
    Doc: TStructureDoc;
  begin
    Scan := SmallScan;
    St := TProgressState.Create;
    P := NewProfile('X');
    Bmp := TBitmap.Create(MeasureW, MeasureH);
    try
      Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(AWidth, 2000, 96), P, Scan, St, Default(TExportOptions));
      try
        Result := Doc.MaxChars;
      finally
        Doc.Free;
      end;
    finally
      Bmp.Free;
      P.Free;
      St.Free;
      Scan.Free;
    end;
  end;

begin
  Assert.IsTrue(MaxCharsAt(3000) > MaxCharsAt(600));
end;

procedure TStructureDocTests.TitleIsTheFirstItemOnPageZero;
var
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
begin
  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('Projeto X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(2000, 20000, 96), P, Scan, St, Default(TExportOptions));
    try
      Assert.IsTrue(Doc.Items.Count > 0);
      Assert.AreEqual(Ord(dkTitle), Ord(Doc.Items[0].Kind));
      Assert.AreEqual(0, Doc.Items[0].Page);
      Assert.IsTrue(Doc.Items[0].Text.Contains('Projeto X'));
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

// pesquisa binaria pela altura mais pequena que ainda cabe tudo numa pagina (preto-e-branco:
// nao depende de nenhuma constante privada de CM.Print, so do PageCount observado)
function SmallestHeightForOnePage(ALo, AHi: Integer): Integer;
begin
  while AHi - ALo > 1 do
  begin
    var Mid := (ALo + AHi) div 2;
    if PageCountAt(Mid) = 1 then
      AHi := Mid
    else
      ALo := Mid;
  end;
  Result := AHi;
end;

procedure TStructureDocTests.AFolderHeadingIsNeverTheLastLineOfAPage;
var
  Threshold: Integer;
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
  DirItemIdx, FileItemIdx, I: Integer;
begin
  // altura minima para caber tudo numa so pagina; um pixel a menos tem de chumbar para 2 paginas
  Threshold := SmallestHeightForOnePage(100, 20000);
  Assert.AreEqual(1, PageCountAt(Threshold));
  Assert.IsTrue(PageCountAt(Threshold - 1) > 1);

  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(2000, Threshold - 1, 96), P, Scan, St,
      Default(TExportOptions));
    try
      DirItemIdx := -1;
      FileItemIdx := -1;
      for I := 0 to Doc.Items.Count - 1 do
      begin
        // o Text ja inclui o conector da arvore (ex.: '\-- F/'), nao so o nome da pasta
        if (Doc.Items[I].Kind = dkDir) and Doc.Items[I].Text.Contains('F/') then
          DirItemIdx := I;
        if Doc.Items[I].Kind = dkFile then
          FileItemIdx := I;
      end;
      Assert.IsTrue(DirItemIdx >= 0, 'cabecalho da pasta F nao encontrado');
      Assert.IsTrue(FileItemIdx = DirItemIdx + 1, 'a.pas e o item logo a seguir a F/');
      // a pasta F/ e o ficheiro a.pas tem de ficar juntos na mesma pagina - nunca F/ sozinho
      // no fundo de uma pagina com a.pas a transbordar para a seguinte
      Assert.AreEqual(Doc.Items[DirItemIdx].Page, Doc.Items[FileItemIdx].Page,
        'o cabecalho da pasta e o primeiro filho ficam sempre na mesma pagina');
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TStructureDocTests.DrawPageDoesNotRaiseForAnyValidIndex;
var
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
  I: Integer;
begin
  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    // pagina "pequena" so na TPageSpec: forca varias paginas sem precisar de um bitmap gigante
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(300, 150, 96), P, Scan, St, Default(TExportOptions));
    try
      Assert.IsTrue(Doc.PageCount > 1);
      for I := 0 to Doc.PageCount - 1 do
      begin
        Bmp.Canvas.BeginScene;
        try
          Bmp.Canvas.Clear($FFFFFFFF);
          Doc.DrawPage(Bmp.Canvas, I);
        finally
          Bmp.Canvas.EndScene;
        end;
      end;
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TStructureDocTests.DrawPageDoesNotRaiseForAnOutOfRangeIndex;
var
  Bmp: TBitmap;
  Scan: TProjectScan;
  St: TProgressState;
  P: TProjectProfile;
  Doc: TStructureDoc;
begin
  Scan := SmallScan;
  St := TProgressState.Create;
  P := NewProfile('X');
  Bmp := TBitmap.Create(MeasureW, MeasureH);
  try
    Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(2000, 20000, 96), P, Scan, St, Default(TExportOptions));
    try
      Bmp.Canvas.BeginScene;
      try
        Doc.DrawPage(Bmp.Canvas, Doc.PageCount);   // um a mais: nao ha itens dessa pagina, so isso
      finally
        Bmp.Canvas.EndScene;
      end;
    finally
      Doc.Free;
    end;
  finally
    Bmp.Free;
    P.Free;
    St.Free;
    Scan.Free;
  end;
end;

procedure TStructureDocTests.NarrowPagesWrapLongSignaturesIntoMoreItems;

  function ItemCountFor(AScan: TProjectScan; AWidth: Integer): Integer;
  var
    Bmp: TBitmap;
    St: TProgressState;
    P: TProjectProfile;
    Doc: TStructureDoc;
    Opt: TExportOptions;
  begin
    St := TProgressState.Create;
    P := NewProfile('X');
    Bmp := TBitmap.Create(MeasureW, MeasureH);
    try
      Opt := Default(TExportOptions);
      Opt.IncludeMethods := True;
      Doc := TStructureDoc.Create(Bmp.Canvas, TPageSpec.Make(AWidth, 20000, 96), P, AScan, St, Opt);
      try
        Result := Doc.Items.Count;
      finally
        Doc.Free;
      end;
    finally
      Bmp.Free;
      P.Free;
      St.Free;
    end;
  end;

var
  Scan: TProjectScan;
  LongName: string;
begin
  // Meth constroi Sig como 'procedure ' + Name + ';': um nome comprido chega para um Sig comprido
  LongName := 'TFoo.MetodoComUmNomeDeliberadamenteEnormeParaNaoCaberNumaLinhaEstreitaDeTodoMesmoAssim';
  Scan := NewScan(0, [MakeUnitInfo('a.pas', 'Raiz', [Meth(LongName, 'TFoo', 'MetodoComprido')])]);
  try
    Assert.IsTrue(ItemCountFor(Scan, 3000) < ItemCountFor(Scan, 400),
      'a mesma assinatura longa precisa de mais linhas numa pagina estreita');
  finally
    Scan.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPageSpecTests);
  TDUnitX.RegisterTestFixture(TStructureDocTests);

end.
