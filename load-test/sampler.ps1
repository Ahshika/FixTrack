$out = Join-Path $PSScriptRoot 'server_res.csv'
"time,cpu_pct,mem_mb,db_mb" | Out-File $out -Encoding ascii
$cores = [Environment]::ProcessorCount
$prev = $null; $prevT = $null
while ($true) {
  $p = Get-Process load_server -ErrorAction SilentlyContinue
  if (-not $p) { break }
  $now = Get-Date
  $cpu = 0
  if ($prev -ne $null) { $cpu = [math]::Round((($p.TotalProcessorTime.TotalSeconds - $prev) / ($now - $prevT).TotalSeconds) * 100 / $cores, 1) }
  $prev = $p.TotalProcessorTime.TotalSeconds; $prevT = $now
  $db = 0; $f = Join-Path $PSScriptRoot 'loaddata\fixtrack.db'; if (Test-Path $f) { $db = [math]::Round((Get-Item $f).Length/1MB,1) }
  "{0},{1},{2},{3}" -f ([DateTimeOffset]$now).ToUnixTimeMilliseconds(), $cpu, [math]::Round($p.WorkingSet64/1MB,1), $db | Out-File $out -Append -Encoding ascii
  Start-Sleep -Seconds 2
}
