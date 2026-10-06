# Restarts only the isolated Minecraft world. Palworld stays online.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$d='D:\PalworldServer-LAN\PalCraft-Dev'
if(Get-NetTCPConnection -LocalPort 25567 -State Listen -ErrorAction SilentlyContinue){
 $request=@{id=[Guid]::NewGuid().ToString();method='stop'}|ConvertTo-Json -Compress
 [IO.File]::WriteAllText("$d\bridge\server-request.tmp",$request)
 Move-Item "$d\bridge\server-request.tmp" "$d\bridge\server-request.json" -Force
 for($i=0;$i -lt 60;$i++){if((Get-ScheduledTask -TaskName 'PalCraft-Minecraft-Shared').State -ne 'Running'){break};Start-Sleep -Milliseconds 500}
 if((Get-ScheduledTask -TaskName 'PalCraft-Minecraft-Shared').State -eq 'Running'){throw 'MC world is still saving; leave it running and inspect mc-shared-runtime.log'}
}
Start-ScheduledTask -TaskName 'PalCraft-Minecraft-Shared'
