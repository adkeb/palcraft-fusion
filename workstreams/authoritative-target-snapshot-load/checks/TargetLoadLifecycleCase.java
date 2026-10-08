
import java.util.*;
import com.google.gson.*;
public class TargetLoadLifecycleCase {
 static final int SNAPSHOT_CELLS_PER_TICK=4096,SNAPSHOT_OPS_PER_TICK=256,BATCH_OPS=32;
 static String session="synthetic-world";static long snapshotSequence;
 static Map<String,ServerLevel> worlds=new HashMap<>();static Map<UUID,View> views=new HashMap<>();
 static ArrayDeque<Snapshot> snapshots=new ArrayDeque<>(),retainedTargetSnapshots=new ArrayDeque<>();
 static Set<Object> moving=new HashSet<>();static Server server=new Server();
 static int ended=0;static String dimension(ServerLevel l){return "synthetic-dim";}
 static JsonObject lifecycle(String op){JsonObject j=new JsonObject();j.addProperty("op",op);return j;}
 static void emitLifecycle(String d,JsonObject e){if(e.get("op").getAsString().equals("snapshot_end"))ended++;}
 static void emitOps(String d,JsonArray b,String req){}static Object position(ServerLevel l,BlockPos p){return p;}
 static JsonObject capture(ServerLevel l,BlockPos p){return new JsonObject();}
 static class WorldStateCodec{static boolean mirrored(Object block,boolean ground){return false;}}
 static class Nether{static boolean isGround(BlockPos p){return false;}}
 static final String OVERWORLD="overworld";static class Blocks{static final Object MOVING_PISTON=new Object();}
 record ChunkPos(int x,int z){static long asLong(int x,int z){return ((long)x<<32)^(z&0xffffffffL);}}
 record BlockPos(int x,int y,int z){}
 static class BlockState{boolean is(Object o){return false;}}static class LevelChunk{BlockState getBlockState(BlockPos p){return new BlockState();}}
 static class TicketType{static final long NO_TIMEOUT=0;static final int FLAG_LOADING=2;static final TicketType PLAYER_LOADING=new TicketType(0,2);TicketType(long t,int f){}}
 record Ticket(TicketType type,int level){TicketType getType(){return type;}int getTicketLevel(){return level;}}
 static class TicketStorage{static final Object TYPE=new Object();Map<Long,List<Ticket>> tickets=new HashMap<>();List<Ticket> getTickets(long p){return tickets.getOrDefault(p,List.of());}}
 static class Data{TicketStorage storage;Data(TicketStorage s){storage=s;}TicketStorage computeIfAbsent(Object t){return storage;}}
 static class Chunks{Map<Long,TicketType> owned=new HashMap<>();Set<Long> loaded=new HashSet<>();TicketStorage storage=new TicketStorage();int starts=0,releases=0;
  Object addTicketAndLoadWithRadius(TicketType t,ChunkPos p,int r){owned.put(ChunkPos.asLong(p.x,p.z),t);starts++;return null;}
  void removeTicketWithRadius(TicketType t,ChunkPos p,int r){long key=ChunkPos.asLong(p.x,p.z);assert owned.get(key)==t;owned.remove(key);releases++;}
  LevelChunk getChunkNow(int x,int z){return loaded.contains(ChunkPos.asLong(x,z))?new LevelChunk():null;}
  Data getDataStorage(){return new Data(storage);}}
 static class ServerLevel{Chunks chunks=new Chunks();Chunks getChunkSource(){return chunks;}}
 static class ServerPlayer{UUID id;ServerPlayer(UUID x){id=x;}}
 static class Players{ServerPlayer player;ServerPlayer getPlayer(UUID u){return player!=null&&player.id.equals(u)?player:null;}}
 static class Server{Players players=new Players();Players getPlayerList(){return players;}}
 static class View{ServerPlayer identity;String dimension="synthetic-dim";long generation=2;boolean waitingAck=true;}
 static class BridgeTravelGate{static int[] snapshotBounds(Server s,ServerPlayer p,JsonObject q){return new int[]{178,12,-171,307,60,-42};}}
    private static final class Snapshot {
        final String id, dimension;
        final UUID owner;
        final ServerLevel level;
        final int chunkX, chunkZ, minX, minY, minZ, maxX, maxY, maxZ;
        int x, y, z;
        boolean begun;
        String requestId;
        JsonObject targetRequest;
        TicketType loadTicket;
        void acquireTargetChunk() {
            if (loadTicket != null) return;
            loadTicket = new TicketType(TicketType.NO_TIMEOUT, TicketType.FLAG_LOADING);
            level.getChunkSource().addTicketAndLoadWithRadius(loadTicket, new ChunkPos(chunkX,chunkZ), 0);
        }
        void releaseTargetChunk() {
            if (loadTicket == null) return;
            level.getChunkSource().removeTicketWithRadius(loadTicket,new ChunkPos(chunkX,chunkZ),0);loadTicket=null;
        }
        boolean targetStillCurrent() {
            ServerPlayer player=server==null?null:server.getPlayerList().getPlayer(owner);
            if(player==null||worlds.get(dimension)!=level||!session.equals(targetRequest.get("world_session").getAsString()))return false;
            View view=views.get(owner);
            return view!=null&&view.identity==player&&view.dimension.equals(dimension)&&view.generation==targetRequest.get("view").getAsLong();
        }
        boolean playerOwnsChunk() {
            if(!targetStillCurrent()||views.get(owner).waitingAck)return false;
            for(var ticket:level.getChunkSource().getDataStorage().computeIfAbsent(TicketStorage.TYPE).getTickets(ChunkPos.asLong(chunkX,chunkZ)))
                if(ticket.getType()==TicketType.PLAYER_LOADING&&ticket.getTicketLevel()<=33)return true;
            return false;
        }
        Snapshot(ServerLevel level, UUID owner, int cx, int cz, int minX, int minY, int minZ,
                 int maxX, int maxY, int maxZ) {
            this.id = session + ":" + (++snapshotSequence);
            this.dimension = dimension(level); this.owner = owner; this.level = level;
            this.chunkX = cx; this.chunkZ = cz;
            this.minX = minX; this.minY = minY; this.minZ = minZ;
            this.maxX = maxX; this.maxY = maxY; this.maxZ = maxZ;
            this.x = minX; this.y = minY; this.z = minZ;
        }
        boolean complete() { return x >= maxX; }
        void advance() {
            if (++y >= maxY) { y = minY; if (++z >= maxZ) { z = minZ; x++; } }
        }
        JsonObject event(String operation) {
            JsonObject result = lifecycle(operation);
            result.addProperty("snapshot", id);
            if (requestId != null) result.addProperty("request_id", requestId);
            result.addProperty("player", owner.toString());
            JsonArray chunk = new JsonArray(); chunk.add(chunkX); chunk.add(chunkZ); result.add("at", chunk);
            JsonArray bounds = new JsonArray();
            for (int value : new int[]{minX,minY,minZ,maxX,maxY,maxZ}) bounds.add(value);
            result.add("bounds", bounds);
            result.addProperty("replace", true);
            return result;
        }
    }

    private static boolean removeSnapshot(Snapshot job, boolean remove) {
        if (remove) {job.releaseTargetChunk();if(job.requestId!=null||job.targetRequest!=null)emitLifecycle(job.dimension,job.event("snapshot_cancel"));}
        return remove;
    }
    private static void releaseAllTargetChunks() {
        for(Snapshot job:snapshots)job.releaseTargetChunk();
        for(Snapshot job:retainedTargetSnapshots)job.releaseTargetChunk();retainedTargetSnapshots.clear();
    }
    public static void cancelTargetSnapshots(UUID owner,String tx) {
        snapshots.removeIf(job->removeSnapshot(job,job.owner.equals(owner)&&job.targetRequest!=null&&tx.equals(job.targetRequest.get("tx").getAsString())));
        retainedTargetSnapshots.removeIf(job->removeSnapshot(job,job.owner.equals(owner)&&tx.equals(job.targetRequest.get("tx").getAsString())));
    }
    public static void cancelOtherTargetSnapshots(UUID owner,String currentTx) {
        snapshots.removeIf(job->removeSnapshot(job,job.owner.equals(owner)&&job.targetRequest!=null&&!currentTx.equals(job.targetRequest.get("tx").getAsString())));
        retainedTargetSnapshots.removeIf(job->removeSnapshot(job,job.owner.equals(owner)&&!currentTx.equals(job.targetRequest.get("tx").getAsString())));
    }
    private static void cancelSnapshots(UUID owner) {
        var iterator = snapshots.iterator();
        while (iterator.hasNext()) {
            Snapshot job = iterator.next();
            if (!job.owner.equals(owner)) continue;
            if (job.begun || job.requestId != null) emitLifecycle(job.dimension, job.event("snapshot_cancel"));
            job.releaseTargetChunk();iterator.remove();
        }
        retainedTargetSnapshots.removeIf(job->removeSnapshot(job,job.owner.equals(owner)));
    }

    private static void scanSnapshots() {
        int cells = 0, operations = 0, loadStarts=0;
        long deadline = System.nanoTime() + 8_000_000L;
        var retained=retainedTargetSnapshots.iterator();
        while(retained.hasNext()&&System.nanoTime()<deadline){Snapshot job=retained.next();
            if(!job.targetStillCurrent()||job.playerOwnsChunk()){job.releaseTargetChunk();retained.remove();}
        }
        while (!snapshots.isEmpty() && cells < SNAPSHOT_CELLS_PER_TICK && operations < SNAPSHOT_OPS_PER_TICK
                && System.nanoTime() < deadline) {
            Snapshot job = snapshots.removeFirst();
            if(job.targetRequest!=null){
                if(!job.targetStillCurrent()){removeSnapshot(job,true);continue;}
                ServerPlayer player=server.getPlayerList().getPlayer(job.owner);
                try{BridgeTravelGate.snapshotBounds(server,player,job.targetRequest);}catch(IllegalArgumentException stale){removeSnapshot(job,true);continue;}
                if(job.loadTicket==null){if(loadStarts>=1){snapshots.addFirst(job);break;}job.acquireTargetChunk();loadStarts++;}
            }
            LevelChunk chunk = job.level.getChunkSource().getChunkNow(job.chunkX, job.chunkZ);
            if(chunk==null&&job.targetRequest!=null&&worlds.get(job.dimension)==job.level){snapshots.addLast(job);break;}
            if (chunk == null || worlds.get(job.dimension) != job.level) {
                if (job.begun || job.requestId != null) emitLifecycle(job.dimension, job.event("snapshot_cancel"));
                job.releaseTargetChunk();continue;
            }
            if (!job.begun) { job.begun = true; emitLifecycle(job.dimension, job.event("snapshot_begin")); }
            JsonArray batch = new JsonArray();
            while (!job.complete() && cells < SNAPSHOT_CELLS_PER_TICK && operations < SNAPSHOT_OPS_PER_TICK
                    && batch.size() < BATCH_OPS && System.nanoTime() < deadline) {
                BlockPos pos = new BlockPos(job.x, job.y, job.z); cells++; job.advance();
                if (!WorldStateCodec.mirrored(chunk.getBlockState(pos), dimension(job.level).equals(OVERWORLD) && Nether.isGround(pos))) continue;
                JsonObject block = capture(job.level, pos); block.addProperty("snapshot", job.id);
                batch.add(block); operations++;
                if (chunk.getBlockState(pos).is(Blocks.MOVING_PISTON)) moving.add(position(job.level, pos));
            }
            if (!batch.isEmpty()) emitOps(job.dimension, batch,job.requestId);
            if (job.complete()) {emitLifecycle(job.dimension,job.event("snapshot_end"));if(job.targetRequest!=null)retainedTargetSnapshots.addLast(job);}
            else snapshots.addLast(job);
        }
    }


 public static void main(String[] args){
  UUID owner=UUID.fromString("11111111-1111-1111-1111-111111111111");ServerPlayer player=new ServerPlayer(owner);server.players.player=player;
  ServerLevel level=new ServerLevel();worlds.put("synthetic-dim",level);View view=new View();view.identity=player;views.put(owner,view);
  JsonObject q=new JsonObject();q.addProperty("world_session",session);q.addProperty("view",2);q.addProperty("tx","fixture:61");
  for(int x=11;x<=19;x++)for(int z=-11;z<=-3;z++){Snapshot j=new Snapshot(level,owner,x,z,Math.max(178,x*16),12,Math.max(-171,z*16),Math.min(307,x*16+16),60,Math.min(-42,z*16+16));j.targetRequest=q.deepCopy();snapshots.add(j);}
  for(int n=0;n<81;n++){int before=level.chunks.starts;scanSnapshots();assert level.chunks.starts-before<=1;}
  assert level.chunks.starts==81&&ended==0&&level.chunks.releases==0;
  level.chunks.loaded.addAll(level.chunks.owned.keySet());
  for(int n=0;n<500&&!snapshots.isEmpty();n++)scanSnapshots();
  assert snapshots.isEmpty()&&ended==81&&retainedTargetSnapshots.size()==81&&level.chunks.releases==0;
  view.waitingAck=false;scanSnapshots();assert level.chunks.releases==0; // ACK alone is not actual player loading.
  long chunk=ChunkPos.asLong(11,-11);level.chunks.storage.tickets.put(chunk,List.of(new Ticket(TicketType.PLAYER_LOADING,33)));
  scanSnapshots();assert level.chunks.releases==1&&retainedTargetSnapshots.size()==80&&level.chunks.storage.getTickets(chunk).size()==1;
  cancelOtherTargetSnapshots(owner,"fixture:62");assert retainedTargetSnapshots.isEmpty()&&level.chunks.owned.isEmpty()&&level.chunks.releases==81;
  System.out.println("actual Snapshot/scan/cancel source:81 exact unloaded target tiles start<=1 per tick, keep8ms/cell/ops budgets; end/ACK retain; actual PLAYER_LOADING handoff then newtx releases only own tickets: PASS (synthetic)");
 }
}
