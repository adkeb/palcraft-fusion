# Explicit standard save-codec interpreter

The normal late-save finalizer can use an existing Python environment that has the standard save codec dependencies. The default remains the current CLI interpreter; no software is installed automatically.

```sh
python3 PalCraft-Dev/player-tools/launcher/palcraft.py finalize-stop \
  --root /path/to/PalCraft --codec-python /path/to/existing/python
```

The selected interpreter must have the dependencies recorded in `PalCraft-Dev/mcp/requirements-runtime.txt`, including `pyooz==0.0.8` (imported as `ooz`). Missing dependencies produce an error and an action message. The finalizer still reads the owned Level and Player, checks the original UID and preserves the original normal-save witness. It does not write saves or change their ownership.

Three bounded synthetic function cases cover the dependency error, the explicit interpreter path and wrong-UID rejection; the CLI parser was also checked. The doctor output gives static guidance and explicitly records that no dependency probe ran. This source increment has not been installed in the running game and does not prove a complete fresh player installation.

Only the journal and CLI production sources change. The included `base/installer/core.py` is an unchanged fixture dependency.
