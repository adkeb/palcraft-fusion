param(
    [Parameter(Mandatory=$true)][string]$ArgsFile,
    [Parameter(Mandatory=$true)][string]$OutputFile
)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($ArgsFile) -eq [IO.Path]::GetFullPath($OutputFile)){throw 'Write a separate reviewed args file, never the active source'}
if(Test-Path -LiteralPath $OutputFile){throw 'Output already exists'}
# Our standard Java args format is one JSON-compatible quoted UTF8 argument per line.
$guestLaunchArgs=@(Get-Content -LiteralPath $ArgsFile | ForEach-Object {
    if(![String]::IsNullOrWhiteSpace($_)){ $_ | ConvertFrom-Json }
})
$main='net.fabricmc.loader.impl.launch.knot.KnotClient'
$index=[Array]::IndexOf($guestLaunchArgs,$main)
if($index -le 0){throw 'Expected ordinary production KnotClient arguments with JVM prefix'}
if($guestLaunchArgs -match 'fabric\.dli|devlaunchinjector'){throw 'Not the current ordinary guest route'}
$prefix=@($guestLaunchArgs[0..($index-1)] | Where-Object {$_ -notmatch '^-Dpalcraft\.(maxFps|renderDistance|simulationDistance)='})
$prefix+=@('-Dpalcraft.maxFps=60','-Dpalcraft.renderDistance=8','-Dpalcraft.simulationDistance=12')
$tail=@($guestLaunchArgs[$index..($guestLaunchArgs.Count-1)])
$next=@($prefix+$tail)
$quote={param([string]$x) '"'+$x.Replace('\','\\').Replace('"','\"').Replace("`n",'\n').Replace("`r",'\r')+'"'}
[IO.File]::WriteAllText($OutputFile,(($next | ForEach-Object {& $quote $_}) -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
@{schema=1;output=$OutputFile;requested_MC=@{maxFps=60;renderDistance=8;simulationDistance=12;master=0;music=0};settings_entry='existing PassthroughClient configure() on same guest normal startup';only_three_JVM_properties_changed=$true;KnotClient_program_args_preserved=$true;no_RPC_or_process_operation=$true;actual_effect_verified=$false} | ConvertTo-Json -Depth 5
