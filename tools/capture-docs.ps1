<#
.SYNOPSIS
  Regenera as imagens da documentacao (docs\images) com o CodeManager a analisar-se a si proprio.

.DESCRIPTION
  Usa o modo de desenvolvimento (--dev) das compilacoes Debug: arranca a aplicacao com uma pasta de
  dados temporaria (CODEMANAGER_DATA), um projecto "CodeManager" apontado a esta pasta e ao plano de
  demonstracao (tools\demo\plano-demo.md), e executa um guiao que navega pelas paginas e grava capturas.

  Em duas passagens:
    1. exporta a estrutura (JSON) para conhecer os ficheiros e metodos;
    2. semeia um progresso e um historico de DEMONSTRACAO e tira as capturas.

  O historico da evolucao e inventado (so serve para a imagem); o resto sao dados reais da analise.

.PARAMETER Exe
  Compilacao Debug da aplicacao. Por omissao: out\bin\Win64\Debug\CodeManager.exe (build.bat Debug Win64).

.PARAMETER Out
  Pasta onde gravar as imagens. Por omissao: docs\images.

.EXAMPLE
  .\build.bat Debug Win64
  .\tools\capture-docs.ps1
#>
param(
  [string]$Exe,
  [string]$Out
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Exe) { $Exe = Join-Path $Root 'out\bin\Win64\Debug\CodeManager.exe' }
if (-not $Out) { $Out = Join-Path $Root 'docs\images' }
if (-not (Test-Path $Exe)) { throw "Nao encontrei $Exe - compile primeiro: .\build.bat Debug Win64" }
if ($Root -match '\s') { throw "O caminho do repositorio nao pode ter espacos (o guiao --dev e passado na linha de comandos): $Root" }

$PlanFile = Join-Path $Root 'tools\demo\plano-demo.md'
$Work = Join-Path $Root 'tools\demo\.work'
$Data = Join-Path $Work 'appdata'
$Struct = Join-Path $Work 'estrutura.json'
New-Item -ItemType Directory -Force $Out | Out-Null

function Reset-Work {
  if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
  New-Item -ItemType Directory -Force $Data | Out-Null
}

function Write-Settings([bool]$WithPlan) {
  $project = @{
    id = 'demo'; name = 'CodeManager'; root = $Root; output = (Join-Path $Root 'docs\html')
    exclude = ''; plan = $(if ($WithPlan) { $PlanFile } else { '' }); watch = $false
    finalized = $false; finalizedAt = ''
  }
  $settings = @{ theme = 'light'; activeProject = 'demo'; openAfterExport = $false; projects = @($project) }
  $settings | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $Data 'settings.json') -Encoding utf8
}

# executa a aplicacao com um guiao --dev e espera que termine ({IMG} e {WORK} sao substituidos)
function Invoke-App([string]$Script) {
  $s = $Script.Replace('{IMG}', $Out).Replace('{WORK}', $Work)
  if ($s -match '\s') { throw "O guiao nao pode ter espacos: $s" }
  $env:CODEMANAGER_DATA = $Data
  $p = Start-Process -FilePath $Exe -ArgumentList @('--dev', $s) -WorkingDirectory $Work -PassThru
  if (-not $p.WaitForExit(240000)) { $p.Kill(); throw 'A aplicacao nao terminou a tempo.' }
  $log = Join-Path $Work 'dev.log'
  if (Test-Path $log) {
    $bad = Get-Content $log | Where-Object { $_ -match '^ERRO' }
    if ($bad) { throw "Falhou um passo do guiao:`n$($bad -join "`n")" }
  }
}

# ------------------------------------------------------------------ passagem 1: estrutura
Reset-Work
Write-Settings $false
Invoke-App 'wait:8;exportstruct:json,{WORK}\estrutura.json,1,0;quit'
$structure = Get-Content $Struct -Raw -Encoding utf8 | ConvertFrom-Json

$files = New-Object System.Collections.ArrayList
function Walk($nodes) {
  foreach ($n in $nodes) {
    if ($n.type -eq 'folder') { Walk $n.children }
    elseif ($n.type -eq 'file') { [void]$files.Add($n) }
  }
}
Walk $structure.tree
$totalFiles = [int]$structure.totals.files
$totalMethods = [int]$structure.totals.methods

# ------------------------------------------------------------------ progresso de demonstracao
# o progresso guarda cada conjunto de metodos como um objecto { nome: true }
function ToSet($names) {
  $set = [ordered]@{}
  foreach ($n in $names) { $set[[string]$n] = $true }
  $set
}
$oldCommit = $null
try { $oldCommit = (& git -C $Root rev-parse 'HEAD~8' 2>$null) } catch { }
$progress = [ordered]@{}
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$doneFiles = 0; $doneMethods = 0; $compilaFiles = 0; $sonarFiles = 0
foreach ($f in $files) {
  $names = @($f.methods | ForEach-Object { $_.name })
  if ($names.Count -eq 0) { continue }
  $p = $f.path
  $unit = [ordered]@{}
  if ($p -match '^src/(Core|Services|Infrastructure)/') {
    $unit.done = $true; $unit.compila = $true; $unit.ts = $ts
    $unit.m = ToSet $names; $unit.mc = ToSet $names
    $doneFiles++; $doneMethods += $names.Count; $compilaFiles++
    if ($p -match '^src/Core/') { $unit.sonar = $true; $unit.mq = ToSet $names; $sonarFiles++ }
  }
  elseif ($p -match '^src/UI/') {
    $part = @($names | Select-Object -First ([math]::Ceiling($names.Count * 0.6)))
    $unit.m = ToSet $part; $unit.mc = ToSet $part; $unit.compila = $true; $compilaFiles++
    $doneMethods += $part.Count
    # estados de revisao de demonstracao: o primeiro metodo por rever fica "em revisao" e, em dois
    # ficheiros, o segundo "precisa de alteracao"
    $rest = @($names | Select-Object -Skip $part.Count)
    if ($rest.Count -gt 0) { $unit.mw = ToSet @($rest[0]) }
    if ($rest.Count -gt 1 -and $p -match 'CM\.(Pages\.Dashboard|MainForm)\.pas$') { $unit.mf = ToSet @($rest[1]) }
  }
  if ($p -match 'CM\.(Analyzer|Plan|MainForm)\.pas$') { $unit.star = $true }
  # revisoes de demonstracao feitas num commit antigo: como os ficheiros mudaram desde entao, aparecem "ALTERADO"
  if ($oldCommit -and $p -match '^src/Core/CM\.(Analyzer|Plan|Store)\.pas$') { $unit.rc = $oldCommit }
  if ($p -match 'CM\.TreeList\.pas$') { $unit.note = 'Rever o desenho das linhas do Mapa' }
  if ($unit.Count -gt 0) { $progress[$p] = $unit }
}
$progress | ConvertTo-Json -Depth 6 -Compress | Set-Content (Join-Path $Data 'progress-demo.json') -Encoding utf8

# historico de DEMONSTRACAO: 24 dias a subir ate perto dos valores de hoje
$days = 24
$snaps = @()
for ($k = 0; $k -lt $days; $k++) {
  $t = ($k + 1) / ($days + 1)
  $ease = [math]::Pow($t, 1.25)
  $snaps += [ordered]@{
    date = (Get-Date).AddDays($k - $days).ToString('yyyy-MM-dd')
    files = [math]::Max(1, $totalFiles - [math]::Floor(($days - $k) / 3))
    doneFiles = [math]::Floor($doneFiles * $ease)
    methods = [math]::Max(1, $totalMethods - 3 * ($days - $k))
    doneMethods = [math]::Floor($doneMethods * $ease)
    filesCompila = [math]::Floor($compilaFiles * [math]::Pow($t, 1.1))
    filesSonar = [math]::Floor($sonarFiles * [math]::Pow($t, 1.4))
    methodsCompila = 0; methodsSonar = 0
  }
}
[ordered]@{ version = 1; snapshots = $snaps } | ConvertTo-Json -Depth 6 |
  Set-Content (Join-Path $Data 'history-demo.json') -Encoding utf8

# ------------------------------------------------------------------ passagem 2: capturas
Write-Settings $true
$steps = @(
  'wait:8'
  'shot:{IMG}\01-projeto.png'
  'size:1344,1500;wait:2;shot:{IMG}\12-projeto-sonarqube.png;size:1344,821;wait:1'
  'page:1;wait:1;shot:{IMG}\02-mapa.png'
  'search:CM.P;wait:1;shot:{IMG}\03-mapa-plano.png'
  'search:CM.Metrics;wait:1;click:1080,686;wait:1;shot:{IMG}\10-mapa-metricas.png;click:1230,686;wait:1'
  'search:;page:2;wait:1;shot:{IMG}\04-checklist.png'
  'search:CM.Pages.Dashboard;wait:1;click:860,223;wait:1;shot:{IMG}\11-checklist-estados.png;click:860,223;wait:1;search:;wait:1'
  'page:3;wait:2;shot:{IMG}\05-painel.png'
  'size:1344,3200;wait:2;shot:{IMG}\06-painel-completo.png'
  'size:1344,821;wait:1'
  'page:4;wait:4;click:1070,117;wait:1;shot:{IMG}\13-grafo.png'
  'code:src/Core/CM.Highlight.pas#FindRoutineLine;wait:2;shot:{IMG}\14-codigo.png'
  'theme:dark;wait:2;shot:{IMG}\07-painel-escuro.png'
  'page:2;wait:1;shot:{IMG}\08-checklist-escuro.png'
  'page:1;wait:1;shot:{IMG}\09-mapa-escuro.png'
  'theme:light;size:1344,821;wait:1;sonardemo;wait:1;code:src/Core/CM.Highlight.pas#LineDefines;wait:2;shot:{IMG}\15-codigo-sonar.png'
  'page:3;wait:2;size:1344,3600;wait:2;shot:{IMG}\16-painel-sonar.png'
  'theme:light;size:1344,1010;page:7;wait:2;shot:{IMG}\19-acerca.png'
  'theme:light;size:1344,1180;page:6;wait:2;shot:{IMG}\17-aspeto.png'
  'click:324,269;wait:1;theme:dark;wait:2;shot:{IMG}\18-aspeto-escuro.png'
  'quit'
)
Invoke-App ($steps -join ';')

# ------------------------------------------------------------------ imagem principal (3 paginas lado a lado)
Add-Type -AssemblyName System.Drawing
$names = '04-checklist.png', '05-painel.png'
$imgs = $names | ForEach-Object { [System.Drawing.Image]::FromFile((Join-Path $Out $_)) }
$w = 700; $gap = 24; $pad = 28
$h = [int]($imgs[0].Height * $w / $imgs[0].Width)
$bmp = New-Object System.Drawing.Bitmap (2 * $pad + 2 * $w + $gap), (2 * $pad + $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(238, 240, 235))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(205, 208, 200)), 1
for ($i = 0; $i -lt 2; $i++) {
  $x = $pad + $i * ($w + $gap)
  $g.DrawImage($imgs[$i], $x, $pad, $w, $h)
  $g.DrawRectangle($pen, $x, $pad, $w - 1, $h - 1)
}
$g.Dispose(); $pen.Dispose()
$imgs | ForEach-Object { $_.Dispose() }
$bmp.Save((Join-Path $Out 'hero.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Remove-Item $Work -Recurse -Force
Write-Host "Imagens gravadas em $Out"
Get-ChildItem $Out -Filter *.png | ForEach-Object { '{0,-28} {1,7:N0} KB' -f $_.Name, ($_.Length / 1KB) }
