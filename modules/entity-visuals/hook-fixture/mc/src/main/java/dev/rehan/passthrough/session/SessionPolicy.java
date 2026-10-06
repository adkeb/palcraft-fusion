package dev.rehan.passthrough.session;

import java.util.Set;

/** The guest transport may affect only the bound player's local input and its shared world. */
public final class SessionPolicy {
    public static String scope(String operation) {
        return switch (operation) {
            case "cam", "host_pose", "world_view_ack", "travel_ready", "travel_observed", "travel_abort" -> "pose";
            case "key", "mode", "slot", "scroll" -> "input";
            case "inventory_toggle", "pointer", "wheel", "gui_key", "text", "hud", "view" -> "gui";
            case "inspect", "blockinspect", "blocksync", "worldcompat_status", "travel_status", "sign_text_view", "entity_visual_view", "material_tint_query" -> "world.read";
            case "ground" -> "terrain";
            case "exchange", "exchange_balance" -> "inventory";
            case "gta", "gtastate", "gtainfo", "director" -> "relay";
            case "cmd", "clear", "shutdown", "projhit", "peds", "mobdmg", "spawnmobs", "mobsclear", "portal", "netheroff", "nethersync", "glide" -> "admin";
            case "session_ping", "hello" -> "mc.login";
            default -> null;
        };
    }
    public static boolean controls(Set<String> scopes) { return scopes.contains("pose") || scopes.contains("input") || scopes.contains("gui"); }
    public static boolean legacyRead(String type) { return Set.of("inspect", "blockinspect", "blocksync").contains(type); }
    private SessionPolicy() {}
}
