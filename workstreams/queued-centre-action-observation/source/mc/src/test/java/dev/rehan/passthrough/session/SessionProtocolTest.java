package dev.rehan.passthrough.session;

import com.google.gson.*;
import java.nio.file.*;
import java.security.KeyPair;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Pure-JDK regression/attack tests for the production admission and routing code. No Minecraft process or save. */
public final class SessionProtocolTest {
    private static final long NOW = 1800000000L;
    private static final String WORLD = "BridgeLab-fixture", BOOT = "Pal-boot-fixture";
    private static final KeyPair AUTHORITY = SessionCrypto.keys();
    private static final BridgeIdentity A = identity("11111111-1111-1111-1111-111111111111", "FixtureAlpha");
    private static final BridgeIdentity B = identity("22222222-2222-2222-2222-222222222222", "FixtureBravo");
    private static final GuestCredential CA = credential(A), CB = credential(B);
    private static final JsonArray RESULTS = new JsonArray();
    private static BridgeIdentity identity(String uid, String name) { return new BridgeIdentity(WORLD, uid, BridgeIdentity.offlineUuid(name), name); }
    private static GuestCredential credential(BridgeIdentity identity) {
        KeyPair keys = SessionCrypto.keys(); SessionGrant g = new SessionGrant(identity, BOOT, UUID.randomUUID(), NOW, NOW + 600, keys.getPublic(), SessionGrant.PLAYER_SCOPES);
        return new GuestCredential(g.signed(AUTHORITY.getPrivate()), g, keys.getPrivate());
    }
    private static SessionRegistry<Object> registry(String purpose) {
        return new SessionRegistry<>(WORLD, BOOT, purpose, "fixture:" + UUID.randomUUID(), token -> SessionGrant.verified(token, AUTHORITY.getPublic(), NOW, WORLD, BOOT));
    }
    private static SessionHandle admit(SessionRegistry<Object> r, Object c, GuestCredential g, long now) {
        JsonObject challenge = r.challenge(c, g.grant().identity(), now);
        return r.authenticate(c, g.answer("mc.login", challenge, now), now);
    }
    private static JsonObject message(SessionHandle h, long seq, String op) {
        JsonObject q = new JsonObject(); q.addProperty("t", op); q.add("session", h.json()); q.addProperty("seq", seq); return q;
    }
    private static void check(boolean value, String why) { if (!value) throw new AssertionError(why); }
    private static void rejects(Runnable action) {
        try { action.run(); } catch (SecurityException | IllegalArgumentException e) { return; }
        throw new AssertionError("Expected identity/proof/scope rejection");
    }
    @FunctionalInterface private interface Test { void run() throws Exception; }
    private static void test(String name, Test body) throws Exception {
        long started = System.nanoTime(); body.run(); JsonObject result = new JsonObject(); result.addProperty("name", name); result.addProperty("ok", true);
        result.addProperty("elapsed_ms", (System.nanoTime() - started) / 1000000); RESULTS.add(result);
    }
    public static void main(String[] args) throws Exception {
        test("authority_signature_and_public_certificate_without_private_keys", () -> {
            SessionGrant g = SessionGrant.verified(CA.token(), AUTHORITY.getPublic(), NOW, WORLD, BOOT);
            check(g.identity().equals(A), "Authority identity changed");
            check(!new String(SessionCrypto.decode(CA.token().split("\\.")[0])).contains("private"), "Private key leaked to certificate");
            check(!CA.token().contains(CA.hostSecret()), "Host secret leaked to certificate");
        });
        test("forged_pal_uid_and_scope_rejected", () -> {
            String[] p = CA.token().split("\\."); JsonObject raw = JsonParser.parseString(new String(SessionCrypto.decode(p[0]))).getAsJsonObject();
            raw.addProperty("pal_uid", B.palUid()); raw.getAsJsonArray("scopes").add("admin");
            String forged = SessionCrypto.encode(raw.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8)) + "." + p[1];
            rejects(() -> SessionGrant.verified(forged, AUTHORITY.getPublic(), NOW, WORLD, BOOT));
        });
        test("wrong_authority_world_and_pal_boot_rejected", () -> {
            rejects(() -> SessionGrant.verified(CA.token(), SessionCrypto.keys().getPublic(), NOW, WORLD, BOOT));
            rejects(() -> SessionGrant.verified(CA.token(), AUTHORITY.getPublic(), NOW, "other-world", BOOT));
            rejects(() -> SessionGrant.verified(CA.token(), AUTHORITY.getPublic(), NOW, WORLD, "previous-Pal-boot"));
        });
        test("stolen_public_certificate_has_no_holder_proof", () -> {
            var r = registry("mc.login"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW);
            GuestCredential attacker = new GuestCredential(CA.token(), CA.grant(), SessionCrypto.keys().getPrivate());
            rejects(() -> r.authenticate(c, attacker.answer("mc.login", challenge, NOW), NOW));
        });
        test("actual_mc_profile_binding_rejects_other_players_certificate", () -> {
            var r = registry("mc.login"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW);
            JsonObject answer = new JsonObject(); answer.addProperty("v", 2); answer.addProperty("grant", CB.token());
            answer.addProperty("proof", SessionCrypto.sign(CB.privateKey(), SessionGrant.proofText("mc.login", challenge, CB.token())));
            rejects(() -> r.authenticate(c, answer, NOW));
        });
        test("challenge_replay_other_connection_and_endpoint_rejected", () -> {
            var r = registry("mc.login"); Object c1 = new Object(), c2 = new Object();
            JsonObject q1 = r.challenge(c1, A, NOW), q2 = r.challenge(c2, A, NOW); JsonObject answer = CA.answer("mc.login", q1, NOW);
            rejects(() -> r.authenticate(c2, answer, NOW));
            r.authenticate(c1, answer, NOW); rejects(() -> r.authenticate(c1, answer, NOW));
            var other = registry("mc.login"); Object c3 = new Object(); other.challenge(c3, A, NOW); rejects(() -> other.authenticate(c3, answer, NOW));
        });
        test("expired_challenge_and_certificate_rejected", () -> {
            var r = registry("mc.login"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW); JsonObject answer = CA.answer("mc.login", challenge, NOW);
            rejects(() -> r.authenticate(c, answer, NOW + 16));
            rejects(() -> SessionGrant.verified(CA.token(), AUTHORITY.getPublic(), NOW + 600, WORLD, BOOT));
        });
        test("two_independent_players_share_one_registry_without_shared_control", () -> {
            var r = registry("mc.login"); Object a = new Object(), b = new Object(); SessionHandle ha = admit(r, a, CA, NOW), hb = admit(r, b, CB, NOW);
            check(r.snapshot(NOW).size() == 2 && !ha.sessionId().equals(hb.sessionId()), "Players collapsed to one session");
            for (String operation : List.of("host_pose", "key", "inventory_toggle", "pointer", "exchange")) {
                long seq = List.of("host_pose", "key", "inventory_toggle", "pointer", "exchange").indexOf(operation) + 1;
                check(r.accept(a, message(ha, seq, operation), NOW).identity().equals(A), "A routed to another player");
                check(r.accept(b, message(hb, seq, operation), NOW).identity().equals(B), "B routed to another player");
            }
            JsonObject attack = message(hb, 6, "key"); attack.addProperty("pal_uid", A.palUid());
            rejects(() -> r.accept(a, attack, NOW));
            JsonObject own = message(ha, 6, "exchange"); own.addProperty("pal_uid", B.palUid()); own.addProperty("mc_uuid", B.mcUuid().toString());
            check(r.accept(a, own, NOW).identity().equals(A), "Caller supplied identity overrode transport identity");
        });
        test("concurrent_two_players_input_and_gui_do_not_cross", () -> {
            var r = registry("mc.login"); Object a = new Object(), b = new Object(); SessionHandle ha = admit(r, a, CA, NOW), hb = admit(r, b, CB, NOW);
            ExecutorService pool = Executors.newFixedThreadPool(2); CountDownLatch start = new CountDownLatch(1); AtomicInteger inputA = new AtomicInteger(), guiB = new AtomicInteger();
            try {
                Future<?> fa = pool.submit(() -> { await(start); for (int i = 1; i <= 2000; i++) { check(r.accept(a, message(ha, i, "key"), NOW).identity().equals(A), "A actor changed"); inputA.incrementAndGet(); } });
                Future<?> fb = pool.submit(() -> { await(start); for (int i = 1; i <= 2000; i++) { check(r.accept(b, message(hb, i, "pointer"), NOW).identity().equals(B), "B actor changed"); guiB.incrementAndGet(); } });
                start.countDown(); fa.get(10, TimeUnit.SECONDS); fb.get(10, TimeUnit.SECONDS);
                check(inputA.get() == 2000 && guiB.get() == 2000, "Lost a player's actions");
            } finally { pool.shutdownNow(); }
        });
        test("simultaneous_duplicate_login_has_exactly_one_owner", () -> {
            for (int attempt = 0; attempt < 50; attempt++) {
                var r = registry("mc.login"); Object c1 = new Object(), c2 = new Object(); JsonObject a1 = CA.answer("mc.login", r.challenge(c1, A, NOW), NOW), a2 = CA.answer("mc.login", r.challenge(c2, A, NOW), NOW);
                ExecutorService pool = Executors.newFixedThreadPool(2); CountDownLatch start = new CountDownLatch(1); AtomicInteger won = new AtomicInteger(), denied = new AtomicInteger();
                try {
                    Future<?> f1 = pool.submit(() -> { await(start); try { r.authenticate(c1, a1, NOW); won.incrementAndGet(); } catch (SecurityException e) { denied.incrementAndGet(); } });
                    Future<?> f2 = pool.submit(() -> { await(start); try { r.authenticate(c2, a2, NOW); won.incrementAndGet(); } catch (SecurityException e) { denied.incrementAndGet(); } });
                    start.countDown(); f1.get(5, TimeUnit.SECONDS); f2.get(5, TimeUnit.SECONDS);
                    check(won.get() == 1 && denied.get() == 1 && r.snapshot(NOW).size() == 1, "Duplicate avatar admitted");
                } finally { pool.shutdownNow(); }
            }
        });
        test("reconnect_keeps_identity_and_discards_queued_old_input_and_late_close", () -> {
            var r = registry("mc.login"); Object old = new Object(), next = new Object(); SessionHandle h1 = admit(r, old, CA, NOW);
            r.accept(old, message(h1, 1, "key"), NOW); r.disconnect(old); SessionHandle h2 = admit(r, next, CA, NOW + 1); AtomicInteger calls = new AtomicInteger();
            check(h1.identity().equals(h2.identity()) && h2.generation() > h1.generation() && !h1.sessionId().equals(h2.sessionId()), "Reconnection created a different avatar");
            check(!r.runIfCurrent(old, h1, NOW + 1, calls::incrementAndGet), "Queued old input executed");
            r.disconnect(old); check(r.runIfCurrent(next, h2, NOW + 1, calls::incrementAndGet) && calls.get() == 1, "Late old close detached new owner");
            rejects(() -> r.accept(next, message(h1, 2, "pointer"), NOW + 1));
        });
        test("sequence_replay_and_fractional_sequence_rejected", () -> {
            var r = registry("mc.login"); Object c = new Object(); SessionHandle h = admit(r, c, CA, NOW); JsonObject q = message(h, 1, "key");
            r.accept(c, q, NOW); rejects(() -> r.accept(c, q, NOW)); q.addProperty("seq", 1.5); rejects(() -> r.accept(c, q, NOW));
            q.addProperty("seq", 0); rejects(() -> r.accept(c, q, NOW)); q.addProperty("seq", "2"); rejects(() -> r.accept(c, q, NOW));
        });
        test("idle_connection_expires_and_reconnect_does_not_duplicate_avatar", () -> {
            var r = registry("mc.login"); Object c = new Object(); SessionHandle old = admit(r, c, CA, NOW);
            check(r.current(c, NOW + 31) == null && r.expired(NOW + 31).contains(c), "Idle controller retained lease");
            SessionHandle h = admit(r, new Object(), CA, NOW + 32); check(h.identity().equals(old.identity()) && h.generation() > old.generation(), "Idle resume replaced identity");
        });
        test("host_hmac_proof_and_scope_are_not_a_bearer_token", () -> {
            var r = registry("host.bind"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW); JsonObject answer = CA.answer("host.bind", challenge, NOW);
            check(SessionCrypto.verifyHmac(CA.hostSecret(), SessionGrant.proofText("host.bind", challenge, CA.token()), answer.get("proof").getAsString()), "Host proof failed");
            SessionHandle h = r.authenticateHost(c, answer, CA, NOW); check(r.accept(c, message(h, 1, "cam"), NOW).identity().equals(A), "Host session changed actor");
            Object attacker = new Object(); JsonObject next = r.challenge(attacker, A, NOW); JsonObject forged = CA.answer("host.bind", next, NOW); forged.addProperty("proof", SessionCrypto.nonce());
            rejects(() -> r.authenticateHost(attacker, forged, CA, NOW));
        });
        test("host_observer_can_read_and_cannot_take_input_or_gui", () -> {
            var r = registry("host.bind"); Object controller = new Object(), observer = new Object();
            SessionHandle hc = r.authenticateHost(controller, CA.answer("host.bind", r.challenge(controller, A, NOW), NOW), CA, NOW);
            JsonObject answer = CA.answer("host.bind", r.challenge(observer, A, NOW), NOW); answer.addProperty("observer", true);
            SessionHandle ho = r.authenticateHost(observer, answer, CA, NOW); r.accept(observer, message(ho, 1, "inspect"), NOW);
            rejects(() -> r.accept(observer, message(ho, 2, "key"), NOW)); rejects(() -> r.accept(observer, message(ho, 2, "pointer"), NOW));
            check(r.current(controller, hc, NOW), "Observer displaced controller");
            rejects(() -> r.accept(controller, message(hc, 1, "cmd"), NOW));
        });
        test("host_certificate_rotation_rejects_previous_device_key", () -> {
            var r = registry("host.bind"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW); GuestCredential renewed = credential(A);
            rejects(() -> r.authenticateHost(c, CA.answer("host.bind", challenge, NOW), renewed, NOW));
        });
        test("legacy_loopback_has_one_controller_and_no_implicit_second_actor", () -> {
            var r = registry("host.bind"); Object c = new Object(), other = new Object(); SessionHandle h = r.legacy(c, A, NOW);
            JsonObject q = new JsonObject(); q.addProperty("t", "key"); r.accept(c, q, NOW);
            rejects(() -> r.legacy(other, A, NOW)); r.disconnect(c); SessionHandle next = r.legacy(other, A, NOW + 1);
            check(next.legacy() && next.identity().equals(h.identity()) && next.generation() > h.generation(), "Legacy resume changed avatar");
        });
        test("identity_import_preserves_palcraft_inventory_uuid_and_rejects_remap", () -> {
            Path dir = Files.createTempDirectory("palcraft-binding-test");
            try {
                IdentityBindings b = new IdentityBindings(dir.resolve("bindings.json")); UUID existing = BridgeIdentity.offlineUuid("PalCraft");
                check(existing.toString().equals("11111111-1111-1111-1111-111111111111"), "Legacy UUID assumption is wrong");
                BridgeIdentity imported = b.enroll(WORLD, A.palUid(), "PalCraft", existing); check(imported.mcUuid().equals(existing), "Inventory UUID migrated unexpectedly");
                check(b.enroll(WORLD, A.palUid(), null, null).equals(imported), "Repeated registration changed identity");
                rejects(() -> { try { b.enroll(WORLD, A.palUid(), "FixtureOther", null); } catch (java.io.IOException e) { throw new RuntimeException(e); } });
                rejects(() -> { try { b.enroll(WORLD, B.palUid(), "PalCraft", existing); } catch (java.io.IOException e) { throw new RuntimeException(e); } });
                BridgeIdentity peer = b.enroll(WORLD, B.palUid(), null, null); check(!peer.mcUuid().equals(existing) && b.load().size() == 2, "Peer shared imported inventory UUID");
            } finally { remove(dir); }
        });
        test("registration_uses_fresh_authoritative_online_pal_uid", () -> {
            Path dir = Files.createTempDirectory("palcraft-enrollment-test");
            try {
                Path presence = dir.resolve("pal-presence.json"); JsonObject p = presence(NOW, A.palUid()); SessionFiles.write(presence, p, false);
                GuestCredential g = SessionEnrollment.enroll(dir.resolve("auth"), presence, A.palUid(), "PalCraft", null, NOW, 600);
                JsonObject cfg = SessionFiles.read(dir.resolve("auth/authority-public.json")); SessionGrant checked = SessionGrant.verified(g.token(), SessionCrypto.publicKey(cfg.get("authority_public").getAsString()), NOW, WORLD, BOOT);
                check(checked.identity().mcUuid().equals(BridgeIdentity.offlineUuid("PalCraft")), "Registration lost old inventory");
                GuestCredential fromDisk = GuestCredential.from(g.json()); check(fromDisk.grant().identity().equals(checked.identity()), "Saved credential did not reload");
                rejects(() -> { try { SessionEnrollment.enroll(dir.resolve("auth"), presence, B.palUid(), null, null, NOW, 600); } catch (java.io.IOException e) { throw new RuntimeException(e); } });
                rejects(() -> { try { SessionEnrollment.presence(presence, NOW + 11); } catch (java.io.IOException e) { throw new RuntimeException(e); } });
                p.addProperty("authority", false); SessionFiles.write(presence, p, false); rejects(() -> { try { SessionEnrollment.presence(presence, NOW); } catch (java.io.IOException e) { throw new RuntimeException(e); } });
            } finally { remove(dir); }
        });
        test("old_event_scope_rejected_after_reconnect_and_restart", () -> {
            var r = registry("mc.login"); Object c = new Object(); SessionHandle h = admit(r, c, CA, NOW); r.disconnect(c); SessionHandle resumed = admit(r, new Object(), CA, NOW + 1);
            check(!resumed.matches(h.json()) && resumed.matches(resumed.json()), "Old event entered resumed GUI");
            SessionHandle restarted = admit(registry("mc.login"), new Object(), CA, NOW + 1); check(!restarted.matches(h.json()), "Restart with generation=1 accepted old event");
        });
        test("world_and_transport_session_namespaces_do_not_overwrite", () -> {
            var r = registry("mc.login"); Object c = new Object(); SessionHandle h = admit(r, c, CA, NOW); JsonObject q = message(h, 1, "world_view_ack");
            q.addProperty("world_session", "mc-world-lifetime"); q.addProperty("view", "native-nether-view-4"); r.accept(c, q, NOW);
            check(q.get("world_session").getAsString().equals("mc-world-lifetime") && q.get("view").getAsString().equals("native-nether-view-4"), "Routing rewrote dimension acknowledgement");
        });
        if (args.length > 0) {
            Path fixtures = Path.of(args[0]); Files.createDirectories(fixtures); SessionFiles.write(fixtures.resolve("synthetic-credential.json"), CA.json(), true);
            var r = registry("host.bind"); Object c = new Object(); JsonObject challenge = r.challenge(c, A, NOW); JsonObject vector = new JsonObject();
            vector.addProperty("synthetic_test_fixture", true); vector.addProperty("now", NOW); vector.add("challenge", challenge); vector.add("answer", CA.answer("host.bind", challenge, NOW));
            vector.addProperty("authority_public", SessionCrypto.encode(AUTHORITY.getPublic().getEncoded())); SessionFiles.write(fixtures.resolve("public-vector.json"), vector, false);
        }
        JsonObject report = new JsonObject(); report.addProperty("ok", true); report.addProperty("suite", "session_protocol_production_code"); report.addProperty("tests", RESULTS.size()); report.add("cases", RESULTS);
        report.addProperty("two_real_pal_clients_verified", false); System.out.println(report);
    }
    private static void await(CountDownLatch latch) { try { latch.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new RuntimeException(e); } }
    private static JsonObject presence(long now, String uid) {
        JsonObject p = new JsonObject(); p.addProperty("v", 2); p.addProperty("authority", true); p.addProperty("world_id", WORLD); p.addProperty("server_session_id", BOOT); p.addProperty("updated_unix", now);
        JsonArray players = new JsonArray(); JsonObject a = new JsonObject(); a.addProperty("pal_uid", uid); players.add(a); p.add("players", players); return p;
    }
    private static void remove(Path dir) throws Exception { try (var files = Files.walk(dir)) { for (Path p : files.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(p); } }
}
