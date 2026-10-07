# Saved crash off recovery

This source adds a distinct `finalize-saved-crash` entry to the original player CLI. It accepts a failed `CLIENT_EXIT` boot only after the original save request completed, every original actor has an actual wait record and is absent, the host reports the same nonzero client exit with an empty job, backend ports are free, and the original Saved/WAL/stat/SHA/event-stream witness remains stable. It does not request another save or stop.

The receipt is `palcraft-owned-saved-crash-off-v1` in the same boot directory as `saved-crash-off-receipt.json`. It retains the failed phase and actual exit code, copies the original host observation exactly, and states `normal_title_Quit_and_native_exit0=false`. The normal finalizer still requires its original Title/Quit/exit-0 proof and writes its original normal receipt.

An original managed update may use that distinct same-boot receipt to adopt only the three existing normal generated data files. All other code, binary and data conflict checks remain. Cold boot selects only an already issued crash receipt and passes it to the unchanged original named-receipt event rotator. Saved/WAL files are preserved; the ordinary event journal is archived.

For review, the overlay can run the original complete player CLI without editing installed source:

```sh
python3 -B run_frozen_cli.py --tool-source "<complete original player tools>" finalize-saved-crash --root "<owned root>"
python3 -B run_frozen_cli.py --tool-source "<complete original player tools>" update --root "<owned root>" --bundle "<approved new release>"
```

The runtime owner executes these after source approval. The usual cold boot/full enrollment then follows. No completed normal-exit claim or phase/hash repair is used.

Run the four bounded source checks:

```sh
python3 -B checks/check_saved_crash.py
```

All native, save, WAL and world identities in these tests are synthetic. The tests create and wait their own short Python children, including a real exit-3 child, and never run Game/SDK/GUI/RPC or read actual saves or credentials. Dependencies are frozen normal tool sources solely for these temporary fixtures. Actual diagnostic records and the private handoff are excluded from public source.
