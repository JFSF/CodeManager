# Gera src\Core\CM.Lang.Table.pas a partir de tools\i18n\translations.tsv
#   powershell -File tools\i18n\generate-lang-table.ps1
# Colunas (separadas por TAB): pt | en | fr | de. Linhas com # sao comentarios.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tsv = Join-Path $here 'translations.tsv'
$out = Join-Path $here '..\..\src\Core\CM.Lang.Table.pas'

# o Delphi nao aceita linhas com mais de 1023 caracteres: os textos longos partem-se em pedacos concatenados
function Quote([string]$s) {
  $max = 160
  if ($s.Length -le $max) { return "'" + $s.Replace("'", "''") + "'" }
  $parts = New-Object System.Collections.Generic.List[string]
  $i = 0
  while ($i -lt $s.Length) {
    $n = [Math]::Min($max, $s.Length - $i)
    if (($i + $n -lt $s.Length) -and [char]::IsHighSurrogate($s[$i + $n - 1])) { $n-- }
    $parts.Add("'" + $s.Substring($i, $n).Replace("'", "''") + "'")
    $i += $n
  }
  return "`n      " + ($parts -join "`n    + ")
}

$rows = New-Object System.Collections.Generic.List[string]
$htmlRows = New-Object System.Collections.Generic.List[string]
$seen = New-Object System.Collections.Generic.HashSet[string]
$seenHtml = New-Object System.Collections.Generic.HashSet[string]
$inHtml = $false
$n = 0
foreach ($line in [System.IO.File]::ReadAllLines($tsv, [System.Text.Encoding]::UTF8)) {
  $n++
  if ($line.StartsWith('#!html')) { $inHtml = $true; continue }
  if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
  $f = $line.Split("`t")
  if ($f.Count -ne 4) { throw "translations.tsv, linha ${n}: esperadas 4 colunas, ha $($f.Count)" }
  # atribuicao directa: um 'if' como expressao desdobraria o conjunto (e um conjunto vazio daria $null)
  if ($inHtml) { $target = $seenHtml } else { $target = $seen }
  if (-not $target.Add($f[0])) { throw "translations.tsv, linha ${n}: chave repetida '$($f[0])'" }
  # os espacos do inicio e do fim da chave (ex.: 'Gerado em: ') valem para as traducoes: os editores
  # costumam cortar os espacos do fim da linha, que na ultima coluna se perderiam
  $lead = $f[0].Substring(0, $f[0].Length - $f[0].TrimStart(' ').Length)
  $trail = $f[0].Substring($f[0].TrimEnd(' ').Length)
  for ($i = 1; $i -lt 4; $i++) { $f[$i] = $lead + $f[$i].Trim(' ') + $trail }
  $row = '  (' + (($f | ForEach-Object { Quote $_ }) -join ', ') + ')'
  if ($inHtml) { $htmlRows.Add($row) } else { $rows.Add($row) }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('unit CM.Lang.Table;' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('{ GERADO por tools\i18n\generate-lang-table.ps1 a partir de tools\i18n\translations.tsv - nao editar.' + "`n")
[void]$sb.Append('  Cada linha: portugues (a chave), ingles, frances, alemao. }' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('interface' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('const' + "`n")
[void]$sb.Append("  LangRows: array[0..$($rows.Count - 1)] of array[0..3] of string = (" + "`n")
[void]$sb.Append(($rows -join (",`n")) + "`n")
[void]$sb.Append('  );' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('  // trocos dos modelos HTML (res/templates), por ordem de leitura' + "`n")
[void]$sb.Append("  HtmlRows: array[0..$($htmlRows.Count - 1)] of array[0..3] of string = (" + "`n")
[void]$sb.Append(($htmlRows -join (",`n")) + "`n")
[void]$sb.Append('  );' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('implementation' + "`n")
[void]$sb.Append('' + "`n")
[void]$sb.Append('end.' + "`n")
# Delphi le ficheiros sem BOM como ANSI: gravar sempre em UTF-8 com BOM
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Host "$($rows.Count) traducoes -> $out"
