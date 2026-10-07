# Final late game save observation

A completed normal save can be followed by another real game-written `Level.sav` before a failed return to the title screen. The earlier crash finalizer rejected this changed file correctly. This increment preserves the original completed save witness and adds a separate `final_post_exit_level_witness`; it does not rewrite the earlier witness or mark the failed exit as normal.

The original save ID, native process scope, durable save observations, waited actor exits, quiet Saved/WAL checks and free ports remain required. The extra observation accepts only a later game file predating the unique same-process crash report and original host exit record. Crash-report file time is not claimed to be the exact fault time. The standard Palworld save codec reparses the actual final file read only and verifies the original standalone player UID. A file modified after the crash boundary or a failed parse is rejected. Normal exit-0 finalization is unchanged.

Run the three isolated source checks with `python3 -B checks/check_late.py`. Native, save and crash data are synthetic; only the test codec subprocess is mocked. The production source invokes the real standard codec.

For the complete original CLI, use `python3 -B run_frozen_cli.py --tool-source "<complete original player tools>" finalize-saved-crash --root "<owned root>"`. The `PALCRAFT_LATE_LEVEL_CODEC_PROOF` environment variable must identify an actual read-only codec observation for that same completed save and final file. It is not a ready flag, a replacement save, or permission to use a different world.

On 2026-10-07 this source was used once in the isolated Mac test installation after the original finalizer had rejected the late save. Actual final-codec parsing, crash-off receipt issuance and the subsequent normal managed update succeeded, while the original exit-3 and unfinished title transition remained recorded. The private saves, receipts, paths and identities are excluded. This recovery success does not prove normal title exit or complete gameplay, and the increment is not yet integrated into the ordinary candidate-19 package.
