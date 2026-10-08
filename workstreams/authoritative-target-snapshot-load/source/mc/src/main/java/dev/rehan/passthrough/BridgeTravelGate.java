package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import dev.rehan.passthrough.session.BridgeSessions;
import dev.rehan.passthrough.session.SessionHandle;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.UUID;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.BiFunction;
import java.util.Objects;
import java.nio.channels.FileChannel;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.StandardOpenOption;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;

/** Only the Pal server's final journal can release a world view; guest ACK packets cannot. */
public final class BridgeTravelGate {
    private static final boolean ENABLED=Boolean.getBoolean("palcraft.travel.enabled");
    private static final Path JOURNAL=Path.of(System.getProperty("palcraft.travelAckJournal",
        "D:/PalworldServer-LAN/BridgeLab/rpc/travel/travel-acks.ndjson"));
    private static final double POSITION_TOLERANCE_CM=Double.parseDouble(System.getProperty("palcraft.travelAckPositionToleranceCm","50"));
    private static final LinkedHashSet<String> completed=new LinkedHashSet<>();
    private static final LinkedHashSet<String> completedRebases=new LinkedHashSet<>();
    private static final java.util.Map<UUID,JsonObject> snapshotPrepares=new java.util.HashMap<>();
    private static BiFunction<ServerPlayer,Vec3,JsonObject> rebaseTransition;
    private static CompleteLineJournal reader;
    private static CompleteLineJournal eventReader;
    private static final Path EVENTS=JOURNAL.resolveSibling("travel-events.ndjson"),INPUT=JOURNAL.resolveSibling("travel-input.ndjson");
    private static MinecraftServer authority;
    private static int ticks;
    private static long applied,rejected,duplicates,rebases;
    private static String lastError;

    public static void attach(MinecraftServer server) {
        authority=server;reader=new CompleteLineJournal(JOURNAL,262144);
        eventReader=new CompleteLineJournal(EVENTS,262144);
        ticks=0;applied=rejected=duplicates=rebases=0;completed.clear();completedRebases.clear();snapshotPrepares.clear();lastError=null;
    }

    public static void detach(MinecraftServer server) { if(authority==server){authority=null;reader=eventReader=null;completed.clear();completedRebases.clear();snapshotPrepares.clear();} }
    /** The world owner supplies the server-only private-source/rollback implementation at feature registration. */
    public static void bindRebaseTransition(BiFunction<ServerPlayer,Vec3,JsonObject> transition){rebaseTransition=Objects.requireNonNull(transition);}

    public static void tick(MinecraftServer server) {
        if(!ENABLED||authority!=server||reader==null||++ticks%2!=0)return;
        try {
            for(String raw:reader.poll(128,1048576)) {
                try { consume(server,JsonParser.parseString(raw).getAsJsonObject()); }
                catch(RuntimeException exception){reject("malformed_travel_journal_row");}
            }
            for(String raw:eventReader.poll(128,1048576)) {
                try { consumeEvent(server,JsonParser.parseString(raw).getAsJsonObject()); }
                catch(RuntimeException exception){reject("malformed_travel_event");}
            }
        } catch(java.io.IOException exception) { lastError="travel_journal_read_failed";Passthrough.LOG.debug("travel authority journal: {}",exception.toString()); }
    }

    private static TravelAckValidator.Binding binding(ServerPlayer player) {
        SessionHandle handle=player==null?null:BridgeSessions.handle(player);
        if(handle==null||!BridgeSessions.authenticated(player))return null;
        JsonObject view=WorldCompatibility.playerView(player);
        return new TravelAckValidator.Binding(player.getUUID().toString(),handle.identity().palUid(),handle.sessionId().toString(),handle.generation(),
            BridgeSessions.mcEpoch(),handle.identity().worldId(),handle.serverSessionId(),view.get("world_session").getAsString(),view.get("dim").getAsString(),view.get("view").getAsLong());
    }

    /** Connection identity is reconstructed here; client-supplied player/session fields are not forwarded. */
    public static void clientSignal(MinecraftServer server,ServerPlayer player,JsonObject query,Consumer<JsonObject> reply) {
        JsonObject result=new JsonObject();result.addProperty("ok",false);
        if(!ENABLED||authority!=server){result.addProperty("error","travel_feature_not_ready");reply.accept(result);return;}
        TravelAckValidator.Binding binding=binding(player);
        if(binding==null){result.addProperty("error","missing_authenticated_player");reply.accept(result);return;}
        if(!query.has("world_session")||!binding.worldSession().equals(query.get("world_session").getAsString())
            ||!query.has("dim")||!binding.dimension().equals(query.get("dim").getAsString())||!query.has("view")||binding.view()!=query.get("view").getAsLong()){
            result.addProperty("error","stale_world_view");reply.accept(result);return;
        }
        String phase=switch(query.get("t").getAsString()){case "travel_ready"->"client_ready";case "travel_observed"->"client_observed";case "travel_abort"->"client_abort";default->throw new IllegalArgumentException("Unsupported travel signal");};
        String tx=query.get("tx").getAsString();if(tx.isBlank()||tx.length()>200||!tx.matches("[A-Za-z0-9_.:-]+"))throw new IllegalArgumentException("Invalid travel transaction");
        JsonObject row=new JsonObject();row.addProperty("t","travel");row.addProperty("v",1);row.addProperty("phase",phase);row.addProperty("tx",tx);
        row.addProperty("player",binding.player());row.addProperty("pal_uid",binding.palUid());row.addProperty("session_id",binding.sessionId());row.addProperty("session_generation",binding.sessionGeneration());
        row.addProperty("mc_epoch",binding.mcEpoch());row.addProperty("world_id",binding.worldId());row.addProperty("server_session_id",binding.serverSessionId());
        row.addProperty("world_session",binding.worldSession());row.addProperty("dim",binding.dimension());row.addProperty("view",binding.view());
        for(String key:ListKeys.CLIENT_EVIDENCE)if(query.has(key))row.add(key,query.get(key).deepCopy());
        byte[] bytes=(row+"\n").getBytes(StandardCharsets.UTF_8);if(bytes.length>65536)throw new IllegalArgumentException("Travel proof is too large");
        try {
            java.nio.file.Files.createDirectories(INPUT.getParent());
            try(FileChannel file=FileChannel.open(INPUT,StandardOpenOption.CREATE,StandardOpenOption.WRITE,StandardOpenOption.APPEND)){
                ByteBuffer buffer=ByteBuffer.wrap(bytes);while(buffer.hasRemaining())file.write(buffer);file.force(true);
            }
            result.addProperty("ok",true);result.addProperty("queued",true);result.addProperty("tx",tx);
        }catch(java.io.IOException exception){result.addProperty("error","travel_signal_not_durable");}
        reply.accept(result);
    }

    private static final class ListKeys {static final Set<String> CLIENT_EVIDENCE=Set.of("proof","position","region_id","error");}

    /** The caller selects a known transaction; only the authenticated Pal prepare supplies its snapshot region. */
    public static int[] snapshotBounds(MinecraftServer server,ServerPlayer player,JsonObject query) {
        if(!ENABLED||authority!=server||!server.isSameThread())throw new IllegalArgumentException("travel_feature_not_ready");
        TravelAckValidator.Binding binding=binding(player);
        JsonObject prepare=player==null?null:snapshotPrepares.get(player.getUUID());
        if(binding==null||prepare==null||TravelAckValidator.rejectBinding(prepare,binding)!=null)
            throw new IllegalArgumentException("current_authoritative_prepare_required");
        if(!binding.worldSession().equals(query.get("world_session").getAsString())
            ||!binding.dimension().equals(query.get("dim").getAsString())||binding.view()!=query.get("view").getAsLong()
            ||!prepare.get("tx").getAsString().equals(query.get("tx").getAsString())
            ||!prepare.get("required_bounds").equals(query.get("required_bounds")))
            throw new IllegalArgumentException("stale_authoritative_snapshot_request");
        var bounds=prepare.getAsJsonArray("required_bounds");
        if(bounds.size()!=6)throw new IllegalArgumentException("invalid_authoritative_snapshot_bounds");
        int[] values=new int[6];
        for(int i=0;i<values.length;i++)values[i]=bounds.get(i).getAsBigDecimal().toBigIntegerExact().intValueExact();
        return values;
    }

    private static void consumeEvent(MinecraftServer server,JsonObject row) {
        if(!row.get("t").getAsString().equals("travel")||row.get("v").getAsInt()!=1){reject("invalid_travel_event");return;}
        String phase=row.get("phase").getAsString();
        if(!Set.of("prepare","committed","complete","error","recovery_required","rebase_required").contains(phase)){reject("invalid_travel_phase");return;}
        ServerPlayer player=server.getPlayerList().getPlayer(UUID.fromString(row.get("player").getAsString()));
        TravelAckValidator.Binding binding=binding(player);if(binding==null){reject("missing_authenticated_player");return;}
        if(phase.equals("rebase_required")){consumeRebase(player,row,binding);return;}
        String reason=TravelAckValidator.rejectBinding(row,binding);if(reason!=null){reject(reason);return;}
        if(phase.equals("prepare")){
            WorldCompatibility.cancelOtherTargetSnapshots(player.getUUID(),row.get("tx").getAsString());
            snapshotPrepares.put(player.getUUID(),row.deepCopy());
        } else {
            snapshotPrepares.remove(player.getUUID());
            if(phase.equals("error")||phase.equals("recovery_required"))WorldCompatibility.cancelTargetSnapshots(player.getUUID(),row.get("tx").getAsString());
        }
        if(phase.equals("error")&&row.has("needs_mc_rollback")&&row.get("needs_mc_rollback").getAsBoolean()){
            // Restore coordinates in the wire record are diagnostic only; MC restores its internally captured source.
            JsonObject rollback=WorldCompatibility.rollbackView(player,binding.worldSession(),binding.view());
            row=row.deepCopy();row.add("mc_rollback",rollback);
        }
        BridgeNetwork.eventFor(player,row.toString());
    }

    private static void consumeRebase(ServerPlayer player,JsonObject row,TravelAckValidator.Binding binding) {
        String key=TravelAckValidator.transactionKey(row);
        if(completedRebases.contains(key)){duplicates++;return;}
        var level=player.level();var border=level.getWorldBorder();
        var bounds=new TravelRebaseValidator.Bounds(level.getMinY(),level.getHeight(),border.getMinX(),border.getMaxX(),border.getMinZ(),border.getMaxZ());
        String reason=TravelRebaseValidator.rejectReason(row,binding,bounds,WorldCompatibility.waitingForView(player));
        if(reason!=null){reject(reason);return;}
        if(rebaseTransition==null){reject("mc_rebase_hook_unavailable");return;}
        var position=TravelRebaseValidator.position(row);
        // This function is bound to the world owner's implementation that captures a private same-dimension source.
        // The old/new Pal origins stay in the existing Lua mapping protocol; no wire origin is applied here.
        JsonObject result=rebaseTransition.apply(player,new Vec3(position.x(),position.y(),position.z()));
        if(result==null||!result.has("ok")||!result.get("ok").getAsBoolean()){reject("mc_rebase_transition_rejected");return;}
        completedRebases.add(key);if(completedRebases.size()>4096)completedRebases.remove(completedRebases.iterator().next());
        rebases++;lastError=null;
        // The generated authoritative player_view is the only response. No unscoped rebase event is sent to a guest.
    }

    private static void consume(MinecraftServer server,JsonObject row) {
        ServerPlayer player=server.getPlayerList().getPlayer(UUID.fromString(row.get("player").getAsString()));
        TravelAckValidator.Binding binding=binding(player);if(binding==null){reject("missing_authenticated_player");return;}
        String reason=TravelAckValidator.rejectReason(row,binding,POSITION_TOLERANCE_CM);
        if(reason!=null){reject(reason);return;}
        String key=TravelAckValidator.transactionKey(row);
        if(completed.contains(key)){duplicates++;return;}
        JsonObject request=new JsonObject();request.addProperty("session",binding.worldSession());
        request.addProperty("dim",binding.dimension());request.addProperty("view",binding.view());request.addProperty("applied",true);
        JsonObject result=WorldCompatibility.acknowledgeView(player,request);
        if(!result.get("ok").getAsBoolean()){reject("world_ack_rejected");return;}
        completed.add(key);if(completed.size()>4096)completed.remove(completed.iterator().next());
        applied++;lastError=null;
        JsonObject event=new JsonObject();event.addProperty("t","world_view_applied");event.addProperty("player",binding.player());
        event.addProperty("tx",row.get("tx").getAsString());event.addProperty("world_session",binding.worldSession());
        event.addProperty("dim",binding.dimension());event.addProperty("view",binding.view());event.addProperty("applied",true);
        BridgeNetwork.eventFor(player,event.toString());
    }

    private static void reject(String reason){rejected++;lastError=reason;}
    public static JsonObject status() {
        JsonObject result=new JsonObject();result.addProperty("ok",authority!=null);result.addProperty("enabled",ENABLED);
        result.addProperty("applied",applied);result.addProperty("rejected",rejected);result.addProperty("duplicates",duplicates);
        result.addProperty("rebase_supported",rebaseTransition!=null);result.addProperty("rebases",rebases);
        result.addProperty("journal_offset",reader==null?0:reader.offset());result.addProperty("partial_bytes",reader==null?0:reader.partialBytes());
        result.addProperty("oversized_lines",reader==null?0:reader.oversizedLines());if(lastError!=null)result.addProperty("last_error",lastError);
        return result;
    }
    private BridgeTravelGate() {}
}
