package dev.rehan.passthrough.session;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.*;
import java.security.KeyPair;
import java.util.*;

/** Local server-admin registration, from an authoritative Pal snapshot. Does not start a service or alter a save. */
public final class SessionEnrollment {
    public static JsonObject presence(Path file, long now) throws IOException {
        JsonObject j = SessionFiles.read(file);
        if (j.get("v").getAsInt() != 2 || !j.get("authority").getAsBoolean()) throw new SecurityException("Snapshot must come from the Pal server");
        long age = now - j.get("updated_unix").getAsLong();
        if (age < -5 || age > 10) throw new SecurityException("Pal online snapshot is stale");
        BridgeIdentity.checkedId(j.get("world_id").getAsString()); BridgeIdentity.checkedId(j.get("server_session_id").getAsString()); return j;
    }
    public static JsonObject initialize(Path root, Path presenceFile, long now) throws IOException {
        JsonObject p = presence(presenceFile, now); Path base = root.toAbsolutePath(); Files.createDirectories(base);
        Path secret = base.resolve("authority-private.json"); JsonObject keys;
        if (Files.exists(secret)) keys = SessionFiles.read(secret);
        else {
            KeyPair pair = SessionCrypto.keys(); keys = new JsonObject(); keys.addProperty("v", 2);
            keys.addProperty("private", SessionCrypto.encode(pair.getPrivate().getEncoded())); keys.addProperty("public", SessionCrypto.encode(pair.getPublic().getEncoded()));
            SessionFiles.write(secret, keys, true);
        }
        String test = SessionCrypto.sign(SessionCrypto.privateKey(keys.get("private").getAsString()), "PalCraft/2/authority-check");
        if (!SessionCrypto.verify(SessionCrypto.publicKey(keys.get("public").getAsString()), "PalCraft/2/authority-check", test)) throw new SecurityException("Authority key pair mismatch");
        JsonObject config = new JsonObject(); config.addProperty("v", 2); config.addProperty("world_id", p.get("world_id").getAsString());
        config.addProperty("server_session_id", p.get("server_session_id").getAsString()); config.addProperty("authority_public", keys.get("public").getAsString());
        config.addProperty("bindings_file", base.resolve("bindings-public.json").toString()); config.addProperty("presence_file", presenceFile.toAbsolutePath().toString());
        config.addProperty("sessions_file", base.resolve("authenticated-sessions.json").toString());
        SessionFiles.write(base.resolve("authority-public.json"), config, false); return config;
    }
    public static GuestCredential enroll(Path root, Path presenceFile, String palUid, String importName, UUID importUuid, long now, long ttl) throws IOException {
        if (ttl < 60 || ttl > SessionGrant.MAX_LIFETIME_SECONDS) throw new IllegalArgumentException("TTL must be 60..86400 seconds");
        JsonObject p = presence(presenceFile, now); String uid = BridgeIdentity.guid(palUid); int matches = 0;
        for (JsonElement e : p.getAsJsonArray("players")) {
            JsonObject row = e.getAsJsonObject(); if (uid.equals(BridgeIdentity.guid(row.get("pal_uid").getAsString()))) matches++;
        }
        if (matches != 1) throw new SecurityException("Registration requires exactly one online authoritative Pal controller for this UID");
        JsonObject config = initialize(root, presenceFile, now);
        BridgeIdentity identity = new IdentityBindings(root.resolve("bindings-public.json")).enroll(config.get("world_id").getAsString(), uid, importName, importUuid);
        KeyPair holder = SessionCrypto.keys(); JsonObject keys = SessionFiles.read(root.resolve("authority-private.json"));
        SessionGrant grant = new SessionGrant(identity, config.get("server_session_id").getAsString(), UUID.randomUUID(), now, now + ttl, holder.getPublic(), SessionGrant.PLAYER_SCOPES);
        String token = grant.signed(SessionCrypto.privateKey(keys.get("private").getAsString()));
        return new GuestCredential(token, grant, holder.getPrivate());
    }
    public static void main(String[] args) throws Exception {
        if (args.length == 0) throw new IllegalArgumentException("init|enroll --root PATH --presence PATH [--pal-uid UUID --credential PATH --import-name NAME --import-uuid UUID --ttl-seconds N]");
        Map<String, String> options = new HashMap<>(); for (int i = 1; i < args.length; i += 2) {
            if (i + 1 == args.length || !args[i].startsWith("--")) throw new IllegalArgumentException("Expected option/value pairs");
            if (options.put(args[i].substring(2), args[i + 1]) != null) throw new IllegalArgumentException("Duplicate option");
        }
        long now = System.currentTimeMillis() / 1000;
        if (args[0].equals("verify")) {
            JsonObject authority = SessionFiles.read(Path.of(required(options, "authority")));
            JsonObject device = SessionFiles.read(Path.of(required(options, "credential")));
            SessionGrant grant = SessionGrant.verified(device.get("grant").getAsString(), SessionCrypto.publicKey(authority.get("authority_public").getAsString()),
                now, authority.get("world_id").getAsString(), authority.get("server_session_id").getAsString());
            JsonObject out = new JsonObject(); out.addProperty("ok", true); out.addProperty("signature_verified", true); out.add("identity", grant.identity().json());
            out.addProperty("server_session_id", grant.serverSessionId()); out.addProperty("expires_at", grant.expiresAt()); System.out.println(out); return;
        }
        Path root = Path.of(required(options, "root")), presence = Path.of(required(options, "presence"));
        JsonObject out = new JsonObject(); out.addProperty("ok", true); out.addProperty("operation", args[0]);
        if (args[0].equals("init")) out.add("config", initialize(root, presence, now));
        else if (args[0].equals("enroll")) {
            String name = options.get("import-name"); UUID uuid = options.containsKey("import-uuid") ? UUID.fromString(options.get("import-uuid")) : null;
            GuestCredential credential = enroll(root, presence, required(options, "pal-uid"), name, uuid, now, Long.parseLong(options.getOrDefault("ttl-seconds", "86400")));
            Path target = Path.of(required(options, "credential")); SessionFiles.write(target, credential.json(), true);
            out.add("identity", credential.grant().identity().json()); out.addProperty("credential_file", target.toAbsolutePath().toString()); out.addProperty("expires_at", credential.grant().expiresAt());
        } else throw new IllegalArgumentException("Unknown command");
        System.out.println(out); // certificate/private keys are deliberately excluded from console output
    }
    private static String required(Map<String, String> options, String key) { return Objects.requireNonNull(options.get(key), "Missing --" + key); }
    private SessionEnrollment() {}
}
