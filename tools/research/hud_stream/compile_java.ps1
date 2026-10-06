$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$taskRoot='D:/PalworldServer-LAN/PalCraft-Dev/workstreams/hud_stream'
$mcRoot='D:/PalworldServer-LAN/PalCraft-Dev/mc'
$jdkRoot='C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon'
Expand-Archive -LiteralPath "$taskRoot/source.zip" -DestinationPath "$taskRoot/source" -Force
$runArgs=[IO.File]::ReadAllText("$mcRoot/build/loom-cache/argFiles/runClient")
$matched=[regex]::Match($runArgs,'(?s)(?:-classpath|-cp)\s+(?:"([^"]+)"|(\S+))')
if(!$matched.Success){throw 'No resolved runtime classpath'}
$classpath=$matched.Groups[1].Value
if(!$classpath){$classpath=$matched.Groups[2].Value}
$classes="$taskRoot/classes"
New-Item -ItemType Directory -Force $classes|Out-Null
$sources=@(Get-ChildItem "$taskRoot/source/mc/src/client/java" -Recurse -Filter '*.java' | Select-Object -ExpandProperty FullName)
$argLines=@('--release','25','-proc:none','-classpath',('"'+($classpath -replace '\\','/')+'"'),'-d',('"'+$classes+'"'))
$argLines+=@($sources|ForEach-Object{'"'+($_ -replace '\\','/')+'"'})
[IO.File]::WriteAllLines("$taskRoot/javac.args",$argLines,[Text.UTF8Encoding]::new($false))
& "$jdkRoot/bin/javac.exe" "@$taskRoot/javac.args"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
@{status='passed';compiler='JDK25.0.1';source_files=$sources.Count;classes=@(Get-ChildItem $classes -Recurse -Filter '*.class').Count;classpath='read-only currently-resolved guest classpath';output=$classes}|ConvertTo-Json -Compress
