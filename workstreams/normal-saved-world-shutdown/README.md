# Normal saved world shutdown

The original operator stop rejects an active physical view hold or recovery transaction. That protects a game which is expected to continue, but a normal saved shutdown must retire its owned native-home scene before returning to Title.

This source adds a separate normal lifecycle entry. It reads the current installation lifecycle token, original successful save witness and exact native UID/world/process scope; a caller boolean is not a save proof. It retains the original operator stop and guard byte for byte. Only exact owned native-home tickets are retired using the existing server stop, lock release, scene release, view/form reset, companion cleanup and client stop APIs. Auxiliary, foreign or unknown leases are rejected. If the original world is actually dead, a fresh Title controller is required and the existing abandon path is used without calling old world objects.

The original server stop persists its own handoff; no new teleport, ACK, transaction replay, save request or custom WAL rewrite is added. Three bounded synthetic function cases and the generated Lua/Python syntax checks passed. These adapters do not prove real native release. Actual normal Title/exit0 and cold-loading remain unaccepted until the player run verifies them.
