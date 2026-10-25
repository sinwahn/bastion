. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[defender] turning scanning off (firewall and UAC stay)'
$rt = 'SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
foreach ($v in @('DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection','DisableIOAVProtection','DisableScanOnRealtimeEnable')) { SetV $HKLM $rt $v 1 }
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 0
try { Get-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\' -ErrorAction Stop | Disable-ScheduledTask -ErrorAction Stop | Out-Null; Note 'Defender tasks off' } catch {}
try { if ((Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected) { Note 'NOTE: Tamper Protection is ON, so Defender ignores the above. Turn it off in Windows Security and re-run.' } else { Note 'Defender scanning off' } } catch {}
Note '[defender] done'
