. (Join-Path $PSScriptRoot '..\lib\common.ps1')
# The Windows application id, as Microsoft's slmgr.vbs defines it: its constant WindowsAppId, line 495
# (SLMGR below).
$windowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'
# ActivateWindows activates Windows with a product key the user types at this console, through Windows' own
# licensing interfaces, the Software Licensing WMI provider. The key is held in $key alone: it goes to the
# WMI method as its argument and nowhere else, never on a command line, never in a line on the screen or in
# setup.log; $key is cleared after the calls. An activated Windows is skipped and nothing is asked.
# Sources: the Software Licensing WMI provider's pages of learn.microsoft.com (sppwmi):
# softwarelicensingproduct (git 6203eafab56a1bcadfd7289916a51fe8fc0ad4f0, PRODUCT), softwarelicensingservice
# (git 2922ae3fd5cbeb52b8f10529ac02fc651bbd56ee, SERVICE), activate-softwarelicensingproduct,
# installproductkey-softwarelicensingservice and refreshlicensestatus-softwarelicensingservice (each git
# 8f0f213225c3910b3f1469befc467fdb5aa26952), all in Root\CIMV2; Microsoft's slmgr.vbs in System32, read
# 2026-10-27 (SLMGR); PowerShell-Docs reference/5.1 (PS): Microsoft.PowerShell.Management/Get-WmiObject.md
# (git 02660c1b01915f250fcd96288edf555600dbb54a) and Microsoft.PowerShell.Utility/Read-Host.md (git
# 1cb441b22beb8a0629daae83e24d96bf85d16f1e); win32-pr 4b1605e37433015369a0de737a0d4565202db75c
# WmiSdk/calling-a-provider-method.md (CALL); dotnet-api-docs ff6ab9d92a3fc276589a73ae80fd3c7df264608e
# xml/System/Exception.xml (NET); Microsoft's activation errors page, "Get help with Windows activation
# errors", https://support.microsoft.com/en-us/windows/get-help-with-windows-activation-errors-09d8fb64-6768-4815-0c30-159fa7d89d85
# fetched whole 2026-10-27 (ERRORS).
# - The Windows product: SoftwareLicensingProduct read with Get-WmiObject -Class -Filter (PS
#   Get-WmiObject.md, -Class, -Filter), the instance SLMGR acts on: PartialProductKey <> null (SLMGR 500,
#   1095; PRODUCT, PartialProductKey: "Returns a null value if a product key is not installed"), its
#   ApplicationID in lower case equal to $windowsAppId and its LicenseIsAddon false (SLMGR 931).
# - Licensed is LicenseStatus 1; $statusNames holds the page's names for 0 to 6 (PRODUCT, LicenseStatus).
#   LicenseStatusReason (PRODUCT) is shown in hexadecimal, as SLMGR 1603 shows it.
# - The question: Read-Host -Prompt, to whose text PowerShell appends the colon (PS Read-Host.md, -Prompt);
#   an answer that is empty after Trim is Enter.
# - With a key: SoftwareLicensingService.InstallProductKey with the key, then RefreshLicenseStatus (SERVICE;
#   SLMGR 1761, 1767); the product read again (SLMGR 1769); SoftwareLicensingProduct.Activate, then
#   RefreshLicenseStatus and the product read again (SLMGR 1122-1125); its LicenseStatus. Each method is
#   called on the object Get-WmiObject returns (PS Get-WmiObject.md, Example 5). The method pages give each a
#   uint32 return and no return section, so a value other than 0 is logged as a code; it is read from the
#   ReturnValue of the method's result (CALL: "the return value is in the property ReturnValue").
# - A call that throws (CALL's PowerShell example: the call in try and catch): Windows' code and message from
#   the innermost exception PowerShell hands over, its InnerException, HResult and Message (NET 866, 814, 926).
# - The words for a code: the first sentence of each entry of ERRORS that lists the code; for the entry of 17
#   codes, the first sentence of each of its three bullets. ERRORS has a section for Windows 11 and one for
#   Windows 10, whose first sentences differ only in that name: {windows} stands for it, Windows 11 from build
#   22000 on, as 97-exchange decides. The page's typographic apostrophes are written as '; 0x803FA067L is
#   keyed as 803FA067; 0xC004C4A2, listed twice in one entry, stands once.
# - Activate is the one call that reaches Microsoft: every failure of it names the way, the VM's internet
#   rule opened in bastion, then run.cmd activation.
$statusNames = @{ 0 = 'Unlicensed'; 1 = 'Licensed'; 2 = 'OOBGrace'; 3 = 'OOTGrace'; 4 = 'NonGenuineGrace'; 5 = 'Notification'; 6 = 'ExtendedGrace' }
$windows = 'Windows 10'
if ([System.Environment]::OSVersion.Version.Build -ge 22000) { $windows = 'Windows 11' }
$errorWords = @(
  @{ codes = @('C004F211'); words = 'Windows reported that the hardware of your device has changed.' },
  @{ codes = @('C004F213'); words = 'Windows reported that no product key was found on your device.' },
  @{ codes = @('C004F212'); words = 'The product key used on this device isn''t compatible with this edition of Windows.' },
  @{ codes = @('803F7001'); words = 'If you encounter error code 0x803F7001, it indicates that a valid {windows} license could not be found to activate Windows on your device.' },
  @{ codes = @('800704CF'); words = 'This error means we didn''t find a valid Windows license for your device.' },
  @{ codes = @('C004C060', 'C004C4A2', '803FA067', 'C004C001', 'C004C004', 'C004F004', 'C004C007', 'C004F005', 'C004C00F', 'C004C010', 'C004C00E', 'C004C4A4', 'C004C4A5', 'C004B001', 'C004F010', 'C004F050');
    words = 'You entered a product key that can''t be used to activate Windows. You upgraded to {windows}, but the activation servers were busy. You upgraded to {windows} using the free upgrade offer, but {windows} isn''t activated after a reinstall.' },
  @{ codes = @('C004C003'); words = 'You may see this error because the {windows} product key you entered isn''t valid.' },
  @{ codes = @('C004F034'); words = 'You might see this error if you entered an invalid product key or a product key for a different version of Windows.' },
  @{ codes = @('C004F210'); words = 'You might see this error if you entered a product key for a different edition of Windows than the edition installed on your device.' },
  @{ codes = @('C004E016', 'C004F210'); words = 'You might see this error if you entered a product key for a different version or edition of Windows.' },
  @{ codes = @('C004FC03'); words = 'You might see this error if you''re not connected to the internet or your firewall settings are preventing Windows from completing the activation process online.' },
  @{ codes = @('C004E028'); words = 'You might see this error if you try to activate a device that is already in the process of activation.' },
  @{ codes = @('8007267C'); words = 'You might see this error if you''re not connected to the internet or the activation server is temporarily unavailable.' },
  @{ codes = @('D0000272', 'C0000272', 'C004C012', 'C004C013', 'C004C014'); words = 'If the activation server is temporarily unavailable, your copy of Windows will automatically be activated when the service comes back online.' },
  @{ codes = @('C004C008', 'C004C770', '803FA071'); words = 'You might see this error if the product key has already been used on another device, or it''s being used on more devices than the Microsoft Software License Terms allow.' },
  @{ codes = @('C004F00F'); words = 'You might see this error if you entered a product key for the Enterprise edition of Windows to activate {windows} Home or {windows} Pro.' },
  @{ codes = @('C004C020'); words = 'This error occurs when a Volume License (a license that was bought from Microsoft by an organization to install Windows on multiple devices) was used on more devices than the Microsoft Software License Terms allow.' },
  @{ codes = @('8007232B', 'C004F074', 'C004F038', '8007007B'); words = 'You might see this error if you entered a product key for the Enterprise edition of Windows to activate {windows} Home or {windows} Pro.' },
  @{ codes = @('80072F8F'); words = 'You might see this error if the date and time for the device is incorrect, or Windows has trouble connecting to the online activation service and can''t verify your product key.' },
  @{ codes = @('C004E003'); words = 'You might see this error after installing third-party software that changed system files.' },
  @{ codes = @('80004005'); words = 'Select Start > Settings > Update & Security > Activation, and then select Troubleshoot to run the Activation troubleshooter.' },
  @{ codes = @('87E10BC6'); words = 'An error occurred with our activation server or licensing service.' },
  @{ codes = @('80070652'); words = 'This error can occur if the update components are missing or corrupted on the computer.' }
)
$theWay = 'the way: in bastion on the host, set this VM''s internet rule to open (v, the VM, internet rule), then run.cmd activation.'

# The Windows product as SLMGR chooses it, or $null when no product holds a key.
function WindowsProduct {
  Get-WmiObject -Class SoftwareLicensingProduct -Filter 'PartialProductKey <> null' -ErrorAction Stop |
    Where-Object { ([string]$_.ApplicationID).ToLower() -eq $windowsAppId -and -not $_.LicenseIsAddon } |
    Select-Object -First 1
}
# A FAILED line: what failed, the words of ERRORS for the code when it lists the code, and the way when the
# call is Activate.
function Failed([string]$call, [string]$what, $code) {
  $hex = '{0:X8}' -f $code
  $line = '[activation] FAILED, ' + $call + $what
  $found = @($errorWords | Where-Object { $_.codes -contains $hex } | ForEach-Object { $_.words.Replace('{windows}', $windows) })
  if ($found.Count -gt 0) { $line += ' - Microsoft: ' + ($found -join ' ') }
  if ($call -eq 'Activate') { $line += ' - ' + $theWay }
  Note $line
}
function Returned([string]$call, $value) { Failed $call (' returned 0x' + ('{0:X8}' -f $value)) $value }
function Skipped { if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = 'skipped' } }

function ActivateWindows {
  $key = $null
  $call = 'Get-WmiObject SoftwareLicensingProduct'
  try {
    $product = WindowsProduct
    if ($null -ne $product -and $product.LicenseStatus -eq 1) {
      Note '[activation] Windows is activated - skipped'
      Skipped
      return
    }
    $call = 'Read-Host'
    $key = Read-Host -Prompt 'Windows product key (25 characters with dashes), or Enter to skip'
    if ($null -eq $key -or $key.Trim() -eq '') {
      Note '[activation] no key typed - skipped; run.cmd activation to try again'
      Skipped
      return
    }
    $key = $key.Trim()
    $call = 'Get-WmiObject SoftwareLicensingService'
    $service = Get-WmiObject -Class SoftwareLicensingService -ErrorAction Stop | Select-Object -First 1
    $call = 'InstallProductKey'
    $r = $service.InstallProductKey($key)
    if ($r.ReturnValue -ne 0) { Returned $call $r.ReturnValue; return }
    Note '[activation] installed the typed key'
    $call = 'RefreshLicenseStatus'
    $r = $service.RefreshLicenseStatus()
    if ($r.ReturnValue -ne 0) { Returned $call $r.ReturnValue; return }
    $call = 'Get-WmiObject SoftwareLicensingProduct'
    $product = WindowsProduct
    Note '[activation] activating with Microsoft'
    $call = 'Activate'
    $r = $product.Activate()
    if ($r.ReturnValue -ne 0) { Returned $call $r.ReturnValue; return }
    $call = 'RefreshLicenseStatus'
    $r = $service.RefreshLicenseStatus()
    if ($r.ReturnValue -ne 0) { Returned $call $r.ReturnValue; return }
    $call = 'Get-WmiObject SoftwareLicensingProduct'
    $product = WindowsProduct
    if ($product.LicenseStatus -eq 1) { Note '[activation] Windows is activated' }
    else { Note ('[activation] FAILED, Windows is not activated: LicenseStatus ' + $product.LicenseStatus + ' ' + $statusNames[[int]$product.LicenseStatus] + ', LicenseStatusReason 0x' + ('{0:X8}' -f $product.LicenseStatusReason)) }
  } catch {
    $e = $_.Exception
    while ($null -ne $e.InnerException) { $e = $e.InnerException }
    Failed $call (': 0x' + ('{0:X8}' -f $e.HResult) + ': ' + ([string]$e.Message).Trim()) $e.HResult
  } finally {
    $key = $null
  }
}
Note '[activation] activating Windows with a product key typed at this console: it needs the VM''s internet'
ActivateWindows
