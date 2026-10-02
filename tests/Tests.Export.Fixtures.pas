unit Tests.Export.Fixtures;

// Scan de exemplo partilhado pelos testes de CM.Export.
//
// arvore:
//   Core/
//     Sub/
//       c.pas          (1 metodo: TC.Run)
//     a.pas             (2 metodos: TA.One, TA.Two)
//     b.pas             (0 metodos)
//   UI/
//     d.pas             (0 metodos)
//   root.pas             (0 metodos, na raiz)
//
// ordem esperada por FlattenStructure (pastas antes dos ficheiros da mesma pasta, tudo por
// ordem alfabetica; os ficheiros da raiz vem sempre no fim, como filhos da raiz):
//   Core, Core/Sub, Core/Sub/c.pas, Core/a.pas, Core/b.pas, UI, UI/d.pas, root.pas
//
// Folders = 3 (Core, Core/Sub, UI); Files = 5; TotalMethods = 3.

interface

uses
  CM.Analyzer, CM.Store, Tests.Helpers;

function BuildSampleScan: TProjectScan;
function NewProfile(const AName: string): TProjectProfile;

implementation

function BuildSampleScan: TProjectScan;
begin
  Result := NewScan(3, [
    MakeUnitInfo('Core/a.pas', 'Core', [Meth('TA.One', 'TA', 'One'), Meth('TA.Two', 'TA', 'Two')]),
    MakeUnitInfo('Core/b.pas', 'Core', []),
    MakeUnitInfo('Core/Sub/c.pas', 'Sub', [Meth('TC.Run', 'TC', 'Run')]),
    MakeUnitInfo('UI/d.pas', 'UI', []),
    MakeUnitInfo('root.pas', 'Raiz', [])]);
  Result.Root := 'C:\Proj';
  Result.ExcludeDirs := ['bin', 'obj'];
end;

function NewProfile(const AName: string): TProjectProfile;
begin
  Result := TProjectProfile.Create;
  Result.Name := AName;
end;

end.
