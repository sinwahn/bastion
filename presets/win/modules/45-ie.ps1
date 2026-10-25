. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[ie] removing Internet Explorer optional feature'
try {
  $ie = Get-WindowsOptionalFeature -Online -FeatureName Internet-Explorer-Optional-amd64 -ErrorAction Stop
  if ($ie.State -eq 'Enabled') {
    Disable-WindowsOptionalFeature -Online -FeatureName Internet-Explorer-Optional-amd64 -NoRestart -ErrorAction Stop | Out-Null
    Note '[ie] Internet Explorer: removed (a restart finishes it)'
  } else { Note '[ie] Internet Explorer: already off' }
} catch { Note ('[ie] FAILED, Internet Explorer: ' + $_.Exception.Message) }
Note '[ie] done'
