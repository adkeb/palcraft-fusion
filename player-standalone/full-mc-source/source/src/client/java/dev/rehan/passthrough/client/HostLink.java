package dev.rehan.passthrough.client;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import dev.rehan.passthrough.MobWar;
import dev.rehan.passthrough.Nether;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.WorldBridge;
import dev.rehan.passthrough.client.signtext.SignTextExporter;
import java.net.InetSocketAddress;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import dev.rehan.passthrough.session.*;
import net.minecraft.client.Minecraft;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

/** A loopback transport for exactly one guest profile; each Pal player runs an independent guest process. */
public final class HostLink extends WebSocketServer {
    private static HostLink instance;
    private volatile SessionRegistry<WebSocket> sessions;
    private final BridgeIdentity expected;
    private volatile String palBoot;
    private final boolean strict;
    private final Set<WebSocket> readers = ConcurrentHashMap.newKeySet();

    private HostLink(int port) {
        super(new InetSocketAddress("127.0.0.1", port));
        setReuseAddr(true); setDaemon(true); strict = GuestSession.strict();
        if (strict) {
            try {
                GuestCredential c = GuestSession.credential(); expected = c.grant().identity();
                palBoot = c.grant().serverSessionId(); sessions = registry(c, port);
            } catch (java.io.IOException e) { throw new IllegalStateException("Strict guest requires its registered credential", e); }
        } else {
            String name = System.getProperty("palcraft.legacyMcName", "PalCraft");
            expected = new BridgeIdentity("legacy-loopback", "00000000-0000-0000-0000-000000000001", BridgeIdentity.offlineUuid(name), name);
            sessions = new SessionRegistry<>(expected.worldId(), "legacy-loopback", "host.bind", "legacy", token -> { throw new SecurityException("Legacy transport"); });
        }
    }
    private static long now() { return System.currentTimeMillis() / 1000; }
    private SessionRegistry<WebSocket> registry(GuestCredential credential, int port) {
        return new SessionRegistry<>(expected.worldId(), credential.grant().serverSessionId(), "host.bind", "host:" + ProcessHandle.current().pid() + ":" + port,
            token -> {
                try {
                    GuestCredential pinned = GuestSession.credential();
                    if (!pinned.token().equals(token) || !expected.equals(pinned.grant().identity())) throw new SecurityException("Certificate is not assigned to this guest");
                    return pinned.grant();
                } catch (java.io.IOException e) { throw new SecurityException("Guest credential unavailable"); }
            });
    }
    private synchronized void refreshCredential(WebSocket opening) {
        try {
            GuestCredential c = GuestSession.credential(); if (!c.grant().identity().equals(expected)) throw new SecurityException("A guest process cannot change its MC profile");
            if (c.grant().serverSessionId().equals(palBoot)) return;
            closeSessions(opening); palBoot = c.grant().serverSessionId(); sessions = registry(c, getPort());
        } catch (java.io.IOException e) { throw new SecurityException("Guest credential unavailable"); }
    }
    private void closeSessions() {
        closeSessions(null);
    }
    private void closeSessions(WebSocket except) {
        for (WebSocket c : getConnections()) { if (c == except) continue; detached(sessions.disconnect(c)); readers.remove(c); c.close(1000, "Shared-world session changed; rebind input"); }
    }
    /** Force native v15 to reconnect and resend mode/held-key state after the MC transport reconnects. */
    static void sharedSessionChanged() { if (instance != null && instance.strict) instance.closeSessions(); }
    static void launch() {
        GuestSession.initialize();
        instance = new HostLink(Integer.getInteger("passthrough.port", 25599)); instance.start();
        Passthrough.events = instance::publish;
    }
    @Override public void onStart() {
        Passthrough.LOG.info("host link listening on 127.0.0.1:{} ({})", getPort(), strict ? "registered session" : "legacy single controller");
    }
    @Override public void onOpen(WebSocket conn, ClientHandshake handshake) {
        if (strict) { try { refreshCredential(conn); } catch (SecurityException e) { conn.close(1008, e.getMessage()); return; } }
        JsonObject hello = new JsonObject(); hello.addProperty("t", "hello"); hello.addProperty("v", 2);
        hello.addProperty("legacy", !strict); hello.addProperty("shm", FrameExporter.NAME); hello.addProperty("pid", ProcessHandle.current().pid());
        if (strict) {
            hello.add("challenge", sessions.challenge(conn, expected, now())); hello.add("identity", expected.json());
        }
        conn.send(hello.toString());
    }
    @Override public void onClose(WebSocket conn, int code, String reason, boolean remote) {
        readers.remove(conn); detached(sessions.disconnect(conn));
        Passthrough.LOG.info("host disconnected ({} {})", code, reason);
    }
    private void detached(SessionHandle handle) {
        if (handle != null && HostState.detach(handle)) {
            PlayFeedback.clearViewportAspect();
            Minecraft.getInstance().execute(() -> { if (HostState.session() == null) { releaseInput(); PlayerSync.reset(); } });
        }
    }
    /** Clear held keys/clicks and close the previous player's local GUI before the next controller input. */
    static void releaseInput() {
        Minecraft mc = Minecraft.getInstance();
        SignTextExporter.unbind();
        SignTextExporter.setTransport(null);
        EntityCaptureExporter.unbind();
        ClientInput.sessionDisconnected();
        if (mc.level != null) ClientInput.modeChanged(false);
    }
    @Override public void onMessage(WebSocket conn, String message) {
        try {
            var registered = new java.util.IdentityHashMap<WebSocket, SessionHandle>();
            for (WebSocket c : getConnections()) registered.put(c, sessions.registered(c));
            for (WebSocket expired : sessions.expired(now())) { readers.remove(expired); detached(registered.get(expired)); expired.close(1008, "Session expired"); }
            JsonObject m = JsonParser.parseString(message).getAsJsonObject(); String type = m.get("t").getAsString();
            if (type.equals("bind")) {
                if (!strict) throw new SecurityException("Use legacy loopback input or configure a registered guest");
                SessionHandle h;
                try { h = sessions.authenticateHost(conn, m, GuestSession.credential(), now()); }
                catch (java.io.IOException e) { throw new SecurityException("Guest credential unavailable"); }
                if (SessionPolicy.controls(h.scopes())) {
                    HostState.bind(h); Minecraft.getInstance().execute(() -> sessions.runIfCurrent(conn, h, now(), () -> { releaseInput(); PlayerSync.reset(); }));
                } else readers.add(conn);
                JsonObject bound = new JsonObject(); bound.addProperty("t", "bound"); bound.add("session", h.json()); conn.send(bound.toString());
                execute(conn,h,()->{
                    JsonObject view=ClientBridge.trustedWorldView();if(view!=null)respond(conn,h,view);
                    if(SessionPolicy.controls(h.scopes()))ClientBridge.requestPendingWorldView();
                });
                return;
            }
            SessionHandle accepted;
            // The current single-player lab's tools use short-lived operator sockets. Preserve them in legacy.
            if (!strict && !type.equals("cam") && sessions.current(conn, now()) == null) {
                readers.add(conn); accepted = null;
            } else {
                if (!strict && sessions.current(conn, now()) == null) {
                    SessionHandle initial = sessions.legacy(conn, expected, now()); HostState.bind(initial);
                    // A legacy host can send its initial mode/key state before its first camera frame.
                    // Closing the previous controller already released old input; do not erase this new state.
                    Minecraft.getInstance().execute(() -> sessions.runIfCurrent(conn, initial, now(), PlayerSync::reset));
                }
                accepted = sessions.accept(conn, m, now());
            }
            final SessionHandle lease = accepted;
            if (strict && (!GuestSession.ready() || lease == null || !lease.identity().equals(GuestSession.current().identity())
                || !lease.serverSessionId().equals(GuestSession.current().serverSessionId()))) throw new SecurityException("MC guest is waiting for its verified shared-world connection");
            if (type.equals("session_ping")) return;
            if (type.equals("cam")) {
                sessions.runIfCurrent(conn, lease, now(), () -> {
                    if (HostState.update(lease, m)) PlayFeedback.updateViewportAspect(m.has("aspect") ? m.get("aspect").getAsDouble() : 0);
                }); return;
            }
            dispatch(conn, lease, m);
        } catch (SecurityException e) {
            JsonObject error = new JsonObject(); error.addProperty("t", "session_error"); error.addProperty("error", e.getMessage());
            if (conn.isOpen()) conn.send(error.toString());
        } catch (RuntimeException e) { Passthrough.LOG.warn("bad host message: {}", e.toString()); }
    }
    private void execute(WebSocket conn, SessionHandle lease, Runnable task) {
        long mcEpoch = GuestSession.epoch();
        Minecraft.getInstance().execute(() -> {
            if (!conn.isOpen() || mcEpoch != GuestSession.epoch() || (strict && !GuestSession.ready())) return;
            if (lease == null) { if (!strict && readers.contains(conn)) task.run(); }
            else sessions.runIfCurrent(conn, lease, now(), task);
        });
    }
    private void respond(WebSocket conn, SessionHandle lease, JsonObject response) {
        if (!conn.isOpen() || (lease != null && !sessions.current(conn, lease, now()))) return;
        JsonObject out = response.deepCopy(); if (strict && lease != null) out.add("host_session", lease.json()); conn.send(out.toString());
    }
    private static String requestId(JsonObject query) {
        if (!query.has("request_id")) return null;
        String id = query.get("request_id").getAsString();
        if (!UUID.fromString(id).toString().equals(id)) throw new IllegalArgumentException("Invalid request_id");
        return id;
    }
    private void respond(WebSocket conn, SessionHandle lease, JsonObject query, JsonObject response) {
        String id = requestId(query); JsonObject out = response.deepCopy();
        if (id != null) out.addProperty("request_id", id);
        respond(conn, lease, out);
    }
    private void dispatch(WebSocket conn, SessionHandle lease, JsonObject m) {
			switch (m.get("t").getAsString()) {
				case "cam" -> HostState.update(lease, m);
				case "ground" -> execute(conn, lease, ()->{if(!HostState.acceptsWorldPacket(m))return;if(ClientBridge.remote())ClientBridge.send(m);else WorldBridge.solid(ints(m.getAsJsonArray("c")));});
                case "travel_ready", "travel_observed", "travel_abort" -> execute(conn, lease, () -> ClientBridge.request(m, r -> respond(conn, lease, r)));
                case "material_tint_query" -> execute(conn, lease, () -> respond(conn, lease, ClientBridge.queryMaterialTint(m)));
                case "entity_visual_view" -> execute(conn, lease, () -> EntityCaptureExporter.bind(m, row -> respond(conn, lease, row)));
                case "sign_text_view" -> execute(conn, lease, () -> {
                    ClientBridge.bindSignText(m);
                    SignTextExporter.setTransport(row -> respond(conn, lease, row));
                });
				case "clear" -> WorldBridge.clearSolid();
				case "cmd" -> WorldBridge.command(m.get("c").getAsString());
				case "gta", "gtastate", "gtainfo", "director" -> this.relay(conn, lease, m.toString());
				case "blockinspect" -> execute(conn, lease, ()->{requestId(m);if(ClientBridge.remote())ClientBridge.request(m,r->{respond(conn, lease, m, r);});else WorldBridge.inspectAt(m.get("x").getAsInt(),m.get("y").getAsInt(),m.get("z").getAsInt(),r -> respond(conn, lease, m, r));});
                case "blocksync" -> execute(conn, lease, ()->{String id=requestId(m);if(ClientBridge.remote())ClientBridge.send(m);else WorldBridge.sync(m.has("r") ? m.get("r").getAsInt() : 48,id);});
				case "shutdown" -> execute(conn, lease, () -> Minecraft.getInstance().stop());
				case "inspect" -> execute(conn, lease, () -> {
                    requestId(m);
					Minecraft mc = Minecraft.getInstance();
					JsonObject report = new JsonObject(); report.addProperty("t", "inspection");
                    report.addProperty("screen",mc.gui.screen()==null ? "none" : mc.gui.screen().getClass().getSimpleName());
                    report.addProperty("host_active",Passthrough.active);
                    report.add("host_camera",HostState.inspection());
                    var target=mc.gameRenderer.mainRenderTarget();
                    if(target!=null){report.addProperty("render_target_width",target.width);report.addProperty("render_target_height",target.height);}
                    var pose=HostState.live();
                    if(pose!=null && pose.groundKnown()) report.addProperty("host_grounded",pose.grounded());
					if (mc.player != null) {
						report.addProperty("name", mc.player.getName().getString());
						report.addProperty("uuid", mc.player.getUUID().toString());
						report.addProperty("creative", mc.player.getAbilities().instabuild);
                        report.addProperty("grounded",mc.player.onGround());
                        report.addProperty("master_volume",mc.options.getSoundSourceOptionInstance(net.minecraft.sounds.SoundSource.MASTER).get());
                        report.addProperty("attack_down",mc.options.keyAttack.isDown());
                        report.addProperty("destroying",mc.gameMode.isDestroying());
						report.addProperty("x", mc.player.getX());report.addProperty("y", mc.player.getY());report.addProperty("z", mc.player.getZ());
						report.addProperty("selected_item", net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(mc.player.getMainHandItem().getItem()).toString());
						JsonArray inventory = new JsonArray();
						for (int i=0;i<mc.player.getInventory().getContainerSize();i++) {
							var stack=mc.player.getInventory().getItem(i);if(stack.isEmpty())continue;
							JsonObject slot=new JsonObject();slot.addProperty("slot",i);slot.addProperty("item",net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(stack.getItem()).toString());slot.addProperty("count",stack.getCount());inventory.add(slot);
						}
						report.add("inventory",inventory);
						if(mc.hitResult instanceof net.minecraft.world.phys.BlockHitResult hit){
							JsonObject aim=new JsonObject();aim.addProperty("type",hit.getType().toString());aim.addProperty("x",hit.getBlockPos().getX());aim.addProperty("y",hit.getBlockPos().getY());aim.addProperty("z",hit.getBlockPos().getZ());aim.addProperty("face",hit.getDirection().toString());report.add("aim",aim);
                            var state=mc.level.getBlockState(hit.getBlockPos());
                            aim.addProperty("block",net.minecraft.core.registries.BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString());
                            float progress=state.getDestroyProgress(mc.player,mc.level,hit.getBlockPos());
                            if(Float.isFinite(progress))aim.addProperty("progress_per_tick",progress);
						}
					}
					if(ClientBridge.remote())ClientBridge.request(m,authority->{report.add("server",authority);respond(conn, lease, m, report);});
                    else WorldBridge.inspect(authority -> {report.add("server",authority);respond(conn, lease, m, report);});
				});
				case "projhit" -> {
					JsonArray at = m.getAsJsonArray("pos");
					WorldBridge.projectileHit(m.get("id").getAsInt(), at.get(0).getAsDouble(), at.get(1).getAsDouble(), at.get(2).getAsDouble(),
						m.has("stick") && m.get("stick").getAsBoolean());
				}
				case "peds" -> {
					JsonArray list = m.getAsJsonArray("p");
					double[] flat = new double[list.size() * 4];
					for (int i = 0; i < list.size(); i++) {
						JsonArray e = list.get(i).getAsJsonArray();
						for (int k = 0; k < 4; k++) {
							flat[i * 4 + k] = e.get(k).getAsDouble();
						}
					}

					MobWar.peds(flat);
				}
				case "mobdmg" -> MobWar.damage(m.get("id").getAsInt(), m.get("d").getAsDouble());
				case "spawnmobs" -> MobWar.spawn(m.get("k").getAsString(), m.has("n") ? m.get("n").getAsInt() : 5,
					m.has("rmin") ? m.get("rmin").getAsDouble() : 8.0, m.has("rmax") ? m.get("rmax").getAsDouble() : 16.0,
					m.has("arc") ? m.get("arc").getAsDouble() : 40.0, m.has("yaw") ? m.get("yaw").getAsDouble() : 0.0,
					m.has("at") ? new double[] {m.getAsJsonArray("at").get(0).getAsDouble(), m.getAsJsonArray("at").get(1).getAsDouble(),
						m.getAsJsonArray("at").get(2).getAsDouble()} : null);
				case "mobsclear" -> MobWar.clearMobs();
				case "portal" -> {
					JsonArray at = m.getAsJsonArray("at");
					Nether.buildPortal(at.get(0).getAsDouble(), at.get(1).getAsDouble(), at.get(2).getAsDouble(), m.get("yaw").getAsFloat());
				}
				case "netheroff" -> Nether.stop();
				case "nethersync" -> Nether.resync();
				case "glide" -> WorldBridge.glide(!m.has("on") || m.get("on").getAsBoolean(), m.has("speed") ? m.get("speed").getAsDouble() : 1.2);
				default -> {
					Minecraft minecraft = Minecraft.getInstance();
					execute(conn, lease, () -> ClientInput.handle(minecraft, m));
				}
			}
    }
    private void publish(String message) {
        if (!dev.rehan.passthrough.BridgeEventPolicy.allows(message)) return;
        ClientBridge.observeLocalEvent(message);
        for (WebSocket c : getConnections()) {
            if (!c.isOpen()) continue;
            SessionHandle h = sessions.current(c, now());
            if (h != null) {
                if (!SessionPolicy.controls(h.scopes()) && !worldEvent(message)) continue;
                if (strict) {
                    try { JsonObject out = JsonParser.parseString(message).getAsJsonObject(); out.add("host_session", h.json()); c.send(out.toString()); }
                    catch (RuntimeException e) { Passthrough.LOG.debug("host event is not JSON"); }
                } else c.send(message);
            } else if (!strict && readers.contains(c) && worldEvent(message)) c.send(message);
        }
    }
    private static boolean worldEvent(String raw) {
        try { String t = JsonParser.parseString(raw).getAsJsonObject().get("t").getAsString(); return t.equals("blocks") || t.equals("drops"); }
        catch (RuntimeException e) { return false; }
    }
    public static void publish(SessionHandle owner, String message) { if (instance != null && HostState.current(owner)) instance.publish(message); }
    private void relay(WebSocket from, SessionHandle lease, String message) {
        if (lease == null) return;
        for (WebSocket c : getConnections()) {
            SessionHandle h = sessions.current(c, now());
            if (c != from && c.isOpen() && h != null && h.identity().equals(lease.identity()) && h.scopes().contains("relay")) c.send(message);
        }
    }
    @Override public void onError(WebSocket conn, Exception e) { Passthrough.LOG.warn("host link error", e); }
    private static int[] ints(JsonArray a) { int[] out = new int[a.size()]; for (int i = 0; i < out.length; i++) out[i] = a.get(i).getAsInt(); return out; }
}
