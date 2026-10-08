package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;

/** Copied with camera bytes at capture time, never inferred from the newest ACK at forwarding time. */
public record WorldPoseScope(String worldSession, String dimension, long view,
                             String sourceEpoch, long sourceGeneration, long originGeneration, long originFrame, long captureFrame) {
    public WorldPoseScope {
        if (worldSession == null || worldSession.isBlank() || dimension == null || dimension.isBlank() || view < 1
            || sourceEpoch == null || sourceEpoch.isBlank() || sourceGeneration < 1 || originGeneration < 1 || originFrame < 0 || captureFrame <= originFrame)
            throw new IllegalArgumentException("Camera was not captured after its origin commit");
    }
    public boolean matches(String session, String dim, long generation) {
        return worldSession.equals(session) && dimension.equals(dim) && view == generation;
    }
    public void write(JsonObject q) {
        q.addProperty("world_session", worldSession); q.addProperty("dim", dimension); q.addProperty("view", view);
        q.addProperty("source_epoch", sourceEpoch); q.addProperty("source_generation", sourceGeneration);
        q.addProperty("source_frame", captureFrame);
        q.addProperty("origin_generation", originGeneration); q.addProperty("origin_frame", originFrame); q.addProperty("capture_frame", captureFrame);
    }
    public static WorldPoseScope from(JsonObject q) {
        long generation=integer(q,"origin_generation"), capture=integer(q,"capture_frame");
        if(capture!=integer(q,"source_frame"))throw new IllegalArgumentException("Camera source_frame differs from captured pose");
        return new WorldPoseScope(q.get("world_session").getAsString(), q.get("dim").getAsString(), integer(q,"view"),
            q.get("source_epoch").getAsString(), integer(q,"source_generation"), generation, integer(q,"origin_frame"), capture);
    }
    private static long integer(JsonObject q,String key) {
        String raw=q.get(key).toString();if(!raw.matches("0|[1-9][0-9]{0,17}"))throw new IllegalArgumentException("Invalid camera capture counter");
        return Long.parseLong(raw);
    }
}
