. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[lg-host] Looking Glass host install'
# attach.sh brings assets\looking-glass-host.exe, the Looking Glass host installer of the build looking-glass.nix pins
$exe = Join-Path $BastionAssets 'looking-glass-host.exe'
if (Test-Path -LiteralPath $exe) {
  try { $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru; Note ('[lg-host] installer exit ' + $p.ExitCode + ' (restart the VM to finish)') }
  catch { Note ('[lg-host] install failed: ' + $_.Exception.Message) }
} else { Note '[lg-host] assets\looking-glass-host.exe not found - skipped' }
Note '[lg-host] done'
