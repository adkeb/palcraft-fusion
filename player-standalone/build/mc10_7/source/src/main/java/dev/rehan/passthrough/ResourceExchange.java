package dev.rehan.passthrough;

import com.google.gson.*;
import java.nio.channels.FileChannel;
import java.security.MessageDigest;
import java.nio.file.*;
import java.util.*;
import java.util.function.Consumer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.*;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.storage.LevelResource;

/** Survival exchange with restart recovery; the UI's request/balances interface is unchanged. */
public final class ResourceExchange {
    public static final Map<String,String> MATERIALS = Map.of("Wood", "minecraft:oak_log", "Stone", "minecraft:cobblestone", "Coal", "minecraft:coal", "Charcoal", "minecraft:charcoal");
    private static final Path ROOT = Path.of(System.getProperty("palcraft.exchangeDir", "D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange"));
    private static MinecraftServer owner;
    private static ExchangeRecovery recovery;
    private static BalanceWait balance;
    private static int ticks;
    private record BalanceWait(UUID player, JsonObject request, Consumer<JsonObject> reply, long started) {}

    private static ExchangeRecovery coordinator(MinecraftServer server) throws Exception {
        if (owner != server) {
            if (recovery != null) recovery.close();
            owner = server; recovery = new ExchangeRecovery(ROOT, new MinecraftInventory(server));
            balance = null;
        }
        return recovery;
    }
    public static void request(UUID player, String material, boolean toMc, int amount, Consumer<JsonObject> reply) {
        MinecraftServer server = WorldBridge.server();
        if (server == null) { reply.accept(ExchangeRecovery.error("世界未连接")); return; }
        server.execute(() -> {
            try {
                if (amount == 0) { beginBalance(server, player, reply); return; }
                if (!MATERIALS.containsKey(material) || amount < 1 || amount > 64) throw new IllegalArgumentException("兑换数量无效");
                if (balance != null) throw new IllegalStateException("材料余额正在确认，请稍后重试");
                JsonObject identities = ExchangeJournal.read(ROOT.resolve("players.json"));
                if (!identities.has(player.toString())) throw new IllegalStateException("尚未绑定帕鲁角色");
                coordinator(server).begin(player, identities.get(player.toString()).getAsString(),
                    server.getWorldPath(LevelResource.ROOT).toAbsolutePath().normalize().toString(),
                    material, MATERIALS.get(material), toMc, amount, reply);
            } catch (Exception e) { reply.accept(ExchangeRecovery.error(e.getMessage())); }
        });
    }
    public static void balances(UUID player, Consumer<JsonObject> reply) { request(player, "", true, 0, reply); }
    private static JsonObject mcCounts(ServerPlayer player) {
        JsonObject counts = new JsonObject();
        if (player != null) for (var entry : MATERIALS.entrySet()) counts.addProperty(entry.getKey(), count(player, entry.getValue()));
        return counts;
    }
    private static void beginBalance(MinecraftServer server, UUID uuid, Consumer<JsonObject> reply) throws Exception {
        JsonObject held = coordinator(server).held();
        if (held != null) { held.add("mc_counts", mcCounts(server.getPlayerList().getPlayer(uuid))); reply.accept(held); return; }
        if (balance != null) { reply.accept(ExchangeRecovery.error("材料余额正在确认")); return; }
        ServerPlayer player = server.getPlayerList().getPlayer(uuid);
        if (player == null) throw new IllegalStateException("角色未连接");
        JsonObject identities = ExchangeJournal.read(ROOT.resolve("players.json"));
        if (!identities.has(uuid.toString())) throw new IllegalStateException("尚未绑定帕鲁角色");
        JsonObject row = new JsonObject(); row.addProperty("protocol", 3); row.addProperty("id", UUID.randomUUID().toString());
        row.addProperty("mc_uid", uuid.toString()); row.addProperty("player_uid", identities.get(uuid.toString()).getAsString());
        row.addProperty("mc_world", server.getWorldPath(LevelResource.ROOT).toAbsolutePath().normalize().toString());
        row.addProperty("action", "snapshot"); row.addProperty("item", ""); row.addProperty("count", 0);
        row.addProperty("fingerprint", ExchangeRecovery.fingerprint(row));
        ExchangeJournal.write(ROOT.resolve("request.json"), row);
        balance = new BalanceWait(uuid, row, reply, System.currentTimeMillis());
    }
    public static void tick(MinecraftServer server) {
        if (++ticks % 10 != 0) return;
        try {
            coordinator(server).tick();
            if (ticks % 100 == 0) retireTerminalReceipts(server);
            BalanceWait current = balance; if (current == null) return;
            Path result = ROOT.resolve("result-" + current.request.get("id").getAsString() + ".json");
            if (Files.exists(result)) {
                JsonObject out = ExchangeJournal.read(result);
                if (!ExchangeRecovery.matches(current.request, out)) throw new IllegalStateException("材料余额回执身份不一致");
                out.add("mc_counts", mcCounts(server.getPlayerList().getPlayer(current.player)));
                balance = null; current.reply.accept(out);
            } else if (System.currentTimeMillis() - current.started > 5000) {
                balance = null; current.reply.accept(ExchangeRecovery.error("帕鲁材料余额暂未确认"));
            }
        } catch (Exception e) {
            Passthrough.LOG.error("resource exchange recovery: {}", e.toString());
            if (balance != null) { BalanceWait current = balance; balance = null; current.reply.accept(ExchangeRecovery.error(e.getMessage())); }
        }
    }
    private static void retireTerminalReceipts(MinecraftServer server) throws Exception {
        boolean changed = false;
        String prefix = "palcraft.exchange.v2:";
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            for (String marker : new ArrayList<>(player.entityTags())) {
                if (!marker.startsWith(prefix) && !marker.startsWith("palcraft.exchange.v3:")) continue;
                String[] parts = marker.substring(prefix.length()).split(":");
                if (parts.length != 2) continue;
                try {
                    String id = UUID.fromString(parts[0]).toString();
                    Path path = ROOT.resolve("mc-" + id + ".json");
                    // A forced terminal coordinator record prevents any future replay of this leg.
                    if (Files.exists(path) && ExchangeRecovery.finished(ExchangeJournal.read(path))) {
                        player.removeTag(marker); changed = true;
                    }
                } catch (IllegalArgumentException ignored) {}
            }
        }
        if (changed) server.getPlayerList().saveAll();
    }
    /** Same-world/UUID respawn receipts only; inventory and normal drops remain vanilla. */
    public static void inheritPendingReceipts(ServerPlayer from, ServerPlayer to) {
        MinecraftServer server = WorldBridge.server();
        if (server == null || !from.getUUID().equals(to.getUUID()) || from.level().getServer() != server || to.level().getServer() != server) return;
        String world = server.getWorldPath(LevelResource.ROOT).toAbsolutePath().normalize().toString();
        for (String marker : from.entityTags()) {
            String prefix = marker.startsWith("palcraft.exchange.v2:") ? "palcraft.exchange.v2:" : marker.startsWith("palcraft.exchange.v3:") ? "palcraft.exchange.v3:" : null;
            if (prefix == null) continue;
            String[] parts = marker.substring(prefix.length()).split(":");
            if (parts.length != 2 || !Set.of("debit","credit","refund").contains(parts[1])) continue;
            String id;
            try { id = UUID.fromString(parts[0]).toString(); } catch (IllegalArgumentException invalidMarker) { continue; }
            try {
                Path path = ROOT.resolve("mc-" + id + ".json");
                if (!Files.exists(path)) continue; // No journal can replay a retired/unknown ID.
                JsonObject row = ExchangeJournal.read(path);
                if (ExchangeRecovery.finished(row) || row.get("protocol").getAsInt() != (prefix.equals("palcraft.exchange.v3:") ? 3 : 2) || !row.get("mc_uid").getAsString().equals(to.getUUID().toString()) || !row.get("mc_world").getAsString().equals(world)) continue;
            } catch (Exception auditUnavailable) {
                // A temporarily unreadable pending WAL cannot erase an already-saved receipt.
            }
            if (!to.entityTags().contains(marker) && !to.addTag(marker)) throw new IllegalStateException("Cannot inherit pending exchange receipt");
        }
    }
    private static int count(ServerPlayer player, String item) {
        int total = 0;
        for (int i = 0; i < 36; i++) {
            ItemStack stack = player.getInventory().getItem(i);
            if (BuiltInRegistries.ITEM.getKey(stack.getItem()).toString().equals(item)) total += stack.getCount();
        }
        return total;
    }
    private static int capacity(ServerPlayer player, ItemStack item) {
        int total = 0;
        for (int i = 0; i < 36; i++) {
            ItemStack stack = player.getInventory().getItem(i);
            if (stack.isEmpty()) total += item.getMaxStackSize();
            else if (ItemStack.isSameItemSameComponents(stack, item)) total += stack.getMaxStackSize() - stack.getCount();
        }
        return total;
    }
    private static JsonArray snapshot(ServerPlayer player) {
        JsonArray out = new JsonArray();
        for (int i = 0; i < 36; i++) {
            ItemStack stack = player.getInventory().getItem(i); JsonObject slot = new JsonObject();
            slot.addProperty("slot", i); slot.addProperty("item", BuiltInRegistries.ITEM.getKey(stack.getItem()).toString());
            slot.addProperty("count", stack.getCount()); slot.addProperty("components", stack.getComponents().toString()); out.add(slot);
        }
        return out;
    }
    private static final class MinecraftInventory implements ExchangeRecovery.InventoryPort {
        private final MinecraftServer server;
        MinecraftInventory(MinecraftServer server) { this.server = server; }
        private ServerPlayer player(UUID uuid) throws ExchangeRecovery.ExchangeHeld {
            ServerPlayer player = server.getPlayerList().getPlayer(uuid);
            if (player == null) throw new ExchangeRecovery.ExchangeHeld("材料已保留，角色重连后自动恢复");
            return player;
        }
        @Override public boolean connected(UUID uuid) { return server.getPlayerList().getPlayer(uuid) != null; }
        @Override public JsonArray snapshot(UUID uuid) throws Exception { return ResourceExchange.snapshot(player(uuid)); }
        @Override public int count(UUID uuid, String item) throws Exception { return ResourceExchange.count(player(uuid), item); }
        @Override public int capacity(UUID uuid, String item) throws Exception {
            return ResourceExchange.capacity(player(uuid), new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(item))));
        }
        @Override public void applyOnce(JsonObject row, String leg, int delta) throws Exception {
            String world = server.getWorldPath(LevelResource.ROOT).toAbsolutePath().normalize().toString();
            if (!row.get("mc_world").getAsString().equals(world)) throw new ExchangeRecovery.ExchangeHeld("交易属于另一个 MC 世界，已隔离");
            ServerPlayer player = player(UUID.fromString(row.get("mc_uid").getAsString()));
            String marker = "palcraft.exchange.v" + row.get("protocol").getAsInt() + ":" + row.get("id").getAsString() + ":" + leg;
            if (!player.entityTags().contains(marker)) {
                String item = row.get("mc_item").getAsString();
                ItemStack offered = new ItemStack(BuiltInRegistries.ITEM.getValue(Identifier.parse(item)), Math.abs(delta));
                if (delta < 0 && ResourceExchange.count(player, item) < -delta)
                    throw new ExchangeRecovery.ExchangeHeld("原材料背包与交易快照不一致，交易已保留");
                if (delta > 0 && ResourceExchange.capacity(player, offered) < delta)
                    throw new ExchangeRecovery.ExchangeHeld("材料已保留，背包腾出空间后自动恢复");
                // These vanilla tags and inventory are serialized in the SAME atomic player .dat.
                if (!player.addTag(marker)) throw new ExchangeRecovery.ExchangeHeld("MC 交易收据空间不足，材料已保留");
                List<ItemStack> before = new ArrayList<>();
                for (int i = 0; i < 36; i++) before.add(player.getInventory().getItem(i).copy());
                try {
                    if (delta < 0) {
                        int left = -delta;
                        for (int i = 0; i < 36 && left > 0; i++) {
                            ItemStack stack = player.getInventory().getItem(i);
                            if (BuiltInRegistries.ITEM.getKey(stack.getItem()).toString().equals(item)) {
                                int take = Math.min(left, stack.getCount()); stack.shrink(take); left -= take;
                            }
                        }
                        if (left != 0) throw new IllegalStateException("Inventory changed");
                    } else {
                        player.getInventory().add(offered);
                        if (!offered.isEmpty()) throw new IllegalStateException("Partial inventory credit");
                    }
                } catch (RuntimeException e) {
                    for (int i = 0; i < 36; i++) player.getInventory().setItem(i, before.get(i));
                    player.removeTag(marker); throw e;
                }
            }
            player.getInventory().setChanged(); player.inventoryMenu.broadcastChanges(); player.containerMenu.broadcastChanges();
            server.getPlayerList().saveAll();
            Path saved = server.getWorldPath(LevelResource.PLAYER_DATA_DIR).resolve(player.getUUID() + ".dat");
            try (FileChannel file = FileChannel.open(saved, StandardOpenOption.WRITE)) { file.force(true); }
            CompoundTag data = NbtIo.readCompressed(saved, NbtAccounter.unlimitedHeap());
            boolean durable = data.getListOrEmpty("Tags").stream().anyMatch(tag -> tag.asString().orElse("").equals(marker));
            if (!durable) throw new ExchangeRecovery.ExchangeHeld("MC 存档尚未确认交易收据，材料已保留");
            JsonObject receipt = new JsonObject();
            for (String key : List.of("protocol","id","fingerprint","mc_uid","mc_world")) receipt.add(key,row.get(key));
            receipt.addProperty("leg",leg); receipt.addProperty("marker",marker);
            receipt.addProperty("player_data",saved.toAbsolutePath().normalize().toString());
            receipt.addProperty("saved_player_sha256",HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(saved))));
            row.add("mc_" + leg + "_receipt",receipt);
        }
    }
    private ResourceExchange() {}
}
