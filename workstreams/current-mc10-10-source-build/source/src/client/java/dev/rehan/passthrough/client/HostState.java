package dev.rehan.passthrough.client;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.session.SessionHandle;
import dev.rehan.passthrough.session.WorldPoseScope;
import java.util.UUID;

/** The host's latest camera and player pose, already in Minecraft coordinates (the host converts). */
public final class HostState {
	/**
	 * @param hostFrame the host's frame number for this pose (echoed in the exported frame)
	 * @param x camera position
	 * @param yaw Minecraft yaw (0 = facing +Z), pitch (positive = down) and roll, in degrees
	 * @param fov vertical field of view, degrees
	 * @param firstPerson whether the host camera is first person (third person shows the player model)
	 * @param px the player's feet (third person)
	 * @param bodyYaw the player's body yaw (third person)
	 * @param drive Minecraft moves the player (elytra flight) and the host follows; lookYaw/lookPitch steer
	 * @param gun the player holds one of the host's guns (Steve aims it; his own item isn't drawn)
	 */
	public record Pose(
		long hostFrame, double x, double y, double z, float yaw, float pitch, float roll, float fov,
		boolean firstPerson, double px, double py, double pz, float bodyYaw, long receivedNanos,
		boolean drive, float lookYaw, float lookPitch, boolean gun, boolean groundKnown, boolean grounded
	) {
	}

	private static final long TIMEOUT_NANOS = 2_000_000_000L;
	/** This JVM has one local player. Existing render hooks see only the explicitly bound session's projection. */
	private static final class SessionPose {
		final SessionHandle handle;
		volatile Sample latest;
		long lastHostFrame = -1;
		long lastCaptureFrame = -1;
		String sourceEpoch;
		long sourceGeneration=-1;
		long originGeneration = -1;
		long originFrame = -1;
		boolean awaitingCommittedOrigin;
		SessionPose(SessionHandle handle) { this.handle = handle; }
	}
	public record Sample(Pose pose, WorldPoseScope worldScope, SessionHandle session) {}
	private record WorldView(String session,String dimension,long generation,boolean waitingAck) {}
	private record FramePose(SessionPose owner, Sample sample) {}
	private static volatile SessionPose bound;
	private static volatile FramePose frame;
	private static volatile WorldView worldView;
	private static WorldView initialOverworld;
	private static boolean initialOnlyBlocked;
	public static boolean worldScopeEnabled() { return Boolean.getBoolean("palcraft.worldScopedCam.enabled"); }
	public static synchronized boolean initialOverworldReady() {
		WorldView v=worldView;
		return !worldScopeEnabled()&&!initialOnlyBlocked&&initialOverworld!=null&&v!=null&&!v.waitingAck
			&&v.session.equals(initialOverworld.session)&&v.dimension.equals(initialOverworld.dimension)&&v.generation==initialOverworld.generation;
	}

	private HostState() {
	}

	/** {"t":"cam","f":frame,"p":[x,y,z],"r":[yaw,pitch,roll],"fov":deg,"fp":bool,"pl":[x,y,z],"h":bodyYaw} */
	public static synchronized void bind(final SessionHandle handle) {
		if (bound != null && bound.handle.sameConnection(handle)) return;
		bound = new SessionPose(handle);
		frame = null;
		Passthrough.active = false;
	}

	public static synchronized boolean detach(final SessionHandle handle) {
		if (bound == null || !bound.handle.sameConnection(handle)) return false;
		bound = null; frame = null; Passthrough.active = false; return true;
	}

	public static synchronized void clearPose() {
		if (bound != null) bound.latest = null;
		frame = null; Passthrough.active = false;
	}

	/** Only authenticated Fabric hello/player_view/final-ACK handlers call this, after checking the actual MC UUID. */
	public static synchronized void observeWorldView(String session,String dim,long view,boolean waitingAck) {
		if(session==null||session.isBlank()||dim==null||dim.isBlank()||view<1)throw new IllegalArgumentException("Invalid trusted world view");
		WorldView previous=worldView;
		if(previous!=null&&previous.session.equals(session)&&view<previous.generation)return;
		WorldView next=new WorldView(session,dim,view,waitingAck);
		if(next.equals(previous))return;
		if(!worldScopeEnabled()){
			if(previous==null&&view==1&&!waitingAck&&dim.equals("minecraft:overworld"))initialOverworld=next;
			else if(initialOverworld==null||waitingAck||!session.equals(initialOverworld.session)||!dim.equals(initialOverworld.dimension)||view!=initialOverworld.generation)initialOnlyBlocked=true;
		}
		worldView=next;clearPose();
		// New coordinate mapping requires a new camera capture, not merely a new outgoing label.
		if(bound!=null&&(previous==null||!previous.session.equals(session)||previous.generation!=view||!previous.dimension.equals(dim))){
			bound.sourceEpoch=null;bound.sourceGeneration=-1;bound.originGeneration=-1;bound.originFrame=-1;bound.lastCaptureFrame=-1;bound.awaitingCommittedOrigin=false;
		}else if(bound!=null&&previous.waitingAck&&!waitingAck){
			// The authenticated final ACK commits this exact view's origin. Keep the
			// producer and capture fences; require a newer capture before locking it.
			bound.originGeneration=-1;bound.originFrame=-1;bound.awaitingCommittedOrigin=true;
		}
	}
	public static synchronized void clearWorldView() { worldView=null;initialOverworld=null;initialOnlyBlocked=false;clearPose(); }
	private static boolean allowed(WorldPoseScope scope) {
		WorldView v=worldView;
		if(!worldScopeEnabled())return v==null?scope==null:initialOverworldReady()&&scope==null;
		return v==null?scope==null:!v.waitingAck&&scope!=null&&scope.matches(v.session,v.dimension,v.generation);
	}
	/** The caller may forward this sample only while this exact accepted camera remains current. */
	public static synchronized boolean scopeHostPose(JsonObject query,Sample sample) {
		SessionPose owner=bound;
		if(sample==null||owner==null||owner.latest!=sample||!owner.handle.sameConnection(sample.session)||!allowed(sample.worldScope))return false;
		if(sample.worldScope!=null)sample.worldScope.write(query);
		else if(initialOverworldReady())writeInitialScope(query);
		return true;
	}
	/** Terrain carries its own production-time scope; an old ground batch is never repaired with current camera labels. */
	public static boolean acceptsWorldPacket(JsonObject query) {
		if(!worldScopeEnabled())return initialOverworldReady();
		if(worldView==null)return !GuestSession.strict();
		try{return allowed(WorldPoseScope.from(query));}catch(RuntimeException e){return false;}
	}
	/** Only the fixed initial native Overworld supports v15 packets; any transition latches this path closed. */
	public static synchronized boolean scopeInitialWorldPacket(JsonObject query) {
		if(!initialOverworldReady())return false;
		if(query.has("world_session")&&!query.get("world_session").getAsString().equals(initialOverworld.session))return false;
		if(query.has("dim")&&!query.get("dim").getAsString().equals(initialOverworld.dimension))return false;
		if(query.has("view")&&query.get("view").getAsLong()!=initialOverworld.generation)return false;
		writeInitialScope(query);return true;
	}
	private static void writeInitialScope(JsonObject query) {
		query.addProperty("world_session",initialOverworld.session);query.addProperty("dim",initialOverworld.dimension);query.addProperty("view",initialOverworld.generation);
	}

	public static SessionHandle session() { SessionPose s = bound; return s == null ? null : s.handle; }
	public static boolean matchesIdentity(UUID uuid) { SessionHandle h = session(); return h != null && (h.legacy() || h.identity().mcUuid().equals(uuid)); }
	public static boolean current(SessionHandle handle) { SessionHandle h = session(); return h != null && h.sameConnection(handle); }

	static synchronized boolean update(final SessionHandle handle, final JsonObject m) {
		SessionPose owner = bound;
		if (owner == null || !owner.handle.sameConnection(handle)) return false;
		WorldPoseScope scope=null;
		if(!worldScopeEnabled()){
			if(worldView!=null&&!initialOverworldReady())return false;
			if(worldView==null&&!handle.legacy())return false;
		}else if(worldView!=null){
			try{scope=WorldPoseScope.from(m);}catch(RuntimeException e){return false;}
			WorldView required=worldView;
			if(!scope.matches(required.session,required.dimension,required.generation))return false;
			if(owner.sourceEpoch!=null&&!owner.sourceEpoch.equals(scope.sourceEpoch()))return false;
			if(owner.sourceGeneration!=-1&&owner.sourceGeneration!=scope.sourceGeneration())return false;
			if(scope.captureFrame()<owner.lastCaptureFrame)return false;
			if(owner.awaitingCommittedOrigin&&scope.captureFrame()<=owner.lastCaptureFrame)return false;
			if(owner.originGeneration!=-1&&(scope.originGeneration()!=owner.originGeneration||scope.originFrame()!=owner.originFrame))return false;
			if(required.waitingAck){
				owner.sourceEpoch=scope.sourceEpoch();owner.sourceGeneration=scope.sourceGeneration();owner.originGeneration=scope.originGeneration();owner.originFrame=scope.originFrame();owner.lastCaptureFrame=scope.captureFrame();return false;
			}
		}else if(!handle.legacy())return false;
		JsonArray p = m.getAsJsonArray("p");
		JsonArray r = m.getAsJsonArray("r");
		JsonArray pl = m.has("pl") ? m.getAsJsonArray("pl") : p;
		float yaw = r.get(0).getAsFloat();
		long hostFrame = m.has("f") ? m.get("f").getAsLong() : owner.lastHostFrame + 1;
		if (hostFrame <= owner.lastHostFrame) return false;
		Pose next = new Pose(
			hostFrame,
			p.get(0).getAsDouble(), p.get(1).getAsDouble(), p.get(2).getAsDouble(),
			yaw, r.get(1).getAsFloat(), r.size() > 2 ? r.get(2).getAsFloat() : 0.0F,
			m.has("fov") ? m.get("fov").getAsFloat() : 70.0F,
			!m.has("fp") || m.get("fp").getAsBoolean(),
			pl.get(0).getAsDouble(), pl.get(1).getAsDouble(), pl.get(2).getAsDouble(),
			m.has("h") ? m.get("h").getAsFloat() : yaw,
			System.nanoTime(),
			m.has("drive") && m.get("drive").getAsBoolean(),
			m.has("look") ? m.getAsJsonArray("look").get(0).getAsFloat() : yaw,
			m.has("look") ? m.getAsJsonArray("look").get(1).getAsFloat() : r.get(1).getAsFloat(),
			m.has("gun") && m.get("gun").getAsBoolean(),
			m.has("g"), m.has("g") && m.get("g").getAsBoolean()
		);
		if (!Double.isFinite(next.x()) || !Double.isFinite(next.y()) || !Double.isFinite(next.z())
			|| !Double.isFinite(next.px()) || !Double.isFinite(next.py()) || !Double.isFinite(next.pz())
			|| !Float.isFinite(next.yaw()) || !Float.isFinite(next.pitch()) || !Float.isFinite(next.roll())
			|| !Float.isFinite(next.bodyYaw()) || !Float.isFinite(next.lookYaw()) || !Float.isFinite(next.lookPitch())
			|| !Float.isFinite(next.fov()) || next.fov() <= 0 || next.fov() >= 180) throw new IllegalArgumentException("Invalid camera pose");
		if(scope!=null){owner.sourceEpoch=scope.sourceEpoch();owner.sourceGeneration=scope.sourceGeneration();owner.originGeneration=scope.originGeneration();owner.originFrame=scope.originFrame();owner.lastCaptureFrame=scope.captureFrame();owner.awaitingCommittedOrigin=false;}
		owner.latest = new Sample(next,scope,handle); owner.lastHostFrame = hostFrame;
		Passthrough.hostMovesPlayer = !next.drive(); return true;
	}

	/** The latest pose if the host is still sending, else null. */
	static Pose live() {
		Sample s=liveSample();return s==null?null:s.pose;
	}
	public static Sample liveSample() {
		SessionPose owner = bound;
		if (owner == null || (!owner.handle.legacy() && !GuestSession.ready())) return null;
		Sample s = owner.latest;
		return s != null && allowed(s.worldScope) && System.nanoTime() - s.pose.receivedNanos() < TIMEOUT_NANOS ? s : null;
	}

	/** The pose for the frame being rendered, or null when no host is attached. */
	public static Pose frame() {
		FramePose f = frame;
		return f != null && f.owner == bound && allowed(f.sample.worldScope) && (f.owner.handle.legacy() || GuestSession.ready()) ? f.sample.pose : null;
	}

	/** Read-only evidence for the existing authenticated inspection request. */
	public static synchronized JsonObject inspection() {
		JsonObject report=new JsonObject();SessionPose owner=bound;WorldView view=worldView;
		Sample sample=owner==null?null:owner.latest;
		report.addProperty("bound",owner!=null);report.addProperty("guest_ready",GuestSession.ready());
		report.addProperty("world_scoped_camera",worldScopeEnabled());report.addProperty("trusted_world_view",view!=null);
		if(view!=null){report.addProperty("world_session",view.session);report.addProperty("dim",view.dimension);report.addProperty("view",view.generation);report.addProperty("waiting_ack",view.waitingAck);}
		if(owner!=null){
			report.addProperty("source_epoch",owner.sourceEpoch);report.addProperty("source_generation",owner.sourceGeneration);
			report.addProperty("origin_generation",owner.originGeneration);report.addProperty("origin_frame",owner.originFrame);
			report.addProperty("last_capture_frame",owner.lastCaptureFrame);report.addProperty("last_host_frame",owner.lastHostFrame);
			report.addProperty("awaiting_committed_origin",owner.awaitingCommittedOrigin);
		}
		report.addProperty("latest_present",sample!=null);
		if(sample!=null){report.addProperty("latest_age_ms",(System.nanoTime()-sample.pose.receivedNanos())/1_000_000.0);report.addProperty("latest_scope_allowed",allowed(sample.worldScope));}
		report.addProperty("live_sample",liveSample()!=null);report.addProperty("render_frame_present",frame()!=null);
		return report;
	}

	public static void beginFrame() {
		SessionPose owner = bound; Sample s = liveSample();
		frame = s != null && owner == bound ? new FramePose(owner, s) : null;
		Passthrough.active = frame() != null;
	}
}
