// Two narrowly scoped Java cases. The production method bodies are copied verbatim below;
// only the server, player, loaded chunk and queue endpoints are data fixtures.
import com.google.gson.*;
import dev.rehan.passthrough.TravelAckValidator;
import java.util.*;
public final class TargetRingChecks {
 static final MinecraftServer SRV=new MinecraftServer();
 static final ServerPlayer PLAYER=new ServerPlayer();
 static final TravelAckValidator.Binding B=new TravelAckValidator.Binding(PLAYER.getUUID().toString(),"fixture-pal-uid","fixture-session",1,"fixture-epoch","fixture-world","fixture-pal-session","fixture-MC-world","minecraft:overworld",1);
 static boolean authenticated=true,forwardedAfterCache=false;
 static class MinecraftServer {boolean isSameThread(){return true;}PlayerList getPlayerList(){return new PlayerList();}}
 static class PlayerList {ServerPlayer getPlayer(UUID id){return id.equals(PLAYER.getUUID())?PLAYER:null;}}
 static class BlockPos {int getX(){return 13;}int getY(){return 53;}int getZ(){return 7;}}
 static class ChunkSource {Object getChunkNow(int x,int z){return Boolean.TRUE;}}
 static class ServerLevel {MinecraftServer getServer(){return SRV;}int getMinY(){return -64;}int getMaxY(){return 319;}ChunkSource getChunkSource(){return new ChunkSource();}}
 static class ServerPlayer {UUID getUUID(){return UUID.fromString("00000000-0000-0000-0000-000000000001");}ServerLevel level(){return new ServerLevel();}BlockPos blockPosition(){return new BlockPos();}}
 static class View {int chunkX,chunkZ,sectionY;}
 static class BridgeNetwork {static void eventFor(ServerPlayer p,String raw){forwardedAfterCache=Gate.snapshotPrepares.containsKey(p.getUUID());}}
 static class WorldCompatibility {

 static MinecraftServer server=SRV;
 static Map<String,ServerLevel> worlds=new HashMap<>();static Set<String> resyncRequired=new HashSet<>();
 static View view=new View();static List<int[]> jobs=new ArrayList<>();static JsonObject event;
 static String dimension(ServerLevel l){return "minecraft:overworld";}
 static View observeView(ServerPlayer p){return view;}
 static void cancelSnapshots(UUID id){jobs.clear();}
 static JsonObject lifecycle(String name){JsonObject r=new JsonObject();r.addProperty("op",name);return r;}
 static void emitLifecycle(String dim,JsonObject e){event=e;}
 static boolean enqueueSnapshot(ServerLevel l,UUID owner,int cx,int cz,int a,int b,int c,int d,int e,int f,String requestId){jobs.add(new int[]{a,b,c,d,e,f});return true;}
 static JsonObject rollbackView(ServerPlayer p,String s,long v){return new JsonObject();}
public static void syncFor(ServerPlayer player, int requestedRadius, String requestId) {
        syncFor(player,requestedRadius,requestId,null);
    }
public static void syncFor(ServerPlayer player, int requestedRadius, String requestId, int[] requestedBounds) {
        if (requestId != null && !UUID.fromString(requestId).toString().equals(requestId)) throw new IllegalArgumentException("Invalid request_id");
        if (server == null || player.level().getServer() != server) return;
        ServerLevel level = player.level(); String dimension = dimension(level);
        worlds.putIfAbsent(dimension, level); View view = observeView(player);
        int radius = Math.clamp(requestedRadius, 1, 64); BlockPos center = player.blockPosition();
        view.chunkX = center.getX() >> 4; view.chunkZ = center.getZ() >> 4; view.sectionY = center.getY() >> 4;
        cancelSnapshots(player.getUUID());
        int minX = center.getX()-radius, maxX = center.getX()+radius+1;
        int minZ = center.getZ()-radius, maxZ = center.getZ()+radius+1;
        int minY = Math.max(level.getMinY(), center.getY()-24), maxY = Math.min(level.getMaxY()+1, center.getY()+41);
        if (requestedBounds != null) {
            if (requestedBounds.length != 6 || requestedBounds[0] >= requestedBounds[3] || requestedBounds[1] >= requestedBounds[4]
                    || requestedBounds[2] >= requestedBounds[5] || (long)requestedBounds[3]-requestedBounds[0] > 129
                    || (long)requestedBounds[5]-requestedBounds[2] > 129 || (long)requestedBounds[4]-requestedBounds[1] > 65
                    || requestedBounds[1] < level.getMinY() || requestedBounds[4] > level.getMaxY()+1)
                throw new IllegalArgumentException("Authoritative target ring exceeds public blocksync capacity");
            minX=requestedBounds[0];minY=requestedBounds[1];minZ=requestedBounds[2];
            maxX=requestedBounds[3];maxY=requestedBounds[4];maxZ=requestedBounds[5];
        }
        int accepted = 0;
        for (int cx = minX >> 4; cx <= (maxX-1) >> 4; cx++) for (int cz = minZ >> 4; cz <= (maxZ-1) >> 4; cz++) {
            if (level.getChunkSource().getChunkNow(cx, cz) == null) continue;
            if (enqueueSnapshot(level, player.getUUID(), cx, cz, Math.max(minX,cx*16), minY, Math.max(minZ,cz*16),
                                Math.min(maxX,cx*16+16), maxY, Math.min(maxZ,cz*16+16),requestId)) accepted++;
        }
        resyncRequired.remove(dimension);
        JsonObject event = lifecycle("sync_requested"); event.addProperty("player", player.getUUID().toString());
        event.addProperty("radius", radius); event.addProperty("chunks", accepted);
        if (requestId != null) event.addProperty("request_id", requestId);
        event.addProperty("vertical_below", 24); event.addProperty("vertical_above", 40);
        event.addProperty("loaded_only", true); emitLifecycle(dimension, event);
    }
 }
 static class BaselineWorldCompatibility {

 static MinecraftServer server=SRV;
 static Map<String,ServerLevel> worlds=new HashMap<>();static Set<String> resyncRequired=new HashSet<>();
 static View view=new View();static List<int[]> jobs=new ArrayList<>();static JsonObject event;
 static String dimension(ServerLevel l){return "minecraft:overworld";}
 static View observeView(ServerPlayer p){return view;}
 static void cancelSnapshots(UUID id){jobs.clear();}
 static JsonObject lifecycle(String name){JsonObject r=new JsonObject();r.addProperty("op",name);return r;}
 static void emitLifecycle(String dim,JsonObject e){event=e;}
 static boolean enqueueSnapshot(ServerLevel l,UUID owner,int cx,int cz,int a,int b,int c,int d,int e,int f,String requestId){jobs.add(new int[]{a,b,c,d,e,f});return true;}
 static JsonObject rollbackView(ServerPlayer p,String s,long v){return new JsonObject();}
public static void syncFor(ServerPlayer player, int requestedRadius, String requestId) {
        if (requestId != null && !UUID.fromString(requestId).toString().equals(requestId)) throw new IllegalArgumentException("Invalid request_id");
        if (server == null || player.level().getServer() != server) return;
        ServerLevel level = player.level(); String dimension = dimension(level);
        worlds.putIfAbsent(dimension, level); View view = observeView(player);
        int radius = Math.clamp(requestedRadius, 1, 64); BlockPos center = player.blockPosition();
        view.chunkX = center.getX() >> 4; view.chunkZ = center.getZ() >> 4; view.sectionY = center.getY() >> 4;
        cancelSnapshots(player.getUUID());
        int minX = center.getX()-radius, maxX = center.getX()+radius+1;
        int minZ = center.getZ()-radius, maxZ = center.getZ()+radius+1;
        int minY = Math.max(level.getMinY(), center.getY()-24), maxY = Math.min(level.getMaxY()+1, center.getY()+41);
        int accepted = 0;
        for (int cx = minX >> 4; cx <= (maxX-1) >> 4; cx++) for (int cz = minZ >> 4; cz <= (maxZ-1) >> 4; cz++) {
            if (level.getChunkSource().getChunkNow(cx, cz) == null) continue;
            if (enqueueSnapshot(level, player.getUUID(), cx, cz, Math.max(minX,cx*16), minY, Math.max(minZ,cz*16),
                                Math.min(maxX,cx*16+16), maxY, Math.min(maxZ,cz*16+16),requestId)) accepted++;
        }
        resyncRequired.remove(dimension);
        JsonObject event = lifecycle("sync_requested"); event.addProperty("player", player.getUUID().toString());
        event.addProperty("radius", radius); event.addProperty("chunks", accepted);
        if (requestId != null) event.addProperty("request_id", requestId);
        event.addProperty("vertical_below", 24); event.addProperty("vertical_above", 40);
        event.addProperty("loaded_only", true); emitLifecycle(dimension, event);
    }
 }
 static class Gate {
 static boolean ENABLED=true;static MinecraftServer authority=SRV;
 static Map<UUID,JsonObject> snapshotPrepares=new HashMap<>();
 static TravelAckValidator.Binding binding(ServerPlayer p){return authenticated&&p!=null?B:null;}
 static void reject(String reason){throw new IllegalArgumentException(reason);}
 static void consumeRebase(ServerPlayer p,JsonObject row,TravelAckValidator.Binding binding){throw new AssertionError("not a rebase fixture");}
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
        if(phase.equals("prepare"))snapshotPrepares.put(player.getUUID(),row.deepCopy());
        else snapshotPrepares.remove(player.getUUID());
        if(phase.equals("error")&&row.has("needs_mc_rollback")&&row.get("needs_mc_rollback").getAsBoolean()){
            // Restore coordinates in the wire record are diagnostic only; MC restores its internally captured source.
            JsonObject rollback=WorldCompatibility.rollbackView(player,binding.worldSession(),binding.view());
            row=row.deepCopy();row.add("mc_rollback",rollback);
        }
        BridgeNetwork.eventFor(player,row.toString());
    }
 }
 static void check(boolean value){if(!value)throw new AssertionError();}
 static JsonObject prepare(){
  JsonObject row=new JsonObject();row.addProperty("t","travel");row.addProperty("v",1);row.addProperty("phase","prepare");row.addProperty("tx","fixture:38");
  row.addProperty("player",B.player());row.addProperty("pal_uid",B.palUid());row.addProperty("session_id",B.sessionId());row.addProperty("session_generation",B.sessionGeneration());
  row.addProperty("mc_epoch",B.mcEpoch());row.addProperty("world_id",B.worldId());row.addProperty("server_session_id",B.serverSessionId());
  row.addProperty("world_session",B.worldSession());row.addProperty("dim",B.dimension());row.addProperty("view",B.view());
  JsonArray bounds=new JsonArray();for(int value:new int[]{-66,46,-70,63,94,59})bounds.add(value);row.add("required_bounds",bounds);return row;
 }
 static JsonObject query(JsonObject p){JsonObject q=p.deepCopy();q.addProperty("t","blocksync");q.addProperty("r",64);return q;}
 static long volume(int[] b){return(long)(b[3]-b[0])*(b[4]-b[1])*(b[5]-b[2]);}
 static void rejects(Runnable operation){try{operation.run();throw new AssertionError("untrusted request accepted");}catch(IllegalArgumentException expected){}}
 public static void main(String[] args){
  JsonArray cases=new JsonArray();
  JsonObject prepare=prepare();Gate.consumeEvent(SRV,prepare);check(forwardedAfterCache);
  int[] trusted=Gate.snapshotBounds(SRV,PLAYER,query(prepare));check(Arrays.equals(trusted,new int[]{-66,46,-70,63,94,59}));
  WorldCompatibility.syncFor(PLAYER,64,null,trusted);
  check(WorldCompatibility.jobs.size()==81);long total=0;
  for(int[] tile:WorldCompatibility.jobs){
   check(tile[0]>=trusted[0]&&tile[1]==46&&tile[2]>=trusted[2]&&tile[3]<=trusted[3]&&tile[4]==94&&tile[5]<=trusted[5]);
   check(tile[3]-tile[0]<=16&&tile[5]-tile[2]<=16);total+=volume(tile);
  }
  for(int i=0;i<WorldCompatibility.jobs.size();i++)for(int j=0;j<i;j++){
   int[] a=WorldCompatibility.jobs.get(i),b=WorldCompatibility.jobs.get(j);
   check(a[3]<=b[0]||b[3]<=a[0]||a[5]<=b[2]||b[5]<=a[2]);
  }
  check(total==798768&&total==volume(trusted));
  check(WorldCompatibility.view.chunkX==0&&WorldCompatibility.view.chunkZ==0&&WorldCompatibility.view.sectionY==3);
  check(!WorldCompatibility.event.has("ready")&&WorldCompatibility.event.get("chunks").getAsInt()==81);
  JsonObject first=new JsonObject();first.addProperty("name","authenticated_prepare_precedes_request_and_exact_full_ring_tiles_preserve_real_player_tracking");first.addProperty("passed",true);first.addProperty("tiles",81);first.addProperty("covered_cells",total);cases.add(first);
  BaselineWorldCompatibility.syncFor(PLAYER,32,null);WorldCompatibility.syncFor(PLAYER,32,null);
  check(BaselineWorldCompatibility.jobs.size()==WorldCompatibility.jobs.size());
  for(int i=0;i<WorldCompatibility.jobs.size();i++)check(Arrays.equals(BaselineWorldCompatibility.jobs.get(i),WorldCompatibility.jobs.get(i)));
  authenticated=false;rejects(()->Gate.snapshotBounds(SRV,PLAYER,query(prepare)));authenticated=true;
  JsonObject changed=query(prepare);changed.getAsJsonArray("required_bounds").set(0,new JsonPrimitive(-65));rejects(()->Gate.snapshotBounds(SRV,PLAYER,changed));
  JsonObject second=new JsonObject();second.addProperty("name","old_default_tiles_unchanged_and_unauthenticated_or_client_selected_bounds_rejected");second.addProperty("passed",true);second.addProperty("default_tiles",WorldCompatibility.jobs.size());cases.add(second);
  JsonObject result=new JsonObject();result.addProperty("ok",true);result.addProperty("targeted_java_cases",2);result.addProperty("fixture_only",true);result.addProperty("actual_coverage_or_ready_proven",false);result.add("cases",cases);System.out.println(result);
 }
}
