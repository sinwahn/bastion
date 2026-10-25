. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[repair] reinstalls the virtio drivers, the installers on the stick and the NVIDIA app'
# Runs only on its word, run.cmd repair: run.ps1 leaves it out of a run with no words. It needs no
# internet; Looking Glass is not touched. Each step and its result go to setup.log through Note, RunLogged
# and StartLogged of lib\common.ps1.
# Sources: windows-driver-docs 8bf796c7126ac13e8ef5f5d1013d0326dc9a0215 windows-driver-docs-pr (WDD);
# the virtio-win 0.1.285-1 ISO's own file listing (the ISO nixpkgs a033e66 pins).

# 1. The virtio drivers from win\virtio on the stick, which attach.sh puts there from the bastion tool's
# virtio-files: one folder per driver, each with the folders w10\amd64 and w11\amd64 as the ISO names them
# (qxldod with w10 alone); amd64, since the VMs are x86_64 (bastion.py's domain_xml). w11 from Windows 11's
# first build, 22000, as 97-exchange decides (WDD install/inf-manufacturer-section.md 99, 190-202; .NET's
# Environment.OSVersion). Each .inf installed with pnputil /add-driver INF /install, one INF at a time
# (WDD devtest/pnputil-command-syntax.md 40, 46; pnputil-return-values.md 17), through RunLogged; it
# installs the driver on every device it matches, and never forces it onto a device whose driver ranks as
# high (pnputil-command-syntax.md 49-50). The exit codes counted as success, each logged with its meaning
# (pnputil-return-values.md 12-14); 3010 asks for a restart.
$pnputilCodes = @{
  0 = 'the requested operation completed successfully'
  259 = 'no device matches the driver, or the device already uses a better or newer driver'
  3010 = 'the driver is installed, and Windows needs a restart to finish it'
}
$why = @()
$found = 0
$windows = 'w10'
if ([System.Environment]::OSVersion.Version.Build -ge 22000) { $windows = 'w11' }
$virtio = Join-Path $BastionRoot 'virtio'
if (-not (Test-Path -LiteralPath $virtio -PathType Container)) {
  Note '[repair] win\virtio not found on the stick (attach.sh NAME puts it there) - no driver installed'
} else {
  Note ('[repair] the drivers for ' + $windows + ' from ' + $virtio)
  foreach ($d in @(Get-ChildItem -LiteralPath $virtio -Directory | Sort-Object Name)) {
    $dir = Join-Path $d.FullName ($windows + '\amd64')
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
      Note ('[repair] ' + $d.Name + ': the virtio ISO holds no ' + $windows + ' folder for it - not installed')
      continue
    }
    foreach ($inf in @(Get-ChildItem -LiteralPath $dir -Filter '*.inf' | Sort-Object Name)) {
      $found++
      Note ('[repair] ' + $d.Name + ': installing ' + $inf.FullName)
      $code = RunLogged 'pnputil.exe' @('/add-driver', $inf.FullName, '/install') -Success $pnputilCodes
      if ($code -eq 3010) { $why += $d.Name }
    }
  }
}

# 2. Each installer of assets\installers.json that is on the stick, started through StartLogged with the
# switches installers.json gives, whatever version is installed now; asking first where the list says so,
# as 75-installers asks; restart in the list asks for a restart.
try { $list = Get-Content -LiteralPath (Join-Path $BastionAssets 'installers.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
catch {
  Note ('[repair] FAILED to read assets\installers.json: ' + $_.Exception.Message)
  $list = $null
}
if ($null -ne $list) {
  foreach ($e in @($list.installers)) {
    $setup = Join-Path $BastionAssets $e.file
    if (-not (Test-Path -LiteralPath $setup)) { Note ('[repair] ' + $e.name + ': assets\' + $e.file + ' not found - skipped'); continue }
    $found++
    if ($e.ask -and (Read-Host -Prompt ('Reinstall ' + $e.name + '? (y/n)')) -ne 'y') { Note ('[repair] ' + $e.name + ': not reinstalled (answered n)'); continue }
    Note ('[repair] ' + $e.name + ': reinstalling, whatever version is installed now')
    $code = StartLogged $setup @($e.switches)
    if ($null -ne $code -and $e.restart) { $why += $e.name }
  }
}

# 3. The NVIDIA app when assets\nvidia-app.exe is on the stick, started as 90-nvidia starts it.
$app = Join-Path $BastionAssets 'nvidia-app.exe'
if (Test-Path -LiteralPath $app) {
  $found++
  Note '[repair] NVIDIA app: reinstalling'
  [void](StartLogged $app @('-s'))
} else { Note '[repair] assets\nvidia-app.exe not present - skipped' }

# 4. The restart mark, which run.ps1 reads at its end, when a driver or an installer asks for a restart.
if ($why.Count -gt 0) {
  try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note ('[repair] restart mark set: Windows needs a restart after ' + ($why -join ', ')) }
  catch { Note ('[repair] FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
} else { Note '[repair] no driver or installer asks for a restart' }
if ($found -eq 0) {
  Note '[repair] the stick holds no driver, no installer and no NVIDIA app - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
}
Note '[repair] done'
