package dev.rehan.passthrough;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import net.minecraft.core.registries.BuiltInRegistries;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.FireworkRocketEntity;
import net.minecraft.world.entity.projectile.Projectile;
import net.minecraft.world.entity.projectile.arrow.AbstractArrow;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.Portal;
import net.minecraft.world.phys.Vec3;

/** Server-side half: the host's collision as invisible barrier blocks, commands, and events back to the host. */
public final class WorldBridge {
	private static volatile MinecraftServer server;
	/** Barriers we placed (so a reset only removes ours, never the player's builds). */
	private static final Map<ServerLevel, Set<BlockPos>> barriers = new ConcurrentHashMap<>();
	/** While placing or removing the host's own ground: those changes aren't news to the host (server thread only). */
	private static boolean placingGround;

	private WorldBridge() {
	}

	static void attach(final MinecraftServer s) {
		server = s;
        BridgeNetwork.attach(s);
		WorldCompatibility.attach(s);
	}

	static void detach() {
		WorldCompatibility.detach();
		server = null;
		barriers.clear();
		placingGround = false;
	}

	public static boolean ready() {
		return server != null;
	}

	static MinecraftServer server() {
		return server;
	}

	/** Columns of solid ground from the host: {x, z, yBottom, yTop, ...} in block coordinates (inclusive). Only air is replaced. */
	public static void solid(final int[] columns) {
		MinecraftServer s = server;
		if (s != null) solid(s.overworld(), columns);
	}

	/** A terrain batch is bound to the connection's authoritative dimension by the bridge entry point. */
	public static void solid(final ServerLevel level, final int[] columns) {
		MinecraftServer s = server;
		if (s == null || level.getServer() != s) return;
		s.execute(() -> {
			BlockState barrier = Blocks.BARRIER.defaultBlockState();
			BlockPos.MutableBlockPos pos = new BlockPos.MutableBlockPos();
			Set<BlockPos> placed = barriers.computeIfAbsent(level, ignored -> ConcurrentHashMap.newKeySet());
			boolean wasQuiet = placingGround;
			placingGround = true;
			try {
			for (int i = 0; i + 3 < columns.length; i += 4) {
				int bottom = Math.max(level.getMinY(),columns[i + 2]);
				int top = Math.min(level.getMaxY(),columns[i + 3]);
				for (int y = bottom; y <= top; y++) {
					pos.set(columns[i], y, columns[i + 1]);
					if (level.isInWorldBounds(pos) && level.getChunkSource().getChunkNow(pos.getX() >> 4, pos.getZ() >> 4) != null
						&& level.getBlockState(pos).isAir()
						&& level.setBlock(pos, barrier, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE)) {
						placed.add(pos.immutable());
					}
				}
			}

			} finally { placingGround = wasQuiet; }
		});
	}

	/** Remove every barrier we placed (e.g. when the host teleports somewhere else). */
	public static void clearSolid() {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		s.execute(() -> {
			boolean wasQuiet = placingGround;
			placingGround = true;
			try {
			for (var entry : barriers.entrySet()) {
				ServerLevel level = entry.getKey();
				for (BlockPos pos : entry.getValue()) {
					if (level.getChunkSource().getChunkNow(pos.getX() >> 4, pos.getZ() >> 4) != null
						&& level.getBlockState(pos).is(Blocks.BARRIER)) {
						level.setBlock(pos, Blocks.AIR.defaultBlockState(), Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
					}
				}
			}
			} finally { placingGround = wasQuiet; }
			barriers.clear();
		});
	}

    public static void inspectAt(int x,int y,int z,java.util.function.Consumer<JsonObject> reply){
        MinecraftServer s=server;if(s==null){reply.accept(new JsonObject());return;}
        inspectAt(s.overworld(),x,y,z,reply);
    }
    public static void inspectAt(ServerLevel level,int x,int y,int z,java.util.function.Consumer<JsonObject> reply){
        MinecraftServer s=server;if(s==null||level.getServer()!=s){reply.accept(new JsonObject());return;}
        s.execute(()->{var pos=new BlockPos(x,y,z);var r=WorldCompatibility.inspectBlock(level,pos);r.addProperty("t","blockinspection");
            if(!r.get("loaded").getAsBoolean()){reply.accept(r);return;}
            r.addProperty("x",x);r.addProperty("y",y);r.addProperty("z",z);r.addProperty("state",level.getBlockState(pos).toString());
            r.addProperty("above",level.getBlockState(pos.above()).toString());r.addProperty("below",level.getBlockState(pos.below()).toString());
            var entity=level.getBlockEntity(pos);if(entity!=null)r.addProperty("entity",entity.getClass().getSimpleName());
            if(entity instanceof net.minecraft.world.Container c){var items=new JsonArray();for(int i=0;i<c.getContainerSize();i++){var a=c.getItem(i);if(a.isEmpty())continue;var o=new JsonObject();o.addProperty("slot",i);o.addProperty("item",BuiltInRegistries.ITEM.getKey(a.getItem()).toString());o.addProperty("count",a.getCount());items.add(o);}r.add("items",items);}
            reply.accept(r);
        });
    }
	/** Read-only authoritative state, returned on the integrated server thread. */
	public static void inspect(java.util.function.Consumer<com.google.gson.JsonObject> reply) {
		MinecraftServer s=server;
		if(s==null){reply.accept(new com.google.gson.JsonObject());return;}
		s.execute(() -> {
			var result=new com.google.gson.JsonObject();
			var players=new com.google.gson.JsonArray();
			for(var p:s.getPlayerList().getPlayers()){
				var o=new com.google.gson.JsonObject();
				o.addProperty("name",p.getName().getString());o.addProperty("uuid",p.getUUID().toString());
				o.addProperty("dim",WorldCompatibility.dimension(p.level()));
				o.addProperty("x",p.getX());o.addProperty("y",p.getY());o.addProperty("z",p.getZ());
				o.addProperty("health",p.getHealth());o.addProperty("grounded",p.onGround());
				var inventory=new com.google.gson.JsonArray();
				for(int i=0;i<p.getInventory().getContainerSize();i++){
					var stack=p.getInventory().getItem(i);if(stack.isEmpty())continue;
					var slot=new com.google.gson.JsonObject();slot.addProperty("slot",i);
					slot.addProperty("item",net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(stack.getItem()).toString());slot.addProperty("count",stack.getCount());inventory.add(slot);
				}
				o.add("inventory",inventory);players.add(o);
			}
			result.add("players",players);
			var items=new com.google.gson.JsonArray();
			for(var e:s.overworld().getAllEntities())if(e instanceof net.minecraft.world.entity.item.ItemEntity item){
				if(items.size()>=64)break;
				var o=new com.google.gson.JsonObject();o.addProperty("item",net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(item.getItem().getItem()).toString());o.addProperty("count",item.getItem().getCount());
				o.addProperty("x",item.getX());o.addProperty("y",item.getY());o.addProperty("z",item.getZ());items.add(o);
			}
			result.add("dropped_items",items);result.add("world_compat",WorldCompatibility.status());reply.accept(result);
		});
	}

	/** Run a command as the server (op). Results go to the log, not to chat (send_command_feedback is off). */
	public static void command(final String command) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		s.execute(() -> {
			Passthrough.LOG.info("command: {}", command);
			s.getCommands().performPrefixedCommand(s.createCommandSourceStack(), command);
		});
	}

	/** Arrows the host already hit something with (they stay where they hit and aren't reported again). */
	private static final String HIT_TAG = "passthrough_hit";

	/** Every server tick: block changes, and projectiles in flight for the host to trace through its own world. */
	static void tick(final MinecraftServer s) {
		WorldCompatibility.tick(s);
		if (Passthrough.active) {
			reportProjectiles(s.overworld());
            reportDrops(s.overworld());
		}

		MobWar.tick(s);
		Nether.tick(s);
	}

    private static int dropTicks;
    private static void reportDrops(ServerLevel level){
        if(++dropTicks%4!=0)return;
        JsonObject r=new JsonObject();r.addProperty("unix",System.currentTimeMillis()/1000);JsonArray items=new JsonArray();
        for(Entity e:level.getAllEntities())if(e instanceof net.minecraft.world.entity.item.ItemEntity item){
            JsonObject a=new JsonObject();a.addProperty("id",item.getId());a.addProperty("item",BuiltInRegistries.ITEM.getKey(item.getItem().getItem()).toString());a.addProperty("count",item.getItem().getCount());a.addProperty("x",e.getX());a.addProperty("y",e.getY());a.addProperty("z",e.getZ());items.add(a);
        }
        r.add("items",items);
        if(level.getServer().isDedicatedServer()) {r.addProperty("t","drops");Passthrough.events.accept(r.toString());return;}
        try{var dir=java.nio.file.Path.of(System.getProperty("palcraft.bridgeDir","D:/PalworldServer-LAN/PalCraft-Dev/bridge"));var temp=dir.resolve("drops.tmp");java.nio.file.Files.writeString(temp,r.toString());java.nio.file.Files.move(temp,dir.resolve("drops.json"),java.nio.file.StandardCopyOption.REPLACE_EXISTING,java.nio.file.StandardCopyOption.ATOMIC_MOVE);}catch(java.io.IOException e){Passthrough.LOG.debug("drop display awaiting host: {}",e.toString());}
    }

	/**
	 * Steve's arrows (bow, crossbow) and crossbow fireworks in flight: {"t":"proj","p":[[id,kind,x,y,z],...]}. Mobs'
	 * arrows aren't traced by the host: they hit its people's proxies here.
	 */
	private static void reportProjectiles(final ServerLevel level) {
		StringBuilder b = null;
		for (Entity e : level.getAllEntities()) {
			String kind = null;
			if (!(e instanceof Projectile projectile) || !(projectile.getOwner() instanceof Player)) {
				continue;
			}

			if (e instanceof AbstractArrow arrow && !arrow.entityTags().contains(HIT_TAG) && arrow.getDeltaMovement().lengthSqr() > 1.0E-4) {
				kind = "arrow";
			} else if (e instanceof FireworkRocketEntity rocket && rocket.isShotAtAngle()) {
				kind = "firework"; // not the ones boosting an elytra flight
			}

			if (kind != null) {
				b = b == null ? new StringBuilder("{\"t\":\"proj\",\"p\":[") : b.append(',');
				b.append(String.format(Locale.ROOT, "[%d,\"%s\",%.3f,%.3f,%.3f]", e.getId(), kind, e.getX(), e.getY(), e.getZ()));
			}
		}

		if (b != null) {
			Passthrough.events.accept(b.append("]}").toString());
		}
	}

	/**
	 * The host traced a projectile into something of its own: a firework bursts there; an arrow goes into a person
	 * or car (gone) or sticks where it hit a wall.
	 */
	public static void projectileHit(final int id, final double x, final double y, final double z, final boolean stick) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		s.execute(() -> {
			ServerLevel level = s.overworld();
			Entity e = level.getEntity(id);
			if (e instanceof FireworkRocketEntity) {
				e.setPos(x, y, z);
				level.broadcastEntityEvent(e, (byte) 17);
				e.discard();
			} else if (e instanceof AbstractArrow) {
				if (stick) {
					e.setPos(x, y, z);
					e.setDeltaMovement(Vec3.ZERO);
					e.setNoGravity(true);
					e.addTag(HIT_TAG);
				} else {
					e.discard();
				}
			}
		});
	}

	/** Server thread, from Level.setBlock: remember the change; flushed once per tick. */
	public static void onBlockChanged(final ServerLevel level, final BlockPos pos, final BlockState state) {
		onBlockChanged(level, pos, state, 0);
	}
	public static void onBlockChanged(final ServerLevel level, final BlockPos pos, final BlockState state, final int flags) {
		if (!Passthrough.active) return;
		if (level == level.getServer().overworld()) Nether.onBlockChanged(pos, state);
		if (!placingGround) WorldCompatibility.blockChanged(level, pos, flags);
	}

	public static void onBlockEntityChanged(final ServerLevel level, final BlockPos pos, final String cause) {
		if (!placingGround) WorldCompatibility.blockEntityChanged(level, pos, cause);
	}

	public static void onPortalEnter(final ServerLevel level, final Entity entity, final Portal portal, final BlockPos pos) {
		WorldCompatibility.portalEnter(level, entity, portal, pos);
	}

	/** While on, block changes are the host's own ground being edited (not reported as blocks to collide with). */
	static void quietGround(final boolean on) {
		placingGround = on;
	}

	/** Flush the bounded authoritative delta queue. Legacy solid fields coexist with full v2 state. */
	static void flush(final MinecraftServer s) {
		WorldCompatibility.flush();
	}

	/** Loaded chunks in the player's own dimension, streamed in bounded replace snapshots. */
    public static void sync(final int radius){ sync(radius,null); }
    public static void sync(final int radius,final String requestId){
        MinecraftServer s=server;if(s==null||s.getPlayerList().getPlayers().isEmpty())return;syncFor(s.getPlayerList().getPlayers().get(0),radius,requestId);
    }
    public static void syncFor(final ServerPlayer player,final int radius){ syncFor(player,radius,null); }
    public static void syncFor(final ServerPlayer player,final int radius,final String requestId){
        MinecraftServer s=server;if(s==null)return;
        s.execute(()->WorldCompatibility.syncFor(player,radius,requestId));
	}

	/** Start vanilla gliding using the player's own equipped gear; stopping never deletes or gives equipment. */
	public static void glide(final boolean start, final double speed) {
		MinecraftServer s = server;
		if (s == null) {
			return;
		}

		s.execute(() -> {
			if (s.getPlayerList().getPlayers().isEmpty()) {
				return;
			}

			ServerPlayer player = s.getPlayerList().getPlayers().get(0);
			if (start) {
				player.tryToStartFallFlying();
			} else {
				player.stopFallFlying();
			}
		});
	}

	/** `source`: what exploded or was blown up, e.g. "tnt", "creeper", "fireball" (a ghast's). */
	public static void onExplosion(final Vec3 center, final float radius, final String source) {
		MinecraftServer s=server;if(s!=null)onExplosion(s.overworld(),center,radius,source,-1,"unknown");
	}
	public static void onExplosion(final ServerLevel level, final Vec3 center, final float radius, final String source,
			final int affectedCount, final String interaction) {
		WorldCompatibility.explosion(level,center,radius,source,affectedCount,interaction);
	}
}
