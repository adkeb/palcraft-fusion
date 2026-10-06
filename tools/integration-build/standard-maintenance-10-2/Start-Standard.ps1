param(
    [Parameter(Mandatory=$true)][string]$LaunchManifest,
    [Parameter(Mandatory=$true)][string]$JavaHome,
    [Parameter(Mandatory=$true)][string]$MigrationReceipt
)
$ErrorActionPreference='Stop'
$launch=Get-Content -LiteralPath $LaunchManifest -Raw | ConvertFrom-Json
$receipt=Get-Content -LiteralPath $MigrationReceipt -Raw | ConvertFrom-Json
if($launch.schema -ne 1 -or $launch.development -ne $false){throw 'Expected prepared production launch'}
if($launch.configured_for_runtime_batch -ne $true){throw 'Replace the preparation template with the actual batch public configuration first'}
if($receipt.schema -ne 1 -or $receipt.clean_save_verified -ne $true -or $receipt.original_server_stopped -ne $true -or $receipt.world_migration_completed -ne $true){throw 'Post-clean-save world migration receipt required'}
$root=(Resolve-Path $launch.root).Path
if((Resolve-Path $receipt.destination_server_root).Path -ne (Join-Path $root 'server')){throw 'Migration target differs from standard server root'}
$java=Join-Path $JavaHome 'bin/java.exe'
$release=Get-Content (Join-Path $JavaHome 'release')
if(!($release -match '^JAVA_VERSION="25([.\"]|$)')){throw 'This candidate requires Java25'}
$serverProps=Join-Path $root 'server/server.properties'
if(!(Test-Path -LiteralPath $serverProps)){throw 'Migrated server configuration missing'}
$props=@{}
Get-Content $serverProps | ForEach-Object {if($_ -match '^([^#=]+)=(.*)$'){$props[$matches[1].Trim()]=$matches[2].Trim()}}
$world=$props['level-name'];if(!$world){throw 'Explicit existing level-name required'}
if(!(Test-Path -LiteralPath (Join-Path $root ('server/'+$world+'/level.dat')))){throw 'Existing world missing; refusing fresh world creation'}
if($launch.role -eq 'guest' -and $props['online-mode'] -ne 'false'){throw 'Registered local guest route requires existing offline local-server policy; use normal official account launcher for online servers'}
$port=if($launch.role -eq 'server'){[int]$props['server-port']}else{25599}
if(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue){throw 'Existing runtime still holds required port; no replacement or kill is performed'}
$mods=Join-Path $launch.cwd 'mods'
$expected='3b782bb7308ea9926bd57e330103f2fa07abd323b817a074117101387a65f831'
$mod=Join-Path $mods 'passthrough-0.2.0-integration.10.2-maintenance.jar'
if((Get-FileHash -LiteralPath $mod -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'Production mod hash differs'}
Push-Location $launch.cwd
try { & $java ('@'+$launch.args_file); exit $LASTEXITCODE } finally { Pop-Location }
