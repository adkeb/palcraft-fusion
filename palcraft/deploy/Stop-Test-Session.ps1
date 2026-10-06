$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$d='D:\PalworldServer-LAN\PalCraft-Dev'
# Only the isolated client path, never the normal Steam client or production server.
Get-CimInstance Win32_Process -Filter "name='Palworld-Win64-Shipping.exe'"|Where-Object {$_.ExecutablePath -like 'D:\PalworldServer-LAN\PalCraft-Client\*'}|ForEach-Object {Stop-Process -Id $_.ProcessId -Force}
if(Get-NetTCPConnection -LocalPort 25599 -State Listen -ErrorAction SilentlyContinue){
 . "$d\WebSocket-Local.ps1"
 try{Open-MC;Send-MC @{t='shutdown'}}finally{Close-MC}
}
Disable-ScheduledTask -TaskName 'PalCraft-Pal-Test-Client'|Out-Null
& "$d\Invoke-Lab.ps1" -Method 'palcraft_stop'|Out-Null
@{test_graphics_stop_requested=$true;servers_left_running=$true}|ConvertTo-Json -Compress
