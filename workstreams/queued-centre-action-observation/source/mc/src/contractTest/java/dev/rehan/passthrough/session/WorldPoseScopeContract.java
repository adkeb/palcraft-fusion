package dev.rehan.passthrough.session;

import com.google.gson.JsonObject;

/** Targeted next-counter contract; does not start Minecraft or repeat the old concurrent suite. */
public final class WorldPoseScopeContract {
    private static int checks;
    private static void check(boolean value,String reason){checks++;if(!value)throw new AssertionError(reason);}
    private static void rejected(Runnable action){checks++;try{action.run();}catch(IllegalArgumentException|NullPointerException e){return;}throw new AssertionError("Expected stale capture rejection");}
    public static void main(String[] args){
        WorldPoseScope first=new WorldPoseScope("world-live","minecraft:the_nether",2,"producer-a",4,7,100,101);
        JsonObject wire=new JsonObject();first.write(wire);
        check(first.equals(WorldPoseScope.from(wire)),"Original capture did not round-trip");
        check(first.matches("world-live","minecraft:the_nether",2),"First new-origin capture rejected");
        check(first.originGeneration()!=first.sourceGeneration(),"Mapping and socket counters collapsed");
        rejected(()->new WorldPoseScope("world-live","minecraft:the_nether",2,"producer-a",4,7,100,100));
        rejected(()->new WorldPoseScope("world-live","minecraft:the_nether",2,"producer-a",4,7,100,99));
        check(!first.matches("world-live","minecraft:overworld",1),"Old origin tuple can masquerade as target");
        WorldPoseScope repeated=WorldPoseScope.from(wire.deepCopy());check(repeated.captureFrame()==101,"Heartbeat invented a new capture");
        JsonObject relabel=wire.deepCopy();relabel.addProperty("view",3);relabel.addProperty("dim","minecraft:the_end");
        check(!first.matches(relabel.get("world_session").getAsString(),relabel.get("dim").getAsString(),relabel.get("view").getAsLong()),"Unchanged source capture got newest ACK labels");
        JsonObject oldEpoch=wire.deepCopy();oldEpoch.addProperty("source_epoch","producer-previous");
        check(!first.sourceEpoch().equals(WorldPoseScope.from(oldEpoch).sourceEpoch()),"Producer epoch omitted from immutable sample");
        JsonObject badAlias=wire.deepCopy();badAlias.addProperty("source_frame",102);rejected(()->WorldPoseScope.from(badAlias));
        JsonObject fractional=wire.deepCopy();fractional.addProperty("capture_frame",101.5);rejected(()->WorldPoseScope.from(fractional));
        JsonObject missing=wire.deepCopy();missing.remove("source_epoch");rejected(()->WorldPoseScope.from(missing));
        System.out.println("WorldPoseScopeContract: PASS ("+checks+" capture boundary/epoch/counter checks; no game or sockets)");
    }
}
