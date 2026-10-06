# Actual paid escrow setup for the runtime owner

9.2 continues with exchange pending until genuine enrollment exists. The correct root is `D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange`. A read-only 5090 check through the shared `work/ssh_ps.py` confirmed this directory exists, `escrow-config.json` is absent, there is no current lease, and known alternate bridge/RPC directories have no config. The small `bridge/v14-shared-chest.json` contains MC block coordinates/items and has no Pal model/container IDs, paid cost or enrollment save hash. It is not a Pal escrow registration. No credential file or production save was accessed.

The previously paid serial box `00000000-0000-4000-8000-00000000000c` / `00000000-0000-4000-8000-000000000016` was really built for 15 Wood +5 Stone, but is inside a base and nonempty. Do not register it as an isolated box. Runtime confirms no new paid box was built in the current deployment.

The old `build.lua` inside-base, foundation and initial 15m requirements are our original probe limits. The real public RPC has only build ID, position, quaternion, archives and debug parameter; it has no base/foundation argument. The actual recipe is still read and must permit outdoors/outside-hub. No old safety gate was silently removed from `build.lua`.

## Runtime-only executable entry

Copy the new local sources to the normal backend payload:

- `palcraft/server/escrow_setup.lua` → existing PalLiveBridge `Scripts/escrow_setup.lua`.
- `palcraft/mcp/escrow_enroll.py` → `D:/PalworldServer-LAN/PalCraft-Dev/mcp/escrow_enroll.py` with the existing `escrow_bootstrap.py`, `escrow_io.py`, `escrow_witness.py`, `exchange_recovery.py`, patched parser vendor and `pyooz==0.0.8`.
- Existing `exchange_store.lua`, `readers.lua`, `discovery.lua`, `json.lua` and `PalCraftExchangeDurable-v3.dll` must be present. Server startup `PALCRAFT_EXCHANGE_ROOT` must match the correct root above. No new server restart is required merely to load this explicit setup helper after those files/env are present.

Load/call on the existing authorized server GAME THREAD. Select the actual current Pal UID from the real presence/strict identity; never pick the first controller or use the historical UID as an assumption.

```lua
local dir='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange/'
_G.PalCraftEscrowSetup=dofile(dir..'escrow_setup.lua').new{
  json=dofile(dir..'json.lua'),readers=dofile(dir..'readers.lua'),root=root,
  durable_dll=dir..'PalCraftExchangeDurable-v3.dll',allow_build=true
}
-- Replace actualPalUid with the UID already verified by the runtime identity path.
local result=PalCraftEscrowSetup.preview(actualPalUid)
```

`preview` reads actual carried resources and unlocked recipe. If it returns `real_carried_material_shortage`, its `needed.Wood/Stone` are the actual differences, not invented stock. Use `PalCraftEscrowSetup.take_stock(actualPalUid)` to normal-Move only those differences from the actual current guild's nearest ordinary base chests into the real bag. It uses strict current source ownership, the player-owned item RPC, durable move intents and observed count changes; it creates no material and reports the actual remaining shortage/space/permission error. Gathering real material or another normal authorized inventory Move remains available if stock is absent.

The successful `preview` selects actual ground around the current character with `KismetSystemLibrary.LineTraceSingle` plus four surface samples and `BoxTraceSingle` clearance. It checks every actual base radius +1000cm, actual slope/ground, native recipe restrictions and source ownership. It does not require a foundation or impose the old inside-base rule. It reports `world_trace_adapter_error` with the actual read/call failure if reflection differs; repair that concrete adapter in the runtime window rather than inventing a point or disabling native validation. If no point is found within the sampled nearby area, normal AI movement can move the actual character and request a fresh preview. The game's public placement/distance rules stay authoritative.

Keep the same helper instance and returned `result.id`; its plan expires after 60 seconds:

```lua
local setupId=result.id
local submitted=PalCraftEscrowSetup.submit(setupId)
-- Only repeat observation, never the public Build call under another ID blindly.
local observed=PalCraftEscrowSetup.observe(setupId)
-- When a real paid construction site is identified, start normal player work:
local work=PalCraftEscrowSetup.start_work(setupId)
-- Observe every ~2 seconds through the existing game-thread dispatcher:
local progress=PalCraftEscrowSetup.observe(setupId)
```

`submit` persists one consuming intent, then calls the same real `PalNetworkPlayerComponent.RequestBuild_ToServer(FName('ItemChest'),location,rotation,{}, {bNotConsumeMaterials=false})` exactly once. It reads the real owner/materials again before the call and records immediate same-game-thread world resource deltas as well as carried deltas. It never grants materials, spawns an actor directly, invokes a cheat or writes inventory. A consumed native attempt is not auto-replayed even when its response is uncertain.

`start_work` resolves this actual model's registered native `BuildProcess:GetWorkProgress()` and uses the real player's `PalNetworkWorkProgressComponent.RequestStartPlayerWork_ToServer(requestUUID,workId)`. Normal engine/player/Pal work determines the speed. No progress/amount/state field is changed and no FinishWork is invoked. The helper records actual current/required work samples. Native work may reject distance, eligibility or a changed player: runtime should observe/fix the concrete result using normal movement/work; GUI is an optional route, not the required construction entry. Completed normal work and an empty outside-base box produce `ready_for_saved_enrollment`; anything else stays pending.

## Register the actual saved result

Only after `ready_for_saved_enrollment`, have the unique runtime save executor perform its existing normal Lab save and wait for the actual installed Level. Run this command on 5090, using the same real Level path already fixed by the runtime's current world and bootstrap; `setupId` is the real result from above:

```powershell
python D:/PalworldServer-LAN/PalCraft-Dev/mcp/escrow_enroll.py `
  --root D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange `
  --server-root D:/PalworldServer-LAN/BridgeLab `
  --level $ActualInstalledLevel `
  --setup-id $ActualSetupId `
  --durable-dll D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/PalCraftExchangeDurable-v3.dll `
  --credit-dll D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/palcraft_escrow_credit_v1.dll `
  --parser-vendor $ActualPatchedParserVendor `
  --lab-candidate
```

The explicitly authorized Lab pilot flag marks the unverified daily/native-credit policy; it never claims `runtime_verified=true`. The program verifies every setup revision has an exact durable copy, actual recipe/carried prerequisites, a real -15 Wood/-5 Stone delta, a new owned model, completed/empty/outside live observation, and the SAME actual saved model/concrete/module/container/capacity/guild/position/build UID in installed Level. It forces/rechecks source bytes, detects races, verifies every other saved box slot is empty and rejects replacing an existing enrollment or any active lease. It writes `escrow-enrollment-<setupId>.json` and the missing `escrow-config.json` with the actual saved SHA256/IDs. It does not write a save, grant a resource, mark daily fences verified or create a full/empty transaction witness.

After real config installation, runtime's existing paid-enrollment readiness check may admit its exchange worker when bootstrap is genuinely ready. Preserve actual reserved-ID/RPC fences before the first exchange. The ordinary one-MC-log → Wood1 experiment and daily open/transport/craft/RPC challenges remain the next real acceptance steps; configuration alone is not player-ready acceptance.

Only syntax checks were run for the new helper and registrar. Actual worldtrace, normal stock-Move, paid Build and work signatures/semantics remain for runtime's short exclusive functional window. This source agent performed no RPC, GUI action, item change, save request, restart, deployment or old test matrix.

CDO entry correction before first setup execution: the helper now separates valid UObject from live non-CDO instance. Only the default Guid/System/Pal static utility libraries use valid; every real player/model/container/work/component instance keeps Default__ rejection. Corrected escrow_setup.lua SHA256: `cc6b7d819a762f3aae30dfc3801c273a99bbc3637629078f7eb445b827837867`. Lua syntax and one narrow actual-module CDO regression passed; no old matrices or actual RPC/deployment were performed, and fee/work rules are unchanged.
