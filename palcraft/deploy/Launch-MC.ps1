$ProgressPreference='SilentlyContinue'
$env:JAVA_HOME='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon'
$env:Path=$env:JAVA_HOME+'\bin;'+$env:Path
$env:GRADLE_USER_HOME='D:\PalworldServer-LAN\PalCraft-Dev\gradle-cache'
$env:JAVA_TOOL_OPTIONS='-Dpalcraft.hidden=true -Dpalcraft.server=127.0.0.1:25567'
Set-Location 'D:\PalworldServer-LAN\PalCraft-Dev\mc'
& D:\PalworldServer-LAN\PalCraft-Dev\gradle\gradle-9.7.1\bin\gradle.bat runClient --offline --no-daemon --console=plain *> 'D:\PalworldServer-LAN\PalCraft-Dev\mc-runtime.log'
@{exit_code=$LASTEXITCODE;finished_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress|Set-Content 'D:\PalworldServer-LAN\PalCraft-Dev\mc-runtime-status.json'