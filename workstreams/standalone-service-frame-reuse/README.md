This source delta removes repeated standalone escrow-service work from the existing client callback. It shares the original loaded-world realm and native process verifier, retaining the native player UID getter and the original process freshness checks. Independent service callers retain their existing path; injected verification failure does not fall back.

Apply both reviewed source files together against the baselines listed in manifest.json. Runtime targets are:

- client/runtime/standalone_bootstrap.lua → PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/runtime/standalone_bootstrap.lua
- server/standalone_service.lua → BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/standalone_service.lua

This is a source review package. It contains no game executable, private installation, Save data, credentials, native binaries or runtime logs.

The three recorded source cases passed: reuse without duplicate scans/native identity writes, injected realm/UID/process rejection without fallback, and independent-path compatibility. The fixture counts do not establish actual FPS or control latency. The recorded production source has not been changed or retested for this publication.

To replay the portable checker with Lua 5.4, run from this extracted bundle directory:

```sh
lua checks/check_service_reuse.lua .
```

The explicit directory argument resolves all code within this bundle. The four checks/deps Lua files preserve the original JSON/readers and tested realm/authority implementations. The checker uses synthetic world/process values and in-memory native/store fixtures; it does not load a DLL, send RPC, launch a game, or touch Save data. The portable copy is supplied for replay and was not executed again during packaging.

manifest.json contains the exact allowlist, source/baseline SHA256 values, and dependency hashes. Only those listed files belong to the publication archive.
