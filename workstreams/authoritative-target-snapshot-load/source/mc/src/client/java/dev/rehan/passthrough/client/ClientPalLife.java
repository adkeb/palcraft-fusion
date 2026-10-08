package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import java.util.UUID;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.DeathScreen;
import net.minecraft.client.player.LocalPlayer;

/** Pal's normal revival releases one vanilla MC respawn; health remains a server projection. */
public final class ClientPalLife {
    private static UUID player;
    private static String session;
    private static long observedNanos;
    private static LocalPlayer respawnRequestedFor;
    private ClientPalLife(){}
    public static void observe(JsonObject event){
        Minecraft mc=Minecraft.getInstance();
        if(mc.player==null||!event.has("mc_uuid")||!mc.player.getUUID().toString().equals(event.get("mc_uuid").getAsString()))return;
        if(event.has("life_active")&&!event.get("life_active").getAsBoolean()){clear();return;}
        player=mc.player.getUUID();session=event.get("session").getAsString();observedNanos=System.nanoTime();
        if(!event.get("alive").getAsBoolean()||event.get("dying").getAsBoolean()){
            if(respawnRequestedFor==mc.player)respawnRequestedFor=null;
            return;
        }
        if(event.has("respawn_ready")&&event.get("respawn_ready").getAsBoolean()
                &&mc.player.getHealth()<=0&&respawnRequestedFor!=mc.player){
            respawnRequestedFor=mc.player;
            mc.player.respawn();
        }
    }
    public static void clear(){player=null;session=null;observedNanos=0;respawnRequestedFor=null;}
    public static boolean mirrorsCurrentPlayer(){Minecraft mc=Minecraft.getInstance();return session!=null&&player!=null&&mc.player!=null&&player.equals(mc.player.getUUID())&&System.nanoTime()-observedNanos<5_000_000_000L;}
    public static void suppressDeathScreen(Minecraft mc){
        if(mirrorsCurrentPlayer()&&respawnRequestedFor!=null&&respawnRequestedFor!=mc.player
                &&mc.player.getHealth()>0&&mc.gui.screen() instanceof DeathScreen)mc.gui.setScreen(null);
    }
}
