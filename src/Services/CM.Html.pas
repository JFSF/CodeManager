unit CM.Html;

{ Exportacao das paginas HTML offline (checklist interactiva e mapa de codigo).
  Os modelos HTML sao os dos scripts originais, embutidos como recursos (CM.Resources);
  aqui apenas se substituem os marcadores __XXX__ pelos dados do projecto. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  CM.Analyzer, CM.Store, CM.Resources;

function ChecklistOutputPath(AProfile: TProjectProfile): string;
function MapOutputPath(AProfile: TProjectProfile): string;

procedure ExportChecklistHtml(AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOutputPath: string);
procedure ExportMapHtml(AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOutputPath: string);

implementation


uses
  CM.Lang;
{ Escapa texto para uma string JSON dentro de um <script> }
function JsonString(const AText: string): string;
var
  SB: TStringBuilder;
  C: Char;
  I: Integer;
begin
  SB := TStringBuilder.Create(Length(AText) + 2);
  try
    SB.Append('"');
    for I := 1 to Length(AText) do
    begin
      C := AText[I];
      case C of
        '\': SB.Append('\\');
        '"': SB.Append('\"');
        #13: ;
        #10: SB.Append('\n');
        #9: SB.Append(' ');
        '/': if (I > 1) and (AText[I - 1] = '<') then SB.Append('\/') else SB.Append('/');
      else
        if C < ' ' then
          SB.Append('\u').Append(IntToHex(Ord(C), 4))
        else
          SB.Append(C);
      end;
    end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function HtmlText(const AText: string): string;
begin
  Result := AText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;');
end;

function JsText(const AText: string): string;
begin
  Result := AText.Replace('\', '\\').Replace('"', '\"').Replace('</', '<\/');
end;

function FilesJson(AScan: TProjectScan): string;
var
  SB: TStringBuilder;
  U: TUnitInfo;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    First := True;
    for U in AScan.Units do
    begin
      if not First then
        SB.Append(',');
      First := False;
      SB.Append(JsonString(U.Path));
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function MethodsJson(AScan: TProjectScan): string;
var
  SB: TStringBuilder;
  U: TUnitInfo;
  M: TMethodInfo;
  FirstUnit, FirstMethod: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    FirstUnit := True;
    for U in AScan.Units do
    begin
      if Length(U.Methods) = 0 then
        Continue;
      if not FirstUnit then
        SB.Append(',');
      FirstUnit := False;
      SB.Append(JsonString(U.Path)).Append(':[');
      FirstMethod := True;
      for M in U.Methods do
      begin
        if not FirstMethod then
          SB.Append(',');
        FirstMethod := False;
        SB.Append('{"name":').Append(JsonString(M.Name))
          .Append(',"kind":').Append(JsonString(M.Kind))
          .Append(',"sig":').Append(JsonString(M.Sig)).Append('}');
      end;
      SB.Append(']');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ExcludedNote(AScan: TProjectScan): string;
var
  S, Dir: string;
begin
  S := '';
  for Dir in AScan.ExcludeDirs do
  begin
    if S <> '' then
      S := S + '</code>, <code>';
    S := S + HtmlText(Dir);
  end;
  Result := Tr('As pastas <code>') + S + Tr('</code> foram ignoradas nesta análise ') +
    Tr('(dependências de terceiros, artefactos de build ou cópias de segurança do IDE) — ') +
    Tr('não são código próprio.');
end;

procedure WriteOutput(const AOutputPath, AHtml: string);
var
  Dir: string;
begin
  Dir := TPath.GetDirectoryName(AOutputPath);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(AOutputPath, AHtml, TUTF8Encoding.Create(False));
end;

function ChecklistOutputPath(AProfile: TProjectProfile): string;
begin
  Result := TPath.Combine(AProfile.OutputFolder, SlugOf(AProfile.Name) + '-checklist-codigo-fonte.html');
end;

function MapOutputPath(AProfile: TProjectProfile): string;
begin
  Result := TPath.Combine(AProfile.OutputFolder, SlugOf(AProfile.Name) + '-estrutura-codigo.html');
end;

procedure ExportChecklistHtml(AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOutputPath: string);
var
  Html, Slug: string;
begin
  Slug := SlugOf(AProfile.Name);
  Html := LoadTextResource('TPL_CHECKLIST');
  Html := Html.Replace('__EXCLUDED_NOTE__', ExcludedNote(AScan));
  Html := Html.Replace('__STORAGE_KEY__', 'checklist-' + Slug + '-v1');
  Html := Html.Replace('__GENERATED_DATE__', FormatDateTime('yyyy-mm-dd', Now));
  Html := Html.Replace('__EXPORT_SLUG__', Slug);
  Html := Html.Replace('__PROJECT_NAME_JS__', JsText(AProfile.Name));
  Html := Html.Replace('__PROJECT_NAME__', HtmlText(AProfile.Name));
  Html := Html.Replace('__ROOT_DISPLAY_JS__', JsText(AScan.Root));
  Html := Html.Replace('__ROOT_DISPLAY__', HtmlText(AScan.Root));
  Html := Html.Replace('__FILES_JSON__', FilesJson(AScan));
  Html := Html.Replace('__METHODS_JSON__', MethodsJson(AScan));
  Html := Html.Replace('__SEED_STATE__', AState.ToJSONString.Replace('</', '<\/'));
  WriteOutput(AOutputPath, Html);
end;

procedure ExportMapHtml(AProfile: TProjectProfile; AScan: TProjectScan;
  AState: TProgressState; const AOutputPath: string);
var
  Html, Slug, Stamp, Banner: string;
begin
  Slug := SlugOf(AProfile.Name);
  Stamp := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  Banner := '';
  if AProfile.Finalized then
    Banner := Tr('<div class="finalized-banner">&#10003; PROJECTO FINALIZADO em ') +
      AProfile.FinalizedAt + '</div>';
  Html := LoadTextResource('TPL_MAP');
  Html := Html.Replace('__EXCLUDED_NOTE__', ExcludedNote(AScan));
  Html := Html.Replace('__STORAGE_KEY__', 'mapa-codigo-' + Slug + '-v1');
  Html := Html.Replace('__GENERATED_DATE__', Stamp);
  Html := Html.Replace('__FINALIZED_BANNER__', Banner);
  Html := Html.Replace('__PROJECT_NAME__', HtmlText(AProfile.Name));
  Html := Html.Replace('__ROOT_DISPLAY__', HtmlText(AScan.Root));
  Html := Html.Replace('__FILES_JSON__', FilesJson(AScan));
  Html := Html.Replace('__METHODS_JSON__', MethodsJson(AScan));
  Html := Html.Replace('__SEED_STATE__', AState.ToJSONString.Replace('</', '<\/'));
  WriteOutput(AOutputPath, Html);
end;

end.
