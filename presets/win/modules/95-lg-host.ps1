. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[lg-host] Looking Glass host install'
# attach.sh brings assets\looking-glass-host.exe, the Looking Glass host installer of the build looking-glass.nix pins
# The installer runs silently, with no window to click through, and is waited for (StartLogged of
# lib\common.ps1). It runs only in a boot with no restart pending (RestartPending of lib\common.ps1), so
# never right after a driver install.
$exe = Join-Path $BastionAssets 'looking-glass-host.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  Note '[lg-host] assets\looking-glass-host.exe not found - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
} elseif (RestartPending) {
  Note '[lg-host] a restart is pending: waits for restart; after it the run goes on with lg-host by itself'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'waits for restart' }
} else {
  Note '[lg-host] Looking Glass requires cumulative updates from Windows, otherwise it will not work at all.'
  # /S: the NSIS manual, 3.2.1 Common Options (nsis.sourceforge.io/Docs/Chapter3.html), "/S runs the installer or uninstaller silently"; Looking Glass's doc/install_idd.rst 67-71 at cdba29f2 names it
  $code = StartLogged $exe @('/S')
  if ($null -eq $code) { Note '[lg-host] install FAILED: the installer could not be started' }
  elseif ($code -eq 0) {
    Note '[lg-host] installed'
    # The installer exits 0 whether or not Windows needs a restart for its drivers (gnif/LookingGlass at
    # cdba29f2f6bcae3ded26369fc231a067cbca3752 idd/installer.nsi 205-216; the NSIS manual, Appendix D.1,
    # "0 - Normal execution (no error)"), so the restart mark is set after exit 0.
    try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note '[lg-host] restart mark set: the display driver starts after the restart of Windows' }
    catch { Note ('[lg-host] FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
  }
  else { Note ('[lg-host] install FAILED, exit ' + $code + ' (0x' + ('{0:X8}' -f $code) + ')') }
}
Note '[lg-host] done'
