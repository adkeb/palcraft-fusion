# Saved shutdown with a missing logical home anchor

Only the existing main saved-home cleanup predicate changes. When the camera mapping is absent or lacks its world session, the predicate can use a present host-owned player/pending/recovery ticket's native-home mapping as a local source anchor. The candidate passes the original home validator before selection. The mapping is not written back to camera state.

Explicit nonhome camera state remains refused. A partial source with a different home origin or region is refused. All original pending/player/recovery checks, native realm identity/epoch/world address checks, per-ticket view checks, home origin checks, deduplication, and exact owned-lease count remain intact. Missing tickets do not establish an anchor. The Save witness guard, operator stop guard and cleanup ordering are byte unchanged.

The three supplied cases use the exact original/new main functions with clearly labelled synthetic ticket/realm/file-witness data and scoped cleanup adapters. They do not establish a real Save, native release, ACK, or live shutdown success. Run them with the existing Lua 5.4 CLI, passing the existing workspace and this exported directory as arguments; the fixture uses the workspace's shared JSON provider.

`construct_predicate.lua` is a pure optional constructor. It reads an original shutdown function's predicate upvalues and builds a reviewed replacement predicate in that scope. It returns both functions and the original upvalue index. It never calls a predicate or changes an upvalue. Any actual application requires a separately approved action by the sole runtime owner; this source task did not execute it or reload a module.
