# Actual entity capture: render hook, authenticated cache and native reader

This is a source increment for the integration-owned next candidate. Frozen 9.2, the running guest and production are untouched. The old capture-hook-v1 snapshot is preserved.

## Install in the next MC staging tree

Run `python3 apply_capture_hook.py NEXT_MC_STAGING_ROOT` from this frozen increment. It installs four Java sources and connects:

- `PassthroughClient` initialization and disconnect cleanup.
- `LevelRenderer.render` TAIL to `EntityCaptureExporter.frame`, using the real `CameraRenderState`.
- `GameRenderer.onResourceManagerReload` TAIL to texture and pose invalidation.
- Existing `HostLink.execute` / connection lease / MC epoch to `entity_visual_view` binding, and existing `respond` transport to outgoing packets.
- The existing `world.read` permission to this derived read-only operation.

The real MC 26.3 JAR contains the render target and the reload target `onResourceManagerReload(ResourceManager): void`. Combined Java/Mixin compilation is pending with integration; this branch has not built a second guest or run a graphical client.

## Capture and pose updates

The accepted `ClientBridge.trustedWorldView()` tuple gates binding. Bounds and mapping come from the native committed view. Loaded entities in those bounds are sampled on the existing render thread, at most two per frame and 64 retained near entities, with a 100 ms minimum interval. No FPS cap is changed.

The actual dispatcher renderer produces its real render state; the original renderer submits models/custom geometry and the original model emits vertices. XYZ, normal, UV and RGBA are retained. Orientation is baked relative to the MC entity origin, so the native visual uses yaw zero. Each frame has `id=mc:<UUID>`, dimension, `captured_ms`, and a unique `seq=producer:epoch:sequence` consumed by the native update callback. Resource reload clears both textures and retained captures and advances the capture epoch.

Unsupported item/block/text/shadow/leash/flame/particle submission paths remain explicit diagnostics. Missing generated atlas, dynamic skin or static PNG resources retain their precise resource IDs and cause unavailable rows. The actual Creeper/Dragon capture proof is reused, not rerun or enlarged.

## Existing authenticated transport

Every outgoing packet uses the same existing HostLink response and host session. This introduces no login, service or world authority.

- `entity_visual_asset`: original PNG bytes, SHA256, resource ID, byte count, chunk index/count and base64, plus the committed view fence.
- `entity_visual_cache`: complete replacement of captured rows, with texture hashes, availability, pending count and budget-skipped count.
- `entity_visual_cache_chunk`: the UTF-8 JSON manifest when it exceeds 48 KiB, split into 48 KiB raw pieces with a whole-payload SHA256 and byte count.

PNG and manifest bounds are each 8 MiB, at most 171 pieces. A larger manifest emits an explicit unavailable replacement with `entity_visual_cache_byte_budget_exceeded` and `required_bytes`; it never presents a cropped manifest as a successful complete snapshot. The complete snapshot still incurs serialization/transfer costs; this is not a claim of a high-density scene performance result.

`host_session` is added by `respond` to each outer packet. It is therefore absent from the serialized inner manifest. The cache verifies the existing outer host session and view, checks the inner type/view/producer/epoch and payload SHA256, then inherits that outer session before accepting the decoded manifest. No alternate authentication token is created.

## Native composition

`lua/capture_runtime_binding.lua` creates the actual `entity_capture_cache`, configures `captured_entity_visuals` to resolve verified local PNGs, and constructs the native owner's `captured_native_consumer` with real `read_visual` and `verify_visual` callbacks.

Runtime supplies `json`, an existing PNG directory, `current_view`, the existing host-session verifier, `verify_actor`, `send_binding`, `models` version 6, `native_consumer`, `material_supported`, `origin` and `context`.

- Send the three derived packet types from the existing event dispatcher to `binding.receive(message)`.
- Call `binding.tick()` in the existing loop to bind the committed view.
- Use `binding.renderer` with the existing exact-Actor entity observer.
- Call `binding.stop()` with the existing lifecycle; it releases the renderer and clears pending cache assemblies.

The existing native observer retains Actor authority, AI, collision and damage. The displayed vertices require the native 72-byte RGBA format. Dynamic/atlas export and material blending/eyes acceptance remain owned dependencies; unavailable dependencies are not described as completed visuals.

## Verification and handoff

The one small cache fixture verifies the existing host/view, PNG hash and disk cache, direct and two-piece manifest paths, exact entity/Actor callbacks, and rejection of a different host. SHA256 uses the empty and `abc` known vectors. It does not launch MC, Palworld or a GPU scene.

The installer is applied only to a private source fixture. Integration performs the one combined compile from this immutable manifest. Actual in-game rendering remains unverified until the lead-controlled runtime window. The final source root and file hashes are in `READY-capture-hook-v2.json`; this source pack contains no vanilla textures.
