BridgeLab passive manual build observer — deployment by root only

Copy manual-build-observer.lua and manual-build-observer-core.lua into:
D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/
The same directory must contain the already reviewed json.lua/readers.lua/targets.lua.

Place the fresh verified real-client report at BridgeLab/rpc/client-context.json.
Create BridgeLab/rpc/manual-build-observer-arm.json with a fresh UUID observation_id,
target_player_uid and expires_unix (current UNIX seconds + 900 or less).
Example schema only; generate fresh values rather than reuse this example:
{"observation_id":"<fresh UUID>","target_player_uid":"22222222-0000-0000-0000-000000000000","expires_unix":0}

Use one top-level dofile of manual-build-observer.lua in the controlled Lab main.
Wait until rpc/manual-build-observation-<UUID>.json reports status=armed.
Then the selected player manually places exactly one ordinary wooden ItemChest.
Avoid other crafting or moving materials during this observation; wait 5 seconds.
The observer never initiates a request or changes any callback argument/result.
It copies location, rotation, every bounded PalNetArchive.Bytes array as hex and
bNotConsumeMaterials; it takes before and 3-second-after material subset snapshots.

A normal success does NOT necessarily emit ReceiveBuildResult_ToRequestClient.
Absence of a result event is not failure. The optional result hook only supplements
evidence. Root must independently compare safely registered new ItemChest models,
BuildProcess/work, materials, client appearance and eventual persistence. No global
model scan or transform access occurs in this observer.

Existing observation output prevents rearming that UUID after hot reload.
To stop: create rpc/manual-build-observer-stop-<UUID> (any content), or remove the
dofile and reload the Lab mod. Logical stop is immediate; native UnregisterHook is
scheduled for a subsequent native post-hook or mod unload in this UE4SS version.
Never deploy to production, enable build.apply, or treat this capture as approval to
replay archives before the independent normal-construction review.
