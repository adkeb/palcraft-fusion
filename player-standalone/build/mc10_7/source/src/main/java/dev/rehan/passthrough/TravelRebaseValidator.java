package dev.rehan.passthrough;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.Set;

/** Validates only the existing trusted Pal-server event channel; this is not a guest coordinate API. */
public final class TravelRebaseValidator {
    public record Bounds(int minY,int height,double minX,double maxX,double minZ,double maxZ) {}
    public record Position(double x,double y,double z) {}
    public static String rejectReason(JsonObject row,TravelAckValidator.Binding binding,Bounds bounds,boolean waitingForView) {
        try {
            if(!row.get("t").getAsString().equals("travel")||row.get("v").getAsInt()!=1
                ||!row.get("phase").getAsString().equals("rebase_required")||row.get("applied").getAsBoolean())return "invalid_rebase_event";
            String bindingError=TravelAckValidator.rejectBinding(row,binding);if(bindingError!=null)return bindingError;
            if(waitingForView)return "view_transition_already_pending";
            // The original Overworld origin/low Z is never changed by an automatic512page rebase.
            if(!Set.of("minecraft:the_nether","minecraft:the_end").contains(binding.dimension()))return "dimension_rebase_not_supported";
            if(!row.get("reason").getAsString().equals("physical_region_window"))return "unsupported_rebase_reason";
            String tx=row.get("tx").getAsString(),region=row.get("region_id").getAsString();
            if(tx.isBlank()||tx.length()>200||!tx.matches("[A-Za-z0-9_.:-]+")||region.isBlank()||region.length()>256)return "invalid_rebase_identity";
            Position position=position(row);
            if(Math.abs(position.x())>29999900||Math.abs(position.z())>29999900
                ||position.y()<bounds.minY()||position.y()>=((long)bounds.minY()+bounds.height())
                ||position.x()<bounds.minX()||position.x()>=bounds.maxX()||position.z()<bounds.minZ()||position.z()>=bounds.maxZ())return "rebase_position_outside_world";
            JsonObject source=row.getAsJsonObject("source_position");
            for(String key:new String[]{"X","Y","Z"})if(!Double.isFinite(source.get(key).getAsDouble()))return "invalid_source_position";
            JsonArray anchor=row.getAsJsonArray("next_mc_anchor");if(anchor.size()!=3)return "invalid_rebase_anchor";
            for(var value:anchor)if(!Double.isFinite(value.getAsDouble()))return "invalid_rebase_anchor";
            // The server registry derives the next actual mapping from the new player_view; the wire anchor is diagnostic.
            return null;
        }catch(RuntimeException exception){return "malformed_rebase_event";}
    }
    public static Position position(JsonObject row) {
        JsonArray values=row.getAsJsonArray("mc_pos");if(values.size()!=3)throw new IllegalArgumentException("Expected threeMC coordinates");
        Position result=new Position(values.get(0).getAsDouble(),values.get(1).getAsDouble(),values.get(2).getAsDouble());
        if(!Double.isFinite(result.x())||!Double.isFinite(result.y())||!Double.isFinite(result.z()))throw new IllegalArgumentException("Non-finiteMC coordinates");
        return result;
    }
    private TravelRebaseValidator() {}
}
