package dev.rehan.passthrough.client;

import com.mojang.blaze3d.pipeline.RenderTarget;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.renderpearl.api.buffers.GpuBuffer;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import com.mojang.renderpearl.api.commands.CommandEncoder;
import dev.rehan.passthrough.Passthrough;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.VarHandle;
import org.joml.Vector4f;

/**
 * Hands Minecraft's frame to the host through the shared memory "Local\MCPassthroughFrame".
 *
 * <pre>
 * header (4096 bytes, little-endian)
 *   0 int magic "MCPT"   4 int version (1)   8 int header bytes (4096)   12 int slot count (3)
 *   16 long slot stride   24 int max width   28 int max height
 *   32 long publish counter (bumped after each completed slot)   40 int latest slot (-1: none yet)   44 int Minecraft pid
 *   256 + 128 * i: slot i
 *     +0 long seq (odd while being written)   +8 long Minecraft frame   +16 long host frame
 *     +24 int width   +28 int height   +32 float near   +36 float far   +40 float vertical fov (degrees)
 *     +44 int flags: 1 = depth in [0, 1], 2 = rows bottom-up, 4 = reversed Z, 8 = overlay only
 *     +48 double camera x, +56 y, +64 z   +72 float yaw   +76 pitch   +80 roll   +84 int first person
 *     +88 long capture time (System.nanoTime)   +96 long publish time
 *     +104 long capture epoch millis   +112 long publish epoch millis   +120 int overlay state (1 build, 2 screen)
 * slot i data at 4096 + i * stride, each layer width * height * 4 bytes:
 *   world colour RGBA8 (premultiplied alpha), world depth float32, overlay RGBA8 (hand + HUD, premultiplied alpha)
 * </pre>
 *
 * Only the overlay is read back. World/depth offsets remain reserved for v1 readers, but are never written or
 * uploaded: Palworld renders the world with native meshes. Clear colour just before the original animated hand,
 * screen effects and GUI, then read that one layer asynchronously. Never reuse a busy readback buffer.
 */
public final class FrameExporter {
	public static final String NAME = System.getProperty("palcraft.frameName", "Local\\MCPassthroughFrame");
	private static final int MAGIC = 0x5450434D;
	private static final int VERSION = 1;
	private static final int HEADER = 4096;
	private static final int SLOTS = 3;
	private static final int SLOT_DESC = 256;
	private static final int SLOT_DESC_BYTES = 128;
	private static final int MAX_W = 3840;
	private static final int MAX_H = 2160;
	private static final long LAYER_MAX = (long)MAX_W * MAX_H * 4;
	private static final long STRIDE = LAYER_MAX * 3;
	private static final int RING = 3;
	private static final long MAX_FRAME_AGE_NANOS = 250_000_000L;
	private static final Vector4f TRANSPARENT = new Vector4f(0.0F, 0.0F, 0.0F, 0.0F);
	private static final ValueLayout.OfInt INT = ValueLayout.JAVA_INT_UNALIGNED;
	private static final ValueLayout.OfLong LONG = ValueLayout.JAVA_LONG_UNALIGNED;
	private static final ValueLayout.OfFloat FLOAT = ValueLayout.JAVA_FLOAT_UNALIGNED;
	private static final ValueLayout.OfDouble DOUBLE = ValueLayout.JAVA_DOUBLE_UNALIGNED;
	/** Near/far planes of the frame being rendered (the camera sets far each frame). */
	private static final float NEAR = 0.05F;
	private static float far = 1024.0F;

	private static SharedMemory shm;
	private static boolean failed;
	private static boolean warnedSize;
	private static final Capture[] ring = new Capture[RING];
	private static int ringNext;
	private static int slotNext;
	private static long frameCounter;
	private static long publishCounter;
	private static long lastPublishedFrame;
	private static long captured, published, droppedBusy, droppedStale, readbackNanos;
	private static Capture current;

	private FrameExporter() {
	}

	private static final class Capture {
		GpuBuffer overlay;
		int width;
		int height;
		long generation;
		boolean busy;
		HostState.Pose pose;
		float far;
		long frame;
		long captureNanos;
		long captureMillis;
		int overlayState;

		void allocate(final int w, final int h) {
			this.free();
			long n = (long)w * h * 4;
			int usage = GpuBuffer.USAGE_MAP_READ | GpuBuffer.USAGE_COPY_DST;
			this.overlay = RenderSystem.getDevice().createBuffer(() -> "passthrough overlay", usage, n);
			this.width = w;
			this.height = h;
		}

		void free() {
			if (this.overlay != null) this.overlay.close();
			this.overlay = null;
		}
	}

	public static void setFar(final float depthFar) {
		far = depthFar;
	}

	public static boolean exporting() {
		return shm != null;
	}

	/** Render-thread counters, surfaced by PlayFeedback instead of a per-frame disk write. */
	public static com.google.gson.JsonObject statistics() {
		com.google.gson.JsonObject s = new com.google.gson.JsonObject();
		s.addProperty("layers", 1);
		s.addProperty("captured", captured);
		s.addProperty("published", published);
		s.addProperty("dropped_busy", droppedBusy);
		s.addProperty("dropped_stale", droppedStale);
		s.addProperty("readback_ms_mean", published == 0 ? 0 : readbackNanos / (published * 1_000_000.0));
		return s;
	}

	private static boolean ensureShm() {
		if (shm != null) {
			return true;
		}

		if (failed) {
			return false;
		}

		try {
			shm = SharedMemory.create(NAME, HEADER + STRIDE * SLOTS);
			MemorySegment m = shm.segment;
			m.set(INT, 0, MAGIC);
			m.set(INT, 4, VERSION);
			m.set(INT, 8, HEADER);
			m.set(INT, 12, SLOTS);
			m.set(LONG, 16, STRIDE);
			m.set(INT, 24, MAX_W);
			m.set(INT, 28, MAX_H);
			m.set(LONG, 32, 0);
			m.set(INT, 40, -1);
			m.set(INT, 44, (int)ProcessHandle.current().pid());
			Passthrough.LOG.info("frame export: shared memory {} ({} MB)", NAME, (HEADER + STRIDE * SLOTS) >> 20);
			return true;
		} catch (Throwable t) {
			failed = true;
			Passthrough.LOG.error("frame export disabled: couldn't create shared memory", t);
			return false;
		}
	}

	/** Existing renderLevel hook: reserve one HUD readback and clear world colour before the original hand. */
	public static void captureWorld(final RenderTarget target) {
        if (Boolean.getBoolean("palcraft.noFrameExport")) return;
		current = null;
		HostState.Pose pose = HostState.frame();
		if (pose == null || !ensureShm()) {
			return;
		}

		int w = target.width;
		int h = target.height;
		if (w <= 0 || h <= 0 || w > MAX_W || h > MAX_H || (long)w * h * 4 > LAYER_MAX) {
			if (!warnedSize) {
				warnedSize = true;
				Passthrough.LOG.warn("frame export: {}x{} is bigger than {}x{}, not exporting", w, h, MAX_W, MAX_H);
			}

			return;
		}

		long now = System.nanoTime();
		CommandEncoder encoder = RenderSystem.getDevice().createCommandEncoder();
		// Clear even if all readbacks are occupied. An overlay must never contain world pixels.
		encoder.clearColorTexture(target.getColorTexture(), TRANSPARENT);
		Capture c = null;
		for (int i = 0; i < RING; i++) {
			int index = (ringNext + i) % RING;
			if (ring[index] == null) ring[index] = new Capture();
			if (!ring[index].busy) {
				c = ring[index];
				ringNext = (index + 1) % RING;
				break;
			}
		}
		if (c == null) { droppedBusy++; return; }
		if (c.width != w || c.height != h || c.overlay == null) {
			c.allocate(w, h);
		}

		c.generation++;
		c.busy = true;
		c.pose = pose;
		c.far = far;
		c.frame = ++frameCounter;
		c.captureNanos = now;
		c.captureMillis = System.currentTimeMillis();
		c.overlayState = (ClientInput.buildMode ? 1 : 0) | (net.minecraft.client.Minecraft.getInstance().gui.screen() != null ? 2 : 0);
		captured++;
		current = c;
	}

	/** End of GameRenderer.render: the overlay (hand, screen effects, GUI) is complete. */
	public static void captureOverlay(final RenderTarget target) {
        if (Boolean.getBoolean("palcraft.noFrameExport")) return;
		Capture c = current;
		current = null;
		if (c == null) {
			return;
		}

		if (target.width != c.width || target.height != c.height) {
			c.busy = false;
			return;
		}

		long generation = c.generation;
		RenderSystem.getDevice().createCommandEncoder().copyTextureToBuffer(target.getColorTexture(), c.overlay, 0L, () -> {
			if (c.generation == generation && c.busy) {
				publish(c);
			}
		}, 0);
	}

	private static void publish(final Capture c) {
		try {
			long now = System.nanoTime();
			if (c.frame <= lastPublishedFrame || now - c.captureNanos > MAX_FRAME_AGE_NANOS) {
				droppedStale++;
				return;
			}
			MemorySegment m = shm.segment;
			int slot = slotNext;
			slotNext = (slotNext + 1) % SLOTS;
			long desc = SLOT_DESC + (long)SLOT_DESC_BYTES * slot;
			long seq = m.get(LONG, desc);
			if ((seq & 1L) != 0L) {
				seq++;
			}

			m.set(LONG, desc, seq + 1L);
			VarHandle.fullFence();
			long base = HEADER + STRIDE * slot;
			long n = (long)c.width * c.height * 4;
			copy(c.overlay, m, base + 2 * n, n);
			HostState.Pose p = c.pose;
			m.set(LONG, desc + 8, c.frame);
			m.set(LONG, desc + 16, p.hostFrame());
			m.set(INT, desc + 24, c.width);
			m.set(INT, desc + 28, c.height);
			m.set(FLOAT, desc + 32, NEAR);
			m.set(FLOAT, desc + 36, c.far);
			m.set(FLOAT, desc + 40, p.fov());
			m.set(INT, desc + 44, 2 | 8); // bottom-up, HUD only: world/depth are intentionally absent
			m.set(DOUBLE, desc + 48, p.x());
			m.set(DOUBLE, desc + 56, p.y());
			m.set(DOUBLE, desc + 64, p.z());
			m.set(FLOAT, desc + 72, p.yaw());
			m.set(FLOAT, desc + 76, p.pitch());
			m.set(FLOAT, desc + 80, p.roll());
			m.set(INT, desc + 84, p.firstPerson() ? 1 : 0);
			m.set(LONG, desc + 88, c.captureNanos);
			m.set(LONG, desc + 96, System.nanoTime());
			m.set(LONG, desc + 104, c.captureMillis);
			m.set(LONG, desc + 112, System.currentTimeMillis());
			m.set(INT, desc + 120, c.overlayState);
			VarHandle.fullFence();
			m.set(LONG, desc, seq + 2L);
			m.set(INT, 40, slot);
			VarHandle.fullFence();
			m.set(LONG, 32, ++publishCounter);
			lastPublishedFrame = c.frame;
			published++;
			readbackNanos += System.nanoTime() - c.captureNanos;
		} catch (RuntimeException e) {
			Passthrough.LOG.warn("frame export failed", e);
		} finally {
			c.busy = false;
		}
	}

	private static void copy(final GpuBuffer buffer, final MemorySegment dst, final long offset, final long n) {
		try (GpuBufferSlice.MappedView view = buffer.map(true, false)) {
			MemorySegment.copy(MemorySegment.ofBuffer(view.data()), 0L, dst, offset, n);
		}
	}
}
