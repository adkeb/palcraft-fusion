package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.UUID;

/** The journal is authoritative; request/result files are replaceable delivery mailboxes. */
public final class ExchangeJournal {
    public static JsonObject read(Path path) throws IOException {
        try { return JsonParser.parseString(Files.readString(path)).getAsJsonObject(); }
        catch (RuntimeException e) { throw new IOException("Invalid exchange record: " + path.getFileName(), e); }
    }

    public static void write(Path path, JsonObject row) throws IOException {
        Files.createDirectories(path.getParent());
        Path temporary = path.resolveSibling(path.getFileName() + "." + UUID.randomUUID() + ".tmp");
        try {
            byte[] bytes = row.toString().getBytes(StandardCharsets.UTF_8);
            try (FileChannel file = FileChannel.open(temporary, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
                ByteBuffer buffer = ByteBuffer.wrap(bytes);
                while (buffer.hasRemaining()) file.write(buffer);
                file.force(true);
            }
            // Never delete the last valid record before installing the next one.
            Files.move(temporary, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            forceDirectory(path.getParent());
        } finally { Files.deleteIfExists(temporary); }
    }

    private static void forceDirectory(Path directory) throws IOException {
        // Windows cannot open directories as FileChannels. The files themselves are forced.
        if (System.getProperty("os.name", "").startsWith("Windows")) return;
        try (FileChannel file = FileChannel.open(directory, StandardOpenOption.READ)) { file.force(true); }
    }
    private ExchangeJournal() {}
}
