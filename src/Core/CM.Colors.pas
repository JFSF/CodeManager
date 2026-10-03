unit CM.Colors;

{ Cores para o aspecto da aplicacao, sem depender da interface: ler e escrever '#RRGGBB', converter para HSL e
  derivar, a partir de uma cor de destaque escolhida pelo utilizador, as quatro cores que o tema precisa (a cor, a
  forte, a suave e a do texto por cima), garantindo contraste legivel no tema claro e no escuro.

  As cores sao ARGB opacas ($FFRRGGBB), como TAlphaColor. }

interface

type
  TAccentSet = record
    Accent, Strong, Soft, OnAccent: Cardinal;
  end;

const
  // as cores prontas (nome, valor): a primeira e a original da aplicacao
  AccentPresetCount = 8;
  AccentPresetNames: array[0..AccentPresetCount - 1] of string = (
    'Verde', 'Azul', 'Indigo', 'Violeta', 'Rosa', 'Vermelho', 'Laranja', 'Grafite');
  AccentPresetColors: array[0..AccentPresetCount - 1] of Cardinal = (
    $FF23705F, $FF2563C9, $FF4A4FC4, $FF7C4DCB, $FFC2377F, $FFC13F2F, $FFB85C0B, $FF4B5563);

// '#23705F', '23705f' ou '#2A6' (3 digitos) -> $FF23705F; False se nao for uma cor
function ParseHexColor(const AText: string; out AColor: Cardinal): Boolean;
// $FF23705F -> '#23705F'
function ColorToHex(AColor: Cardinal): string;

procedure ColorToHsl(AColor: Cardinal; out H, S, L: Double);
function HslToColor(H, S, L: Double): Cardinal;
// mistura AFrom com ATo (AAmount 0 = AFrom, 1 = ATo)
function MixColors(AFrom, ATo: Cardinal; AAmount: Double): Cardinal;
// luminancia relativa (WCAG) de 0 a 1 e razao de contraste de 1 a 21
function RelativeLuminance(AColor: Cardinal): Double;
function ContrastRatio(AColor1, AColor2: Cardinal): Double;

// as cores do tema claro ou escuro para a cor de destaque escolhida. ASurface e o fundo dos cartoes desse tema
function DeriveAccent(ABase: Cardinal; ADark: Boolean; ASurface: Cardinal): TAccentSet;

implementation

uses
  System.SysUtils, System.Math;

function Channel(AColor: Cardinal; AShift: Integer): Integer; inline;
begin
  Result := (AColor shr AShift) and $FF;
end;

function Pack(R, G, B: Integer): Cardinal;
begin
  Result := $FF000000 or (Cardinal(EnsureRange(R, 0, 255)) shl 16) or (Cardinal(EnsureRange(G, 0, 255)) shl 8) or
    Cardinal(EnsureRange(B, 0, 255));
end;

function ParseHexColor(const AText: string; out AColor: Cardinal): Boolean;
var
  S: string;
  I: Integer;
  V: Cardinal;
begin
  Result := False;
  AColor := 0;
  S := Trim(AText);
  if S.StartsWith('#') then
    S := Copy(S, 2, MaxInt);
  if Length(S) = 3 then
    S := S[1] + S[1] + S[2] + S[2] + S[3] + S[3];
  if Length(S) <> 6 then
    Exit;
  for I := 1 to 6 do
    if not CharInSet(S[I], ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit;
  V := StrToUInt('$' + S);
  AColor := $FF000000 or V;
  Result := True;
end;

function ColorToHex(AColor: Cardinal): string;
begin
  Result := '#' + IntToHex(AColor and $FFFFFF, 6);
end;

procedure ColorToHsl(AColor: Cardinal; out H, S, L: Double);
var
  R, G, B, MaxC, MinC, D: Double;
begin
  R := Channel(AColor, 16) / 255;
  G := Channel(AColor, 8) / 255;
  B := Channel(AColor, 0) / 255;
  MaxC := Max(R, Max(G, B));
  MinC := Min(R, Min(G, B));
  L := (MaxC + MinC) / 2;
  D := MaxC - MinC;
  if D = 0 then
  begin
    H := 0;
    S := 0;
    Exit;
  end;
  if L > 0.5 then
    S := D / (2 - MaxC - MinC)
  else
    S := D / (MaxC + MinC);
  if MaxC = R then
    H := (G - B) / D + IfThen(G < B, 6, 0)
  else if MaxC = G then
    H := (B - R) / D + 2
  else
    H := (R - G) / D + 4;
  H := H * 60;
end;

function HueToRgb(P, Q, T: Double): Double;
begin
  if T < 0 then T := T + 1;
  if T > 1 then T := T - 1;
  if T < 1 / 6 then Exit(P + (Q - P) * 6 * T);
  if T < 1 / 2 then Exit(Q);
  if T < 2 / 3 then Exit(P + (Q - P) * (2 / 3 - T) * 6);
  Result := P;
end;

function HslToColor(H, S, L: Double): Cardinal;
var
  Q, P, HN: Double;
  R, G, B: Double;
begin
  S := EnsureRange(S, 0, 1);
  L := EnsureRange(L, 0, 1);
  if S = 0 then
  begin
    R := L; G := L; B := L;
  end
  else
  begin
    if L < 0.5 then Q := L * (1 + S) else Q := L + S - L * S;
    P := 2 * L - Q;
    HN := H / 360;
    HN := HN - Floor(HN);
    R := HueToRgb(P, Q, HN + 1 / 3);
    G := HueToRgb(P, Q, HN);
    B := HueToRgb(P, Q, HN - 1 / 3);
  end;
  Result := Pack(Round(R * 255), Round(G * 255), Round(B * 255));
end;

function MixColors(AFrom, ATo: Cardinal; AAmount: Double): Cardinal;
begin
  AAmount := EnsureRange(AAmount, 0, 1);
  Result := Pack(
    Round(Channel(AFrom, 16) + (Channel(ATo, 16) - Channel(AFrom, 16)) * AAmount),
    Round(Channel(AFrom, 8) + (Channel(ATo, 8) - Channel(AFrom, 8)) * AAmount),
    Round(Channel(AFrom, 0) + (Channel(ATo, 0) - Channel(AFrom, 0)) * AAmount));
end;

function RelativeLuminance(AColor: Cardinal): Double;

  function Lin(AValue: Integer): Double;
  var
    C: Double;
  begin
    C := AValue / 255;
    if C <= 0.03928 then Result := C / 12.92 else Result := Power((C + 0.055) / 1.055, 2.4);
  end;

begin
  Result := 0.2126 * Lin(Channel(AColor, 16)) + 0.7152 * Lin(Channel(AColor, 8)) + 0.0722 * Lin(Channel(AColor, 0));
end;

function ContrastRatio(AColor1, AColor2: Cardinal): Double;
var
  L1, L2: Double;
begin
  L1 := RelativeLuminance(AColor1);
  L2 := RelativeLuminance(AColor2);
  if L1 < L2 then
  begin
    Result := L1; L1 := L2; L2 := Result;
  end;
  Result := (L1 + 0.05) / (L2 + 0.05);
end;

function DeriveAccent(ABase: Cardinal; ADark: Boolean; ASurface: Cardinal): TAccentSet;
const
  White = $FFFFFFFF;
  Black = $FF0E1513;
  MinContrast = 4.5;
var
  H, S, L: Double;
  Color: Cardinal;
  Guard: Integer;
begin
  ColorToHsl(ABase, H, S, L);
  Color := ABase;
  Guard := 0;
  if ADark then
  begin
    // no tema escuro a cor sobe de luminosidade ate se ler bem sobre os cartoes
    while (ContrastRatio(Color, ASurface) < MinContrast) and (L < 0.92) and (Guard < 60) do
    begin
      L := L + 0.02;
      Color := HslToColor(H, S, L);
      Inc(Guard);
    end;
    Result.Accent := Color;
    Result.Strong := HslToColor(H, S, Min(0.95, L + 0.12));
    Result.Soft := MixColors(ASurface, Color, 0.16);
  end
  else
  begin
    // no tema claro desce ate o texto branco por cima ler bem (botoes cheios)
    while (ContrastRatio(Color, White) < MinContrast) and (L > 0.08) and (Guard < 60) do
    begin
      L := L - 0.02;
      Color := HslToColor(H, S, L);
      Inc(Guard);
    end;
    Result.Accent := Color;
    Result.Strong := HslToColor(H, S, Max(0.08, L * 0.68));
    Result.Soft := MixColors(White, Color, 0.12);
  end;
  if ContrastRatio(Result.Accent, White) >= ContrastRatio(Result.Accent, Black) then
    Result.OnAccent := White
  else
    Result.OnAccent := Black;
end;

end.
