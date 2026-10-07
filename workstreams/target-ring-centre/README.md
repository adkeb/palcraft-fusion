The target-ring request uses the authoritative required bounds instead of the MC avatar's previous position. MC accepts the region only from the matching Pal prepare that passed the original player/world binding check, then uses its existing loaded-only 16×16 snapshot queue. The default player-centered request and the 64 radius / 512 jobs / 4096 cells / 256 operations budgets are unchanged.

The reviewed change is four source files and two managed payloads: one client Lua file plus one MC10.9 JAR. Three Java units were incrementally compiled over the exact MC10.7 F35 base. Nine classes were regenerated; Snapshot.class is byte-identical. Nine archive entries changed bytes, while all other 163 entry bytes and their order were preserved. Three recorded source cases passed. The 129×48×129 fixture produces 81 disjoint tiles and 798,768 cells. These results do not establish actual scene coverage, collision, ACK or FPS.

This source package includes the complete 118-member MC10.9 source ZIP, both build recipes, the compile-only interface helper source, and the exact three-unit builder used for the recorded build. It includes no vendor game binary, dependency JAR, wrapper JAR, compile overlay binary, private installation, Save data, credential, runtime log or session/pose capture. The release owner supplies the experimental mod JAR separately.

Rebuild using your legally obtained exact F35 mod, JDK 25.0.4.1, Minecraft 26.3 runtime dependencies and Fabric API 0.161.0+26.3. From a fresh extracted bundle directory, recreate the F35 source inventory by extracting the complete candidate source ZIP and restoring the three bundled baseline files. Javac compiles only the three candidate Java units:

```sh
unzip build/mc10_9/source.zip -d build/mc10_7/source
cp base/mc/src/main/java/dev/rehan/passthrough/*.java build/mc10_7/source/src/main/java/dev/rehan/passthrough/
nice -n 19 python3 build_mc_delta.py \
  --delta-root . --freeze build/mc10_7 \
  --base-mod /path/to/legal-F35-mod.jar \
  --jdk-home /path/to/jdk-25.0.4.1 \
  --runtime-root /path/to/legal-MC-runtime-root \
  --fabric-api /path/to/fabric-api-0.161.0+26.3.jar
```

The runtime root supplies the relative client/versions and client/libraries entries in build/mc10_7/build-recipe.json. Embedded dependencies come from the user's F35/Fabric API inputs. The builder keeps helpers outside the runtime mod and emits an output recipe and receipt. The recorded JDK/dependency environment is required for the recorded class pins and binary hash.

- Expected F35 SHA256: `f35ebc90cfa2f77c81b7f9f02d7ea721bffc21166bc63ff36159825bd0170b55`.
- Expected MC10.9 JAR SHA256: `fbbf30937a85f7f8d879520de9ce663fc87b031a6a94d3110fe38bb1294cf53c` (552,399 bytes).

Replay the recorded source checks independently with Lua 5.4 and the user's legal F35/Gson inputs. The Lua command slot is confined to scratch. Java uses copied production method bodies with fixture server/player/chunk/queue endpoints and the unchanged TravelAckValidator from F35:

```sh
mkdir -p scratch scratch/classes
lua checks/check_request.lua . scratch
/path/to/jdk-25.0.4.1/bin/javac --release 25 -proc:none \
  -classpath /path/to/gson-2.14.0.jar:/path/to/legal-F35-mod.jar \
  -d scratch/classes checks/TargetRingChecks.java
/path/to/jdk-25.0.4.1/bin/java -Xmx128m \
  -classpath scratch/classes:/path/to/gson-2.14.0.jar:/path/to/legal-F35-mod.jar TargetRingChecks
```

All fixtures use synthetic identities and illustrative local coordinates. Publication did not rerun the checks or compiler. manifest.json records the exact production source hashes, nested source inventory and publication allowlist.
