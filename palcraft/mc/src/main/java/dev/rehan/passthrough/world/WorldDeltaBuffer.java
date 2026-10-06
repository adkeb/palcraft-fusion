package dev.rehan.passthrough.world;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Predicate;

/** Server-thread queue: one authoritative read per coordinate, even after cascading neighbor updates. */
public final class WorldDeltaBuffer {
    public record Position(String dimension, int x, int y, int z) {}
    public record Change(Position position, List<String> causes, int flags) {}
    private static final class Dirty {
        final Set<String> causes = new LinkedHashSet<>();
        int flags;
    }
    private final LinkedHashMap<Position, Dirty> pending = new LinkedHashMap<>();
    private final int capacity;

    public WorldDeltaBuffer(int capacity) {
        if (capacity < 1) throw new IllegalArgumentException("capacity must be positive");
        this.capacity = capacity;
    }
    public boolean mark(Position position, String cause, int flags) {
        Dirty dirty = pending.get(position);
        if (dirty == null) {
            if (pending.size() >= capacity) return false;
            dirty = new Dirty(); pending.put(position, dirty);
        }
        dirty.causes.add(cause); dirty.flags |= flags;
        return true;
    }
    public List<Change> drain(int limit) {
        List<Change> result = new ArrayList<>();
        var iterator = pending.entrySet().iterator();
        while (iterator.hasNext() && result.size() < limit) {
            Map.Entry<Position, Dirty> entry = iterator.next();
            result.add(new Change(entry.getKey(), List.copyOf(entry.getValue().causes), entry.getValue().flags));
            iterator.remove();
        }
        return result;
    }
    public void removeIf(Predicate<Position> test) { pending.keySet().removeIf(test); }
    public int size() { return pending.size(); }
    public void clear() { pending.clear(); }
}
