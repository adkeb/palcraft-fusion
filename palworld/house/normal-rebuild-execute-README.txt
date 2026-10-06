Single normal wooden-chest rebuild — BridgeLab only

Frozen candidate files and test/runtime evidence are recorded in:
  research/normal-rebuild-execute-manifest.json
Independent review:
  research/normal-rebuild-independent-review.json

Status: ISOLATED LAB CRASH; INDETERMINATE, NO RETRY. Both read-only previews
passed. Root then submitted nonce 00000000-0000-4000-8000-000000000017 once.
The normal call returned and immediately consumed exactly 15 Wood + 5 Stone;
other checked slots were unchanged. The Lab process crashed before the next
observation was persisted. No completed construction, saved persistence or
client replication is established. Root preserved report and permanent intent,
and is collecting CrashContext before restoring only Lab. Production remains
healthy and was not modified. Frozen code is retained solely for diagnosis;
do not reuse the following deployment procedure to retry this operation.

Deployment (root alone; never production):
  Copy normal-rebuild-execute.lua, normal-rebuild-execute-core.lua and
  normal-rebuild-materials.lua into the existing Lab PalLiveBridge Scripts.
  Existing json/readers/targets/build/registered-model-details-core dependencies
  remain required. Host enforces the exact absolute BridgeLab Scripts path.
  Copy client-manual-nearby-saved-buildings.json to:
    D:/PalworldServer-LAN/BridgeLab/rpc/normal-rebuild-nearby-baseline.json
  Keep original manual capture and registered model details evidence in rpc.

Arm path:
  D:/PalworldServer-LAN/BridgeLab/rpc/normal-rebuild-once-arm.json
  Preview: nonce=fresh UUID, mode=preview, expires_unix=now+120 (max 300).
  Execute: another fresh UUID, mode=execute, expires_unix=now+120,
    operator_confirmed_normal_dismantle=true,
    execute_exact_manual_request=true.
  The user already confirmed normal dismantling; preflight independently
  requires the old model to be absent. Do not use the old preview-only host.

Invoke the host at top level through the root-controlled Lab main. Output is
  rpc/normal-rebuild-once-<nonce>.json.

A nonreplace, read-back-verified intent is created before the only normal RPC:
  rpc/normal-rebuild-once.intent.json
Never delete this fence or change nonce to retry an uncertain native request.
The fence survives final-check failure and blocks another nonce. Flush, close,
readback and rename protect script reload/process restart, not a promise of
Windows power-loss fsync durability. Existing nonce output prevents replay.

The only gameplay write is the same normal RequestBuild_ToServer observed
from the user's real client: ItemChest, exact captured location and quaternion,
empty archives and bNotConsumeMaterials=false. Real current player identity,
guild/technology, recipe, materials and registered site are checked. Nine
historical neighbors and the exact eight-building 11.9 m inner set must match.
This is evidence for this manually proven point, not generic geometry proof.

Observe for at most 30 seconds. No automatic retry, refund, free spawn, owner
replacement or forced work completion exists. Materials are compared by full
slot identity/count across the 13 old-base chests and player CommonContainer.
Native normal construction supplies its own actual permissions, consumption,
placement checks and work process. Passive hooks help associate this request
with the new registered model and initial BuildWork.

Terminal success requires a current unique new registered ItemChest, exact
owner/base/guild/transform and a new initialized ten-slot container, plus
strictly attributed normal recipe debit and no ambiguity. Initial work missed
is explicitly distinguished from observed normal construction. New chest
contents from normal Pal transport do not alone invalidate construction.

After the attempt, root must preserve report/intent, remove the observer from
main, and separately check actual client visibility and saved persistence.
An indeterminate result must be investigated without another request.
