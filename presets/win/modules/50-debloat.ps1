. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[debloat] consumer features off, Dev Home removed, Windows Backup shortcut removed'
Note '[debloat] consumer features and suggested apps off'
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
$cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($v in @('SilentInstalledAppsEnabled','PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','ContentDeliveryAllowed','SystemPaneSuggestionsEnabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled')) { SetV $HKCU $cdm $v 0 }
foreach ($app in @('Microsoft.Windows.DevHome')) {
  $pkg = @(Get-AppxPackage -Name $app -ErrorAction SilentlyContinue)
  if ($pkg.Count -eq 0) { Note ('[debloat] app ' + $app + ': not installed for this user - nothing removed') }
  else {
    try { $pkg | Remove-AppxPackage -ErrorAction Stop; Note ('[debloat] removed app: ' + $app) }
    catch { Note ('[debloat] FAILED to remove app ' + $app + ': ' + $_.Exception.Message) }
  }
  try {
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $app })
    if ($prov.Count -eq 0) { Note ('[debloat] app ' + $app + ': not provisioned - nothing deprovisioned') }
    else { $prov | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null; Note ('[debloat] deprovisioned: ' + $app) }
  } catch { Note ('[debloat] FAILED to deprovision ' + $app + ': ' + $_.Exception.Message) }
}
# Windows Backup: no clean uninstall (system app). Remove its Start-menu shortcut so it leaves the menu.
foreach ($sm in @('C:\ProgramData\Microsoft\Windows\Start Menu\Programs','C:\Users\Public\AppData\Roaming\Microsoft\Windows\Start Menu\Programs')) {
  foreach ($name in @('Windows Backup.lnk')) {
    $lnk = Join-Path $sm $name
    if (Test-Path -LiteralPath $lnk) {
      try { Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop; Note ('[debloat] removed Start shortcut: ' + $lnk) }
      catch { Note ('[debloat] FAILED to remove Start shortcut ' + $lnk + ': ' + $_.Exception.Message) }
    }
  }
}
Note '[debloat] done'
