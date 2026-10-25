. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[resolution] Looking Glass display resolution'
# win\resolution.txt, which attach.sh writes onto the stick from bastion resolution NAME:
# WIDTHxHEIGHT locks the Looking Glass display at that size, follows lets it follow the glass window.
# The display driver (gnif/LookingGlass at cdba29f2f6bcae3ded26369fc231a067cbca3752, the build
# 95-lg-host installs) reads HKLM\SOFTWARE\LookingGlass\IDD at its start (idd/LGIdd/config/CSettings.h
# 110-113, CSettings.cpp 34-79): Modes, REG_MULTI_SZ, one WIDTHxHEIGHT@REFRESH entry per mode, * on
# the preferred one (CSettings.cpp 243-289 and 316-346); ExtraMode, the size the glass window last
# sent, comes first and is preferred over Modes (CSettings.cpp 41-48 and 69-75). So a lock is Modes
# with one entry and no ExtraMode; both take effect at the driver's next start, a restart of Windows.
# The registry calls are .NET's Microsoft.Win32.RegistryKey (dotnet/dotnet-api-docs at
# ff6ab9d92a3fc276589a73ae80fd3c7df264608e, xml/Microsoft.Win32/RegistryKey.xml: OpenSubKey 1999 and
# 2154, GetValueNames 1669, GetValueKind 1596, GetValue 1349 and 1512, DeleteValue 928-947; SetV of
# lib\common.ps1 with SetValue 2528 and RegistryValueKind.xml MultiString 155-185).
$file = Join-Path $BastionRoot 'resolution.txt'
$sub = 'SOFTWARE\LookingGlass\IDD'
if (-not (Test-Path -LiteralPath $file)) {
  Note '[resolution] win\resolution.txt not found - skipped'
  if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' }
} else {
  # Get-Content -Raw: the whole file as one string (PowerShell-Docs at
  # a3de8f22552170e70852470d46cd52cd9ca471ec, reference/5.1/Microsoft.PowerShell.Management/Get-Content.md 497-501).
  $want = (Get-Content -LiteralPath $file -Raw).Trim()
  if ($want -match '^[0-9]+x[0-9]+$') {
    # The refresh the driver gives a size it is asked for, its DefaultRefresh (CSettings.cpp 202-241):
    # a DWORD from 24 to 1000, or a string its parser takes (idd/LGCommon/RefreshRate.cpp 53-86:
    # digits with at most 4 decimals, 23.9 to 1000), read as stored (RegistryValueOptions.xml 58-88);
    # else 60.
    $refresh = '60'
    $k = $HKLM.OpenSubKey($sub)
    if ($null -ne $k) {
      if ($k.GetValueNames() -contains 'DefaultRefresh') {
        $kind = $k.GetValueKind('DefaultRefresh')
        $value = $k.GetValue('DefaultRefresh', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord -and $value -ge 24 -and $value -le 1000) {
          $refresh = [string]$value
        } elseif ($kind -eq [Microsoft.Win32.RegistryValueKind]::String -or $kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) {
          $text = ([string]$value).Trim()
          if ($text -match '^[0-9]+(\.[0-9]{1,4})?$') {
            $hz = [decimal]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($hz -ge 23.9 -and $hz -le 1000) { $refresh = $text }
          }
        }
      }
      $k.Close()
    }
    $entry = $want + '@' + $refresh + '*'
    SetV $HKLM $sub 'Modes' ([string[]]@($entry)) 'MultiString'
    $k = $HKLM.OpenSubKey($sub, $true)
    if ($null -ne $k) { $k.DeleteValue('ExtraMode', $false); $k.Close() }
    Note ('[resolution] Modes is ' + $entry + ', ExtraMode removed: Windows stays at ' + $want)
  } else {
    # follows: Modes removed only when it is the one entry this module writes, so a list made in the
    # driver's helper window stays; ExtraMode removed.
    $k = $HKLM.OpenSubKey($sub, $true)
    if ($null -ne $k) {
      if ($k.GetValueNames() -contains 'Modes') {
        $modes = @($k.GetValue('Modes'))
        if ($k.GetValueKind('Modes') -eq [Microsoft.Win32.RegistryValueKind]::MultiString -and $modes.Count -eq 1 -and $modes[0] -match '^[0-9]+x[0-9]+@[0-9]+(\.[0-9]{1,4})?\*$') {
          $k.DeleteValue('Modes', $false)
          Note ('[resolution] Modes ' + $modes[0] + ' removed')
        } else {
          Note '[resolution] Modes kept: it is not the one entry this module writes'
        }
      }
      $k.DeleteValue('ExtraMode', $false)
      $k.Close()
    }
    Note '[resolution] ExtraMode removed: Windows follows the glass window'
  }
  try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note '[resolution] restart mark set: the display driver reads these values at its next start' }
  catch { Note ('[resolution] FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
}
Note '[resolution] done'
