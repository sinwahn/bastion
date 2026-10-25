. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[debloat] consumer features off, Dev Home removed, Windows Backup shortcut removed'
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
$cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($v in @('SilentInstalledAppsEnabled','PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','ContentDeliveryAllowed','SystemPaneSuggestionsEnabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled')) { SetV $HKCU $cdm $v 0 }
foreach ($app in @('Microsoft.Windows.DevHome')) {
  try { Get-AppxPackage -Name $app -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop; Note ('removed app: ' + $app) }
  catch { Note ('app remove note ' + $app + ': ' + $_.Exception.Message) }
  try { Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app } | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null; Note ('deprovisioned: ' + $app) }
  catch {}
}
# Windows Backup: no clean uninstall (system app). Remove its Start-menu shortcut so it leaves the menu.
foreach ($sm in @('C:\ProgramData\Microsoft\Windows\Start Menu\Programs','C:\Users\Public\AppData\Roaming\Microsoft\Windows\Start Menu\Programs')) {
  foreach ($name in @('Windows Backup.lnk')) {
    $lnk = Join-Path $sm $name
    if (Test-Path -LiteralPath $lnk) { try { Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop; Note ('removed Start shortcut: ' + $name) } catch {} }
  }
}
Note '[debloat] done'
