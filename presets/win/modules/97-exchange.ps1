. (Join-Path $PSScriptRoot '..\lib\common.ps1')
# The exchange of files between the VMs, set up inside this Windows: the vsock driver, vstbridge, OpenSSH
# Server, the account only the host's key logs into, its folders and sshd's configuration. A re-run
# changes nothing that is right and repairs what drifted. The module's word is the part of this file's
# name after the number and the dash; its files are on the stick in win\<word>, put there by attach.sh
# from the bastion tool's exchange-files, among them the words file <word>.json, which holds every
# word and sentence this module uses (host-networks.nix's exchange). The names written below are fixed
# by Windows, OpenSSH, vstbridge and the virtio ISO themselves, each beside its source. It prints only
# the sentences of the words file, and Windows' own message when a command fails.
# Sources: PowerShell-Docs a3de8f22552170e70852470d46cd52cd9ca471ec reference/5.1 (PS below);
# windows-powershell-docs b7645dd8c687139b28e845119da30ec670526507 docset/winserver2022-ps (WPS);
# dotnet-api-docs ff6ab9d92a3fc276589a73ae80fd3c7df264608e xml (NET); windowsserverdocs
# 6ae633133066b1e1ad5992f84405176c6a682b46 WindowsServerDocs/administration (WSD); windows-driver-docs
# 8bf796c7126ac13e8ef5f5d1013d0326dc9a0215 windows-driver-docs-pr (WDD); kvm-guest-drivers-windows
# d92b9c073ec1108f51846d0bd109c5796b46fd36 (KVM).
# $PSCommandPath, this file's path (PS Microsoft.PowerShell.Core/About/about_Automatic_Variables.md 50);
# Path.GetFileNameWithoutExtension (NET System.IO/Path.xml 1249); Get-Content -LiteralPath -Raw
# (PS Microsoft.PowerShell.Management/Get-Content.md 457, 497); ConvertFrom-Json
# (PS Microsoft.PowerShell.Utility/ConvertFrom-Json.md 19). Throughout: Join-Path
# (PS Microsoft.PowerShell.Management/Join-Path.md 18), Where-Object and ForEach-Object with a script
# block (Microsoft.PowerShell.Core/Where-Object.md 30, ForEach-Object.md 23), Out-Null (Out-Null.md 18),
# Sort-Object and New-Object (Microsoft.PowerShell.Utility/Sort-Object.md 22, New-Object.md 21),
# Select-Object -First and -Unique (Select-Object.md 513, 665).
$word = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) -replace '^[0-9]+-', ''
$prefix = '[' + $word + '] '
$files = Join-Path $BastionRoot $word
try {
  $words = Get-Content -LiteralPath (Join-Path $files ($word + '.json')) -Raw -ErrorAction Stop | ConvertFrom-Json
} catch {
  Note ($prefix + $_.Exception.Message)
  return
}
$inbox = Join-Path $words.folder $words.'inbox-folder'
$outbox = Join-Path $words.folder $words.'outbox-folder'
$fields = @{ command = $words.command; module = $word; account = $words.account; folder = $words.folder;
  inbox = $inbox; outbox = $outbox }

# A sentence of the words file, its fields in braces filled.
function Tell([string]$key, [hashtable]$more) {
  $s = [string]$words.'module-lines'.$key
  $all = $fields.Clone()
  foreach ($k in $more.Keys) { $all[$k] = $more[$k] }
  foreach ($k in $all.Keys) { $s = $s.Replace('{' + $k + '}', [string]$all[$k]) }
  Note ($prefix + $s)
}
# Windows' own message of a command that failed.
function Failed($err) { Note ($prefix + $err.Exception.Message) }
# The lines a program printed, when it failed.
function Printed($lines) { foreach ($l in $lines) { if ("$l".Trim()) { Note ($prefix + $l) } } }

# 1. The vsock device, by the PCI ids of the virtio ISO's driver (KVM viosock/sys/viosock.inx 49-53);
# Get-PnpDevice -PresentOnly (WPS PnpDevice/Get-PnpDevice.md 20, 204-206), its Status OK, ERROR or
# UNKNOWN (220-226).
$deviceIds = @('PCI\VEN_1AF4&DEV_1053&SUBSYS_1100*', 'PCI\VEN_1AF4&DEV_1012&SUBSYS_0013*')
function Device {
  Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $id = $_.InstanceId; @($deviceIds | Where-Object { $id -like $_ }).Count -gt 0 } |
    Select-Object -First 1
}
if ($null -eq (Device)) {
  Tell 'no-device' @{}
  return
}

# 2. The driver from the ISO's w10 or w11 folder: w11 from Windows 11's first build, 22000 (WDD
# install/inf-manufacturer-section.md 99, 190-202), the build read from .NET's Environment.OSVersion
# (NET System/Environment.xml 1692, its remarks on the application manifest 1736-1738;
# System/OperatingSystem.xml 1183; System/Version.xml 446); pnputil /add-driver INF /install (WDD
# devtest/pnputil-command-syntax.md 40-46) when the device's Status is not OK; $LASTEXITCODE
# (about_Automatic_Variables.md 41).
$windows = 'w10'
if ([System.Environment]::OSVersion.Version.Build -ge 22000) { $windows = 'w11' }
$driverDir = Join-Path $files ('viosock\' + $windows + '\amd64')
if ((Device).Status -ne 'OK') {
  $out = pnputil /add-driver (Join-Path $driverDir 'viosock.inf') /install 2>&1
  if ($LASTEXITCODE -ne 0) { Printed $out }
}

# 3. vstbridge (KVM viosock/tcp-bridge): its service VsockTcpBridge (main.cpp 11), registered by -i
# (main.cpp 45-47) with the path of the exe that ran it (utils.cpp 55-67), starting automatically
# (utils.cpp 79), not started by -i (utils.cpp 47-103); bridge-folder is the place its README.md 46
# names. Get-Service, Stop-Service, Start-Service (PS Microsoft.PowerShell.Management/Get-Service.md 23,
# Stop-Service.md 23, Start-Service.md 23), the Status Running or Stopped (NET
# System.ServiceProcess/ServiceController.xml 1207, ServiceControllerStatus.xml 143, 197);
# Get-FileHash -LiteralPath, SHA256 by default (PS Microsoft.PowerShell.Utility/Get-FileHash.md 27, 54);
# Test-Path -LiteralPath (Test-Path.md 331); New-Item -ItemType Directory -Force (New-Item.md 361, 383);
# Copy-Item -LiteralPath -Force (Copy-Item.md 495, 556); Start-Process -Wait -NoNewWindow
# (Start-Process.md 243, 377). The copy only when the file differs, the service stopped before it.
$service = 'VsockTcpBridge'
$bridgeExe = 'vstbridge.exe'
$bridgeFrom = Join-Path $driverDir $bridgeExe
$bridgeTo = Join-Path $words.'bridge-folder' $bridgeExe
try {
  $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
  $same = (Test-Path -LiteralPath $bridgeTo) -and
    ((Get-FileHash -LiteralPath $bridgeTo).Hash -eq (Get-FileHash -LiteralPath $bridgeFrom).Hash)
  if (-not $same) {
    if ($null -ne $svc -and $svc.Status -ne 'Stopped') { Stop-Service -Name $service -ErrorAction Stop }
    New-Item -ItemType Directory -Force -Path $words.'bridge-folder' -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $bridgeFrom -Destination $bridgeTo -Force -ErrorAction Stop
  }
  if ($null -eq $svc) { Start-Process -FilePath $bridgeTo -ArgumentList '-i' -Wait -NoNewWindow -ErrorAction Stop }
  if ((Get-Service -Name $service -ErrorAction Stop).Status -ne 'Running') { Start-Service -Name $service -ErrorAction Stop }
} catch { Failed $_ }

# 4. OpenSSH Server, the Windows optional feature serviced through Windows Update (WSD
# OpenSSH/OpenSSH_Install_FirstUse.md 20): Get-WindowsCapability, its State NotPresent while not
# installed (135-145), Add-WindowsCapability -Online -Name (155 for Windows 11, 331 for Windows 10;
# WPS DISM/Get-WindowsCapability.md 111, 126, Add-WindowsCapability.md 113, 128); a failure ends the
# module. sshd.exe in OpenSSH's default installation folder %systemdrive%\Windows\System32\openssh (WSD
# OpenSSH/openssh-server-configuration.md 44), its version read with .NET's FileVersionInfo (NET
# System.Diagnostics/FileVersionInfo.xml 605, 541).
$capability = 'OpenSSH.Server~~~~0.0.1.0'
try {
  if ((Get-WindowsCapability -Online -Name $capability -ErrorAction Stop).State -eq 'NotPresent') {
    Add-WindowsCapability -Online -Name $capability -ErrorAction Stop | Out-Null
  }
} catch {
  Failed $_
  Tell 'no-capability' @{}
  return
}
$version = ''
try {
  $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $env:SystemDrive 'Windows\System32\openssh\sshd.exe')).FileVersion
} catch { Failed $_ }

# 5. The account (PS Microsoft.PowerShell.LocalAccounts): Get-LocalUser -Name (Get-LocalUser.md 89), its
# SID (29; NET System.Security.Principal/SecurityIdentifier.xml 867); made when missing with
# New-LocalUser -Name -Password -PasswordNeverExpires -UserMayNotChangePassword (New-LocalUser.md 24-26,
# 212, 232, 248), which adds it to no group; its password random, from .NET's RandomNumberGenerator
# (NET System.Security.Cryptography/RandomNumberGenerator.xml 132, 419) through Convert.ToBase64String
# (System/Convert.xml 1455) and the cmdlet below with -AsPlainText -Force (its page PS
# Microsoft.PowerShell.Security/ConvertTo-SecureString.md 28, 160), held in this process alone,
# never written or printed; on a re-run Set-LocalUser -PasswordNeverExpires $true -UserMayChangePassword
# $false (Set-LocalUser.md 23, 204, 236); never an administrator: Get-LocalGroupMember and
# Remove-LocalGroupMember -SID of the Administrators group, S-1-5-32-544, which lib\common.ps1 uses too
# (Get-LocalGroupMember.md 35, 74-78; Remove-LocalGroupMember.md 36). Without the account the steps
# after it cannot run, and the module ends.
$admins = 'S-1-5-32-544'
try {
  $user = Get-LocalUser -Name $words.account -ErrorAction SilentlyContinue
  if ($null -eq $user) {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $password = ConvertTo-SecureString -String ([System.Convert]::ToBase64String($bytes)) -AsPlainText -Force
    $user = New-LocalUser -Name $words.account -Password $password -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop
  } else {
    Set-LocalUser -Name $words.account -PasswordNeverExpires $true -UserMayChangePassword $false -ErrorAction Stop
  }
  if ($null -ne (Get-LocalGroupMember -SID $admins -Member $user.SID.Value -ErrorAction SilentlyContinue)) {
    Remove-LocalGroupMember -SID $admins -Member $user -ErrorAction Stop
  }
} catch {
  Failed $_
  return
}

# 6. The rights, by icacls (WSD windows-commands/icacls.md 21, 40, 42, 46, 60 a SID after *, 66-72 the
# simple rights, 74-95 the specific rights, DC delete child 93, 99-103 the inheritance; /inheritance:r
# in the form openssh-server-configuration.md 130 writes it): the folder with inheritance removed,
# SYSTEM (S-1-5-18) and Administrators full, which Inbox and Outbox inherit, the user running run.cmd
# and the account read on it alone; Outbox: that user modify, the account read; Inbox: that user read
# and delete child, so a file there can be deleted and none added or changed, the account modify.
# The rights are compared first through Get-Acl -LiteralPath (PS Microsoft.PowerShell.Security/Get-Acl.md
# 21, 228) and .NET (NET System.Security.AccessControl: ObjectSecurity.xml 315
# AreAccessRulesProtected; CommonObjectSecurity.xml 160 GetAccessRules; AuthorizationRule.xml 116,
# 148, 213; AccessRule.xml 83; FileSystemAccessRule.xml 287; FileSystemRights.xml FullControl 294-322,
# Modify 360-388, Read 393-421, DeleteSubdirectoriesAndFiles 228-256, Synchronize 591-619, left out of
# the comparison since icacls's rights may carry it; InheritanceFlags.xml 40, 71, 102;
# PropagationFlags.xml 71), and icacls runs only on a difference. The user's SID from .NET's
# WindowsIdentity (NET System.Security.Principal/WindowsIdentity.xml 854, 1845).
$system = 'S-1-5-18'
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$them = $user.SID.Value
$rights = [System.Security.AccessControl.FileSystemRights]
$sync = [int]$rights::Synchronize
$both = [int]([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit)
$alone = [int][System.Security.AccessControl.InheritanceFlags]::None
$flat = [System.Security.AccessControl.PropagationFlags]::None
function Grant([string]$sid, [string]$perm, $mask, [int]$flags) { @{ sid = $sid; perm = $perm; mask = $mask; flags = $flags } }
function Key([string]$sid, $type, $mask, $flags, $propagation) {
  $sid + ',' + [string]$type + ',' + ([int]$mask -band (-bnot $sync)) + ',' + [int]$flags + ',' + [int]$propagation
}
function RunIcacls([string]$path) {
  $out = icacls $path @args 2>&1
  if ($LASTEXITCODE -ne 0) { Printed $out }
}
function Rights([string]$path, [bool]$protected, [object[]]$grants) {
  $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
  $rules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
  $now = @($rules | ForEach-Object { Key $_.IdentityReference.Value $_.AccessControlType $_.FileSystemRights $_.InheritanceFlags $_.PropagationFlags } | Sort-Object)
  $want = @($grants | ForEach-Object { Key $_.sid 'Allow' $_.mask $_.flags $flat } | Sort-Object)
  if ($acl.AreAccessRulesProtected -eq $protected -and ($now -join ';') -eq ($want -join ';')) { return }
  $keep = @($grants | ForEach-Object { $_.sid })
  foreach ($sid in @($rules | ForEach-Object { $_.IdentityReference.Value } | Select-Object -Unique)) {
    if ($keep -notcontains $sid) { RunIcacls $path '/remove' ('*' + $sid) }
  }
  $done = @()
  foreach ($g in $grants) {
    $how = '/grant:r'
    if ($done -contains $g.sid) { $how = '/grant' }
    RunIcacls $path $how ('*' + $g.sid + ':' + $g.perm)
    $done += $g.sid
  }
  if ($protected) { RunIcacls $path '/inheritance:r' } else { RunIcacls $path '/inheritance:e' }
}
try {
  foreach ($p in @($words.folder, $inbox, $outbox)) {
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Path $p -ErrorAction Stop | Out-Null }
  }
  Rights $words.folder $true @(
    (Grant $system '(OI)(CI)F' $rights::FullControl $both),
    (Grant $admins '(OI)(CI)F' $rights::FullControl $both),
    (Grant $me 'R' $rights::Read $alone),
    (Grant $them 'R' $rights::Read $alone))
  Rights $outbox $false @(
    (Grant $me '(OI)(CI)M' $rights::Modify $both),
    (Grant $them '(OI)(CI)R' $rights::Read $both))
  Rights $inbox $false @(
    (Grant $me '(OI)(CI)R' $rights::Read $both),
    (Grant $me '(DC)' $rights::DeleteSubdirectoriesAndFiles $alone),
    (Grant $them '(OI)(CI)M' $rights::Modify $both))
} catch { Failed $_ }

# 7. sshd_config, written whole where sshd reads it, %programdata%\ssh\sshd_config (WSD
# OpenSSH/openssh-server-configuration.md 26, 69), only when its text differs: ListenAddress 127.0.0.1,
# where vstbridge sends vsock port 22 (KVM viosock/tcp-bridge/service.cpp 197-198, bridge.cpp 391-394);
# AllowUsers and Match User with the account in lower case (84, 178-180); the Match block's
# AuthorizedKeysFile an absolute path (118-122), the account's file named as OpenSSH's
# administrators_authorized_keys is (122); ChrootDirectory with ForceCommand internal-sftp (132-135)
# and PermitTTY no, since ForceCommand holds only for sessions with no terminal (Win32-OpenSSH wiki
# sshd_config 834c09355b10c501f64c463485e29e499044d6c9 50-51); PasswordAuthentication no and
# AllowTcpForwarding no; the paths in double quotes (OpenSSH V_10_5_P1 sshd_config.5 55-57, 145, 164,
# 277, 486, 704, 1105, 1257, 1319-1325, 1432, 1549). Set-Content -LiteralPath -NoNewline -Encoding Ascii
# (PS Microsoft.PowerShell.Management/Set-Content.md 187, 199, 330). The keys file is the stick's
# public half, its rights SYSTEM and Administrators full and the account read with inheritance removed,
# as the TIP of openssh-server-configuration.md 124-130 sets administrators_authorized_keys's.
$ssh = Join-Path $env:ProgramData 'ssh'
$config = Join-Path $ssh 'sshd_config'
$keys = Join-Path $ssh ($words.account + '_authorized_keys')
$name = $words.account.ToLower()
$text = (@(
  'ListenAddress 127.0.0.1',
  ('AllowUsers ' + $name),
  'PasswordAuthentication no',
  ('Match User ' + $name),
  ('AuthorizedKeysFile "' + $keys + '"'),
  ('ChrootDirectory "' + $words.folder + '"'),
  'ForceCommand internal-sftp',
  'PermitTTY no',
  'AllowTcpForwarding no') -join "`r`n") + "`r`n"
$written = $false
try {
  if (-not (Test-Path -LiteralPath $ssh -PathType Container)) { New-Item -ItemType Directory -Path $ssh -ErrorAction Stop | Out-Null }
  if ((Get-Content -LiteralPath $config -Raw -ErrorAction SilentlyContinue) -cne $text) {
    Set-Content -LiteralPath $config -Value $text -NoNewline -Encoding Ascii -ErrorAction Stop
    $written = $true
  }
  $public = Join-Path $files $words.'public-key'
  if (-not (Test-Path -LiteralPath $keys) -or (Get-FileHash -LiteralPath $keys).Hash -ne (Get-FileHash -LiteralPath $public).Hash) {
    Copy-Item -LiteralPath $public -Destination $keys -Force -ErrorAction Stop
    $written = $true
  }
  Rights $keys $true @(
    (Grant $system 'F' $rights::FullControl $alone),
    (Grant $admins 'F' $rights::FullControl $alone),
    (Grant $them 'R' $rights::Read $alone))
} catch { Failed $_ }

# 8. sshd, its service named sshd (OpenSSH_Install_FirstUse.md 170-173), starting automatically
# (Set-Service -StartupType, PS Set-Service.md 60, 291; the StartType Automatic, NET
# System.ServiceProcess/ServiceController.xml 1179, ServiceStartMode.xml 52), restarted when its
# configuration or keys file was written or when it does not run (Restart-Service, Restart-Service.md
# 21); the firewall rule the install makes and enables, OpenSSH-Server-In-TCP (OpenSSH_Install_FirstUse.md
# 124), disabled when it is enabled, since sshd listens on 127.0.0.1 alone (Get-NetFirewallRule -Name,
# its Enabled True or False, WPS NetSecurity/Get-NetFirewallRule.md 459-464, 546;
# Disable-NetFirewallRule -Name, Disable-NetFirewallRule.md 597).
$sshdService = 'sshd'
$firewallRule = 'OpenSSH-Server-In-TCP'
try {
  $sshd = Get-Service -Name $sshdService -ErrorAction Stop
  if ($sshd.StartType -ne 'Automatic') { Set-Service -Name $sshdService -StartupType Automatic -ErrorAction Stop }
  if ($written -or $sshd.Status -ne 'Running') { Restart-Service -Name $sshdService -ErrorAction Stop }
} catch { Failed $_ }
try {
  $rule = Get-NetFirewallRule -Name $firewallRule -ErrorAction SilentlyContinue
  if ($null -ne $rule -and [string]$rule.Enabled -eq 'True') { Disable-NetFirewallRule -Name $firewallRule -ErrorAction Stop }
} catch { Failed $_ }

# 9. What the module found: the device's Status and each service's Status as Windows reports them.
Tell 'driver' @{ state = (Device).Status }
Tell 'bridge' @{ service = $service; state = (Get-Service -Name $service -ErrorAction SilentlyContinue).Status }
Tell 'sshd' @{ state = (Get-Service -Name $sshdService -ErrorAction SilentlyContinue).Status; version = $version }
Tell 'account' @{}
Tell 'folders' @{}
