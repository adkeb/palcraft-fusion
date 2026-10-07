# Initial NativeHome uses the normal Pal spawn

The existing initial native Overworld join/reconnect/respawn condition now selects the authenticated actor's actual saved/respawn snapshot as its target. Required coverage is derived from that actor's feet through the unchanged inverse mapping. MC saved pose is left unchanged during preparation and synchronizes through the existing trusted post-ACK host_pose route.

Mapping/origin/region bounds, identity validation, collision/readiness, measured 50 cm position check and camera/complete-ACK sequence remain. Auxiliary Nether/End and ordinary established transitions retain their original MC destination. No teleport bypass flags or MC Jar changes are introduced.

Run `lua checks/check_initial_home.lua` with Lua 5.4. The three source cases load the original protocol and server module, using explicit synthetic actor/native/camera/collision callbacks. They do not demonstrate actual Game success. The first two test runs exposed fixture setup errors only; the corrected cases passed. Actual diagnostics and private handoff are excluded from public source.
