# Bastion shared helpers. Dot-sourced by every module. Not run on its own.
$ErrorActionPreference = 'Continue'
$HKLM = [Microsoft.Win32.Registry]::LocalMachine
$HKCU = [Microsoft.Win32.Registry]::CurrentUser
$HKU  = [Microsoft.Win32.Registry]::Users
$BastionDir = 'C:\ProgramData\Bastion'
try { New-Item -ItemType Directory -Force -Path $BastionDir | Out-Null } catch {}
if ($env:BASTION_ROOT) { $BastionRoot = $env:BASTION_ROOT } else { $BastionRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath) }
$BastionAssets = Join-Path $BastionRoot 'assets'
$BastionRestart = Join-Path $BastionDir 'restart'

function Note([string]$s) {
  Write-Host $s
  try { Add-Content -LiteralPath (Join-Path $BastionDir 'setup.log') -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $s) -Encoding ASCII } catch {}
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
  Add-Type -Namespace Bastion -Name Priv -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("ntdll.dll")]
public static extern int RtlAdjustPrivilege(int Privilege, bool Enable, bool CurrentThread, out bool Enabled);
"@
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
