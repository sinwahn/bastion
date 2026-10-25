. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[context-menu] stripping Send to / Share / Give access / etc.'
$targets = @{
  '{7BA4C740-9E81-11CF-99D3-00AA004AE837}' = 'Send to'
  '{3dad6c5d-2167-4cae-9914-f99e41c12cfa}' = 'Include in library'
  '{E2BF9676-5F8F-435C-97EB-11607A5BEDF7}' = 'Share'
  '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}' = 'Give access to'
  '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}' = 'Cast to Device'
  '{596AB062-B4D2-4215-9F74-E9109B0A8153}' = 'Restore previous versions'
  '{470C0EBD-5D73-4d58-9CED-E91E22E23282}' = 'Pin to Start'
  '{1d27f844-3a1f-4410-85ac-14651078412d}' = 'Troubleshoot compatibility'
}
$roots = @('*', 'AllFilesystemObjects', 'Directory', 'Directory\Background', 'Folder', 'Drive', 'UserLibraryFolder', 'LibraryFolder', 'Network', 'Unknown')
foreach ($r in $roots) {
  $base = 'SOFTWARE\Classes\' + $r + '\shellex\ContextMenuHandlers'
  $k = $HKLM.OpenSubKey($base)
  if ($null -eq $k) { continue }
  foreach ($sub in $k.GetSubKeyNames()) {
    $clsid = ''
    $sk = $k.OpenSubKey($sub); if ($null -ne $sk) { $clsid = ([string]$sk.GetValue('')).Trim() }
    if ([string]::IsNullOrEmpty($clsid)) { $clsid = $sub.Trim() }
    if ($targets.ContainsKey($clsid)) { KillHandler ($base + '\' + $sub) ($targets[$clsid] + ' in ' + $r) }
  }
}
$bk = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
foreach ($c in $targets.Keys) { SetV $HKLM $bk $c '' 'String' }
$leftover = @()
foreach ($r in @('AllFilesystemObjects','UserLibraryFolder','*','Directory','Folder')) {
  $p = 'SOFTWARE\Classes\' + $r + '\shellex\ContextMenuHandlers\SendTo'
  if ($null -ne $HKLM.OpenSubKey($p)) { $leftover += $p }
}
if ($leftover.Count -gt 0) { Note ('Send to STILL PRESENT at: ' + ($leftover -join ' ; ')) } else { Note 'Send to: confirmed removed' }
Note '[context-menu] done'
