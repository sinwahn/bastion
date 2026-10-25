. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[nvidia] NVIDIA app (the driver is installed by 75-installers)'
# For the VM that should have the NVIDIA app, put the NVIDIA app installer in assets\nvidia-app.exe;
# it installs only when that file is present.
$app = Join-Path $BastionAssets 'nvidia-app.exe'
if (Test-Path -LiteralPath $app) {
  Note '[nvidia] installing NVIDIA app silently (the VM that should have the NVIDIA app)'
  try { $p = Start-Process -FilePath $app -ArgumentList '-s' -Wait -PassThru; Note ('[nvidia] app installer exit ' + $p.ExitCode) }
  catch { Note ('[nvidia] app install failed: ' + $_.Exception.Message) }
} else { Note '[nvidia] assets\nvidia-app.exe not present - staying driver-only' }
Note '[nvidia] done'
