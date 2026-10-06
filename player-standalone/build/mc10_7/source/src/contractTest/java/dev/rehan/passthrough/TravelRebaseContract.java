package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.util.List;

/** Next-candidate regression cases, deliberately not executed during the frozen firstOverworld deployment. */
public final class TravelRebaseContract {
    private static final TravelAckValidator.Binding BINDING=new TravelAckValidator.Binding(
        "00000000-0000-0000-0000-000000000001","pal-1","session-1",3,"mc-boot-1","world-1","pal-boot-1","world-boot-1","minecraft:the_nether",2);
    private static final TravelRebaseValidator.Bounds BOUNDS=new TravelRebaseValidator.Bounds(0,256,-29999900,29999900,-29999900,29999900);
    public static void main(String[] arguments){run();}
    static void run(){
        JsonObject row=JsonParser.parseString("""
            {"t":"travel","v":1,"phase":"rebase_required","applied":false,"reason":"physical_region_window","tx":"tx-rebase-1",
             "player":"00000000-0000-0000-0000-000000000001","pal_uid":"pal-1","session_id":"session-1","session_generation":3,
             "mc_epoch":"mc-boot-1","world_id":"world-1","server_session_id":"pal-boot-1","world_session":"world-boot-1","dim":"minecraft:the_nether","view":2,
             "mc_pos":[300,64,0],"source_position":{"X":-78099.9282,"Y":187800.8170,"Z":120000},"region_id":"room-0","next_mc_anchor":[512,64,0]}
            """).getAsJsonObject();
        if(TravelRebaseValidator.rejectReason(row,BINDING,BOUNDS,false)!=null)throw new AssertionError("Verified authority rebase rejected");
        int checks=1;
        for(String key:List.of("player","pal_uid","session_id","mc_epoch","world_id","server_session_id","world_session","dim")){
            JsonObject stale=row.deepCopy();stale.addProperty(key,"other");reject(stale,false);checks++;
        }
        for(String key:List.of("session_generation","view")){JsonObject stale=row.deepCopy();stale.addProperty(key,999);reject(stale,false);checks++;}
        reject(row,true);checks++;
        JsonObject bad=row.deepCopy();bad.getAsJsonArray("mc_pos").set(0,new com.google.gson.JsonPrimitive(Double.NaN));reject(bad,false);checks++;
        bad=row.deepCopy();bad.getAsJsonArray("mc_pos").set(1,new com.google.gson.JsonPrimitive(256));reject(bad,false);checks++;
        bad=row.deepCopy();bad.getAsJsonArray("mc_pos").set(0,new com.google.gson.JsonPrimitive(30000000));reject(bad,false);checks++;
        var overworld=new TravelAckValidator.Binding(BINDING.player(),BINDING.palUid(),BINDING.sessionId(),BINDING.sessionGeneration(),BINDING.mcEpoch(),BINDING.worldId(),BINDING.serverSessionId(),BINDING.worldSession(),"minecraft:overworld",BINDING.view());
        bad=row.deepCopy();bad.addProperty("dim","minecraft:overworld");
        if(!"dimension_rebase_not_supported".equals(TravelRebaseValidator.rejectReason(bad,overworld,BOUNDS,false)))throw new AssertionError("Overworld origin was allowed to rebase");checks++;
        String property="palcraft.legacyPlayerTeleportEvents",old=System.getProperty(property);
        try{
            System.clearProperty(property);
            if(BridgeEventPolicy.allows("{\"t\":\"pteleport\",\"pos\":[1,2,3]}"))throw new AssertionError("Unscoped teleport broadcast escaped");checks++;
            if(!BridgeEventPolicy.allows("{\"t\":\"blocks\",\"label\":\"pteleport\"}"))throw new AssertionError("World event incorrectly filtered");checks++;
            System.setProperty(property,"true");if(!BridgeEventPolicy.allows("{\"t\":\"pteleport\"}"))throw new AssertionError("Explicit legacy opt-in failed");checks++;
        }finally{if(old==null)System.clearProperty(property);else System.setProperty(property,old);}
        System.out.println("TravelRebaseContract: PASS ("+checks+" binding/bounds/Overworld/legacy-event checks)");
    }
    private static void reject(JsonObject row,boolean waiting){if(TravelRebaseValidator.rejectReason(row,BINDING,BOUNDS,waiting)==null)throw new AssertionError("Unverified rebase accepted");}
    private TravelRebaseContract(){}
}
