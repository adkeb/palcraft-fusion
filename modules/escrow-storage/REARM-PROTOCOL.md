# Current export and rearm contract for exchange_v3

Updated 2026-10-06 Asia/Shanghai. Additive adapter interface; no exchange-owner WAL files were edited. Source tests simulate process restoration and do not certify a live Pal restart.

## Current export

`escrow_witness.write_witness(root,currentPath,LevelPath,vendor,tx_id=TX)` and CLI `--tx-id TX` accept this atomic export:

```json
{
  "protocol": 3,
  "revision": 17,
  "leases": {
    "real-container-uuid": {"protocol": 3, "owner_tx": "transaction-uuid", "tx": {}, "revision": 9}
  }
}
```

The illustrated lease must contain the complete adapter row, not that abbreviated example: `tx`, `candidate`, `container_id`, `slot`, `generation`, `revision`, `status`, `expected_after`, `save_after_unix`, and `operations`. Full/empty receipt fields retain the original binding: protocol, transaction/fingerprint, lease generation/revision, container/slot, stage and exact afterimage. Source/recipient presence in the same installed Level is still required.

The receipt also includes `lease_record`, a full deep copy of exactly the selected row. Factory acceptance must compare that full semantic record to the current lease. This detects unconfirmed-current safe rebase even when the tuple remains identical. The adapter strips `lease_record` before storing its consumed full/empty receipt; that snapshot remains in the external receipt file and does not grow recursively.

Each container key must equal its row's canonical lowercase ID. One current transaction cannot own two exported containers. Released tombstones stay in immutable history for `get_tx`; the current map exposes the most recent row per container. If more than one full/empty row exists, the watcher must specify `--tx-id`.

The worker rereads the selected lease semantically after decoding. Another container advancing or changing the outer export revision does not invalidate this transaction. A changed/released/rearmed/replaced selected lease does invalidate it. `lease_sha256` hashes the selected row's canonical JSON (sorted keys, compact separators, UTF-8); `current_export_sha256` records the raw first-read export for audit and is not the equality criterion.

## Rearm API

Both `adapter.rearm(lease,proof)` and `adapter.rearm(lease,operation,proof)` are supported. It only commits a new journal revision; it never calls Move/credit/dispose, creates a permit, restarts a process or releases a lease. Afterwards the owner calls the ordinary `moveIn`, `ensureCredit`, `dispose` or `deliver` API again.

Pass `boot_id` in `new(options)`. It must identify the real Pal process/world boot and remain unchanged across a Lua/mod/MC-side reload. `epoch` can identify the Lua instance. A changed epoch with the same boot cannot rearm. Existing intents without a recorded real boot identity stay held.

Native intents now record `boot_id`, `epoch`, `attempt` (initially 1), and `attempted_unix`. Request-ID callback is `request_id(lease,operation,attempt)`. For attempt 1, `escrow_credit.native_request_id` retains the prior UUID5 name exactly; later attempts append `:attempt:N`. A callback that ignores attempt and returns an archived RequestID is rejected before native invocation.

Successful rearm preserves `operation_history[operation][]` including the original `observed` flag, consumes a unique proof ID, sets `next_attempt[operation]=oldAttempt+1`, clears only that active operation, and returns to `claimed` (MoveIn/credit) or `full_saved` (dispose/deliver). Generation, transaction ID, fingerprint, chest and material stay fixed. Old claimed native permit files are retained; the new native RequestID has a distinct one-use permit path.

An effect observed in memory but not yet witnessed in the actual save may be lost at a genuine process restart, so that case is included. **An accepted durable full witness prevents rearming MoveIn/credit; an accepted durable empty witness prevents rearming dispose/deliver.** This API cannot erase a witnessed result or implement an administrator rollback. The owner must also verify that its own MC coordinator has not already advanced past this native leg based on another durable receipt.

## Proof schema

`escrow_rehydrate.make_rearm_proof` returns:

```text
protocol=3
kind="escrow_rearm_after_world_rehydrate"
proof_id=fresh UUID (one-use)
id / fingerprint / container_id / slot
lease_generation / lease_revision
operation="moveIn"|"credit"|"dispose"|"deliver"
previous_attempt / previous_request_id / previous_observed
from_epoch / to_epoch
from_boot_id / to_boot_id
full_world_rehydrated=true
loaded_level_sha256 / installed_level_sha256 (identical)
boot_certificate_sha256
checkpoint_mtime_ns (checkpoint completed before old attempt)
saved_before (exact documented escrow beforeimage)
counterpart_before (exact original source slots, or delivery bag target, in order)
```

`authorize('rehydrate',lease,proof)` is mandatory and must resolve/verify the trusted lifecycle certificate and the MC coordinator prerequisites. A `true` flag in a file is not itself an attestation. Likewise a new random mod UUID, REST/save success, current mtime or one empty slot cannot create this proof.

The lifecycle certificate consumed by the Python verifier has:

```text
protocol=3
kind="palworld_full_world_rehydration"
full_world_rehydrated=true
boot_id=canonical UUID of actual new Pal boot
epoch=new adapter epoch
pid=actual Pal process ID
process_created_unix > previous native attempted_unix
loaded_unix >= process_created_unix
installed_level_path=actual installed world Level.sav
checkpoint_mtime_ns=actual checkpoint file metadata
loaded_level_sha256=exact checkpoint used to restore the COMPLETE world
```

The owner supplies `verify_boot(certificate)` to `make_rearm_proof`. It must validate the actual new process identity/creation time and a trustworthy bootstrap/loader record that the complete world loaded this exact checkpoint before new effects were admitted. The helper deliberately has no CLI that self-asserts this from booleans. A certificate for only a container reread or a hot reload must return false.

The Python verifier forces/rereads the installed file, rejects file races or a checkpoint completed after the attempt, verifies saved model/concrete/container/ownership/capacity/position, and requires the exact recorded escrow **and source/delivery-bag** beforeimages in that checkpoint. A source quantity changed since the captured checkpoint, absent same-Level counterpart, partial effect, persisted afterimage or foreign item stays in audit. The Lua adapter independently requires the exact live escrow beforeimage and the current lease revision. Normal source changes after the proven complete-world restoration can be replanned through the ordinary Move API; they cannot be substituted into the restoration proof.

Live loader/boot certificate issuance is still an owner integration and Lab validation point. Fixtures demonstrate the proof boundary; they do not establish actual Pal asynchronous-save capture semantics or support arbitrary manual backup restore.

The receiver/publisher must reach rearm for both unobserved native intents and observed-in-memory full/empty stages with no accepted corresponding durable witness after an actual new boot. Try the trusted pre-attempt checkpoint proof before requesting a new REST save; otherwise the bootstrap checkpoint can be replaced before the verifier sees it. An actual durable afterimage follows normal witness completion. `previous_observed` binds the old operation flag explicitly.
