unit CM.Resources;

{ Acesso aos recursos embutidos no executavel (modelos HTML em templates.res). Isola aqui a
  API do Windows (HInstance, RT_RCDATA) para o resto da aplicacao nao depender dela. }

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows;

{$R templates.res}

// le um recurso RCDATA embutido (texto UTF-8)
function LoadTextResource(const AResName: string): string;

implementation

function LoadTextResource(const AResName: string): string;
var
  RS: TResourceStream;
  SS: TStringStream;
begin
  RS := TResourceStream.Create(HInstance, AResName, RT_RCDATA);
  try
    SS := TStringStream.Create('', TEncoding.UTF8);
    try
      SS.CopyFrom(RS, 0);
      Result := SS.DataString;
    finally
      SS.Free;
    end;
  finally
    RS.Free;
  end;
end;

end.
