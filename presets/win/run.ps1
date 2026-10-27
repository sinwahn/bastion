# Bastion module runner. Called by run.cmd (elevated). Runs modules in order,
# or only those whose name contains one of the given words: run.cmd firefox nvidia
# The module repair (99-repair) runs only when one of the words is repair itself: run.cmd repair;
# a run with no words, or with words that are only part of it, leaves it out, and the start line says so.
# Every line it shows also goes to setup.log through Note: the run's start, Windows' product name,
# version and build (Win32_OperatingSystem Caption, Version, BuildNumber, read with Get-CimInstance),
# whether it runs elevated (WindowsPrincipal.IsInRole for the Administrators role, which is false in
# the standard-user token of User Account Control), the presets folder, the modules, each module's
# start and end with its result, one summary line per module, the RunOnce value written when a module
# waits for restart, and the answer to the restart question.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Only)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:BASTION_ROOT = $root
$global:BastionLogFailed = $false
$global:BastionModuleState = 'done'
. (Join-Path $root 'lib\common.ps1')
# The module word is the part of a module's name after the number and the dash, as 97-exchange reads its own.
$repairWord = 'repair'
$modDir = Join-Path $root 'modules'
$all = @(Get-ChildItem -Path $modDir -Filter '*.ps1' | Sort-Object Name)
$repair = @($all | Where-Object { ($_.BaseName -replace '^[0-9]+-', '') -eq $repairWord })
$withRepair = @($Only | Where-Object { $_ -eq $repairWord }).Count -gt 0
$repairNames = ($repair | ForEach-Object { $_.BaseName }) -join ', '
if ($withRepair) { $repairState = ', ' + $repairNames + ' runs' }
else { $repairState = ', ' + $repairNames + ' left out (run.cmd ' + $repairWord + ' runs it)' }
Note ('==== run start ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + $repairState)
try {
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  Note ('Windows: ' + ([string]$os.Caption).Trim() + ', version ' + $os.Version + ', build ' + $os.BuildNumber)
} catch { Note ('FAILED to read the Windows product name, version and build: ' + $_.Exception.Message) }
$me = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if ($me.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { Note 'elevated: yes' } else { Note 'elevated: no' }
Note ('presets folder: ' + $root)
Remove-Item -LiteralPath $BastionRestart -Force -ErrorAction SilentlyContinue
$mods = @($all | Where-Object { ($_.BaseName -replace '^[0-9]+-', '') -ne $repairWord })
if ($Only -and $Only.Count -gt 0) {
  $mods = @($mods | Where-Object { $n = $_.BaseName; ($Only | Where-Object { $n -like ('*' + $_ + '*') }).Count -gt 0 })
}
if ($withRepair) { $mods = @(@($mods) + $repair | Sort-Object Name) }
Note ('modules to run (' + $mods.Count + '): ' + (($mods | ForEach-Object { $_.BaseName }) -join ', '))
$summary = @()
# The end state of a module whose work needs a Windows that has restarted while a restart is pending
# (RestartPending of lib\common.ps1); the words of the modules that end in it are what the run goes on with.
$waits = 'waits for restart'
$waited = @()
foreach ($m in $mods) {
  $global:BastionModuleState = 'done'
  Note ('start ' + $m.BaseName)
  try {
    & $m.FullName
    Note ('end ' + $m.BaseName + ': ' + $global:BastionModuleState)
  } catch {
    $global:BastionModuleState = 'failed'
    Note ('end ' + $m.BaseName + ': failed: ' + $_.Exception.Message)
  }
  $summary += ($m.BaseName + ' ' + $global:BastionModuleState)
  if ($global:BastionModuleState -eq $waits) { $waited += ($m.BaseName -replace '^[0-9]+-', '') }
}
foreach ($s in $summary) { Note ('summary: ' + $s) }
Note 'Restarting Explorer to apply shell changes...'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
# When a module waited: Windows' RunOnce value Bastion, the name of the setup's own folder under ProgramData,
# so the run goes on with the words of the modules that waited, and nothing else, at the next sign-in of a
# member of Administrators after the restart. Its command line finds the stick by its volume label PRESETS,
# which attach.sh gives it, and starts run.cmd in this run's own folder, its drive taken off; run.cmd
# elevates itself as always. Sources: learn.microsoft.com windows/win32/setupapi/run-and-runonce-registry-keys
# (MicrosoftDocs/win32 6bd370f8857e5f2a175c6a33b9ef68914babaa80
# desktop-src/SetupApi/run-and-runonce-registry-keys.md): a command line no longer than 260 characters 14,
# the key 19, HKLM's RunOnce runs only when members of the Administrators group log on after the reboot 24,
# the value deleted before the command line is run 27. Get-Volume -FileSystemLabel (windows-powershell-docs
# 0ef3f225d29e26d1cf3119f37dfff70bb6165746 docset/winserver2022-ps/Storage/Get-Volume.md 45, 226-227), its
# DriveLetter a Char16 (MSFT_Volume, windows-driver-docs b00125b36af8eba737e1382456bdd2f7be9c03b9
# windows-driver-docs-pr/storage/msft-volume.md 42); Split-Path -NoQualifier (PowerShell-Docs
# a3de8f22552170e70852470d46cd52cd9ca471ec reference/5.1/Microsoft.PowerShell.Management/Split-Path.md 29,
# 247-249). SetV of lib\common.ps1 notes a write that fails.
$runOnce = 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
if ($waited.Count -gt 0) {
  $line = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& (''{0}:' + (Split-Path -Path $root -NoQualifier) + '\run.cmd'' -f (Get-Volume -FileSystemLabel PRESETS).DriveLetter) ' + ($waited -join ' ') + '"'
  Note ('the run goes on after the restart with ' + ($waited -join ', ') + ': writing the value Bastion of HKLM\' + $runOnce + ': ' + $line)
  SetV $HKLM $runOnce 'Bastion' $line 'String'
}
# The question whenever a restart is pending: y restarts Windows at once, shutdown.exe /r /t 0 through
# RunLogged (learn.microsoft.com windows-server/administration/windows-commands/shutdown,
# MicrosoftDocs/windowsserverdocs f328f4eedd90a57e54fce5b02fd9da159e4583ab
# WindowsServerDocs/administration/windows-commands/shutdown.md: /r 29, /t 40); any other answer, as
# 75-installers reads its question, leaves the restart to the user and the RunOnce value in place. Read-Host
# -Prompt returns the answer as a string (PowerShell-Docs a3de8f22552170e70852470d46cd52cd9ca471ec
# reference/5.1/Microsoft.PowerShell.Utility/Read-Host.md 122-124, 154-156).
if (RestartPending) {
  if ((Read-Host -Prompt 'Restart Windows now to finish this setup? (y/n)') -eq 'y') {
    Note 'Restart Windows now: answered y, restarting'
    [void](RunLogged 'shutdown.exe' @('/r', '/t', '0'))
  } else {
    Note 'Restart Windows now: not answered y, Windows is not restarted'
    Note 'Restart Windows to finish this setup.'
  }
}
