package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/** Fresh for every transport connection, with a generation for reconnects of the same persistent identity. */
public record SessionHandle(BridgeIdentity identity, String serverSessionId, UUID sessionId, long generation,
                            long expiresAt, Set<String> scopes, boolean legacy) {
    public SessionHandle { Objects.requireNonNull(identity); Objects.requireNonNull(sessionId); scopes = Set.copyOf(scopes); }
    public JsonObject json() {
        JsonObject j = identity.json(); j.addProperty("v", 2); j.addProperty("server_session_id", serverSessionId);
        j.addProperty("session_id", sessionId.toString()); j.addProperty("generation", generation); j.addProperty("expires_at", expiresAt);
        j.addProperty("legacy", legacy); return j;
    }
    public boolean matches(JsonObject j) {
        try {
            return j.get("v").getAsInt() == 2 && identity.equals(BridgeIdentity.from(j))
                && serverSessionId.equals(j.get("server_session_id").getAsString()) && sessionId.toString().equals(j.get("session_id").getAsString())
                && generation == j.get("generation").getAsLong();
        } catch (RuntimeException e) { return false; }
    }
    public boolean sameConnection(SessionHandle other) {
        return other != null && sessionId.equals(other.sessionId) && generation == other.generation && identity.equals(other.identity);
    }
    public static SessionHandle from(JsonObject j, Set<String> scopes) {
        if (j.get("v").getAsInt() != 2) throw new IllegalArgumentException("Unsupported session protocol");
        return new SessionHandle(BridgeIdentity.from(j), j.get("server_session_id").getAsString(), UUID.fromString(j.get("session_id").getAsString()),
            j.get("generation").getAsLong(), j.get("expires_at").getAsLong(), scopes, j.has("legacy") && j.get("legacy").getAsBoolean());
    }
}
