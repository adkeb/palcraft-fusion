# Actual PalLab normal-startup receipt entrypoint

This is executable source for coherent9. It does not stop/restart the current server. The runtime owner inserts the calls around the existing normal `Palworld-BridgeLab` ScheduledTask. Production stays off. No new account or client is involved.

## Package dependencies

Copy into the existing server scripts:

- `palcraft/server/exchange_bootstrap.lua`
- `escrow-storage/PalCraftEscrowBoot-v1.dll` (18,944 bytes; SHA256 `8432074e272d77385b40271bb3c8524bf4185ef8015b8bfc1440a2f0cf871858`; sole export `palcraft_escrow_process_identity_v1`)

Copy into the existing backend MCP directory:

- `palcraft/mcp/escrow_bootstrap.py`
- existing `escrow_io.py`, `escrow_witness.py`, `escrow_rehydrate.py`, `exchange_recovery.py` and its actual save parser vendor / pyooz runtime

No second scheduler/coordinator is created. This boot evidence is an external receipt for the existing exchange runner.

## Normal startup calls

Use the existing backend Python with the patched parser. Set these actual normal profile values:

```powershell
$Python = '<existing backend Python with palworld_save_tools/pyooz>'
$McpDir = 'D:/PalworldServer-LAN/PalCraft-Dev/mcp'
$ExchangeRoot = 'D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange'
$LabRoot = 'D:/PalworldServer-LAN/BridgeLab'
$LevelPath = "$LabRoot/Pal/Saved/SaveGames/0/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/Level.sav"
$Vendor = '<existing patched palworld_save_tools vendor directory>'
```

After the runtime's existing normal REST `/save` then `/shutdown wait2`, and only once the actual Lab process has exited:

```powershell
& $Python "$McpDir/escrow_bootstrap.py" prepare --root $ExchangeRoot --server-root $LabRoot --level $LevelPath --parser-vendor $Vendor
if ($LASTEXITCODE) { throw 'Stopped checkpoint capture failed; do not start exchange.' }

# This is the EXISTING Task, with its existing exe/arguments/working directory.
Start-ScheduledTask -TaskName 'Palworld-BridgeLab'

# The runtime waits for and records the real UDP8321 owning PID. It must not
# invent/reuse a PID from a previous run.
$PalProcessId = (Get-NetUDPEndpoint -LocalPort 8321 | Select-Object -First 1).OwningProcess
& $Python "$McpDir/escrow_bootstrap.py" complete --root $ExchangeRoot --server-root $LabRoot --level $LevelPath --pid $PalProcessId --rpc-root "$LabRoot/rpc" --timeout-seconds 60
if ($LASTEXITCODE) { throw 'Actual loader/process evidence failed; retain exchange fence and audit.' }
```

The tool itself never runs `Start-ScheduledTask`, launches/kills a process or sends a game RPC. `prepare` independently queries the exact BridgeLab exe before/after capture and refuses a still-running/restarting server. It reads and forces the real installed Level, checks races, parses actual data, and keeps an immutable same-byte checkpoint and prelaunch manifest under `exchange/bootstrap/<bootUUID>/`.

`complete` binds the singleton actual Pal PID using Win32 `QueryFullProcessImageNameW`, `GetProcessTimes` and exit status. Process creation must follow completed stopped capture. It then waits for the existing server startup observer and finalizes only matching evidence. A PID reuse, old process, wrong executable or mod-reload observation is rejected.

## Game-thread hook, independent of exchange flag

In the runtime-owned server startup/tick composition:

```lua
local boot = dofile(scriptDir..'exchange_bootstrap.lua').new{
  json=J, readers=R,
  root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange/',
  rpc_root='D:/PalworldServer-LAN/BridgeLab/rpc/',
  process_dll=scriptDir..'PalCraftEscrowBoot-v1.dll',
  restore_fence=function(prelaunch)
    -- Bind boot_id=prelaunch.boot_id, epoch=prelaunch.epoch to the existing
    -- exchange_v3 factory and restore its held RPC/AI exclusion fence only.
    -- Do not tick/dispatch item operations here.
  end
}

-- Every call is on the existing server game thread. Invoke before exchange
-- admission; ordinary features may continue at the configured low frame rate.
boot.tick()

-- Runtime's exchange_ready must require boot.ready() in addition to the
-- existing paid candidate/isolation/save-worker checks.
```

The observer makes REAL calls to `PalSaveGameManager.IsLoadedWorldData()` / `GetLoadedWorldSaveData()`, `PalUtility.IsAllLevelLoaded(gameState)`, and the actual game state's world directory/name/session. It reads loaded save Version/Revision/FDateTime components/exact saved game-time ticks and all saved item-container identities/capacities/nondynamic+dynamic slot identities/counts, plus actual manager slots for every in-flight transaction's escrow and source/recipient beforeimages. It refuses incomplete loading, a failed-world directory or a content mismatch. `bIsUseBackupSaveData` remains a diagnostic with its actual observed value: its meaning is unverified, so it is not an additional acceptance gate. A new random Lua instance ID cannot replace any of these data.

The process DLL reads only the current process ID, creation FILETIME and actual thread ID and writes a nonce-bound immutable process observation under BridgeLab `rpc/`. It performs no game function call, process-memory read, lifecycle or save/inventory action. Finalize compares this IN-PROCESS identity with external actual OS metadata and requires the complete loaded signature and transaction slots to match the true stopped checkpoint.

Full loaded signatures are normalized by real container ID and slot index. Empty sparse slots are normalized away; every occupied static/dynamic identity and count is compared. This is a one-time startup observation, not an ongoing inventory scan or performance workload. Errors remain visible in `boot.status()` / exception output and do not set readiness.

## Existing watcher verifier

The exchange owner wires the actual callback, using the existing runner:

```python
import escrow_bootstrap
verify_boot = escrow_bootstrap.verifier(exchange_root, pal_server_root, level_path)
runner = exchange_v3.Runner(exchange_root, level_path, vendor,
    save=existing_save_callback, rpc_root=installed_rpc_root,
    verify_boot=verify_boot)
```

It compares the immutable prelaunch/execution/loaded/certificate records and their SHA256, the actual process still alive with the same creation FILETIME and executable, actual loader/world/container data and the sealed boot checkpoint. It does not return a fixed true or trust mtime alone. A first boot with no in-flight transactions is supported; future native intents bind to this actual boot UUID.

`escrow_rehydrate.make_rearm_proof` now consumes the sealed checkpoint ONLY after that verifier succeeds. Its actual installed Level path remains fixed in the certificate, and the stored blob must match the exact loaded SHA and original checkpoint mtime preceding the old native attempt. Later normal autosaves may update the current Level without destroying actual boot evidence. The transaction's complete recorded beforeimages, changed actual boot, current lease revision and no accepted afterimage witness are still required. It cannot implement an arbitrary backup/admin rollback.

## Evidence and next actual call

The original five narrow Python cases covered stopped capture, process change/PID reuse, wrong-world/incomplete-load/beforeimage rejection and retained boot evidence across ordinary autosave; one decoded the actual historical Level's 1404 containers/header. Their original assumption that the backup flag must be false was not engine evidence. Two new focused regressions in `bootstrap-backup-guard-evidence.json` allow actual `uses_backup=true` with all required content and identity matching, preserve idempotent finalization, and reject header/container/transaction-slot mismatches. The previous matrix was not rerun. One earlier Lua exporter-shape test and DLL PE/import/export inspection remain offline evidence; this branch made no game invocation.

The actual runtime probe now shows `IsLoadedWorldData=true` while both the getter and `LoadedWorldSaveData` property are invalid; `uses_backup=true` and the failed directory is empty. There is no successful actual loaded observation or recovery receipt yet. The separate `escrow-startup-repair/` owner is preparing an early copy of real save data followed by world-readiness/current-manager checks. Its candidate is not replaced here. At the next already-needed normal load, runtime should validate that candidate and retain the existing evidence files. It can then run the already-handed-off normal paid enrollment and one-item exchange/recovery. No extra restart or new evidence layer is required by this handoff. See `FINAL-HANDOFF.md` for the shortest material and recovery flows and a persistent-manager alternative.
