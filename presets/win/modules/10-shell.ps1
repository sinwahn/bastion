. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[shell] Explorer prefs, dark mode, This PC, Spotlight, search box'
function ExplorerPrefs($root, [string]$p) {
  $e = $p + 'Software\Microsoft\Windows\CurrentVersion\Explorer'
  SetV $root ($e + '\Advanced') 'HideFileExt' 0
  SetV $root ($e + '\Advanced') 'Hidden' 1
  SetV $root ($e + '\Advanced') 'LaunchTo' 1
  SetV $root $e 'ShowFrequent' 0
  SetV $root $e 'ShowRecent' 0
  SetV $root ($e + '\CabinetState') 'FullPath' 1
}
function Dark($root, [string]$p) {
  $t = $p + 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  SetV $root $t 'AppsUseLightTheme' 0
  SetV $root $t 'SystemUsesLightTheme' 0
}
ExplorerPrefs $HKCU ''
Dark $HKCU ''
$unwanted = @('3D Objects','Contacts','Favorites','Links','Searches')
foreach ($f in $unwanted) { $d = Join-Path $env:USERPROFILE $f; if (Test-Path -LiteralPath $d) { try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop; Note ("removed folder " + $f) } catch {} } }
$hive = 'C:\Users\Default\NTUSER.DAT'
& reg.exe load 'HKU\BastionDef' $hive | Out-Null
if ($LASTEXITCODE -eq 0) {
  ExplorerPrefs $HKU 'BastionDef\'
  Dark $HKU 'BastionDef\'
  $rd = ($unwanted | ForEach-Object { 'rd /s /q "%USERPROFILE%\' + $_ + '"' }) -join ' & '
  SetV $HKU 'BastionDef\Software\Microsoft\Windows\CurrentVersion\RunOnce' 'BastionFolders' ('cmd /c ' + $rd) 'String'
  [GC]::Collect(); [GC]::WaitForPendingFinalizers(); & reg.exe unload 'HKU\BastionDef' | Out-Null
  Note 'default profile: explorer + dark set'
} else { Note 'default profile: could not load (this user only)' }
# no grouping
SetV $HKCU 'Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' 'GroupView' 0
# This PC: remove Desktop/Documents/Music/3D Objects nodes (keep Downloads/Pictures/Videos)
$remCLSID = @{
  '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = 'Desktop'
  '{d3162b92-9365-467a-956b-92703aca08af}' = 'Documents'
  '{A8CDFF1C-4878-43be-B5FD-F8091C1C60D0}' = 'Documents (old)'
  '{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}' = 'Music'
  '{1CF1260C-4DD0-4ebb-811F-33C572699FDE}' = 'Music (old)'
  '{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}' = '3D Objects'
}
foreach ($ns in @('SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace','SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace')) {
  foreach ($c in $remCLSID.Keys) { DelTree $HKLM ($ns + '\' + $c) ('This PC ' + $remCLSID[$c]) }
}
# Spotlight desktop off + Learn-about icon
SetV $HKCU 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1
SetV $HKCU 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
SetV $HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}' 1
SetV $HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu' '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}' 1
# search box + indexer + Meet Now
SetV $HKCU 'Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
SetV $HKLM 'SYSTEM\CurrentControlSet\Services\WSearch' 'Start' 4
SetV $HKCU 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1
Note '[shell] done'
