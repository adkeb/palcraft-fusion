package dev.rehan.passthrough;

import dev.rehan.passthrough.mixin.MobAccessor;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import com.google.gson.*;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.DamageTypeTags;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.*;
import net.minecraft.world.entity.ai.goal.GoalSelector;
import net.minecraft.world.entity.ai.memory.MemoryModuleType;
import net.minecraft.world.entity.ai.memory.MemoryStatus;
import net.minecraft.world.entity.monster.Enemy;
import net.minecraft.world.entity.npc.villager.Villager;
import net.minecraft.world.entity.projectile.Projectile;

/** Original MC mobs keep their own AI, health, inventory, death and loot. Pal bodies have explicit authority. */
public final class MobWar {
    public static final String PROXY_TAG="palcraft_proxy";
    private static final String LEGACY_PROXY_TAG="gta_proxy";
    private static final String MARKER="palcraft:proxy/";
    private static final Map<String,Villager> proxies=new HashMap<>();
    private static final Map<UUID,PalEntityBridge.HostEntity> hostOf=new HashMap<>();
    private static final Map<String,PalEntityBridge.HostEntity> hosts=new HashMap<>();
    private static final Map<UUID,HitWindow> windows=new HashMap<>();
    private static List<PalEntityBridge.HostEntity> newest=List.of();
    private static final Set<String> BRAIN_MOBS=Set.of("piglin","piglin_brute","hoglin","zoglin","breeze","creaking","warden");
    private record HitWindow(long tick,float amount) {}
    private MobWar() {}

    /** Invisibility alone is never an identity: invisible ordinary villagers remain normal villagers. */
    public static boolean isProxy(Entity e) {
        return e instanceof Villager && (e.entityTags().contains(PROXY_TAG)
                || (e.getCustomName()!=null && e.getCustomName().getString().startsWith(MARKER)));
    }
    static PalEntityBridge.HostEntity hostFor(Entity e){return hostOf.get(e.getUUID());}
    static LivingEntity proxyFor(String id){Villager v=proxies.get(id);return v!=null&&!v.isRemoved()?v:null;}
    public static int proxyCount(){return proxies.size();}
    static JsonArray proxySnapshot(){
        JsonArray rows=new JsonArray();
        for(var e:proxies.entrySet()){
            Villager v=e.getValue();if(v.isRemoved())continue;
            JsonObject r=new JsonObject();r.addProperty("id",EntityCombatLedger.mcId(v.getUUID()));r.addProperty("pal_id",e.getKey());
            r.addProperty("dimension",v.level().dimension().identifier().toString());r.addProperty("x",v.getX());r.addProperty("y",v.getY());r.addProperty("z",v.getZ());rows.add(r);
            r.addProperty("width",v.getBoundingBox().getXsize());r.addProperty("height",v.getBoundingBox().getYsize());
        }
        return rows;
    }
    static void replaceHostEntities(List<PalEntityBridge.HostEntity> next){newest=List.copyOf(next);}
    static void clearHostEntities(){clearProxies();newest=List.of();}

    /** Legacy client-supplied GTA handles and damage have no Pal server authority and are intentionally rejected. */
    @Deprecated public static void peds(double[] flat){Passthrough.LOG.debug("Rejected legacy peds; use Pal server entity snapshot");}
    @Deprecated public static void damage(int id,double amount){Passthrough.LOG.warn("Rejected unauthenticated legacy mobdmg for runtime entity {}",id);}

    static void onEntityLoad(Entity e,ServerLevel level) {
        if(e instanceof Villager v && (v.entityTags().contains(LEGACY_PROXY_TAG)
                || (isProxy(v)&&!proxies.containsValue(v)))){v.discard();return;}
        if(!(e instanceof Mob mob)||!(e instanceof Enemy)||isProxy(e))return;
        GoalSelector targets=((MobAccessor)mob).passthrough$targetSelector();
        if(targets.getAvailableGoals().stream().noneMatch(w->w.getGoal() instanceof ProxyTargetGoal))
            targets.addGoal(3,new ProxyTargetGoal(mob));
    }

    /** Return true only after a unique, durable event was created. Vanilla melee wear and projectile impact then work. */
    public static boolean onProxyHit(LivingEntity proxy,DamageSource source,float amount) {
        if(!(proxy.level() instanceof ServerLevel level)||!Float.isFinite(amount)||amount<=0)return false;
        long now=level.getGameTime();HitWindow old=windows.get(proxy.getUUID());float forwarded=amount;
        boolean bypass=source.is(DamageTypeTags.BYPASSES_COOLDOWN);
        if(!bypass&&old!=null&&now-old.tick()<10){if(amount<=old.amount())return false;forwarded=amount-old.amount();}
        boolean accepted=PalEntityBridge.proxyHit(proxy,source,forwarded);
        if(accepted){
            windows.put(proxy.getUUID(),new HitWindow(old!=null&&!bypass&&now-old.tick()<10?old.tick():now,amount));
            proxy.hurtTime=10;
        }
        return accepted;
    }

    static void tick(MinecraftServer server) {
        PalEntityBridge.tick(server);
        syncProxies(server.overworld());
        PalEntityBridge.syncPlayers(server);
    }
    private static void syncProxies(ServerLevel level) {
        Map<String,PalEntityBridge.HostEntity> next=new HashMap<>();
        for(PalEntityBridge.HostEntity h:newest){
            if(!h.alive())continue;
            // A bound Pal player already has their MC avatar; do not give the same person a second hit target.
            if(h.player()&&PalEntityBridge.boundPlayer(level.getServer(),h.playerUid())!=null)continue;
            next.put(h.id(),h);Villager v=proxies.get(h.id());
            if(v==null||v.isRemoved()){
                v=EntityTypes.VILLAGER.create(level,EntitySpawnReason.COMMAND);if(v==null)continue;
                v.setInvisible(true);v.addEffect(new MobEffectInstance(MobEffects.INVISIBILITY,MobEffectInstance.INFINITE_DURATION,0,false,false),null);
                v.setNoAi(true);v.setNoGravity(true);v.setSilent(true);v.addTag(PROXY_TAG);
                v.setCustomName(Component.literal(MARKER+h.id()));v.setCustomNameVisible(false);
                v.snapTo(h.x(),h.y(),h.z(),h.yaw(),0);
                proxies.put(h.id(),v);hostOf.put(v.getUUID(),h);
                if(!level.addFreshEntity(v)){proxies.remove(h.id());hostOf.remove(v.getUUID());continue;}
            }else{v.setPos(h.x(),h.y(),h.z());v.setYRot(h.yaw());hostOf.put(v.getUUID(),h);}
            // The native capsule's actual bounds drive MC contact, rather than a default villager's height/width.
            double half=h.width()/2;
            v.setBoundingBox(new net.minecraft.world.phys.AABB(h.x()-half,h.y(),h.z()-half,h.x()+half,h.y()+h.height(),h.z()+half));
        }
        for(var entry:new ArrayList<>(proxies.entrySet()))if(!next.containsKey(entry.getKey())){
            Villager v=entry.getValue();hostOf.remove(v.getUUID());windows.remove(v.getUUID());v.discard();proxies.remove(entry.getKey());
        }
        hosts.clear();hosts.putAll(next);
    }

    /** Goal and brain mobs share native attack behavior. Existing living targets keep priority. */
    public static void syncBrainTarget(Mob mob) {
        if(mob.level().isClientSide()||!PalEntityBridge.ready()||!BRAIN_MOBS.contains(BuiltInRegistries.ENTITY_TYPE.getKey(mob.getType()).getPath()))return;
        var brain=mob.getBrain();
        if(!brain.checkMemory(MemoryModuleType.ATTACK_TARGET,MemoryStatus.REGISTERED))return;
        Optional<LivingEntity> current=brain.getMemory(MemoryModuleType.ATTACK_TARGET);
        if(current.isPresent()&&current.get().isAlive()&&!current.get().isRemoved())return;
        LivingEntity closest=null;double dist=48*48;
        for(Villager v:proxies.values()){
            double d=v.distanceToSqr(mob);
            if(v.isAlive()&&!v.isRemoved()&&v.level()==mob.level()&&d<dist&&mob.hasLineOfSight(v)){closest=v;dist=d;}
        }
        if(closest!=null){brain.setMemory(MemoryModuleType.ATTACK_TARGET,closest);mob.setTarget(closest);}
    }
	/**
	 * Spawn `count` mobs of `kind` (e.g. "zombie") on the ground `minR`..`maxR` blocks from the player, within `arc`
	 * degrees either side of where the player faces (or of `yawOffset` from it); or, given `at` ({x, y, z}: a fixed
	 * spot, y near its ground), all round that spot instead, wherever the player is.
	 */
	public static void spawn(final String kind, final int count, final double minR, final double maxR, final double arc, final double yawOffset,
		final double[] at) {
		MinecraftServer s = serverOrNull();
		if (s == null) {
			return;
		}

		s.execute(() -> {
			ServerLevel level = s.overworld();
			ServerPlayer player = s.getPlayerList().getPlayers().isEmpty() ? null : s.getPlayerList().getPlayers().get(0);
			Optional<EntityType<?>> type = BuiltInRegistries.ENTITY_TYPE.getOptional(Identifier.withDefaultNamespace(kind));
			if (player == null || type.isEmpty()) {
				Passthrough.LOG.warn("spawnmobs: no player or unknown mob {}", kind);
				return;
			}

			ThreadLocalRandom random = ThreadLocalRandom.current();
			double cx = at != null ? at[0] : player.getX(), cy = at != null ? at[1] : player.getY(), cz = at != null ? at[2] : player.getZ();
			double baseYaw = at != null ? 0.0 : player.getYRot() + yawOffset, spread = at != null ? 180.0 : arc;
			int spawned = 0;
			for (int i = 0; i < count * 4 && spawned < count; i++) {
				double yaw = Math.toRadians(baseYaw + (random.nextDouble() * 2.0 - 1.0) * spread);
				double r = minR + random.nextDouble() * (maxR - minR);
				int x = (int) Math.floor(cx - Math.sin(yaw) * r), z = (int) Math.floor(cz + Math.cos(yaw) * r);
				BlockPos ground = groundAt(level, x, (int) Math.floor(cy), z);
				if (ground == null) {
					continue; // no host ground there (yet)
				}

				Entity e = type.get().spawn(level, ground, EntitySpawnReason.COMMAND);
				if (e instanceof Mob mob) {
					mob.setPersistenceRequired();
					spawned++;
				}
			}

			Passthrough.LOG.info("spawnmobs: {} x {}", spawned, kind);
		});
	}

	/** The free block above the host's ground near height y in column (x, z), or null. */
	private static BlockPos groundAt(final ServerLevel level, final int x, final int y, final int z) {
		BlockPos.MutableBlockPos p = new BlockPos.MutableBlockPos();
		for (int dy = 6; dy >= -12; dy--) {
			p.set(x, y + dy, z);
			if (!level.getBlockState(p).isAir() && level.getBlockState(p.above()).isAir() && level.getBlockState(p.above(2)).isAir()) {
				return p.above().immutable();
			}
		}

		return null;
	}

    /** Explicit developer helper only. Disconnect/shutdown never call this on natural mobs. */
    public static void clearMobs(){MinecraftServer s=serverOrNull();if(s!=null)s.execute(()->discardFighters(s.overworld()));}
    static void discardFighters(ServerLevel level){List<Entity> all=new ArrayList<>();level.getAllEntities().forEach(all::add);all.stream().filter(e->e instanceof Enemy&&!isProxy(e)).forEach(Entity::discard);}
    public static void hostGone(){MinecraftServer s=serverOrNull();if(s!=null)s.execute(MobWar::clearHostEntities);}
    private static void clearProxies(){proxies.values().forEach(Entity::discard);proxies.clear();hostOf.clear();hosts.clear();windows.clear();}
    static void detach(MinecraftServer s){PalEntityBridge.detach(s);clearHostEntities();}
    private static MinecraftServer serverOrNull(){return WorldBridge.server();}
}
