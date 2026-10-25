. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[copy-path] adding Copy full path context menu'
$vbs = @'
Set a = WScript.Arguments
If a.Count = 0 Then WScript.Quit
p = a(0)
If Right(p, 1) = """" Then p = Left(p, Len(p) - 1) & "\"
Set sh = CreateObject("WScript.Shell")
sh.Environment("Process")("BASTION_COPY_PATH") = p
sh.Run "powershell.exe -NoProfile -NonInteractive -Command Set-Clipboard -Value $env:BASTION_COPY_PATH", 0, True
'@
$vbsPath = Join-Path $BastionDir 'copy-path.vbs'
try { Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII -ErrorAction Stop; Note ('[copy-path] written ' + $vbsPath) }
catch { Note ('[copy-path] FAILED to write ' + $vbsPath + ': ' + $_.Exception.Message) }
$cmd = 'wscript.exe //B //Nologo "C:\ProgramData\Bastion\copy-path.vbs" '
Note '[copy-path] menu entries for files, folders, drives and folder backgrounds'
foreach ($pair in @(@('*','"%1"'), @('Directory','"%1"'), @('Drive','"%1"'), @('Directory\Background','"%V"'))) {
  $kk = 'SOFTWARE\Classes\' + $pair[0] + '\shell\BastionCopyPath'
  SetV $HKLM $kk '' 'Copy full path' 'String'
  SetV $HKLM ($kk + '\command') '' ($cmd + $pair[1]) 'String'
}
Note '[copy-path] done'
