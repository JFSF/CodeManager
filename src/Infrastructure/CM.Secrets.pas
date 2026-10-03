unit CM.Secrets;

{ Guarda segredos (como o token do SonarQube) sem os deixar em claro nos ficheiros de dados.

  Usa a protecao de dados do Windows (DPAPI): o texto cifrado so se decifra na mesma conta de utilizador
  e no mesmo computador. Copiar o ficheiro de definicoes para outro sitio nao leva o token. O resultado e
  texto ('dpapi:' + base64), por isso cabe num JSON. }

interface

uses
  System.SysUtils, System.NetEncoding, Winapi.Windows;

// protege APlain; '' devolve ''
function ProtectText(const APlain: string): string;
// o inverso; '' se ACipher estiver vazio, nao for valido ou tiver sido protegido por outra conta/computador
function UnprotectText(const ACipher: string): string;

implementation

type
  TCryptBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PCryptBlob = ^TCryptBlob;

function CryptProtectData(pDataIn: PCryptBlob; szDataDescr: LPCWSTR; pOptionalEntropy: PCryptBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PCryptBlob): BOOL; stdcall;
  external 'crypt32.dll';
function CryptUnprotectData(pDataIn: PCryptBlob; ppszDataDescr: PPWideChar; pOptionalEntropy: PCryptBlob;
  pvReserved: Pointer; pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PCryptBlob): BOOL; stdcall;
  external 'crypt32.dll';

const
  CRYPTPROTECT_UI_FORBIDDEN = $1;       // nunca abre janelas
  Prefix = 'dpapi:';
  EntropyText = 'CodeManager.Secrets.v1';       // mistura propria da aplicacao

function EntropyBlob(var ABytes: TBytes): TCryptBlob;
begin
  ABytes := TEncoding.UTF8.GetBytes(EntropyText);
  Result.cbData := Length(ABytes);
  Result.pbData := @ABytes[0];
end;

function ProtectText(const APlain: string): string;
var
  Plain, Entropy: TBytes;
  InBlob, EntBlob, OutBlob: TCryptBlob;
  Cipher: TBytes;
begin
  Result := '';
  if APlain = '' then
    Exit;
  Plain := TEncoding.UTF8.GetBytes(APlain);
  InBlob.cbData := Length(Plain);
  InBlob.pbData := @Plain[0];
  EntBlob := EntropyBlob(Entropy);
  if not CryptProtectData(@InBlob, nil, @EntBlob, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @OutBlob) then
    Exit;
  try
    SetLength(Cipher, OutBlob.cbData);
    Move(OutBlob.pbData^, Cipher[0], OutBlob.cbData);
  finally
    LocalFree(HLOCAL(OutBlob.pbData));
  end;
  Result := Prefix + TNetEncoding.Base64String.EncodeBytesToString(Cipher);
end;

function UnprotectText(const ACipher: string): string;
var
  Cipher, Entropy, Plain: TBytes;
  InBlob, EntBlob, OutBlob: TCryptBlob;
begin
  Result := '';
  if not ACipher.StartsWith(Prefix) then
    Exit;
  try
    Cipher := TNetEncoding.Base64String.DecodeStringToBytes(Copy(ACipher, Length(Prefix) + 1, MaxInt));
  except
    Exit;
  end;
  if Length(Cipher) = 0 then
    Exit;
  InBlob.cbData := Length(Cipher);
  InBlob.pbData := @Cipher[0];
  EntBlob := EntropyBlob(Entropy);
  if not CryptUnprotectData(@InBlob, nil, @EntBlob, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, @OutBlob) then
    Exit;
  try
    SetLength(Plain, OutBlob.cbData);
    if OutBlob.cbData > 0 then
      Move(OutBlob.pbData^, Plain[0], OutBlob.cbData);
    Result := TEncoding.UTF8.GetString(Plain);
  finally
    LocalFree(HLOCAL(OutBlob.pbData));
  end;
end;

end.
