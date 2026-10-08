# Queued centre and action-source observation

This candidate changes two managed payloads: the native operator DLL and the original MC10.10 component with an action-observation suffix. It has not been installed or run in Game.

Actual Win cursor sampling keeps the one-shot host centre marker armed. Only the owned hook's centre WM_MOUSEMOVE consumes it, with original scope reset and expiry retained. Pending ordinary motion is still accepted, and human returns through centre after the warp acknowledgement are counted. The integer HUD mapping, helper, Windows RAW/old relative mode, native750 freshness and current input ABI remain unchanged. Two actual-header cases model both cursor-read/queued-message orders with synthetic data; they do not prove every real pixel is delivered.

Original controls status records actual polled F9/F10/left/right states, derived attack/use, down-edge counts, source mask and tick, and original WsClient.send attempts/success counts. Source bit1 is the function key, bit2 is the corresponding mouse button. These counts distinguish state transitions from a generation resend. Send success is the original socket-send result, not proof that MC applied the action.

The original command.json sender adds only attempt sequence, successful-send count, last tick and a whitelisted action hint to render status. It never logs the payload. The hint recognizes compact key fields; it is not an exact JSON parser or attribution proof. Original send/delete behavior remains. MC inspection reads actual keyUse down and existing Mixin getter click counts without consuming or changing them. No actions, damage, inventory, HP, pose, ready/ACK, authentication or gameplay features are disabled or forged.

Native compiled controls and palcraft once and reused the unchanged ws/compositor objects. Seven exports, original imports and snapshot ABI remain. MC compiled only HostLink once; all171 unrelated JAR entries keep original bytes/CRC. The initial fixture had a test-only output-string error; the initial post-javac ZIP verification used a mutated old ZipInfo reader. Both failures are recorded. Fresh readers verified the already-built JAR without recompiling or rewriting it.

The unexpected torch source and actual continuous negative navigation remain runtime questions. No Game, GUI, RPC, input, installed/current state, saved world, credentials or Git operation was performed.
