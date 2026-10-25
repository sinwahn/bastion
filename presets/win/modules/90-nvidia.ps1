. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[nvidia] NVIDIA app (the driver is installed by 75-installers)'
# For the VM that should have the NVIDIA app, put the NVIDIA app installer in assets\nvidia-app.exe;
# it installs only when that file is present. StartLogged of lib\common.ps1 starts it as before:
# Start-Process with -s, waited for, its exit code logged.
$app = Join-Path $BastionAssets 'nvidia-app.exe'
if (Test-Path -LiteralPath $app) {
  Note '[nvidia] installing NVIDIA app silently (the VM that should have the NVIDIA app)'
  [void](StartLogged $app @('-s'))
} else {
  Note '[nvidia] assets\nvidia-app.exe not present - staying driver-only, skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
}
Note '[nvidia] done'
