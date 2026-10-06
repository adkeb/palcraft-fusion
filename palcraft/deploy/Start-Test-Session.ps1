# Run deliberately for acceptance. No login trigger and no production mutation.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$d='D:\PalworldServer-LAN\PalCraft-Dev'
if(Get-CimInstance Win32_Process -Filter "name='Palworld-Win64-Shipping.exe'"|Where-Object {$_.ExecutablePath -like 'D:\steam\steamapps\common\Palworld\*'}){throw 'Normal game is running; session not started'}
# A deliberately stopped production server is compatible with isolated testing.
if(Get-NetTCPConnection -LocalPort 8212 -State Listen -ErrorAction SilentlyContinue){
$ini=[IO.File]::ReadAllText('D:\steam\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini')
$pw=[regex]::Match($ini,'AdminPassword="([^"\r\n]+)"').Groups[1].Value
$h=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:'+$pw))}
$m=Invoke-RestMethod 'http://127.0.0.1:8212/v1/api/metrics' -Headers $h -TimeoutSec 3
if($m.currentplayernum -gt 0){throw 'Production players are online; graphical test deferred'}
}
if(!(Get-NetTCPConnection -LocalPort 8322 -State Listen -ErrorAction SilentlyContinue)){Start-ScheduledTask -TaskName 'Palworld-BridgeLab'}
for($i=0;$i -lt 45;$i++){if(Get-NetTCPConnection -LocalPort 8322 -State Listen -ErrorAction SilentlyContinue){break};Start-Sleep -Seconds 1}
& "$d\Invoke-Lab.ps1" -Method 'palcraft_start' -TimeoutSeconds 45|Out-Null
if(!(Get-NetTCPConnection -LocalPort 25567 -State Listen -ErrorAction SilentlyContinue)){Start-ScheduledTask -TaskName 'PalCraft-Minecraft-Shared'}
for($i=0;$i -lt 60;$i++){if(Get-NetTCPConnection -LocalPort 25567 -State Listen -ErrorAction SilentlyContinue){break};Start-Sleep -Seconds 1}
if(!(Get-NetTCPConnection -LocalPort 25567 -State Listen -ErrorAction SilentlyContinue)){throw 'Shared Minecraft world did not start; see mc-shared-runtime.log'}
if(!(Get-NetTCPConnection -LocalPort 25599 -State Listen -ErrorAction SilentlyContinue)){Start-ScheduledTask -TaskName 'PalCraft-Minecraft-Guest'}
for($i=0;$i -lt 90;$i++){if(Get-NetTCPConnection -LocalPort 25599 -State Listen -ErrorAction SilentlyContinue){break};Start-Sleep -Seconds 1}
if(!(Get-NetTCPConnection -LocalPort 25599 -State Listen -ErrorAction SilentlyContinue)){throw 'Minecraft did not start; see mc-runtime.log'}
Enable-ScheduledTask -TaskName 'PalCraft-Pal-Test-Client'|Out-Null
Start-ScheduledTask -TaskName 'PalCraft-Pal-Test-Client'
@{test_session_started=$true;target='127.0.0.1:8321'}|ConvertTo-Json -Compress
