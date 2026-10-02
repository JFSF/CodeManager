unit CM.Pages.Host;

{ Contrato entre a janela principal e as paginas (Projeto, Mapa, Checklist).
  A janela guarda o estado partilhado (definicoes, projeto activo, analise, progresso) e coordena
  o que atravessa varias paginas; cada pagina so fala com a janela por esta interface. }

interface

uses
  CM.Analyzer, CM.Store, CM.History, CM.Plan;

type
  TPage = (pgProject, pgMap, pgChecklist, pgDashboard);

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

    procedure Toast(const AText: string);
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
  end;

implementation

end.
