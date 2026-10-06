import dev.rehan.passthrough.EntityCombatLedger;
import dev.rehan.passthrough.EntityVitals;

/** Offline assertions against the actual engine-independent Java authority code. */
public final class EntityCombatTest {
    private static int tests;
    private static void check(boolean yes){tests++;if(!yes)throw new AssertionError("assertion "+tests);}
    private static EntityCombatLedger.Hit hit(String id,double amount){return new EntityCombatLedger.Hit(id,"pal-session","mc-epoch","pal-epoch",
        "mc:00000001-0000-0000-0000-000000000001","pal:00000000-0000-0000-0000-000000000000/00000002-0000-0000-0000-000000000002",amount,"pal:native");}
    public static void main(String[] args){
        String id="00000003-0000-0000-0000-000000000003";
        EntityCombatLedger l=new EntityCombatLedger(2);l.reset("pal-session","mc-epoch");
        check(l.inspect(hit(id,3))==EntityCombatLedger.Decision.ACCEPT);
        check(l.reserve(hit(id,3))==EntityCombatLedger.Decision.ACCEPT);
        check(l.reserve(hit(id,3))==EntityCombatLedger.Decision.REPLAY);
        check(l.reserve(hit(id,4))==EntityCombatLedger.Decision.CONFLICT);
        check(!EntityCombatLedger.valid(hit(id,Double.NaN)));
        check(!EntityCombatLedger.valid(hit(id,Double.POSITIVE_INFINITY)));
        check(!EntityCombatLedger.valid(hit(id,-1)));
        check(!EntityCombatLedger.valid(hit(id,0)));
        check(!EntityCombatLedger.valid(hit(id,10001)));
        check(!EntityCombatLedger.entityId("mc:123"));
        check(!EntityCombatLedger.uuid("../ack"));
        l.reset("pal-session","new-mc-epoch");check(l.inspect(hit(id,3))==EntityCombatLedger.Decision.STALE_EPOCH);
        l.reset("new-pal-session","mc-epoch");check(l.inspect(hit(id,3))==EntityCombatLedger.Decision.STALE_SESSION);
        float actual=EntityVitals.health(1,2370,true,false);
        check(Math.abs(actual-20f/2370)<0.00000001);
        for(int switchForm=0;switchForm<50;switchForm++)check(EntityVitals.health(1,2370,true,false)==actual);
        check(EntityVitals.health(2370,2370,true,false)==20);
        check(EntityVitals.health(1,2370,false,false)==0);
        check(EntityVitals.health(1,2370,true,true)==0);
        check(EntityVitals.food(0,100)==0);check(EntityVitals.food(50,100)==10);check(EntityVitals.food(100,100)==20);
        try{EntityVitals.health(1,0,true,false);throw new AssertionError("Missing max HP accepted");}catch(IllegalArgumentException expected){tests++;}
        System.out.println("{\"ok\":true,\"suite\":\"java_entity_authority\",\"assertions\":"+tests+",\"pal_1_of_2370_mapped_mc_hp\":"+actual+",\"real_game_runtime_verified\":false}");
    }
}
