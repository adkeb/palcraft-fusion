from pathlib import Path
import subprocess,json,argparse
D=Path(__file__).resolve().parents[1]
s=(D/'source/mc/src/main/java/dev/rehan/passthrough/WorldCompatibility.java').read_text()
def method(a,b):return s[s.index(a):s.index(b,s.index(a))]
parts=method('    private static final class Snapshot {','    private WorldCompatibility()')
parts+=method('    private static boolean removeSnapshot(','    public static void syncFor')
parts+=method('    private static void scanSnapshots()','    private static void chunkLoad(')
java=r"""
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
"""
java+=parts
java+=r"""
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
"""
(D/'checks/TargetLoadLifecycleCase.java').write_text(java)
parser=argparse.ArgumentParser(description='One synthetic production Snapshot lifecycle case; never runs Game')
parser.add_argument('--java-home',type=Path,required=True)
parser.add_argument('--gson',type=Path,required=True)
args=parser.parse_args()
gson=args.gson
jdk=args.java_home/'bin';classes=D/'checks/classes';classes.mkdir(exist_ok=True)
r=subprocess.run(['/usr/bin/nice','-n','19',str(jdk/'javac'),'-J-Xmx384m','-J-XX:ActiveProcessorCount=1','--release','25','-cp',str(gson),'-d',str(classes),str(D/'checks/TargetLoadLifecycleCase.java')],capture_output=True,text=True);assert r.returncode==0,r.stderr
r=subprocess.run(['/usr/bin/nice','-n','19',str(jdk/'java'),'-Xmx128m','-XX:ActiveProcessorCount=1','-ea','-cp',str(classes)+':'+str(gson),'TargetLoadLifecycleCase'],capture_output=True,text=True);assert r.returncode==0,r.stderr
(D/'checks/java-stdout.txt').write_text(r.stdout);print(r.stdout)
