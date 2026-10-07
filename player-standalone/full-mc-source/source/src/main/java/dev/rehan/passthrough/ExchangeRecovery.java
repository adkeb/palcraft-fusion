package dev.rehan.passthrough;

import com.google.gson.*;
import java.io.IOException;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.Consumer;

/** Persistent coordinator. All callbacks and mutations run on the Minecraft server thread. */
public final class ExchangeRecovery implements AutoCloseable {
    public interface InventoryPort {
        boolean connected(UUID player);
        JsonArray snapshot(UUID player) throws Exception;
        int count(UUID player, String item) throws Exception;
        int capacity(UUID player, String item) throws Exception;
        /** Atomically save the mutation AND its receipt in the same player-data record. */
        void applyOnce(JsonObject row, String leg, int delta) throws Exception;
    }
    public interface Faults { void at(String point, JsonObject row) throws Exception; }
    private record Waiter(Consumer<JsonObject> callback, long started) {}
    private static final Set<String> TERMINAL = Set.of("completed", "rejected", "refunded");
    private final Path root;
    private final InventoryPort inventory;
    private final Faults faults;
    private final int protocol;
    private final Map<String, JsonObject> rows = new TreeMap<>();
    private final Map<String, Waiter> waiters = new HashMap<>();
    private FileChannel lockFile;
    private FileLock lock;
    private boolean loaded;
    private String failure;
    private String lastTransaction;
    private long lastDispatch;

    public ExchangeRecovery(Path root, InventoryPort inventory) { this(root, inventory, (point, row) -> {}); }
    public ExchangeRecovery(Path root, InventoryPort inventory, Faults faults) {
        this(root, inventory, faults, 3);
    }
    ExchangeRecovery(Path root, InventoryPort inventory, Faults faults, int protocol) {
        if (protocol != 2 && protocol != 3) throw new IllegalArgumentException("Exchange protocol");
        this.root = root; this.inventory = inventory; this.faults = faults; this.protocol = protocol;
    }
    public static boolean terminal(JsonObject row) { return row.has("state") && TERMINAL.contains(row.get("state").getAsString()); }
    private Path journal(JsonObject row) { return root.resolve("mc-" + row.get("id").getAsString() + ".json"); }
    private void save(JsonObject row) throws Exception {
        lastTransaction = row.get("id").getAsString();
        row.addProperty("updated_ms", System.currentTimeMillis());
        ExchangeJournal.write(journal(row), row);
        faults.at("journal:" + row.get("state").getAsString(), row);
    }
    private void load() throws IOException {
        if (loaded) return;
        Files.createDirectories(root);
        lockFile = FileChannel.open(root.resolve("coordinator.lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
        try { lock = lockFile.tryLock(); }
        catch (OverlappingFileLockException e) { throw new IOException("已有兑换协调器持有此目录", e); }
        if (lock == null) throw new IOException("已有兑换协调器持有此目录");
        try (DirectoryStream<Path> files = Files.newDirectoryStream(root, "mc-*.json")) {
            for (Path file : files) {
                JsonObject row = ExchangeJournal.read(file);
                String id = row.get("id").getAsString();
                if (!UUID.fromString(id).toString().equals(id) || !file.getFileName().toString().equals("mc-" + id + ".json"))
                    throw new IOException("交易 ID 与日志文件不一致");
                if (!terminal(row) && (!row.has("protocol") || row.get("protocol").getAsInt() != 2 && row.get("protocol").getAsInt() != 3)) {
                    // v1 had no player-data receipts: never infer whether its credit/refund ran.
                    row.addProperty("state", "needs_recovery");
                    row.addProperty("error", "旧版未完成交易没有存档收据，需要核对原始存档");
                    ExchangeJournal.write(file, row);
                }
                rows.put(id, row);
            }
        } catch (RuntimeException e) { throw new IOException("兑换日志损坏，已停止新增兑换", e); }
        loaded = true;
    }
    private JsonObject active() {
        return rows.values().stream().filter(r -> !finished(r))
            .min(Comparator.comparingLong(r -> r.has("created_ms") ? r.get("created_ms").getAsLong() : 0L)).orElse(null);
    }
    public JsonObject held() {
        try { load(); } catch (Exception e) { failure = e.getMessage(); }
        if (failure != null) return failedResponse(lastTransaction == null ? null : rows.get(lastTransaction));
        JsonObject row = active(); return row == null ? null : response(row);
    }
    public void begin(UUID player, String palPlayer, String world, String material, String mcItem,
                      boolean toMc, int count, Consumer<JsonObject> reply) {
        try {
            load();
            if (failure != null) throw new IOException(failure);
            JsonObject occupied = active();
            if (occupied != null) { reply.accept(response(occupied)); return; }
            if (!inventory.connected(player)) throw new IllegalStateException("角色未连接");
            if (count < 1 || count > 64) throw new IllegalArgumentException("兑换数量无效");
            if (toMc && inventory.capacity(player, mcItem) < count) throw new IllegalStateException("MC 背包空间不足");
            if (!toMc && inventory.count(player, mcItem) < count) throw new IllegalStateException("MC 背包材料不足");
            JsonObject row = new JsonObject();
            String id = UUID.randomUUID().toString();
            row.addProperty("protocol", protocol); row.addProperty("id", id); row.addProperty("mc_uid", player.toString());
            row.addProperty("player_uid", palPlayer); row.addProperty("mc_world", world);
            row.addProperty("item", material); row.addProperty("mc_item", mcItem); row.addProperty("count", count);
            row.addProperty("to_mc", toMc); row.addProperty("action", toMc ? "debit" : "credit");
            row.addProperty("state", "prepared"); row.addProperty("created_ms", System.currentTimeMillis());
            row.addProperty("fingerprint", fingerprint(row));
            row.add("mc_initial", inventory.snapshot(player));
            save(row);
            rows.put(id, row); waiters.put(id, new Waiter(reply, System.currentTimeMillis()));
            advance(row);
        } catch (Exception e) {
            if (e instanceof IOException) {
                Waiter waiting = lastTransaction == null ? null : waiters.get(lastTransaction);
                boolean notified = waiting != null && waiting.callback == reply;
                fail(e);
                if (!notified) reply.accept(failedResponse(lastTransaction == null ? null : rows.get(lastTransaction)));
            }
            else reply.accept(error(e.getMessage()));
        }
    }
    public void tick() {
        try {
            load();
            if (failure != null) { notifyFailure(); return; }
            JsonObject row = active();
            if (row != null) advance(row);
            for (var entry : new ArrayList<>(waiters.entrySet())) {
                JsonObject current = rows.get(entry.getKey());
                if (finished(current) || System.currentTimeMillis() - entry.getValue().started > 15000) {
                    waiters.remove(entry.getKey());
                    try { entry.getValue().callback.accept(response(current)); }
                    catch (RuntimeException ignored) { /* The durable transaction does not depend on reply delivery. */ }
                }
            }
        } catch (Exception e) {
            fail(e); // Never acknowledge a material mutation without the authoritative WAL.
        }
    }
    private JsonObject failedResponse(JsonObject row) {
        JsonObject out = row == null ? error(failure) : row.deepCopy();
        out.addProperty("ok", false); out.addProperty("pending", true); out.addProperty("state", "journal_unconfirmed");
        out.addProperty("error", "兑换日志暂未确认，交易已保留：" + failure);
        return out;
    }
    private void notifyFailure() {
        for (var entry : new ArrayList<>(waiters.entrySet())) {
            waiters.remove(entry.getKey());
            try { entry.getValue().callback.accept(failedResponse(rows.get(entry.getKey()))); }
            catch (RuntimeException ignored) { /* A disconnected reply consumer does not change transaction ownership. */ }
        }
    }
    private void fail(Exception error) { failure = error.getMessage(); notifyFailure(); }
    private void leg(JsonObject row, String leg, int delta) throws Exception {
        UUID player = UUID.fromString(row.get("mc_uid").getAsString());
        if (!inventory.connected(player)) { row.addProperty("blocked", "材料已保留，角色重连后自动恢复"); return; }
        if (!row.has("mc_leg_before") || !row.has("mc_leg") || !row.get("mc_leg").getAsString().equals(leg)) {
            row.addProperty("mc_leg", leg); row.add("mc_leg_before", inventory.snapshot(player)); save(row);
        }
        try {
            inventory.applyOnce(row, leg, delta);
            faults.at("inventory:" + leg, row);
            row.remove("blocked"); row.addProperty("mc_" + leg + "_durable", true);
            row.addProperty("mc_after", inventory.count(player, row.get("mc_item").getAsString()));
            if (leg.equals("debit")) row.addProperty("state", "waiting_pal");
            else { row.addProperty("state", leg.equals("refund") ? "refunded" : v3(row) ? "waiting_pal_cleanup" : "completed"); row.addProperty("ok", leg.equals("credit") && !v3(row)); }
            save(row);
        } catch (ExchangeHeld e) { row.addProperty("blocked", e.getMessage()); save(row); }
    }
    private void advance(JsonObject row) throws Exception {
        if (v3(row)) { advanceV3(row); return; }
        String state = row.get("state").getAsString();
        int amount = row.get("count").getAsInt(); boolean toMc = row.get("to_mc").getAsBoolean();
        switch (state) {
            case "prepared" -> {
                row.addProperty("state", toMc ? "waiting_pal" : "applying_mc_debit"); save(row);
                if (!toMc) leg(row, "debit", -amount);
            }
            case "applying_mc_debit" -> leg(row, "debit", -amount);
            case "applying_mc_credit" -> leg(row, "credit", amount);
            case "refunding_mc" -> leg(row, "refund", amount);
            case "needs_recovery" -> { return; }
            case "waiting_pal" -> {}
            default -> { if (!terminal(row)) throw new IOException("未知兑换阶段：" + state); }
        }
        if (!row.get("state").getAsString().equals("waiting_pal")) return;
        Path result = root.resolve("result-" + row.get("id").getAsString() + ".json");
        if (Files.exists(result)) {
            JsonObject pal;
            try { pal = ExchangeJournal.read(result); }
            catch (IOException e) { row.addProperty("blocked", "帕鲁回执写入未完成，正在等待重传"); dispatch(row); return; }
            if (!matches(row, pal)) {
                row.addProperty("state", "needs_recovery"); row.addProperty("error", "帕鲁回执与交易身份不一致"); save(row); return;
            }
            String status = pal.has("status") ? pal.get("status").getAsString() : "unknown";
            if (status.equals("rejected") && !pal.has("effect_attempted")) {
                row.add("pal", pal); row.addProperty("error", pal.has("error") ? pal.get("error").getAsString() : "帕鲁拒绝了兑换");
                row.addProperty("state", toMc ? "rejected" : "refunding_mc"); save(row);
                if (!toMc) leg(row, "refund", amount);
                return;
            }
            if (status.equals("completed") && pal.has("durable") && pal.get("durable").getAsBoolean() && pal.get("ok").getAsBoolean()) {
                row.add("pal", pal); row.remove("blocked");
                row.addProperty("state", toMc ? "applying_mc_credit" : "completed");
                if (!toMc) row.addProperty("ok", true);
                save(row); if (toMc) leg(row, "credit", amount); return;
            }
            row.add("pal", pal);
            row.addProperty("blocked", pal.has("error") ? pal.get("error").getAsString() : "等待帕鲁材料变更落盘确认");
        }
        dispatch(row);
    }
    private static boolean v3(JsonObject row) { return row.has("protocol") && row.get("protocol").getAsInt() == 3; }
    private static boolean flag(JsonObject row, String name) { return row.has(name) && row.get(name).getAsBoolean(); }
    /** completed is a durable release permit; the coordinator stays active until Pal acknowledges release. */
    public static boolean finished(JsonObject row) {
        return terminal(row) && (!v3(row) || !row.get("state").getAsString().equals("completed") || flag(row, "pal_released"));
    }
    private JsonObject installedLease(JsonObject row, JsonObject pal, String stage) throws Exception {
        if (!pal.has("lease")) throw new IOException("缺少持久 escrow 回执");
        JsonObject lease = pal.getAsJsonObject("lease");
        JsonObject current = ExchangeJournal.read(root.resolve("escrow-leases-current.json"));
        String cid = lease.get("container_id").getAsString();
        if (!current.has("leases") || !current.getAsJsonObject("leases").has(cid) ||
            !current.getAsJsonObject("leases").get(cid).equals(lease)) throw new ExchangeHeld("escrow current 已推进，等待新回执");
        Path durable = root.resolve("escrow-" + cid + String.format(".r%06d.durable.json", lease.get("revision").getAsInt()));
        if (!ExchangeJournal.read(durable).equals(lease) || !matches(row, lease.getAsJsonObject("tx")) ||
            !lease.get("owner_tx").getAsString().equals(row.get("id").getAsString()) || lease.get("slot").getAsInt() != 0)
            throw new IOException("escrow WAL 身份或持久收据不一致");
        int generation = lease.get("generation").getAsInt();
        if (generation < 1 || row.has("lease_generation") && row.get("lease_generation").getAsInt() != generation ||
            row.has("escrow_container_id") && !row.get("escrow_container_id").getAsString().equals(cid))
            throw new IOException("escrow 代号或容器不一致");
        JsonObject witness = lease.getAsJsonObject(stage + "_witness");
        if (witness == null || witness.get("protocol").getAsInt() != 3 || !flag(witness,"durable") || !flag(witness,"same_level_counterpart") ||
            !witness.get("id").equals(row.get("id")) || !witness.get("fingerprint").equals(row.get("fingerprint")) ||
            witness.get("lease_generation").getAsInt() != generation || witness.get("lease_revision").getAsInt() >= lease.get("revision").getAsInt() ||
            !witness.get("container_id").getAsString().equals(cid) || witness.get("slot").getAsInt() != 0 ||
            !witness.get("stage").getAsString().equals(stage) || !witness.get("save_sha256").getAsString().matches("[0-9a-f]{64}"))
            throw new IOException("escrow 存档回执阶段、代号或身份不一致");
        JsonObject image = witness.getAsJsonObject("expected_after");
        if (image.get("count").getAsInt() != (stage.equals("full") ? row.get("count").getAsInt() : 0) ||
            !image.get("item").getAsString().equals(stage.equals("full") ? row.get("item").getAsString() : "") ||
            !image.get("container_id").getAsString().equals(cid) || image.get("slot").getAsInt() != 0)
            throw new IOException("escrow 存档数量不一致");
        row.addProperty("lease_generation", generation); row.addProperty("escrow_container_id", cid);
        row.add(stage + "_escrow_receipt", witness.deepCopy());
        return lease;
    }
    private void advanceV3(JsonObject row) throws Exception {
        String state = row.get("state").getAsString();
        int amount = row.get("count").getAsInt(); boolean toMc = row.get("to_mc").getAsBoolean();
        switch (state) {
            case "prepared" -> {
                row.addProperty("state", toMc ? "waiting_pal" : "applying_mc_debit"); save(row);
                if (!toMc) leg(row,"debit",-amount);
            }
            case "applying_mc_debit" -> leg(row,"debit",-amount);
            case "applying_mc_credit" -> leg(row,"credit",amount);
            case "refunding_mc" -> leg(row,"refund",amount);
            case "needs_recovery" -> { return; }
            case "waiting_pal", "waiting_pal_cleanup", "completed" -> {}
            default -> { if (!terminal(row)) throw new IOException("未知 v3 兑换阶段：" + state); }
        }
        state = row.get("state").getAsString();
        if (!Set.of("waiting_pal","waiting_pal_cleanup","completed").contains(state) || finished(row)) return;
        Path result = root.resolve("result-" + row.get("id").getAsString() + ".json");
        if (Files.exists(result)) {
            JsonObject pal;
            try { pal = ExchangeJournal.read(result); }
            catch (IOException e) { dispatch(row); return; }
            if (!matches(row,pal)) {
                row.addProperty("state","needs_recovery"); row.addProperty("error","帕鲁回执与交易身份不一致"); save(row); return;
            }
            String status = pal.has("status") ? pal.get("status").getAsString() : "unknown";
            if (status.equals("rejected") && !pal.has("lease") && !flag(pal,"effect_attempted")) {
                row.add("pal",pal); row.addProperty("error",pal.has("error") ? pal.get("error").getAsString() : "帕鲁拒绝兑换");
                row.addProperty("state",toMc ? "rejected" : "refunding_mc"); save(row);
                if (!toMc) leg(row,"refund",amount); return;
            }
            try {
                if (status.equals("full_saved") && toMc && state.equals("waiting_pal")) {
                    installedLease(row,pal,"full"); row.add("pal",pal); row.remove("blocked");
                    row.addProperty("state","applying_mc_credit"); save(row); leg(row,"credit",amount);
                } else if (status.equals("empty_saved") && !state.equals("completed")) {
                    if (!flag(row,toMc ? "mc_credit_durable" : "mc_debit_durable")) throw new IOException("MC 对应材料收据未落盘");
                    installedLease(row,pal,"full"); installedLease(row,pal,"empty"); row.add("pal",pal);
                    row.addProperty("escrow_empty_durable",true); row.addProperty("state","completed");
                    row.addProperty("ok",false); row.remove("blocked"); save(row);
                } else if (status.equals("completed") && state.equals("completed") && flag(pal,"released")) {
                    JsonObject lease = installedLease(row,pal,"empty");
                    if (!lease.get("status").getAsString().equals("released")) throw new IOException("escrow 释放回执不一致");
                    row.add("pal",pal); row.addProperty("pal_released",true); row.addProperty("ok",true); save(row); return;
                } else row.addProperty("blocked",pal.has("error") ? pal.get("error").getAsString() : "材料已保留，等待 escrow 存档确认");
            } catch (ExchangeHeld held) { row.addProperty("blocked",held.getMessage()); }
        }
        dispatch(row);
    }
    private void dispatch(JsonObject row) throws Exception {
        if (System.currentTimeMillis() - lastDispatch < 1000) return;
        ExchangeJournal.write(root.resolve("request.json"), row);
        faults.at("dispatch", row); lastDispatch = System.currentTimeMillis();
    }
    public static boolean matches(JsonObject row, JsonObject pal) {
        for (String key : List.of("protocol", "id", "mc_uid", "player_uid", "mc_world", "item", "count", "action", "fingerprint"))
            if (!pal.has(key) || !row.get(key).equals(pal.get(key))) return false;
        return true;
    }
    public static String fingerprint(JsonObject row) throws Exception {
        JsonArray identity = new JsonArray();
        for (String key : List.of("protocol", "id", "mc_uid", "player_uid", "mc_world", "item", "count", "action")) identity.add(row.get(key));
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(identity.toString().getBytes(StandardCharsets.UTF_8)));
    }
    public static JsonObject error(String text) {
        JsonObject out = new JsonObject(); out.addProperty("ok", false); out.addProperty("error", text == null ? "兑换暂未确认" : text); return out;
    }
    private static JsonObject response(JsonObject row) {
        JsonObject out = row.deepCopy();
        if (!finished(row)) {
            out.addProperty("ok", false); out.addProperty("pending", true);
            out.addProperty("error", row.has("blocked") ? row.get("blocked").getAsString() : row.has("error") ? row.get("error").getAsString() : "交易已保留，确认后自动恢复；请勿重复提交");
        }
        return out;
    }
    public static final class ExchangeHeld extends Exception { public ExchangeHeld(String reason) { super(reason); } }
    @Override public void close() throws IOException {
        if (lock != null) lock.release(); if (lockFile != null) lockFile.close();
    }
}
