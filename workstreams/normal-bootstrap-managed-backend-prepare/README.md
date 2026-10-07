# Managed backend preparation during original bootstrap

The ordinary standalone backend producer previously required every component to be off, even when only its own original game bootstrap was running and no Minecraft or HUD backend had started. This increment permits the existing `prepare_backend` operation during that exact sole-client bootstrap, after verifying the original supervisor/client identities and unused backend ports. Other modes retain the original no-session rule.

The original three-file hash preflight, pending-copy replacements and generated backend ownership record remain in use. First-generation copies predating `backend-files.json` are accepted only when all three have exactly the old unique Minecraft-mod bytes proven by this installation's committed update, unchanged backed-up mod and matching backend profile. Foreign files and live backend components are rejected before replacement.

Run four isolated source cases with `python3 -B checks/check_prepare.py`. Temporary file operations use synthetic process and port responses; no game, actual save or credential is accessed.

The original producer can be reviewed through `python3 -B run_frozen_backend.py --tool-source "<complete original player tools>" prepare-backend --root "<owned root>"`. It uses the original complete launcher with only this frozen module overlaid.

On 2026-10-07 the second revision completed the actual three-copy Minecraft-mod upgrade through the original producer in the isolated Mac installation. The unchanged supervisor then started its normal six roles and the initial world ACK completed naturally. The earlier missing-record rejection remains a failed attempt; no manifest or file hash was manually repaired. Private process receipts, identity and paths are excluded. This increment is not yet integrated into the ordinary installer and does not imply complete game acceptance.
