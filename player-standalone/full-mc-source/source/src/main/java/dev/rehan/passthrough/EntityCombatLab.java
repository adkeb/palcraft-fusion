package dev.rehan.passthrough;

import com.google.gson.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntitySpawnReason;
import net.minecraft.world.entity.Mob;

/** Opt-in one-creature Lab fixture, server-owned file only. No item grants, healing, world commands or network API. */
public final class EntityCombatLab {
    public static final String TAG="palcraft_lab_entity";
    private static final Set<String> TYPES=Set.of("minecraft:zombie","minecraft:sheep","minecraft:skeleton");
    private EntityCombatLab(){}
    public static void tick(MinecraftServer server,Path root,String session){
        if(!Boolean.getBoolean("palcraft.entityLab"))return;
        Path request=root.resolve("lab-request.json");
        if(!Files.exists(request))return;
        try{
            if(Files.size(request)>8192)throw new IllegalArgumentException("Lab request too large");
            JsonObject q=JsonParser.parseString(Files.readString(request)).getAsJsonObject();String id=q.get("id").getAsString();
            if(!EntityCombatLedger.uuid(id))throw new IllegalArgumentException("Lab request UUID required");
            Path result=root.resolve("lab-result-"+id+".json");if(Files.exists(result))return;
            JsonObject out=new JsonObject();out.addProperty("id",id);out.addProperty("ok",false);
            try{
                long age=Instant.now().getEpochSecond()-q.get("unix").getAsLong();
                if(age< -5||age>30||!session.equals(q.get("session").getAsString()))throw new IllegalArgumentException("Stale Lab request");
                String action=q.get("action").getAsString();
                if(action.equals("spawn")){
                    if(!PalEntityBridge.ready())throw new IllegalStateException("Pal authority must be fresh before Lab spawn");
                    String kind=q.get("kind").getAsString();if(!TYPES.contains(kind))throw new IllegalArgumentException("Lab creature type");
                    ServerPlayer p=server.getPlayerList().getPlayer(UUID.fromString(q.get("mc_player_uuid").getAsString()));
                    if(p==null)throw new IllegalArgumentException("Exact connected MC player required");
                    if(!tagged(server).isEmpty())throw new IllegalStateException("Clean up the existing one-creature fixture first");
                    Mob mob=(Mob)BuiltInRegistries.ENTITY_TYPE.getOptional(Identifier.parse(kind)).orElseThrow().create((ServerLevel)p.level(),EntitySpawnReason.COMMAND);
                    if(mob==null)throw new IllegalStateException("Vanilla creature factory returned null");
                    mob.setUUID(UUID.nameUUIDFromBytes(("palcraft-lab:"+id).getBytes(StandardCharsets.UTF_8)));
                    mob.addTag(TAG);mob.setNoAi(true);mob.setNoGravity(true);mob.setPersistenceRequired();
                    mob.snapTo(p.getX()+3,p.getY(),p.getZ(),0,0);
                    out.addProperty("status","in_flight");out.addProperty("entity",EntityCombatLedger.mcId(mob.getUUID()));
                    PalEntityBridge.write(result,out);
                    boolean added=((ServerLevel)p.level()).addFreshEntity(mob);out.addProperty("ok",added);
                    out.addProperty("status",added?"spawned_held_ai":"spawn_rejected");out.addProperty("native_mc_hp",mob.getHealth());
                    out.addProperty("ai_held",true);out.addProperty("items_granted",0);out.addProperty("player_hp_modified",false);
                }else if(action.equals("cleanup")){
                    int removed=0;
                    for(Entity e:tagged(server)){e.discard();removed++;}
                    out.addProperty("ok",true);out.addProperty("status","discarded_lab_creature_without_loot");out.addProperty("removed",removed);
                }else if(action.equals("release_ai")){
                    if(!PalEntityBridge.ready())throw new IllegalStateException("Pal authority must be fresh before Lab AI release");
                    UUID uuid=UUID.fromString(q.get("entity").getAsString().substring(3));Mob found=null;
                    for(ServerLevel l:server.getAllLevels())if(l.getEntity(uuid) instanceof Mob m&&m.entityTags().contains(TAG))found=m;
                    if(found==null)throw new IllegalArgumentException("Tagged Lab entity unavailable");
                    found.setNoAi(false);found.setNoGravity(false);out.addProperty("ok",true);out.addProperty("status","vanilla_ai_released");
                }else throw new IllegalArgumentException("Unsupported Lab action");
            }catch(RuntimeException e){out.addProperty("status","rejected");out.addProperty("error",e.toString());}
            PalEntityBridge.write(result,out);
        }catch(Exception e){Passthrough.LOG.warn("entity Lab fixture: {}",e.toString());}
    }
    public static void detach(MinecraftServer server){
        tagged(server).forEach(Entity::discard);
    }
    private static List<Entity> tagged(MinecraftServer server){
        List<Entity> found=new ArrayList<>();
        for(ServerLevel l:server.getAllLevels())for(Entity e:l.getAllEntities())if(e.entityTags().contains(TAG))found.add(e);
        return found;
    }
}
