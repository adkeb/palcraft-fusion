package dev.rehan.passthrough.client.signtext;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.renderpearl.api.GpuFormat;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.textures.GpuTexture;
import com.mojang.renderpearl.api.textures.GpuTextureView;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.client.mixin.SignFontAccessor;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;
import javax.imageio.ImageIO;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.blockentity.state.SignRenderState;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.entity.SignBlockEntity;
import net.minecraft.world.level.block.entity.SignText;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.status.ChunkStatus;
import net.minecraft.world.phys.Vec3;

/** Local display-only bridge. No sign mutation, packet to edit a sign, command,
 * server scan, HUD drawing, or font substitution exists in this exporter.
 * Bind it only from the client's already-authenticated world/view lifecycle. */
public final class SignTextExporter {
    private static final String PRODUCER = UUID.randomUUID().toString();
    private static final Path ROOT = Path.of(System.getProperty("palcraft.signTextDir",
        System.getProperty("palcraft.bridgeDir", "D:/PalworldServer-LAN/PalCraft-Dev/bridge") + "/sign-text-v1"));
    private static final int MAX_SIGNS = 1024, MAX_SCAN_CHUNKS = 4096, BATCH = 16, SCALE = 4;
    private static final long SAMPLE_MILLIS = 250, HEARTBEAT_MILLIS = 1000;
    private static final Object PUBLICATION = new Object();
    private static final ScheduledExecutorService IO = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread t = new Thread(task, "PalCraft sign pixels"); t.setDaemon(true); t.setPriority(Thread.MIN_PRIORITY); return t;
    });
    private static final ConcurrentLinkedQueue<Completion> COMPLETED = new ConcurrentLinkedQueue<>();
    private static final Map<Long, Entry> ENTRIES = new HashMap<>();
    private static final IdentityHashMap<GpuTexture, CachedAtlas> ATLAS_CACHE = new IdentityHashMap<>();
    private static SignGlyphRaster.Atlas cachedLightmap;
    private static long lightmapRevision, cachedLightmapRevision = -1, fontRevision;
    private static volatile long epoch;
    private static Fence fence;
    private static int[] bounds;
    private static boolean initialized, busy;
    private static long busySince;
    private static long nextSample, nextPublish, sequence, captures, publications, dropped;
    private static volatile String error;
    private static String viewerUuid = "";
    private static volatile Transport transport;
    private static final int WIRE_CHUNK = 48 * 1024, WIRE_MAX_PNG = 16 * 1024 * 1024;
    private static final class Transport {
        final Consumer<JsonObject> send;
        final HashSet<String> sent = new HashSet<>(); // IO worker only
        Transport(Consumer<JsonObject> send) { this.send = send; }
    }

    private record Fence(String worldSession, String dimension, long view, String mapping) {}
    private static final class Entry {
        SignBlockEntity sign; JsonObject row; long capturedAt, lightRevision = -1, fontRevision = -1;
        Source signature; boolean obfuscated, dynamic;
    }
    private record Source(BlockState block, SignText front, SignText back, boolean outline, boolean filtered, int light) {}
    private record Pending(long position, Source signature, JsonObject row,
                           SignGlyphCapture.Surface front, SignGlyphCapture.Surface back) {}
    private record Completion(long epoch, long lightRevision, long fontRevision, List<Pending> pending, String error) {}
    private record Region(double u0, double v0, double u1, double v1) {}
    private record CachedAtlas(SignGlyphRaster.Atlas pixels, HashSet<Region> regions) {}

    private SignTextExporter() {}

    /** One initializer call from PassthroughClient. It registers cleanup only;
     * the separate render hook does bounded work while a view is bound. */
    public static void initialize() {
        if (initialized) return;
        initialized = true;
        ClientPlayConnectionEvents.DISCONNECT.register((handler, client) -> unbind());
    }

    /** Reuses the existing authenticated HostLink response channel. Call only
     * after bindRequest succeeds inside the existing lease/epoch execute helper:
     * setTransport(row -> respond(connection, lease, row)). A fresh transport
     * re-sends referenced immutable PNGs, so reconnect never assumes remote FS. */
    public static void setTransport(Consumer<JsonObject> sender) {
        transport = sender == null ? null : new Transport(sender);
        nextPublish = 0;
    }

    /** Native view's MC bounds are exclusive at max. Its mapping identifier must
     * equal the native scheduler fence; never infer a Pal origin here. */
    public static void bind(String worldSession, String dimension, long view, String mapping, int[] exclusiveBounds) {
        if (worldSession == null || worldSession.isBlank() || dimension == null || dimension.isBlank()
            || mapping == null || mapping.isBlank() || view < 0 || exclusiveBounds == null || exclusiveBounds.length != 6)
            throw new IllegalArgumentException("sign world/view binding");
        for (int i = 0; i < 3; i++) if (exclusiveBounds[i] >= exclusiveBounds[i + 3])
            throw new IllegalArgumentException("sign view bounds");
        Fence next = new Fence(worldSession, dimension, view, mapping);
        if (next.equals(fence) && Arrays.equals(exclusiveBounds, bounds)) return;
        synchronized (PUBLICATION) {
            if (next.equals(fence)) {
                // Moving/resizing the visible scope keeps this view's object
                // epoch and existing faces. The next scan retires only exits.
                bounds = exclusiveBounds.clone(); nextSample = 0; return;
            }
            epoch++; fence = next; bounds = exclusiveBounds.clone(); ENTRIES.clear();
            sequence = 0; nextSample = nextPublish = 0; error = null;
        }
    }

    /** Called only inside HostLink's existing authenticated/epoch-fenced execute
     * callback. Current authoritative WorldView is passed by ClientBridge,
     * rather than accepted from the host request itself. */
    public static void bindRequest(JsonObject request, String acceptedSession, String acceptedDimension,
                                   long acceptedView, boolean applied) {
        Minecraft mc = Minecraft.getInstance();
        if (!applied || mc.player == null || !request.get("world_session").getAsString().equals(acceptedSession)
            || !request.get("dim").getAsString().equals(acceptedDimension)
            || request.get("view").getAsLong() != acceptedView
            || !request.get("mc_uuid").getAsString().equals(mc.player.getUUID().toString()))
            throw new IllegalArgumentException("sign binding does not match authenticated applied view");
        if (request.has("op") && request.get("op").getAsString().equals("unbind")) { unbind(); return; }
        JsonArray requestedBounds = request.getAsJsonArray("bounds");
        if (requestedBounds.size() != 6) throw new IllegalArgumentException("sign view bounds");
        int[] at = new int[6];
        for (int i = 0; i < 6; i++) {
            double n = requestedBounds.get(i).getAsDouble();
            if (!Double.isFinite(n) || n != Math.rint(n) || Math.abs(n) > 30000000) throw new IllegalArgumentException("integral sign bounds required");
            at[i] = (int)n;
        }
        bind(acceptedSession, acceptedDimension, acceptedView, request.get("mapping").getAsString(), at);
    }

    public static void unbind() {
        synchronized (PUBLICATION) {
            Fence old = fence;
            epoch++; fence = null; bounds = null; ENTRIES.clear(); sequence = 0; nextSample = nextPublish = 0;
            if (old != null) {
                publish(old, false, true, "view_unbound", System.currentTimeMillis());
                long retiredEpoch = epoch;
                IO.schedule(() -> {
                    synchronized (PUBLICATION) {
                        if (epoch != retiredEpoch || fence != null) return;
                        JsonObject empty = new JsonObject(); empty.add("rows", new JsonArray());
                        try { pruneTextures(empty, System.currentTimeMillis()); }
                        catch (IOException exception) { error = exception.toString(); }
                    }
                }, 11, TimeUnit.SECONDS);
            }
        }
    }

    public static void invalidateFonts() { fontRevision++; ATLAS_CACHE.clear(); cachedLightmap = null; nextSample = 0; }
    public static void lightmapChanged() { lightmapRevision++; }

    /** Invoked by SignTextGameRendererMixin after vanilla renderLevel. */
    public static void frame(Minecraft mc, GpuTextureView lightmap) {
        if (!initialized) return;
        drain();
        Fence active = fence;
        if (active == null) return;
        if (mc.level == null || mc.player == null || !mc.level.dimension().identifier().toString().equals(active.dimension)) {
            if (mc.level == null) unbind();
            return;
        }
        long now = System.currentTimeMillis();
        viewerUuid = mc.player.getUUID().toString();
        if (now < nextSample) return;
        nextSample = now + SAMPLE_MILLIS;
        if (busy && now - busySince > 5000) {
            error = "font_readback_timeout";
            if (now >= nextPublish) publish(active, true, false, error, now);
            return; // do not allocate more buffers while an earlier GPU copy is busy
        }
        try {
            Map<Long, SignBlockEntity> live = scan(mc);
            boolean changed = ENTRIES.keySet().removeIf(position -> !live.containsKey(position));
            for (var item : live.entrySet()) {
                Entry entry = ENTRIES.computeIfAbsent(item.getKey(), ignored -> new Entry());
                if (entry.sign != item.getValue()) { entry.sign = item.getValue(); entry.capturedAt = 0; }
            }
            if (!busy) {
                var capture = new SignGlyphCapture();
                var pending = new ArrayList<Pending>();
                List<Long> positions = live.keySet().stream().sorted(Comparator
                    .comparingLong((Long position) -> ENTRIES.get(position).capturedAt).thenComparingLong(Long::longValue)).toList();
                Vec3 camera = mc.getCameraEntity() == null ? mc.player.position() : mc.getCameraEntity().position();
                for (long position : positions) {
                    Entry entry = ENTRIES.get(position);
                    var stateAndRenderer = renderState(mc, entry.sign, camera);
                    SignRenderState state = stateAndRenderer.state;
                    Source sig = signature(entry.sign, state);
                    // Static text is captured only after its content/font/light
                    // dependencies change. Obfuscation is sampled at4Hz.
                    if (sig.equals(entry.signature) && entry.lightRevision == lightmapRevision && entry.fontRevision == fontRevision
                        && (!(entry.obfuscated || entry.dynamic) || now - entry.capturedAt < SAMPLE_MILLIS)) continue;
                    var font = ((SignFontAccessor)stateAndRenderer.renderer).palcraft$signFont();
                    JsonObject row = new JsonObject();
                    JsonArray at = new JsonArray(); BlockPos pos = entry.sign.getBlockPos();
                    at.add(pos.getX()); at.add(pos.getY()); at.add(pos.getZ()); row.add("at", at);
                    row.addProperty("id", BuiltInRegistries.BLOCK.getKey(entry.sign.getBlockState().getBlock()).toString());
                    row.addProperty("state_key", entry.sign.getBlockState().toString());
                    pending.add(new Pending(position, sig, row,
                        capture.face(font, state, state.frontText, state.transformations.frontText()),
                        capture.face(font, state, state.backText, state.transformations.backText())));
                    if (pending.size() >= BATCH) break;
                }
                if (!pending.isEmpty()) { busy = true; busySince = now; captures += pending.size(); read(capture, lightmap, pending, epoch); }
            }
            if (changed || now >= nextPublish) publish(active, true, error == null, error, now);
        } catch (RuntimeException exception) {
            error = exception.toString();
            // Incomplete enumeration must never be interpreted as a replacement.
            if (now >= nextPublish) publish(active, true, false, error, now);
            Passthrough.LOG.debug("sign display awaiting view/font resources: {}", error);
        }
    }

    private static Map<Long, SignBlockEntity> scan(Minecraft mc) {
        var result = new HashMap<Long, SignBlockEntity>();
        int minX = bounds[0] >> 4, maxX = (bounds[3] - 1) >> 4;
        int minZ = bounds[2] >> 4, maxZ = (bounds[5] - 1) >> 4;
        // Query only existing client chunks. getChunk(...,false) never loads a chunk.
        if ((long)(maxX - minX + 1) * (maxZ - minZ + 1) > MAX_SCAN_CHUNKS)
            throw new IllegalStateException("sign view chunk limit");
        for (int x = minX; x <= maxX; x++) for (int z = minZ; z <= maxZ; z++) {
            var chunk = mc.level.getChunkSource().getChunk(x, z, ChunkStatus.FULL, false);
            if (chunk == null) continue;
            for (var entity : chunk.getBlockEntities().values()) if (entity instanceof SignBlockEntity sign && !sign.isRemoved()) {
                BlockPos p = sign.getBlockPos();
                if (p.getX() >= bounds[0] && p.getY() >= bounds[1] && p.getZ() >= bounds[2]
                    && p.getX() < bounds[3] && p.getY() < bounds[4] && p.getZ() < bounds[5]) {
                    result.put(p.asLong(), sign);
                    if (result.size() > MAX_SIGNS) throw new IllegalStateException("sign view capacity");
                }
            }
        }
        return result;
    }

    private record Rendered(SignRenderState state, BlockEntityRenderer<SignBlockEntity, SignRenderState> renderer) {}
    @SuppressWarnings("unchecked")
    private static Rendered renderState(Minecraft mc, SignBlockEntity sign, Vec3 camera) {
        var renderer = (BlockEntityRenderer<SignBlockEntity, SignRenderState>)(Object)mc.getBlockEntityRenderDispatcher().getRenderer(sign);
        if (!(renderer instanceof SignFontAccessor)) throw new IllegalStateException("SignFontAccessor mixin not installed");
        SignRenderState state = renderer.createRenderState();
        renderer.extractRenderState(sign, state, 0, camera, null);
        return new Rendered(state, renderer);
    }

    private static Source signature(SignBlockEntity sign, SignRenderState state) {
        // Actual immutable SignText values and live block orientation, not decoded
        // NBT/plain strings. Resource-pack/lighting refresh has its own cadence.
        return new Source(sign.getBlockState(), state.frontText, state.backText,
            state.drawOutline, state.isTextFilteringEnabled, state.lightCoords);
    }

    /** Original bounded GPU readback, reused by the entity input capture on the
     * existing render thread; no additional reader/executor is created. */
    public static CompletableFuture<SignGlyphRaster.Atlas> readShaderTexture(GpuTexture texture) {
        return readTexture(texture);
    }
    public static long shaderLightmapRevision() { return lightmapRevision; }

    private static CompletableFuture<SignGlyphRaster.Atlas> readTexture(GpuTexture texture) {
        var future = new CompletableFuture<SignGlyphRaster.Atlas>();
        if (texture.isClosed() || (texture.usage() & GpuTexture.USAGE_COPY_SRC) == 0)
            throw new IllegalStateException("font/lightmap readback usage not installed");
        boolean gray = texture.getFormat() == GpuFormat.R8_UNORM;
        if (!gray && texture.getFormat() != GpuFormat.RGBA8_UNORM) throw new IllegalStateException("unsupported font atlas format");
        int width = texture.getWidth(0), height = texture.getHeight(0);
        long bytes = (long)width * height * (gray ? 1 : 4);
        if (bytes < 1 || bytes > 16777216) throw new IllegalStateException("sign atlas byte limit");
        GpuBuffer buffer = RenderSystem.getDevice().createBuffer(() -> "PalCraft sign atlas readback",
            GpuBuffer.USAGE_COPY_DST | GpuBuffer.USAGE_MAP_READ, bytes);
        try {
            RenderSystem.getDevice().createCommandEncoder().copyTextureToBuffer(texture, buffer, 0, () -> {
                try (var mapped = buffer.map(true, false)) {
                    byte[] pixels = new byte[(int)bytes]; mapped.data().get(pixels);
                    future.complete(new SignGlyphRaster.Atlas(width, height, gray, pixels));
                } catch (RuntimeException exception) { future.completeExceptionally(exception); }
                finally { buffer.close(); }
            }, 0);
        } catch (RuntimeException exception) { buffer.close(); throw exception; }
        return future;
    }

    private static void read(SignGlyphCapture capture, GpuTextureView lightmap, List<Pending> pending, long capturedEpoch) {
        var textures = new ArrayList<CompletableFuture<SignGlyphRaster.Atlas>>();
        long capturedLightRevision = lightmapRevision, capturedFontRevision = fontRevision;
        try {
            ATLAS_CACHE.keySet().removeIf(GpuTexture::isClosed);
            if (ATLAS_CACHE.size() > 64) ATLAS_CACHE.clear();
            for (int i = 0; i < capture.textures.size(); i++) {
                GpuTexture texture = capture.textures.get(i);
                var regions = regions(pending, i);
                CachedAtlas cached = ATLAS_CACHE.get(texture);
                if (cached != null && !capture.dynamicTextures.contains(texture) && cached.regions.containsAll(regions)) textures.add(CompletableFuture.completedFuture(cached.pixels));
                else {
                    if (cached != null) regions.addAll(cached.regions);
                    var readback = readTexture(texture);
                    readback.thenAccept(pixels -> {
                        if (fontRevision == capturedFontRevision) ATLAS_CACHE.put(texture, new CachedAtlas(pixels, regions));
                    });
                    textures.add(readback);
                }
            }
            CompletableFuture<SignGlyphRaster.Atlas> light;
            if (cachedLightmap != null && cachedLightmapRevision == capturedLightRevision)
                light = CompletableFuture.completedFuture(cachedLightmap);
            else {
                light = readTexture(lightmap.texture());
                light.thenAccept(pixels -> { cachedLightmap = pixels; cachedLightmapRevision = capturedLightRevision; });
            }
            var all = new ArrayList<CompletableFuture<?>>(); all.addAll(textures); all.add(light);
            CompletableFuture.allOf(all.toArray(CompletableFuture[]::new)).whenCompleteAsync((ignored, failure) -> {
                if (failure != null) { COMPLETED.add(new Completion(capturedEpoch, capturedLightRevision, capturedFontRevision, List.of(), failure.toString())); return; }
                try {
                    if (epoch != capturedEpoch) { COMPLETED.add(new Completion(capturedEpoch, capturedLightRevision, capturedFontRevision, List.of(), null)); return; }
                    List<SignGlyphRaster.Atlas> atlases = textures.stream().map(CompletableFuture::join).toList();
                    for (Pending item : pending) {
                        item.row.add("front", bake(item.front, atlases, light.join()));
                        item.row.add("back", bake(item.back, atlases, light.join()));
                    }
                    COMPLETED.add(new Completion(capturedEpoch, capturedLightRevision, capturedFontRevision, pending, null));
                } catch (IOException | RuntimeException exception) { COMPLETED.add(new Completion(capturedEpoch, capturedLightRevision, capturedFontRevision, List.of(), exception.toString())); }
            }, IO);
        } catch (RuntimeException exception) { COMPLETED.add(new Completion(capturedEpoch, capturedLightRevision, capturedFontRevision, List.of(), exception.toString())); }
    }

    private static HashSet<Region> regions(List<Pending> pending, int atlas) {
        var result = new HashSet<Region>();
        for (Pending item : pending) for (var side : List.of(item.front, item.back)) for (var q : side.quads()) if (q.atlas() == atlas) {
            result.add(new Region(Math.min(Math.min(q.a().u(), q.b().u()), Math.min(q.c().u(), q.d().u())),
                Math.min(Math.min(q.a().v(), q.b().v()), Math.min(q.c().v(), q.d().v())),
                Math.max(Math.max(q.a().u(), q.b().u()), Math.max(q.c().u(), q.d().u())),
                Math.max(Math.max(q.a().v(), q.b().v()), Math.max(q.c().v(), q.d().v()))));
        }
        return result;
    }

    private static JsonObject bake(SignGlyphCapture.Surface surface, List<SignGlyphRaster.Atlas> atlases,
                                   SignGlyphRaster.Atlas lightmap) throws IOException {
        var image = SignGlyphRaster.render(surface.bounds(), SCALE, atlases, surface.quads(), SignGlyphRaster.light(lightmap, surface.light()));
        var bytes = new ByteArrayOutputStream();
        if (!ImageIO.write(image, "png", bytes)) throw new IOException("PNG encoder unavailable");
        byte[] png = bytes.toByteArray(); String sha;
        try { sha = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png)); }
        catch (java.security.NoSuchAlgorithmException exception) { throw new IllegalStateException(exception); }
        Path texture = ROOT.resolve("textures/" + sha + ".png"); Files.createDirectories(texture.getParent());
        if (!Files.isRegularFile(texture)) atomic(texture, png);
        JsonObject side = surface.metadata().deepCopy(), desc = new JsonObject();
        desc.addProperty("path", "textures/" + sha + ".png"); desc.addProperty("sha256", sha);
        desc.addProperty("width", image.getWidth()); desc.addProperty("height", image.getHeight());
        boolean fractionalAlpha = false;
        for (int y = 0; y < image.getHeight() && !fractionalAlpha; y++) for (int x = 0; x < image.getWidth(); x++) {
            int alpha = image.getRGB(x, y) >>> 24;
            if (alpha != 0 && alpha != 255) { fractionalAlpha = true; break; }
        }
        desc.addProperty("scale", SCALE);
        desc.addProperty("alpha_mode", fractionalAlpha ? "translucent" : "cutout");
        side.add("image", desc); return side;
    }

    private static void drain() {
        Completion done;
        while ((done = COMPLETED.poll()) != null) {
            busy = false;
            if (done.epoch != epoch) { dropped++; continue; }
            if (done.error != null) { error = done.error; continue; }
            for (Pending item : done.pending) {
                Entry entry = ENTRIES.get(item.position);
                if (entry == null) continue;
                // A late readback from an unloaded/replaced BE cannot republish it.
                Minecraft mc = Minecraft.getInstance();
                if (mc.level == null || mc.level.getBlockEntity(entry.sign.getBlockPos()) != entry.sign) continue;
                var state = renderState(mc, entry.sign, mc.player.position()).state;
                if (!item.signature.equals(signature(entry.sign, state))) continue;
                entry.row = item.row; entry.signature = item.signature; entry.capturedAt = System.currentTimeMillis();
                entry.lightRevision = done.lightRevision; entry.fontRevision = done.fontRevision;
                entry.obfuscated = item.front.metadata().get("obfuscated").getAsBoolean() || item.back.metadata().get("obfuscated").getAsBoolean();
                entry.dynamic = item.front.metadata().get("dynamic_atlas").getAsBoolean() || item.back.metadata().get("dynamic_atlas").getAsBoolean();
            }
            error = null; nextPublish = 0;
        }
    }

    private static void publish(Fence active, boolean available, boolean complete, String reason, long now) {
        long capturedEpoch = epoch;
        JsonObject snapshot = new JsonObject();
        snapshot.addProperty("schema", 1); snapshot.addProperty("t", "sign_text");
        snapshot.addProperty("producer", PRODUCER); snapshot.addProperty("epoch", capturedEpoch);
        snapshot.addProperty("seq", ++sequence); snapshot.addProperty("created_ms", now);
        snapshot.addProperty("world_session", active.worldSession); snapshot.addProperty("dim", active.dimension);
        snapshot.addProperty("view", active.view); snapshot.addProperty("mapping", active.mapping);
        Minecraft mc = Minecraft.getInstance();
        snapshot.addProperty("mc_uuid", mc.player == null ? viewerUuid : mc.player.getUUID().toString());
        snapshot.addProperty("available", available); snapshot.addProperty("complete", complete);
        if (reason != null) snapshot.addProperty("error", reason);
        JsonArray rows = new JsonArray();
        ENTRIES.entrySet().stream().sorted(Map.Entry.comparingByKey()).forEach(entry -> {
            if (entry.getValue().row != null) rows.add(entry.getValue().row.deepCopy());
        });
        snapshot.add("rows", rows); snapshot.addProperty("loaded_signs", ENTRIES.size());
        snapshot.addProperty("raster_ready", rows.size() == ENTRIES.size());
        snapshot.addProperty("source", "minecraft26.3_Font_quads_atlas_and_live_lightmap");
        IO.execute(() -> {
            try {
                synchronized (PUBLICATION) {
                    if (epoch != capturedEpoch) return;
                    Files.createDirectories(ROOT); atomic(ROOT.resolve("snapshot.json"), snapshot.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    publications++;
                    if (publications % 16 == 0) pruneTextures(snapshot, now);
                }
                stream(snapshot, capturedEpoch);
            } catch (IOException exception) { error = exception.toString(); }
        });
        nextPublish = now + HEARTBEAT_MILLIS;
    }

    private static void atomic(Path path, byte[] bytes) throws IOException {
        Path temp = path.resolveSibling(path.getFileName() + ".pending");
        Files.write(temp, bytes);
        Files.move(temp, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    }

    private static JsonObject envelope(JsonObject snapshot, String type) {
        JsonObject message = new JsonObject(); message.addProperty("schema", 1); message.addProperty("t", type);
        for (String key : List.of("producer", "epoch", "seq", "created_ms", "world_session", "dim", "view", "mapping", "mc_uuid"))
            message.add(key, snapshot.get(key).deepCopy());
        return message;
    }

    private static void stream(JsonObject snapshot, long capturedEpoch) throws IOException {
        Transport channel = transport; if (channel == null || epoch != capturedEpoch) return;
        var images = new LinkedHashMap<String, JsonObject>();
        for (var element : snapshot.getAsJsonArray("rows")) for (String face : List.of("front", "back")) {
            JsonObject image = element.getAsJsonObject().getAsJsonObject(face).getAsJsonObject("image");
            images.putIfAbsent(image.get("sha256").getAsString(), image);
        }
        if (channel.sent.size() > 8192) channel.sent.clear();
        try {
            for (var item : images.entrySet()) {
                if (channel != transport || epoch != capturedEpoch) return;
                String sha = item.getKey(); if (channel.sent.contains(sha)) continue;
                JsonObject image = item.getValue();
                if (!image.get("path").getAsString().equals("textures/" + sha + ".png") || !sha.matches("[a-f0-9]{64}"))
                    throw new IOException("invalid private glyph path");
                Path file = ROOT.resolve("textures/" + sha + ".png");
                long size = Files.size(file);
                if (size < 1 || size > WIRE_MAX_PNG) throw new IOException("glyph wire byte limit");
                byte[] png = Files.readAllBytes(file);
                for (int offset = 0; offset < png.length; offset += WIRE_CHUNK) {
                    if (channel != transport || epoch != capturedEpoch) return;
                    int count = Math.min(WIRE_CHUNK, png.length - offset);
                    JsonObject packet = envelope(snapshot, "sign_text_asset");
                    packet.addProperty("sha256", sha); packet.addProperty("bytes", png.length);
                    packet.addProperty("offset", offset); packet.addProperty("final", offset + count == png.length);
                    packet.addProperty("width", image.get("width").getAsInt()); packet.addProperty("height", image.get("height").getAsInt());
                    packet.addProperty("data", Base64.getEncoder().encodeToString(Arrays.copyOfRange(png, offset, offset + count)));
                    channel.send.accept(packet);
                }
                channel.sent.add(sha);
            }
            if (channel != transport || epoch != capturedEpoch) return;
            JsonObject footer = envelope(snapshot, "sign_text_snapshot"); footer.add("snapshot", snapshot.deepCopy());
            channel.send.accept(footer); // every referenced PNG was sent before this footer
        } catch (RuntimeException exception) {
            // The next controller rebind creates a fresh transport/asset set.
            if (channel == transport) transport = null;
            throw new IOException("glyph authenticated transport unavailable", exception);
        }
    }

    private static void pruneTextures(JsonObject snapshot, long now) throws IOException {
        var keep = new HashSet<String>();
        for (var element : snapshot.getAsJsonArray("rows")) for (String side : List.of("front", "back"))
            keep.add(element.getAsJsonObject().getAsJsonObject(side).getAsJsonObject("image").get("path").getAsString());
        Path textures = ROOT.resolve("textures"); if (!Files.isDirectory(textures)) return;
        try (var files = Files.list(textures)) {
            List<Path> unused = files.filter(path -> path.getFileName().toString().matches("[a-f0-9]{64}\\.png"))
                .filter(path -> !keep.contains("textures/" + path.getFileName())).sorted().toList();
            for (Path path : unused) {
                // Preserve recently published/in-flight textures long enough for
                // the native consumer's5-second freshness window.
                if (now - Files.getLastModifiedTime(path).toMillis() > 10000) Files.deleteIfExists(path);
            }
        }
    }

    public static JsonObject status() {
        JsonObject result = new JsonObject(); result.addProperty("schema", 1);
        result.addProperty("initialized", initialized); result.addProperty("bound", fence != null);
        result.addProperty("busy", busy); result.addProperty("signs", ENTRIES.size());
        result.addProperty("captures", captures); result.addProperty("publications", publications); result.addProperty("dropped", dropped);
        result.addProperty("epoch", epoch); if (error != null) result.addProperty("error", error);
        result.addProperty("runtime_verified", false); return result;
    }
}
