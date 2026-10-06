# Read-only endpoint/process/status snapshot. No RPC, schedules, save reads or input.
# Example (from the shared workspace):
# python3 work/ssh_ps.py < work/minecraft-fusion/palcraft/qa/Read-Lab-Evidence.ps1
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$bridge='D:\PalworldServer-LAN\PalCraft-Dev\bridge'
$processes=@(Get-CimInstance Win32_Process | Where-Object {
 $_.Name -match '^(PalServer.*\.exe|Palworld-Win64-Shipping\.exe|java\.exe|python.*\.exe)$'
})
$udp=@(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @(8211,8321) })
$tcp=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @(8212,8322,25567,25599,25603) })
$servers=@($processes | Where-Object { $_.Name -like 'PalServer*' })
$lab=@($servers | Where-Object { $_.ExecutablePath -like 'D:\PalworldServer-LAN\BridgeLab\*' })
$production=@($servers | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -notlike 'D:\PalworldServer-LAN\BridgeLab\*' })
$out=[ordered]@{
 schema_version=1
 observed_utc=[DateTime]::UtcNow.ToString('o')
 scope='read_only_process_endpoints_and_allowlisted_lab_files'
 production_ports_checked=$true
 production_running=([bool]$production.Count -or [bool](@($udp | Where-Object {$_.LocalPort -eq 8211}).Count) -or [bool](@($tcp | Where-Object {$_.LocalPort -eq 8212}).Count))
 production_save_accessed=$false
 lab_running=[bool]$lab.Count
 processes=@($processes | Select-Object ProcessId,SessionId,Name,ExecutablePath)
 udp=@($udp | Select-Object LocalPort,OwningProcess)
 tcp=@($tcp | Select-Object LocalPort,OwningProcess)
 files=[ordered]@{}
}
foreach($name in @('client-status','render-status','feedback','palcraft-collision-status','world-origin','world-backend','world-compat-status','entity-combat-status')) {
 $path=Join-Path $bridge ($name+'.json')
 if(Test-Path -LiteralPath $path) {
  $f=Get-Item -LiteralPath $path
  try {
   $data=[IO.File]::ReadAllText($path) | ConvertFrom-Json
   $out.files[$name]=@{modified_utc=$f.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant();payload=$data}
  } catch { $out.files[$name]=@{modified_utc=$f.LastWriteTimeUtc.ToString('o');valid=$false;error='Writer in progress or invalid JSON'} }
 }
}
$out | ConvertTo-Json -Depth 20 -Compress
