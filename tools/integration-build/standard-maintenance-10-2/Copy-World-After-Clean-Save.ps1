param(
    [Parameter(Mandatory=$true)][string]$SourceServerRoot,
    [Parameter(Mandatory=$true)][string]$StandardRoot,
    [Parameter(Mandatory=$true)][string]$CleanSaveReceipt
)
$ErrorActionPreference='Stop'
$receipt=Get-Content -LiteralPath $CleanSaveReceipt -Raw | ConvertFrom-Json
$source=(Resolve-Path $SourceServerRoot).Path
$standard=(Resolve-Path $StandardRoot).Path
if($receipt.schema -ne 1 -or $receipt.clean_save_verified -ne $true -or $receipt.original_server_stopped -ne $true){throw 'Runtime-owned clean save and stop receipt required'}
if((Resolve-Path $receipt.source_server_root).Path -ne $source){throw 'Receipt belongs to another source root'}
if(Get-NetTCPConnection -State Listen -LocalPort 25567 -ErrorAction SilentlyContinue){throw 'Existing server still listening; no stop/kill is performed'}
$properties=Get-Content (Join-Path $source 'server.properties')
$line=@($properties | Where-Object {$_ -match '^level-name='})
if($line.Count -ne 1){throw 'Explicit existing level-name required'}
$name=$line[0].Substring('level-name='.Length)
if(!$name -or [IO.Path]::IsPathRooted($name) -or $name -match '(^|[\/])\.\.([\/]|$)'){throw 'Unsafe level-name'}
$world=Join-Path $source $name
if(!(Test-Path -LiteralPath (Join-Path $world 'level.dat'))){throw 'Source existing world missing'}
$targetServer=Join-Path $standard 'server'
$targetWorld=Join-Path $targetServer $name
if(Test-Path -LiteralPath $targetWorld){throw 'Refuse to replace a destination world'}
$records=@(Get-ChildItem -LiteralPath $world -File -Recurse -Force | ForEach-Object {
    @{relative=$_.FullName.Substring($world.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
Copy-Item -LiteralPath $world -Destination $targetWorld -Recurse
foreach($entry in $records){
    if((Get-FileHash -LiteralPath (Join-Path $world $entry.relative) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'Source changed after clean-save receipt'}
    if((Get-FileHash -LiteralPath (Join-Path $targetWorld $entry.relative) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'Copied world mismatch'}
}
foreach($file in @('server.properties','eula.txt','ops.json','whitelist.json','banned-players.json','banned-ips.json')){
    $path=Join-Path $source $file
    if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination (Join-Path $targetServer $file)}
}
$migration=@{schema=1;source_server_root=$source;destination_server_root=$targetServer;level_name=$name;clean_save_verified=$true;original_server_stopped=$true;world_migration_completed=$true;all_world_files_sha256_matched=$true;world_files=$records;playerdata_26_3='players/data';game_started=$false;source_removed=$false}
$migration | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $standard 'world-migration-receipt.json') -Encoding UTF8
'Existing world copied with complete playerdata and exact file hashes; no game started'
