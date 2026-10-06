package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.UUID;

/** A persistent player identity. The Pal server boot id belongs to a grant, never to this identity. */
public record BridgeIdentity(String worldId, String palUid, UUID mcUuid, String mcName) {
    public BridgeIdentity {
        worldId = checkedId(worldId);
        palUid = guid(palUid);
        if (mcUuid == null || mcUuid.equals(new UUID(0, 0))) throw new IllegalArgumentException("Invalid MC UUID");
        if (mcName == null || !mcName.matches("[A-Za-z0-9_]{1,16}")) throw new IllegalArgumentException("Invalid MC name");
    }

    public String key() { return worldId + "/" + palUid; }

    public JsonObject json() {
        JsonObject j = new JsonObject();
        j.addProperty("world_id", worldId);
        j.addProperty("pal_uid", palUid);
        j.addProperty("mc_uuid", mcUuid.toString());
        j.addProperty("mc_name", mcName);
        return j;
    }

    public static BridgeIdentity from(JsonObject j) {
        return new BridgeIdentity(j.get("world_id").getAsString(), j.get("pal_uid").getAsString(),
            UUID.fromString(j.get("mc_uuid").getAsString()), j.get("mc_name").getAsString());
    }

    public static UUID offlineUuid(String name) {
        return UUID.nameUUIDFromBytes(("OfflinePlayer:" + name).getBytes(StandardCharsets.UTF_8));
    }

    public static String guid(String input) {
        if (input == null) throw new IllegalArgumentException("Missing Pal UID");
        String s = input.toLowerCase(Locale.ROOT);
        if (!s.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}") || s.equals("00000000-0000-0000-0000-000000000000"))
            throw new IllegalArgumentException("Invalid Pal UID");
        return s;
    }

    public static String checkedId(String value) {
        if (value == null || !value.matches("[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}"))
            throw new IllegalArgumentException("Invalid world/server id");
        return value;
    }
}
