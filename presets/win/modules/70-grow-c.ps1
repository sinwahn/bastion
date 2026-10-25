. (Join-Path $PSScriptRoot '..\lib\common.ps1')
Note '[grow-c] extending C: to fill the disk'
try {
  $cp = Get-Partition -DriveLetter C -ErrorAction Stop
  $disk = $cp.DiskNumber
  $after = Get-Partition -DiskNumber $disk | Where-Object { $_.Offset -gt $cp.Offset } | Sort-Object Offset -Descending
  if ($after) {
    Note ('[grow-c] deleting the partitions after C: on disk ' + $disk + ': ' + (($after | ForEach-Object { $_.PartitionNumber }) -join ', '))
    $s = "select disk " + $disk + "`r`n"
    foreach ($p in $after) { $s += "select partition " + $p.PartitionNumber + "`r`ndelete partition override`r`n" }
    $tmp = Join-Path $env:TEMP 'bastion-del.txt'; Set-Content -LiteralPath $tmp -Value $s -Encoding ASCII
    [void](RunLogged 'diskpart.exe' @('/s', $tmp)); Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
  } else { Note '[grow-c] no partition after C:' }
  Update-Disk -Number $disk -ErrorAction SilentlyContinue
  $max = (Get-PartitionSupportedSize -DriveLetter C -ErrorAction Stop).SizeMax
  if ($max -gt (Get-Partition -DriveLetter C).Size) { Resize-Partition -DriveLetter C -Size $max -ErrorAction Stop; Note ("[grow-c] C: extended to " + [math]::Round((Get-Partition -DriveLetter C).Size/1GB,1) + " GB") }
  else { Note '[grow-c] C: already at maximum' }
} catch { Note ('[grow-c] FAILED, C: resize: ' + $_.Exception.Message) }
Note '[grow-c] done'
