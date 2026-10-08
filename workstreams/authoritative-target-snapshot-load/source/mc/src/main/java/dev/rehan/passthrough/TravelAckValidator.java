package dev.rehan.passthrough;

import com.google.gson.JsonObject;

/** Used only for rows read from the configured Pal-server journal, never guest packets. */
public final class TravelAckValidator {
    public record Binding(String player, String palUid, String sessionId, long sessionGeneration, String mcEpoch,
                          String worldId, String serverSessionId, String worldSession, String dimension, long view) {}

    public static String rejectReason(JsonObject row, Binding binding, double toleranceCm) {
        try {
            if (!Double.isFinite(toleranceCm) || toleranceCm <= 0) return "invalid_position_policy";
            if (!text(row,"t").equals("travel") || row.get("v").getAsInt()!=1 || !text(row,"phase").equals("complete")
                || !text(row,"operation").equals("world_view_ack") || !row.get("applied").getAsBoolean()
                || !text(row,"authority_source").equals("pal_server")) return "incomplete_authority_result";
            String tx=text(row,"tx");
            if(tx.isBlank() || tx.length()>200 || !tx.matches("[A-Za-z0-9_.:-]+"))return "invalid_transaction";
            String bindingError=rejectBinding(row,binding);if(bindingError!=null)return bindingError;
            JsonObject mapping=row.getAsJsonObject("mapping");
            if(text(mapping,"region_id").isBlank())return "missing_region";
            JsonObject proof=row.getAsJsonObject("proof");
            if(!proof.get("collision_committed").getAsBoolean() || !proof.get("visual_committed").getAsBoolean()
                || proof.get("server_settle_ms").getAsLong()<100 || proof.get("server_settle_ms").getAsLong()>15000
                || !revision(proof,"server_revision") || !revision(proof,"client_revision"))return "incomplete_readiness_proof";
            double[] target=position(proof.getAsJsonObject("target_pawn"));
            double[] serverPosition=position(proof.getAsJsonObject("server_position"));
            if(distance(target,serverPosition)>toleranceCm
                || distance(serverPosition,position(proof.getAsJsonObject("client_position")))>toleranceCm)return "unsettled_pawn";
            return null;
        } catch(RuntimeException exception) { return "malformed_authority_result"; }
    }

    public static String rejectBinding(JsonObject row,Binding binding) {
        try {
            if(!text(row,"player").equals(binding.player()) || !text(row,"pal_uid").equals(binding.palUid())
                || !text(row,"session_id").equals(binding.sessionId()) || row.get("session_generation").getAsLong()!=binding.sessionGeneration()
                || !text(row,"mc_epoch").equals(binding.mcEpoch()) || !text(row,"world_id").equals(binding.worldId())
                || !text(row,"server_session_id").equals(binding.serverSessionId()))return "stale_player_binding";
            if(!text(row,"world_session").equals(binding.worldSession()) || !text(row,"dim").equals(binding.dimension())
                || row.get("view").getAsLong()!=binding.view())return "stale_world_view";
            return null;
        } catch(RuntimeException exception){return "malformed_player_binding";}
    }

    private static String text(JsonObject row,String key) { return row.get(key).getAsString(); }
    private static boolean revision(JsonObject row,String key) {
        return row.get(key).isJsonPrimitive()&&row.getAsJsonPrimitive(key).isNumber()
            &&row.get(key).getAsBigDecimal().toBigIntegerExact().signum()>=0;
    }
    private static double[] position(JsonObject row) {
        double[] values={row.get("X").getAsDouble(),row.get("Y").getAsDouble(),row.get("Z").getAsDouble()};
        for(double value:values)if(!Double.isFinite(value))throw new IllegalArgumentException("Non-finite position");
        return values;
    }
    private static double distance(double[] a,double[] b) { return Math.hypot(Math.hypot(a[0]-b[0],a[1]-b[1]),a[2]-b[2]); }
    public static String transactionKey(JsonObject row) {
        return text(row,"tx")+"|"+text(row,"player")+"|"+text(row,"session_id")+"|"+row.get("session_generation").getAsLong()
            +"|"+text(row,"mc_epoch")+"|"+text(row,"world_session")+"|"+row.get("view").getAsLong();
    }
    private TravelAckValidator() {}
}
