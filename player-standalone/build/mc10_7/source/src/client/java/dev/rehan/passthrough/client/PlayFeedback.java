package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.client.mixin.MiningAccessor;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;

/** Player-facing feedback; the same state controls native host input ownership. */
public final class PlayFeedback {
 private static int ticks;
 private record Vitals(double hp,double maxHp,double shield,double maxShield,boolean alive,boolean dying,long received) {}
 private static volatile Vitals vitals;
 private record Viewport(double aspect,long received) {}
 private static volatile Viewport viewport;
 /** Camera-message extension; aspect describes the real Pal client area, excluding its title bar. */
 public static void updateViewportAspect(double aspect) {
  if(Double.isFinite(aspect)&&aspect>=.5&&aspect<=4)viewport=new Viewport(aspect,System.nanoTime());else viewport=null;
 }
 public static void clearViewportAspect(){viewport=null;}
 static double viewportAspect(){Viewport v=viewport;return v!=null&&System.nanoTime()-v.received<250_000_000L?v.aspect:0;}
 /** The entity authority routes the already-bound local player here. This never changes either game's health. */
 public static void updateVitals(double hp,double maxHp,double shield,double maxShield,boolean alive,boolean dying) {
  if(!Double.isFinite(hp)||!Double.isFinite(maxHp)||!Double.isFinite(shield)||!Double.isFinite(maxShield)||maxHp<=0||maxShield<0) return;
  vitals=new Vitals(Math.clamp(hp,0,maxHp),maxHp,Math.clamp(shield,0,maxShield),maxShield,alive,dying,System.nanoTime());
 }
 public static void clearVitals(){vitals=null;}
 private static Vitals liveVitals(){Vitals v=vitals;return v!=null&&System.nanoTime()-v.received<750_000_000L?v:null;}
 public static void tick(Minecraft mc) {
  if (++ticks % 2 != 0 || !Passthrough.active || mc.player == null) return;
  JsonObject r=new JsonObject(); r.addProperty("t","feedback");
  r.addProperty("unix",System.currentTimeMillis()/1000);
  r.addProperty("screen",mc.gui.screen()!=null);
  r.addProperty("screen_name",mc.gui.screen()==null?"none":mc.gui.screen().getClass().getSimpleName());
  r.addProperty("mode",ClientInput.buildMode);
  r.addProperty("progress",mc.gameMode!=null&&mc.gameMode.isDestroying()?((MiningAccessor)mc.gameMode).palcraft$destroyProgress():0);
  r.addProperty("selected",BuiltInRegistries.ITEM.getKey(mc.player.getMainHandItem().getItem()).toString());
  r.addProperty("count",mc.player.getMainHandItem().getCount());
  r.addProperty("gui_width",mc.getWindow().getGuiScaledWidth());r.addProperty("gui_height",mc.getWindow().getGuiScaledHeight());
  r.add("placement",PlacementGuide.feedback());
  r.addProperty("viewport_aspect",viewportAspect());
  if(ticks%20==0)r.add("hud_export",FrameExporter.statistics());
  Vitals v=liveVitals();
  if(v!=null){JsonObject life=new JsonObject();life.addProperty("authority","pal_server");life.addProperty("hp",v.hp);life.addProperty("max_hp",v.maxHp);life.addProperty("shield",v.shield);life.addProperty("max_shield",v.maxShield);life.addProperty("alive",v.alive);life.addProperty("dying",v.dying);r.add("vitals",life);}
  if(mc.level!=null&&mc.hitResult instanceof BlockHitResult hit && hit.getType()==HitResult.Type.BLOCK) {
   var p=hit.getBlockPos();r.addProperty("x",p.getX());r.addProperty("y",p.getY());r.addProperty("z",p.getZ());
   r.addProperty("block",BuiltInRegistries.BLOCK.getKey(mc.level.getBlockState(p).getBlock()).toString());
  }
  Passthrough.events.accept(r.toString());
 }
 public static void draw(GuiGraphicsExtractor g) {
  Minecraft mc=Minecraft.getInstance();
  if(!Passthrough.active || mc.player==null) return;
  if(mc.gui.screen()!=null) {
   g.centeredText(mc.font,"E / F8 关闭界面 · F5 返回帕鲁",g.guiWidth()/2,12,0xffffffff);
   if(mc.gui.screen() instanceof net.minecraft.client.gui.screens.inventory.InventoryScreen){int x=g.guiWidth()/2,y=g.guiHeight()-34;g.fill(x-64,y,x+64,y+16,0xee20483f);g.centeredText(mc.font,"帕鲁材料兑换",x,y+4,0xffa5ffe1);}
   return;
  }
  PlacementGuide.draw(g);
  int cx=g.guiWidth()/2, y=14;
  Vitals life=liveVitals();
  if(life!=null){
   if(!life.alive||life.dying)g.centeredText(mc.font,life.dying?"已倒下 · 等待救援":"已死亡",cx,g.guiHeight()/2+38,0xffffb5b5);
   else if(life.maxShield>0){
    int barY=g.guiHeight()-66;
    g.fill(cx-51,barY,cx+51,barY+6,0xcc102024);
    g.fill(cx-50,barY+1,cx-50+(int)(100*life.shield/life.maxShield),barY+5,0xff7fc8ff);
    g.centeredText(mc.font,"护盾 "+(int)Math.ceil(life.shield)+" / "+(int)Math.ceil(life.maxShield),cx,barY-10,0xffb8deff);
   }
  }
  g.centeredText(mc.font,"左键挖掘 · 右键放置/使用 · E 背包 · 1–9 / 滚轮切换",cx,g.guiHeight()-48,0xffdbe9e5);
  g.centeredText(mc.font,ClientInput.buildMode?"Minecraft 形态 · F5 返回帕鲁":"F5 变身 Minecraft",cx,y,0xffdbe9e5);
  if(mc.level!=null&&mc.gameMode!=null&&mc.hitResult instanceof BlockHitResult hit && hit.getType()==HitResult.Type.BLOCK) {
   var state=mc.level.getBlockState(hit.getBlockPos());
   if(!state.isAir()&&!state.is(net.minecraft.world.level.block.Blocks.BARRIER)) {
    g.centeredText(mc.font,state.getBlock().getName(),cx,y+14,0xff8fffe0);
    if(mc.gameMode.isDestroying()) {
     float progress=Math.clamp(((MiningAccessor)mc.gameMode).palcraft$destroyProgress(),0,1);
     g.fill(cx-51,y+28,cx+51,y+34,0xcc102024);
     g.fill(cx-50,y+29,cx-50+(int)(100*progress),y+33,0xff67e7b7);
    }
   }
  }
 }
}
