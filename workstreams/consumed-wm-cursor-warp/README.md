# Consumed WM motion and causal host warp

This candidate changes two managed payloads: the native operator and original Mac HUD. No actual F03 pass or cause of each missing real step is claimed.

The existing owned hook records actual WM messages, processed client point/sequence/tick, centre acknowledgement, seeds, nonzero look,128px jump drops and gate/outside drops in the original input JSON. A processed point can have a recorded drop reason; it is not a claim that look was applied. Scope reset invalidates the consumed point. Current owner/native epoch and generation remain required. No new log, timer, manager or input source is added.

The original HUD waits for a same-scope consumed off-centre point to match both the actual Win cursor query and its actually read CG cursor, in the already-established screen mapping. Worker arm alone is insufficient. Before CGWarp it captures that matched WM sequence; the original observed metadata carries it, and another successful warp in that owner/epoch/generation requires a newer consumed sequence. Actual cursor observation is still mandatory.

Native verifies the actual Win centre and only establishes a centre baseline when no point exists or the current WM sequence still equals the warp's matched sequence. When newer WM has advanced, the older observation cannot overwrite its point or marker. The original one-shot centre WM acknowledgement remains.128px filter,750ms freshness, epoch/auth, UI/focus/buttons, Windows RAW and old relative mode remain unchanged.

The prior two pure-function groups and source review are preserved under pre-sequence-review. One additional native sequence case and the actual HUD helper check passed, with every identity, point, clock, metadata and message value synthetic. They show missing-centre-WM recovery through a real-centre parameter and matching sequence, newer WM preservation, original human return after centre acknowledgement, and refusal to reuse old warp sequence. No actual Win or CG event was injected by these cases.

Only controls.cpp was compiled once, reusing the unchanged current palcraft/ws/compositor objects. HUD was compiled once for arm64 macOS13. Seven exports, original import modules and binary input ABI remain. MC, helper, runtime and all other sources/payloads remain unchanged. No Game, GUI, RPC, input, installed/current file, saved world, credentials or Git operation was performed.
