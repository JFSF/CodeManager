unit CM.Print;

{ Impressao da estrutura (pastas > ficheiros > metodos) na impressora do Windows, com FMX.Printer.
  A paginacao nao depende da impressora: TStructureDoc recebe as medidas da superficie (pixeis e DPI)
  e desenha qualquer pagina em qualquer TCanvas - a impressora ou um TBitmap (usado nos testes).
  Letra monoespacada (Courier New, 0,6 em de avanco), tal como a arvore do TXT, e quebra de linha com
  indentacao das guias quando uma assinatura e maior do que a largura da pagina. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math, System.Generics.Collections,
  FMX.Graphics, FMX.Types, CM.Analyzer, CM.Store, CM.Export;

type
  // superficie onde se desenha: dimensoes em pixeis e resolucao
  TPageSpec = record
    Width, Height: Integer;
    DPI: Integer;
    class function Make(AWidth, AHeight, ADPI: Integer): TPageSpec; static;
  end;

  TDocItemKind = (dkTitle, dkMeta, dkBlank, dkDir, dkFile, dkMethod);

  TDocItem = record
    Kind: TDocItemKind;
    Text: string;
    Page: Integer;     // 0-based
    Y: Single;         // desde o topo da area de corpo
    H: Single;
  end;

  TStructureDoc = class
  private
    FSpec: TPageSpec;
    FProfileName: string;
    FStamp: string;
    FItems: TList<TDocItem>;
    FPageCount: Integer;
    FMargin: Single;
    FBodyPx, FSmallPx, FTitlePx: Single;
    FLineH: Single;
    FHeaderH, FFooterH: Single;
    FCharW: Single;
    FMaxChars: Integer;
    function Px(APoints: Single): Single;
    procedure Layout(ACanvas: TCanvas; AProfile: TProjectProfile; AScan: TProjectScan;
      AState: TProgressState; const AOptions: TExportOptions);
    procedure AddItem(AKind: TDocItemKind; const AText: string; AHeight: Single; AKeepWithNext: Boolean);
    procedure SetFont(ACanvas: TCanvas; ASize: Single; ABold: Boolean; AColor: TAlphaColor);
    procedure PutText(ACanvas: TCanvas; const AText: string; const ARect: TRectF; AAlign: TTextAlign);
  public
    constructor Create(ACanvas: TCanvas; const ASpec: TPageSpec; AProfile: TProjectProfile;
      AScan: TProjectScan; AState: TProgressState; const AOptions: TExportOptions);
    destructor Destroy; override;
    procedure DrawPage(ACanvas: TCanvas; APageIndex: Integer);
    property PageCount: Integer read FPageCount;
    property MaxChars: Integer read FMaxChars;
    // itens paginados (pagina e posicao ja calculadas); so para inspeccao nos testes
    property Items: TList<TDocItem> read FItems;
  end;

// imprime na impressora activa do FMX (ja escolhida no dialogo); devolve o numero de paginas
function PrintStructure(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): Integer;

// parte AText em linhas de ate AMaxChars caracteres (contando o prefixo), preferindo quebrar num
// espaco; a primeira leva APrefix e as seguintes AContPrefix - exposta so para ser testada directamente
function WrapLine(const APrefix, AContPrefix, AText: string; AMaxChars: Integer): TArray<string>;

implementation

uses
  Winapi.Windows, FMX.Printer, FMX.Printer.Win;

const
  MonoFamily = 'Courier New';
  MarginMm = 15;
  BodyPt = 9;
  SmallPt = 8;
  TitlePt = 13;
  ColorText = $FF000000;
  ColorSoft = $FF3C3C3C;
  ColorMeta = $FF555555;
  ColorRule = $FF9A9A9A;

class function TPageSpec.Make(AWidth, AHeight, ADPI: Integer): TPageSpec;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.DPI := ADPI;
end;

{ ---------------------------------------------------------------- quebra de linha }

// parte AText em linhas de ate AMaxChars caracteres (contando o prefixo), preferindo quebrar num espaco;
// a primeira leva APrefix e as seguintes AContPrefix
function WrapLine(const APrefix, AContPrefix, AText: string; AMaxChars: Integer): TArray<string>;
var
  Lines: TList<string>;
  Rest, Prefix, Chunk: string;
  Avail, Cut: Integer;
begin
  Lines := TList<string>.Create;
  try
    Rest := AText;
    Prefix := APrefix;
    repeat
      Avail := Max(8, AMaxChars - Length(Prefix));
      if Length(Rest) <= Avail then
      begin
        Lines.Add(Prefix + Rest);
        Break;
      end;
      Cut := LastDelimiter(' ', Copy(Rest, 1, Avail + 1));   // espaco no limite tambem serve
      if Cut < 2 then
        Cut := Avail;                                        // sem espacos: quebra a direito
      Chunk := Copy(Rest, 1, Cut);
      Lines.Add(Prefix + TrimRight(Chunk));
      Rest := TrimLeft(Copy(Rest, Cut + 1, MaxInt));
      Prefix := AContPrefix;
    until Rest = '';
    Result := Lines.ToArray;
  finally
    Lines.Free;
  end;
end;

{ ---------------------------------------------------------------- TStructureDoc }

constructor TStructureDoc.Create(ACanvas: TCanvas; const ASpec: TPageSpec; AProfile: TProjectProfile;
  AScan: TProjectScan; AState: TProgressState; const AOptions: TExportOptions);
begin
  inherited Create;
  FSpec := ASpec;
  FItems := TList<TDocItem>.Create;
  FProfileName := AProfile.Name;
  FStamp := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  Layout(ACanvas, AProfile, AScan, AState, AOptions);
end;

destructor TStructureDoc.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TStructureDoc.Px(APoints: Single): Single;
begin
  Result := APoints * FSpec.DPI / 72;
end;

procedure TStructureDoc.SetFont(ACanvas: TCanvas; ASize: Single; ABold: Boolean; AColor: TAlphaColor);
begin
  ACanvas.Font.Family := MonoFamily;
  ACanvas.Font.Size := ASize;
  if ABold then
    ACanvas.Font.Style := [TFontStyle.fsBold]
  else
    ACanvas.Font.Style := [];
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;
end;

procedure TStructureDoc.PutText(ACanvas: TCanvas; const AText: string; const ARect: TRectF; AAlign: TTextAlign);
begin
  ACanvas.FillText(ARect, AText, False, 1, [], AAlign, TTextAlign.Leading);
end;

procedure TStructureDoc.AddItem(AKind: TDocItemKind; const AText: string; AHeight: Single;
  AKeepWithNext: Boolean);
var
  It: TDocItem;
  BodyH, Y: Single;
  Page: Integer;
begin
  BodyH := FSpec.Height - 2 * FMargin - FHeaderH - FFooterH;
  Page := 0;
  Y := 0;
  if FItems.Count > 0 then
  begin
    Page := FItems.Last.Page;
    Y := FItems.Last.Y + FItems.Last.H;
  end;
  // uma pasta nao fica sozinha no fundo da pagina: exige espaco tambem para a linha seguinte
  if Y + AHeight + IfThen(AKeepWithNext, FLineH, 0) > BodyH + 0.5 then
  begin
    Inc(Page);
    Y := 0;
  end;
  It.Kind := AKind;
  It.Text := AText;
  It.Page := Page;
  It.Y := Y;
  It.H := AHeight;
  FItems.Add(It);
  FPageCount := Page + 1;
end;

procedure TStructureDoc.Layout(ACanvas: TCanvas; AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOptions: TExportOptions);
var
  Line, S: string;
  TL: TTreeLine;
  Kind: TDocItemKind;
  Wrapped: TArray<string>;
  I: Integer;
begin
  FMargin := MarginMm / 25.4 * FSpec.DPI;
  FBodyPx := Px(BodyPt);
  FSmallPx := Px(SmallPt);
  FTitlePx := Px(TitlePt);
  FLineH := FBodyPx * 1.3;
  FHeaderH := FSmallPx * 2.2;
  FFooterH := FSmallPx * 2.6;
  // largura real de um caractere, medida na propria superficie
  SetFont(ACanvas, FBodyPx, False, ColorText);
  FCharW := ACanvas.TextWidth(StringOfChar('M', 40)) / 40;
  if FCharW <= 0 then
    FCharW := FBodyPx * 0.6;
  FMaxChars := Max(20, Floor((FSpec.Width - 2 * FMargin) / FCharW));
  FPageCount := 1;

  AddItem(dkTitle, 'Estrutura do código — ' + AProfile.Name, FTitlePx * 1.5, False);
  for Line in ExportHeaderLines(AScan, AState, AOptions) do
    for S in WrapLine('', '  ', Line, FMaxChars) do
      AddItem(dkMeta, S, FLineH, False);
  AddItem(dkBlank, '', FLineH * 0.6, False);
  AddItem(dkDir, AProfile.Name + '/', FLineH, True);
  for TL in BuildTreeLines(AScan, AState, AOptions) do
  begin
    case TL.Row.Kind of
      xkDir: Kind := dkDir;
      xkFile: Kind := dkFile;
    else
      Kind := dkMethod;
    end;
    Wrapped := WrapLine(TL.Prefix, TL.ContPrefix, TL.Text, FMaxChars);
    for I := 0 to High(Wrapped) do
      // so a primeira linha de uma pasta fica presa a seguinte
      AddItem(Kind, Wrapped[I], FLineH, (Kind = dkDir) and (I = High(Wrapped)));
  end;
end;

procedure TStructureDoc.DrawPage(ACanvas: TCanvas; APageIndex: Integer);
var
  It: TDocItem;
  Left, Right, BodyTop, Y: Single;
  R: TRectF;
begin
  Left := FMargin;
  Right := FSpec.Width - FMargin;
  BodyTop := FMargin + FHeaderH;

  // cabecalho corrido (a primeira pagina ja tem o titulo no corpo)
  if APageIndex > 0 then
  begin
    SetFont(ACanvas, FSmallPx, False, ColorMeta);
    PutText(ACanvas, FProfileName, RectF(Left, FMargin, Right, FMargin + FSmallPx * 1.6), TTextAlign.Leading);
    PutText(ACanvas, 'Estrutura do código', RectF(Left, FMargin, Right, FMargin + FSmallPx * 1.6), TTextAlign.Trailing);
    ACanvas.Stroke.Kind := TBrushKind.Solid;
    ACanvas.Stroke.Color := ColorRule;
    ACanvas.Stroke.Thickness := Max(1, FSpec.DPI / 200);
    Y := FMargin + FSmallPx * 1.75;
    ACanvas.DrawLine(PointF(Left, Y), PointF(Right, Y), 1);
  end;

  for It in FItems do
  begin
    if It.Page <> APageIndex then
      Continue;
    R := RectF(Left, BodyTop + It.Y, Right + FCharW * 4, BodyTop + It.Y + It.H);
    case It.Kind of
      dkTitle:
        SetFont(ACanvas, FTitlePx, True, ColorText);
      dkMeta:
        SetFont(ACanvas, FBodyPx, False, ColorMeta);
      dkDir:
        SetFont(ACanvas, FBodyPx, True, ColorText);
      dkFile:
        SetFont(ACanvas, FBodyPx, False, ColorText);
      dkMethod:
        SetFont(ACanvas, FBodyPx, False, ColorSoft);
    else
      Continue;
    end;
    PutText(ACanvas, It.Text, R, TTextAlign.Leading);
  end;

  // rodape: data a esquerda, "Pagina X de N" a direita
  Y := FSpec.Height - FMargin - FFooterH;
  ACanvas.Stroke.Kind := TBrushKind.Solid;
  ACanvas.Stroke.Color := ColorRule;
  ACanvas.Stroke.Thickness := Max(1, FSpec.DPI / 200);
  ACanvas.DrawLine(PointF(Left, Y + FSmallPx * 0.4), PointF(Right, Y + FSmallPx * 0.4), 1);
  SetFont(ACanvas, FSmallPx, False, ColorMeta);
  PutText(ACanvas, FStamp, RectF(Left, Y + FSmallPx * 0.7, Right, Y + FFooterH), TTextAlign.Leading);
  PutText(ACanvas, Format('Página %d de %d', [APageIndex + 1, FPageCount]),
    RectF(Left, Y + FSmallPx * 0.7, Right, Y + FFooterH), TTextAlign.Trailing);
end;

{ ---------------------------------------------------------------- impressora }

function PrintStructure(AProfile: TProjectProfile; AScan: TProjectScan; AState: TProgressState;
  const AOptions: TExportOptions): Integer;
var
  Prn: TPrinter;
  Doc: TStructureDoc;
  Spec: TPageSpec;
  DPI, I: Integer;
begin
  Prn := Printer;
  if Prn.Count = 0 then
    raise Exception.Create('Não há impressoras instaladas.');
  Prn.Title := 'Estrutura do código — ' + AProfile.Name;
  Prn.BeginDoc;
  try
    DPI := 0;
    if Prn is TPrinterWin then
      DPI := GetDeviceCaps(TPrinterWin(Prn).Handle, LOGPIXELSX);
    if DPI <= 0 then
      DPI := Prn.ActivePrinter.ActiveDPI.X;
    if DPI <= 0 then
      DPI := 300;
    Spec := TPageSpec.Make(Prn.PageWidth, Prn.PageHeight, DPI);
    Doc := TStructureDoc.Create(Prn.Canvas, Spec, AProfile, AScan, AState, AOptions);
    try
      Result := Doc.PageCount;
      for I := 0 to Doc.PageCount - 1 do
      begin
        if I > 0 then
          Prn.NewPage;
        Doc.DrawPage(Prn.Canvas, I);
      end;
    finally
      Doc.Free;
    end;
    Prn.EndDoc;
  except
    if Prn.Printing then
      Prn.Abort;
    raise;
  end;
end;

end.
