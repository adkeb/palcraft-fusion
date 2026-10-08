package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;
import java.util.*;
import java.util.function.Function;

/** Transport-scoped leases. All ownership/sequence transitions are atomic, including simultaneous reconnects. */
public final class SessionRegistry<C> {
    private record Challenge(JsonObject wire, BridgeIdentity identity, long createdAt) {}
    private static final class Entry {
        final SessionHandle handle; final boolean exclusive;
        long sequence, seenAt;
        Entry(SessionHandle h, boolean exclusive, long now) { handle = h; this.exclusive = exclusive; seenAt = now; }
    }
    private final String world, serverSession, purpose, endpoint;
    private final Function<String, SessionGrant> verifier;
    private final Map<C, Challenge> challenges = new IdentityHashMap<>();
    private final Map<C, Entry> entries = new IdentityHashMap<>();
    private final Map<String, Entry> owners = new HashMap<>();
    private final Map<String, Long> generations = new HashMap<>();
    public static final long IDLE_SECONDS = 30, CHALLENGE_SECONDS = 15;

    public SessionRegistry(String world, String serverSession, String purpose, String endpoint, Function<String, SessionGrant> verifier) {
        this.world = world; this.serverSession = serverSession; this.purpose = purpose; this.endpoint = endpoint; this.verifier = verifier;
    }
    public synchronized JsonObject challenge(C connection, BridgeIdentity expected, long now) {
        if (entries.containsKey(connection)) throw new SecurityException("Already bound");
        JsonObject j = new JsonObject(); j.addProperty("t", "challenge"); j.addProperty("v", 2); j.addProperty("nonce", SessionCrypto.nonce());
        j.addProperty("purpose", purpose); j.addProperty("endpoint", endpoint); j.addProperty("world_id", world);
        j.addProperty("server_session_id", serverSession); j.addProperty("mc_uuid", expected.mcUuid().toString());
        challenges.put(connection, new Challenge(j.deepCopy(), expected, now)); return j;
    }
    public synchronized SessionHandle authenticate(C connection, JsonObject answer, long now) {
        Challenge c = challenges.remove(connection); // one response only; proof cannot be replayed or retried on another transport
        if (c == null || now < c.createdAt || now - c.createdAt > CHALLENGE_SECONDS) throw new SecurityException("Challenge expired");
        if (answer.get("v").getAsInt() != 2) throw new SecurityException("Unsupported session protocol");
        String token = answer.get("grant").getAsString(); SessionGrant g = verifier.apply(token);
        if (!g.identity().equals(c.identity) || !g.identity().worldId().equals(world) || !g.serverSessionId().equals(serverSession))
            throw new SecurityException("Identity does not match connection");
        if (g.issuedAt() > now + 5 || g.expiresAt() <= now || !SessionCrypto.verify(g.holder(), SessionGrant.proofText(purpose, c.wire, token), answer.get("proof").getAsString()))
            throw new SecurityException("Invalid holder proof");
        boolean exclusive = purpose.equals("mc.login") || SessionPolicy.controls(g.scopes());
        if (purpose.equals("mc.login") && !g.scopes().contains("mc.login")) throw new SecurityException("Login scope missing");
        Set<String> granted = g.scopes();
        if (purpose.equals("host.bind") && answer.has("observer") && answer.get("observer").getAsBoolean()) {
            granted = g.scopes().contains("world.read") ? Set.of("world.read") : Set.of();
            exclusive = false;
        }
        Entry old = owners.get(g.identity().key());
        if (exclusive && old != null) throw new SecurityException("Player already has an active connection");
        long generation = generations.merge(g.identity().key(), 1L, Long::sum);
        SessionHandle h = new SessionHandle(g.identity(), serverSession, UUID.randomUUID(), generation, g.expiresAt(), granted, false);
        Entry entry = new Entry(h, exclusive, now); entries.put(connection, entry); if (exclusive) owners.put(g.identity().key(), entry); return h;
    }
    /** LAN native adapters use stdlib HMAC. The guest pins their private device file, then uses the same lease path. */
    public synchronized SessionHandle authenticateHost(C connection, JsonObject answer, GuestCredential pinned, long now) {
        if (!purpose.equals("host.bind")) throw new SecurityException("Wrong authentication purpose");
        Challenge c = challenges.get(connection);
        if (c == null || !pinned.token().equals(answer.get("grant").getAsString())
            || !SessionCrypto.verifyHmac(pinned.hostSecret(), SessionGrant.proofText(purpose, c.wire, pinned.token()), answer.get("proof").getAsString())) {
            challenges.remove(connection); throw new SecurityException("Invalid local host proof");
        }
        JsonObject local = answer.deepCopy();
        local.addProperty("proof", SessionCrypto.sign(pinned.privateKey(), SessionGrant.proofText(purpose, c.wire, pinned.token())));
        return authenticate(connection, local, now);
    }
    public synchronized SessionHandle legacy(C connection, BridgeIdentity expected, long now) {
        Entry exists = entries.get(connection); if (exists != null) return exists.handle;
        if (owners.containsKey(expected.key())) throw new SecurityException("Another connection controls this guest");
        SessionHandle h = new SessionHandle(expected, serverSession, UUID.randomUUID(), generations.merge(expected.key(), 1L, Long::sum),
            Long.MAX_VALUE, Set.of("mc.login", "pose", "input", "gui", "inventory", "world.read", "terrain", "admin", "relay"), true);
        Entry e = new Entry(h, true, now); entries.put(connection, e); owners.put(expected.key(), e); return h;
    }
    public synchronized SessionHandle current(C connection, long now) {
        Entry e = entries.get(connection); return valid(e, now) ? e.handle : null;
    }
    public synchronized SessionHandle registered(C connection) { Entry e = entries.get(connection); return e == null ? null : e.handle; }
    public synchronized List<C> connections() { return List.copyOf(entries.keySet()); }
    public synchronized boolean current(C connection, SessionHandle handle, long now) {
        SessionHandle h = current(connection, now); return h != null && h.sameConnection(handle);
    }
    /** Called again on the game thread, so queued work from a closed socket cannot execute after reconnection. */
    public synchronized boolean runIfCurrent(C connection, SessionHandle handle, long now, Runnable action) {
        if (!current(connection, handle, now)) return false;
        action.run(); return true;
    }
    public synchronized SessionHandle accept(C connection, JsonObject message, long now) {
        Entry e = entries.get(connection); if (!valid(e, now)) throw new SecurityException("Session is detached or expired");
        String scope = SessionPolicy.scope(message.get("t").getAsString());
        if (scope == null || !e.handle.scopes().contains(scope)) throw new SecurityException("Operation is not allowed in this session");
        if (!e.handle.legacy()) {
            if (!message.has("session") || !e.handle.matches(message.getAsJsonObject("session"))) throw new SecurityException("Wrong session/player scope");
            String n = message.has("seq") ? message.get("seq").toString() : "";
            if (!n.matches("[1-9][0-9]{0,17}")) throw new SecurityException("Invalid sequence");
            long seq = Long.parseLong(n); if (seq <= e.sequence) throw new SecurityException("Replayed or reordered message");
            e.sequence = seq;
        }
        e.seenAt = now; return e.handle;
    }
    public synchronized SessionHandle disconnect(C connection) {
        challenges.remove(connection); Entry e = entries.remove(connection); if (e == null) return null;
        if (e.exclusive && owners.get(e.handle.identity().key()) == e) owners.remove(e.handle.identity().key()); return e.handle;
    }
    public synchronized List<C> expired(long now) {
        List<C> result = new ArrayList<>(); for (var row : entries.entrySet()) if (!valid(row.getValue(), now)) result.add(row.getKey());
        for (C c : result) disconnect(c);
        challenges.entrySet().removeIf(e -> now - e.getValue().createdAt > CHALLENGE_SECONDS); return result;
    }
    public synchronized List<SessionHandle> snapshot(long now) { return entries.values().stream().filter(e -> valid(e, now)).map(e -> e.handle).toList(); }
    private static boolean valid(Entry e, long now) { return e != null && now < e.handle.expiresAt() && now >= e.seenAt && now - e.seenAt <= IDLE_SECONDS; }
}
