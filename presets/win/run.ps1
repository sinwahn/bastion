# Bastion module runner. Called by run.cmd (elevated). Runs modules in order,
# or only those whose name contains one of the given words: run.cmd firefox nvidia
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Only)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:BASTION_ROOT = $root
. (Join-Path $root 'lib\common.ps1')
Remove-Item -LiteralPath $BastionRestart -Force -ErrorAction SilentlyContinue
$modDir = Join-Path $root 'modules'
$mods = Get-ChildItem -Path $modDir -Filter '*.ps1' | Sort-Object Name
if ($Only -and $Only.Count -gt 0) {
  $mods = $mods | Where-Object { $n = $_.BaseName; ($Only | Where-Object { $n -like ('*' + $_ + '*') }).Count -gt 0 }
}
Write-Host ('Bastion setup - running ' + $mods.Count + ' module(s):')
$mods | ForEach-Object { Write-Host ('  ' + $_.BaseName) }
foreach ($m in $mods) {
  Write-Host ''
  Write-Host ('>>> ' + $m.BaseName)
  try { & $m.FullName } catch { Write-Host ('MODULE ERROR ' + $m.BaseName + ': ' + $_.Exception.Message) }
}
Write-Host ''
Write-Host 'Restarting Explorer to apply shell changes...'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $BastionRestart) { Write-Host 'Restart Windows to finish this setup.' }
