. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[firefox] certificates + AutoConfig prefs + policies (Firefox is installed by 75-installers)'

$ffDir = 'C:\Program Files\Mozilla Firefox'

# 1. certificates: import the CA bundle into the machine Root and CA stores
$p7b = Join-Path $BastionAssets 'roots.p7b'
if (Test-Path -LiteralPath $p7b) {
  try { & certutil.exe -f -addstore Root $p7b | Out-Null; & certutil.exe -f -addstore CA $p7b | Out-Null; Note '[firefox] roots.p7b imported to Root and CA' }
  catch { Note ('[firefox] cert import note: ' + $_.Exception.Message) }
} else { Note '[firefox] assets\roots.p7b not present - skipping cert import' }

# 2. AutoConfig: applies these prefs at every launch, to whatever profile runs, without
#    touching the rest of the profile. lockPref forces; defaultPref is a default you can still change.
if (Test-Path -LiteralPath $ffDir) {
  $cfg = @'
// Bastion Firefox defaults
lockPref("network.trr.mode", 5);
lockPref("browser.ml.chat.enabled", false);
lockPref("browser.ml.chat.menu", false);
defaultPref("browser.startup.page", 3);
defaultPref("browser.ctrlTab.sortByRecentlyUsed", true);
defaultPref("datareporting.healthreport.uploadEnabled", false);
defaultPref("datareporting.policy.dataSubmissionEnabled", false);
defaultPref("app.shield.optoutstudies.enabled", false);
defaultPref("browser.newtabpage.activity-stream.feeds.telemetry", false);
defaultPref("browser.aboutConfig.showWarning", false);
'@
  [System.IO.File]::WriteAllText((Join-Path $ffDir 'firefox.cfg'), ($cfg -replace "`r`n","`n"))
  $ac = @'
pref("general.config.filename", "firefox.cfg");
pref("general.config.obscure_value", 0);
'@
  $acDir = Join-Path $ffDir 'defaults\pref'
  New-Item -ItemType Directory -Force -Path $acDir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $acDir 'autoconfig.js'), ($ac -replace "`r`n","`n"))
  Note '[firefox] AutoConfig written (chatbot off, restore session, ctrlTab recent, DoH off)'

  # 3. policies.json: force-install uBlock Origin + Dark Reader, no default-browser nag, telemetry off
  $pol = @'
{
  "policies": {
    "DontCheckDefaultBrowser": true,
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "NoDefaultBookmarks": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": { "installation_mode": "force_installed", "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi" },
      "addon@darkreader.org": { "installation_mode": "force_installed", "install_url": "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi" }
    }
  }
}
'@
  $distDir = Join-Path $ffDir 'distribution'
  New-Item -ItemType Directory -Force -Path $distDir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $distDir 'policies.json'), $pol)
  Note '[firefox] policies.json written (uBlock + Dark Reader force-installed)'
} else { Note '[firefox] install dir missing - config not written' }
Note '[firefox] done. Default-browser cannot be set by script on Win10 (hash-protected): set it once in Settings, or apply a default-associations file in the template.'
