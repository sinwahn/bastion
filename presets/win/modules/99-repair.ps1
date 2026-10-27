. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[repair] reinstalls Looking Glass, the virtio drivers, the installers on the stick and the NVIDIA app'
# Runs only on its word, run.cmd repair: run.ps1 leaves it out of a run with no words. It needs no
# internet. Each step and its result go to setup.log through Note, RunLogged, StartLogged and
# InstallLookingGlass of lib\common.ps1.
# Sources: windows-driver-docs 8bf796c7126ac13e8ef5f5d1013d0326dc9a0215 windows-driver-docs-pr (WDD);
# the virtio-win 0.1.285-1 ISO's own file listing (the ISO nixpkgs a033e66 pins); for Looking Glass,
# gnif/LookingGlass at cdba29f2f6bcae3ded26369fc231a067cbca3752 (LG) and the pages named in step 1.
$why = @()
$found = 0

# 1. Looking Glass, first, before the drivers and the installers: RestartPending (lib\common.ps1) then
# reads only what stood before this run. This run's own drivers and installers can make Windows report a
# pending restart; a step after them would wait in this run and again in every run the continued run
# starts, and a step right after a driver install of this run would reinstall Looking Glass before the
# restart that install needs. When assets\looking-glass-host.exe is not on the stick, nothing is
# uninstalled, deleted or installed. When a restart is pending the step waits: the module ends "waits for
# restart", and after the restart the continued run of run.ps1 starts run.cmd repair, which runs this
# module whole. Else, in this order:
# a. The devices of Looking Glass's driver packages and each one's INF, read before the uninstaller runs,
#    since the uninstaller runs LGIddInstall.exe uninstall (LG idd/installer.nsi 223): the devices of the
#    class Win32_PnPEntity (Get-CimInstance -ClassName, PowerShell-Docs 01f1236990533ae78f9db4a005524e10f7c34ce8
#    reference/5.1/CimCmdlets/Get-CimInstance.md 23, 243) whose HardwareID, the ids Setup matches a device
#    to an INF file by (MicrosoftDocs/win32 3f42ac423191be263920ddf69b1ae6c2975c81b0
#    desktop-src/CIMWin32Prov/win32-pnpentity.md 831-840), holds one of $deviceIds; each device's INF read by
#    Get-PnpDeviceProperty with its PNPDeviceID (win32-pnpentity.md 956-968) as InstanceId and the key name
#    DEVPKEY_Device_DriverInfPath (windows-powershell-docs 7bbbc0c2423a312fd77dd36aa4a0935b44632fd0
#    docset/winserver2022-ps/PnpDevice/Get-PnpDeviceProperty.md 14, 20, 166-194, Data 256-257): the name
#    of the INF file that installed the device, its OemNnn.inf copy (windows-driver-docs
#    c708f7b244f8d1f9dfbb35238226b08e44a8cf02 windows-driver-docs-pr/install/devpkey-device-driverinfpath.md
#    20, 62).
# b. The uninstaller that Windows' uninstall entry "Looking Glass (IDD)" names: the installer writes the
#    entry under HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall, its UninstallString the
#    uninstaller's path in double quotes (LG idd/installer.nsi 180-187), read with Get-ItemProperty
#    -LiteralPath -Name (PowerShell-Docs a008c4bde67b8245958b9f677edc68790b3d4e87
#    reference/5.1/Microsoft.PowerShell.Management/Get-ItemProperty.md 31, 182, 204). It runs through
#    StartLogged with /S, silently, and _?= with the uninstaller's own folder, last and with no quotes, so
#    it does not copy itself to the temporary directory and the process waited for is the uninstaller
#    itself (the NSIS manual's source, kichik/nsis 8f790b6d555eeedca351ce095bffb7b645c9cf8f
#    Docs/src/usage.but 92, 98, 110; Start-Process joins the arguments with spaces, StartLogged's sources).
#    With no entry the line says so and the step goes on.
# c. Each driver package found in a, once: pnputil /delete-driver INF /uninstall, which deletes it from
#    the driver store and uninstalls it from any devices using it (windows-driver-docs
#    154f765a1003031a576ffebc8ba759df566f7a89 windows-driver-docs-pr/devtest/pnputil-command-syntax.md
#    55, 58, 63), through RunLogged; 0 and 3010 count as success, each logged with its meaning
#    (windows-driver-docs 81d06fd79dd36cdd74ec0b3aeed6c4e52c2e2fc3
#    windows-driver-docs-pr/devtest/pnputil-return-values.md 12, 14).
# d. InstallLookingGlass of lib\common.ps1, which sets the restart mark after exit 0.
# The hardware ids the three INF files in the installer declare, as its files taken out of it hold them:
# LGIdd.inf 19 and 20 (the same in LG idd/LGIdd/LGIdd.inf), LGInput.inf 18, ivshmem.inf 47. A Looking
# Glass build with other ids leaves its packages in place until these change.
$deviceIds = @('Root\LGIdd', 'LGIdd', 'Root\LGInput', 'PCI\VEN_1AF4&DEV_1110&SUBSYS_11001AF4&REV_01', 'PCI\VEN_1AF4&DEV_1110')
$exe = Join-Path $BastionAssets 'looking-glass-host.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  Note '[repair] Looking Glass: assets\looking-glass-host.exe not found - not uninstalled, no driver package deleted, not installed'
} elseif (RestartPending) {
  $found++
  Note '[repair] Looking Glass: a restart is pending: waits for restart; after it the run goes on with repair by itself'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'waits for restart' }
} else {
  $found++
  Note '[repair] Looking Glass: reinstalling: its devices and driver packages, the uninstaller, the packages deleted, the install'
  $devices = @()
  try { $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { @($_.HardwareID | Where-Object { $deviceIds -contains $_ }).Count -gt 0 }) }
  catch { Note ('[repair] Looking Glass: FAILED to read the devices (Win32_PnPEntity): ' + $_.Exception.Message) }
  if ($devices.Count -eq 0) { Note '[repair] Looking Glass: no device has a hardware id of LGIdd.inf, LGInput.inf or ivshmem.inf - no driver package to delete' }
  $packages = @()
  foreach ($dev in $devices) {
    $inf = $null
    try { $inf = [string](Get-PnpDeviceProperty -InstanceId $dev.PNPDeviceID -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction Stop).Data }
    catch { Note ('[repair] Looking Glass: FAILED to read DEVPKEY_Device_DriverInfPath of ' + $dev.PNPDeviceID + ': ' + $_.Exception.Message) }
    if (-not $inf) { Note ('[repair] Looking Glass: ' + $dev.PNPDeviceID + ' has no driver INF - no package to delete for it'); continue }
    Note ('[repair] Looking Glass: ' + $dev.PNPDeviceID + ' uses the driver package ' + $inf)
    if ($packages -notcontains $inf) { $packages += $inf }
  }
  $uninstaller = $null
  try { $uninstaller = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Looking Glass (IDD)' -Name 'UninstallString' -ErrorAction Stop).UninstallString }
  catch { Note ('[repair] Looking Glass: no uninstall entry Looking Glass (IDD) with an UninstallString (' + $_.Exception.Message + ') - not uninstalled, the step goes on') }
  if ($uninstaller) {
    $path = $uninstaller.Trim().Trim('"')
    Note ('[repair] Looking Glass: uninstalling with ' + $path)
    [void](StartLogged $path @('/S', ('_?=' + (Split-Path -Parent $path))))
  }
  foreach ($inf in $packages) {
    Note ('[repair] Looking Glass: deleting the driver package ' + $inf)
    [void](RunLogged 'pnputil.exe' @('/delete-driver', $inf, '/uninstall') -Success @{
      0 = 'the requested operation completed successfully'
      3010 = 'the requested operation completed successfully and a system reboot is required'
    })
  }
  [void](InstallLookingGlass '[repair] ')
}

# 2. The virtio drivers from win\virtio on the stick, which attach.sh puts there from the bastion tool's
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

# 3. Each installer of assets\installers.json that is on the stick, started through StartLogged with the
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

# 4. The NVIDIA app when assets\nvidia-app.exe is on the stick, started as 90-nvidia starts it.
$app = Join-Path $BastionAssets 'nvidia-app.exe'
if (Test-Path -LiteralPath $app) {
  $found++
  Note '[repair] NVIDIA app: reinstalling'
  [void](StartLogged $app @('-s'))
} else { Note '[repair] assets\nvidia-app.exe not present - skipped' }

# 5. The restart mark, which run.ps1 reads at its end, when a driver or an installer asks for a restart.
if ($why.Count -gt 0) {
  try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note ('[repair] restart mark set: Windows needs a restart after ' + ($why -join ', ')) }
  catch { Note ('[repair] FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
} else { Note '[repair] no driver or installer asks for a restart' }
if ($found -eq 0) {
  Note '[repair] the stick holds no Looking Glass installer, no driver, no installer and no NVIDIA app - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
}
Note '[repair] done'
