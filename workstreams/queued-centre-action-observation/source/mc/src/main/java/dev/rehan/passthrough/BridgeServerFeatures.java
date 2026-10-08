package dev.rehan.passthrough;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.world.phys.Vec3;
import dev.rehan.passthrough.session.BridgeSessions;

/** Each feature contributes its own operations; transport contains no feature switch. */
final class BridgeServerFeatures {
    static void register() {
        registerSession();
        registerWorld();
        registerExchange();
    }

    private static void registerSession() {
        BridgeNetwork.registerOperation("session", "hello", (server, player, query, reply) -> {
            if (!BridgeSessions.authenticated(player)) throw new IllegalStateException("Unauthenticated guest");
            BridgeNetwork.markDriven(player);
            JsonObject result = BridgeSessions.hello(player);
            result.addProperty("mc_epoch",BridgeSessions.mcEpoch());
            result.addProperty("dedicated", server.isDedicatedServer());
            result.addProperty("protocol", BridgePayload.PROTOCOL_VERSION);
            result.add("features", BridgeNetwork.features());
            result.add("feature_flags",BridgeNetwork.featureFlags());
            result.add("world_view",WorldCompatibility.playerView(player));
            reply.accept(result);
            WorldBridge.syncFor(player, 32);
        });
        BridgeNetwork.registerOperation("session", "session_ping", (server, player, query, reply) -> {});
        BridgeNetwork.registerOperation("session", "host_pose", (server, player, query, reply) -> {
            if (!BridgeNetwork.isDriven(player)) return;
            if (!WorldCompatibility.acceptsHostPose(player, worldQuery(query))) return;
            double x = query.get("x").getAsDouble(), y = query.get("y").getAsDouble(), z = query.get("z").getAsDouble();
            if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z) || Math.abs(x) > 29999900 || Math.abs(z) > 29999900) return;
            player.setPos(x, y, z);
            player.setDeltaMovement(Vec3.ZERO);
            player.setOnGround(query.get("grounded").getAsBoolean());
            player.resetFallDistance();
        });
    }

    private static void registerWorld() {
        BridgeNetwork.registerOperation("world", "ground", (server, player, query, reply) -> {
            if (!BridgeNetwork.isDriven(player)) return;
            if (!WorldCompatibility.acceptsHostPose(player, worldQuery(query))) return;
            JsonArray array = query.getAsJsonArray("c");
            if (array.size() > 8192 || array.size() % 4 != 0) throw new IllegalArgumentException("Invalid terrain batch");
            int[] columns = new int[array.size()];
            for (int i = 0; i < columns.length; i++) columns[i] = array.get(i).getAsInt();
            WorldBridge.solid(player.level(), columns);
        });
        BridgeNetwork.registerOperation("world", "blocksync", (server, player, query, reply) -> {
            int radius = Math.clamp(query.has("r") ? query.get("r").getAsInt() : 32, 1, 64);
            String requestId = query.has("request_id") ? query.get("request_id").getAsString() : null;
            if (query.has("required_bounds"))
                WorldCompatibility.syncFor(player, radius, requestId, BridgeTravelGate.snapshotBounds(server, player, query));
            else WorldBridge.syncFor(player, radius, requestId);
        });
        BridgeNetwork.registerOperation("world", "inspect", (server, player, query, reply) -> WorldBridge.inspect(reply));
        BridgeNetwork.registerOperation("world", "blockinspect", (server, player, query, reply) ->
            WorldBridge.inspectAt(player.level(), query.get("x").getAsInt(), query.get("y").getAsInt(), query.get("z").getAsInt(), reply));
        BridgeNetwork.registerOperation("world", "worldcompat_status", (server, player, query, reply) -> reply.accept(WorldCompatibility.status()));
        BridgeNetwork.registerOperation("world", "world_view_sync", (server, player, query, reply) ->
            reply.accept(WorldCompatibility.syncPendingView(player)));
        BridgeNetwork.registerOperation("travel", "travel_status", (server, player, query, reply) -> reply.accept(BridgeTravelGate.status()));
        for(String operation:new String[]{"travel_ready","travel_observed","travel_abort"})BridgeNetwork.registerOperation("travel",operation,BridgeTravelGate::clientSignal);
        BridgeNetwork.registerOperation("world", "world_view_ack", (server, player, query, reply) -> {
            JsonObject result=new JsonObject();result.addProperty("ok",false);result.addProperty("error","requires_authoritative_travel_ack");reply.accept(result);
        });
    }

    /** The outer session belongs to authentication; world lifetime is a separate namespace. */
    private static JsonObject worldQuery(JsonObject query) {
        JsonObject world = query.deepCopy();
        if (query.has("world_session")) world.add("session", query.get("world_session"));
        else if (world.has("session") && !world.get("session").isJsonPrimitive()) world.remove("session");
        return world;
    }

    private static void registerExchange() {
        BridgeNetwork.registerOperation("exchange", "exchange_balance", (server, player, query, reply) -> {
            if(!BridgeNetwork.exchangeEnabled()){reply.accept(BridgeNetwork.exchangeUnavailable());return;}
            ResourceExchange.balances(player.getUUID(), reply);
        });
        BridgeNetwork.registerOperation("exchange", "exchange", (server, player, query, reply) -> {
            if(!BridgeNetwork.exchangeEnabled()){reply.accept(BridgeNetwork.exchangeUnavailable());return;}
            if(WorldCompatibility.waitingForView(player)){JsonObject result=new JsonObject();result.addProperty("ok",false);result.addProperty("error","world_view_not_ready");reply.accept(result);return;}
            ResourceExchange.request(player.getUUID(), query.get("material").getAsString(), query.get("to_mc").getAsBoolean(), query.get("count").getAsInt(), reply);
        });
    }

    private BridgeServerFeatures() {}
}
