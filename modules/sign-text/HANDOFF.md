# Sign text candidate v1 — MC26.3 actual glyphs to native world planes

Source is complete for the independent exporter/consumer/adapter and the authenticated cross-machine glyph stream. Final Java is frozen for next9 assembly. It is not enabled in the running candidate or production. Pal asset existence, shader sampling, no WPO, alpha appearance, and the v5 DLL remain engine-unverified. Production stays OFF.

## What is implemented

- Actual `AbstractSignRenderer` Font via a read-only accessor; the real renderer extracts standing/wall/hanging sign front/back matrices, line height, width, filtered text, outline visibility and light coordinates.
- Exact MC26.3 `Font.split` first line and integer `-width/2` centring, actual `prepareText`/`prepare8xTextOutline` glyph/effect vertices and UVs. Bold, italic, underline, strikethrough, glyph provider choice, CJK/bidi, styled colours, filtering and obfuscation follow the active vanilla Font.
- Asynchronous reads of used Font atlas regions and the actual current 16×16 lightmap. CPU raster follows MC nearest sampling, `IS_GRAYSCALE .rrrr`, vertex colour, packed light UV, 0.1 discard and source-over alpha. The output is straight-alpha PNG; nonbinary alpha requests the translucent candidate parent rather than silently cutting off the glyph edges.
- Four-vertex planes per side transformed by those exact column-major matrices, with MC `(x,y,z)` mapped to native `(100x,-100z,100y)`. A 0.04 font-pixel surface bias substitutes the original polygon-offset draw mode. Canvas expands for resource-pack glyph extents while retaining topology. The renderer never lays out text or substitutes a host font.
- Live edits/dye/glow/lighting change textures on the same actor, component and MID objects. Changed orientation/canvas uses `models.update_groups(actor,groups)`; no text edit recreates the sign or sends a sign edit packet. Original sign geometry continues to belong to the ordinary block renderer.
- Trusted world/view/player/mapping fences, source epoch/sequence, duplicate/path/size checks, committed native block lookup, complete replacements, removal, chunk unload, producer timeout, world reset and invalid-context native release.

The CPU image represents the original glyph shader before camera fog and host postprocessing. Native scene acceptance is still required. No original game asset is bundled; only private runtime text images are created from the user's installed MC resources. Do not publish/package generated PNGs, font atlases, or research copies of game bytecode.

## Files and source-only verification

New client Java classes are under `palcraft/mc/src/client/java/dev/rehan/passthrough/client/signtext/` and three independent mixins under `client/mixin/Sign*.java`. New Lua modules are `sign-text/lua/{geometry,materials,native,consumer,scene}.lua`.

- Six pre-transport Java sources compiled against the installed actual MC26.3 jar and cached Fabric/Mixin dependencies using JDK25, `javac -proc:none`, one processor, BelowNormal and 256MiB; no game start. The final one-file `setTransport`/stream delta is frozen at SHA `7f54b90d9b15e5f18792eebf432ce8e42541e133bd280308c54417f1e64047d4`.
- The lead confirmed the actual integration build `integration-build/snapshots/coherent-9-f74fed4a87ce`: `Gradle clean assemble + targeted`, exit0, 2026-10-05T19:52:00Z–19:52:46Z. Its frozen source contains that exact final Exporter. Artifact `passthrough-0.2.0-integration.9.jar` is528500 bytes, SHA `f91546bd4ea05aaa94b608833d8df440fdfa745a500563bc52737c30122e1db8`. This proves final source compilation/assembly; it does not prove runtime mixin application, WS delivery, native materials, v5 updates or actual visuals. The earlier narrow log remains only the pre-transport baseline. Build evidence was supplied by the lead; this source worker did not rerun the build.
- `tests/SignGlyphRasterTest.java`: pure CPU shader sampling, diagonal alpha, RGBA atlas orientation, vanilla discard threshold, outline order, actual packed light UV and empty surfaces.
- `tests/consumer_test.lua`: all 40 existing vanilla front/back layouts' winding/centres; edits retain actor/two MIDs; orientation calls fixed-topology update; stale/cross-view/unsafe path/duplicate rejection; destroyed or uncommitted blocks cannot float text; unload/producer epoch/timeout cleanup; bounded material references. Mocks remain explicitly unverified.
- `tests/receiver_test.py`: PNG before snapshot, sequential chunk assembly, SHA/PNG CRC/dimensions, native world/mapping/player fence, producer epoch, corrupt-cache rejection, immutable PNG reuse, same-request bounded retry and unbind. This is a data-only transport test and starts no network process.

Logs/manifest are under this directory and `coordination/sign_text_visuals.json`. No existing large tests or game/GUI/RPC/service/deploy action was performed.

## MC integration owner — minimal additions

Add these names to the **client** list in `passthrough.client.mixins.json`:

```json
"SignFontAccessor",
"SignTextGameRendererMixin",
"SignLightmapReadbackMixin"
```

`SignTextGameRendererMixin` is a separate `renderLevel` TAIL hook, so the owned HUD `GameRendererMixin` and FrameExporter need no edit. `SignLightmapReadbackMixin` adds only COPY_SRC permission to the original lightmap constructor and observes its actual needsUpdate flag. Resource reload invalidation uses the same separate GameRenderer mixin.

In `PassthroughClient.onInitializeClient()` add:

```java
dev.rehan.passthrough.client.signtext.SignTextExporter.initialize();
```

No inferred world origin exists in the exporter. Bind only from an existing authenticated, already applied WorldView. A caller which already receives native scope can call:

```java
SignTextExporter.bind(worldSession, dimension, view, nativeMappingId, exclusiveMcBounds);
```

Otherwise this narrow read-only transport uses the **existing** authenticated host session, not a new handshake:

```java
// SessionPolicy.scope switch:
case "sign_text_view" -> "world.read";

// HostLink.dispatch switch, using the existing lease/MC-epoch execute helper:
case "sign_text_view" -> execute(conn, lease, () -> {
    ClientBridge.bindSignText(m);
    dev.rehan.passthrough.client.signtext.SignTextExporter.setTransport(row -> respond(conn, lease, row));
});

// ClientBridge, whose existing WorldView is authoritative:
static void bindSignText(JsonObject request) {
    WorldView current = worldView;
    if (current == null) throw new IllegalArgumentException("authenticated world view unavailable");
    dev.rehan.passthrough.client.signtext.SignTextExporter.bindRequest(
        request, current.session(), current.dimension(), current.generation(), !current.waitingAck());
}
```

`bindRequest` checks the current MC player UUID and accepted session/dimension/view; only then reads native mapping ID and exclusive bounds. The transport setter must follow that successful check. On WorldView replacement/prepare and current host detach, call `SignTextExporter.unbind()` alongside the existing input/view release; on current host detach also clear `setTransport(null)`. MC disconnect already unbinds through the initializer. Optionally include `SignTextExporter.status()` in the existing inspection reply.

Per-player `-Dpalcraft.signTextDir=<private 5090 dir>` can override `<palcraft.bridgeDir>/sign-text-v1`. The MC-side cache and Mac-side receiver cache are separate private directories. The actual WS stream below transfers images automatically; no shared-directory assumption or manual SCP is needed. Exported `snapshot.json` carries no executable/click commands and no rewritten text.

## Installer/proxy owner — actual cross-machine transfer

`sign-text/python/receiver.py` is the completed stdlib-only receiver. Package it as a frozen executable role and load it inside the existing unique authenticated session proxy. It owns no socket/process/thread/timer or generic resource endpoint.

```python
receiver = SignTextReceiver(status_path.parent / 'sign-text-v1', public['identity'])

# Existing to_guest/native loop, after its ordinary operation whitelist:
if message.get('t') == 'sign_text_view':
    receiver.bind(message)       # same genuine native request, with scene provenance
await send_scoped(message)       # existing lease.stamp + existing WS

# Existing to_native/upstream loop:
clean = lease.receive(message)  # existing host_session validation always comes first
if receiver.receive(clean):
    retry = receiver.retry_request()
    if retry is not None:
        await send_scoped(retry) # same original request; don't receiver.bind it again
    continue                    # glyph blobs are not forwarded to the native input parser
mirror_event(clean, lease)
await native.send(json.dumps(clean, separators=(',', ':')))

# Existing finally/host-generation cleanup:
receiver.close()
```

Add `sign_text_view` to the existing local proxy player-operation whitelist; its MC scope remains existing `world.read`. `receiver.bind(request)` accepts the exact native request already sent by `Consumer.binding_request`: mandatory `world_session`, `dim`, `view`, `mapping`, `mc_uuid`, `bounds`; `op=unbind` unbinds. The constructor checks the already-authenticated identity's MC UUID. The receiver never reconstructs an ACK/origin or invents another scene proof. Explicit `unbind()`, `reset()` and `close()` aliases clear pending transfers and the local snapshot. The normal native host feature reset releases actors; the consumer's5-second freshness timeout is an additional cleanup path.

The two exact wire types are `sign_text_asset` and `sign_text_snapshot`. Both carry `{schema=1,producer,epoch,seq,created_ms,world_session,dim,view,mapping,mc_uuid}`. Assets additionally carry `{sha256,bytes,offset,final,width,height,data}` where data is base64 for at most48KiB raw bytes (64KiB encoded). The sender sends every missing referenced PNG's chunks before the snapshot footer, whose `snapshot` is the original complete document. The existing HostLink response appends the existing `host_session` envelope. A new transport resets its sent-hash inventory so a reconnect resends actual required PNGs.

Receiver assembly uses one bounded `.receiving` file, exact chunk offsets/size, SHA-256, PNG signature/chunk CRC/IHDR dimensions, then atomically renames `textures/<sha>.png`. It publishes `snapshot.json` only after every referenced PNG is locally present and verified. A footer that arrives before an evicted file waits; `retry_request()` returns the same original native request at most1Hz, so the existing MC setter resends cached assets through the same channel. View/identity/old producer/epoch/sequence are fenced. Corrupt/malformed glyph messages set display status and are consumed without disconnecting the game's input transport. Unused images expire after a10-second grace.

## Native/material owners — exact v5 contract

Use the complete approved next v5 package, not partially compiled DLLs. Required existing calls:

```lua
models.spawn_groups(ctx,origin,groups,at,{hidden=true}) --> actor,component,native_id
models.update_groups(actor,groups)                     -- same topology/object
models.set_visible(actor,visible)
models.release_model(actor,context_alive)               -- false: release without actor dereference
```

Text groups set `text_plane=true`, `sign_key`, `side`, virtual `texture='palcraft:sign/<sha>'`, `image={path='textures/<sha>.png',sha256,width,height,scale,alpha_mode}`, `material_root`, `shade=false`, `tint=-1`, `texture_meta.baked_diffuse_tint=true`, `light_emission=0`. Glow and ordinary MC light are already baked; no native emissive override is needed.

Route text groups before the general block material provider:

```lua
local TextMaterials=dofile(sign_dir..'materials.lua')
local text_materials=TextMaterials.new{
 root=private_text_root,
 -- Enable only for the assigned scene probe. Production requires verified profiles.
 allow_candidate=true,
 profiles=probed_unlit_profiles,
 verified_profiles=actual_scene_proofs
}
models.set_material_provider(function(ctx,g,root)
 if g.text_plane then return text_materials:resolve(ctx,g)end
 return existing_block_provider(ctx,g,root)
end,existing_verified_capabilities)
local renderer=dofile(sign_dir..'native.lua').new{models=models,materials=text_materials}
```

`profiles` maps cutout/translucent to `{id,parent,parameter,blend}`. Defaults are Paper2D Masked/TranslucentUnlitSpriteMaterial **candidate** asset names. Loading/BlendMode/MaterialDomain/inherited SpriteTexture are checked; defaults do not prove actual visibility, no WPO, shader sampling or alpha. `allow_candidate` is an explicit lab probe gate. Supply a real proven surface/unlit/no-WPO parent if those assets are unavailable. There is no opaque/debug fallback. One text MID per side is reused; only a necessary cutout/translucent parent change creates a replacement MID on the same component.

Model/material caches use active references plus at most 32 unused textures; old `previous` chains are cleared. The native module creates both images/materials before showing a new actor, and stages both replacements before updating an old actor. Its component SetMaterial lookup is only needed when the compiled alpha profile changes. Reset the text worker before the ordinary model world's reset/abandon operation.

## General Overworld and travel providers

The consumer has no dependency on travel-enabled, travel tickets or a guessed authored coordinate. It accepts a current-scene provider from either owner:

```lua
local worker=dofile(sign_dir..'consumer.lua').new{
 json=J,root=private_text_root,renderer=renderer,
 send_binding=function(request)session.send(request)end, -- existing authenticated world.read sender
 block_at=function(dim,at)
  return current_authoritative_block(dim,at), current_native_sign_geometry_committed(dim,at)
 end,
 view_provider=function(ctx)
  return {fence={world_session=confirmed_world_session,dim=current_dimension,
                 view=confirmed_view,mapping=current_native_mapping_id,mc_uuid=bound_mc_uuid},
          origin=current_native_O,bounds=current_visible_exclusive_mc_bounds}
 end
}
-- Existing single game-thread callback, at most once per250ms:
worker:tick(ctx,context_alive)
```

The ordinary per-block Overworld adapter supplies its existing accepted WorldView, committed block registry, actual current `O`, mapping fence and visible/synchronized bounds. This works when `travel_enabled=false` and no ticket exists. The travel/chunk adapter supplies the active region's same values (`mapping.region_id`, actual `mapping.origin`, `required_bounds`) only after that region is committed. These are two providers of the same shape, not two protocols.

The ordinary path has a concrete adapter for the current companion fields, so the caller need not reconstruct its model proof:

```lua
local scene=dofile(sign_dir..'scene.lua').per_block{
 json=J,companion=function()return current_collision_companion end,
 confirmed_view=function(companion,ctx)
  -- Return the owner's already-confirmed player WorldView:
  -- {applied=true,world_session,dim,view,mc_uuid,mapping?}.
  return accepted_native_player_view
 end
}
-- Pass scene.block_at and scene.view_provider to Consumer.new above.
```

This adapter uses `companion.world:get`, `companion.actors[x:y:z].model/model_status/render_signature`, and the current renderer's exact render-signature fields; it does not wait for irrelevant NBT/container bookkeeping to re-create a body. Scope is the union of actual committed reducer snapshot receipts for that dimension/player, or the existing owner's `visible_bounds` callback. Origin is the actual `companion.origin`. If that normal per-block scene has no named mapping, its opaque mapping identifier is derived from that real transform; it is never an authored coordinate. A native owner may provide `model_live(actor,component)` for an additional engine-lifetime proof. A pending scene/player view returns no binding. Travel passes its own equivalent provider and does not use this receipt helper.

`block_at` must return the current block's exact exported `id`/`state` and `committed=true` only once its native sign geometry exists. The text module doesn't fabricate this proof. Origin/bounds must come from that same committed scene; a changed mapping must change its fence. To manually bind without a provider, use `worker:bind(fence,true)` and send `Consumer.binding_request(fence,bounds)` through the same session. On rejected/unloaded blocks call `worker:prune(context_alive)`; on native chunk retirement call `worker:unload_chunk(dim,cx,cz,context_alive)`; on host/world/context replacement call `worker:reset(reason,context_alive)`; on stop call `worker:stop(context_alive)`.

MC sampling is capped at 4Hz/16 signs per batch, 1024 signs/4096 existing-chunk probes, 32 used atlases per job and one low-priority CPU worker. Static atlas reads are reused until a new glyph UV region/font appears; dynamic sprite glyphs/obfuscation resample. Actual lightmap updates invalidate light dependencies. Content hashes avoid repeated PNG writes and texture/MID imports. Atomic snapshots heartbeat at 1Hz; late jobs fail their epoch fence. Unused PNGs expire after a 10-second grace, with deferred cleanup after unbind. CPU/noise performance is a source limit, not an in-game measurement.

## Remaining acceptance

The integration owner should assemble one next build with these mixin entries and callbacks plus the complete native v5/material candidate. Under the lead's single low-FPS graphics lease, inspect original front/back Chinese/Latin/styled signs and standing/wall/hanging rotations; edit, dye, glow, remove, unload and reconnect. Verify actor/component/MID identities remain stable for ordinary edits, no WPO/depth fighting, partial-alpha glyph edges, MC normal darkness versus glow, and no player/view leakage. Record scene/runtime evidence before marking the original model manifest's sign-text graphics capability verified.
