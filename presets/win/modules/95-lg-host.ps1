. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[lg-host] Looking Glass host install'
# attach.sh brings assets\looking-glass-host.exe, the Looking Glass host installer of the build looking-glass.nix pins
# The installer starts in its own normal window with no arguments, as a double-click starts it, and is
# waited for (StartLogged of lib\common.ps1); the user clicks through it. It runs only in a boot with no
# restart pending (RestartPending of lib\common.ps1), so never right after a driver install.
$exe = Join-Path $BastionAssets 'looking-glass-host.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  Note '[lg-host] assets\looking-glass-host.exe not found - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
} elseif (RestartPending) {
  Note '[lg-host] a restart is pending: waits for restart; after it the run goes on with lg-host by itself'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'waits for restart' }
} else {
  Note '[lg-host] starting the installer in its own window: click through it to its end'
  $code = StartLogged $exe @()
  if ($null -eq $code) { Note '[lg-host] install FAILED: the installer could not be started' }
  elseif ($code -eq 0) { Note '[lg-host] installed' }
  else { Note ('[lg-host] install FAILED, exit ' + $code + ' (0x' + ('{0:X8}' -f $code) + ')') }
}
Note '[lg-host] done'
