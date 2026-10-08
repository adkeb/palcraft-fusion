# Refresh the current native-home spawn

One server travel source slot changes; the client, actor adapter, protocol,50cm tolerance,750ms input/camera rules and ACK chain remain unchanged. This candidate has not been applied to a live world.

Native-home preparation takes the current authority pawn snapshot, recomputes its feet and complete required bounds through the original registry, and journals the refreshed target before prepare. After native activation it reads the same pawn again. A drift beyond50cm or insufficient actual server/client coverage invokes the existing measured forward-resume method, which creates a new transaction identity and normally releases/reprepares its owned ticket/hold. It does not teleport to the earlier spawn. The original client therefore cannot reuse its cached prepared target for a substantially new target.

For a small drift covered by both original readiness checks, the actual target is journalled and the original commit/observation/camera/ACK sequence continues. Repreparation retains the original initial limit and clamps its deadline; it cannot extend that cap. Auxiliary/dimension-target behavior remains unchanged.

Three limited cases load the actual server, protocol and original client methods. Every identity, position, actor, readiness, camera and journal observation is synthetic. They cover late same-pawn drift with a new prepare/no teleport/no ACK and finite cap, stable original completion, and20cm drift accepted by the unchanged client. They do not prove live respawn success or identify the exact native late-position API.

The nested scheduler fence uses the region's first native_view, whereas readiness's top-level view uses the current ticket. This mechanism was only documented; no fence or ready value was rewritten. No Game, GUI, RPC, input, installed/current file, saved world, credentials, process or Git operation was performed.

The final one-line follow-up keeps the native-home rehold's movement restoration based on the actual current CharacterMovement, rather than the earlier source snapshot. The original actor.hold captures current mode when restore_state is nil; non-native recovery keeps its existing restore argument. The late-drift fixture was rerun once and records a nil restore/current receiver mode instead of the old source mode. That receiver state is synthetic and does not prove a live engine movement mode. The preceding three-case run and original source freeze remain unchanged.
