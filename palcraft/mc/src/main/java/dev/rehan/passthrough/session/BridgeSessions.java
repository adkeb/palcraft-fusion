package dev.rehan.passthrough.session;

import com.google.gson.*;
import dev.rehan.passthrough.Passthrough;
import io.netty.buffer.Unpooled;
import java.io.IOException;
import java.nio.file.*;
import java.security.PublicKey;
import java.util.*;
import java.util.concurrent.*;
import net.fabricmc.fabric.api.event.lifecycle.v1.*;
import net.fabricmc.fabric.api.networking.v1.*;
import net.fabricmc.fabric.api.networking.v1.context.*;
import net.minecraft.network.Connection;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.server.level.ServerPlayer;

/** Login admission and bridge scoping share the actual Fabric connection, never a payload's player UUID. */
public final class BridgeSessions {
    public static final Identifier LOGIN = Identifier.parse("passthrough:session_login_v2");
    private record Config(String world, String palSession, PublicKey authority, IdentityBindings bindings, Path presence, Path sessions) {}
    private record Presence(Config config, Set<String> players, long observedAt) {}
    private static final SessionFiles.PresenceReadCache<Presence> presenceReads = new SessionFiles.PresenceReadCache<>();
    private static boolean presenceReadWarned;
    private static volatile Config config;
    private static String configFingerprint;
    private static volatile SessionRegistry<Connection> registry;
    private static volatile Set<String> present = Set.of();
    private static volatile long presenceAt;
    private static final Map<UUID, ServerPlayer> players = new ConcurrentHashMap<>();
    private static final String MC_EPOCH = UUID.randomUUID().toString();
    private static boolean initialized;
    private static int ticks;
    public static boolean strict() { return System.getProperty("palcraft.sessions.mode", "legacy").equals("strict"); }
    public static String mcEpoch() { return MC_EPOCH; }
    private static long now() { return System.currentTimeMillis() / 1000; }
    private static Connection connection(PacketContextProvider provider) { return provider.getPacketContext().orElseThrow(PacketContext.CONNECTION); }

    public static synchronized void initialize() {
        if (initialized) return; initialized = true;
        ServerLoginConnectionEvents.QUERY_START.register((listener, server, sender, synchronizer) -> {
            if (!strict() || !server.isDedicatedServer()) return;
            try {
                Config cfg = configuration(); refreshPresence();
                var profile = loginProfile(listener);
                BridgeIdentity expected = cfg.bindings.find(profile.id());
                if (expected == null || !expected.worldId().equals(cfg.world) || !expected.mcName().equals(profile.name()) || !present.contains(expected.palUid()))
                    throw new SecurityException("MC profile is not registered to an online Pal player");
                JsonObject challenge = registry.challenge(connection(listener), expected, now());
                sender.sendPacket(LOGIN, new FriendlyByteBuf(Unpooled.buffer()).writeUtf(challenge.toString(), 8192));
            } catch (RuntimeException | IOException e) { listener.disconnect(Component.literal("PalCraft: " + e.getMessage())); }
        });
        ServerLoginNetworking.registerGlobalReceiver(LOGIN, (server, listener, understood, data, synchronizer, responseSender) -> {
            if (!strict() || !server.isDedicatedServer()) return;
            String raw;
            try { raw = understood ? data.readUtf(16384) : null; }
            catch (RuntimeException e) { listener.disconnect(Component.literal("PalCraft: invalid login response")); return; }
            CompletableFuture<Void> checked = new CompletableFuture<>(); synchronizer.waitFor(checked);
            server.execute(() -> {
                try {
                    if (raw == null || registry == null) throw new SecurityException("Registered PalCraft guest required");
                    refreshPresence();
                    SessionHandle h = registry.authenticate(connection(listener), JsonParser.parseString(raw).getAsJsonObject(), now());
                    if (!present.contains(h.identity().palUid())) { registry.disconnect(connection(listener)); throw new SecurityException("Pal player disconnected"); }
                    // Registration is the allowlist: a new, verified Pal guest can enter without a manual MC command.
                    var profile = loginProfile(listener);
                    var nameAndId = new net.minecraft.server.players.NameAndId(profile);
                    var whitelist = server.getPlayerList().getWhiteList();
                    if (!whitelist.isWhiteListed(nameAndId)) whitelist.add(new net.minecraft.server.players.UserWhiteListEntry(nameAndId));
                } catch (RuntimeException | IOException e) { listener.disconnect(Component.literal("PalCraft: " + e.getMessage())); }
                finally { checked.complete(null); }
            });
        });
        ServerLoginConnectionEvents.DISCONNECT.register((listener, server) -> { if (registry != null) registry.disconnect(connection(listener)); });
        ServerPlayConnectionEvents.JOIN.register((handler, sender, server) -> {
            if (!strict() || !server.isDedicatedServer()) return;
            SessionHandle h = registry == null ? null : registry.current(connection(handler), now());
            if (h == null || !h.identity().mcUuid().equals(handler.player.getUUID())) {
                handler.disconnect(Component.literal("PalCraft: login identity mismatch")); return;
            }
            players.put(handler.player.getUUID(), handler.player);
        });
        ServerPlayConnectionEvents.DISCONNECT.register((handler, server) -> disconnect(handler.player));
        ServerLifecycleEvents.SERVER_STOPPED.register(server -> { players.clear(); registry = null; config = null; configFingerprint = null; present = Set.of(); presenceAt = 0; presenceReads.clear(); presenceReadWarned = false; });
        ServerTickEvents.END_SERVER_TICK.register(server -> {
            if (!strict() || !server.isDedicatedServer() || registry == null || ++ticks % 20 != 0) return;
            try { refreshPresence(); }
            catch (RuntimeException | IOException e) {
                if (!present.isEmpty()) Passthrough.LOG.warn("Pal presence rejected: {}", e.getClass().getSimpleName());
                present = Set.of(); presenceAt = 0; presenceReads.clear(); presenceReadWarned = false;
            }
            for (Connection c : registry.expired(now())) c.disconnect(Component.literal("PalCraft: guest session expired; reconnect to resume"));
            for (ServerPlayer p : List.copyOf(players.values())) {
                if (identity(p) == null) p.connection.disconnect(Component.literal("PalCraft: Pal player/session disconnected"));
            }
            if (ticks % 40 == 0) try { publishSessions(); } catch (IOException e) { Passthrough.LOG.warn("session snapshot: {}", e.toString()); }
        });
    }
    private static synchronized Config configuration() throws IOException {
        String file = System.getProperty("palcraft.sessions.authority", "");
        if (file.isBlank()) throw new IOException("Missing -Dpalcraft.sessions.authority");
        JsonObject j = SessionFiles.read(Path.of(file)); if (j.get("v").getAsInt() != 2) throw new IOException("Unsupported authority config");
        String fingerprint = String.join("\n", j.get("world_id").getAsString(), j.get("server_session_id").getAsString(), j.get("authority_public").getAsString(),
            j.get("bindings_file").getAsString(), j.get("presence_file").getAsString(), j.get("sessions_file").getAsString());
        if (config != null && registry != null && fingerprint.equals(configFingerprint)) return config;
        presenceReads.clear(); presenceReadWarned = false;
        if (registry != null) {
            SessionRegistry<Connection> previous = registry;
            for (Connection connection : previous.connections()) { previous.disconnect(connection); connection.disconnect(Component.literal("PalCraft: authority session renewed; reconnect to resume")); }
            players.clear(); present = Set.of(); presenceAt = 0;
        }
        config = new Config(BridgeIdentity.checkedId(j.get("world_id").getAsString()), BridgeIdentity.checkedId(j.get("server_session_id").getAsString()),
            SessionCrypto.publicKey(j.get("authority_public").getAsString()), new IdentityBindings(Path.of(j.get("bindings_file").getAsString())),
            Path.of(j.get("presence_file").getAsString()), Path.of(j.get("sessions_file").getAsString()));
        Config c = config;
        registry = new SessionRegistry<>(c.world, c.palSession, "mc.login", "mc:" + MC_EPOCH,
            token -> SessionGrant.verified(token, c.authority, now(), c.world, c.palSession));
        configFingerprint = fingerprint;
        return c;
    }
    /** Use Minecraft's actual connection profile during the early Fabric login-query phase. */
    private static com.mojang.authlib.GameProfile loginProfile(net.minecraft.server.network.ServerLoginPacketListenerImpl listener) {
        var profile = ((dev.rehan.passthrough.mixin.SessionLoginAccessor) listener).palcraft$authenticatedProfile();
        if (profile == null) throw new SecurityException("MC login profile is not ready");
        return profile;
    }
    private static void refreshPresence() throws IOException {
        Config c = configuration(); long clock = now();
        Presence p = presenceReads.read(() -> {
            JsonObject row = SessionEnrollment.presence(c.presence, clock);
            if (!c.world.equals(row.get("world_id").getAsString()) || !c.palSession.equals(row.get("server_session_id").getAsString()))
                throw new SecurityException("Pal server/world changed; refresh registration config");
            Set<String> online = new HashSet<>();
            for (JsonElement e : row.getAsJsonArray("players")) online.add(BridgeIdentity.guid(e.getAsJsonObject().get("pal_uid").getAsString()));
            return new Presence(c, Set.copyOf(online), row.get("updated_unix").getAsLong());
        }, previous -> previous.config == c && clock - previous.observedAt >= -5 && clock - previous.observedAt <= 10);
        if (c != config) throw new SecurityException("Pal authority changed during presence read");
        present = p.players; presenceAt = p.observedAt;
        String retained = presenceReads.retainedAfter();
        if (retained != null && !presenceReadWarned)
            Passthrough.LOG.warn("Pal presence read {}: retained original observed snapshot at {} within existing freshness", retained, presenceAt);
        presenceReadWarned = retained != null;
    }
    public static BridgeIdentity identity(ServerPlayer player) {
        if (!strict() || registry == null || players.get(player.getUUID()) != player || now() - presenceAt > 10) return null;
        SessionHandle h = registry.current(connection(player.connection), now());
        return h != null && h.identity().mcUuid().equals(player.getUUID()) && present.contains(h.identity().palUid()) ? h.identity() : null;
    }
    public static BridgeIdentity identity(UUID uuid) { ServerPlayer p = players.get(uuid); return p == null ? null : identity(p); }
    public static boolean authenticated(ServerPlayer p) { return !strict() || identity(p) != null; }
    public static SessionHandle handle(ServerPlayer p) { return identity(p) == null ? null : registry.current(connection(p.connection), now()); }
    public static JsonObject hello(ServerPlayer p) {
        JsonObject result = new JsonObject(); SessionHandle h = handle(p);
        result.addProperty("ok", !strict() || h != null); result.addProperty("uuid", p.getUUID().toString());
        result.addProperty("legacy", !strict()); if (h != null) result.add("session", h.json()); return result;
    }
    public static boolean require(ServerPlayer p, JsonObject q) {
        if (!strict()) return true;
        try { if (identity(p) == null) return false; registry.accept(connection(p.connection), q, now()); return true; }
        catch (RuntimeException e) { Passthrough.LOG.debug("session request rejected for {}: {}", p.getUUID(), e.getMessage()); return false; }
    }
    public static void disconnect(ServerPlayer p) {
        players.remove(p.getUUID(), p); if (registry != null) registry.disconnect(connection(p.connection));
    }
    /** Add to every bridge reply, including the initial hello. A callback after disconnect has no live envelope. */
    public static JsonObject envelope(ServerPlayer p, JsonObject out) {
        if (!strict()) return out; SessionHandle h = handle(p); if (h == null) return null;
        out.add("session", h.json()); return out;
    }
    public static JsonObject eventFor(ServerPlayer p, String raw) {
        JsonObject out = new JsonObject(); out.addProperty("t", "event"); out.addProperty("data", raw); return envelope(p, out);
    }
    private static void publishSessions() throws IOException {
        Config c = config; if (c == null) return;
        JsonObject out = new JsonObject(); out.addProperty("v", 2); out.addProperty("world_id", c.world); out.addProperty("server_session_id", c.palSession);
        out.addProperty("mc_epoch", MC_EPOCH); out.addProperty("updated_unix", now()); JsonArray rows = new JsonArray();
        for (ServerPlayer p : players.values()) { SessionHandle h = handle(p); if (h != null) rows.add(h.json()); }
        out.add("sessions", rows); SessionFiles.write(c.sessions, out, false);
    }
    private BridgeSessions() {}
}
