unit CM.Pages.Host;

{ Contrato entre a janela principal e as paginas (Projeto, Mapa, Checklist).
  A janela guarda o estado partilhado (definicoes, projeto activo, analise, progresso) e coordena
  o que atravessa varias paginas; cada pagina so fala com a janela por esta interface. }

interface

uses
  CM.Lang, CM.Analyzer, CM.Store, CM.History, CM.Plan, CM.SonarModel;

type
  // a ordem do enumerado e a dos indices do guiao --dev; a ordem na barra lateral esta em BuildRail
  TPage = (pgProject, pgMap, pgChecklist, pgDashboard, pgGraph);

  IPageHost = interface
    ['{6F1D3A52-8C47-4B0E-9E21-5A7C3D90B4E8}']
    function GetAppSettings: TAppSettings;
    function GetCurrentProfile: TProjectProfile;
    function GetCurrentScan: TProjectScan;
    function GetCurrentState: TProgressState;
    function GetCurrentHistory: THistory;
    function GetShuttingDown: Boolean;
    function GetHasPlan: Boolean;
    function GetPlanSummary: TPlanSummary;
    function GetCurrentPlanView: TProjectScan;
    function GetCurrentSonar: TSonarSnapshot;
    function GetSonarBusy: Boolean;
    function GetSonarMessage: string;

    procedure Toast(const AText: string);
    // muda o idioma da aplicacao: grava a escolha e reconstroi a interface (a analise recomeca)
    procedure SetLanguage(ALang: TLang);
    // volta a consultar o SonarQube (so se o utilizador o activou e o projecto tem chave); em segundo plano
    procedure RequestSonarRefresh;
    procedure MarkStateDirty;
    procedure MarkSettingsDirty;
    procedure ShowPage(APage: TPage);
    // troca o projecto activo (guarda o anterior, carrega o progresso, actualiza as paginas)
    procedure SelectProject(AProfile: TProjectProfile);
    // o projecto activo foi removido da lista: larga-o sem guardar o progresso
    procedure DetachProfile;
    // passa a ter uma nova analise (ou nenhuma) e recarrega as vistas. APlan e a analise do documento
    // do plano (nil sem plano); a janela fica dona de ambas
    procedure BindScan(AScan, APlan: TProjectScan);
    // recalcula as estatisticas mostradas em todas as paginas
    procedure UpdateAll;
    procedure UpdateHeader;
    // repoe as duas listas (Mapa e Checklist) a partir do estado actual
    procedure RefreshAllLists;
    // depois de o vigia reanalisar ficheiros: AFlashKeys = linhas a realcar
    procedure ScanChangesApplied(const AFlashKeys: TArray<string>);
    function ExportMapHtml(AQuiet: Boolean): Boolean;
    procedure ExportChecklistHtml;

    property AppSettings: TAppSettings read GetAppSettings;
    property CurrentProfile: TProjectProfile read GetCurrentProfile;
    property CurrentScan: TProjectScan read GetCurrentScan;
    property CurrentState: TProgressState read GetCurrentState;
    property CurrentHistory: THistory read GetCurrentHistory;
    property ShuttingDown: Boolean read GetShuttingDown;
    // ha um plano cruzado com o codigo (vista do Mapa com estados) e o resumo da comparacao
    property HasPlan: Boolean read GetHasPlan;
    property PlanSummary: TPlanSummary read GetPlanSummary;
    // a analise do codigo cruzada com o plano (nil sem plano); e de quem a janela, nao a liberte
    property CurrentPlanView: TProjectScan read GetCurrentPlanView;
    // o que o SonarQube disse na ultima consulta (nil sem Sonar ou se falhou); e da janela, nao a liberte
    property CurrentSonar: TSonarSnapshot read GetCurrentSonar;
    property SonarBusy: Boolean read GetSonarBusy;
    // o erro da ultima consulta ('' se correu bem) ou o estado enquanto decorre
    property SonarMessage: string read GetSonarMessage;
  end;

implementation

end.
