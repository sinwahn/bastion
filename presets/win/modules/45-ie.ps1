. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[ie] removing Internet Explorer optional feature'
try {
  $ie = Get-WindowsOptionalFeature -Online -FeatureName Internet-Explorer-Optional-amd64 -ErrorAction Stop
  if ($ie.State -eq 'Enabled') {
    Disable-WindowsOptionalFeature -Online -FeatureName Internet-Explorer-Optional-amd64 -NoRestart -ErrorAction Stop | Out-Null
    Note 'Internet Explorer: removed (a restart finishes it)'
  } else { Note 'Internet Explorer: already off' }
} catch { Note ('Internet Explorer note: ' + $_.Exception.Message) }
Note '[ie] done'
