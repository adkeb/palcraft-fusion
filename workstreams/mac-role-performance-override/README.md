# Explicit Mac guest/HUD performance override

The original `prepare_launch.py` accepts optional `--performance-override selected-values.json`. The JSON contains exactly `mc_fps` and `hud_fps`; their integer ranges match the original performance contract: MC 1..60 and HUD 1..120.

Example selected policy data: `{"mc_fps":60,"hud_fps":30}` for day, or `{"mc_fps":10,"hud_fps":10}` for night. The caller chooses the user's policy data. This generator contains no clock, schedule, author path or global performance policy.

Invoke the original file-only producer with `python3 -B source/mac/scripts/prepare_launch.py --config /path/to/original/config.json --performance-override /path/to/selected-values.json`. It changes only the existing guest `-Dpalcraft.maxFps=` value and HUD `--fps` value. It does not rewrite the preserved template or config, and preserves all other arguments, paths, identity, feature flags, scopes and original role metadata behavior. Both FPS positions must be unique before any role files are published.

Without the optional flag, output bytes and arguments are equal to the original producer. The override applies to that preparation invocation; it does not persist policy into the config or template. The producer does not start, stop, signal or tune a live process. The sole runtime owner selects the appropriate normal lifecycle for its own guest/HUD; PalWorld and the shared MC server are not controlled by this source change.

Three bounded checks passed. Run `python3 -B checks/verify_performance_override.py` in a writable copy for the same file-only synthetic suite. It checks default byte equality, only-two-value day/night changes, the unchanged Mac DTO 2089 FPS/identity/port/frame guard against actual temporary producer outputs, and invalid/ambiguous overrides before publication. Test dependencies are unchanged source snapshots. The existing credential fixture is synthetic; no real credential, UID, SID, key, grant, role witness or game data was read, generated or published. No original 12-check suite was rerun.
