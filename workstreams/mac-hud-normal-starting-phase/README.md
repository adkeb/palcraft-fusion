# Normal Mac HUD starting phase source delta

The original full-service promotion saves phase `promoting`, then starts `proxy` before `hud`. Every original `Session.spawn` saves phase `starting` after creating its child. The HUD foreground-group producer omitted that normal intermediate phase and emitted an empty group, which the existing required HUD gate correctly rejected.

This one-line change accepts the original `starting` phase. It retains every same-session token, original menu return, permission/SDK observation SHA, native process epoch, owned executable/UserDir, process birth and unique process match check. HUD/native code, focus-loss release and permission schema are unchanged.

The three existing synthetic source cases cover valid promotion/starting/running stages, stopped-session rejection, wrong UserDir/stale birth/ambiguous process rejection, and the unchanged Swift focus selector. No Game or HUD application is executed. Real private diagnostics remain outside public source.

Apply through the original managed update transaction and normal owned launch path. A running HUD child has already received its environment, so this source file alone does not change its current process environment.
