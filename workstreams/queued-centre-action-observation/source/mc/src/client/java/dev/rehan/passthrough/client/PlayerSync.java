package dev.rehan.passthrough.client;

import net.minecraft.client.CameraType;
import net.minecraft.client.Minecraft;
import dev.rehan.passthrough.Passthrough;
import java.util.Locale;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.world.entity.player.Abilities;
import net.minecraft.world.phys.Vec3;
import dev.rehan.passthrough.session.SessionHandle;
import java.util.UUID;

/** Keeps the Minecraft player on the host's player: it stands where they stand and looks where the host camera looks. */
public final class PlayerSync {
	private static final double TELEPORT_SQ = 64.0 * 64.0;
	/** How far the host's player moved over the last client tick (drives the walk animation). */
	private static float tickDistance;
	private static double lastX = Double.NaN, lastZ;
	private static SessionHandle owner;
	private static UUID playerUuid;

	private PlayerSync() {
	}

	public static float tickDistance() {
		return tickDistance;
	}

	/** Game thread only. Walking interpolation belongs to a connection generation, not a static camera stream. */
	public static void reset() { tickDistance = 0; lastX = Double.NaN; lastZ = 0; owner = null; playerUuid = null; }
	private static boolean owns(LocalPlayer player) {
		SessionHandle h = HostState.session();
		if (h == null || !HostState.matchesIdentity(player.getUUID()) || (!h.legacy() && !GuestSession.ready())) { reset(); return false; }
		if (owner == null || !owner.sameConnection(h) || !player.getUUID().equals(playerUuid)) {
			reset(); owner = h; playerUuid = player.getUUID();
		}
		return true;
	}

	/** Every frame, before the camera update: position, rotation, and first/third person to match the host. */
	public static void frame(final float partialTick) {
		if (!ClientBridge.worldInteractionsReady()) return;
		HostState.Pose p = HostState.frame();
		Minecraft minecraft = Minecraft.getInstance();
		LocalPlayer player = minecraft.player;
		if (p == null || player == null || !owns(player)) {
			return;
		}

		if (p.drive()) {
			// Minecraft flies the player (elytra): it only takes where to look, and tells the host where it is
			player.setYRot(p.lookYaw());
			player.setXRot(p.lookPitch());
			player.yRotO = p.lookYaw();
			player.xRotO = p.lookPitch();
			player.yHeadRot = player.yHeadRotO = p.lookYaw();
			if (minecraft.options.getCameraType() != CameraType.THIRD_PERSON_BACK) {
				minecraft.options.setCameraType(CameraType.THIRD_PERSON_BACK);
			}
			// airborne: with no collision onGround never updates, and the server cancels a grounded player's glide
			player.setOnGround(false);

			// where the player is drawn this frame, how fast that moves (the slope of the tick interpolation, per
			// second) and when (System.nanoTime is the host's QueryPerformanceCounter clock): the host carries it forward
			Vec3 at = player.getPosition(partialTick);
			double vx = (player.getX() - player.xo) * 20.0, vy = (player.getY() - player.yo) * 20.0, vz = (player.getZ() - player.zo) * 20.0;
			HostLink.publish(owner, String.format(Locale.ROOT, "{\"t\":\"mcpos\",\"pos\":[%.4f,%.4f,%.4f],\"vel\":[%.3f,%.3f,%.3f],\"tn\":%d,\"fly\":%b}",
				at.x, at.y, at.z, vx, vy, vz, System.nanoTime(), player.isFallFlying()));
			return;
		}

		player.setYRot(p.yaw());
		player.setXRot(p.pitch());
		player.yRotO = p.yaw();
		player.xRotO = p.pitch();
		player.yHeadRot = player.yHeadRotO = p.yaw();
		player.yBodyRot = player.yBodyRotO = p.firstPerson() ? p.yaw() : p.bodyYaw();
		// the model stands exactly where the host's player is this frame (not a tick behind, interpolating)
		double x = p.px();
		double y = p.py();
		double z = p.pz();
		player.setPos(x, y, z);
		applyGround(player);
		player.xo = player.xOld = x;
		player.yo = player.yOld = y;
		player.zo = player.zOld = z;
		CameraType cameraType = p.firstPerson() ? CameraType.FIRST_PERSON : CameraType.THIRD_PERSON_BACK;
		if (minecraft.options.getCameraType() != cameraType) {
			minecraft.options.setCameraType(cameraType);
		}
	}

	/** Preserve host contact after Minecraft movement, before its movement packet and the next input tick. */
	public static void applyGround(final LocalPlayer player) {
		if (!ClientBridge.worldInteractionsReady()) return;
		HostState.Pose p = HostState.live();
		if (p != null && owns(player) && !p.drive() && p.groundKnown()) player.setOnGround(p.grounded());
	}

	/**
	 * Every client tick, at the start of the player's tick (the old position is already saved, so the model
	 * interpolates and walks): the player stands at the host feet in either camera mode.
	 */
	public static void tick(final LocalPlayer player) {
		if (!ClientBridge.worldInteractionsReady()) { tickDistance = 0; return; }
		HostState.Pose p = HostState.live();
		if (p == null || p.drive() || !owns(player)) {
			if (p == null) tickDistance = 0;
			return;
		}

		double x = p.px();
		double y = p.py();
		double z = p.pz();
		tickDistance = Double.isNaN(lastX) ? 0.0F : (float) Math.min(Math.hypot(x - lastX, z - lastZ), 1.0);
		lastX = x;
		lastZ = z;
		boolean teleport = player.distanceToSqr(x, y, z) > TELEPORT_SQ;
		player.setPos(x, y, z);
		applyGround(player);
		if (teleport) {
			player.xo = player.xOld = x;
			player.yo = player.yOld = y;
			player.zo = player.zOld = z;
		}

		player.setDeltaMovement(Vec3.ZERO);
		Abilities abilities = player.getAbilities();
		if (abilities.mayfly && !abilities.flying) {
			abilities.flying = true;
			player.onUpdateAbilities();
		}
	}
}
