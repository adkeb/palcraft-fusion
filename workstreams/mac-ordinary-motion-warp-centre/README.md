# Mac ordinary mouse and observed centre candidate

This source candidate changes two managed payloads: the native operator DLL and existing Mac HUD. It has not been installed or exercised in Game.

In explicit `relative-host-warp-v1` mode, ordinary WM_MOUSEMOVE is the sole look motion source. Windows RAW and the old relative-v1 mode retain their original handling. The owned HWND publishes actual window/client geometry and queried cursor coordinates. The existing HUD callback maps its client centre through that geometry and actual CGWindow bounds, without a fixed title-bar estimate.

The existing metadata file distinguishes a centre request from an actual CG cursor observation. Native acknowledges the request before HUD warps. A same-scope one-shot armed centre marker consumes one warp return; other pending movement and later human moves through centre count normally. Native baseline confirmation independently queries GetCursorPos and ScreenToClient, and requires the actual point to match. Request coordinates are never claimed as an observation.

The three limited groups use actual production header functions and the extracted HUD planning function. Every identity, timestamp, geometry and cursor value in them is synthetic. They check ordinary accumulation, one-shot centre handling, geometry mapping and scope/UI rejection; they do not prove real infinite FPS look.

Native build compiled only controls.cpp and linked three unchanged objects from the earlier complete four-TU source build. HUD was compiled once for arm64 macOS13. Both binaries were not run. Seven exports, original import modules and the binary input ABI remain unchanged. Original 8ms native tick, HUD callback, 750ms camera freshness, owner checks, menu/focus/buttons and live FPS remain in place.

Actual new window mapping, warp jitter and continuous yaw/pitch still require ordinary player verification after an approved update. This bundle contains no private Game observation, actual identity, saved world or credential.
