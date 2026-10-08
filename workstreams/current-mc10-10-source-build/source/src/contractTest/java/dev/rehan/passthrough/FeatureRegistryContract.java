package dev.rehan.passthrough;

import java.util.ArrayList;
import java.util.List;

/** No game/server process is needed to verify feature ownership isolation. */
public final class FeatureRegistryContract {
    public static void main(String[] arguments) {
        FeatureRegistry<List<String>> registry = new FeatureRegistry<>();
        registry.register("world", "blocksync", calls -> calls.add("world"));
        registry.register("exchange", "exchange", calls -> calls.add("exchange"));
        expectFailure(IllegalStateException.class, () -> registry.register("other", "blocksync", calls -> calls.add("overwritten")));
        List<String> calls = new ArrayList<>();
        if (!registry.dispatch("blocksync", calls)) throw new AssertionError("World handler missing");
        if (registry.dispatch("unknown", calls)) throw new AssertionError("Unknown operation dispatched");
        if (!calls.equals(List.of("world"))) throw new AssertionError("Feature owner was replaced: " + calls);
        var metadata = registry.registrations();
        expectFailure(UnsupportedOperationException.class, () -> metadata.put("blocksync", "other"));
        registry.freeze();
        expectFailure(IllegalStateException.class, () -> registry.register("session", "hello", ignored -> {}));
        registry.dispatch("exchange", calls);
        if (!calls.equals(List.of("world", "exchange"))) throw new AssertionError("Frozen registry changed");
        System.out.println("FeatureRegistryContract: PASS (duplicate ownership, unknown operation, immutable metadata, frozen registration)");
        TravelAckContract.run();
        TravelRebaseContract.run();
    }

    private static void expectFailure(Class<? extends RuntimeException> expected, Runnable action) {
        try { action.run(); }
        catch (RuntimeException exception) {
            if (expected.isInstance(exception)) return;
            throw exception;
        }
        throw new AssertionError("Expected " + expected.getSimpleName());
    }
}
