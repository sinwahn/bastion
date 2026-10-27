. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[display] the Looking Glass display as the only display Windows shows the desktop on'
# The Looking Glass display is made the only active display, told by what it is and never by its number,
# and the configuration is saved to Windows' display database, so it holds across restarts. The device is
# found from Windows' own data by the two hardware ids the driver's INF declares; the display path whose
# adapter is that device stays active, every other path is made inactive. A re-run changes nothing while
# the Looking Glass display is the only active one; run.cmd display brings it back after a repair.
# Sources: gnif/LookingGlass cdba29f2f6bcae3ded26369fc231a067cbca3752 (LG); MicrosoftDocs/sdk-api
# 656e9656bfaef34dd29cd7ee9e1146aec17e924c sdk-api-src/content (SDK, the pages of learn.microsoft.com
# windows/win32/api; each structure's members, their types and order from the Syntax block of its page);
# MicrosoftDocs/win32 ca8274decead49403d70ceeed4af8d4ca74eaf11 desktop-src (W32); PowerShell-Docs
# a3de8f22552170e70852470d46cd52cd9ca471ec reference/5.1 (PS); dotnet-api-docs
# ff6ab9d92a3fc276589a73ae80fd3c7df264608e xml (NET); dotnet/docs 2e59bda0361d688287bb5c1bb19962ac0654449d
# docs/standard/native-interop (DOCS).
# - The device: Get-CimInstance -ClassName Win32_PnPEntity in its default namespace root/CIMV2 (PS
#   CimCmdlets/Get-CimInstance.md 23, 243, 354; W32 CIMWin32Prov/win32-pnpentity.md 49, 1371), its
#   HardwareID (831-840), PNPDeviceID (956-968), Status (1132-1144) and ConfigManagerErrorCode (369-381);
#   the ids compared without case by -ieq (PS Microsoft.PowerShell.Core/About/about_Comparison_Operators.md
#   23, 57, 61).
# - The paths: GetDisplayConfigBufferSizes and QueryDisplayConfig with QDC_ALL_PATHS, again while the
#   result is ERROR_INSUFFICIENT_BUFFER (SDK winuser/nf-winuser-getdisplayconfigbuffersizes.md 71, 87, 91;
#   nf-winuser-querydisplayconfig.md 72-74, 161-173, 264, 266, 274, 310-330).
# - The names: DisplayConfigGetDeviceInfo (nf-winuser-displayconfiggetdeviceinfo.md 63) with the header
#   (wingdi/ns-wingdi-displayconfig_device_info_header.md 57-71), DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME 2
#   and GET_ADAPTER_NAME 4 (ne-wingdi-displayconfig_device_info_type.md 61, 69), DISPLAYCONFIG_ADAPTER_NAME
#   (ns-wingdi-displayconfig_adapter_name.md 59, 63) and DISPLAYCONFIG_TARGET_DEVICE_NAME
#   (ns-wingdi-displayconfig_target_device_name.md 59, 83, 87, 95: a NULL friendly name when Windows cannot
#   get it, so the monitor's device path names it then).
# - The device of an adapter: its adapterDevicePath "can be used with SetupAPI.dll" (adapter_name.md 63);
#   a new device information set (setupapi/nf-setupapi-setupdicreatedeviceinfolist.md 57, 67, 71; a handle of
#   0 or -1 is invalid, NET Microsoft.Win32.SafeHandles/SafeHandleZeroOrMinusOneIsInvalid.xml 43), the
#   interface opened in it (nf-setupapi-setupdiopendeviceinterfacew.md 81, 94, 102), the device's
#   SP_DEVINFO_DATA alone (nf-setupapi-setupdigetdeviceinterfacedetailw.md 85, 107), its device instance id
#   (nf-setupapi-setupdigetdeviceinstanceidw.md 75, 83), then SetupDiDeleteDeviceInterfaceData and
#   SetupDiDestroyDeviceInfoList (nf-setupapi-setupdideletedeviceinterfacedata.md 72,
#   nf-setupapi-setupdidestroydeviceinfolist.md 58); each cbSize the structure's size
#   (ns-setupapi-sp_devinfo_data.md 63, ns-setupapi-sp_device_interface_data.md 63).
# - The Looking Glass path: its adapter's device instance id is a matched PNPDeviceID and its target is
#   available (ns-wingdi-displayconfig_path_target_info.md 103-105); the first active one, else the first in
#   the order QueryDisplayConfig returns them.
# - The change: DISPLAYCONFIG_PATH_ACTIVE (ns-wingdi-displayconfig_path_info.md 78) cleared on every other
#   path and set on the Looking Glass path; SetDisplayConfig with SDC_APPLY, SDC_USE_SUPPLIED_DISPLAY_CONFIG,
#   SDC_SAVE_TO_DATABASE and SDC_ALLOW_CHANGES (winuser/nf-winuser-setdisplayconfig.md 66, 87-89, 107-109,
#   117-123, 137-139, 264-280, 381, 391).
# - The codes' names: W32 Debug/system-error-codes--0-499-.md 18-21, 83-86, 421-424, 512-515, 889-892,
#   1188-1191 and system-error-codes--1300-1699-.md 2449-2452.
# - The helper: Add-Type -MemberDefinition (PS Microsoft.PowerShell.Utility/Add-Type.md 487-491, 510,
#   680-681); structures laid out in sequence (NET System.Runtime.InteropServices/LayoutKind.xml 198) or by
#   FieldOffset with a Size (LayoutKind.xml 137, StructLayoutAttribute.xml 327); the strings as ByValTStr of
#   SizeConst characters (UnmanagedType.xml 380, MarshalAsAttribute.xml 532); Marshal.SizeOf and
#   GetLastWin32Error (Marshal.xml 7714, 3748) with DllImport's SetLastError and EntryPoint
#   (DllImportAttribute.xml 480, 301). The path and mode structures hold blittable fields alone, and their
#   arrays are passed [In, Out] (DOCS blittable-and-non-blittable-types.md 34, 38).

# The two hardware ids the Looking Glass display driver's INF declares (LG idd/LGIdd/LGIdd.inf 20-21).
$glassIds = @('Root\LGIdd', 'LGIdd')
$qdcAllPaths = [uint32]0x00000001
$pathActive = [uint32]0x00000001
$sdcFlags = [uint32](0x00000080 -bor 0x00000020 -bor 0x00000200 -bor 0x00000400)
$insufficientBuffer = 122
$codeNames = @{ 0 = 'ERROR_SUCCESS'; 5 = 'ERROR_ACCESS_DENIED'; 31 = 'ERROR_GEN_FAILURE'; 50 = 'ERROR_NOT_SUPPORTED';
  87 = 'ERROR_INVALID_PARAMETER'; 122 = 'ERROR_INSUFFICIENT_BUFFER'; 1610 = 'ERROR_BAD_CONFIGURATION' }

# A Windows code in decimal and hexadecimal, with its name when it is one the display calls return.
function Code([int]$c) {
  $t = [string]$c + ' (0x' + ('{0:X8}' -f $c) + ')'
  if ($codeNames.ContainsKey($c)) { $t = $t + ': ' + $codeNames[$c] }
  return $t
}
function EndAs([string]$state) { if ($global:BastionModuleState -ne 'failed') { $global:BastionModuleState = $state } }

if (-not ('Bastion.Display' -as [type])) {
  try {
    Add-Type -Namespace Bastion -Name Display -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct LUID { public uint LowPart; public int HighPart; }
[StructLayout(LayoutKind.Sequential)]
public struct RATIONAL { public uint Numerator; public uint Denominator; }
// modeInfoIdx is the union's UINT32 form: QDC_VIRTUAL_MODE_AWARE is not passed.
[StructLayout(LayoutKind.Sequential)]
public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
[StructLayout(LayoutKind.Sequential)]
public struct PATH_TARGET_INFO {
  public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology;
  public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering;
  public int targetAvailable; public uint statusFlags;
}
[StructLayout(LayoutKind.Sequential)]
public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }
// DISPLAYCONFIG_MODE_INFO: infoType, id and adapterId, then at 16 the union of the target mode (48 bytes,
// its UINT64 aligning it at 8), the source mode (20) and the desktop image (40). The six ulong fields hold
// every byte of the union as Windows wrote it; the source mode's fields lie over its first 20 bytes.
[StructLayout(LayoutKind.Explicit, Size = 64)]
public struct MODE_INFO {
  [FieldOffset(0)] public uint infoType;
  [FieldOffset(4)] public uint id;
  [FieldOffset(8)] public LUID adapterId;
  [FieldOffset(16)] public ulong union16;
  [FieldOffset(24)] public ulong union24;
  [FieldOffset(32)] public ulong union32;
  [FieldOffset(40)] public ulong union40;
  [FieldOffset(48)] public ulong union48;
  [FieldOffset(56)] public ulong union56;
  [FieldOffset(16)] public uint sourceWidth;
  [FieldOffset(20)] public uint sourceHeight;
  [FieldOffset(24)] public uint sourcePixelFormat;
  [FieldOffset(28)] public int sourceX;
  [FieldOffset(32)] public int sourceY;
}
[StructLayout(LayoutKind.Sequential)]
public struct DEVICE_INFO_HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct ADAPTER_NAME {
  public DEVICE_INFO_HEADER header;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string adapterDevicePath;
}
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct TARGET_DEVICE_NAME {
  public DEVICE_INFO_HEADER header; public uint flags; public uint outputTechnology;
  public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
}
[StructLayout(LayoutKind.Sequential)]
public struct SP_DEVICE_INTERFACE_DATA { public uint cbSize; public Guid InterfaceClassGuid; public uint Flags; public IntPtr Reserved; }
[StructLayout(LayoutKind.Sequential)]
public struct SP_DEVINFO_DATA { public uint cbSize; public Guid ClassGuid; public uint DevInst; public IntPtr Reserved; }

[DllImport("user32.dll")]
public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);
[DllImport("user32.dll")]
public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [In, Out] PATH_INFO[] pathArray,
  ref uint numModeInfoArrayElements, [In, Out] MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);
[DllImport("user32.dll")]
public static extern int SetDisplayConfig(uint numPathArrayElements, [In] PATH_INFO[] pathArray,
  uint numModeInfoArrayElements, [In] MODE_INFO[] modeInfoArray, uint flags);
[DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
static extern int GetAdapterName(ref ADAPTER_NAME requestPacket);
[DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
static extern int GetTargetName(ref TARGET_DEVICE_NAME requestPacket);
[DllImport("setupapi.dll", SetLastError = true)]
static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr ClassGuid, IntPtr hwndParent);
[DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "SetupDiOpenDeviceInterfaceW")]
static extern bool SetupDiOpenDeviceInterface(IntPtr DeviceInfoSet, string DevicePath, uint OpenFlags,
  ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
[DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "SetupDiGetDeviceInterfaceDetailW")]
static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData,
  IntPtr DeviceInterfaceDetailData, uint DeviceInterfaceDetailDataSize, IntPtr RequiredSize, ref SP_DEVINFO_DATA DeviceInfoData);
[DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "SetupDiGetDeviceInstanceIdW")]
static extern bool SetupDiGetDeviceInstanceId(IntPtr DeviceInfoSet, ref SP_DEVINFO_DATA DeviceInfoData,
  System.Text.StringBuilder DeviceInstanceId, uint DeviceInstanceIdSize, out uint RequiredSize);
[DllImport("setupapi.dll", SetLastError = true)]
static extern bool SetupDiDeleteDeviceInterfaceData(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
[DllImport("setupapi.dll", SetLastError = true)]
static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

// The adapter's device path: DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME (4), the adapter's identifier, the
// packet's size. Returns DisplayConfigGetDeviceInfo's result.
public static int AdapterName(LUID adapterId, out string adapterDevicePath) {
  ADAPTER_NAME r = new ADAPTER_NAME();
  r.header.type = 4;
  r.header.size = (uint)Marshal.SizeOf(typeof(ADAPTER_NAME));
  r.header.adapterId = adapterId;
  int code = GetAdapterName(ref r);
  adapterDevicePath = r.adapterDevicePath;
  return code;
}
// The target's names: DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME (2), the adapter's identifier and the
// target's, the packet's size. Returns DisplayConfigGetDeviceInfo's result.
public static int TargetName(LUID adapterId, uint id, out string friendlyName, out string devicePath) {
  TARGET_DEVICE_NAME r = new TARGET_DEVICE_NAME();
  r.header.type = 2;
  r.header.size = (uint)Marshal.SizeOf(typeof(TARGET_DEVICE_NAME));
  r.header.adapterId = adapterId;
  r.header.id = id;
  int code = GetTargetName(ref r);
  friendlyName = r.monitorFriendlyDeviceName;
  devicePath = r.monitorDevicePath;
  return code;
}
// The device instance id of the device behind a device interface path, or null with the Windows code in
// error. GetDeviceInterfaceDetail with no detail buffer fills SP_DEVINFO_DATA and fails with 122,
// ERROR_INSUFFICIENT_BUFFER; GetDeviceInstanceId tells the length first, then fills the buffer.
public static string InstanceId(string devicePath, out int error) {
  error = 0;
  IntPtr set = SetupDiCreateDeviceInfoList(IntPtr.Zero, IntPtr.Zero);
  if (set == IntPtr.Zero || set == new IntPtr(-1)) { error = Marshal.GetLastWin32Error(); return null; }
  try {
    SP_DEVICE_INTERFACE_DATA iface = new SP_DEVICE_INTERFACE_DATA();
    iface.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
    if (!SetupDiOpenDeviceInterface(set, devicePath, 0, ref iface)) { error = Marshal.GetLastWin32Error(); return null; }
    try {
      SP_DEVINFO_DATA device = new SP_DEVINFO_DATA();
      device.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVINFO_DATA));
      if (!SetupDiGetDeviceInterfaceDetail(set, ref iface, IntPtr.Zero, 0, IntPtr.Zero, ref device)) {
        int code = Marshal.GetLastWin32Error();
        if (code != 122) { error = code; return null; }
      }
      uint need = 0;
      SetupDiGetDeviceInstanceId(set, ref device, null, 0, out need);
      System.Text.StringBuilder id = new System.Text.StringBuilder((int)need + 1);
      if (!SetupDiGetDeviceInstanceId(set, ref device, id, (uint)id.Capacity, out need)) { error = Marshal.GetLastWin32Error(); return null; }
      return id.ToString();
    } finally { SetupDiDeleteDeviceInterfaceData(set, ref iface); }
  } finally { SetupDiDestroyDeviceInfoList(set); }
}
'@
  } catch {
    Note ('[display] FAILED to build the display helper (Add-Type): ' + $_.Exception.Message)
    Note '[display] done'
    return
  }
}

# 1. The Looking Glass display device: every Plug and Play device whose hardware ids hold one of the two.
function IsGlass($device) {
  foreach ($h in @($device.HardwareID)) { foreach ($g in $glassIds) { if ([string]$h -ieq $g) { return $true } } }
  return $false
}
try { $glass = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { IsGlass $_ }) }
catch {
  Note ('[display] FAILED to read the Plug and Play devices (Win32_PnPEntity): ' + $_.Exception.Message)
  Note '[display] done'
  return
}
if ($glass.Count -eq 0) {
  if (RestartPending) {
    Note '[display] the Looking Glass display device is not there yet - waits for restart'
    EndAs 'waits for restart'
  } else {
    Note '[display] the Looking Glass display device is not there (Looking Glass not installed) - skipped'
    EndAs 'skipped'
  }
  Note '[display] done'
  return
}
foreach ($d in $glass) { Note ('[display] the Looking Glass display device ' + $d.PNPDeviceID + ': status ' + $d.Status + ', code ' + $d.ConfigManagerErrorCode) }

# 2. Windows' display paths, all of them, and the device of each path's adapter.
do {
  $np = [uint32]0
  $nm = [uint32]0
  $call = 'GetDisplayConfigBufferSizes'
  $code = [Bastion.Display]::GetDisplayConfigBufferSizes($qdcAllPaths, [ref]$np, [ref]$nm)
  if ($code -ne 0) { break }
  $paths = New-Object 'Bastion.Display+PATH_INFO[]' $np
  $modes = New-Object 'Bastion.Display+MODE_INFO[]' $nm
  $call = 'QueryDisplayConfig'
  $code = [Bastion.Display]::QueryDisplayConfig($qdcAllPaths, [ref]$np, $paths, [ref]$nm, $modes, [IntPtr]::Zero)
} while ($code -eq $insufficientBuffer)
if ($code -ne 0) {
  Note ('[display] FAILED, ' + $call + ': code ' + (Code $code))
  Note '[display] done'
  return
}
$pnp = @($glass | ForEach-Object { [string]$_.PNPDeviceID })
$devices = @{}
$active = @()
$glassPaths = @()
for ($i = 0; $i -lt $np; $i++) {
  $p = $paths[$i]
  $a = $p.targetInfo.adapterId
  $key = [string]$a.HighPart + ':' + [string]$a.LowPart
  if (-not $devices.ContainsKey($key)) {
    $devicePath = $null
    $code = [Bastion.Display]::AdapterName($a, [ref]$devicePath)
    if ($code -ne 0) {
      Note ('[display] FAILED, DisplayConfigGetDeviceInfo (the adapter name): code ' + (Code $code))
      Note '[display] done'
      return
    }
    $err = 0
    $instance = [Bastion.Display]::InstanceId($devicePath, [ref]$err)
    if ($null -eq $instance) {
      Note ('[display] FAILED to find the device of the adapter ' + $devicePath + ' (SetupAPI): code ' + (Code $err))
      Note '[display] done'
      return
    }
    Note ('[display] the adapter ' + $devicePath + ' is the device ' + $instance)
    $devices[$key] = $instance
  }
  if (($p.flags -band $pathActive) -ne 0) { $active += $i }
  $mine = $false
  foreach ($id in $pnp) { if ($devices[$key] -ieq $id) { $mine = $true } }
  if ($mine -and $p.targetInfo.targetAvailable -ne 0) { $glassPaths += $i }
}
$chosen = -1
foreach ($i in $glassPaths) { if ($chosen -lt 0 -and $active -contains $i) { $chosen = $i } }
if ($chosen -lt 0 -and $glassPaths.Count -gt 0) { $chosen = $glassPaths[0] }
if ($chosen -lt 0) {
  $state = 'device status ' + $glass[0].Status + ', code ' + $glass[0].ConfigManagerErrorCode
  if (RestartPending) {
    Note ('[display] the Looking Glass display is not present (' + $state + '; its driver starts after the restart) - waits for restart')
    EndAs 'waits for restart'
  } else {
    Note ('[display] the Looking Glass display is not present (' + $state + ') - skipped; after Looking Glass is repaired: run.cmd display')
    EndAs 'skipped'
  }
  Note '[display] done'
  return
}

# 3. The Looking Glass path alone active, saved to Windows' display database.
if ($active.Count -eq 1 -and $active[0] -eq $chosen) {
  Note '[display] the Looking Glass display is already the only active display - nothing changed'
  Note '[display] done'
  return
}
# A target's name as Windows gives it: the monitor's friendly name, or its device path when Windows has none.
function TargetName($path) {
  $friendly = $null
  $device = $null
  $code = [Bastion.Display]::TargetName($path.targetInfo.adapterId, $path.targetInfo.id, [ref]$friendly, [ref]$device)
  if ($code -ne 0) { return ('target ' + $path.targetInfo.id + ' (its name not read: code ' + (Code $code) + ')') }
  if ($friendly) { return $friendly }
  return $device
}
Note '[display] making the Looking Glass display the only active display, saved to Windows'' display database'
$off = @()
foreach ($i in $active) {
  if ($i -ne $chosen) {
    $p = $paths[$i]
    $off += (TargetName $p)
    $p.flags = [uint32]($p.flags - ($p.flags -band $pathActive))
    $paths[$i] = $p
  }
}
$p = $paths[$chosen]
$wasActive = ($p.flags -band $pathActive) -ne 0
$p.flags = [uint32]($p.flags -bor $pathActive)
$paths[$chosen] = $p
if ($wasActive) {
  # The Looking Glass source moves to 0,0: "The source surface that is located at (0, 0) is always the primary
  # source surface", and "there cannot be any gaps between source surfaces" (SDK
  # wingdi/ns-wingdi-displayconfig_source_mode.md 71, 75); its mode is the one its modeInfoIdx names, valid
  # for an active path (ns-wingdi-displayconfig_path_source_info.md 69; nf-winuser-querydisplayconfig.md 266).
  # An inactive Looking Glass path keeps the invalid indexes QueryDisplayConfig gave it, and SetDisplayConfig
  # "uses best mode logic to generate any missing source and target mode information" (setdisplayconfig.md 381).
  $k = $p.sourceInfo.modeInfoIdx
  $m = $modes[$k]
  $m.sourceX = 0
  $m.sourceY = 0
  $modes[$k] = $m
}
$code = [Bastion.Display]::SetDisplayConfig($np, $paths, $nm, $modes, $sdcFlags)
if ($code -eq 0) {
  foreach ($n in $off) { Note ('[display] made inactive: ' + $n) }
  Note '[display] SetDisplayConfig: done'
} else {
  Note ('[display] SetDisplayConfig FAILED, code ' + (Code $code))
}
Note '[display] done'
