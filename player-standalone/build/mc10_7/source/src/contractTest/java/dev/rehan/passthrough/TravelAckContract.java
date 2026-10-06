package dev.rehan.passthrough;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.List;

/** Tests bind the Pal completion proof to the actual player, boot and world view. */
final class TravelAckContract {
    private static final TravelAckValidator.Binding BINDING=new TravelAckValidator.Binding(
        "00000000-0000-0000-0000-000000000001","pal-1","session-1",3,"mc-boot-1","world-1","pal-boot-1","world-boot-1","minecraft:overworld",2);
    static void run() {
        JsonObject row=JsonParser.parseString("""
            {"t":"travel","v":1,"phase":"complete","operation":"world_view_ack","applied":true,"authority_source":"pal_server",
             "tx":"tx-1","player":"00000000-0000-0000-0000-000000000001","pal_uid":"pal-1","session_id":"session-1","session_generation":3,
             "mc_epoch":"mc-boot-1","world_id":"world-1","server_session_id":"pal-boot-1","world_session":"world-boot-1","dim":"minecraft:overworld","view":2,
             "mapping":{"region_id":"region-1"},"proof":{"server_position":{"X":1000,"Y":-200,"Z":50},"client_position":{"X":1002,"Y":-200,"Z":50},
             "target_pawn":{"X":1000,"Y":-200,"Z":50},"server_revision":1,"client_revision":2,"collision_committed":true,"visual_committed":true,"server_settle_ms":100}}
            """).getAsJsonObject();
        if(TravelAckValidator.rejectReason(row,BINDING,50)!=null)throw new AssertionError("Valid authority proof rejected");
        int rejected=0;
        for(String field:List.of("player","pal_uid","session_id","mc_epoch","world_id","server_session_id","world_session","dim")){
            JsonObject stale=row.deepCopy();stale.addProperty(field,"other");mustReject(stale);rejected++;
        }
        for(String field:List.of("session_generation","view")){JsonObject stale=row.deepCopy();stale.addProperty(field,999);mustReject(stale);rejected++;}
        JsonObject incomplete=row.deepCopy();incomplete.addProperty("applied",false);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").addProperty("collision_committed",false);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").addProperty("server_settle_ms",99);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").getAsJsonObject("client_position").addProperty("X",2000);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").getAsJsonObject("server_position").addProperty("X",Double.NaN);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").addProperty("client_revision",-1);mustReject(incomplete);rejected++;
        incomplete=row.deepCopy();incomplete.getAsJsonObject("proof").addProperty("server_settle_ms",15001);mustReject(incomplete);rejected++;
        JsonObject settled=row.deepCopy();settled.getAsJsonObject("proof").getAsJsonObject("server_position").addProperty("X",1045);
        settled.getAsJsonObject("proof").getAsJsonObject("client_position").addProperty("X",1080);
        if(TravelAckValidator.rejectReason(settled,BINDING,50)!=null)throw new AssertionError("Server/client replication tolerance not honored");
        testJournal();
        System.out.println("TravelAckContract: PASS ("+rejected+" stale/incomplete proof cases; torn line, bounded poll, truncate, rotate, oversized line)");
    }
    private static void mustReject(JsonObject row){if(TravelAckValidator.rejectReason(row,BINDING,50)==null)throw new AssertionError("Unverified travel released");}
    private static void testJournal(){
        try {
            Path directory=Files.createTempDirectory("palcraft-travel-contract-");Path file=directory.resolve("ack.ndjson"),rotated=directory.resolve("ack.old");
            try {
                Files.writeString(file,"{\"tx\":\"first\"}");CompleteLineJournal reader=new CompleteLineJournal(file,64);
                if(!reader.poll(1,1024).isEmpty())throw new AssertionError("Torn line delivered");
                Files.writeString(file,"\n{\"tx\":\"second\"}\n",StandardOpenOption.APPEND);
                if(!reader.poll(1,1024).equals(List.of("{\"tx\":\"first\"}")))throw new AssertionError("First committed line missing");
                if(!reader.poll(1,1024).equals(List.of("{\"tx\":\"second\"}")))throw new AssertionError("Bounded poll skipped a line");
                Files.writeString(file,"x\n");if(!reader.poll(2,1024).equals(List.of("x")))throw new AssertionError("Truncate not reset");
                Files.move(file,rotated);Files.writeString(file,"y\n");
                if(!reader.poll(2,1024).equals(List.of("y")))throw new AssertionError("Rotation not reset");
                Files.writeString(file,"z".repeat(100)+"\nvalid\n",StandardOpenOption.APPEND);
                if(!reader.poll(4,1024).equals(List.of("valid"))||reader.oversizedLines()!=1)throw new AssertionError("Oversized row handling failed");
                Files.deleteIfExists(rotated);
            } finally {Files.deleteIfExists(file);Files.deleteIfExists(rotated);Files.deleteIfExists(directory);}
        } catch(java.io.IOException exception){throw new AssertionError(exception);}
    }
    private TravelAckContract() {}
}
