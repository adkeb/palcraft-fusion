package dev.rehan.passthrough.client;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

/** Original Win32 mapping, or a shared mapped file on native macOS/Linux.
 * The MCPT ring bytes, publication fences and frame timestamps are unchanged. */
final class SharedMemory {
	private static final int PAGE_READWRITE = 0x04;
	private static final int FILE_MAP_ALL_ACCESS = 0xF001F;
	final MemorySegment segment;
	private final FileChannel fileChannel;
	private final FileLock writerLock;

	private SharedMemory(final MemorySegment segment) {
		this(segment, null, null);
	}

	private SharedMemory(final MemorySegment segment, FileChannel fileChannel, FileLock writerLock) {
		this.segment = segment;
		this.fileChannel = fileChannel;
		this.writerLock = writerLock;
	}

	static SharedMemory create(final String name, final long size) throws Throwable {
		if (!System.getProperty("os.name", "").startsWith("Windows")) return createFile(size);
		Linker linker = Linker.nativeLinker();
		SymbolLookup kernel32 = SymbolLookup.libraryLookup("kernel32", Arena.global());
		MethodHandle createFileMapping = linker.downcallHandle(
			kernel32.find("CreateFileMappingW").orElseThrow(),
			FunctionDescriptor.of(
				ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT, ValueLayout.ADDRESS
			)
		);
		MethodHandle mapViewOfFile = linker.downcallHandle(
			kernel32.find("MapViewOfFile").orElseThrow(),
			FunctionDescriptor.of(ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT, ValueLayout.JAVA_INT, ValueLayout.JAVA_LONG)
		);
		MemorySegment wideName = Arena.global().allocateFrom(ValueLayout.JAVA_BYTE, (name + "\0").getBytes(StandardCharsets.UTF_16LE));
		MemorySegment invalidHandle = MemorySegment.ofAddress(-1L);
		MemorySegment handle = (MemorySegment)createFileMapping.invoke(
			invalidHandle, MemorySegment.NULL, PAGE_READWRITE, (int)(size >>> 32), (int)size, wideName
		);
		if (handle.address() == 0L) {
			throw new IllegalStateException("CreateFileMappingW failed for " + name);
		}

		MemorySegment view = (MemorySegment)mapViewOfFile.invoke(handle, FILE_MAP_ALL_ACCESS, 0, 0, size);
		if (view.address() == 0L) {
			throw new IllegalStateException("MapViewOfFile failed for " + name);
		}

		return new SharedMemory(view.reinterpret(size));
	}

	private static SharedMemory createFile(final long size) throws Throwable {
		if (size <= 0) throw new IllegalArgumentException("Positive MCPT mapping size required");
		Path bridge = Path.of(System.getProperty("palcraft.bridgeDir", "."));
		Path path = Path.of(System.getProperty("palcraft.frameFile", bridge.resolve("mcpt-hud.bin").toString())).toAbsolutePath();
		Files.createDirectories(path.getParent());
		FileChannel channel = FileChannel.open(path, StandardOpenOption.CREATE, StandardOpenOption.READ, StandardOpenOption.WRITE);
		FileLock lock = null;
		try {
			lock = channel.tryLock();
			if (lock == null) throw new IllegalStateException("MCPT frame file already has a producer");
			// Never truncate a mapped file under an existing reader. The same ring
			// size is reused; FrameExporter resets the header and producer PID.
			long oldSize = channel.size();
			if (oldSize != 0 && oldSize != size) throw new IllegalStateException("Existing MCPT file has a different size");
			if (oldSize == 0) {
				channel.position(size - 1);
				channel.write(ByteBuffer.wrap(new byte[] {0}));
			}
			MemorySegment mapped = channel.map(FileChannel.MapMode.READ_WRITE, 0, size, Arena.global());
			return new SharedMemory(mapped, channel, lock);
		} catch (Throwable failure) {
			if (lock != null) lock.release();
			channel.close();
			throw failure;
		}
	}
}
