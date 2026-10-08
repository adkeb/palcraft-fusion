# Authoritative target snapshot loading

Four source modules change, plus the MC component version. No native/HUD/runtime source or live data changes. Production MC compilation is delegated to the approved assembler; this handoff contains full current source rather than a reused modified class.

The Pal prepare's authenticated tx and exact required_bounds select the snapshot ring. Its pos field is not the snapshot centre. Lua now deduplicates by tx and bounds as well as the original authenticated view tuple, so a same-view new authoritative target requests a fresh snapshot.

The original MC gateway still validates signed current prepare and exact bounds. Only that validated request may enqueue target chunks not already loaded. The original Snapshot scanner starts at most one normal asynchronous chunk acquisition per tick, retaining its8ms/4096cell/256operation budgets and original ring bounds/capacity. Unscoped ordinary sync remains loaded-only.

Each target Snapshot owns a distinct nonpersistent loading ticket. Finished target jobs retain their tickets because snapshot_end or ACK alone does not put the distant MC player at the target. Actual PLAYER_LOADING coverage transfers ownership; abort/recovery, changed tx/view/world and original teardown release the owned resources. Vanilla player tickets are never removed. The original gateway cancellation path is wired to this lifecycle; no new manager, schema, logger, pose, item, HP, grant, ready or ACK writer is added.

One aggregate case executes extracted production Snapshot/scanner/cancellation methods with synthetic APIs and data. It checks81exact tiles, bounded acquisition, completion/ACK retention, player-loading handoff and new-tx release. Lua's single dedup change was reviewed directly rather than adding another fixture. It does not prove live view completion. The available normal loading APIs were read from official local class metadata. No Game, GUI, RPC, input, installed/current file, saved world, credentials or Git operation was performed.

The public helper is portable: `python3 checks/run_case.py --java-home /path/to/jdk25 --gson /path/to/gson.jar`. Supply existing dependencies; the case uses synthetic API objects and does not start Minecraft or Palworld. This argument-only sanitation was not rerun and does not change production sources.
