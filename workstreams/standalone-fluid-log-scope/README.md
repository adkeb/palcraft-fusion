# Generate the existing standalone fluid client log field

The enabled standalone fluid consumer requires `PalCraftStandaloneBootstrap.scope.client_log_windows`. It opens that log to find the current ProcessEvent address. The correct log belongs to the private game client: `PalCraft-Client/Pal/Binaries/Win64/ue4ss/UE4SS.log`. It must be mapped from this profile's existing Windows root, rather than the BridgeLab server log.

This delta changes only `installer/standalone.py`: one assignment in `generated_files` and the same assignment in the existing `enrollment_profile` scope writer. The first ensures normal installation/update/configuration produces the dependency. The second lets the already authorized ordinary enrollment-profile entry backfill an older scope while retaining all its fields. The original issuer and normal-load permission checks, DLL path, fluid flags, scope assertions, authority, identities, role arguments, worlds and ledgers are unchanged.

The boundary check compares every generated file before and after: only this field differs. It exercises the original enrollment writer with a synthetic mocked issuer, preserves existing scope/config fields, and confirms the original permission-world mismatch still rejects before any writes. Unicode and spaces in the owned root map to the private client log. No actual credentials, games, GUI, RPC or installed files are read or modified by the check.

```sh
nice -n 19 python3 -B checks/check_scope_and_enrollment.py --base PLAYER_TOOLS_SOURCE --player-overlay CANDIDATE11_PLAYER_SOURCE
```

The regular application entry is the revised release's original launcher:

```sh
python3 REVISED_RELEASE/PalCraft-Player/launcher/install_standalone.py enrollment-profile --root OWNED_ROOT --guest-manifest CURRENT_ISSUER_GUEST_MANIFEST --output NORMAL_ENROLLED_PROFILE_OUTPUT
```

Run that only through the existing authorized enrollment workflow, with its actual issuer and native normal-load observation. Use the revised outer tools so they import this source; invoking the old installed module still uses its old writer. This is not another standalone transition or a manual scope/state/hash edit. The source task does not execute enrollment or install any code.

Writing the field does not prove that the current Lua VM adopted it. `standalone_bootstrap.new` reads scope once and its SP/permission objects retain that table; the existing tick shown in this source has no scope reread. A regular enrollment write can update the disk file without terminating the game, but the original normal Lua lifecycle must load that file before the consumer can use it. This delta adds no reload mechanism and makes no claim that an existing in-memory scope changes immediately. The sole runtime owner validates that normal lifecycle or the next normal boot.
