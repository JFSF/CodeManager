unit CM.Theme;

{ Tema visual da aplicacao: paletas clara/escura (os mesmos tokens de cor das paginas HTML
  originais), icones vectoriais, tipos de letra e utilitarios de desenho.
  Todos os controlos da aplicacao pintam-se a partir de Pal, por isso mudar o tema e
  simplesmente trocar a paleta e repintar. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Math,
  System.Math.Vectors, System.Generics.Collections, FMX.Types, FMX.Graphics, FMX.Forms, FMX.Platform.Win,
  Winapi.Windows, Winapi.Dwmapi, System.Win.Registry;

type
  TThemeMode = (tmLight, tmDark);

  TPalette = record
    Bg, Surface, Surface2, Border, BorderStrong: TAlphaColor;
    Text, TextDim, TextFaint: TAlphaColor;
    Accent, AccentStrong, AccentSoft, OnAccent: TAlphaColor;
    Star, Pending, DoneStrike, FlagCompila, FlagSonar, Danger, Hover: TAlphaColor;
  end;

  TIconKind = (icCheck, icStar, icStarOff, icChevronRight, icChevronDown, icSearch, icFolder,
    icFolderOpen, icEdit, icRefresh, icSun, icMoon, icMap, icChecklist, icDashboard, icPlus,
    icTrash, icCopy, icDownload, icUpload, icFlag, icClose, icPlay, icFile, icBrowse, icExport, icBrackets, icChart, icMinus, icGraph);

const
  LightPalette: TPalette = (
    Bg: $FFF6F7F4; Surface: $FFFFFFFF; Surface2: $FFEEF0EB; Border: $FFDCDED7; BorderStrong: $FFC4C7BE;
    Text: $FF1B1E1A; TextDim: $FF565B52; TextFaint: $FF676C62;
    Accent: $FF23705F; AccentStrong: $FF17493D; AccentSoft: $FFE3EDE9; OnAccent: $FFFFFFFF;
    Star: $FFB8860B; Pending: $FF8A6500; DoneStrike: $FF6A6F65; FlagCompila: $FF2F6FED;
    FlagSonar: $FF8B5CF6; Danger: $FFB8452F; Hover: $FFEEF0EB);

  DarkPalette: TPalette = (
    Bg: $FF14171A; Surface: $FF1B1F22; Surface2: $FF202426; Border: $FF2C3134; BorderStrong: $FF3D4448;
    Text: $FFE9EBE6; TextDim: $FF9AA09A; TextFaint: $FF8A908B;
    Accent: $FF4FB89B; AccentStrong: $FF7FD6BC; AccentSoft: $FF1E2F2B; OnAccent: $FF0E1513;
    Star: $FFE0B23C; Pending: $FFD7A53A; DoneStrike: $FF858B86; FlagCompila: $FF6FA8FF;
    FlagSonar: $FFC9A6FF; Danger: $FFE0705A; Hover: $FF202426);

function Pal: TPalette;
function ThemeMode: TThemeMode;
procedure SetThemeMode(AMode: TThemeMode);
function SystemPrefersDark: Boolean;
procedure OnThemeChanged(AHandler: TProc);
procedure ApplyTitleBarTheme(AForm: TCommonCustomForm);

function Pick(ACond: Boolean; AIfTrue, AIfFalse: TAlphaColor): TAlphaColor; inline;
function UiFont: string;
function MonoFont: string;

procedure DrawIcon(ACanvas: TCanvas; AKind: TIconKind; const ARect: TRectF; AColor: TAlphaColor;
  AOpacity: Single = 1);
procedure FillRound(ACanvas: TCanvas; const ARect: TRectF; ARadius: Single; AColor: TAlphaColor);
procedure StrokeRound(ACanvas: TCanvas; const ARect: TRectF; ARadius: Single; AColor: TAlphaColor;
  AThickness: Single = 1);
procedure DrawTextRect(ACanvas: TCanvas; const ARect: TRectF; const AText: string;
  AColor: TAlphaColor; ASize: Single; const AFamily: string; AStyle: TFontStyles = [];
  AHAlign: TTextAlign = TTextAlign.Leading; AVAlign: TTextAlign = TTextAlign.Center);
function MeasureText(const AText: string; ASize: Single; const AFamily: string;
  AStyle: TFontStyles = []): Single;
function FitText(ACanvas: TCanvas; const AText: string; AMaxWidth: Single): string;

implementation

var
  GMode: TThemeMode = tmLight;
  GPalette: TPalette;
  GListeners: TList<TProc>;
  GIcons: TObjectDictionary<TIconKind, TPathData>;
  GUiFont, GMonoFont: string;

const
  IconPaths: array[TIconKind] of string = (
    { icCheck } 'M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
    { icStar } 'M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z',
    { icStarOff } 'M22 9.24l-7.19-.62L12 2 9.19 8.62 2 9.24l5.46 4.73L5.82 21 12 17.27 18.18 21l-1.63-7.03L22 9.24zM12 15.4l-3.76 2.27 1-4.28-3.32-2.88 4.38-.38L12 6.1l1.71 4.04 4.38.38-3.32 2.88 1 4.28L12 15.4z',
    { icChevronRight } 'M10 6 8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z',
    { icChevronDown } 'M16.59 8.59 12 13.17 7.41 8.59 6 10l6 6 6-6z',
    { icSearch } 'M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z',
    { icFolder } 'M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z',
    { icFolderOpen } 'M20 6h-8l-2-2H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 12H4V8h16v10z',
    { icEdit } 'M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z',
    { icRefresh } 'M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z',
    { icSun } 'M6.76 4.84l-1.8-1.79-1.41 1.41 1.79 1.79 1.42-1.41zM4 10.5H1v2h3v-2zm9-9.95h-2V3.5h2V.55zm7.45 3.91l-1.41-1.41-1.79 1.79 1.41 1.41 1.79-1.79zm-3.21 13.7l1.79 1.8 1.41-1.41-1.8-1.79-1.4 1.4zM20 10.5v2h3v-2h-3zm-8-5c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm-1 16.95h2V19.5h-2v2.95zm-7.45-3.91l1.41 1.41 1.79-1.8-1.41-1.41-1.79 1.8z',
    { icMoon } 'M9 2c-1.05 0-2.05.16-3 .46 4.06 1.27 7 5.06 7 9.54 0 4.48-2.94 8.27-7 9.54.95.3 1.95.46 3 .46 5.52 0 10-4.48 10-10S14.52 2 9 2z',
    { icMap } 'M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z',
    { icChecklist } 'M22 7h-9v2h9V7zm0 8h-9v2h9v-2zM5.54 11L2 7.46l1.41-1.41 2.12 2.12 4.24-4.24 1.41 1.41L5.54 11zm0 8L2 15.46l1.41-1.41 2.12 2.12 4.24-4.24 1.41 1.41L5.54 19z',
    { icDashboard } 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
    { icPlus } 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
    { icTrash } 'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    { icCopy } 'M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z',
    { icDownload } 'M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z',
    { icUpload } 'M9 16h6v-6h4l-7-7-7 7h4zm-4 2h14v2H5z',
    { icFlag } 'M14.4 6L14 4H5v17h2v-7h5.6l.4 2h7V6z',
    { icClose } 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
    { icPlay } 'M8 5v14l11-7z',
    { icFile } 'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
    { icBrowse } 'M20 6h-8l-2-2H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 12H4V8h16v10z',
    { icExport } 'M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z',
    { icBrackets } 'M15,4V6H18V18H15V20H20V4M4,4V20H9V18H6V6H9V4H4Z',
    { icChart } 'M5 9.2h3V19H5V9.2zM10.6 5h2.8v14h-2.8V5zm5.6 8H19v6h-2.8v-6z',
    { icMinus } 'M19 13H5v-2h14v2z',
    { icGraph } 'M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z'
  );

function Pal: TPalette;
begin
  Result := GPalette;
end;

function ThemeMode: TThemeMode;
begin
  Result := GMode;
end;

procedure SetThemeMode(AMode: TThemeMode);
var
  H: TProc;
begin
  GMode := AMode;
  if AMode = tmDark then
    GPalette := DarkPalette
  else
    GPalette := LightPalette;
  for H in GListeners do
    H();
end;

procedure OnThemeChanged(AHandler: TProc);
begin
  GListeners.Add(AHandler);
end;

function SystemPrefersDark: Boolean;
var
  R: TRegistry;
begin
  Result := False;
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') then
      if R.ValueExists('AppsUseLightTheme') then
        Result := R.ReadInteger('AppsUseLightTheme') = 0;
  finally
    R.Free;
  end;
end;

procedure ApplyTitleBarTheme(AForm: TCommonCustomForm);
const
  DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
  DWMWA_CAPTION_COLOR = 35;
  DWMWA_TEXT_COLOR = 36;
var
  H: HWND;
  V: BOOL;
  C: COLORREF;
  function ToColorRef(AColor: TAlphaColor): COLORREF;
  begin
    Result := TAlphaColorRec(AColor).R or (TAlphaColorRec(AColor).G shl 8) or
      (TAlphaColorRec(AColor).B shl 16);
  end;
begin
  H := FormToHWND(AForm);
  if H = 0 then
    Exit;
  V := GMode = tmDark;
  DwmSetWindowAttribute(H, DWMWA_USE_IMMERSIVE_DARK_MODE, @V, SizeOf(V));
  C := ToColorRef(GPalette.Bg);           // Windows 11: barra de titulo com a cor de fundo
  DwmSetWindowAttribute(H, DWMWA_CAPTION_COLOR, @C, SizeOf(C));
  C := ToColorRef(GPalette.Text);
  DwmSetWindowAttribute(H, DWMWA_TEXT_COLOR, @C, SizeOf(C));
end;

function EnumFontProc(var LogFont: TLogFont; var TextMetric: TTextMetric; FontType: DWORD;
  Data: LPARAM): Integer; stdcall;
begin
  PBoolean(Data)^ := True;
  Result := 0;
end;

function FontInstalled(const AName: string): Boolean;
var
  DC: HDC;
  LF: TLogFont;
begin
  Result := False;
  DC := GetDC(0);
  try
    FillChar(LF, SizeOf(LF), 0);
    LF.lfCharSet := DEFAULT_CHARSET;
    StrPLCopy(LF.lfFaceName, AName, LF_FACESIZE - 1);
    EnumFontFamiliesEx(DC, LF, @EnumFontProc, LPARAM(@Result), 0);
  finally
    ReleaseDC(0, DC);
  end;
end;

function Pick(ACond: Boolean; AIfTrue, AIfFalse: TAlphaColor): TAlphaColor;
begin
  if ACond then Result := AIfTrue else Result := AIfFalse;
end;

function UiFont: string;
begin
  Result := GUiFont;
end;

function MonoFont: string;
begin
  Result := GMonoFont;
end;

procedure DrawIcon(ACanvas: TCanvas; AKind: TIconKind; const ARect: TRectF; AColor: TAlphaColor;
  AOpacity: Single);
var
  P: TPathData;
  M: TMatrix;
  S: Single;
begin
  S := Min(ARect.Width, ARect.Height) / 24;
  P := TPathData.Create;
  try
    P.Assign(GIcons[AKind]);
    M := TMatrix.CreateScaling(S, S) *
      TMatrix.CreateTranslation(ARect.Left + (ARect.Width - 24 * S) / 2,
        ARect.Top + (ARect.Height - 24 * S) / 2);
    P.ApplyMatrix(M);
    ACanvas.Fill.Kind := TBrushKind.Solid;
    ACanvas.Fill.Color := AColor;
    ACanvas.FillPath(P, AOpacity);
  finally
    P.Free;
  end;
end;

procedure FillRound(ACanvas: TCanvas; const ARect: TRectF; ARadius: Single; AColor: TAlphaColor);
begin
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;
  ACanvas.FillRect(ARect, ARadius, ARadius, AllCorners, 1);
end;

procedure StrokeRound(ACanvas: TCanvas; const ARect: TRectF; ARadius: Single; AColor: TAlphaColor;
  AThickness: Single);
var
  R: TRectF;
begin
  R := ARect;
  R.Inflate(-AThickness / 2, -AThickness / 2);     // traco nitido dentro da caixa
  ACanvas.Stroke.Kind := TBrushKind.Solid;
  ACanvas.Stroke.Color := AColor;
  ACanvas.Stroke.Thickness := AThickness;
  ACanvas.Stroke.Dash := TStrokeDash.Solid;
  ACanvas.DrawRect(R, ARadius, ARadius, AllCorners, 1);
end;

procedure DrawTextRect(ACanvas: TCanvas; const ARect: TRectF; const AText: string;
  AColor: TAlphaColor; ASize: Single; const AFamily: string; AStyle: TFontStyles;
  AHAlign, AVAlign: TTextAlign);
begin
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := AColor;
  ACanvas.Font.Family := AFamily;
  ACanvas.Font.Size := ASize;
  ACanvas.Font.Style := AStyle;
  ACanvas.FillText(ARect, AText, False, 1, [], AHAlign, AVAlign);
end;

function MeasureText(const AText: string; ASize: Single; const AFamily: string;
  AStyle: TFontStyles): Single;
var
  C: TCanvas;
begin
  C := TCanvasManager.MeasureCanvas;
  C.Font.Family := AFamily;
  C.Font.Size := ASize;
  C.Font.Style := AStyle;
  Result := C.TextWidth(AText);
end;

{ Corta o texto com reticencias para caber em AMaxWidth (a fonte ja deve estar definida em ACanvas) }
function FitText(ACanvas: TCanvas; const AText: string; AMaxWidth: Single): string;
var
  Lo, Hi, Mid: Integer;
begin
  if (AMaxWidth <= 0) or (AText = '') then
    Exit('');
  if ACanvas.TextWidth(AText) <= AMaxWidth then
    Exit(AText);
  Lo := 0;
  Hi := Length(AText);
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if ACanvas.TextWidth(Copy(AText, 1, Mid) + '…') <= AMaxWidth then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  Result := Copy(AText, 1, Lo) + '…';
end;

procedure InitTheme;
var
  K: TIconKind;
  P: TPathData;
begin
  GListeners := TList<TProc>.Create;
  GIcons := TObjectDictionary<TIconKind, TPathData>.Create([doOwnsValues]);
  for K := Low(TIconKind) to High(TIconKind) do
  begin
    P := TPathData.Create;
    P.Data := IconPaths[K];
    GIcons.Add(K, P);
  end;
  GUiFont := 'Segoe UI';
  if FontInstalled('Cascadia Code') then
    GMonoFont := 'Cascadia Code'
  else if FontInstalled('Cascadia Mono') then
    GMonoFont := 'Cascadia Mono'
  else
    GMonoFont := 'Consolas';
  GPalette := LightPalette;
end;

initialization
  InitTheme;

finalization
  GIcons.Free;
  GListeners.Free;

end.
