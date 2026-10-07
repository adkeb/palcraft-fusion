# Mac local public guest manifest source

This source-only bundle adds explicit `--platform mac-local` to the existing guest planner. Windows defaults are preserved. The planner reads an original issuer-issued v2 credential; it never creates or signs an identity, credential, key, UID, or SID and never starts a process.

Mac mode requires explicit POSIX backend and data roots, an existing public guest/HUD role directory, and assigned MC WS/HUD ports. The role arguments are configuration witnesses. Identity, session and expiry come from the issuer credential grant; the original MC authority verifies signatures before entry.

Run `python3 -B source/multiplayer/prepare_guest.py --help` for the normal file-only CLI. For local use add `--platform mac-local --remote-root /path/to/backend --mac-data-root /path/to/data --mac-launch-dir /path/to/public/roles`, along with the original credential, new output, allocations, assigned ports and the FPS already used by those roles.

The portable bounded checker is `python3 -B checks/verify_mac_guest.py`. It reads only this bundle's `source`, `base`, `consumer`, and `checks/fixtures` paths and temporary directories. The credential and public vector in `checks/fixtures` are explicitly synthetic, pre-existing test fixtures. Their fixed test keys and grant do not represent a real user, server, world or session. No real credential was copied into this bundle; no new key or grant was generated.

`consumer/credentials.py` is an unchanged source snapshot used only for the schema test. The checker exercises its original inspection and guest-profile preparation functions with file-reading/error stubs, not the real profile validator, installed state, or credential-import writes. It makes no local signature-verification or gameplay claim.

The original 12 bounded source checks passed. The portable checker prints its fresh receipt to stdout and leaves the recorded verification file unchanged, so it also works from a read-only source tree. Only that final receipt-write line was removed; all check function logic and production source bytes remain identical. The unchanged check functions were not rerun for this packaging adjustment.
