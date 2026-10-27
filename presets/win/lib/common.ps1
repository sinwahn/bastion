# Bastion shared helpers. Dot-sourced by every module. Not run on its own.
$ErrorActionPreference = 'Continue'
$HKLM = [Microsoft.Win32.Registry]::LocalMachine
$HKCU = [Microsoft.Win32.Registry]::CurrentUser
$HKU  = [Microsoft.Win32.Registry]::Users
# C:\ProgramData\Bastion: Windows' own ProgramData folder, C:\ProgramData on every Windows.
$BastionDir = Join-Path $env:ProgramData 'Bastion'
try { New-Item -ItemType Directory -Force -Path $BastionDir | Out-Null } catch {}
if ($env:BASTION_ROOT) { $BastionRoot = $env:BASTION_ROOT } else { $BastionRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$BastionAssets = Join-Path $BastionRoot 'assets'
$BastionRestart = Join-Path $BastionDir 'restart'

# A line on the screen and in setup.log. When setup.log cannot be written, the screen says so once per
# run ($global:BastionLogFailed, cleared by run.ps1 at its start). A line holding FAILED marks the module
# that is running as failed in run.ps1's summary ($global:BastionModuleState).
function Note([string]$s) {
  Write-Host $s
  try { Add-Content -LiteralPath (Join-Path $BastionDir 'setup.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $s) -Encoding ASCII -ErrorAction Stop }
  catch {
    if (-not $global:BastionLogFailed) {
      $global:BastionLogFailed = $true
      Write-Host ('setup.log could not be written: ' + $_.Exception.Message)
    }
  }
  if ($s.Contains('FAILED')) { $global:BastionModuleState = 'failed' }
}

# RunLogged PROGRAM ARGUMENTS [OUTPUT] [SUCCESS]: runs one console program, waits for it and keeps what it
# prints. It logs the command line before the program starts and its exit code after it, in decimal and in
# hexadecimal; for a code that is not a success it logs FAILED and every line the program printed. It
# returns the exit code, or $null when the program could not be started. OUTPUT, a [ref], gets the lines
# of its standard output. SUCCESS, a hashtable, holds the exit codes the caller counts as success, each
# with its meaning, logged after the code; without it 0 alone is success and no meaning is logged. An
# argument holding a space or a double quote is passed in double quotes.
# Sources (learn.microsoft.com, Windows PowerShell 5.1, PowerShell-Docs 5e0701d
# reference/5.1/Microsoft.PowerShell.Management/Start-Process.md): ArgumentList joined with single spaces
# 143-156, NoNewWindow 243-246, PassThru 262-265, RedirectStandardError 279-282, RedirectStandardOutput
# 313-316, Wait 377-380 and 489-491 (the process and all its descendants), the Process object 464.
# Get-Command -CommandType Application finds the program on PATH; Path.GetTempFileName makes the two
# files; the hexadecimal form is the X8 format (dotnet docs standard-numeric-format-strings.md 306-310).
function RunLogged([string]$Program, [string[]]$Arguments, [ref]$Output, [hashtable]$Success) {
  $quoted = @()
  foreach ($a in @($Arguments | Where-Object { $null -ne $_ })) {
    if ($a -eq '' -or $a -match '[\s"]') { $quoted += ('"' + $a.Replace('"', '\"') + '"') } else { $quoted += $a }
  }
  $line = $quoted -join ' '
  $out = $null
  $err = $null
  try {
    $path = (Get-Command -Name $Program -CommandType Application -ErrorAction Stop | Select-Object -First 1).Path
    Note (('run: ' + $path + ' ' + $line).TrimEnd())
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    $start = @{ FilePath = $path; NoNewWindow = $true; Wait = $true; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err; ErrorAction = 'Stop' }
    if ($line) { $start.ArgumentList = $line }
    $p = Start-Process @start
    $code = $p.ExitCode
    $printed = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue)
    if ($null -ne $Output) { $Output.Value = $printed }
    $text = [string]$code + ' (0x' + ('{0:X8}' -f $code) + '): ' + $path
    if ($null -eq $Success -and $code -eq 0) { Note ('exit ' + $text) }
    elseif ($null -ne $Success -and $Success.ContainsKey($code)) { Note ('exit ' + $text + ': ' + $Success[$code]) }
    else {
      Note ('FAILED, exit ' + $text)
      foreach ($l in ($printed + @(Get-Content -LiteralPath $err -ErrorAction SilentlyContinue))) { if ("$l".Trim()) { Note ('output: ' + $l) } }
    }
    return $code
  } catch {
    Note ('FAILED, could not start ' + $Program + ': ' + $_.Exception.Message)
    return $null
  } finally {
    foreach ($f in @($out, $err)) { if ($f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
  }
}

# StartLogged PROGRAM ARGUMENTS: starts an installer the way the presets always started it,
# Start-Process -Wait -PassThru with the same arguments, in its own window, nothing redirected or
# captured. It logs the command line before it starts and the exit code after it, in decimal and in
# hexadecimal, FAILED for a code other than 0, and the message when the installer cannot be started. It
# returns the exit code, or $null when the installer could not be started. Sources: as RunLogged's.
function StartLogged([string]$Program, [string[]]$Arguments) {
  $start = @{ FilePath = $Program; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
  $shown = $Program
  if ($Arguments -and $Arguments.Count -gt 0) { $start.ArgumentList = $Arguments; $shown = $shown + ' ' + ($Arguments -join ' ') }
  Note ('start: ' + $shown)
  try { $p = Start-Process @start }
  catch {
    Note ('FAILED, could not start ' + $Program + ': ' + $_.Exception.Message)
    return $null
  }
  $code = $p.ExitCode
  $text = [string]$code + ' (0x' + ('{0:X8}' -f $code) + '): ' + $Program
  if ($code -eq 0) { Note ('exit ' + $text) } else { Note ('FAILED, exit ' + $text) }
  return $code
}

# InstallLookingGlass PREFIX: installs Looking Glass silently from assets\looking-glass-host.exe, the Looking
# Glass host installer that attach.sh brings, waited for through StartLogged. Every line starts with PREFIX,
# the calling module's tag with its space, as 97-exchange writes its own: '[lg-host] ' in 95-lg-host,
# '[repair] ' in 99-repair. The callers check that the installer is on the stick and that no restart is
# pending first. The requirement line is stated before the installer starts, no check made; after exit 0
# the restart mark is set. It returns the exit code, or $null when the installer could not be started.
function InstallLookingGlass([string]$prefix) {
  Note ($prefix + 'Looking Glass requires cumulative updates from Windows, otherwise it will not work at all.')
  # /S: the NSIS manual, 3.2.1 Common Options (nsis.sourceforge.io/Docs/Chapter3.html), "/S runs the installer or uninstaller silently"; Looking Glass's doc/install_idd.rst 67-71 at cdba29f2 names it
  $code = StartLogged (Join-Path $BastionAssets 'looking-glass-host.exe') @('/S')
  if ($null -eq $code) { Note ($prefix + 'install FAILED: the installer could not be started') }
  elseif ($code -eq 0) {
    Note ($prefix + 'installed')
    # The installer exits 0 whether or not Windows needs a restart for its drivers (gnif/LookingGlass at
    # cdba29f2f6bcae3ded26369fc231a067cbca3752 idd/installer.nsi 205-216; the NSIS manual, Appendix D.1,
    # "0 - Normal execution (no error)"), so the restart mark is set after exit 0.
    try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note ($prefix + 'restart mark set: the display driver starts after the restart of Windows') }
    catch { Note ($prefix + 'FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
  }
  else { Note ($prefix + 'install FAILED, exit ' + $code + ' (0x' + ('{0:X8}' -f $code) + ')') }
  return $code
}

# RestartPending: true when this run's restart mark ($BastionRestart) exists, or when Windows reports a
# pending restart in one of the four registry places Microsoft lists for it (learn.microsoft.com
# intune/configmgr/core/servers/deploy/install/list-of-prerequisite-checks, "Pending system restart",
# git 7c60abcec32dd6ed1fd412284a04ef2a20a818c7): the keys Component Based Servicing\RebootPending and
# WindowsUpdate\Auto Update\RebootRequired, the values PendingFileRenameOperations of Session Manager
# (also learn.microsoft.com windows/win32/api/winbase/nf-winbase-movefileexw, sdk-api d43984d,
# nf-winbase-movefileexw.md 229-233) and CurrentRebootAttempts of ServerManager. Each one found is noted.
function RestartPending {
  $pending = $false
  if (Test-Path -LiteralPath $BastionRestart) {
    Note ('restart pending: this run''s restart mark ' + $BastionRestart + ' exists')
    $pending = $true
  }
  $keys = @('SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
  foreach ($key in $keys) {
    try {
      $k = $HKLM.OpenSubKey($key)
      if ($null -ne $k) {
        $k.Close()
        Note ('restart pending: the key HKLM\' + $key + ' exists')
        $pending = $true
      }
    } catch { Note ('FAILED to read HKLM\' + $key + ': ' + $_.Exception.Message) }
  }
  $values = @(@('SYSTEM\CurrentControlSet\Control\Session Manager', 'PendingFileRenameOperations'),
    @('SOFTWARE\Microsoft\ServerManager', 'CurrentRebootAttempts'))
  foreach ($pair in $values) {
    try {
      $k = $HKLM.OpenSubKey($pair[0])
      if ($null -ne $k) {
        $has = $k.GetValueNames() -contains $pair[1]
        $k.Close()
        if ($has) {
          Note ('restart pending: the value ' + $pair[1] + ' of HKLM\' + $pair[0] + ' is set')
          $pending = $true
        }
      }
    } catch { Note ('FAILED to read HKLM\' + $pair[0] + ' ' + $pair[1] + ': ' + $_.Exception.Message) }
  }
  return $pending
}

function SetV($root, [string]$sub, [string]$name, $value, [string]$kind = 'DWord') {
  try { $k = $root.CreateSubKey($sub); $k.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]::$kind); $k.Close() }
  catch { Note ("FAILED set " + $sub + " " + $name + ": " + $_.Exception.Message) }
}
function DelTree($root, [string]$sub, [string]$label) {
  try { if ($null -ne $root.OpenSubKey($sub)) { $root.DeleteSubKeyTree($sub); Note ("removed " + $label) } }
  catch { Note ("FAILED to remove " + $label + ": " + $_.Exception.Message) }
}
if (-not ('Bastion.Priv' -as [type])) {
  try {
    Add-Type -Namespace Bastion -Name Priv -ErrorAction Stop -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("ntdll.dll")]
public static extern int RtlAdjustPrivilege(int Privilege, bool Enable, bool CurrentThread, out bool Enabled);
"@
  } catch { Note ('FAILED to build the privilege helper (Add-Type): ' + $_.Exception.Message) }
}
$adminsSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
function TakeOwn([string]$sub) {
  try {
    $d = $false
    [void][Bastion.Priv]::RtlAdjustPrivilege(9, $true, $false, [ref]$d)
    [void][Bastion.Priv]::RtlAdjustPrivilege(18, $true, $false, [ref]$d)
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if ($null -eq $k) { return $false }
    $own = New-Object System.Security.AccessControl.RegistrySecurity
    $own.SetOwner($adminsSid); $k.SetAccessControl($own); $k.Close()
    $k2 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
    if ($null -eq $k2) { return $true }
    $acl = $k2.GetAccessControl()
    $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($adminsSid, 'FullControl', 'ContainerInherit', 'None', 'Allow')))
    $k2.SetAccessControl($acl); $k2.Close(); return $true
  } catch { return $false }
}
function KillHandler([string]$sub, [string]$label) {
  if ($null -eq $HKLM.OpenSubKey($sub)) { return }
  try { $HKLM.DeleteSubKeyTree($sub); Note ("menu removed: " + $label); return } catch { }
  [void](TakeOwn $sub)
  $k = $HKLM.OpenSubKey($sub)
  if ($null -ne $k) { foreach ($c in $k.GetSubKeyNames()) { [void](TakeOwn ($sub + '\' + $c)) } }
  try { $HKLM.DeleteSubKeyTree($sub); Note ("menu removed (after ownership): " + $label) }
  catch { Note ("menu STILL FAILED: " + $sub + " -- " + $_.Exception.Message) }
}
