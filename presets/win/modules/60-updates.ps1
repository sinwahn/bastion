. (Join-Path $PSScriptRoot '..\lib\common.ps1')
# InstallUpdates installs the updates Windows Update offers this Windows, through the Windows Update
# Agent's interfaces, in the order of Microsoft's sample (SAMPLE below): the search, a line per update
# found, the updates kept downloaded in one call, the downloaded ones installed, a line per result. Then
# the module sets the two policy values, as before; nothing installs by itself afterwards.
# Sources: MicrosoftDocs/sdk-api 656e9656bfaef34dd29cd7ee9e1146aec17e924c sdk-api-src/content/wuapi
# (WUA, the pages of learn.microsoft.com windows/win32/api/wuapi); MicrosoftDocs/win32
# ca8274decead49403d70ceeed4af8d4ca74eaf11 desktop-src/Wua_Sdk/searching--downloading--and-installing-updates.md
# (SAMPLE); dotnet-api-docs ff6ab9d92a3fc276589a73ae80fd3c7df264608e xml/System/Exception.xml (NET);
# PowerShell-Docs a3de8f22552170e70852470d46cd52cd9ca471ec reference/5.1 (PS).
# - The session: New-Object -ComObject (PS Microsoft.PowerShell.Utility/New-Object.md 28, 238) with the
#   program identifier Microsoft.Update.Session (WUA nn-wuapi-iupdatesession.md 61; SAMPLE 217).
# - The search: CreateUpdateSearcher (nf-wuapi-iupdatesession-createupdatesearcher.md 4; SAMPLE 231),
#   Search with IsInstalled=0, IsHidden=0 and Type='Software' joined by and (nf-wuapi-iupdatesearcher-search.md
#   4, 120, 124, 138-142, 243-251, 256-264; SAMPLE 151, 243), its Updates, Count and Item
#   (nf-wuapi-isearchresult-get_updates.md 4, nf-wuapi-iupdatecollection-get_count.md 4, -get_item.md 4;
#   SAMPLE 249-250).
# - Each update: Title (nf-wuapi-iupdate-get_title.md 4) and MaxDownloadSize, the maximum download size
#   (nf-wuapi-iupdate-get_maxdownloadsize.md 54, 62). That page names no unit: it is read as bytes and
#   shown in MB with one decimal.
# - Kept or skipped as SAMPLE 314-347 keeps or skips it: InstallationBehavior.CanRequestUserInput
#   (nf-wuapi-iupdate-get_installationbehavior.md 4, nf-wuapi-iinstallationbehavior-get_canrequestuserinput.md
#   4) true skips it; EulaAccepted false (nf-wuapi-iupdate-get_eulaaccepted.md 4) shows EulaText
#   (nf-wuapi-iupdate-get_eulatext.md 4) on the screen and asks with Read-Host (PS
#   Microsoft.PowerShell.Utility/Read-Host.md 19, 121); y calls AcceptEula (nf-wuapi-iupdate-accepteula.md
#   4), anything else skips it. A property that cannot be read counts as SAMPLE 314-325 counts it.
# - The download: Microsoft.Update.UpdateColl and Add (nn-wuapi-iupdatecollection.md 61,
#   nf-wuapi-iupdatecollection-add.md 4; SAMPLE 260, 376), CreateUpdateDownloader, Updates and Download
#   (nf-wuapi-iupdatesession-createupdatedownloader.md 4, nf-wuapi-iupdatedownloader-put_updates.md 4,
#   nf-wuapi-iupdatedownloader-download.md 4; SAMPLE 401-403), never with an empty collection (download.md
#   111); IsDownloaded (nf-wuapi-iupdate-get_isdownloaded.md 4; SAMPLE 407-411) keeps an update for the
#   install; for one not downloaded, its download result (nf-wuapi-idownloadresult-getupdateresult.md 4, 59;
#   nf-wuapi-iupdatedownloadresult-get_resultcode.md 4, -get_hresult.md 4).
# - The install: CreateUpdateInstaller, Updates and Install (nf-wuapi-iupdatesession-createupdateinstaller.md
#   4, nf-wuapi-iupdateinstaller-put_updates.md 4, nf-wuapi-iupdateinstaller-install.md 4; SAMPLE 442-445),
#   never with an empty collection (install.md 111). An update whose InstallationBehavior.Impact is 2,
#   iiRequiresExclusiveHandling, cannot share an Install call with any other update
#   (nf-wuapi-iinstallationbehavior-get_impact.md 4, ne-wuapi-installationimpact.md 76-78; SAMPLE 349-360,
#   378-384): the other updates are installed first, together, then each such update in an Install call of
#   its own. Each update's result: GetUpdateResult (nf-wuapi-iinstallationresult-getupdateresult.md 4, 59;
#   SAMPLE 456-460), its ResultCode, HResult and RebootRequired
#   (nf-wuapi-iupdateinstallationresult-get_resultcode.md 4, -get_hresult.md 4, -get_rebootrequired.md 4),
#   the code's name from OperationResultCode (ne-wuapi-operationresultcode.md 59-79); 4 and 5 are FAILED.
# - A call that throws: Windows' code and message from the innermost exception PowerShell hands over, its
#   InnerException, HResult and Message (NET Exception.xml 866, 814, 926).
# - The policy values: NoAutoUpdate 1, Automatic Updates disabled, and NoAutoRebootWithLoggedOnUsers 1, no
#   automatic restart while users are logged on (learn.microsoft.com windows/deployment/update/waas-wu-settings,
#   git 73576177d4d886516747c93075421703aa369d2d, "Configuring Automatic Updates by editing the registry").
function InstallUpdates {
  Note '[updates] installing the updates Windows Update offers this Windows: they download from Microsoft, which may take long'
  $names = @{ 0 = 'orcNotStarted'; 1 = 'orcInProgress'; 2 = 'orcSucceeded'; 3 = 'orcSucceededWithErrors'; 4 = 'orcFailed'; 5 = 'orcAborted' }
  $culture = [System.Globalization.CultureInfo]::InvariantCulture
  $call = 'New-Object -ComObject Microsoft.Update.Session'
  try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $call = 'CreateUpdateSearcher'
    $searcher = $session.CreateUpdateSearcher()
    $call = 'Search'
    $found = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'").Updates
    if ($found.Count -eq 0) {
      Note '[updates] Windows Update offers no update - nothing installed'
      return
    }
    $call = 'New-Object -ComObject Microsoft.Update.UpdateColl'
    $download = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $found.Count; $i++) {
      $call = 'Item'
      $u = $found.Item($i)
      $call = 'MaxDownloadSize'
      $mb = [math]::Round(([decimal]$u.MaxDownloadSize) / 1MB, 1)
      $call = 'Title'
      Note ('[updates] ' + $u.Title + ', up to ' + $mb.ToString('0.0', $culture) + ' MB')
      $asks = $false
      try { $asks = $u.InstallationBehavior.CanRequestUserInput } catch { }
      if ($asks) {
        Note ('[updates] ' + $u.Title + ': skipped, it can ask for user input')
        continue
      }
      $accepted = $true
      try { $accepted = $u.EulaAccepted } catch { }
      if (-not $accepted) {
        Note ('[updates] ' + $u.Title + ' has a license that must be accepted:')
        $call = 'EulaText'
        Write-Host $u.EulaText
        $call = 'Read-Host'
        if ((Read-Host -Prompt ('accept the license of ' + $u.Title + '? (y/n)')) -ne 'y') {
          Note ('[updates] ' + $u.Title + ': skipped, its license was not accepted (answered n)')
          continue
        }
        $call = 'AcceptEula'
        $u.AcceptEula()
        Note ('[updates] ' + $u.Title + ': license accepted (answered y)')
      }
      $call = 'Add'
      [void]$download.Add($u)
    }
    if ($download.Count -eq 0) {
      Note '[updates] no update left to download - nothing installed'
      return
    }
    $call = 'CreateUpdateDownloader'
    $downloader = $session.CreateUpdateDownloader()
    $call = 'Updates'
    $downloader.Updates = $download
    $call = 'Download'
    $got = $downloader.Download()
    $call = 'New-Object -ComObject Microsoft.Update.UpdateColl'
    $together = New-Object -ComObject Microsoft.Update.UpdateColl
    $calls = @()
    for ($i = 0; $i -lt $download.Count; $i++) {
      $call = 'Item'
      $u = $download.Item($i)
      $call = 'IsDownloaded'
      if (-not $u.IsDownloaded) {
        $call = 'GetUpdateResult'
        $r = $got.GetUpdateResult($i)
        $line = '[updates] ' + $u.Title + ': not downloaded, download result ' + $r.ResultCode + ' ' + $names[[int]$r.ResultCode]
        if ($r.ResultCode -eq 4 -or $r.ResultCode -eq 5) { $line += ', FAILED' }
        if ($r.ResultCode -eq 4 -or $r.ResultCode -eq 5 -or $r.HResult -ne 0) { $line += ', HResult 0x' + ('{0:X8}' -f $r.HResult) }
        Note ($line + ' - not installed')
        continue
      }
      $impact = 0
      try { $impact = $u.InstallationBehavior.Impact } catch { }
      if ($impact -eq 2) {
        $call = 'New-Object -ComObject Microsoft.Update.UpdateColl'
        $one = New-Object -ComObject Microsoft.Update.UpdateColl
        $call = 'Add'
        [void]$one.Add($u)
        $calls += @{ updates = $one; alone = $u.Title }
      } else {
        $call = 'Add'
        [void]$together.Add($u)
      }
    }
    if ($together.Count -gt 0) { $calls = @(@{ updates = $together; alone = $null }) + $calls }
    if ($calls.Count -eq 0) {
      Note '[updates] no update was downloaded - nothing installed'
      return
    }
    foreach ($c in $calls) {
      if ($null -ne $c.alone) { Note ('[updates] ' + $c.alone + ' is exclusive: installing it in an Install call of its own') }
      $call = 'CreateUpdateInstaller'
      $installer = $session.CreateUpdateInstaller()
      $call = 'Updates'
      $installer.Updates = $c.updates
      $call = 'Install'
      $done = $installer.Install()
      $why = @()
      for ($i = 0; $i -lt $c.updates.Count; $i++) {
        $call = 'Item'
        $title = $c.updates.Item($i).Title
        $call = 'GetUpdateResult'
        $r = $done.GetUpdateResult($i)
        $line = '[updates] ' + $title + ': result ' + $r.ResultCode + ' ' + $names[[int]$r.ResultCode]
        if ($r.ResultCode -eq 4 -or $r.ResultCode -eq 5) { $line += ', FAILED' }
        if ($r.ResultCode -eq 4 -or $r.ResultCode -eq 5 -or $r.HResult -ne 0) { $line += ', HResult 0x' + ('{0:X8}' -f $r.HResult) }
        Note $line
        if ($r.RebootRequired) { $why += $title }
      }
      if ($why.Count -gt 0) {
        try { New-Item -ItemType File -Force -Path $BastionRestart -ErrorAction Stop | Out-Null; Note ('[updates] restart mark set: Windows needs a restart after ' + ($why -join ', ')) }
        catch { Note ('[updates] FAILED to set the restart mark ' + $BastionRestart + ': ' + $_.Exception.Message) }
      }
    }
  } catch {
    $e = $_.Exception
    while ($null -ne $e.InnerException) { $e = $e.InnerException }
    Note ('[updates] FAILED, ' + $call + ': 0x' + ('{0:X8}' -f $e.HResult) + ': ' + ([string]$e.Message).Trim() + ' - the way: in bastion on the host, set this VM''s internet rule to open (v, the VM, internet rule), then run.cmd updates.')
  }
}
InstallUpdates
Note '[updates] disabling automatic Windows Update (NoAutoUpdate 1) and restarts by itself while a user is logged on (NoAutoRebootWithLoggedOnUsers 1); LTSC honors this policy'
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
SetV $HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
Note '[updates] automatic updates and surprise reboots off. Nothing installs unless you start it.'
