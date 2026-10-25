. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[defender] turning scanning off (firewall and UAC stay)'
Note '[defender] real-time protection policies off, SmartScreen off'
$rt = 'SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
foreach ($v in @('DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection','DisableIOAVProtection','DisableScanOnRealtimeEnable')) { SetV $HKLM $rt $v 1 }
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 0
try { Get-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\' -ErrorAction Stop | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Note '[defender] Defender tasks off' }
catch { Note ('[defender] FAILED to turn the Defender tasks off: ' + $_.Exception.Message) }
try { if ((Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected) { Note '[defender] NOTE: Tamper Protection is ON, so Defender ignores the above. Turn it off in Windows Security and re-run.' } else { Note '[defender] Defender scanning off' } }
catch { Note ('[defender] FAILED to read Tamper Protection: ' + $_.Exception.Message) }
Note '[defender] done'
