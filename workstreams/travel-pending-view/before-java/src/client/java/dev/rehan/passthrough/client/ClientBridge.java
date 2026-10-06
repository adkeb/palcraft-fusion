package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import dev.rehan.passthrough.BridgePayload;
import dev.rehan.passthrough.BridgeNetwork;
import dev.rehan.passthrough.BridgeEventPolicy;
import dev.rehan.passthrough.FeatureRegistry;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.ResourceExchange;
import dev.rehan.passthrough.client.signtext.SignTextExporter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.function.Consumer;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.minecraft.client.Minecraft;

/** Feature callbacks use the same player connection as original Minecraft actions. */
final class ClientBridge {
    private record Pending(Consumer<JsonObject> callback, long expires, long epoch, boolean hello) {}
    private record Event(JsonObject message, String raw) {}
    private record WorldView(String session,String dimension,long generation,boolean waitingAck) {}
    private static final Map<String, Pending> pending = new HashMap<>();
    private static final FeatureRegistry<Event> events = new FeatureRegistry<>();
    private static int ticks;
    private static WorldView worldView;
    private static String nativeMcEpoch;

    static boolean worldInteractionsReady() {
        return HostState.worldScopeEnabled()?worldView!=null&&!worldView.waitingAck():HostState.initialOverworldReady();
    }

    private static void observeTrustedWorldView(WorldView view) {
        if(!view.equals(worldView)){PlayerSync.reset();SignTextExporter.unbind();}
        worldView=view;
        HostState.observeWorldView(view.session(),view.dimension(),view.generation(),view.waitingAck());
        if(view.waitingAck())ClientInput.releaseAllHostKeys();
    }

    private static boolean carriesCurrentWorldScope(JsonObject message) {
        WorldView view=worldView;
        if(view==null||view.waitingAck())return false;
        try {
            return message.has("world_session")&&view.session().equals(message.get("world_session").getAsString())
                &&message.has("dim")&&view.dimension().equals(message.get("dim").getAsString())
                &&message.has("view")&&view.generation()==message.get("view").getAsLong();
        }catch(RuntimeException exception){return false;}
    }

    static boolean remote() {
        Minecraft mc = Minecraft.getInstance();
        return mc.player != null && mc.getSingleplayerServer() == null;
    }

    static void registerEvent(String feature, String type, Consumer<JsonObject> handler) {
        events.register(feature, type, event -> handler.accept(event.message()));
    }

    static void bindSignText(JsonObject request) {
        WorldView current=worldView;
        if(current==null)throw new IllegalArgumentException("Authenticated world view unavailable");
        SignTextExporter.bindRequest(request,current.session(),current.dimension(),current.generation(),!current.waitingAck());
    }

    /** Read-only material query stays inside the existing authenticated host lease. */
    static JsonObject queryMaterialTint(JsonObject request) {
        return dev.rehan.passthrough.client.material.MaterialTintFeature.query(request,trustedWorldView());
    }

    /** Replay only the already accepted local view after an authenticated native host rebind. */
    static JsonObject trustedWorldView() {
        Minecraft mc=Minecraft.getInstance();WorldView current=worldView;
        if(current==null||mc.player==null||mc.level==null||!GuestSession.ready()||!HostState.matchesIdentity(mc.player.getUUID()))return null;
        JsonObject event=new JsonObject();event.addProperty("t","blocks");event.addProperty("v",2);
        event.addProperty("session",current.session());event.addProperty("dim",current.dimension());
        com.google.gson.JsonArray lifecycle=new com.google.gson.JsonArray();JsonObject row=new JsonObject();
        row.addProperty("op","player_view");row.addProperty("reason","host_rebind");row.addProperty("player",mc.player.getUUID().toString());
        row.addProperty("to",current.dimension());row.addProperty("view",current.generation());row.addProperty("waiting_ack",current.waitingAck());
        com.google.gson.JsonArray pos=new com.google.gson.JsonArray();pos.add(mc.player.getX());pos.add(mc.player.getY());pos.add(mc.player.getZ());row.add("pos",pos);
        row.addProperty("yaw",mc.player.getYRot());row.addProperty("pitch",mc.player.getXRot());lifecycle.add(row);event.add("lifecycle",lifecycle);
        event.add("set",new com.google.gson.JsonArray());event.add("clear",new com.google.gson.JsonArray());event.add("geometry",new com.google.gson.JsonArray());
        var nativeHandle=GuestSession.current();
        if(nativeHandle!=null&&nativeMcEpoch!=null){JsonObject binding=nativeHandle.json();binding.addProperty("mc_epoch",nativeMcEpoch);event.add("native_binding",binding);}
        JsonObject confirmed=new JsonObject();confirmed.addProperty("player",mc.player.getUUID().toString());
        confirmed.addProperty("world_session",current.session());confirmed.addProperty("dim",current.dimension());
        confirmed.addProperty("view",current.generation());confirmed.addProperty("waiting_ack",current.waitingAck());
        // This client has only confirmed the MC tuple. Native mapping/bounds require separate committed scene evidence.
        confirmed.add("mapping",com.google.gson.JsonNull.INSTANCE);confirmed.add("bounds",com.google.gson.JsonNull.INSTANCE);event.add("world_view",confirmed);
        return event;
    }

    static void initialize() {
        events.register("world", "drops", ClientBridge::publishDrops);
        events.register("world", "blocks", event -> { observeWorldEvent(event.message()); Passthrough.events.accept(event.raw()); });
        registerEvent("world", "world_view_applied", ClientBridge::worldViewApplied);
        registerEvent("entities", "player_vitals", message -> {
            Minecraft mc=Minecraft.getInstance();
            if(mc.player==null||!message.has("mc_uuid")||!mc.player.getUUID().toString().equals(message.get("mc_uuid").getAsString()))return;
            ClientPalLife.observe(message);
            PlayFeedback.updateVitals(message.get("hp").getAsDouble(),message.get("max_hp").getAsDouble(),message.get("shield").getAsDouble(),message.get("max_shield").getAsDouble(),message.get("alive").getAsBoolean(),message.get("dying").getAsBoolean());
        });
        events.freeze();
        ClientPlayNetworking.registerGlobalReceiver(BridgePayload.TYPE, (payload, context) -> context.client().execute(() -> receive(payload.json())));
        ClientPlayConnectionEvents.JOIN.register((handler, sender, client) -> {
            ticks = 0;
            nativeMcEpoch=null;
            ClientPalLife.clear();
            if (remote()) {
                JsonObject query = new JsonObject();
                query.addProperty("t", "hello");
                long expectedEpoch=GuestSession.epoch();
                request(query, result -> {
                    if (!GuestSession.acceptHello(result,expectedEpoch)) {
                        ClientInput.sessionDisconnected();
                        Passthrough.LOG.warn("server session hello rejected for current guest");
                    } else {
                        if(result.has("mc_epoch")&&!result.get("mc_epoch").getAsString().isBlank())nativeMcEpoch=result.get("mc_epoch").getAsString();
                        if(!result.has("world_view"))return;
                        JsonObject view=result.getAsJsonObject("world_view");
                        if(view.has("player")&&Minecraft.getInstance().player!=null&&Minecraft.getInstance().player.getUUID().toString().equals(view.get("player").getAsString()))
                            observeTrustedWorldView(new WorldView(view.get("world_session").getAsString(),view.get("dim").getAsString(),view.get("view").getAsLong(),view.get("waiting_ack").getAsBoolean()));
                    }
                });
            }
        });
        ClientPlayConnectionEvents.DISCONNECT.register((handler, client) -> disconnect());
    }

    private static JsonObject error(String text) {
        JsonObject result = new JsonObject();
        result.addProperty("ok", false);
        result.addProperty("error", text);
        return result;
    }

    private static void complete(Pending request, JsonObject result) {
        try { request.callback().accept(result); }
        catch (RuntimeException exception) { Passthrough.LOG.warn("bridge callback: {}", exception.toString()); }
    }

    private static void disconnect() {
        ArrayList<Pending> requests = new ArrayList<>(pending.values());
        pending.clear();
        ticks = 0;
        worldView = null;
        nativeMcEpoch=null;
        HostState.clearWorldView();
        ClientInput.sessionDisconnected();
        PlayFeedback.clearVitals();
        ClientPalLife.clear();
        SignTextExporter.unbind();
        requests.forEach(request -> complete(request, error("服务器连接已断开")));
    }

    static boolean send(JsonObject query) {
        if (!ClientPlayNetworking.canSend(BridgePayload.TYPE)) return false;
        JsonObject message=query.deepCopy();
        String type=message.get("t").getAsString();
        if(!worldInteractionsReady()&&(type.equals("host_pose")||type.equals("ground")||type.equals("exchange")))return false;
        // Pose scope comes from its captured sample; terrain scope comes from the packet's producer.
        // Never relabel a queued packet with the latest view.
        if((type.equals("host_pose")||type.equals("ground"))&&!HostState.worldScopeEnabled()&&!HostState.scopeInitialWorldPacket(message))return false;
        if((type.equals("host_pose")||type.equals("ground"))&&!carriesCurrentWorldScope(message))return false;
        if(type.equals("ground")&&!HostState.acceptsWorldPacket(message))return false;
        if (!GuestSession.scope(message)) return false;
        ClientPlayNetworking.send(new BridgePayload(message.toString()));
        return true;
    }

    static void request(JsonObject query, Consumer<JsonObject> callback) {
        if(!worldInteractionsReady()&&query.has("t")&&query.get("t").getAsString().equals("exchange")){
            callback.accept(error("正在等待目标世界就绪"));return;
        }
        if (!ClientPlayNetworking.canSend(BridgePayload.TYPE)) {
            callback.accept(error("服务器桥接尚未连接"));
            return;
        }
        String id = UUID.randomUUID().toString();
        JsonObject message = query.deepCopy();
        message.addProperty("request", id);
        Pending request = new Pending(callback, System.currentTimeMillis() + 20000, GuestSession.epoch(), message.has("t") && message.get("t").getAsString().equals("hello"));
        pending.put(id, request);
        try {
            if (!send(message)) { pending.remove(id); complete(request,error("服务器会话尚未确认")); }
        }
        catch (RuntimeException exception) {
            pending.remove(id);
            complete(request, error("无法发送服务器请求"));
        }
    }

    private static void receive(String raw) {
        try {
            JsonObject message = JsonParser.parseString(raw).getAsJsonObject();
            if (!message.has("t")) return;
            if (message.get("t").getAsString().equals("event")) {
                if (!GuestSession.acceptEvent(message)) return;
                String data = message.get("data").getAsString();
                JsonObject event = JsonParser.parseString(data).getAsJsonObject();
                if (!event.has("t")) return;
                if (!BridgeEventPolicy.allows(event)) return;
                if (!events.dispatch(event.get("t").getAsString(), new Event(event, data))) Passthrough.events.accept(data);
                return;
            }
            if (message.get("t").getAsString().equals("reply") && message.has("request")) {
                String id=message.get("request").getAsString();
                Pending request = pending.get(id);
                if (request == null || request.epoch()!=GuestSession.epoch()) return;
                if (!request.hello() && !GuestSession.acceptReply(message)) return;
                pending.remove(id);
                complete(request, message.getAsJsonObject("result"));
            }
        } catch (RuntimeException exception) { Passthrough.LOG.warn("invalid server bridge message: {}", exception.toString()); }
    }

    private static void publishDrops(Event event) {
        if (Boolean.getBoolean("palcraft.noFrameExport")) return;
        try {
            Path root = Path.of(System.getProperty("palcraft.bridgeDir", "D:/PalworldServer-LAN/PalCraft-Dev/bridge"));
            Files.createDirectories(root);
            Path temporary = root.resolve("drops.tmp");
            Files.writeString(temporary, event.raw());
            Files.move(temporary, root.resolve("drops.json"), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (java.io.IOException exception) { Passthrough.LOG.debug("drop display: {}", exception.toString()); }
    }

    static void observeLocalEvent(String raw) {
        if(remote())return;
        try{JsonObject event=JsonParser.parseString(raw).getAsJsonObject();if(event.has("t")&&event.get("t").getAsString().equals("blocks"))observeWorldEvent(event);}
        catch(RuntimeException exception){Passthrough.LOG.debug("local world event: {}",exception.toString());}
    }

    private static void observeWorldEvent(JsonObject event) {
        Minecraft mc=Minecraft.getInstance();
        if(mc.player==null||!event.has("lifecycle")||!event.has("session"))return;
        for(var element:event.getAsJsonArray("lifecycle")){
            JsonObject row=element.getAsJsonObject();
            if(!row.has("op")||!row.get("op").getAsString().equals("player_view")||!row.has("player")||!row.get("player").getAsString().equals(mc.player.getUUID().toString()))continue;
            WorldView next=new WorldView(event.get("session").getAsString(),row.get("to").getAsString(),row.get("view").getAsLong(),row.get("waiting_ack").getAsBoolean());
            observeTrustedWorldView(next);
        }
    }

    private static void worldViewApplied(JsonObject event) {
        Minecraft mc=Minecraft.getInstance();WorldView current=worldView;
        if(mc.player==null||current==null||!event.has("player")||!event.get("player").getAsString().equals(mc.player.getUUID().toString()))return;
        if(!event.has("world_session")||!event.has("dim")||!event.has("view")||!event.has("applied")||!event.get("applied").getAsBoolean())return;
        if(!current.session().equals(event.get("world_session").getAsString())||!current.dimension().equals(event.get("dim").getAsString())||current.generation()!=event.get("view").getAsLong())return;
        observeTrustedWorldView(new WorldView(current.session(),current.dimension(),current.generation(),false));
        Passthrough.events.accept(event.toString());
    }

    static void tick(Minecraft mc) {
        long now = System.currentTimeMillis();
        for (var entry : new ArrayList<>(pending.entrySet())) {
            if (entry.getValue().expires() < now) {
                pending.remove(entry.getKey());
                complete(entry.getValue(), error("服务器尚未确认"));
            }
        }
        if (!remote() || ++ticks % 2 != 0) return;
        HostState.Sample sample = HostState.liveSample();
        if (sample == null) return;
        HostState.Pose pose = sample.pose();
        JsonObject query = new JsonObject();
        query.addProperty("t", "host_pose");
        query.addProperty("x", pose.px()); query.addProperty("y", pose.py()); query.addProperty("z", pose.pz());
        query.addProperty("grounded", pose.grounded());
        if(!HostState.scopeHostPose(query,sample))return;
        send(query);
    }

    static void balances(Consumer<JsonObject> reply) {
        if (!remote()) {
            if(!BridgeNetwork.exchangeEnabled()){reply.accept(BridgeNetwork.exchangeUnavailable());return;}
            if (Minecraft.getInstance().player == null) reply.accept(error("玩家尚未进入世界"));
            else ResourceExchange.balances(Minecraft.getInstance().player.getUUID(), reply);
            return;
        }
        JsonObject query = new JsonObject(); query.addProperty("t", "exchange_balance"); request(query, reply);
    }

    static void exchange(String material, boolean toMc, int count, Consumer<JsonObject> reply) {
        if (!remote()) {
            if(!BridgeNetwork.exchangeEnabled()){reply.accept(BridgeNetwork.exchangeUnavailable());return;}
            if (Minecraft.getInstance().player == null) reply.accept(error("玩家尚未进入世界"));
            else ResourceExchange.request(Minecraft.getInstance().player.getUUID(), material, toMc, count, reply);
            return;
        }
        JsonObject query = new JsonObject(); query.addProperty("t", "exchange");
        query.addProperty("material", material); query.addProperty("to_mc", toMc); query.addProperty("count", count);
        request(query, reply);
    }

    private ClientBridge() {}
}
