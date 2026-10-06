package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import java.util.UUID;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.DeathScreen;

/** A bound avatar uses the real Pal death/revive UI. This never sends a respawn or writes health. */
public final class ClientPalLife {
    private static UUID player;
    private static String session;
    private static long observedNanos;
    private ClientPalLife(){}
    public static void observe(JsonObject event){
        Minecraft mc=Minecraft.getInstance();
        if(mc.player==null||!event.has("mc_uuid")||!mc.player.getUUID().toString().equals(event.get("mc_uuid").getAsString()))return;
        if(event.has("life_active")&&!event.get("life_active").getAsBoolean()){clear();return;}
        player=mc.player.getUUID();session=event.get("session").getAsString();observedNanos=System.nanoTime();
    }
    public static void clear(){player=null;session=null;observedNanos=0;}
    public static boolean mirrorsCurrentPlayer(){Minecraft mc=Minecraft.getInstance();return session!=null&&player!=null&&mc.player!=null&&player.equals(mc.player.getUUID())&&System.nanoTime()-observedNanos<5_000_000_000L;}
    public static void suppressDeathScreen(Minecraft mc){
        if(mirrorsCurrentPlayer()&&mc.gui.screen() instanceof DeathScreen)mc.gui.setScreen(null);
    }
}
