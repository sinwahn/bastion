# Bastion module runner. Called by run.cmd (elevated). Runs modules in order,
# or only those whose name contains one of the given words: run.cmd firefox nvidia
# Every line it shows also goes to setup.log through Note: the run's start, Windows' product name,
# version and build (Win32_OperatingSystem Caption, Version, BuildNumber, read with Get-CimInstance),
# whether it runs elevated (WindowsPrincipal.IsInRole for the Administrators role, which is false in
# the standard-user token of User Account Control), the presets folder, the modules, each module's
# start and end with its result, and one summary line per module.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Only)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:BASTION_ROOT = $root
$global:BastionLogFailed = $false
$global:BastionModuleState = 'done'
. (Join-Path $root 'lib\common.ps1')
Note ('==== run start ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
try {
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  Note ('Windows: ' + ([string]$os.Caption).Trim() + ', version ' + $os.Version + ', build ' + $os.BuildNumber)
} catch { Note ('FAILED to read the Windows product name, version and build: ' + $_.Exception.Message) }
$me = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if ($me.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { Note 'elevated: yes' } else { Note 'elevated: no' }
Note ('presets folder: ' + $root)
Remove-Item -LiteralPath $BastionRestart -Force -ErrorAction SilentlyContinue
$modDir = Join-Path $root 'modules'
$mods = @(Get-ChildItem -Path $modDir -Filter '*.ps1' | Sort-Object Name)
if ($Only -and $Only.Count -gt 0) {
  $mods = @($mods | Where-Object { $n = $_.BaseName; ($Only | Where-Object { $n -like ('*' + $_ + '*') }).Count -gt 0 })
}
Note ('modules to run (' + $mods.Count + '): ' + (($mods | ForEach-Object { $_.BaseName }) -join ', '))
$summary = @()
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
}
foreach ($s in $summary) { Note ('summary: ' + $s) }
Note 'Restarting Explorer to apply shell changes...'
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $BastionRestart) { Note 'Restart Windows to finish this setup.' }
