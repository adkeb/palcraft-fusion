# Ordinary update retains the original generated launch template

The standalone transition creates `PalCraft-Dev/player-tools/standalone/previous-launch-plan.json` as managed generated data. A later ordinary release update previously omitted that target from its desired files and deleted it, while the profile continued to reference it. `prepare_launch` then failed before creating normal role arguments.

This one-file repair retains the referenced template through the existing `_apply` transaction. An existing template must match its managed SHA. A missing template is accepted only from a committed deletion journal for the same owned installation, persistent identity and backend, with a matching original managed SHA and verified `before` backup. Its server, guest and HUD scope must match the current profile. Missing, altered, conflicting or unrelated evidence is rejected; no argv is reconstructed. Recovery runs through the original generated staging, pending replace, state ledger and transaction undo.

The original transition, prepare_launch, launcher hash guard, enrollment, native Host control, world save and job shutdown paths are unchanged. Publish the updated installer as a new ordinary release version; retain its outer installer and inner managed installer source as the same version. Deployment must wait for the existing ordinary save/off boundary. Execute that update with the **new release's frozen outer launcher/installer**, which imports the new `installer/core.py` before applying the inner bundle:

```sh
python3 NEW_RELEASE/PalCraft-Player/launcher/palcraft.py update --root OWNED_ROOT --bundle NEW_RELEASE/PalCraft-Player/release.zip
```

Invoking update from the old installed launcher loads the old `_apply`; replacing its module on disk during that call does not replace the already imported implementation, so that first call alone cannot restore the template. If that old entry was used, finish its ordinary update, then invoke the newly installed original `configure --root OWNED_ROOT --profile CURRENT_PROFILE_JSON` once with the same existing profile. This is ordinary configure, not another standalone transition. Do not copy a module over installed code or edit state/files/ledger manually. This source delta has not been installed or verified in a game.

The directed check reuses the original temporary player installer fixture and calls actual Bundle/install/configuration/update/rollback/prepare_launch modules. It proves the old deletion, verified archive recovery, later retention, fault undo, unchanged role argv/UUID, and refusal of corrupt backups, changed current files and active sessions. Existing Saved, world, inventory and WAL sentinels retain bytes and modification times. No processes or games run. Private fixture setup errors and actual-install observations are evidence only and are excluded from the public source bundle.

Run from this delta after supplying the existing source tree and fixture paths:

```sh
nice -n 19 python3 -B checks/check_template_continuity.py --base PLAYER_TOOLS_SOURCE --overlay CANDIDATE10_SOURCE_OVERLAY --fixture ORIGINAL_TEST_PLAYER_TOOLS_PY
```

The check uses synthetic fixture identities and game files. It is not a native-world, current-frame or complete gameplay acceptance test.
