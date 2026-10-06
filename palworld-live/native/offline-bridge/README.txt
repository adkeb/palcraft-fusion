Palworld 1.0.5 native bridge — local research status
Updated: 2026-10-04

Current result
The isolated BridgeLab single-slot material trial succeeded. Wood changed from
172 to 171 and back to 172. The complete 48-byte slot payload was restored, and
all item identities/counts in the 18 allowlisted chests stayed unchanged.
The trial did not touch production. Lab PID 33492 was healthy afterward.

Evidence
- Trial nonce: 00000000-0000-4000-8000-00000000002c
- Native stage: restored; consume_called=true; restore_called=true; ok=true.
- roundtrip-manifest.json records the exact reviewed DLL/Lua hashes and outcome.
- Before the trial, the parent stopped Lab and independently hash-checked all
  85 Saved files against the backup copy:
  D:/PalworldServer-LAN/BridgeLab/checkpoints/roundtrip-20261004-064805/Saved
- Native ASan/UBSan mocks: 13 cases; Lua mocks: 9 cases plus replay refusal.
- Independent review: ../../research/material-roundtrip-independent-review.json

Verified stages
1. Real offline account lookup and account/inventory/technology ownership.
2. Native material transaction preparation, with no live inventory mutation.
3. One native Wood debit followed by exact same-slot compensation.

Checks still owned by the parent
Live negative replay refusal, probe cleanup, and saving/checking target-slot
persistence are in progress. This README does not mark those checks as passed.
The local mock replay check is distinct from the live negative replay check.

Scope and limits
This proves item transaction and compensation plumbing only. The low-level
commit applies final slot state; it does not validate recipes, technology,
guild permission, collision, support, or building placement. The fixed reviewed
Lua selector restricts this test to nondynamic Wood; the native export is not
a general MCP inventory API.

Normal survival construction is NOT complete. The normal downstream path still
requires a real active PlayerState and pawn, so validation needs a legitimate
isolated Lab client. Do not change the normal flag to false, use free spawning,
or fabricate another player's identity as a substitute.

The mutation probe requires a one-time arm marker, persistent intent, and a
non-replacing native permit claim. An existing intent or claim prevents retry.
If interrupted, preserve evidence and inspect manually; never blindly repeat
the debit or refund. All experimental native work is restricted to BridgeLab.
No further experiment is being added in this update.
