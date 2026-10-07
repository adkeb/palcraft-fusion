package dev.rehan.passthrough.session;

import com.google.gson.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;

/** An authority-signed, world/boot/player-bound public certificate and a holder proof. */
public record SessionGrant(BridgeIdentity identity, String serverSessionId, UUID credentialId,
                           long issuedAt, long expiresAt, PublicKey holder, Set<String> scopes) {
    public static final long MAX_LIFETIME_SECONDS = 86400;
    public static final Set<String> PLAYER_SCOPES = Set.of("mc.login", "pose", "input", "gui", "inventory", "world.read", "terrain");
    private static final Set<String> KNOWN_SCOPES = Set.of("mc.login", "pose", "input", "gui", "inventory", "world.read", "terrain", "admin", "relay");
    public SessionGrant {
        Objects.requireNonNull(identity); Objects.requireNonNull(credentialId); Objects.requireNonNull(holder);
        serverSessionId = BridgeIdentity.checkedId(serverSessionId);
        scopes = Set.copyOf(scopes);
        if (issuedAt < 0 || expiresAt <= issuedAt || expiresAt - issuedAt > MAX_LIFETIME_SECONDS)
            throw new IllegalArgumentException("Invalid grant lifetime");
        if (scopes.isEmpty() || !KNOWN_SCOPES.containsAll(scopes)) throw new IllegalArgumentException("Invalid grant scopes");
    }
    public JsonObject json() {
        JsonObject j = identity.json(); j.addProperty("v", 2);
        j.addProperty("server_session_id", serverSessionId); j.addProperty("credential_id", credentialId.toString());
        j.addProperty("issued_at", issuedAt); j.addProperty("expires_at", expiresAt);
        j.addProperty("holder_public", SessionCrypto.encode(holder.getEncoded()));
        JsonArray a = new JsonArray(); new TreeSet<>(scopes).forEach(a::add); j.add("scopes", a); return j;
    }
    public String signed(PrivateKey authority) {
        String payload = SessionCrypto.encode(json().toString().getBytes(StandardCharsets.UTF_8));
        return payload + "." + SessionCrypto.sign(authority, "PalCraft/2/grant\n" + payload);
    }
    public static SessionGrant verified(String token, PublicKey authority, long now, String world, String serverSession) {
        String[] parts = token.split("\\.", -1);
        if (parts.length != 2 || token.length() > 8192 || !SessionCrypto.verify(authority, "PalCraft/2/grant\n" + parts[0], parts[1]))
            throw new SecurityException("Invalid authority signature");
        SessionGrant g = parse(token);
        if (!g.identity.worldId().equals(world) || !g.serverSessionId.equals(serverSession)) throw new SecurityException("Wrong Pal world/server session");
        if (g.issuedAt > now + 5 || g.expiresAt <= now) throw new SecurityException("Grant expired or not yet valid");
        return g;
    }
    /** Parse a local credential or a certificate already checked by verified(). This does not establish trust. */
    public static SessionGrant parse(String token) {
        String[] parts = token.split("\\.", -1);
        if (parts.length != 2 || token.length() > 8192) throw new IllegalArgumentException("Invalid grant encoding");
        JsonObject j = JsonParser.parseString(new String(SessionCrypto.decode(parts[0]), StandardCharsets.UTF_8)).getAsJsonObject();
        if (j.get("v").getAsInt() != 2) throw new IllegalArgumentException("Unsupported session protocol");
        Set<String> scopes = new HashSet<>(); for (JsonElement e : j.getAsJsonArray("scopes")) scopes.add(e.getAsString());
        return new SessionGrant(BridgeIdentity.from(j), j.get("server_session_id").getAsString(), UUID.fromString(j.get("credential_id").getAsString()),
            j.get("issued_at").getAsLong(), j.get("expires_at").getAsLong(), SessionCrypto.publicKey(j.get("holder_public").getAsString()), scopes);
    }
    public static String proofText(String purpose, JsonObject challenge, String grant) {
        if (!Set.of("mc.login", "host.bind").contains(purpose)) throw new IllegalArgumentException("Invalid proof purpose");
        return "PalCraft/2/" + purpose + "\n" + challenge.get("nonce").getAsString() + "\n"
            + challenge.get("endpoint").getAsString() + "\n" + challenge.get("world_id").getAsString() + "\n"
            + challenge.get("server_session_id").getAsString() + "\n" + challenge.get("mc_uuid").getAsString() + "\n" + SessionCrypto.sha256(grant);
    }
}
