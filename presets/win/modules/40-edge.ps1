. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[edge] removing Microsoft Edge if present'
# Edge's own setup.exe is started as before, by the call operator with its output discarded; its
# command line is logged before it and its exit code ($LASTEXITCODE) after it, as StartLogged logs them.
$edgeRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
$setup = $null
if (Test-Path -LiteralPath $edgeRoot) { $setup = Get-ChildItem -LiteralPath $edgeRoot -Recurse -Filter setup.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*\Installer\setup.exe' } | Select-Object -First 1 }
if ($null -ne $setup) {
  SetV $HKLM 'SOFTWARE\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
  Note ('start: ' + $setup.FullName + ' --uninstall --system-level --force-uninstall')
  try {
    & $setup.FullName '--uninstall' '--system-level' '--force-uninstall' 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $text = [string]$code + ' (0x' + ('{0:X8}' -f $code) + '): ' + $setup.FullName
    if ($code -eq 0) { Note ('exit ' + $text) } else { Note ('FAILED, exit ' + $text) }
  } catch { Note ('FAILED, could not start ' + $setup.FullName + ': ' + $_.Exception.Message) }
  Note '[edge] Edge: uninstall attempted'
} else {
  Note '[edge] Edge: not installed - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
}
Note '[edge] done'
