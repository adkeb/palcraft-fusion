package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;
import java.io.IOException;
import java.nio.file.Path;
import java.security.PrivateKey;

/** A device's certificate and holder private key. The latter is never put on the wire. */
public record GuestCredential(String token, SessionGrant grant, PrivateKey privateKey, String hostSecret) {
    public GuestCredential(String token, SessionGrant grant, PrivateKey privateKey) { this(token, grant, privateKey, SessionCrypto.nonce()); }
    public GuestCredential { if (SessionCrypto.decode(hostSecret).length != 32) throw new IllegalArgumentException("Invalid local host key"); }
    public static GuestCredential read(Path path) throws IOException { return from(SessionFiles.read(path)); }
    public static GuestCredential from(JsonObject j) {
        if (j.get("v").getAsInt() != 2) throw new IllegalArgumentException("Unsupported credential schema");
        String token = j.get("grant").getAsString(); SessionGrant grant = SessionGrant.parse(token);
        PrivateKey key = SessionCrypto.privateKey(j.get("holder_private").getAsString());
        String proof = SessionCrypto.sign(key, "PalCraft/2/key-check");
        if (!SessionCrypto.verify(grant.holder(), "PalCraft/2/key-check", proof)) throw new IllegalArgumentException("Credential key does not match certificate");
        return new GuestCredential(token, grant, key, j.get("host_secret").getAsString());
    }
    public JsonObject answer(String purpose, JsonObject challenge, long now) {
        if (now < grant.issuedAt() - 5 || now >= grant.expiresAt()) throw new SecurityException("Credential expired");
        if (!grant.identity().worldId().equals(challenge.get("world_id").getAsString())
            || !grant.serverSessionId().equals(challenge.get("server_session_id").getAsString())
            || !grant.identity().mcUuid().toString().equals(challenge.get("mc_uuid").getAsString())) throw new SecurityException("Challenge is for another player/world");
        JsonObject j = new JsonObject(); j.addProperty("t", "bind"); j.addProperty("v", 2); j.addProperty("grant", token);
        String text = SessionGrant.proofText(purpose, challenge, token);
        j.addProperty("proof", purpose.equals("host.bind") ? SessionCrypto.hmac(hostSecret, text) : SessionCrypto.sign(privateKey, text)); return j;
    }
    public JsonObject json() {
        JsonObject j = new JsonObject(); j.addProperty("v", 2); j.addProperty("grant", token);
        j.addProperty("holder_private", SessionCrypto.encode(privateKey.getEncoded())); j.add("identity", grant.identity().json());
        j.addProperty("host_secret", hostSecret);
        j.addProperty("server_session_id", grant.serverSessionId()); j.addProperty("expires_at", grant.expiresAt()); return j;
    }
}
