$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$ue='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss'
$dump=$ue+'/UE4SS_ObjectDump.txt'
Select-String -LiteralPath $dump -Pattern 'PalSaveGameManager:GetLoadedWorldSaveData','PalSaveGameManager:IsLoadedWorldData','PalSaveGameManager:LoadedWorldSaveData','PalSaveGameManager:bIsLoadedWorldSaveData','PalWorldSaveGame:','PalGameSystemInitSequence_ApplyWorldSaveData','PalGameSystemInitSequence_ReadyWorldSaveData','\[n: CAB9\]' | ForEach-Object {$_.Line}
Get-FileHash -LiteralPath ($ue+'/UE4SS.dll'),($ue+'/Mods/PalLiveBridge/Scripts/exchange_bootstrap.lua') -Algorithm SHA256 | Select-Object Path,Hash | ConvertTo-Json -Compress
$status='D:/PalworldServer-LAN/BridgeLab/rpc/palcraft-features-status.json'
if(Test-Path -LiteralPath $status){
 $s=[IO.File]::ReadAllText($status)|ConvertFrom-Json
 $s.features | Where-Object {$_.name -eq 'exchange_bootstrap'} | ConvertTo-Json -Depth 8 -Compress
}
[ordered]@{read_only=$true;observed_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
