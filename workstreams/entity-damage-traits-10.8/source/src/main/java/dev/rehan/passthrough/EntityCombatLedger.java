package dev.rehan.passthrough;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Engine-independent authority and replay checks. Never identifies an entity by a recyclable runtime handle. */
public final class EntityCombatLedger {
    public enum Decision { ACCEPT, REPLAY, CONFLICT, STALE_SESSION, STALE_EPOCH, INVALID }
    public record DamageTraits(boolean explosion, boolean projectile) {}
    public record Hit(String id, String session, String targetEpoch, String sourceEpoch,
                      String target, String source, double amount, String kind, DamageTraits damageTraits) {
        public Hit(String id,String session,String targetEpoch,String sourceEpoch,String target,String source,double amount,String kind) {
            this(id,session,targetEpoch,sourceEpoch,target,source,amount,kind,null);
        }
        public String fingerprint() {
            String value=String.join("\n", session, targetEpoch, sourceEpoch, target, source,Double.toHexString(amount),kind);
            if(damageTraits!=null)value+="\ntraits1:"+damageTraits.explosion()+":"+damageTraits.projectile();
            return digest(value);
        }
    }
    private final int capacity;
    private final Map<String, String> seen = new LinkedHashMap<>();
    private String session;
    private String epoch;

    public EntityCombatLedger(int capacity) {
        if (capacity < 1) throw new IllegalArgumentException("Positive capacity required");
        this.capacity = capacity;
    }

    public void reset(String session, String epoch) {
        if (!safeToken(session) || !safeToken(epoch)) throw new IllegalArgumentException("Authority identity required");
        this.session = session;
        this.epoch = epoch;
        seen.clear();
    }

    /** A durable intent must be written before reserve, and before invoking the native engine. */
    public Decision inspect(Hit h) {
        if (!valid(h)) return Decision.INVALID;
        if (!h.session().equals(session)) return Decision.STALE_SESSION;
        if (!h.targetEpoch().equals(epoch)) return Decision.STALE_EPOCH;
        String old = seen.get(h.id());
        return old == null ? Decision.ACCEPT : old.equals(h.fingerprint()) ? Decision.REPLAY : Decision.CONFLICT;
    }

    public Decision reserve(Hit h) {
        Decision d = inspect(h);
        if (d != Decision.ACCEPT) return d;
        seen.put(h.id(), h.fingerprint());
        while (seen.size() > capacity) seen.remove(seen.keySet().iterator().next());
        return d;
    }

    public static boolean valid(Hit h) {
        return h != null && uuid(h.id()) && safeToken(h.session()) && safeToken(h.targetEpoch())
                && safeToken(h.sourceEpoch()) && entityId(h.target()) && entityId(h.source())
                && Double.isFinite(h.amount()) && h.amount() > 0 && h.amount() <= 10000
                && h.kind() != null && h.kind().matches("[a-z0-9_:./-]{1,96}");
    }

    public static boolean entityId(String id) {
        if (id == null) return false;
        if (id.startsWith("mc:")) return uuid(id.substring(3));
        if (!id.startsWith("pal:")) return false;
        String[] ids = id.substring(4).split("/", -1);
        return ids.length == 2 && uuid(ids[0]) && uuid(ids[1]);
    }

    public static boolean uuid(String id) {
        return id != null && id.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");
    }

    public static boolean safeToken(String value) {
        return value != null && value.matches("[a-zA-Z0-9_.:-]{1,128}");
    }

    public static String mcId(UUID uuid) { return "mc:" + uuid; }
    private static String digest(String value) {
        try {
            return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
    }
}
