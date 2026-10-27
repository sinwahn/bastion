. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[lg-host] Looking Glass host install'
# attach.sh brings assets\looking-glass-host.exe, the Looking Glass host installer of the build looking-glass.nix pins
# The installer runs silently, with no window to click through, and is waited for (InstallLookingGlass of
# lib\common.ps1, which 99-repair calls too). It runs only in a boot with no restart pending (RestartPending
# of lib\common.ps1), so never right after a driver install.
$exe = Join-Path $BastionAssets 'looking-glass-host.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  Note '[lg-host] assets\looking-glass-host.exe not found - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
} elseif (RestartPending) {
  Note '[lg-host] a restart is pending: waits for restart; after it the run goes on with lg-host by itself'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'waits for restart' }
} else {
  [void](InstallLookingGlass '[lg-host] ')
}
Note '[lg-host] done'
