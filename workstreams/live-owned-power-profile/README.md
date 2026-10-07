This source delta adds an explicit live performance request handled by the existing local singleplayer supervisor. It changes no running installation in this workspace.

After a normal update and boot containing all seven payload changes, use the original CLI:

```text
palcraft performance --root OWNED_ROOT --preset normal --live --mc-fps 60 --hud-fps 30
palcraft performance --root OWNED_ROOT --preset night --live --mc-fps 10 --hud-fps 10
```

`--pal-fps` uses the existing validated 10..120 range. Optional `--mc-render-distance 2..32` and `--mc-muted true|false` change only guest client options. Muted sets master volume zero; unmuted explicitly sets it to one. Music and simulation distance retain the original behavior. Caller policy selects when to send a request; this tool adds no clock schedule.

Without `--live`, configure and its return value remain unchanged. Live requests do not rewrite the managed profile, role argv, signed guest manifest, or next-boot configuration. Current live changes therefore last for this boot; future startup values remain governed by the original producers.

The request is accepted only by the currently running original owner with its existing client, MC guest, HUD relay, and HUD worker. Original Popen handles and worker-created child identity are used; this code does not start, restart, or adopt a role. The normal client-op mailbox is retained and its existing operation lock is used. Pal validates the original native process epoch and world/SID/UID tuple before setting FPS and reading both the settings limit and `t.MaxFPS`. No save/settings-save, Title, pose, inventory, credential, ready, input or ACK operation is added.

The MC guest applies options on its existing END_CLIENT_TICK, the HUD replaces its original display timer on its existing position callback, and the relay updates its existing loop period. Each returns correlated actual getter/timer values. The owner requires all four readbacks to match; rejection and timeout preserve partial observations and do not claim success. This is not a multi-role atomic rollback: a role may already have applied a setting before a later role rejects.

The two code dependency pins preserve the approved portable codec change (journal a8c49589 and CLI 6c3aa4b6), itself layered over candidate28 journal0978/CLIe67. HostLink, server tick/simulation, frame protocols, 750ms/250ms freshness, foreground group, input/security and world lifecycle are unchanged.

Three synthetic source cases passed, including the real extracted Foundation Timer methods without NSApp/UI, the generated Pal script with fake UE setters, original relay period update, owner correlation/rejection and default configure equivalence. Production Swift compiled once for arm64/macOS13; production Java compiled one changed class against the existing legal dependencies and preserved the other 171 JAR entries. This does not prove actual Game FPS or current runtime application; that belongs to the sole runtime owner after ordinary delivery.
