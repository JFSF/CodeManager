unit CM.Pages.About;

{ Pagina Acerca: o nome, a versao e a compilacao da aplicacao, o sistema, onde ficam os dados, as ligacoes (repositorio,
  novidades, reportar um problema) e os creditos. "Copiar informacao" poe um texto de diagnostico na area de
  transferencia, pronto para colar numa issue. }

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, System.Rtti, System.Math,
  FMX.Types, FMX.Controls, FMX.Platform, Winapi.Windows, Winapi.ShellAPI,
  CM.Theme, CM.Controls, CM.Layouts, CM.AppInfo, CM.SysInfo, CM.Store, CM.Lang, CM.Pages.Host;

type
  TAboutPage = class(TCMControl)
  private
    FHost: IPageHost;
    FScroll: TCMFadeScroll;
    FBody: TCMPanel;
    FCards: array[0..3] of TCMPanel;
    FVersionLabel: TCMLabel;
    FInfo: TCMKeyValue;
    FLinks: TCMButtonRow;
    procedure OpenUrl(const AUrl: string);
    procedure RepoClick(Sender: TObject);
    procedure ChangelogClick(Sender: TObject);
    procedure IssuesClick(Sender: TObject);
    procedure DataClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    function Collect: TAboutInfo;
    procedure Load;
    procedure FitCards;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost); reintroduce;
    procedure ApplyTheme;
    // a pagina passou a estar visivel: volta a ler o idioma, o tema e a pasta de dados
    procedure Activate;
  end;

implementation

const
  ThemeNames: array[TThemeMode] of string = ('claro', 'escuro');

function KV(const ACaption, AValue: string; AHighlight: Boolean = False): TKeyValue;
begin
  Result.Caption := ACaption;
  Result.Value := AValue;
  Result.Highlight := AHighlight;
end;

function IfThenYes(AValue: Boolean): string;
begin
  if AValue then Result := Tr('disponível') else Result := Tr('não encontrado');
end;

constructor TAboutPage.Create(AOwner: TComponent; AParent: TFmxObject; const AHost: IPageHost);
var
  Logo: TCMLogo;
  Head: TCMControl;
  Lbl: TCMLabel;
begin
  inherited Create(AOwner);
  FHost := AHost;
  Parent := AParent;
  Align := TAlignLayout.Client;
  Visible := False;

  FScroll := TCMFadeScroll.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := TAlignLayout.Client;
  FScroll.ShowScrollBars := False;
  FScroll.Padding.Right := 0;
  FBody := TCMPanel.Create(Self);
  FBody.Parent := FScroll;
  FBody.Align := TAlignLayout.Top;
  FBody.Role := prBg;
  FBody.Radius := 0;
  FBody.Bordered := False;
  FBody.Height := 900;

  // 1) cabecalho: o logotipo, o nome e a versao
  FCards[0] := NewCard(Self, FBody, 150);
  Logo := TCMLogo.Create(Self);
  Logo.Parent := FCards[0];
  Logo.Align := TAlignLayout.Left;
  Logo.Width := 92;
  Logo.Margins.Right := 22;
  Head := TCMControl.Create(Self);
  Head.Parent := FCards[0];
  Head.Align := TAlignLayout.Client;
  Lbl := TCMLabel.Make(Head, AppName, 30, True);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 44;
  Lbl.Margins.Top := 6;
  Lbl := TCMLabel.Make(Head, Tr('Mapa e checklist do código-fonte Delphi'), 14, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 24;
  FVersionLabel := TCMLabel.Make(Head, '', 14, True, lcAccentStrong, True);
  FVersionLabel.Align := TAlignLayout.Top;
  FVersionLabel.Height := 28;
  FVersionLabel.Margins.Top := 8;

  // 2) informacao
  FCards[1] := NewCard(Self, FBody, 380);
  TCMLabel.Make(FCards[1], Tr('Informação'), 15, True).Align := TAlignLayout.Top;
  FInfo := TCMKeyValue.Create(Self);
  FInfo.Parent := FCards[1];
  FInfo.Align := TAlignLayout.Top;
  FInfo.Margins.Top := 8;

  // 3) ligacoes
  FCards[2] := NewCard(Self, FBody, 150);
  TCMLabel.Make(FCards[2], Tr('Ligações'), 15, True).Align := TAlignLayout.Top;
  FLinks := NewButtonRow(Self, FCards[2]);
  FLinks.Margins.Top := 12;
  FLinks.Wrap := True;
  TCMButton.Make(FLinks, Tr('Repositório'), icExport, bkPrimary, RepoClick);
  TCMButton.Make(FLinks, Tr('Novidades'), icExport, bkSecondary, ChangelogClick);
  TCMButton.Make(FLinks, Tr('Reportar um problema'), icExport, bkSecondary, IssuesClick);
  TCMButton.Make(FLinks, Tr('Pasta de dados'), icFolderOpen, bkSecondary, DataClick);
  TCMButton.Make(FLinks, Tr('Copiar informação'), icCopy, bkSecondary, CopyClick);

  // 4) creditos
  FCards[3] := NewCard(Self, FBody, 240);
  TCMLabel.Make(FCards[3], Tr('Licença e créditos'), 15, True).Align := TAlignLayout.Top;
  Lbl := TCMLabel.Make(FCards[3], Tr('Distribuído sob a licença MIT. © 2026 João Ferreira.'), 12.5, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl.Margins.Top := 10;
  Lbl := TCMLabel.Make(FCards[3], Tr('Gráficos do Painel: Chart4D (MIT, GDK Software).'), 12.5, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl := TCMLabel.Make(FCards[3], Tr('Testes: DUnitX (Apache 2.0).'), 12.5, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl := TCMLabel.Make(FCards[3], Tr('Ícones: Material Design Icons (Apache 2.0).'), 12.5, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl := TCMLabel.Make(FCards[3], Tr('Mapa de dependências inspirado no DelphiNodeEditor (MIT, HemulGM).'), 12.5, False, lcDim);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl := TCMLabel.Make(FCards[3], Tr('Os avisos completos estão em THIRD-PARTY-NOTICES.md, no repositório.'), 12.5, False,
    lcFaint);
  Lbl.Align := TAlignLayout.Top;
  Lbl.Height := 22;
  Lbl.Margins.Top := 8;

  Load;
end;

procedure TAboutPage.ApplyTheme;
begin
  FInfo.Repaint;
  FVersionLabel.Repaint;
end;

procedure TAboutPage.Activate;
begin
  Load;
end;

procedure TAboutPage.Resize;
begin
  inherited;
  if FCards[0] <> nil then
    FitCards;
end;

procedure TAboutPage.FitCards;
begin
  FLinks.Relayout;
  FCards[2].Height := 18 + 18 + 28 + 12 + FLinks.Height + 8;
  FBody.Height := FCards[0].Height + FCards[1].Height + FCards[2].Height + FCards[3].Height + 4 * 16 + 8;
end;

function TAboutPage.Collect: TAboutInfo;
begin
  Result := CollectAboutInfo(LangCodes[CurrentLang], ThemeNames[ThemeMode], AppDataDir);
end;

procedure TAboutPage.Load;
var
  I: TAboutInfo;
begin
  I := Collect;
  FVersionLabel.Text := Tr('Versão ') + I.Version;
  FInfo.SetRows([
    KV(Tr('Versão'), I.Version),
    KV(Tr('Compilação'), I.BuildKind + ' · ' + I.PlatformName),
    KV(Tr('Compilado em'), I.BuildDate),
    KV(Tr('Compilador'), I.Compiler),
    KV(Tr('Sistema'), I.SystemName),
    KV(Tr('Idioma'), LangNames[CurrentLang]),
    KV(Tr('Git'), IfThenYes(I.GitAvailable)),
    KV(Tr('Subversion'), IfThenYes(I.SvnAvailable)),
    KV(Tr('Pasta de dados'), I.DataDir),
    KV(Tr('Licença'), LicenseName)]);
  FCards[1].Height := 16 + 16 + 28 + 8 + FInfo.Height + 14;
  FitCards;
end;

procedure TAboutPage.OpenUrl(const AUrl: string);
begin
  ShellExecute(0, 'open', PChar(AUrl), nil, nil, SW_SHOWNORMAL);
end;

procedure TAboutPage.RepoClick(Sender: TObject);
begin
  OpenUrl(RepoUrl);
end;

procedure TAboutPage.ChangelogClick(Sender: TObject);
begin
  OpenUrl(ChangelogUrl);
end;

procedure TAboutPage.IssuesClick(Sender: TObject);
begin
  OpenUrl(IssuesUrl);
end;

procedure TAboutPage.DataClick(Sender: TObject);
begin
  ForceDirectories(AppDataDir);
  ShellExecute(0, 'open', PChar(AppDataDir), nil, nil, SW_SHOWNORMAL);
end;

procedure TAboutPage.CopyClick(Sender: TObject);
var
  Svc: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Svc) then
  begin
    Svc.SetClipboard(TValue.From<string>(BuildAboutText(Collect)));
    FHost.Toast(Tr('Informação copiada'));
  end;
end;

end.
