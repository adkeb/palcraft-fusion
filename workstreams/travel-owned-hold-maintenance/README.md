# Preserve the owned travel movement freeze until final acknowledgement

A real singleplayer transition kept its original authority hold marked disabled, but the possessed character movement mode was Walking and the pawn was about 149 cm from the committed target. Its 50 cm replication confirmation consequently failed. The actor did not lose its identity, and the original camera-commit predicate passed. The exact native subsystem that restored Walking is not proven.

This delta maintains the movement disable already acquired by the travel executor. After its normal teleport and on each pending server progress callback, it checks the same live authority controller, pawn and movement component. If the acquired authority hold still owns the disable and the movement mode has been reset, it stops movement and disables it again. It does not acquire extra ignore-input entries. The original release restores the original mode once; a replacement pawn is never modified. A client-only hold does not disable authority movement.

Position tolerance, replication timeout, destination, logical intent, native camera proof, final acknowledgement, inventory and material rules remain unchanged. Recovery continues through the original measured forward-retry API. No pose, checkpoint or ACK is edited by this source delta.

Three targeted temporary-object cases exercise the real actor methods and server move/progress methods. Native teleport resetting the movement mode is explicitly simulated. The actual repaired game transition has not yet been exercised.
