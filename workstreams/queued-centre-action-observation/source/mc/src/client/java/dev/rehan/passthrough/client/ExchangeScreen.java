package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import dev.rehan.passthrough.ResourceExchange;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;

/** Player-operated exchange, backed by the real Palworld server inventory. */
final class ExchangeScreen extends Screen {
 private static final String[] IDS={"Wood","Stone","Coal","Charcoal"};
 private static final String[] LABELS={"木材 ↔ 橡木原木","石头 ↔ 圆石","煤炭 ↔ 煤炭","木炭 ↔ 木炭"};
 private final Screen parent;
 private JsonObject balances;
 private boolean busy;
 private int amount=8;
 private String message="读取材料中…";
 ExchangeScreen(Screen parent){super(Component.literal("帕鲁 · MC 材料兑换"));this.parent=parent;}
 @Override protected void init(){
  int left=width/2-178,top=height/2-64;
  for(int i=0;i<4;i++){final String id=IDS[i];int y=top+i*28;
   addRenderableWidget(Button.builder(Component.literal("转入 MC"),b->exchange(id,true)).bounds(left+170,y,88,20).build());
   addRenderableWidget(Button.builder(Component.literal("转回帕鲁"),b->exchange(id,false)).bounds(left+266,y,90,20).build());
  }
  addRenderableWidget(Button.builder(Component.literal("返回背包"),b->onClose()).bounds(width/2-50,top+146,100,20).build());
  addRenderableWidget(Button.builder(Component.literal("数量：8"),b->{if(!busy){amount=amount==1?8:amount==8?32:1;b.setMessage(Component.literal("数量："+amount));}}).bounds(left,top+146,100,20).build());
  refresh();
 }
 private void refresh(){
  if(busy)return;busy=true;ClientBridge.balances(r->minecraft.execute(()->{busy=false;if(r.has("counts")){balances=r;if(message.equals("读取材料中…"))message="每 1 份帕鲁材料兑换 1 个对应 MC 物品";}else message=r.has("error")?r.get("error").getAsString():"读取失败";}));
 }
 private void exchange(String id,boolean toMc){
  if(busy)return;busy=true;message="正在兑换…";
  ClientBridge.exchange(id,toMc,amount,r->minecraft.execute(()->{
   busy=false;message=r.has("ok")&&r.get("ok").getAsBoolean()?"兑换完成，材料已存入背包":r.has("error")?r.get("error").getAsString():"兑换未完成";refresh();
  }));
 }
 @Override public void extractRenderState(GuiGraphicsExtractor g,int x,int y,float partial){
  int left=width/2-178,top=height/2-64;
  g.fill(left-12,top-40,left+368,top+180,0xee10222b);
  g.centeredText(font,title,width/2,top-30,0xffeffffb);
  g.centeredText(font,"使用背包与当前基地资源 · 正常生存合成",width/2,top-14,0xff95c6b8);
  for(int i=0;i<4;i++){
   g.text(font,LABELS[i],left,top+i*28,0xffffffff);
   String counts="—";
   if(balances!=null)counts="可用 "+balances.getAsJsonObject("counts").get(IDS[i])+"  /  MC "+balances.getAsJsonObject("mc_counts").get(IDS[i]);
   g.text(font,counts,left,top+i*28+12,0xffa7c1c9);
  }
  g.centeredText(font,message,width/2,top+124,busy?0xffffd88c:0xffa6ead2);
  super.extractRenderState(g,x,y,partial);
 }
 @Override public boolean isPauseScreen(){return false;}
 @Override public void onClose(){minecraft.gui.setScreen(parent);}
}
