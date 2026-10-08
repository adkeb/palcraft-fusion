package dev.rehan.passthrough.session;

import com.google.gson.*;
import java.io.IOException;
import java.nio.channels.*;
import java.nio.file.*;
import java.util.*;

/** Server-owned persistent bijection; allocation never overwrites an existing avatar/inventory. */
public final class IdentityBindings {
    private final Path path;
    public IdentityBindings(Path path) { this.path = path.toAbsolutePath(); }
    public synchronized List<BridgeIdentity> load() throws IOException {
        if (!Files.exists(path)) return List.of();
        JsonObject j = SessionFiles.read(path);
        if (j.get("v").getAsInt() != 2) throw new IOException("Unsupported bindings schema");
        Map<String, BridgeIdentity> byPal = new HashMap<>(); Set<UUID> ids = new HashSet<>(); Set<String> names = new HashSet<>();
        for (JsonElement e : j.getAsJsonArray("bindings")) {
            BridgeIdentity b = BridgeIdentity.from(e.getAsJsonObject());
            if (byPal.putIfAbsent(b.key(), b) != null || !ids.add(b.mcUuid()) || !names.add(b.mcName().toLowerCase(Locale.ROOT)))
                throw new IOException("Bindings contain duplicate Pal or MC identity");
        }
        return byPal.values().stream().sorted(Comparator.comparing(BridgeIdentity::key)).toList();
    }
    public synchronized BridgeIdentity find(UUID mcUuid) throws IOException {
        return load().stream().filter(x -> x.mcUuid().equals(mcUuid)).findFirst().orElse(null);
    }
    /** Explicit name/UUID imports preserve existing playerdata. null/null allocates a stable offline identity. */
    public synchronized BridgeIdentity enroll(String worldId, String palUid, String importName, UUID importUuid) throws IOException {
        String world = BridgeIdentity.checkedId(worldId), uid = BridgeIdentity.guid(palUid), key = world + "/" + uid;
        Files.createDirectories(path.getParent());
        try (FileChannel lock = FileChannel.open(path.resolveSibling(path.getFileName() + ".lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock held = lock.lock()) {
            List<BridgeIdentity> all = new ArrayList<>(load());
            BridgeIdentity old = all.stream().filter(b -> b.key().equals(key)).findFirst().orElse(null);
            if (old != null) {
                if ((importName != null && !old.mcName().equals(importName)) || (importUuid != null && !old.mcUuid().equals(importUuid)))
                    throw new IllegalArgumentException("Identity already registered; explicit migration required");
                return old;
            }
            String name = importName != null ? importName : "PC" + SessionCrypto.sha256(key).substring(0, 14);
            BridgeIdentity identity = new BridgeIdentity(world, uid, importUuid != null ? importUuid : BridgeIdentity.offlineUuid(name), name);
            for (BridgeIdentity b : all) {
                if (b.mcUuid().equals(identity.mcUuid()) || b.mcName().equalsIgnoreCase(identity.mcName()))
                    throw new IllegalArgumentException("MC avatar is already bound to another Pal player");
            }
            all.add(identity); all.sort(Comparator.comparing(BridgeIdentity::key));
            JsonObject j = new JsonObject(); j.addProperty("v", 2); JsonArray rows = new JsonArray();
            all.forEach(b -> rows.add(b.json())); j.add("bindings", rows); SessionFiles.write(path, j, false);
            return identity;
        }
    }
}
