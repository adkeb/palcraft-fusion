$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$normal='D:\steam\steamapps\common\Palworld'
if(Get-CimInstance Win32_Process -Filter "name='Palworld-Win64-Shipping.exe'"|Where-Object {$_.ExecutablePath -like "$normal\*"}){throw 'Normal Palworld client is running; test client not launched'}
# A deliberately stopped production server is compatible with isolated testing.
if(Get-NetTCPConnection -LocalPort 8212 -State Listen -ErrorAction SilentlyContinue){
$ini=[IO.File]::ReadAllText('D:\steam\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini')
$pw=[regex]::Match($ini,'AdminPassword="([^"\r\n]+)"').Groups[1].Value
$h=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:'+$pw))}
$m=Invoke-RestMethod 'http://127.0.0.1:8212/v1/api/metrics' -Headers $h -TimeoutSec 3
if($m.currentplayernum -gt 0){throw 'Production players are online; graphical test deferred'}
}
$d='D:\PalworldServer-LAN\PalCraft-Dev';$root='D:\PalworldServer-LAN\PalCraft-Client';$user='D:\PalworldServer-LAN\PalCraft-Client-User'
$identity=& "$d\Invoke-Lab.ps1" -Method 'palcraft_identity'
[IO.File]::WriteAllText("$d\bridge\lab-identity.json",($identity|ConvertTo-Json -Compress))
[IO.File]::Copy("$d\client-auto-join-lab.lua","$d\bridge\client-op.lua",$true)
New-Item -ItemType Directory -Force "$user\Saved\SaveGames"|Out-Null
$option="$env:LOCALAPPDATA\Pal\Saved\SaveGames\UserOption.sav"
if((Test-Path $option)-and !(Test-Path "$user\Saved\SaveGames\UserOption.sav")){Copy-Item $option "$user\Saved\SaveGames\UserOption.sav"}
# Native actors retain engine pointers; apply client updates with a clean restart.
$ueSettings="$root\Pal\Binaries\Win64\ue4ss\UE4SS-settings.ini"
if(Test-Path $ueSettings){$ueText=[IO.File]::ReadAllText($ueSettings);$ueText=[regex]::Replace($ueText,'EnableAutoReloadingLuaMods\s*=\s*1','EnableAutoReloadingLuaMods = 0');[IO.File]::WriteAllText($ueSettings,$ueText)}
$env:SteamAppId='1623730'
Set-Location $root
$p=Start-Process "$root\Palworld.exe" -ArgumentList @('-windowed','-ResX=1280','-ResY=720','-nosound','-NoVSync',"-UserDir=$user/",'-ExecCmds="t.MaxFPS 30"') -PassThru
@{pid=$p.Id;test_root=$root;user_dir=$user;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress|Set-Content "$d\test-client-launch.json"
