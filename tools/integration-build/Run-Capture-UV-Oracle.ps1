param([Parameter(Mandatory=$true)][string]$Snapshot)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Diagnostics.Process]::GetCurrentProcess().PriorityClass=[Diagnostics.ProcessPriorityClass]::BelowNormal
$base='D:/PalworldServer-LAN/PalCraft-Dev/workstreams/integration/'+$Snapshot
$mc=$base+'/mc'
$out=$base+'/capture-uv-oracle.json'
if(Test-Path -LiteralPath $out){throw 'Oracle receipt already exists; refuse to rerun'}
$build=Get-Content ($base+'/build-result.json') -Raw | ConvertFrom-Json
if($build.exit_code -ne 0){throw 'Candidate compile must pass first'}
$metadata=Get-Content ($mc+'/build/palcraft-launch-metadata/runRegisteredGuest.json') -Raw | ConvertFrom-Json
$cp=@($metadata.classpath | ForEach-Object {
    $extended='\\?\'+$_.Replace('/','\')
    if(![IO.File]::Exists($extended) -and ![IO.Directory]::Exists($extended)){throw ('Actual classpath missing '+$_)}
    $_.Replace('\','/')
})
$source=$mc+'/src/oracle/java/CaptureUvOracle.java'
if((Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne '7c0abdb5ea3f7b0a7c6db1e0e51ed0e52e8a51037ce751bac58e4573bb2bf5c5'){throw 'Frozen oracle source mismatch'}
$quote={param([string]$x) '"'+$x.Replace('\','\\').Replace('"','\"')+'"'}
$arguments=@('-Xmx128M','-XX:ActiveProcessorCount=1','-Djava.awt.headless=true','--class-path',($cp -join ';'),$source)
$argFile=$base+'/capture-uv-oracle.args'
[IO.File]::WriteAllText($argFile,(($arguments | ForEach-Object {& $quote $_}) -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
$env:JAVA_TOOL_OPTIONS=''
$java='C:/Users/PLAYER/AppData/Roaming/.minecraft/runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon/bin/java.exe'
$ErrorActionPreference='Continue'
$text=@(& $java ('@'+$argFile) 2>&1 | ForEach-Object {$_.ToString()})
$rc=$LASTEXITCODE
$ErrorActionPreference='Stop'
$text | Set-Content ($base+'/capture-uv-oracle.log') -Encoding UTF8
$line=$text | Where-Object {$_ -match '^\{"status":"passed"'} | Select-Object -Last 1
$record=@{schema=1;snapshot=$Snapshot;exit_code=$rc;executions=1;oracle_source_sha256='7c0abdb5ea3f7b0a7c6db1e0e51ed0e52e8a51037ce751bac58e4573bb2bf5c5';data_only=$true;minecraft_main_invoked=$false;game_or_services_started=$false;runtime_graphics_verified=$false;actual_result=$(if($line){$line | ConvertFrom-Json}else{$null})}
$record | ConvertTo-Json -Depth 7 | Set-Content $out -Encoding UTF8
$record | ConvertTo-Json -Depth 7 -Compress
if($rc -ne 0 -or !$line){$text;exit 1}
