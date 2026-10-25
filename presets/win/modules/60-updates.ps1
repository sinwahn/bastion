. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[updates] disabling automatic Windows Update (LTSC honors this policy)'
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
Note '[updates] automatic updates and surprise reboots off. Nothing installs unless you start it.'
