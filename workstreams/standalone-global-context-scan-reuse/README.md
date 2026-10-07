# Standalone global context scan reuse

Actual short worker timing found repeated global GameStateBase scans in the shared companion context, and repeated PalPlayerController scans in server entity operations. This increment obtains the current validated standalone realm proof instead: the actual game state/controller/world and UID/pawn relationships are still checked on each operation. Invalid standalone context fails without falling back to a foreign game state. Network mode retains its original global scans.

The two source changes leave all NPC PalCharacter discovery, range, spawn/damage/food/vitals, geometry and cadence unchanged. Twelve isolated synthetic lifecycle/context contracts and Lua5.4 syntax passed. This does not yet prove actual FPS improvement. The independent empty-entity index draft and five earlier duplicate-current cleanups are not adopted.

The increment is packaged in candidate22 with the form-intent and finite snapshot progress changes. It has not been installed. Candidate21 suffered an actual client crash after an ordinary torch mining event; mining/pickup and complete playable acceptance remain unfinished. Native crash dumps and private runtime records are excluded.

Run `lua checks/check_hotspots.lua .` with Lua5.4 in this workstream; the copied helper fixtures originate from the exact production method bodies.
