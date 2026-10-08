package dev.rehan.passthrough.session;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.function.Predicate;

public final class SessionFiles {
    @FunctionalInterface public interface SnapshotRead<T> { T read() throws IOException; }
    /** Cache only the caller's fully validated immutable presence, with its original timestamp. */
    public static final class PresenceReadCache<T> {
        private T previous;
        private String retainedAfter;
        public synchronized T read(SnapshotRead<T> source, Predicate<T> stillFresh) throws IOException {
            retainedAfter = null;
            try {
                T observed = source.read(); previous = observed; return observed;
            } catch (IOException | JsonParseException transientRead) {
                if (previous != null && stillFresh.test(previous)) {
                    retainedAfter = transientRead.getClass().getSimpleName(); return previous;
                }
                previous = null; throw transientRead;
            } catch (RuntimeException invalidSnapshot) {
                previous = null; throw invalidSnapshot;
            }
        }
        public synchronized String retainedAfter() { return retainedAfter; }
        public synchronized void clear() { previous = null; retainedAfter = null; }
    }
    public static JsonObject read(Path path) throws IOException {
        if (Files.size(path) > 1048576) throw new IOException("Session file is too large");
        return JsonParser.parseString(Files.readString(path)).getAsJsonObject();
    }
    public static void write(Path path, JsonObject json, boolean secret) throws IOException {
        Path target = path.toAbsolutePath(); Files.createDirectories(target.getParent());
        Path temp = Files.createTempFile(target.getParent(), target.getFileName().toString(), ".tmp");
        try {
            if (secret && Files.getFileStore(temp).supportsFileAttributeView("posix"))
                Files.setPosixFilePermissions(temp, PosixFilePermissions.fromString("rw-------"));
            Files.writeString(temp, json.toString());
            try { Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
            catch (AtomicMoveNotSupportedException e) { Files.move(temp, target, StandardCopyOption.REPLACE_EXISTING); }
        } finally { Files.deleteIfExists(temp); }
    }
    private SessionFiles() {}
}
