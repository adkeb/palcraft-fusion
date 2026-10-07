package dev.rehan.passthrough;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.function.Consumer;

/** Named feature handlers are installed once before networking starts. */
public final class FeatureRegistry<T> {
    private record Entry<T>(String feature, Consumer<T> handler) {}
    private final Map<String, Entry<T>> entries = new LinkedHashMap<>();
    private boolean frozen;

    public void register(String feature, String operation, Consumer<T> handler) {
        if (frozen) throw new IllegalStateException("Feature registration is closed");
        if (feature == null || !feature.matches("[a-z][a-z0-9_.-]*")) throw new IllegalArgumentException("Invalid feature name");
        if (operation == null || !operation.matches("[a-z][a-z0-9_]*")) throw new IllegalArgumentException("Invalid operation name");
        Objects.requireNonNull(handler, "handler");
        Entry<T> previous = entries.putIfAbsent(operation, new Entry<>(feature, handler));
        if (previous != null) throw new IllegalStateException("Operation " + operation + " already belongs to " + previous.feature());
    }

    public boolean dispatch(String operation, T context) {
        Entry<T> entry = entries.get(operation);
        if (entry == null) return false;
        entry.handler().accept(context);
        return true;
    }

    public Map<String, String> registrations() {
        Map<String, String> result = new LinkedHashMap<>();
        entries.forEach((operation, entry) -> result.put(operation, entry.feature()));
        return Map.copyOf(result);
    }

    public void freeze() { frozen = true; }
}
