package dev.rehan.passthrough;

import com.google.gson.*;
import java.nio.file.*;
import java.util.*;

/** Real child JVMs halt without cleanup at WAL, inventory-save and reply boundaries. No game is started. */
public final class ExchangeRecoveryCrashTest {
    private static final UUID PLAYER = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static String crash;
    private static void fault(String point) { if (point.equals(crash)) Runtime.getRuntime().halt(91); }
    private static void check(boolean value, String label) { if (!value) throw new AssertionError(label); }
    private static final class Inventory implements ExchangeRecovery.InventoryPort {
        private final Path root;
        Inventory(Path root) { this.root = root; }
        JsonObject data() throws Exception { return ExchangeJournal.read(root.resolve("inventory.json")); }
        @Override public boolean connected(UUID player) { return !Files.exists(root.resolve("offline")); }
        @Override public JsonArray snapshot(UUID player) throws Exception { JsonArray out = new JsonArray(); out.add(data().get("count")); return out; }
        @Override public int count(UUID player, String item) throws Exception { return data().get("count").getAsInt(); }
        @Override public int capacity(UUID player, String item) throws Exception { return data().get("capacity").getAsInt() - count(player, item); }
        @Override public void applyOnce(JsonObject row, String leg, int delta) throws Exception {
            JsonObject saved = data(); JsonArray receipts = saved.getAsJsonArray("receipts");
            String marker = row.get("id").getAsString() + ":" + leg;
            boolean recorded = receipts.asList().stream().anyMatch(v -> v.getAsString().equals(marker));
            if (!recorded) {
                if (delta < 0 && !snapshot(PLAYER).equals(row.get("mc_leg_before"))) throw new ExchangeRecovery.ExchangeHeld("changed source inventory");
                if (delta > 0 && capacity(PLAYER, "") < delta) throw new ExchangeRecovery.ExchangeHeld("full recipient inventory");
                fault("port_before:" + leg);
                saved.addProperty("count", saved.get("count").getAsInt() + delta); receipts.add(marker);
                fault("port_memory:" + leg);
                // Same-file atomic inventory+receipt commit, matching the production port's .dat contract.
                ExchangeJournal.write(root.resolve("inventory.json"), saved); fault("port_saved:" + leg);
            }
        }
    }
    private static void setup(Path root) throws Exception {
        Files.createDirectories(root);
        JsonObject inv = new JsonObject(); inv.addProperty("count", 20); inv.addProperty("capacity", 128); inv.add("receipts", new JsonArray());
        ExchangeJournal.write(root.resolve("inventory.json"), inv);
        JsonObject pal = new JsonObject(); pal.addProperty("count", 20); pal.add("receipts", new JsonArray());
        ExchangeJournal.write(root.resolve("sim-pal.json"), pal);
    }
    private static JsonObject row(Path root) throws Exception {
        try (var files = Files.newDirectoryStream(root, "mc-*.json")) {
            for (Path path : files) return ExchangeJournal.read(path);
        }
        throw new AssertionError("Missing transaction journal");
    }
    private static void pal(Path root, boolean reject) throws Exception {
        if (!Files.exists(root.resolve("request.json"))) return;
        JsonObject request = ExchangeJournal.read(root.resolve("request.json"));
        JsonObject reply = request.deepCopy();
        if (reject) { reply.addProperty("status", "rejected"); reply.addProperty("ok", false); reply.addProperty("error", "simulated full Pal inventory"); }
        else {
            JsonObject state = ExchangeJournal.read(root.resolve("sim-pal.json")); JsonArray receipts = state.getAsJsonArray("receipts");
            String id = request.get("id").getAsString();
            if (receipts.asList().stream().noneMatch(v -> v.getAsString().equals(id))) {
                int delta = request.get("action").getAsString().equals("debit") ? -8 : 8;
                state.addProperty("count", state.get("count").getAsInt() + delta); receipts.add(id);
                ExchangeJournal.write(root.resolve("sim-pal.json"), state); fault("pal_saved");
            }
            reply.addProperty("status", "completed"); reply.addProperty("durable", true); reply.addProperty("ok", true);
        }
        ExchangeJournal.write(root.resolve("result-" + request.get("id").getAsString() + ".json"), reply); fault("pal_reply");
    }
    private static void child(Path root, boolean start, boolean toMc, boolean reject) throws Exception {
        Inventory port = new Inventory(root);
        try (ExchangeRecovery engine = new ExchangeRecovery(root, port, (point, row) -> fault(point), 2)) {
            if (start) engine.begin(PLAYER, "00000000-0000-0000-0000-000000000001", "test-world", "Wood", "minecraft:oak_log", toMc, 8, result -> {});
            for (int i = 0; i < 12; i++) { engine.tick(); pal(root, reject); }
        }
    }
    private static int launch(Path root, boolean start, boolean toMc, boolean reject, String point) throws Exception {
        String java = Path.of(System.getProperty("java.home"), "bin", System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java").toString();
        Process process = new ProcessBuilder(java, "-cp", System.getProperty("java.class.path"), ExchangeRecoveryCrashTest.class.getName(),
            "child", root.toString(), Boolean.toString(start), Boolean.toString(toMc), Boolean.toString(reject), point).inheritIO().start();
        return process.waitFor();
    }
    private static void matrix(Path base, boolean toMc, boolean reject, List<String> points) throws Exception {
        for (String point : points) {
            Path root = base.resolve((toMc ? "import" : reject ? "refund" : "export") + "-" + point.replace(':', '_')); setup(root);
            check(launch(root, true, toMc, reject, point) == 91, "Fault point was not reached: " + point);
            check(launch(root, false, toMc, reject, "none") == 0, "Recovery process failed");
            for (int retry = 0; retry < 3; retry++) check(launch(root, false, toMc, reject, "none") == 0, "Duplicate recovery failed");
            JsonObject finalRow = row(root);
            check(finalRow.get("state").getAsString().equals(reject ? "refunded" : "completed"), "Not terminal: " + point + " " + finalRow);
            int mc = ExchangeJournal.read(root.resolve("inventory.json")).get("count").getAsInt();
            int pal = ExchangeJournal.read(root.resolve("sim-pal.json")).get("count").getAsInt();
            check(mc == (reject ? 20 : toMc ? 28 : 12), "Duplicate/missing MC effect: " + point);
            check(pal == (reject ? 20 : toMc ? 12 : 28), "Duplicate/missing Pal effect: " + point);
            check(mc + pal == 40, "Resource conservation failed: " + point);
            System.out.println("PASS crash " + (toMc ? "import" : reject ? "refund" : "export") + " " + point);
        }
    }
    private static void holds(Path base) throws Exception {
        Path root = base.resolve("full-and-offline"); setup(root); Inventory port = new Inventory(root);
        final Path fullRoot = root;
        try (ExchangeRecovery engine = new ExchangeRecovery(root, port, (point, row) -> {}, 2)) {
            engine.begin(PLAYER, "pal", "test-world", "Wood", "minecraft:oak_log", true, 8, result -> {});
            pal(root, false);
            JsonObject inv = port.data(); inv.addProperty("capacity", 20); ExchangeJournal.write(root.resolve("inventory.json"), inv);
            engine.tick(); check(engine.held() != null, "Full backpack transaction lost");
            engine.begin(PLAYER, "pal", "test-world", "Wood", "minecraft:oak_log", true, 8,
                response -> check(response.get("id").getAsString().equals(rowIdUnchecked(fullRoot)), "New request replaced held transaction"));
            Files.writeString(root.resolve("offline"), ""); inv.addProperty("capacity", 128); ExchangeJournal.write(root.resolve("inventory.json"), inv);
            engine.tick(); check(port.count(PLAYER, "") == 20, "Offline player was credited");
            Files.delete(root.resolve("offline")); engine.tick(); check(port.count(PLAYER, "") == 28, "Reconnect failed to restore held credit");
        }
        root = base.resolve("corrupt"); setup(root); Files.writeString(root.resolve("mc-" + UUID.randomUUID() + ".json"), "{broken");
        try (ExchangeRecovery engine = new ExchangeRecovery(root, new Inventory(root), (point, row) -> {}, 2)) {
            check(engine.held().has("error"), "Corrupt journal did not fail closed");
        }
        root = base.resolve("duplicate-owner"); setup(root);
        try (ExchangeRecovery first = new ExchangeRecovery(root, new Inventory(root), (point, row) -> {}, 2); ExchangeRecovery second = new ExchangeRecovery(root, new Inventory(root), (point, row) -> {}, 2)) {
            check(first.held() == null, "First owner failed"); check(second.held().has("error"), "Second owner obtained mailbox");
        }
        root = base.resolve("timeout-keeps-reservation"); setup(root); final int[] callbacks = {0}; Inventory timeoutPort = new Inventory(root);
        try (ExchangeRecovery engine = new ExchangeRecovery(root, timeoutPort, (point, row) -> {}, 2)) {
            engine.begin(PLAYER, "pal", "test-world", "Wood", "minecraft:oak_log", false, 8, response -> { check(response.get("pending").getAsBoolean(), "Timeout not pending"); callbacks[0]++; });
            Thread.sleep(15100); engine.tick(); check(callbacks[0] == 1 && engine.held() != null, "Timeout released transaction");
            check(timeoutPort.count(PLAYER, "") == 12, "Timeout applied debit twice");
            pal(root, false); engine.tick(); check(row(root).get("state").getAsString().equals("completed"), "Late confirmation did not recover");
        }
        root = base.resolve("io-error-after-credit"); setup(root); Inventory faultPort = new Inventory(root); JsonObject[] response = {null};
        try (ExchangeRecovery engine = new ExchangeRecovery(root, faultPort, (point, row) -> {
            if (point.equals("inventory:credit")) throw new java.io.IOException("simulated post-mutation journal error");
        }, 2)) {
            engine.begin(PLAYER, "pal", "test-world", "Wood", "minecraft:oak_log", true, 8, result -> response[0] = result);
            pal(root, false); engine.tick();
            check(response[0] != null && response[0].get("pending").getAsBoolean() && !response[0].get("ok").getAsBoolean(), "Disk error silently lost callback or acknowledged completion");
            check(engine.held() != null, "Disk error released reservation");
        }
        try (ExchangeRecovery engine = new ExchangeRecovery(root, new Inventory(root), (point, row) -> {}, 2)) {
            engine.tick(); check(row(root).get("state").getAsString().equals("completed"), "Restart did not recover durable credit receipt");
            check(new Inventory(root).count(PLAYER, "") == 28, "Post-error recovery duplicated credit");
        }
        System.out.println("PASS full inventory, offline/reconnect, corrupt WAL, duplicate coordinator, timeout/late reply, post-credit I/O error");
    }
    private static String rowIdUnchecked(Path root) { try { return row(root).get("id").getAsString(); } catch (Exception e) { throw new RuntimeException(e); } }
    private static JsonObject v3Lease(Path root, JsonObject mc, String status, int revision) throws Exception {
        JsonObject lease = new JsonObject(); JsonObject tx = new JsonObject();
        for (String key : List.of("protocol","id","mc_uid","player_uid","mc_world","item","count","action","fingerprint")) tx.add(key,mc.get(key));
        String cid = "33333333-3333-3333-3333-333333333333";
        lease.addProperty("protocol",3); lease.add("tx",tx); lease.add("owner_tx",mc.get("id"));
        lease.addProperty("container_id",cid); lease.addProperty("slot",0); lease.addProperty("generation",1);
        lease.addProperty("revision",revision); lease.addProperty("status",status);
        for (String stage : List.of("full","empty")) {
            if (stage.equals("empty") && revision < 4) continue;
            JsonObject witness = new JsonObject(); witness.addProperty("protocol",3); witness.add("id",mc.get("id")); witness.add("fingerprint",mc.get("fingerprint"));
            witness.addProperty("lease_generation",1); witness.addProperty("lease_revision",stage.equals("full") ? 1 : 3);
            witness.addProperty("container_id",cid); witness.addProperty("slot",0); witness.addProperty("stage",stage);
            witness.addProperty("durable",true); witness.addProperty("same_level_counterpart",true); witness.addProperty("save_sha256","f".repeat(64));
            JsonObject image = new JsonObject(); image.addProperty("container_id",cid); image.addProperty("slot",0);
            image.addProperty("count",stage.equals("full") ? 8 : 0); image.addProperty("item",stage.equals("full") ? "Wood" : "");
            witness.add("expected_after",image); lease.add(stage+"_witness",witness);
        }
        JsonObject leases = new JsonObject(); leases.add(cid,lease); JsonObject current = new JsonObject();current.addProperty("protocol",3);current.addProperty("revision",revision);current.add("leases",leases);
        ExchangeJournal.write(root.resolve("escrow-leases-current.json"),current);
        ExchangeJournal.write(root.resolve("escrow-"+cid+String.format(".r%06d.durable.json",revision)),lease);
        JsonObject result = mc.deepCopy();result.add("lease",lease);result.addProperty("status",status.equals("released") ? "completed" : status);
        if (status.equals("released")) result.addProperty("released",true);
        ExchangeJournal.write(root.resolve("result-"+mc.get("id").getAsString()+".json"),result);return lease;
    }
    private static void v3(Path base) throws Exception {
        crash = "none";
        for (boolean toMc : List.of(true,false)) {
            Path root = base.resolve(toMc ? "v3-import" : "v3-export");setup(root);Inventory port = new Inventory(root);
            try (ExchangeRecovery engine = new ExchangeRecovery(root,port)) {
                engine.begin(PLAYER,"00000000-0000-0000-0000-000000000001","test-world","Wood","minecraft:oak_log",toMc,8,r -> {});
                check(row(root).get("protocol").getAsInt()==3,"New transactions must use v3");
                v3Lease(root,row(root),"full_saved",2);engine.tick();
                check(port.count(PLAYER,"")==(toMc ? 28 : 12),"Saved full phase must authorize exactly one MC leg");
                check(!ExchangeRecovery.finished(row(root)),"Full phase cannot finish/release");
                v3Lease(root,row(root),"empty_saved",4);engine.tick();
                check(row(root).get("state").getAsString().equals("completed") && !ExchangeRecovery.finished(row(root)),"Durable terminal must retain coordination until Pal release");
            }
            try (ExchangeRecovery restarted = new ExchangeRecovery(root,port)) {
                restarted.tick();check(port.count(PLAYER,"")==(toMc ? 28 : 12),"Restart after terminal must not replay MC effect");
                v3Lease(root,row(root),"released",5);restarted.tick();
                check(ExchangeRecovery.finished(row(root)) && row(root).get("ok").getAsBoolean(),"Matched released generation must finish");
            }
            System.out.println("PASS v3 "+(toMc ? "import" : "export")+" full/empty/terminal/restart/release");
        }
    }
    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("v3")) { v3(Path.of(args[1])); return; }
        if (args.length > 0 && args[0].equals("child")) {
            crash = args[5]; child(Path.of(args[1]), Boolean.parseBoolean(args[2]), Boolean.parseBoolean(args[3]), Boolean.parseBoolean(args[4])); return;
        }
        Path base = Path.of(args.length > 0 ? args[0] : "exchange-jvm-evidence");
        matrix(base, true, false, List.of("journal:prepared", "journal:waiting_pal", "dispatch", "pal_saved", "pal_reply", "journal:applying_mc_credit", "port_before:credit", "port_memory:credit", "port_saved:credit", "inventory:credit", "journal:completed"));
        matrix(base, false, false, List.of("journal:prepared", "journal:applying_mc_debit", "port_before:debit", "port_memory:debit", "port_saved:debit", "inventory:debit", "journal:waiting_pal", "dispatch", "pal_saved", "pal_reply", "journal:completed"));
        matrix(base, false, true, List.of("journal:refunding_mc", "port_before:refund", "port_memory:refund", "port_saved:refund", "inventory:refund", "journal:refunded"));
        holds(base); System.out.println("PASS 28 hard-exit scenarios with repeated restarts; resource total stays 40");
    }
}
