. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[installers] each installer of assets\installers.json, installed only when missing or older'
# Every rule is data in installers.json: name, ask, installed (how Windows reports the
# installed version), prefix (removed from <file>.version before comparing), switches, restart.
$uninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'

# The installed version as Windows reports it, or $null when the program is missing.
#   kind uninstall: DisplayVersion of the first uninstall entry whose DisplayName is like displayName
#   kind program: the first line the program prints with its args, when it exits with 0
function ReadInstalled($rule) {
  if ($rule.kind -eq 'uninstall') {
    $all = $HKLM.OpenSubKey($uninstallKey)
    if ($null -eq $all) { return $null }
    try {
      foreach ($sub in $all.GetSubKeyNames()) {
        $k = $all.OpenSubKey($sub)
        if ($null -eq $k) { continue }
        $dn = $k.GetValue('DisplayName'); $dv = $k.GetValue('DisplayVersion'); $k.Close()
        if ($dn -like $rule.displayName -and $dv) { return [string]$dv }
      }
    } finally { $all.Close() }
    return $null
  }
  if ($rule.kind -eq 'program') {
    $cmd = Get-Command -Name $rule.program -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { return $null }
    $progArgs = @($rule.args)
    $out = & $cmd.Path @progArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $line = @($out) | Where-Object { ([string]$_).Trim() } | Select-Object -First 1
    if ($line) { return ([string]$line).Trim() }
  }
  return $null
}

# Compares the installed version with the one on the stick (<file>.version).
# Returns install ($true or $false) and state, the line noted for this entry.
function Decide($e, $installed, $onStick) {
  $name = [string]$e.name
  if (-not $installed) {
    if ($onStick) { return @{ install = $true; state = ($name + ': not installed, on the stick ' + $onStick) } }
    return @{ install = $true; state = ($name + ': not installed, version on the stick not known') }
  }
  if (-not $onStick) { return @{ install = $false; state = ($name + ': installed ' + $installed + ', version on the stick not known - nothing installed') } }
  $want = $onStick
  if ($e.prefix -and $want.StartsWith([string]$e.prefix, [System.StringComparison]::Ordinal)) { $want = $want.Substring(([string]$e.prefix).Length) }
  $have = $null; $new = $null
  if (-not ([version]::TryParse($installed, [ref]$have) -and [version]::TryParse($want, [ref]$new))) {
    return @{ install = $false; state = ($name + ': installed ' + $installed + ', on the stick ' + $onStick + ' - the versions cannot be compared, nothing installed') }
  }
  if ($have.CompareTo($new) -lt 0) { return @{ install = $true; state = ($name + ': installed ' + $installed + ', on the stick ' + $onStick) } }
  return @{ install = $false; state = ($name + ' ' + $installed + ' is current - nothing installed') }
}

$list = Get-Content -LiteralPath (Join-Path $BastionAssets 'installers.json') -Raw | ConvertFrom-Json
foreach ($e in @($list.installers)) {
  $setup = Join-Path $BastionAssets $e.file
  if (-not (Test-Path -LiteralPath $setup)) { Note ('[installers] ' + $e.name + ': assets\' + $e.file + ' not found - skipped'); continue }
  $onStick = $null
  if (Test-Path -LiteralPath ($setup + '.version')) { $onStick = (Get-Content -LiteralPath ($setup + '.version') -Raw).Trim() }
  $d = Decide $e (ReadInstalled $e.installed) $onStick
  if (-not $d.install) { Note ('[installers] ' + $d.state); continue }
  if ($e.ask) {
    Note ('[installers] ' + $d.state)
    if ($onStick) { $q = 'Install ' + $e.name + ' ' + $onStick + '? (y/n)' } else { $q = 'Install ' + $e.name + ' (version on the stick not known)? (y/n)' }
    if ((Read-Host -Prompt $q) -ne 'y') { Note ('[installers] ' + $e.name + ': not installed (answered n)'); continue }
    Note ('[installers] ' + $e.name + ': installing')
  } else { Note ('[installers] ' + $d.state + ' - installing') }
  try {
    $p = Start-Process -FilePath $setup -ArgumentList @($e.switches) -Wait -PassThru
    Note ('[installers] ' + $e.name + ' installer exit ' + $p.ExitCode)
    if ($e.restart) { New-Item -ItemType File -Force -Path $BastionRestart | Out-Null }
  } catch { Note ('[installers] ' + $e.name + ' install failed: ' + $_.Exception.Message) }
}
Note '[installers] done'
