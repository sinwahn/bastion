# Bastion Firefox privacy tool. Interactive. Run through run-ffpriv.cmd as administrator.
# Sets locked about:config prefs via Firefox AutoConfig (machine-wide, every profile) or a
# user.js in one profile. DoH is kept OFF in every level so the Bastion gateway stays in
# charge of DNS. Re-run any time to change level or reset.
# Each step, each skip and each failure goes to the screen and to setup.log through Note of
# lib\common.ps1; the menu itself stays on the screen only.
. (Join-Path $PSScriptRoot '..\lib\common.ps1')
$ErrorActionPreference = 'Stop'

# ---- the preference sets, cumulative. Each item: name, value (bool/int/string). ----
function Tier-Baseline {
  @(
    @{n='network.trr.mode'; v=5}                       # DoH OFF: the gateway resolves and logs DNS
    @{n='network.dns.disablePrefetch'; v=$true}
    @{n='network.prefetch-next'; v=$false}
    @{n='network.predictor.enabled'; v=$false}
    @{n='beacon.enabled'; v=$false}
  )
}
function Tier-T1 {
  (Tier-Baseline) + @(
    @{n='geo.enabled'; v=$false}
    @{n='network.captive-portal-service.enabled'; v=$false}
    @{n='network.connectivity-service.enabled'; v=$false}
    @{n='captivedetect.canonicalURL'; v=''}
    @{n='app.normandy.enabled'; v=$false}
    @{n='app.shield.optoutstudies.enabled'; v=$false}
    @{n='browser.tabs.crashReporting.sendReport'; v=$false}
    @{n='breakpad.reportURL'; v=''}
    @{n='extensions.formautofill.addresses.enabled'; v=$false}
    @{n='extensions.formautofill.creditCards.enabled'; v=$false}
    @{n='dom.event.clipboardevents.enabled'; v=$false}
    @{n='network.http.referer.XOriginPolicy'; v=2}
    @{n='network.http.referer.XOriginTrimmingPolicy'; v=2}
  )
}
function Tier-T2 {
  (Tier-T1) + @(
    @{n='network.cookie.cookieBehavior'; v=5}          # Total Cookie Protection (dFPI)
    @{n='privacy.trackingprotection.enabled'; v=$true}
    @{n='privacy.trackingprotection.socialtracking.enabled'; v=$true}
    @{n='media.peerconnection.ice.default_address_only'; v=$true}
    @{n='media.peerconnection.ice.no_host'; v=$true}
  )
}
function Tier-T3 {
  (Tier-T2) + @(
    @{n='privacy.resistFingerprinting'; v=$true}
    @{n='privacy.resistFingerprinting.letterboxing'; v=$true}
  )
}
function Tier-Set([string]$name) {
  switch ($name) {
    'baseline' { Tier-Baseline }
    't1' { Tier-T1 }
    't2' { Tier-T2 }
    't3' { Tier-T3 }
    default { @() }
  }
}

function Jsval($v) {
  if ($v -is [bool]) { if ($v) { 'true' } else { 'false' } }
  elseif ($v -is [int]) { "$v" }
  else { '"' + ($v -replace '"','\"') + '"' }
}

function Find-FirefoxDir {
  foreach ($p in @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox")) {
    if (Test-Path -LiteralPath (Join-Path $p 'firefox.exe')) { return $p }
  }
  return $null
}

function Current-Tier([string]$dir) {
  $cfg = Join-Path $dir 'firefox.cfg'
  if (-not (Test-Path -LiteralPath $cfg)) { return 'none' }
  $first = Get-Content -LiteralPath $cfg -TotalCount 1
  if ($first -match 'tier=(\w+)') { return $Matches[1] } else { return 'custom' }
}

function Apply-Machine([string]$dir, [string]$tierName, $prefs) {
  $apref = Join-Path $dir 'defaults\pref'
  New-Item -ItemType Directory -Force -Path $apref | Out-Null
  $autocfg = "pref(`"general.config.filename`", `"firefox.cfg`");`npref(`"general.config.obscure_value`", 0);`n"
  [IO.File]::WriteAllText((Join-Path $apref 'autoconfig.js'), $autocfg)
  $lines = @("// Bastion-Firefox-Privacy tier=$tierName generated $(Get-Date -Format s)")
  foreach ($p in $prefs) { $lines += ('lockPref("' + $p.n + '", ' + (Jsval $p.v) + ');') }
  [IO.File]::WriteAllText((Join-Path $dir 'firefox.cfg'), ($lines -join "`n") + "`n")
}

function Reset-Machine([string]$dir) {
  Remove-Item -LiteralPath (Join-Path $dir 'firefox.cfg') -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $dir 'defaults\pref\autoconfig.js') -ErrorAction SilentlyContinue
}

function List-Profiles {
  $ini = Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'
  if (-not (Test-Path -LiteralPath $ini)) { return @() }
  $base = Join-Path $env:APPDATA 'Mozilla\Firefox'
  $res = @(); $path = $null; $rel = $true
  foreach ($ln in Get-Content -LiteralPath $ini) {
    if ($ln -match '^\[Profile') { if ($path) { $res += ($(if ($rel) { Join-Path $base $path } else { $path })) }; $path = $null; $rel = $true }
    elseif ($ln -match '^Path=(.+)$') { $path = $Matches[1] -replace '/','\' }
    elseif ($ln -match '^IsRelative=(\d)') { $rel = ($Matches[1] -eq '1') }
  }
  if ($path) { $res += ($(if ($rel) { Join-Path $base $path } else { $path })) }
  return $res
}
function Apply-Profile([string]$profDir, [string]$tierName, $prefs) {
  New-Item -ItemType Directory -Force -Path $profDir | Out-Null
  $lines = @("// Bastion-Firefox-Privacy tier=$tierName (user.js, this profile)")
  foreach ($p in $prefs) { $lines += ('user_pref("' + $p.n + '", ' + (Jsval $p.v) + ');') }
  [IO.File]::WriteAllText((Join-Path $profDir 'user.js'), ($lines -join "`n") + "`n")
}

# ---- test hook: dump every tier and exit (no menu) ----
if ($env:BASTION_DUMP) {
  foreach ($t in 'baseline','t1','t2','t3') {
    Write-Host "===== $t ====="
    foreach ($p in (Tier-Set $t)) { Write-Host ('lockPref("' + $p.n + '", ' + (Jsval $p.v) + ');') }
  }
  exit 0
}

Note '[ffpriv] Firefox privacy tool'
$dir = Find-FirefoxDir
if ($null -eq $dir) { Note '[ffpriv] Firefox is not installed here - skipped. Install it first (run-getint.cmd).'; Note '[ffpriv] done'; exit 1 }
Note ('[ffpriv] Firefox: ' + $dir + ', machine level now: ' + (Current-Tier $dir))

while ($true) {
  Write-Host ''
  Write-Host '=============================================='
  Write-Host ' Bastion Firefox privacy'
  Write-Host (' Firefox: ' + $dir)
  Write-Host (' Machine level now: ' + (Current-Tier $dir))
  Write-Host '----------------------------------------------'
  Write-Host ' Scope:'
  Write-Host '  [M] whole machine (every profile, locked)   <- recommended'
  Write-Host '  [P] one Firefox profile (user.js, unlocked)'
  Write-Host '  [Q] quit'
  $scope = (Read-Host ' choose M / P / Q').Trim().ToUpper()
  if ($scope -eq 'Q') { break }
  if ($scope -ne 'M' -and $scope -ne 'P') { continue }

  Write-Host ''
  Write-Host ' Level:'
  Write-Host '  [0] reset   - remove Bastion prefs (Firefox own defaults)'
  Write-Host '  [1] baseline- DoH off + no prefetch/beacon (safe, Bastion-correct)'
  Write-Host '  [2] T1      - baseline + safe hardening (geo/referer/clipboard/normandy)'
  Write-Host '  [3] T2      - T1 + strict cookies + WebRTC leak guard (mild breakage)'
  Write-Host '  [4] T3      - T2 + resistFingerprinting + letterboxing (breaks tz/canvas/size)'
  Write-Host '  [B] back'
  $lvl = (Read-Host ' choose 0 / 1 / 2 / 3 / 4 / B').Trim().ToUpper()
  $map = @{ '1'='baseline'; '2'='t1'; '3'='t2'; '4'='t3' }
  if ($lvl -eq 'B') { continue }

  try {
    if ($scope -eq 'M') {
      if ($lvl -eq '0') { Reset-Machine $dir; Note '[ffpriv] Bastion prefs removed machine-wide' }
      elseif ($map.ContainsKey($lvl)) { $t = $map[$lvl]; Apply-Machine $dir $t (Tier-Set $t); Note ("[ffpriv] level $t locked machine-wide (" + (Tier-Set $t).Count + ' prefs)') }
      else { Write-Host ' not a level'; continue }
    } else {
      $profs = List-Profiles
      if ($profs.Count -eq 0) { Note '[ffpriv] no Firefox profiles yet - skipped. Start Firefox once, then re-run.'; continue }
      for ($i=0; $i -lt $profs.Count; $i++) { Write-Host ("  [$i] " + $profs[$i]) }
      $pi = (Read-Host ' profile number').Trim()
      if (-not ($pi -match '^\d+$') -or [int]$pi -ge $profs.Count) { Write-Host ' bad number'; continue }
      $pd = $profs[[int]$pi]
      if ($lvl -eq '0') { Remove-Item -LiteralPath (Join-Path $pd 'user.js') -ErrorAction SilentlyContinue; Note ('[ffpriv] user.js removed from the profile ' + $pd) }
      elseif ($map.ContainsKey($lvl)) { $t = $map[$lvl]; Apply-Profile $pd $t (Tier-Set $t); Note ("[ffpriv] level $t written to the user.js of the profile " + $pd) }
      else { Write-Host ' not a level'; continue }
    }
  } catch { Note ('[ffpriv] FAILED: ' + $_.Exception.Message); continue }
  Write-Host ' Restart Firefox for it to take effect.'
}
Note '[ffpriv] done'
