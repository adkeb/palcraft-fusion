# HUD client-screen centre correction

This source candidate changes only the existing Mac HUD payload. In the explicit CrossOver host-warp mode, the HUD computes a whole-pixel centre from the actual native ClientToScreen origin plus the reported client centre. It no longer scales between Win outer-window and CGWindow bounds, which can represent different border extents.

The original geometry/owner/epoch/generation/live/focus/menu/buttons checks remain. A request still does not count as an observation: the original callback must read the actual CG cursor, and unchanged native code must independently query and match its actual Win client cursor. The existing one-shot centre marker, ordinary mouse authority, original cadence and live FPS are unchanged.

One limited case extracts the actual planning function. All identity, epoch, clock, geometry and cursor data are synthetic. It checks centre(756,476) from origin(116,116) and client centre(640,360), and rejects cursor(756,474) as an observation. The HUD was compiled once for arm64 macOS13; it was not run. Actual continuous look remains unverified.

No Game, GUI, RPC, input, installed/current file, saved world, credential or public Git operation was performed. Native/helper binaries and their sources are unchanged.
