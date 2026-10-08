package dev.rehan.passthrough;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.Arrays;

/** Bounded, read-only NDJSON tailing: a torn final line is never delivered. */
public final class CompleteLineJournal {
    private final Path path;
    private final int maxLineBytes;
    private final ByteArrayOutputStream partial = new ByteArrayOutputStream();
    private String fileIdentity;
    private long offset, oversizedLines;
    private boolean droppingLine;
    private byte[] anchor=new byte[0];

    public CompleteLineJournal(Path path, int maxLineBytes) {
        this.path = Objects.requireNonNull(path);
        if (maxLineBytes < 1) throw new IllegalArgumentException("Line limit must be positive");
        this.maxLineBytes = maxLineBytes;
    }

    public List<String> poll(int maxLines, int maxBytes) throws IOException {
        if (maxLines < 1 || maxBytes < 1) throw new IllegalArgumentException("Poll limits must be positive");
        if (!Files.exists(path)) return List.of();
        BasicFileAttributes attributes = Files.readAttributes(path, BasicFileAttributes.class);
        String identity = String.valueOf(attributes.fileKey()) + ":" + attributes.creationTime();
        if (!identity.equals(fileIdentity) || attributes.size() < offset) {
            fileIdentity = identity; reset();
        }
        ArrayList<String> lines = new ArrayList<>();
        int bytes = 0;
        try (RandomAccessFile file = new RandomAccessFile(path.toFile(), "r")) {
            // Windows may expose no fileKey and preserve creation time when a name is replaced.
            if(file.length()<offset || anchor.length>0&&!Arrays.equals(anchor,window(file,offset-anchor.length,anchor.length)))reset();
            file.seek(offset);
            byte[] buffer = new byte[Math.min(8192, maxBytes)];
            while (bytes < maxBytes && lines.size() < maxLines) {
                int count = file.read(buffer, 0, Math.min(buffer.length, maxBytes - bytes));
                if (count < 0) break;
                for (int i = 0; i < count && lines.size() < maxLines; i++) {
                    byte value = buffer[i]; offset++; bytes++;
                    if (value == '\n') {
                        if (!droppingLine && partial.size() != 0) {
                            String line = partial.toString(StandardCharsets.UTF_8).stripTrailing();
                            if (!line.isBlank()) lines.add(line);
                        }
                        partial.reset(); droppingLine = false;
                    } else if (!droppingLine) {
                        if (partial.size() >= maxLineBytes) { oversizedLines++; droppingLine = true; partial.reset(); }
                        else partial.write(value);
                    }
                }
            }
            int anchorBytes=(int)Math.min(256,offset);
            anchor=window(file,offset-anchorBytes,anchorBytes);
        }
        return List.copyOf(lines);
    }

    public long offset() { return offset; }
    public long oversizedLines() { return oversizedLines; }
    public int partialBytes() { return partial.size(); }
    private void reset(){offset=0;partial.reset();droppingLine=false;anchor=new byte[0];}
    private static byte[] window(RandomAccessFile file,long start,int length)throws IOException{
        if(start<0||file.length()<start+length)return new byte[0];
        byte[] bytes=new byte[length];file.seek(start);file.readFully(bytes);return bytes;
    }
}
