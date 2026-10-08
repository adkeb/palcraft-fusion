package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

/** Legacy unscoped teleport broadcasts cannot replace the authenticated world-view protocol. */
public final class BridgeEventPolicy {
    public static boolean allows(JsonObject event) {
        return Boolean.getBoolean("palcraft.legacyPlayerTeleportEvents") || !event.has("t")
            || !event.get("t").getAsString().equals("pteleport");
    }
    public static boolean allows(String raw) {
        if(Boolean.getBoolean("palcraft.legacyPlayerTeleportEvents")||!raw.contains("\"pteleport\""))return true;
        try{return allows(JsonParser.parseString(raw).getAsJsonObject());}
        catch(RuntimeException exception){return false;}
    }
    private BridgeEventPolicy() {}
}
