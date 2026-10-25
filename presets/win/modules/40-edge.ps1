. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[edge] removing Microsoft Edge if present'
$edgeRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
$setup = $null
if (Test-Path -LiteralPath $edgeRoot) { $setup = Get-ChildItem -LiteralPath $edgeRoot -Recurse -Filter setup.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*\Installer\setup.exe' } | Select-Object -First 1 }
if ($null -ne $setup) {
  SetV $HKLM 'SOFTWARE\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
  & $setup.FullName '--uninstall' '--system-level' '--force-uninstall' 2>&1 | Out-Null
  Note 'Edge: uninstall attempted'
} else { Note 'Edge: not installed' }
Note '[edge] done'
