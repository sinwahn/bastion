. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[grow-c] extending C: to fill the disk'
try {
  $cp = Get-Partition -DriveLetter C
  $disk = $cp.DiskNumber
  $after = Get-Partition -DiskNumber $disk | Where-Object { $_.Offset -gt $cp.Offset } | Sort-Object Offset -Descending
  if ($after) {
    $s = "select disk " + $disk + "`r`n"
    foreach ($p in $after) { $s += "select partition " + $p.PartitionNumber + "`r`ndelete partition override`r`n" }
    $tmp = Join-Path $env:TEMP 'bastion-del.txt'; Set-Content -LiteralPath $tmp -Value $s -Encoding ASCII
    diskpart /s $tmp | Out-Null; Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  }
  Update-Disk -Number $disk -ErrorAction SilentlyContinue
  $max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
  if ($max -gt (Get-Partition -DriveLetter C).Size) { Resize-Partition -DriveLetter C -Size $max; Note ("C: extended to " + [math]::Round((Get-Partition -DriveLetter C).Size/1GB,1) + " GB") }
  else { Note 'C: already at maximum' }
} catch { Note ('C: resize note: ' + $_.Exception.Message) }
Note '[grow-c] done'
