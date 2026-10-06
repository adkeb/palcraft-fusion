# Escrow storage v3 candidate

Updated 2026-10-06 Asia/Shanghai. Sources, a Windows x64 candidate build, and lightweight offline verification only. No RPC was delivered, no box created or moved, no actual material changed, no service/client restarted, and production remains OFF. All final validation below ran under `night_low_power`; it is not a performance baseline.

## Implemented integration surface

`palcraft/server/exchange_escrow.lua` exports `game_backend(readers, creditOptions?)`, `rpc_guard(options)`, `daily_guard(options)`, `new(options)`, and `witness_matches(lease,witness)`.

`new(options)` returns `claim(transaction,binding)`, `read(lease)`, `moveIn(lease,sourceSlots,n)`, `ensureCredit(lease,actualMcDebitReceipt,n)`, `acceptWitness(lease,witness)`, `dispose(lease,actualMcCreditReceipt,n)`, `deliver(lease,realBagContainerId,n)`, `reconcile(lease,operation)`, `rearm(lease,proof)`, and `release(lease,terminalReceipt)`. `read` returns exact slot and latest lease. A mutating operation returns the latest lease; it does not claim transaction completion.

The existing exchange owner supplies the durable store and transaction WAL. No second coordinator or replacement transaction WAL was added. Store interface:

- `get(containerId) -> current lease or nil`
- `get_tx(transactionId) -> its last immutable lease/tombstone or nil`, including old generations forever
- `cas(containerId, expectedRevision, newLease) -> true` only after durable commit. It must serialize this one Pal authority, update the current-row export used by the witness, and preserve every old lease revision/tombstone.

Other required callbacks:

- `request_id(lease, operation, attempt)` must deterministically bind UUID to transaction + lease generation + native operation. `escrow_credit.native_request_id` provides a UUID5 implementation; native RequestID by itself is NOT idempotent.
- `authorize('source', lease, sourceSnapshot)` checks the real bound bag/current guild-base source. `authorize('mc_debit'/'mc_credit', lease, receipt)` checks saved Minecraft receipt + same ID/fingerprint/direction. `authorize('terminal', lease, receipt)` checks the owner's actual durable v3 terminal WAL.
- `accept_witness(lease,witness)` verifies its trusted saved receipt. The adapter independently checks protocol, ID, fingerprint, lease generation, lease revision, container, slot, phase, exact afterimage and SHA256 shape.

Transaction schema is the existing identity tuple with `protocol=3`: `id, mc_uid, player_uid, mc_world, item, count, action, fingerprint`. Quantity is 1..64, ordinary Wood/Stone/Coal/Charcoal only. Binding is `{owner_uid=transaction.player_uid, guild_id, base_id=sourceBaseId}`.

One ordinary chest is reserved as a whole and only its slot 0 is used. It must be wholly empty at enrollment. This makes ordinary single-stack sorting harmless; AI organizers still exclude the entire chest. Candidates bind `model_id, concrete_id, container_id, type, capacity, base_id, guild_id, position, source_base_id, enrollment_save_sha256`. Runtime calls verify registered model → no-force concrete → actual container module → canonical manager container, construction/HP, type/capacity, guild/base and position. Missing, destroyed, rebound or relocated escrow stays held; no replacement ID or lease is created.

## Actual isolation configuration, without extra accounts or clients

Use a current real player's/guild's ordinary paid wood chest outside **every** live base radius, with 1000 cm margin. `base_id` must be the zero GUID; `source_base_id` remains the original legitimate guild base for material selection. No new account, synthetic identity, private-lock holder or player disconnect is required. Private locking may be supplementary; it is not the policy proof.

Create a singleton `rpc_guard` with `readers` and `current(containerId)` backed by the owner lease store. Pass it into `daily_guard` with `backend`, `readers`, `epoch`, and `excluded(containerId,modelId)` tied to the ACTUAL organizer and exchange-source exclusion table. `daily_guard` rechecks base ranges, ownership, position and exclusions every use. A newly built nearby base stops further effects.

The RPC guard registers the **existing** reflected functions:

- `PalNetworkItemComponent.RequestMove_ToServer`, `RequestMoveToContainer_ToServer`, `RequestSwap_ToServer`, `RequestDispose_ToServer`, `RequestDrop_ToServer`.
- Both `PalPlayerInventoryData.RequestFillSlotToTargetContainerFromInventory*_ToServer` quick-stack paths, because these can invoke native manager Move directly.
- `PalInteractiveInterface.IsEnableTriggerInteract`: override its boolean to false for the reserved chest Actor/owned interaction component.

For void RPCs the hook does **not** pretend that returning false cancels execution. It writes an invalid destination slot/container or empty source array through `RemoteUnrealParam:set`, so the game's existing native pre-mutation validator refuses it. Only an internal, local permit matching the already-persisted operation RequestID and reserved container permits the adapter's normal Move/Dispose. Other players' containers pass through unchanged. No low-level native detours or administrator/third-party-memory-write protection is involved.

The 2281fa31 source `work/palworld-live/research/ue4ss-2281fa31-LuaUObject.cpp` confirms struct/array setters. The matching ObjectDump confirms every registered function. Primary docs: [RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html), [RemoteUnrealParam](https://docs.ue4ss.com/dev/lua-api/classes/remoteunrealparam.html). Live RPC dispatch and UI getter routing are still unverified; a Lua mock cannot prove them.

Strict normal policy accepts only a certificate for this exact model/container with `runtime_verified, player_open, pal_transport, craft_consume, ai_organize, restart=true`. For the lead's explicit **BridgeLab pilot**, both the adapter and daily guard can receive `lab_candidate=true` and record `assurance='lab_candidate'`. This allows a real pilot before certification, including an explicitly enabled produce candidate. Without RPC filters this is only ordinary spatial isolation + exclusion + change detection; do not present it as strict concurrency acceptance. Strict mode never fabricates a proof.

## Direct escrow credit, actual API path

`escrow_credit.cpp` is a produce-only native candidate for the already-matched 1.0.5 executable. It uses the existing verified Prepare RVA `0x02E6C180`, Commit RVA `0x02E60400`, and game-free RVA `0x032A0700`, with copied code fingerprints/ABI gates. It accepts one real empty slot and one nondynamic allowed-item descriptor, produces an engine-prepared record, validates all returned data, commits Product=1 once, and reads the exact slot back. It does not create/register a persistent container, write raw inventory fields, stage items in a player's bag or compensate blindly.

The Lua backend obtains the descriptor through the **existing** `PalItemUtility.CreateLocalItemSlot` (a local UI object, not persistent escrow) and calls the fixed native export. This is an explicit candidate: its actual produce preparation slot convention and descriptor semantics need the one-item Lab test. Prepare mismatch refuses BEFORE commit. The known same-slot native compensation evidence does not prove this produce-only preparation path.

`palcraft/mcp/escrow_credit.py` creates a 128-byte one-use permit only after reading the real MC player's gzip NBT, validating bound world and UUID, and finding `palcraft.exchange.v3:<tx>:debit` in actual saved `Tags`, plus a matching durable v3 MC WAL. A `mc_debit_durable=true` flag or old v2 tag alone cannot authorize it. The permit binds native RequestID, transaction, generation, exact container/slot/count, fingerprint and saved-player SHA256. Non-replacing claim files survive restart forever. Integrate the v3 tag prefix in the exchange owner's Minecraft leg; this module intentionally does not accept v2 receipts for a new v3 transaction.

Native wire is 208 bytes, with static assertions in the source. Files stay inside fixed BridgeLab `rpc/`. Build/deploy the DLL from the owned `escrow-storage` directory, then copy next to the server scripts during an owner-authorized deployment. The Windows x64 DLL is built at `palcraft_escrow_credit_v1.dll`: 28,160 bytes, SHA256 `0260235fc9028a49f269fa450ec19886ff541c39f0e8983624d2219f4419748f`, one export `palcraft_escrow_credit_v1`. Zig 0.15.2 used `-j1` under `nice19`; only KERNEL32 and Windows UCRT API sets are imported. `windows-build-evidence.json` records the exact command and PE inspection. No deployment/game loading occurred. `build_windows_dll.py --build` reproduces it; without `--build`, that script only verifies the existing file.

## Two real save barriers and stale witnesses

Import: `claim → ordinary moveIn → full Level witness → durable MC credit → dispose → empty Level witness → durable v3 terminal → release`.

Export: `durable MC debit → claim → direct escrow credit → full Level witness → ordinary deliver → empty Level witness → durable v3 terminal → release`.

`palcraft/mcp/escrow_witness.py` reads the actual installed Level, decodes ordinary chest model/concrete/module binding and 1.0 sparse slots, verifies the exact escrow afterimage, requires the genuine source/recipient containers to exist in the SAME Level file, checks save barrier and file/current-lease races, forces the file and receipt, and writes separate full/empty witness names containing transaction and generation. Recipient contents/source quantities may lawfully change. If bag/source lives in another save file, it refuses until the owner adds atomicity proof.

Pass `--lease-current` as the owner's atomic CURRENT lease export; `escrow-leases-current.json` supports `{protocol:3,revision,leases:{containerId:completeLease}}`, selected with `--tx-id`. Only the selected row must remain semantically identical; other leases may advance. An old immutable revision file by itself cannot prove the generation is still current. Late receipts are rejected by exact generation/revision/phase checks even if their worker finishes after release/reuse.

`release` requires `status='empty_saved'`, actual live slot empty, and a terminal receipt `{protocol=3,id,fingerprint,lease_generation,state='completed',escrow_empty_durable=true}` verified by the owner. v2 `completed` never releases a v3 lease. Timeout/offline/space shortage does not release it.

After an attempted native effect loses its response, `reconcile` may recognize its own exact afterimage in the still-exclusive escrow and advance with no native replay. If it sees the beforeimage or a partial/foreign image, it holds `needs_recovery`; it does not retry. `rearm(lease,proof)` now supports a genuinely lost unpersisted effect, including observed-in-memory but unwitnessed effects. It requires a changed REAL Pal boot, the exact pre-attempt installed full-world checkpoint/beforeimages, current lease revision, and the owner's trusted bootstrap certificate validation. It preserves prior attempts and increments attempt/RequestID within the same generation. Accepted full/empty witnesses cannot be erased or rearmed. `mcp/escrow_rehydrate.py` verifies the installed checkpoint with a mandatory lifecycle `verify_boot` port; issuing that actual loader certificate still needs owner integration/live validation. See `REARM-PROTOCOL.md` for the exact schema.

## Reusing existing paid boxes and minimum future Lab window

The actual paid serial chest is model `00000000-0000-4000-8000-00000000000c`, concrete `00000000-0000-4000-8000-000000000028`, container `00000000-0000-4000-8000-000000000016`. It cost 15 Wood + 5 Stone and its model/module/container is truly saved. The historical save contains Wood17/CopperOre13/Fiber3, and the chest is in a base. All 19 ordinary chests in that historical Level are inside bases. **None is an already-proven empty outside-base escrow.** Historical builder UID `d8178a9d...` belongs to the actual player “落日残殇”; do not relabel it a service account.

`escrow_lab_probe.lua` is an unscheduled read-only survey/observation module for the lead's next lease. It enumerates registered ordinary chest bindings, current actual players, all base ranges, private-lock facts and contents. It makes no build/move/save calls. Run it through the existing authorized game-thread bridge, retain the JSON, then select a current real ordinary candidate. Survey observations do not set `runtime_verified`.

Minimum actual steps, during a lead-granted Lab window:

1. If no current empty outside-base paid chest exists, use the normal **survival** build path at reviewed ground outside base radius +10m, deducting real 15 Wood +5 Stone. The existing `build.lua` preflight supports only inside-base foundations; do not silently remove its checks or invent a CreateContainer API. Use ordinary player construction for this one placement, or have its build owner extend the normal paid path explicitly. Verify actual completed model/module/Level save and enroll these fresh IDs/coordinates.
2. Install one reserved-ID exclusion table and the singleton RPC guard before claiming. While the same real owner remains online, attempt normal open/manual withdraw/deposit/quick-stack/drop. Verify hook counters and exact before/after quantities; validate real blocked RPC dispatch makes no consumption. Also verify a separate normal box still works, and the adapter's ordinary Move has its local permit and succeeds.
3. Using real stock, Move one existing material into escrow, leave normal Pal transport working at the nearby base and perform one ordinary base craft. Verify neither supplies/deposits into the outside chest. Preserve observation/ordinary-craft receipts; do not generate test materials. These are the requested transport, supply and player-open daily challenges.
4. Save and reconnect/reload in the same authorized lifecycle window. Restore guard from persistent lease BEFORE accepting normal transactions; verify stable model/container ID, exclusions and held contents. A controlled release/reclaim must increase generation and reject an intentionally late old witness.
5. For direct credit, consume **one actual MC material via the v3 normal saved debit**, create its NBT-backed permit, then attempt the native produce candidate once. Verify exact escrow count1, native prepared record convention, full Level witness; Move that legitimate converted item to its actual bag, verify empty Level witness and same-Level bag presence. Do not enable larger amounts before this passes.

If the interface getter does not route through this reflected hook, the inventory RPC filter still needs its negative test. Record that UI opening is not blocked yet; use the candidate's ordinary isolation + detection while adding the actual derived interface hook or existing interactive-component disable path. Do not require an offline account as a workaround. No extra rendering process, stress test or high-performance mode is needed.

## Offline evidence

`run_checks.py` runs the lightweight checks serially at low priority and writes `offline-evidence.json`. This branch owns these files and does not repeat exchange_recovery's existing v2 WAL/crash matrix.

- 44 Lua adapter/filter/rearm cases in the last full source run, followed by 2 focused selected-row/rebase/compact-receipt cases: true material Move workflows, two save phases, MC receipt prerequisite, exact local permit, unrelated Move passthrough, void-parameter neutralization, boolean interaction override, offline/space holding, destroyed/rebound/relocated model, lawful source production and bag sorting, ambiguous native beforeimage, lost native response, generation/revision/phase stale witnesses, and v2 terminal rejection.
- 24 Python witness/actual saved NBT permit/rehydration tests in the last full source run, followed by 3 focused selected-row/platform-I/O tests, including actual historical serial Level (1404 containers / 19 ordinary chests), file replacement/current-lease race, missing same-Level counterpart and claimed/partial permit retention.
- 24 C++ native candidate gates/prepare/commit-readback mock cases. These validate buffer layout and refusal behavior; they do not prove live native produce semantics.

Remaining: owner v3 wiring/store/current export/exclusion table; isolated Windows loader smoke and the minimum real Lab challenges/produce trial; trusted new-process whole-world checkpoint certificate and controlled restart acceptance. Nothing here is a player-ready runtime acceptance claim.

## Final exact-record and Windows file-handle alignment

The persisted and returned witness now includes `lease_record`: the complete selected CURRENT row, rather than the combined export. The owner factory validates full semantic equality, protecting safe rebase under an unchanged generation/revision/phase/count tuple. After that validation the adapter removes `lease_record` from its stored full/empty receipt, so subsequent snapshots do not recursively copy prior snapshots. `focused-evidence.json` records 2 Lua and 3 Python targeted checks; the prior 92-case full run was not repeated in night mode.

`mcp/escrow_io.py` performs read-and-force on Windows via OPEN_EXISTING with GENERIC_READ|GENERIC_WRITE and SHARE_READ|SHARE_WRITE|SHARE_DELETE, never writing/truncating source bytes. This corrects read-only-fd fsync incompatibility and avoids blocking normal atomic file replacement. The own credit/witness/rehydration verifiers reuse it. Microsoft documents the write-access requirement in [FlushFileBuffers](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers). Actual Windows loader/file-I/O invocation remains a future isolated check.

Reviewed the real `EXCHANGE-V3-HANDOFF.md`/factory/worker: current export, exact row validator, actual Level parser and rearm callback contracts agree. The owner uses its own matching Lua/Python deterministic RequestID scheme and passes that ID to permit preparation, which is compatible. Two owned follow-ups were reported through the lead: the credit saved-leg reader still used rb+fsync and must adopt shared read/write force; observed-but-unwitnessed full/empty rollback must reach the rearm publisher/consumer before a new REST save overwrites the pre-attempt checkpoint. No exchange-owner file was edited by this branch.
