$ProgressPreference='SilentlyContinue'
$d='D:\PalworldServer-LAN\PalCraft-Dev'
# Session 0 is separate from the player's desktop. Never use an interactive task for this check.
if((Get-Process -Id $PID).SessionId -ne 0){throw 'Background check requires SSH session 0'}
(Get-Process -Id $PID).PriorityClass='BelowNormal'
$env:JAVA_HOME='C:\Users\PLAYER\AppData\Roaming\.minecraft\runtime\java-runtime-epsilon\windows-x64\java-runtime-epsilon'
$env:Path=$env:JAVA_HOME+'\bin;'+$env:Path
$env:GRADLE_USER_HOME="$d\gradle-cache"
$env:JAVA_TOOL_OPTIONS=''
Set-Location "$d\mc"
& "$d\gradle\gradle-9.7.1\bin\gradle.bat" runBackgroundCheck --offline --no-daemon --console=plain *> "$d\background-check.log"
@{exit_code=$LASTEXITCODE;finished_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress|Set-Content "$d\background-check-status.json"
