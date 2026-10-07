package dev.rehan.passthrough;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.rehan.passthrough.world.WorldDeltaBuffer;
import dev.rehan.passthrough.world.WorldStateCodec;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerBlockEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerChunkEvents;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.Portal;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.Vec3;

/** Authoritative world events. All reads and callbacks run on the Minecraft server thread. */
public final class WorldCompatibility {
    public static final int PROTOCOL_VERSION = 2;
    private static final boolean TRAVEL_ENABLED = Boolean.getBoolean("palcraft.travel.enabled");
    private static final String OVERWORLD = "minecraft:overworld";
    // A block entity's 16 KiB update tag is duplicated by legacy geometry, then escaped by the transport wrapper.
    private static final int BATCH_OPS = 32;
    private static final int DELTAS_PER_TICK = 2048;
    private static final int SNAPSHOT_CELLS_PER_TICK = 4096;
    private static final int SNAPSHOT_OPS_PER_TICK = 256;
    private static final int MAX_SNAPSHOT_JOBS = 512;
    private static final WorldDeltaBuffer changes = new WorldDeltaBuffer(65536);
    private static final Map<String, ServerLevel> worlds = new LinkedHashMap<>();
    private static final Set<WorldDeltaBuffer.Position> moving = new HashSet<>();
    private static final Set<String> resyncRequired = new HashSet<>();
    private static final ArrayDeque<Snapshot> snapshots = new ArrayDeque<>();
    private static final Map<UUID, View> views = new HashMap<>();
    private static final Map<UUID, Long> viewGenerations = new HashMap<>();
    private static final Map<UUID, Restore> teleportSources = new HashMap<>();
    private static final Map<UUID, Integer> teleportDepth = new HashMap<>();
    private static final Set<UUID> teleportSucceeded = new HashSet<>();
    private static final Map<UUID, Restore> rollbackSources = new HashMap<>();
    private static final Set<UUID> rollingBack = new HashSet<>();
    private static final Map<UUID, PortalContact> portals = new HashMap<>();
    private static MinecraftServer server;
    private static boolean initialized;
    private static String session;
    private static long sequence;
    private static long snapshotSequence;
    private static long emittedOps;
    private static int autoSyncTicks;

    private static final class View {
        String dimension;
        long generation = 1;
        boolean waitingAck = true;
        ServerPlayer identity;
        int chunkX = Integer.MIN_VALUE, chunkZ = Integer.MIN_VALUE, sectionY = Integer.MIN_VALUE;
        View(String dimension) { this.dimension = dimension; }
    }
    private record PortalContact(String dimension, BlockPos pos, String kind, int lastTick) {}
    private record Restore(String dimension, Vec3 pos, float yaw, float pitch, long generation) {}

    /** Reads never load a neighbor chunk merely to compute fluid height, flow, or a shape. */
    private record LoadedView(ServerLevel level) implements BlockGetter {
        private LevelChunk chunk(BlockPos pos) {
            return level.getChunkSource().getChunkNow(pos.getX() >> 4, pos.getZ() >> 4);
        }
        public BlockEntity getBlockEntity(BlockPos pos) {
            LevelChunk chunk = chunk(pos); return chunk == null ? null : chunk.getBlockEntity(pos);
        }
        public BlockState getBlockState(BlockPos pos) {
            LevelChunk chunk = chunk(pos); return chunk == null ? Blocks.AIR.defaultBlockState() : chunk.getBlockState(pos);
        }
        public FluidState getFluidState(BlockPos pos) { return getBlockState(pos).getFluidState(); }
        public int getHeight() { return level.getHeight(); }
        public int getMinY() { return level.getMinY(); }
    }

    private static final class Snapshot {
        final String id, dimension;
        final UUID owner;
        final ServerLevel level;
        final int chunkX, chunkZ, minX, minY, minZ, maxX, maxY, maxZ;
        int x, y, z;
        boolean begun;
        String requestId;
        Snapshot(ServerLevel level, UUID owner, int cx, int cz, int minX, int minY, int minZ,
                 int maxX, int maxY, int maxZ) {
            this.id = session + ":" + (++snapshotSequence);
            this.dimension = dimension(level); this.owner = owner; this.level = level;
            this.chunkX = cx; this.chunkZ = cz;
            this.minX = minX; this.minY = minY; this.minZ = minZ;
            this.maxX = maxX; this.maxY = maxY; this.maxZ = maxZ;
            this.x = minX; this.y = minY; this.z = minZ;
        }
        boolean complete() { return x >= maxX; }
        void advance() {
            if (++y >= maxY) { y = minY; if (++z >= maxZ) { z = minZ; x++; } }
        }
        JsonObject event(String operation) {
            JsonObject result = lifecycle(operation);
            result.addProperty("snapshot", id);
            if (requestId != null) result.addProperty("request_id", requestId);
            result.addProperty("player", owner.toString());
            JsonArray chunk = new JsonArray(); chunk.add(chunkX); chunk.add(chunkZ); result.add("at", chunk);
            JsonArray bounds = new JsonArray();
            for (int value : new int[]{minX,minY,minZ,maxX,maxY,maxZ}) bounds.add(value);
            result.add("bounds", bounds);
            result.addProperty("replace", true);
            return result;
        }
    }

    private WorldCompatibility() {}

    public static String dimension(ServerLevel level) { return level.dimension().identifier().toString(); }

    public static void initialize() {
        if (initialized) return;
        initialized = true;
        ServerChunkEvents.CHUNK_LOAD.register(WorldCompatibility::chunkLoad);
        ServerChunkEvents.CHUNK_UNLOAD.register(WorldCompatibility::chunkUnload);
        ServerBlockEntityEvents.BLOCK_ENTITY_LOAD.register((entity, level) -> blockEntityChanged(level, entity.getBlockPos(), "block_entity_load"));
        ServerBlockEntityEvents.BLOCK_ENTITY_UNLOAD.register((entity, level) -> blockEntityChanged(level, entity.getBlockPos(), "block_entity_unload"));
    }

    public static void attach(MinecraftServer authority) {
        initialize();
        server = authority; session = UUID.randomUUID().toString(); sequence = 0;
        snapshotSequence = 0; emittedOps = 0; autoSyncTicks = 0;
        changes.clear(); worlds.clear(); moving.clear(); snapshots.clear(); views.clear(); portals.clear(); resyncRequired.clear();
        viewGenerations.clear(); teleportSources.clear(); teleportDepth.clear(); teleportSucceeded.clear(); rollbackSources.clear(); rollingBack.clear();
        discoverWorlds();
    }

    public static void detach() {
        if (server != null) for (String dimension : new ArrayList<>(worlds.keySet()))
            emitLifecycle(dimension, lifecycle("world_unload"));
        server = null; changes.clear(); worlds.clear(); moving.clear(); snapshots.clear(); views.clear(); portals.clear(); resyncRequired.clear();
        viewGenerations.clear(); teleportSources.clear(); teleportDepth.clear(); teleportSucceeded.clear(); rollbackSources.clear(); rollingBack.clear();
    }

    private static boolean observing(ServerLevel level) {
        return server != null && level.getServer() == server && Passthrough.active;
    }

    private static JsonObject lifecycle(String operation) {
        JsonObject result = new JsonObject(); result.addProperty("op", operation); return result;
    }

    private static void discoverWorlds() {
        Set<String> present = new HashSet<>();
        for (ServerLevel level : server.getAllLevels()) {
            String dimension = dimension(level); present.add(dimension);
            if (!worlds.containsKey(dimension)) {
                worlds.put(dimension, level);
                JsonObject event = lifecycle("world_load");
                event.addProperty("min_y", level.getMinY()); event.addProperty("height", level.getHeight());
                event.addProperty("coordinate_scale", level.dimensionType().coordinateScale());
                event.addProperty("has_skylight", level.dimensionType().hasSkyLight());
                emitLifecycle(dimension, event);
            }
        }
        for (String removed : new ArrayList<>(worlds.keySet())) if (!present.contains(removed)) {
            emitLifecycle(removed, lifecycle("world_unload")); worlds.remove(removed);
            changes.removeIf(pos -> pos.dimension().equals(removed));
            moving.removeIf(pos -> pos.dimension().equals(removed));
            snapshots.removeIf(job -> removeSnapshot(job,job.dimension.equals(removed)));
        }
    }

    private static WorldDeltaBuffer.Position position(ServerLevel level, BlockPos pos) {
        return new WorldDeltaBuffer.Position(dimension(level), pos.getX(), pos.getY(), pos.getZ());
    }

    private static void mark(ServerLevel level, BlockPos pos, String cause, int flags) {
        if (!observing(level) || !level.isInWorldBounds(pos)) return;
        String dimension = dimension(level);
        worlds.putIfAbsent(dimension, level);
        if (!changes.mark(position(level, pos), cause, flags) && resyncRequired.add(dimension)) {
            JsonObject event = lifecycle("resync_required");
            event.addProperty("reason", "delta_capacity"); event.addProperty("capacity", 65536);
            emitLifecycle(dimension, event);
        }
    }

    public static void blockChanged(ServerLevel level, BlockPos pos, int flags) {
        mark(level, pos, "block_state", flags);
        LoadedView loaded = new LoadedView(level);
        BlockState state = loaded.getBlockState(pos);
        if (state.is(Blocks.MOVING_PISTON)) moving.add(position(level, pos));
        else moving.remove(position(level, pos));
        // Fluid height/flow and collision may depend on a neighbor even if its BlockState did not change.
        for (Direction direction : Direction.values()) {
            BlockPos neighbor = pos.relative(direction);
            if (WorldStateCodec.mirrored(loaded.getBlockState(neighbor), false)) mark(level, neighbor, "neighbor_shape", 0);
        }
    }

    public static void blockEntityChanged(ServerLevel level, BlockPos pos, String cause) { mark(level, pos, cause, 0); }

    public static void blockEvent(ServerLevel level, BlockPos pos, Block block, int type, int data) {
        if (!observing(level)) return;
        JsonObject event = lifecycle("block_event");
        event.add("at", WorldStateCodec.at(pos));
        event.addProperty("id", net.minecraft.core.registries.BuiltInRegistries.BLOCK.getKey(block).toString());
        event.addProperty("type", type); event.addProperty("data", data); event.addProperty("phase", "applied");
        emitLifecycle(dimension(level), event);
        mark(level, pos, "block_event", 0);
    }

    private static JsonObject capture(ServerLevel level, BlockPos pos) {
        LoadedView view = new LoadedView(level);
        BlockState state = view.getBlockState(pos);
        boolean ground = dimension(level).equals(OVERWORLD) && Nether.isGround(pos);
        return WorldStateCodec.block(view, pos, state, level.registryAccess(), ground,
            neighbor -> !level.isInWorldBounds(neighbor) || view.chunk(neighbor) != null);
    }

    public static JsonObject inspectBlock(ServerLevel level, BlockPos pos) {
        JsonObject result = new JsonObject();
        result.addProperty("dim", dimension(level));
        result.addProperty("session", session); result.addProperty("loaded", new LoadedView(level).chunk(pos) != null);
        if (new LoadedView(level).chunk(pos) != null) result.add("world_state", capture(level, pos));
        return result;
    }

    public static void tick(MinecraftServer authority) {
        if (authority != server || !Passthrough.active) return;
        discoverWorlds();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) observeView(player);
        Set<UUID> online = new HashSet<>();
        for (ServerPlayer player : server.getPlayerList().getPlayers()) online.add(player.getUUID());
        for (UUID owner : new ArrayList<>(views.keySet())) if (!online.contains(owner)) {
            View view = views.remove(owner);
            JsonObject event = lifecycle("player_leave"); event.addProperty("player", owner.toString());
            emitLifecycle(view.dimension, event); cancelSnapshots(owner);
            teleportSources.remove(owner); rollbackSources.remove(owner);
            teleportDepth.remove(owner); teleportSucceeded.remove(owner);
        }
        for (var entry : new ArrayList<>(portals.entrySet())) if (entry.getValue().lastTick < authority.getTickCount() - 1) {
            PortalContact contact = entry.getValue();
            JsonObject event = lifecycle("portal_exit"); event.addProperty("player", entry.getKey().toString());
            event.add("at", WorldStateCodec.at(contact.pos)); emitLifecycle(contact.dimension, event); portals.remove(entry.getKey());
        }
        for (WorldDeltaBuffer.Position pos : new ArrayList<>(moving)) {
            ServerLevel level = worlds.get(pos.dimension());
            BlockPos at = new BlockPos(pos.x(), pos.y(), pos.z());
            if (level == null || new LoadedView(level).chunk(at) == null) { moving.remove(pos); continue; }
            mark(level, at, "piston_motion", 0);
            if (!new LoadedView(level).getBlockState(at).is(Blocks.MOVING_PISTON)) moving.remove(pos);
        }
        flushChanges(DELTAS_PER_TICK);
        if (++autoSyncTicks % 10 == 0) for (ServerPlayer player : authority.getPlayerList().getPlayers()) {
            View view = views.get(player.getUUID()); BlockPos pos = player.blockPosition();
            if (view.chunkX != pos.getX() >> 4 || view.chunkZ != pos.getZ() >> 4 || view.sectionY != pos.getY() >> 4)
                syncFor(player, 32);
        }
        scanSnapshots();
    }

    public static void flush() { if (server != null && Passthrough.active) flushChanges(DELTAS_PER_TICK); }

    private static void flushChanges(int limit) {
        Map<String, JsonArray> batches = new LinkedHashMap<>();
        for (WorldDeltaBuffer.Change change : changes.drain(limit)) {
            WorldDeltaBuffer.Position pos = change.position();
            ServerLevel level = worlds.get(pos.dimension()); BlockPos at = new BlockPos(pos.x(), pos.y(), pos.z());
            if (level == null || new LoadedView(level).chunk(at) == null) continue;
            JsonObject block = capture(level, at);
            JsonArray causes = new JsonArray(); change.causes().forEach(causes::add);
            block.add("causes", causes); block.addProperty("flags", change.flags());
            JsonArray batch = batches.computeIfAbsent(pos.dimension(), ignored -> new JsonArray());
            batch.add(block);
            if (batch.size() >= BATCH_OPS) { emitOps(pos.dimension(), batch); batches.put(pos.dimension(), new JsonArray()); }
        }
        batches.forEach((dimension, batch) -> { if (!batch.isEmpty()) emitOps(dimension, batch); });
    }

    private static JsonObject envelope(String dimension) {
        JsonObject result = new JsonObject();
        // Kept first for the existing server journal's blocks prefix filter.
        result.addProperty("t", "blocks"); result.addProperty("v", PROTOCOL_VERSION);
        result.addProperty("session", session); result.addProperty("seq", ++sequence);
        result.addProperty("tick", server == null ? 0 : server.getTickCount()); result.addProperty("dim", dimension);
        result.add("set", new JsonArray()); result.add("clear", new JsonArray()); result.add("geometry", new JsonArray());
        return result;
    }

    private static void emitOps(String dimension, JsonArray operations) { emitOps(dimension,operations,null); }
    private static void emitOps(String dimension, JsonArray operations, String requestId) {
        JsonObject message = envelope(dimension); message.add("ops", operations);
        if (requestId != null) message.addProperty("request_id", requestId);
        if (dimension.equals(OVERWORLD)) for (var operation : operations) {
            JsonObject block = operation.getAsJsonObject();
            boolean solid = block.get("op").getAsString().equals("upsert") && block.get("solid").getAsBoolean();
            JsonArray coordinates = message.getAsJsonArray(solid ? "set" : "clear");
            block.getAsJsonArray("at").forEach(coordinates::add);
            if (solid) message.getAsJsonArray("geometry").add(block);
        }
        emittedOps += operations.size(); Passthrough.events.accept(message.toString());
    }

    private static void emitLifecycle(String dimension, JsonObject event) {
        if (server == null) return;
        JsonObject message = envelope(dimension); JsonArray events = new JsonArray(); events.add(event);
        if (event.has("request_id")) message.add("request_id", event.get("request_id"));
        message.add("lifecycle", events); message.add("ops", new JsonArray());
        Passthrough.events.accept(message.toString());
    }

    private static boolean removeSnapshot(Snapshot job, boolean remove) {
        if (remove && job.requestId != null) emitLifecycle(job.dimension, job.event("snapshot_cancel"));
        return remove;
    }
    private static void cancelSnapshots(UUID owner) {
        var iterator = snapshots.iterator();
        while (iterator.hasNext()) {
            Snapshot job = iterator.next();
            if (!job.owner.equals(owner)) continue;
            if (job.begun || job.requestId != null) emitLifecycle(job.dimension, job.event("snapshot_cancel"));
            iterator.remove();
        }
    }

    public static void syncFor(ServerPlayer player, int requestedRadius) { syncFor(player,requestedRadius,null); }
    public static void syncFor(ServerPlayer player, int requestedRadius, String requestId) {
        syncFor(player,requestedRadius,requestId,null);
    }
    public static void syncFor(ServerPlayer player, int requestedRadius, String requestId, int[] requestedBounds) {
        if (requestId != null && !UUID.fromString(requestId).toString().equals(requestId)) throw new IllegalArgumentException("Invalid request_id");
        if (server == null || player.level().getServer() != server) return;
        ServerLevel level = player.level(); String dimension = dimension(level);
        worlds.putIfAbsent(dimension, level); View view = observeView(player);
        int radius = Math.clamp(requestedRadius, 1, 64); BlockPos center = player.blockPosition();
        view.chunkX = center.getX() >> 4; view.chunkZ = center.getZ() >> 4; view.sectionY = center.getY() >> 4;
        cancelSnapshots(player.getUUID());
        int minX = center.getX()-radius, maxX = center.getX()+radius+1;
        int minZ = center.getZ()-radius, maxZ = center.getZ()+radius+1;
        int minY = Math.max(level.getMinY(), center.getY()-24), maxY = Math.min(level.getMaxY()+1, center.getY()+41);
        if (requestedBounds != null) {
            if (requestedBounds.length != 6 || requestedBounds[0] >= requestedBounds[3] || requestedBounds[1] >= requestedBounds[4]
                    || requestedBounds[2] >= requestedBounds[5] || (long)requestedBounds[3]-requestedBounds[0] > 129
                    || (long)requestedBounds[5]-requestedBounds[2] > 129 || (long)requestedBounds[4]-requestedBounds[1] > 65
                    || requestedBounds[1] < level.getMinY() || requestedBounds[4] > level.getMaxY()+1)
                throw new IllegalArgumentException("Authoritative target ring exceeds public blocksync capacity");
            minX=requestedBounds[0];minY=requestedBounds[1];minZ=requestedBounds[2];
            maxX=requestedBounds[3];maxY=requestedBounds[4];maxZ=requestedBounds[5];
        }
        int accepted = 0;
        for (int cx = minX >> 4; cx <= (maxX-1) >> 4; cx++) for (int cz = minZ >> 4; cz <= (maxZ-1) >> 4; cz++) {
            if (level.getChunkSource().getChunkNow(cx, cz) == null) continue;
            if (enqueueSnapshot(level, player.getUUID(), cx, cz, Math.max(minX,cx*16), minY, Math.max(minZ,cz*16),
                                Math.min(maxX,cx*16+16), maxY, Math.min(maxZ,cz*16+16),requestId)) accepted++;
        }
        resyncRequired.remove(dimension);
        JsonObject event = lifecycle("sync_requested"); event.addProperty("player", player.getUUID().toString());
        event.addProperty("radius", radius); event.addProperty("chunks", accepted);
        if (requestId != null) event.addProperty("request_id", requestId);
        event.addProperty("vertical_below", 24); event.addProperty("vertical_above", 40);
        event.addProperty("loaded_only", true); emitLifecycle(dimension, event);
    }

    private static boolean enqueueSnapshot(ServerLevel level, UUID owner, int cx, int cz, int minX, int minY, int minZ,
                                           int maxX, int maxY, int maxZ) {
        return enqueueSnapshot(level,owner,cx,cz,minX,minY,minZ,maxX,maxY,maxZ,null);
    }
    private static boolean enqueueSnapshot(ServerLevel level, UUID owner, int cx, int cz, int minX, int minY, int minZ,
                                           int maxX, int maxY, int maxZ, String requestId) {
        if (minY >= maxY) return false;
        for (Snapshot queued : snapshots) if (queued.owner.equals(owner) && queued.dimension.equals(dimension(level))
                && queued.chunkX == cx && queued.chunkZ == cz && queued.minX == minX && queued.minY == minY
                && queued.minZ == minZ && queued.maxX == maxX && queued.maxY == maxY && queued.maxZ == maxZ) return true;
        if (snapshots.size() >= MAX_SNAPSHOT_JOBS) {
            JsonObject event = lifecycle("resync_required"); event.addProperty("player", owner.toString());
            event.addProperty("reason", "snapshot_capacity");
            if (requestId != null) event.addProperty("request_id", requestId);
            emitLifecycle(dimension(level), event); return false;
        }
        Snapshot job=new Snapshot(level, owner, cx, cz, minX, minY, minZ, maxX, maxY, maxZ);job.requestId=requestId;
        snapshots.addLast(job); return true;
    }

    private static void scanSnapshots() {
        int cells = 0, operations = 0;
        long deadline = System.nanoTime() + 8_000_000L;
        while (!snapshots.isEmpty() && cells < SNAPSHOT_CELLS_PER_TICK && operations < SNAPSHOT_OPS_PER_TICK
                && System.nanoTime() < deadline) {
            Snapshot job = snapshots.removeFirst();
            LevelChunk chunk = job.level.getChunkSource().getChunkNow(job.chunkX, job.chunkZ);
            if (chunk == null || worlds.get(job.dimension) != job.level) {
                if (job.begun || job.requestId != null) emitLifecycle(job.dimension, job.event("snapshot_cancel"));
                continue;
            }
            if (!job.begun) { job.begun = true; emitLifecycle(job.dimension, job.event("snapshot_begin")); }
            JsonArray batch = new JsonArray();
            while (!job.complete() && cells < SNAPSHOT_CELLS_PER_TICK && operations < SNAPSHOT_OPS_PER_TICK
                    && batch.size() < BATCH_OPS && System.nanoTime() < deadline) {
                BlockPos pos = new BlockPos(job.x, job.y, job.z); cells++; job.advance();
                if (!WorldStateCodec.mirrored(chunk.getBlockState(pos), dimension(job.level).equals(OVERWORLD) && Nether.isGround(pos))) continue;
                JsonObject block = capture(job.level, pos); block.addProperty("snapshot", job.id);
                batch.add(block); operations++;
                if (chunk.getBlockState(pos).is(Blocks.MOVING_PISTON)) moving.add(position(job.level, pos));
            }
            if (!batch.isEmpty()) emitOps(job.dimension, batch,job.requestId);
            if (job.complete()) emitLifecycle(job.dimension, job.event("snapshot_end"));
            else snapshots.addLast(job);
        }
    }

    private static void chunkLoad(ServerLevel level, LevelChunk chunk, boolean newlyGenerated) {
        if (!observing(level)) return;
        JsonObject event = lifecycle("chunk_load"); event.addProperty("newly_generated", newlyGenerated); JsonArray at = new JsonArray();
        at.add(chunk.getPos().x()); at.add(chunk.getPos().z()); event.add("at", at); emitLifecycle(dimension(level), event);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) if (player.level() == level) {
            BlockPos center = player.blockPosition(); int cx = chunk.getPos().x(), cz = chunk.getPos().z();
            int minX = Math.max(center.getX()-32,cx*16), maxX = Math.min(center.getX()+33,cx*16+16);
            int minZ = Math.max(center.getZ()-32,cz*16), maxZ = Math.min(center.getZ()+33,cz*16+16);
            if (minX < maxX && minZ < maxZ) enqueueSnapshot(level, player.getUUID(), cx, cz, minX,
                Math.max(level.getMinY(),center.getY()-24), minZ, maxX, Math.min(level.getMaxY()+1,center.getY()+41), maxZ);
        }
    }

    private static void chunkUnload(ServerLevel level, LevelChunk chunk) {
        if (!observing(level)) return;
        String dimension = dimension(level); int cx = chunk.getPos().x(), cz = chunk.getPos().z();
        changes.removeIf(pos -> pos.dimension().equals(dimension) && pos.x() >> 4 == cx && pos.z() >> 4 == cz);
        moving.removeIf(pos -> pos.dimension().equals(dimension) && pos.x() >> 4 == cx && pos.z() >> 4 == cz);
        snapshots.removeIf(job -> removeSnapshot(job,job.dimension.equals(dimension) && job.chunkX == cx && job.chunkZ == cz));
        JsonObject event = lifecycle("chunk_unload"); JsonArray at = new JsonArray(); at.add(cx); at.add(cz); event.add("at", at);
        emitLifecycle(dimension, event);
    }

    private static View observeView(ServerPlayer player) {
        return observeView(player, null, false);
    }

    private static View observeView(ServerPlayer player, String requestedReason, boolean force) {
        String current = dimension(player.level()); View view = views.get(player.getUUID());
        String previous = null; String reason = "join";
        if (view == null) {
            view = new View(current);
            view.waitingAck = TRAVEL_ENABLED || !current.equals(OVERWORLD);
            views.put(player.getUUID(), view);
        }
        else if (view.dimension.equals(current) && view.identity == player && !force) return view;
        else {
            previous = view.dimension;
            reason = requestedReason != null ? requestedReason : !view.dimension.equals(current) ? "dimension_change" : "respawn";
            cancelSnapshots(player.getUUID()); view.dimension = current; view.waitingAck = true;
            view.chunkX = Integer.MIN_VALUE; view.chunkZ = Integer.MIN_VALUE; view.sectionY = Integer.MIN_VALUE;
        }
        view.identity = player;
        view.generation = viewGenerations.getOrDefault(player.getUUID(), 0L) + 1;
        viewGenerations.put(player.getUUID(), view.generation);
        JsonObject event = lifecycle("player_view"); event.addProperty("reason", reason);
        event.addProperty("player", player.getUUID().toString());
        if (previous != null) event.addProperty("from", previous);
        event.addProperty("to", current); event.addProperty("view", view.generation);
        event.addProperty("waiting_ack", view.waitingAck); event.add("pos", WorldStateCodec.vector(player.position()));
        event.addProperty("yaw", player.getYRot()); event.addProperty("pitch", player.getXRot());
        emitLifecycle(current, event);
        return view;
    }

    /** Republish the actual pending view after authenticated consumers attach; never advances its generation or ACKs it. */
    public static JsonObject syncPendingView(ServerPlayer player) {
        if (server == null || !server.isSameThread() || player.level().getServer() != server
                || server.getPlayerList().getPlayer(player.getUUID()) != player) return transitionError("current_server_player_required");
        View view = views.get(player.getUUID());
        if (view == null || view.identity != player || !view.dimension.equals(dimension(player.level())))
            return transitionError("current_pending_world_view_required");
        JsonObject result = new JsonObject(); result.addProperty("ok", true); result.addProperty("published", false);
        result.add("world_view", playerView(player));
        if (!view.waitingAck) return result;
        JsonObject event = lifecycle("player_view"); event.addProperty("reason", "reconnect");
        event.addProperty("player", player.getUUID().toString()); event.addProperty("to", view.dimension);
        event.addProperty("view", view.generation); event.addProperty("waiting_ack", true);
        event.add("pos", WorldStateCodec.vector(player.position()));
        event.addProperty("yaw", player.getYRot()); event.addProperty("pitch", player.getXRot());
        emitLifecycle(view.dimension, event); result.addProperty("published", true);
        return result;
    }

    /** Server-only entry for an actual respawn/reconnect/rebase; it creates no portal, items, or client-selected destination. */
    public static JsonObject beginViewTransition(ServerPlayer player, String reason) {
        observeView(player, reason == null ? "rebase" : reason, true);
        return playerView(player);
    }

    public static boolean waitingForView(ServerPlayer player) {
        return server != null && player.level().getServer() == server && observeView(player).waitingAck;
    }

    /** Trusted Pal-server file consumer only. The gateway authenticates its transaction and outer identity first. */
    public static JsonObject beginRebaseTransition(ServerPlayer player, Vec3 authoritativeMcPos) {
        View current = views.get(player.getUUID());
        if (current == null) return transitionError("world_view_missing");
        return beginRebaseTransition(player, session, current.dimension, current.generation, authoritativeMcPos);
    }

    /** No guest operation may call this with client-selected coordinates. No dimension, items, or original O changes. */
    public static JsonObject beginRebaseTransition(ServerPlayer player, String worldSession, String requestedDimension,
                                                   long generation, Vec3 authoritativeMcPos) {
        if (server == null || player.level().getServer() != server || !server.isSameThread())
            return transitionError("authority_thread_required");
        View current = views.get(player.getUUID());
        ServerLevel level = player.level();
        if (current == null || current.identity != player || current.waitingAck || !session.equals(worldSession)
                || current.generation != generation || !current.dimension.equals(requestedDimension)
                || !dimension(level).equals(requestedDimension)) return transitionError("stale_or_unapplied_world_view");
        if (authoritativeMcPos == null || !Double.isFinite(authoritativeMcPos.x) || !Double.isFinite(authoritativeMcPos.y)
                || !Double.isFinite(authoritativeMcPos.z) || Math.abs(authoritativeMcPos.x) > 29999900
                || Math.abs(authoritativeMcPos.z) > 29999900) return transitionError("invalid_authoritative_feet");
        BlockPos source = BlockPos.containing(authoritativeMcPos);
        if (!level.isInWorldBounds(source) || !level.getWorldBorder().isWithinBounds(source))
            return transitionError("authoritative_feet_out_of_world");
        // Prior MC coordinates may be wrong because the old physical page O was wrong. The trusted Pal inverse
        // mapping is the real source, including for rollback; never restore the stale logical position.
        float yaw = player.getYRot(), pitch = player.getXRot();
        player.setPos(authoritativeMcPos.x,authoritativeMcPos.y,authoritativeMcPos.z);
        View rebased = observeView(player,"rebase",true);
        rollbackSources.put(player.getUUID(),new Restore(requestedDimension,authoritativeMcPos,yaw,pitch,rebased.generation));
        JsonObject result = new JsonObject(); result.addProperty("ok",true); result.add("world_view",playerView(player));
        return result;
    }

    private static JsonObject transitionError(String reason) {
        JsonObject result = new JsonObject(); result.addProperty("ok",false); result.addProperty("error",reason); return result;
    }

    public static JsonObject playerView(ServerPlayer player) {
        View view = observeView(player); JsonObject result = new JsonObject();
        result.addProperty("world_session", session); result.addProperty("dim", view.dimension);
        result.addProperty("view", view.generation); result.addProperty("waiting_ack", view.waitingAck);
        result.addProperty("player", player.getUUID().toString()); result.add("pos", WorldStateCodec.vector(player.position()));
        result.addProperty("yaw", player.getYRot()); result.addProperty("pitch", player.getXRot()); return result;
    }

    /** Called before vanilla teleportTo so rollback can only restore an internally captured authoritative source. */
    public static void beforeTeleport(ServerPlayer player) {
        if (server == null || player.level().getServer() != server || rollingBack.contains(player.getUUID())) return;
        View view = observeView(player);
        teleportSources.putIfAbsent(player.getUUID(), new Restore(dimension(player.level()), player.position(), player.getYRot(), player.getXRot(), view.generation));
        teleportDepth.merge(player.getUUID(),1,Integer::sum);
    }

    public static void afterTeleport(ServerPlayer player, boolean succeeded) {
        if (rollingBack.contains(player.getUUID())) return;
        if (succeeded) teleportSucceeded.add(player.getUUID());
        int depth = teleportDepth.getOrDefault(player.getUUID(),1)-1;
        if (depth > 0) { teleportDepth.put(player.getUUID(),depth); return; }
        teleportDepth.remove(player.getUUID());
        boolean anySucceeded = teleportSucceeded.remove(player.getUUID());
        Restore source = teleportSources.remove(player.getUUID());
        if (source == null || !anySucceeded) return;
        View target = observeView(player, "teleport", true);
        rollbackSources.put(player.getUUID(), new Restore(source.dimension, source.pos, source.yaw, source.pitch, target.generation));
    }

    /** A trusted, authenticated Pal-server transaction handler may call this; do not expose it as a guest operation. */
    public static JsonObject rollbackView(ServerPlayer player, String worldSession, long generation) {
        JsonObject result = new JsonObject(); View view = observeView(player); Restore source = rollbackSources.get(player.getUUID());
        if (!session.equals(worldSession) || !view.waitingAck || view.generation != generation || source == null || source.generation != generation) {
            result.addProperty("ok", false); result.addProperty("error", "no_matching_authoritative_source"); return result;
        }
        ServerLevel destination = worlds.get(source.dimension);
        if (destination == null) { result.addProperty("ok", false); result.addProperty("error", "source_dimension_unavailable"); return result; }
        boolean restored;
        rollingBack.add(player.getUUID());
        try {
            restored = player.teleportTo(destination, source.pos.x, source.pos.y, source.pos.z, Set.of(), source.yaw, source.pitch, false);
        } finally { rollingBack.remove(player.getUUID()); }
        result.addProperty("ok", restored);
        if (restored) {
            rollbackSources.remove(player.getUUID());
            result.add("world_view", beginViewTransition(player, "rollback"));
            result.addProperty("waiting_ack", true);
        } else result.addProperty("error", "vanilla_rollback_failed");
        return result;
    }

    /** Prevent stale host coordinates from moving a player back immediately after a real MC dimension transfer. */
    public static boolean acceptsHostPose(ServerPlayer player, JsonObject request) {
        if (server == null || player.level().getServer() != server) return false;
        View view = observeView(player);
        if (view.waitingAck) return false;
        if (request.has("session") && !request.get("session").getAsString().equals(session)) return false;
        if (request.has("dim") && !request.get("dim").getAsString().equals(view.dimension)) return false;
        if (request.has("view") && request.get("view").getAsLong() != view.generation) return false;
        // Existing pose senders remain usable in their initial overworld view only.
        return view.generation == 1 && view.dimension.equals(OVERWORLD)
            || request.has("session") && request.has("dim") && request.has("view");
    }

    public static JsonObject acknowledgeView(ServerPlayer player, JsonObject request) {
        View view = observeView(player); JsonObject result = new JsonObject();
        boolean applied = request.has("applied") && request.get("applied").getAsBoolean();
        boolean matches = applied && request.has("session") && session.equals(request.get("session").getAsString())
            && request.has("dim") && view.dimension.equals(request.get("dim").getAsString())
            && request.has("view") && view.generation == request.get("view").getAsLong();
        result.addProperty("ok", matches);
        if (matches) { view.waitingAck = false; rollbackSources.remove(player.getUUID()); }
        else result.addProperty("error", applied ? "stale_world_view" : "host_projection_not_applied");
        result.addProperty("session", session); result.addProperty("dim", view.dimension); result.addProperty("view", view.generation);
        result.addProperty("waiting_ack", view.waitingAck);
        return result;
    }

    public static void portalEnter(ServerLevel level, Entity entity, Portal portal, BlockPos pos) {
        if (!observing(level) || !(entity instanceof ServerPlayer player)) return;
        PortalContact previous = portals.get(player.getUUID());
        PortalContact current = new PortalContact(dimension(level), pos.immutable(), portal.getClass().getSimpleName(), server.getTickCount());
        portals.put(player.getUUID(), current);
        if (previous != null && previous.dimension.equals(current.dimension) && previous.kind.equals(current.kind)
                && previous.lastTick >= server.getTickCount()-2) return;
        JsonObject event = lifecycle("portal_enter"); event.addProperty("player", player.getUUID().toString());
        event.addProperty("kind", current.kind); event.add("at", WorldStateCodec.at(pos));
        event.addProperty("travel", "vanilla"); emitLifecycle(current.dimension, event);
    }

    public static void explosion(ServerLevel level, Vec3 center, float radius, String source, int affectedCount, String interaction) {
        if (!observing(level)) return;
        // Publish actual destruction before effects. The Pal companion must never deal this damage a second time.
        flushChanges(65536);
        JsonObject event = lifecycle("explosion"); event.add("pos", WorldStateCodec.vector(center));
        event.addProperty("r", radius); event.addProperty("src", source); event.addProperty("affected_count", affectedCount);
        event.addProperty("block_interaction", interaction); event.addProperty("effect_only", true);
        event.addProperty("native_damage", false); emitLifecycle(dimension(level), event);
        if (dimension(level).equals(OVERWORLD)) {
            JsonObject legacy = event.deepCopy(); legacy.remove("op"); legacy.addProperty("t", "explosion");
            legacy.addProperty("dim", dimension(level)); legacy.addProperty("session", session);
            Passthrough.events.accept(legacy.toString());
        }
    }

    public static JsonObject status() {
        JsonObject result = new JsonObject(); result.addProperty("ok", server != null);
        result.addProperty("v", PROTOCOL_VERSION); result.addProperty("session", session); result.addProperty("seq", sequence);
        result.addProperty("travel_enabled", TRAVEL_ENABLED);
        result.addProperty("pending_changes", changes.size()); result.addProperty("snapshot_jobs", snapshots.size());
        result.addProperty("moving_pistons", moving.size()); result.addProperty("emitted_ops", emittedOps);
        JsonArray dimensions = new JsonArray(); worlds.keySet().forEach(dimensions::add); result.add("dimensions", dimensions);
        JsonArray recovery = new JsonArray(); resyncRequired.forEach(recovery::add); result.add("resync_required", recovery);
        JsonArray playerViews = new JsonArray();
        views.forEach((owner, view) -> {
            JsonObject info = new JsonObject(); info.addProperty("player", owner.toString()); info.addProperty("dim", view.dimension);
            info.addProperty("view", view.generation); info.addProperty("waiting_ack", view.waitingAck); playerViews.add(info);
        });
        result.add("views", playerViews); return result;
    }
}
