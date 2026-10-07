# Optional normal Wine loader trace

Set `PALCRAFT_WINE_TRACE=loader` on the original normal launcher invocation after installing this source through the managed update.

```sh
PALCRAFT_WINE_TRACE=loader python3 -B "<new outer player tools>/launcher/palcraft.py" start --root "<owned root>" --boot-singleplayer
```

The original start Popen inherits caller environment, and the supervisor copies it into the normal client helper Popen. Helper `run` resolves the mode once. Its normal raw menu producer then supplies the vendor Wine options `--cx-log <owned root>/.palcraft/logs/client-loader-<current boot token>.log` and `--debugmsg -all,err+all,trace+loaddll,trace+module`.

Logging is explicit in the persisted raw Command; it does not depend on `CX_LOG` environment reaching a native controller. The original link bytes/host arguments, owner, bottle, macdrv loader and native App identity are preserved. With no flag, the original command/spec/native environment are unchanged. Readonly planner calls do not inspect global environment. Other modes are rejected.

The loader log is private runtime evidence and is not a public-source artifact. This source bundle has not started Game, registered a menu, changed an installed manifest or captured a real trace. An exit code alone does not establish a missing DLL.

Run the three pure source cases with `python3 -B checks/check_loader_trace.py`. All input paths/tokens are synthetic temporary fixtures; no vendor API or child process is invoked.
