package dev.rehan.passthrough.client;

import com.google.gson.*;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.session.*;
import io.netty.buffer.Unpooled;
import java.io.IOException;
import java.nio.file.Path;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicLong;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.networking.v1.*;
import net.minecraft.client.Minecraft;
import net.minecraft.network.FriendlyByteBuf;

/** One guest process owns one persistent MC profile. Login/WS reconnects do not replace it. */
public final class GuestSession {
    private static volatile SessionHandle current;
    private static SessionHandle sequenceOwner;
    private static volatile GuestCredential credential;
    private static final AtomicLong epoch = new AtomicLong(), sequence = new AtomicLong();
    private static boolean initialized; private static int ticks;
    public static boolean strict() { return BridgeSessions.strict(); }
    public static long epoch() { return epoch.get(); }
    public static SessionHandle current() { return current; }
    public static GuestCredential credential() throws IOException {
        String path = System.getProperty("palcraft.session.credential", "");
        if (path.isBlank()) throw new IOException("Missing -Dpalcraft.session.credential");
        return GuestCredential.read(Path.of(path));
    }
    public static synchronized void initialize() {
        if (initialized) return; initialized = true;
        ClientLoginNetworking.registerGlobalReceiver(BridgeSessions.LOGIN, (client, listener, data, callbacks) -> {
            if (!strict()) return CompletableFuture.completedFuture(null);
            try {
                JsonObject challenge = JsonParser.parseString(data.readUtf(8192)).getAsJsonObject(); credential = credential();
                JsonObject answer = credential.answer("mc.login", challenge, System.currentTimeMillis() / 1000);
                return CompletableFuture.completedFuture(new FriendlyByteBuf(Unpooled.buffer()).writeUtf(answer.toString(), 16384));
            } catch (RuntimeException | IOException e) { Passthrough.LOG.warn("guest login: {}", e.getMessage()); return CompletableFuture.completedFuture(null); }
        });
        ClientPlayConnectionEvents.JOIN.register((handler, sender, client) -> { current = null; epoch.incrementAndGet(); HostState.clearPose(); });
        ClientPlayConnectionEvents.DISCONNECT.register((handler, client) -> { current = null; epoch.incrementAndGet(); HostState.clearPose(); PlayerSync.reset(); HostLink.sharedSessionChanged(); HostLink.releaseInput(); });
        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            if (!strict() || ++ticks % 100 != 0 || !ready()) return;
            JsonObject q = new JsonObject(); q.addProperty("t", "session_ping"); ClientBridge.send(q);
        });
    }
    public static boolean ready() {
        Minecraft mc = Minecraft.getInstance(); SessionHandle h = current;
        return !strict() || (h != null && mc.player != null && mc.level != null && h.identity().mcUuid().equals(mc.player.getUUID()) && System.currentTimeMillis() / 1000 < h.expiresAt());
    }
    public static boolean scope(JsonObject q) {
        if (!strict()) return true;
        if (q.get("t").getAsString().equals("hello")) { q.addProperty("v", 2); return true; }
        if (!ready()) return false; q.add("session", current.json()); q.addProperty("seq", sequence.incrementAndGet()); return true;
    }
    public static boolean acceptHello(JsonObject result) { return acceptHello(result, epoch()); }
    public static boolean acceptHello(JsonObject result, long expectedEpoch) {
        if (!strict()) return true;
        try {
            if (expectedEpoch != epoch() || credential == null || !result.get("ok").getAsBoolean()) return false;
            SessionHandle h = SessionHandle.from(result.getAsJsonObject("session"), credential.grant().scopes());
            Minecraft mc = Minecraft.getInstance();
            if (h.legacy() || !h.identity().equals(credential.grant().identity()) || !h.serverSessionId().equals(credential.grant().serverSessionId())
                || mc.player == null || !h.identity().mcUuid().equals(mc.player.getUUID())) return false;
            SessionHandle previous = current; current = h;
            // A play-protocol reconfiguration may keep the same Fabric connection and server lease.
            if (sequenceOwner == null || !sequenceOwner.sameConnection(h)) { sequenceOwner = h; sequence.set(0); }
            if (previous == null || !previous.sameConnection(h)) HostLink.sharedSessionChanged();
            return true;
        } catch (RuntimeException e) { return false; }
    }
    public static boolean acceptEvent(JsonObject wrapper) {
        if (!strict()) return true;
        return ready() && wrapper.has("session") && current.matches(wrapper.getAsJsonObject("session"));
    }
    /** Initial hello is checked against its pending request epoch; all subsequent replies must match this connection. */
    public static boolean acceptReply(JsonObject wrapper) { return acceptEvent(wrapper); }
    private GuestSession() {}
}
