package dev.rehan.passthrough;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.projectile.Projectile;
import java.util.function.Function;

/** Trusted server-file transport. Observing clients never get an entity damage operation. */
public final class PalEntityBridge {
    public record HostEntity(String id, String kind, double x, double y, double z, float yaw,
                             float hp, float maxHp, float width, float height, boolean alive,
                             boolean player, String playerUid, String group, String target,
                             double shield, double maxShield, boolean dying, double fullStomach, double maxFullStomach) {}
    private static final int LIMIT = 512;
    private static final Path ROOT = Path.of(System.getProperty("palcraft.entityDir",
            "D:/PalworldServer-LAN/PalCraft-Dev/bridge/entities"));
    private static final Path BRIDGE = Path.of(System.getProperty("palcraft.bridgeDir",
            "D:/PalworldServer-LAN/PalCraft-Dev/bridge"));
    private static final EntityCombatLedger ledger = new EntityCombatLedger(8192);
    private static final Map<String, Long> pending = new LinkedHashMap<>();
    private static final Map<Path,JsonObject> deferredPublications=new LinkedHashMap<>();
    private static String publicationError;
    private static final Map<String, HostEntity> hostStates = new HashMap<>();
    private static Function<UUID,String> playerUid = uuid -> null;
    private static Function<ServerPlayer,JsonObject> playerSession = player -> null;
    private static final Map<UUID,ServerPlayer> healthAvatars=new HashMap<>();
    private static JsonObject foodCapabilities;
    private static MinecraftServer attached;
    private static String session, palEpoch, epoch;
    private static long palRevision = -1, revision, ticks;
    private static long lastPalTick = Long.MIN_VALUE;
    private static String error, phase = "waiting_for_pal_server";
    private static int incoming, outgoing, rejected;
    private PalEntityBridge() {}

    /** Attach is idempotent; the existing MobWar tick can call it without a second tick registration. */
    public static void attach(MinecraftServer server) {
        if (attached == server) return;
        attached = server;
        epoch = UUID.randomUUID().toString();
        session = palEpoch = null;
        palRevision = -1;
        revision = ticks = 0;
        incoming = outgoing = rejected = 0;
        phase = "waiting_for_pal_server";
        error = null;
        pending.clear();deferredPublications.clear();publicationError=null;
        hostStates.clear();
        healthAvatars.clear();
        foodCapabilities=null;PalFoodBridge.attach(ROOT);
    }

    public static void tick(MinecraftServer server) {
        attach(server);
        ticks++;
        if (ticks % 2 != 0) return;
        try {
            Files.createDirectories(ROOT);
            flushPublications();
            readPalState();
            if (ready()) readPalHits(server);
            if (session != null && ticks % 10 == 0) EntityCombatLab.tick(server,ROOT,session);
            if (ticks % 4 == 0) { publish(server); writeHitIndex(); }
            if (ticks % 20 == 0) { pollResults();PalFoodBridge.tick();publishLater(ROOT.resolve("mc-status.json"), status()); }
            error = null;
        } catch (IOException | RuntimeException e) {
            error = e.toString();
            phase = "transport_error";
            Passthrough.LOG.warn("entity authority: {}", error);
        }
        if (lastPalTick != Long.MIN_VALUE && ticks - lastPalTick > 40) {
            phase = "pal_server_stale";
            MobWar.replaceHostEntities(List.of());
        }
    }

    public static boolean ready() {
        return session != null && palEpoch != null && ticks - lastPalTick <= 40 && phase.equals("active");
    }

    private static JsonObject read(Path path) throws IOException {
        if (!Files.exists(path)) return null;
        if (Files.size(path) > 1048576) throw new IOException("Entity message too large");
        return JsonParser.parseString(Files.readString(path)).getAsJsonObject();
    }

    private static void readPalState() throws IOException {
        JsonObject state = read(ROOT.resolve("pal-state.json"));
        if (state == null) return;
        JsonObject identity = read(BRIDGE.resolve("lab-identity.json"));
        if (identity == null || !identity.has("server_session_id")) { phase = "missing_lab_identity"; return; }
        String nextSession = str(state, "session"), nextPalEpoch = str(state, "epoch");
        if (integer(state, "v") != 1 || !str(state,"authority").equals("pal_server")
                || !nextSession.equals(str(identity,"server_session_id"))
                || !EntityCombatLedger.safeToken(nextPalEpoch)) { rejected++; return; }
        long unix = state.get("unix").getAsLong();
        long age = Instant.now().getEpochSecond() - unix;
        if (age < -5 || age > 3) { phase = "pal_server_stale"; return; }
        boolean changed = !nextSession.equals(session) || !nextPalEpoch.equals(palEpoch);
        long nextRevision = state.get("revision").getAsLong();
        if (!changed && nextRevision <= palRevision) return;
        JsonArray rows = state.getAsJsonArray("entities");
        if (rows == null || rows.size() > LIMIT) throw new IllegalArgumentException("Pal snapshot entity limit");
        List<HostEntity> parsed = new ArrayList<>();
        Set<String> ids = new HashSet<>();
        for (JsonElement row : rows) {
            JsonObject r = row.getAsJsonObject();
            String id = str(r,"id");
            if (!id.startsWith("pal:") || !EntityCombatLedger.entityId(id) || !ids.add(id))
                throw new IllegalArgumentException("Invalid or repeated Pal entity identity");
            String kind = str(r,"kind");
            if (kind.length() > 128) throw new IllegalArgumentException("Pal kind length");
            double x = number(r,"x"), y = number(r,"y"), z = number(r,"z");
            if (Math.abs(x) > 29999900 || Math.abs(z) > 29999900 || Math.abs(y) > 100000)
                throw new IllegalArgumentException("Pal entity outside bridge bounds");
            float hp = (float)number(r,"hp"), maxHp = (float)number(r,"max_hp");
            float width = (float)number(r,"width"), height = (float)number(r,"height");
            if (hp < 0 || maxHp <= 0 || width <= 0 || width > 64 || height <= 0 || height > 64)
                throw new IllegalArgumentException("Invalid Pal entity state");
            parsed.add(new HostEntity(id,kind,x,y,z,(float)number(r,"yaw"),hp,maxHp,width,height,
                    r.get("alive").getAsBoolean(), r.has("player") && r.get("player").getAsBoolean(),
                    optional(r,"player_uid"), optional(r,"group"), optional(r,"target"),
                    r.has("shield")?number(r,"shield"):0, r.has("max_shield")?number(r,"max_shield"):0,
                    r.has("dying")&&r.get("dying").getAsBoolean(),
                    r.has("full_stomach")?number(r,"full_stomach"):0,r.has("max_full_stomach")?number(r,"max_full_stomach"):100));
        }
        if (changed) {
            MobWar.clearHostEntities();
            pending.clear();
            ledger.reset(nextSession, epoch);
        }
        session = nextSession;
        palEpoch = nextPalEpoch;
        palRevision = nextRevision;
        lastPalTick = ticks;
        phase = "active";
        foodCapabilities=state.has("food")?state.getAsJsonObject("food").deepCopy():null;
        hostStates.clear();
        for(HostEntity h:parsed)hostStates.put(h.id(),h);
        MobWar.replaceHostEntities(parsed);
        JsonObject observation=state.deepCopy();observation.addProperty("t","pal_entity_snapshot");
        Passthrough.events.accept(observation.toString());
    }

    private static void readPalHits(MinecraftServer server) throws IOException {
        int budget = 32;
        try (DirectoryStream<Path> files = Files.newDirectoryStream(ROOT, "pal-hit-*.json")) {
            for (Path file : files) {
                String id = file.getFileName().toString().substring(8).replaceFirst("\\.json$", "");
                if (!EntityCombatLedger.uuid(id)) continue;
                Path resultPath = ROOT.resolve("mc-result-" + id + ".json");
                if (Files.exists(resultPath)) continue; // includes uncertain durable intents: never re-apply
                if (budget-- == 0) break;
                JsonObject q = read(file), result = new JsonObject();
                result.addProperty("id", id);
                result.addProperty("ok", false);
                try {
                    if (integer(q,"v") != 1 || !str(q,"authority").equals("pal_server") || !id.equals(str(q,"id")))
                        throw new IllegalArgumentException("Invalid Pal event envelope");
                    EntityCombatLedger.Hit hit = new EntityCombatLedger.Hit(id,str(q,"session"),str(q,"target_epoch"),
                            str(q,"source_epoch"),str(q,"target"),str(q,"source"),number(q,"amount"),str(q,"kind"));
                    EntityCombatLedger.Decision decision = ledger.inspect(hit);
                    result.addProperty("decision", decision.name());
                    if (decision != EntityCombatLedger.Decision.ACCEPT || !hit.sourceEpoch().equals(palEpoch)) {
                        result.addProperty("status", "rejected_authority_or_replay"); rejected++;
                    } else {
                        Entity target = find(server, hit.target());
                        ServerPlayer player = playerForPal(server, hit.source());
                        LivingEntity attacker = player!=null?player:MobWar.proxyFor(hit.source());
                        if (!(target instanceof Mob mob) || MobWar.isProxy(target) || !mob.isAlive() || attacker == null)
                            throw new IllegalArgumentException("Entity source or target unavailable");
                        if (mob.level() != attacker.level() || mob.distanceToSqr(attacker) > 256*256)
                            throw new IllegalArgumentException("Cross-world or out-of-range native hit");
                        ServerLevel level = (ServerLevel)mob.level();
                        DamageSource source = level.damageSources().mobAttack(attacker);
                        if (player != null) source = level.damageSources().playerAttack(player);
                        result.addProperty("status", "in_flight");
                        result.addProperty("fingerprint", hit.fingerprint());
                        write(resultPath, result); // uncertain crash window is visible, not replayed
                        ledger.reserve(hit);
                        float before = mob.getHealth();
                        boolean accepted = mob.hurtServer(level, source, (float)hit.amount());
                        result.addProperty("ok", true);
                        result.addProperty("accepted", accepted);
                        result.addProperty("before_hp", before);
                        result.addProperty("after_hp", mob.getHealth());
                        result.addProperty("alive", mob.isAlive());
                        result.addProperty("status", "applied");
                        result.addProperty("drop_owner", "minecraft");
                        incoming++;
                    }
                } catch (RuntimeException e) {
                    result.addProperty("status", "rejected");
                    result.addProperty("error", e.toString());
                    rejected++;
                }
                write(resultPath, result);
            }
        }
    }

    private static ServerPlayer playerForPal(MinecraftServer server, String palId) {
        HostEntity h=hostStates.get(palId);
        return h!=null&&h.player()?boundPlayer(server,h.playerUid()):null;
    }

    /** Only the verified multiplayer owner may provide this connection-scoped binding. */
    public static void bindPlayerUidResolver(Function<UUID,String> resolver){playerUid=Objects.requireNonNull(resolver);}
    public static void bindPlayerSessionResolver(Function<ServerPlayer,JsonObject> resolver){playerSession=Objects.requireNonNull(resolver);}
    public static JsonObject authorityContext(){JsonObject r=envelope("entity_authority","mc_server");r.addProperty("epoch",epoch);r.addProperty("source_epoch",epoch);r.addProperty("target_epoch",palEpoch);return r;}
    public static JsonObject foodContext(ServerPlayer p){
        if(!ready()||!ownsHealth(p))return null;HostEntity h=playerState(p);JsonObject proof=playerSession.apply(p);
        if(h==null||!h.alive()||h.dying()||proof==null)return null;
        JsonObject r=authorityContext();r.addProperty("source",EntityCombatLedger.mcId(p.getUUID()));r.addProperty("target",h.id());r.add("player_session",proof.deepCopy());return r;
    }
    public static boolean foodReady(ServerPlayer p){
        JsonObject context=foodContext(p);if(context==null||foodCapabilities==null||!foodCapabilities.has("enabled")||!foodCapabilities.get("enabled").getAsBoolean())return false;
        String target=context.get("target").getAsString();
        for(JsonElement id:foodCapabilities.getAsJsonArray("ready_players"))if(target.equals(id.getAsString()))return true;
        return false;
    }
    public static ServerPlayer boundPlayer(MinecraftServer server,String uid){
        if(uid==null||uid.isEmpty())return null;
        for(ServerPlayer p:server.getPlayerList().getPlayers())if(uid.equals(playerUid.apply(p.getUUID())))return p;
        return null;
    }
    public static HostEntity playerState(ServerPlayer p){
        String uid=playerUid.apply(p.getUUID());if(uid==null)return null;
        for(HostEntity h:hostStates.values())if(h.player()&&uid.equals(h.playerUid()))return h;
        return null;
    }
    /** Bound avatars retain Pal authority even while the snapshot is stale: never fall back to separate MC health. */
    public static boolean ownsHealth(ServerPlayer p){
        if(playerUid.apply(p.getUUID())!=null){healthAvatars.put(p.getUUID(),p);return true;}
        return healthAvatars.get(p.getUUID())==p;
    }
    public static void syncPlayers(MinecraftServer server){
        if(!ready())return;
        for(ServerPlayer p:server.getPlayerList().getPlayers()){
            if(!ownsHealth(p))continue;HostEntity h=playerState(p);if(h==null)continue;
            p.setHealth(EntityVitals.health(h.hp(),h.maxHp(),h.alive(),h.dying()));
            p.setAbsorptionAmount(0); // native Pal shield is displayed separately, never deducted by MC a second time
            p.getFoodData().setFoodLevel(EntityVitals.food(h.fullStomach(),h.maxFullStomach()));
            p.getFoodData().setSaturation(0);
            JsonObject v=envelope("player_vitals","pal_server");v.addProperty("mc_uuid",p.getUUID().toString());
            v.addProperty("player_uid",h.playerUid());v.addProperty("hp",h.hp());v.addProperty("max_hp",h.maxHp());
            v.addProperty("shield",h.shield());v.addProperty("max_shield",h.maxShield());v.addProperty("alive",h.alive());v.addProperty("dying",h.dying());
            v.addProperty("full_stomach",h.fullStomach());v.addProperty("max_full_stomach",h.maxFullStomach());v.addProperty("food_authority","pal_server");
            v.addProperty("life_active",true);v.addProperty("pal_epoch",palEpoch);v.addProperty("mc_epoch",epoch);
            BridgeNetwork.eventFor(p,v.toString());
        }
    }
    /** MC damage to the avatar (mobs, starvation, environment) goes through the same Pal ordinary damage path. */
    public static boolean playerHurt(ServerPlayer p,DamageSource source,float amount){
        if(!ownsHealth(p)||!ready()||amount<=0||!Float.isFinite(amount)||amount>10000)return false;
        HostEntity h=playerState(p);if(h==null||!h.alive())return false;
        Entity attacker=source.getEntity();if(attacker==null)attacker=source.getDirectEntity();
        // Native Pal damage already changed the real HP. The imported Pal source must never echo back.
        if(attacker!=null&&MobWar.isProxy(attacker))return false;
        // Pal already runs hunger and environmental physics. Only MC starvation must be suppressed altogether.
        if(source.typeHolder().unwrapKey().map(k->k.identifier().toString()).orElse("").equals("minecraft:starve"))return false;
        JsonObject event=envelope("entity_damage","mc_server");String id=UUID.randomUUID().toString();
        event.addProperty("id",id);event.addProperty("source_epoch",epoch);event.addProperty("target_epoch",palEpoch);
        event.addProperty("target",h.id());event.addProperty("source",EntityCombatLedger.mcId((attacker!=null?attacker:p).getUUID()));
        event.addProperty("source_kind",attacker!=null?BuiltInRegistries.ENTITY_TYPE.getKey(attacker.getType()).toString():"minecraft:environment");
        event.addProperty("source_player",attacker instanceof ServerPlayer);event.addProperty("environment",attacker==null);
        ServerPlayer responsible=attacker instanceof ServerPlayer a?a:attacker==null?p:null;
        if(responsible!=null){JsonObject binding=playerSession.apply(responsible);if(binding==null)return false;event.add("player_session",binding);}
        event.addProperty("amount",amount);
        event.addProperty("kind",source.typeHolder().unwrapKey().map(k->k.identifier().toString()).orElse("minecraft:generic"));
        event.addProperty("x",attacker!=null?attacker.getX():p.getX());event.addProperty("y",attacker!=null?attacker.getY():p.getY());event.addProperty("z",attacker!=null?attacker.getZ():p.getZ());
        try{write(ROOT.resolve("mc-hit-"+id+".json"),event);pending.put(id,ticks);outgoing++;return true;}
        catch(IOException e){error=e.toString();return false;}
    }

    private static Entity find(MinecraftServer server, String id) {
        if (!id.startsWith("mc:") || !EntityCombatLedger.entityId(id)) return null;
        UUID uuid = UUID.fromString(id.substring(3));
        for (ServerLevel level : server.getAllLevels()) { Entity e = level.getEntity(uuid); if (e != null) return e; }
        return null;
    }

    /** Called once by the server proxy damage mixin. The durable event is the only Pal damage authority. */
    public static boolean proxyHit(LivingEntity proxy, DamageSource damage, float amount) {
        if (!ready() || !Float.isFinite(amount) || amount <= 0 || amount > 10000) return false;
        HostEntity host = MobWar.hostFor(proxy);
        if (host == null || !host.alive()) return false;
        Entity attacker = damage.getEntity();
        if (attacker == null) attacker = damage.getDirectEntity();
        String kind=damage.typeHolder().unwrapKey().map(k -> k.identifier().toString()).orElse("minecraft:generic");
        boolean environment=attacker==null;
        if(environment&&(host.player()||!Set.of("minecraft:lava","minecraft:in_fire","minecraft:on_fire").contains(kind)))return false;
        if (attacker != null && MobWar.isProxy(attacker)) return false; // imported damage never echoes back
        String id = UUID.randomUUID().toString();
        JsonObject event = envelope("entity_damage", "mc_server");
        event.addProperty("id", id);
        event.addProperty("source_epoch", epoch);
        event.addProperty("target_epoch", palEpoch);
        event.addProperty("target", host.id());
        event.addProperty("source", EntityCombatLedger.mcId((environment?proxy:attacker).getUUID()));
        event.addProperty("source_kind",environment?"minecraft:environment_proxy":BuiltInRegistries.ENTITY_TYPE.getKey(attacker.getType()).toString());
        event.addProperty("environment",environment);event.addProperty("source_proxy",environment);
        event.addProperty("source_player", attacker instanceof ServerPlayer);
        if(attacker instanceof ServerPlayer p){JsonObject binding=playerSession.apply(p);if(binding==null)return false;event.add("player_session",binding);}
        event.addProperty("amount", amount);
        event.addProperty("kind",kind);
        Entity from=environment?proxy:attacker;
        event.addProperty("x", from.getX()); event.addProperty("y",from.getY()); event.addProperty("z",from.getZ());
        try {
            write(ROOT.resolve("mc-hit-"+id+".json"),event);
            pending.put(id,ticks);
            outgoing++;
            Passthrough.events.accept(event.toString()); // observers may display it; must never apply it
            return true;
        } catch (IOException e) { error = e.toString(); return false; }
    }

    /** Native deaths are notifications only; MC already ran its normal death/loot path. */
    public static void onDeath(LivingEntity e, DamageSource source) {
        if (!ready() || MobWar.isProxy(e) || !(e instanceof Mob)) return;
        JsonObject event = envelope("entity_death", "mc_server");
        event.addProperty("entity",EntityCombatLedger.mcId(e.getUUID()));
        event.addProperty("drop_owner","minecraft");
        if (source.getEntity()!=null) event.addProperty("killer",EntityCombatLedger.mcId(source.getEntity().getUUID()));
        Passthrough.events.accept(event.toString());
    }

    private static void publish(MinecraftServer server) throws IOException {
        JsonObject state = envelope("entity_snapshot","mc_server");
        state.addProperty("epoch",epoch); state.addProperty("revision",++revision);
        state.addProperty("ready",ready());
        JsonArray rows = new JsonArray();
        Set<UUID> seen = new HashSet<>();
        outer: for (ServerLevel level : server.getAllLevels()) {
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                if (player.level()!=level) continue;
                for (Entity e : level.getEntities((Entity)null,player.getBoundingBox().inflate(96),
                        a -> (a instanceof Mob || a instanceof Projectile) && !MobWar.isProxy(a))) {
                    if (!seen.add(e.getUUID())) continue;
                    rows.add(row(e,level));
                    if (rows.size()>=LIMIT) break outer;
                }
            }
        }
        state.add("entities", rows);
        state.add("host_proxies",MobWar.proxySnapshot());
        JsonArray players=new JsonArray();
        for(ServerPlayer p:server.getPlayerList().getPlayers()){
            if(!ownsHealth(p))continue;HostEntity h=playerState(p);if(h==null)continue;
            JsonObject v=new JsonObject();v.addProperty("mc_uuid",p.getUUID().toString());v.addProperty("pal_uid",h.playerUid());
            v.addProperty("hearts",p.getHealth());v.addProperty("max_hearts",p.getMaxHealth());
            v.addProperty("hp",h.hp());v.addProperty("max_hp",h.maxHp());v.addProperty("shield",h.shield());v.addProperty("max_shield",h.maxShield());
            v.addProperty("alive",h.alive());v.addProperty("dying",h.dying());v.addProperty("authority","pal_server");players.add(v);
            v.addProperty("food",p.getFoodData().getFoodLevel());v.addProperty("full_stomach",h.fullStomach());v.addProperty("max_full_stomach",h.maxFullStomach());
        }
        state.add("player_vitals",players);
        publishLater(ROOT.resolve("mc-state.json"), state);
        Passthrough.events.accept(state.toString());
    }

    private static JsonObject row(Entity e, ServerLevel level) {
        JsonObject r = new JsonObject();
        r.addProperty("id",EntityCombatLedger.mcId(e.getUUID())); r.addProperty("entity_id",e.getId());
        r.addProperty("kind",BuiltInRegistries.ENTITY_TYPE.getKey(e.getType()).toString());
        r.addProperty("dimension",level.dimension().identifier().toString());
        r.addProperty("category",e instanceof Mob?"mob":"projectile");
        r.addProperty("x",e.getX()); r.addProperty("y",e.getY()); r.addProperty("z",e.getZ());
        r.addProperty("yaw",e.getYRot()); r.addProperty("pitch",e.getXRot());
        r.addProperty("vx",e.getDeltaMovement().x); r.addProperty("vy",e.getDeltaMovement().y); r.addProperty("vz",e.getDeltaMovement().z);
        r.addProperty("width",e.getBbWidth()); r.addProperty("height",e.getBbHeight()); r.addProperty("alive",e.isAlive());
        if (e instanceof LivingEntity living) {
            r.addProperty("hp",living.getHealth()); r.addProperty("max_hp",living.getMaxHealth());
            r.addProperty("baby",living.isBaby()); r.addProperty("hurt",living.hurtTime>0);
            r.addProperty("age",e.tickCount);r.addProperty("walk_pos",living.walkAnimation.position());r.addProperty("walk_speed",living.walkAnimation.speed());
            r.addProperty("scale",living.getScale());r.addProperty("age_scale",living.getAgeScale());
            r.addProperty("hurt_time",living.hurtTime);r.addProperty("death_time",living.deathTime);r.addProperty("attack_time",living.getSwingAnimation(1));
            r.addProperty("body_yaw",living.yBodyRot);r.addProperty("head_yaw",net.minecraft.util.Mth.wrapDegrees(living.yHeadRot-living.yBodyRot));
            r.addProperty("head_pitch",living.getXRot());r.addProperty("current_swing",living.isSwinging());
            var swing=living.getCurrentSwing();r.addProperty("swing_arm",(swing==null?living.getMainArm():swing.hand().asArm(living.getMainArm())).name().toLowerCase(Locale.ROOT));
            if(swing!=null)r.addProperty("swing_hand",swing.hand().name().toLowerCase(Locale.ROOT));
        }
        if (e instanceof Mob mob) {
            r.addProperty("hostile",mob instanceof net.minecraft.world.entity.monster.Enemy);
            r.addProperty("aggressive",mob.isAggressive());
            LivingEntity target = mob.getTarget();
            if (target != null) { HostEntity h=MobWar.hostFor(target); r.addProperty("target",h!=null?h.id():EntityCombatLedger.mcId(target.getUUID())); }
        }
        if(e instanceof net.minecraft.world.entity.monster.Creeper creeper)r.addProperty("swelling",creeper.getSwelling(1));
        if(e instanceof net.minecraft.world.entity.animal.pig.Pig pig)r.addProperty("pig_variant",pig.getVariant().unwrapKey().map(k->k.identifier().toString()).orElse("minecraft:temperate"));
        if (e instanceof Projectile p && p.getOwner()!=null) r.addProperty("owner",EntityCombatLedger.mcId(p.getOwner().getUUID()));
        return r;
    }

    private static JsonObject envelope(String type,String authority) {
        JsonObject r=new JsonObject(); r.addProperty("v",1);r.addProperty("t",type);r.addProperty("authority",authority);
        r.addProperty("session",session==null?"pending":session);r.addProperty("unix",Instant.now().getEpochSecond()); return r;
    }
    private static void pollResults() throws IOException {
        for (var e : new ArrayList<>(pending.entrySet())) {
            JsonObject result=read(ROOT.resolve("pal-result-"+e.getKey()+".json"));
            if (result!=null) { pending.remove(e.getKey()); Passthrough.events.accept(result.toString()); }
        }
        writeHitIndex();
    }
    private static void writeHitIndex() throws IOException {
        JsonObject index=envelope("entity_hits","mc_server");index.addProperty("epoch",epoch);
        JsonArray ids=new JsonArray();for(String id:pending.keySet())ids.add(id);index.add("ids",ids);
        publishLater(ROOT.resolve("mc-hits.json"),index);
    }
    public static JsonObject status() {
        JsonObject r=envelope("entity_status","mc_server");r.addProperty("epoch",epoch);r.addProperty("phase",phase);
        r.addProperty("incoming",incoming);r.addProperty("outgoing",outgoing);r.addProperty("rejected",rejected);
        r.addProperty("pending",pending.size());r.addProperty("publication_pending",deferredPublications.size());
        if(publicationError!=null)r.addProperty("publication_error",publicationError);r.addProperty("pal_revision",palRevision);
        r.addProperty("proxies",MobWar.proxyCount());r.addProperty("legacy_damage_enabled",false);
        r.addProperty("player_health_authority","pal_server");
        r.add("food",PalFoodBridge.status());
        if(error!=null)r.addProperty("error",error);return r;
    }
    public static void detach(MinecraftServer server) {
        if(attached!=server)return;
        phase="detached";MobWar.clearHostEntities();
        EntityCombatLab.detach(server);
        try { write(ROOT.resolve("mc-status.json"),status()); } catch(IOException e){Passthrough.LOG.warn("entity detach: {}",e.toString());}
        attached=null;session=palEpoch=null;pending.clear();hostStates.clear();healthAvatars.clear();
    }
    /** Publication can wait for a Windows rb reader. Damage intents/receipts still use strict write(). */
    private static boolean publishLater(Path path,JsonObject value)throws IOException{
        try{write(path,value);deferredPublications.remove(path);if(deferredPublications.isEmpty())publicationError=null;return true;}
        catch(AccessDeniedException busy){
            Path temp=path.resolveSibling(path.getFileName()+".tmp");
            if(!Files.exists(path)||!Files.exists(temp))throw busy;
            deferredPublications.put(path,value.deepCopy());publicationError=busy.toString();return false;
        }
    }
    private static void flushPublications()throws IOException{
        int budget=4;
        for(var e:new ArrayList<>(deferredPublications.entrySet())){
            if(budget--==0)break;publishLater(e.getKey(),e.getValue());
        }
    }
    public static void write(Path path,JsonObject value) throws IOException {
        Path tmp=path.resolveSibling(path.getFileName()+".tmp");Files.writeString(tmp,value.toString());
        try{Files.move(tmp,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
        catch(AtomicMoveNotSupportedException e){Files.move(tmp,path,StandardCopyOption.REPLACE_EXISTING);}
    }
    private static String str(JsonObject r,String key){String s=r.get(key).getAsString();if(s.length()>256)throw new IllegalArgumentException("Entity field length");return s;}
    private static String optional(JsonObject r,String key){return r.has(key)&&!r.get(key).isJsonNull()?str(r,key):"";}
    private static int integer(JsonObject r,String key){return r.get(key).getAsInt();}
    private static double number(JsonObject r,String key){double n=r.get(key).getAsDouble();if(!Double.isFinite(n))throw new IllegalArgumentException("Non-finite entity value");return n;}
}
