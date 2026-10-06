# Original entity shader inputs

Independent source increment after sealed 10.1. This supplies original inputs;
it does not claim that native UV1/UV2, lighting or overlay shaders are accepted.

## MC source and original values

`VanillaEntityCapture` keeps the first 12 XYZ/normal/UV0/RGBA values unchanged and appends `uv1_u, uv1_v, uv2_u, uv2_v`. They come from the original `VertexConsumer.setUv1/setUv2` calls, including MC's actual default packed `setOverlay/setLight` methods. Batch `uv1_written_vertices/uv2_written_vertices` distinguish missing attributes from an actual zero. Packed batch light/overlay remain diagnostics, not substituted per-vertex UVs.

Material owner supplies `CaptureBlendMetadata.read(type.pipeline())` and `capture_blend_route.lua`. Its original blend/coverage/defines helper is reused unchanged. The merged Lua provider no longer infers additive blending from the word `eyes`.

Four new Mixins observe original inputs without changing vanilla's writes:

- `Lighting.updateBuffer` copies the actual two input vectors; `setupFor` records the selected entry.
- `DynamicGpuData.writeTransform(Transform)` and its bulk counterpart copy actual ColorModulator, ModelOffset and TextureMat keyed by the returned original UBO slice.
- `RenderType.writeDynamicTransforms` maps that slice to the actual render type. Each captured batch carries its observed `shader_inputs`. A type not observed in the current render frame is explicitly unavailable; no guessed WHITE modulator or light directions are inserted.
- An accessor reads `OverlayTexture`'s actual `DynamicTexture` CPU pixels.

Sampler1 PNG comes from those original overlay pixels. Sampler2 uses the actual active `GameRenderer.lightmap()` also used by `RenderType.prepare`, through a two-method public wrapper around the existing sign module's `readTexture` and lightmap revision. The original GPU copy/callback/buffer close implementation is reused. No extra executor, service or event reader is created.

Each PNG has immutable content-addressed resource ID, SHA256, dimensions, original source, revision, capture epoch and capture time. Original row zero remains UV v=0. GPU lightmap RGBA bytes are encoded without recolouring or baking guessed brightness.

Pose, batch uniforms and texture-copy request come from the same capture frame. Its two entity rows share one original lightmap future. They publish after completion with the retained original pose. At most four pending rows are held; epoch/binding changes discard stale completions. No later-frame pose is relabelled with earlier lightmap pixels.

Existing `entity_visual_asset/cache/cache_chunk` packets, HostLink lease, host session, MC epoch, current tuple and ACK gate are retained. This source increment does not introduce world authority or visible submission gates.

## Native input interface

The pure Lua provider retains the existing eight-double mesh vertices and RGBA list, and adds:

- `overlay_uvs[i]={original UV1_u,UV1_v}` and `light_uvs[i]={original UV2_u,UV2_v}`.
- `mc_uv1_written_vertices` and `mc_uv2_written_vertices`.
- `mc_shader_textures.Sampler1/2`: original image descriptors.
- `mc_sampler_paths.Sampler1/2`: verified local cached PNG paths.
- `mc_shader_inputs.dynamic_transforms`: original per-type ColorModulator, ModelOffset, TextureMat and source frame, or explicit unavailable reason.
- `mc_shader_inputs.cardinal_lighting`: original selected Lighting entry and Light0/1 directions. Values use the original MC normal basis; native must transform vectors consistently with the existing MC-to-UE normals.
- `capture_blend`: the material owner's full original pipeline metadata.

Native6's current 72-byte RGBA+UV0 ABI does not consume the new UV/lighting/overlay inputs. Native owner decides the next real shader/vertex contract and provides actual game evidence. Shader texture sampling, Normal packing, fog, OIT and unsupported submission paths remain separate acceptance work.

## Install and verify

Run `apply_shader_inputs.py NEXT_MC_STAGING_ROOT` only in an independent integration staging tree based on sealed 10.1 (or that base plus the material owner's one metadata hunk). It guards the three existing source baselines, installs the new Java and registers four Mixins. The normal render-tail hook and transport stay in place. Merge the Lua files only into the next native candidate.

Only a tiny provider passthrough fixture is run here. `CaptureUvOracle.java` is a data-only check of actual MC default packed UV calls and can run once after the integration-owned necessary compile. There is no extra MC game instance or expanded renderer matrix. Source API/combined compile and original runtime pixel/hook receipts are recorded separately; graphics are not reported accepted from this source pack.
