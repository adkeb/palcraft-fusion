package dev.rehan.passthrough;

import com.google.gson.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import net.fabricmc.fabric.api.networking.v1.*;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import java.util.function.Consumer;
import dev.rehan.passthrough.session.BridgeSessions;

/** Server operations use the connection's player, never a caller-supplied UUID. */
public final class BridgeNetwork {
 private static final Map<UUID,ServerPlayer> driven=new ConcurrentHashMap<>();
 private static final Path ROOT=Path.of(System.getProperty("palcraft.bridgeDir","D:/PalworldServer-LAN/PalCraft-Dev/bridge"));
 private static String lastAdmin;
 @FunctionalInterface
 public interface Operation {void handle(MinecraftServer server,ServerPlayer player,JsonObject query,Consumer<JsonObject> reply);}
 private record Request(MinecraftServer server,ServerPlayer player,JsonObject query,Consumer<JsonObject> reply){}
 private static final FeatureRegistry<Request> operations=new FeatureRegistry<>();
 public static void registerOperation(String feature,String operation,Operation handler){
  operations.register(feature,operation,r->handler.handle(r.server(),r.player(),r.query(),r.reply()));
 }
 public static JsonObject features(){JsonObject result=new JsonObject();operations.registrations().forEach(result::addProperty);return result;}
 public static boolean exchangeEnabled(){return Boolean.getBoolean("palcraft.exchange.enabled");}
 public static JsonObject featureFlags(){JsonObject result=new JsonObject();result.addProperty("exchange_enabled",exchangeEnabled());result.addProperty("travel_enabled",Boolean.getBoolean("palcraft.travel.enabled"));result.addProperty("strict_sessions",BridgeSessions.strict());return result;}
 public static JsonObject exchangeUnavailable(){JsonObject result=error("材料兑换尚未就绪");result.addProperty("code","feature_not_ready");result.addProperty("feature","exchange");result.addProperty("enabled",false);return result;}
 static void markDriven(ServerPlayer player){driven.put(player.getUUID(),player);}
 static boolean isDriven(ServerPlayer player){return driven.get(player.getUUID())==player;}
 public static void initialize(){
  BridgeSessions.initialize();
  BridgeServerFeatures.register();
  operations.freeze();
  PayloadTypeRegistry.serverboundPlay().registerLarge(BridgePayload.TYPE,BridgePayload.CODEC,BridgePayload.MAX_PACKET_BYTES);
  PayloadTypeRegistry.clientboundPlay().registerLarge(BridgePayload.TYPE,BridgePayload.CODEC,BridgePayload.MAX_PACKET_BYTES);
  ServerPlayNetworking.registerGlobalReceiver(BridgePayload.TYPE,(payload,context)->context.server().execute(()->handle(context.server(),context.player(),payload.json())));
  ServerPlayConnectionEvents.DISCONNECT.register((handler,server)->{driven.remove(handler.player.getUUID(),handler.player);BridgeSessions.disconnect(handler.player);});
 }
 public static boolean drives(Entity e){return e instanceof ServerPlayer p?BridgeSessions.authenticated(p)&&(isDriven(p)||(!p.level().getServer().isDedicatedServer()&&Passthrough.hostMovesPlayer)):Passthrough.hostMovesPlayer;}
 private static void sendPayload(ServerPlayer p,JsonObject r){if(r!=null&&ServerPlayNetworking.canSend(p,BridgePayload.TYPE))ServerPlayNetworking.send(p,new BridgePayload(r.toString()));}
 private static void send(ServerPlayer p,JsonObject r){sendPayload(p,BridgeSessions.envelope(p,r));}
 private static void reply(ServerPlayer p,JsonObject q,JsonObject r){JsonObject out=new JsonObject();out.addProperty("t","reply");if(q.has("request"))out.add("request",q.get("request"));out.add("result",r);send(p,out);}
 private static JsonObject error(String message){JsonObject r=new JsonObject();r.addProperty("ok",false);r.addProperty("error",message==null?"Invalid bridge request":message);return r;}
 private static void handle(MinecraftServer s,ServerPlayer p,String raw){
  JsonObject q;
  try{q=JsonParser.parseString(raw).getAsJsonObject();}catch(RuntimeException e){return;}
  try{
   if(!q.has("t")||!q.get("t").isJsonPrimitive()||!q.getAsJsonPrimitive("t").isString())throw new IllegalArgumentException("Missing bridge operation");
   if(!q.get("t").getAsString().equals("hello")&&!BridgeSessions.require(p,q)){reply(p,q,error("Session scope rejected"));return;}
   if(!operations.dispatch(q.get("t").getAsString(),new Request(s,p,q,r->reply(p,q,r))))reply(p,q,error("Unsupported bridge operation"));
  }catch(RuntimeException e){reply(p,q,error(e.getMessage()));Passthrough.LOG.warn("bridge request {}: {}",p.getUUID(),e.toString());}
 }
 public static void detach(MinecraftServer server){driven.clear();lastAdmin=null;adminTicks=0;if(server.isDedicatedServer()){Passthrough.active=false;Passthrough.events=raw->{};}}
 public static void attach(MinecraftServer s){
  driven.clear();lastAdmin=null;adminTicks=0;if(!s.isDedicatedServer())return;
  Passthrough.active=true;Passthrough.events=raw->publish(s,raw);
  Passthrough.LOG.info("PalCraft shared world authority ready");
 }
 private static void publish(MinecraftServer s,String raw){
  if(!BridgeEventPolicy.allows(raw))return;
  for(ServerPlayer p:s.getPlayerList().getPlayers())eventFor(p,raw);
  if(raw.startsWith("{\"t\":\"blocks\"")){
   try{Path path=Path.of(System.getProperty("palcraft.serverJournal","D:/PalworldServer-LAN/BridgeLab/rpc/authoritative-events.ndjson"));Files.createDirectories(path.getParent());Files.writeString(path,raw+"\n",StandardOpenOption.CREATE,StandardOpenOption.APPEND);}catch(Exception e){Passthrough.LOG.error("authoritative block journal: {}",e.toString());}
  }
 }
 public static void eventFor(ServerPlayer p,String raw){if(BridgeEventPolicy.allows(raw))sendPayload(p,BridgeSessions.eventFor(p,raw));}
 private static int adminTicks;
 static void tick(MinecraftServer s){
  if(!s.isDedicatedServer()||++adminTicks%10!=0)return;
  Path path=ROOT.resolve("server-request.json");if(!Files.exists(path))return;
  try{
   JsonObject q=JsonParser.parseString(Files.readString(path)).getAsJsonObject();String id=q.get("id").getAsString();if(id.equals(lastAdmin))return;lastAdmin=id;Files.deleteIfExists(path);
   if(q.get("method").getAsString().equals("stop")){s.saveEverything(false,true,true);s.halt(false);}
   else if(q.get("method").getAsString().equals("save"))s.saveEverything(false,true,true);
  }catch(Exception e){Passthrough.LOG.warn("shared world admin: {}",e.toString());}
 }
 private BridgeNetwork(){}
}
