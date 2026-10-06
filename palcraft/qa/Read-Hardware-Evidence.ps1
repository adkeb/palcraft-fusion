# Read-only. Preserve the user's CPU30% / boost-off / GPU400W caps.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$out=[ordered]@{observed_utc=[DateTime]::UtcNow.ToString('o');scope='read_only_hardware_queries';requested_cpu_max_percent=30;requested_turbo_enabled=$false;requested_gpu_limit_w=400}
if(Get-Command powercfg.exe -ErrorAction SilentlyContinue) {
 $out.cpu_max=(& powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Out-String).Trim()
 $out.turbo=(& powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE | Out-String).Trim()
}
if(Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
 $out.gpu=(& nvidia-smi.exe --query-gpu=name,power.limit,pstate --format=csv,noheader | Out-String).Trim()
}
$out|ConvertTo-Json -Depth 5 -Compress
