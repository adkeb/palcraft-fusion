package dev.rehan.passthrough;

import com.google.gson.*;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;
import net.minecraft.core.component.DataComponents;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.food.FoodProperties;
import net.minecraft.world.item.ItemStack;

/** Original vanilla consumption is the payment. Native Pal item effects receive one completion receipt. */
public final class PalFoodBridge {
    private record Token(String id,ItemStack stack,int before,JsonObject event,Map<String,String> effects){}
    private static final Map<UUID,Token> consuming=new HashMap<>();
    private static final Map<String,JsonObject> pending=new LinkedHashMap<>();
    private static final Map<UUID,String> waiting=new HashMap<>();
    private static Path root;
    private PalFoodBridge(){}
    static void attach(Path directory){root=directory;consuming.clear();pending.clear();waiting.clear();}
    public static boolean canConsume(ServerPlayer p,ItemStack stack){
        return !p.getAbilities().instabuild && stack.has(DataComponents.FOOD) && PalEntityBridge.foodReady(p)
                && !waiting.containsKey(p.getUUID());
    }
    public static boolean begin(ServerPlayer p,ItemStack stack){
        if(!canConsume(p,stack))return false;
        FoodProperties food=stack.get(DataComponents.FOOD);if(food==null||stack.getCount()<1)return false;
        if(food.nutrition()<0||food.nutrition()>20||!Float.isFinite(food.saturation())||food.saturation()<0||food.saturation()>40)return false;
        JsonObject event=PalEntityBridge.foodContext(p);if(event==null)return false;
        String id=UUID.randomUUID().toString();event.addProperty("id",id);event.addProperty("t","entity_consume");
        event.addProperty("item",BuiltInRegistries.ITEM.getKey(stack.getItem()).toString());
        event.addProperty("nutrition",food.nutrition());event.addProperty("saturation",food.saturation());event.addProperty("before_count",stack.getCount());
        event.addProperty("phase","prepared");event.addProperty("creative",false);
        try{PalEntityBridge.write(root.resolve("mc-food-"+id+".json"),event);}
        catch(IOException e){Passthrough.LOG.warn("Food receipt preparation failed: {}",e.toString());return false;}
        consuming.put(p.getUUID(),new Token(id,stack,stack.getCount(),event,effects(p)));return true;
    }
    public static void complete(ServerPlayer p,ItemStack original){
        Token token=consuming.remove(p.getUUID());if(token==null||token.stack()!=original)return;
        JsonObject event=token.event();int after=original.getCount();
        event.addProperty("after_count",after);event.addProperty("consumed_count",token.before()-after);
        boolean paid=after==token.before()-1&&!p.getAbilities().instabuild;
        event.addProperty("vanilla_completed",paid);event.addProperty("phase",paid?"consumed":"cancelled_unpaid");
        JsonArray effects=new JsonArray();
        for(MobEffectInstance e:p.getActiveEffects()){
            String kind=e.getEffect().unwrapKey().map(k->k.identifier().toString()).orElse("");
            String value=e.getAmplifier()+":"+e.getDuration();
            if(!value.equals(token.effects().get(kind))){JsonObject r=new JsonObject();r.addProperty("id",kind);r.addProperty("amplifier",e.getAmplifier());r.addProperty("duration",e.getDuration());effects.add(r);}
        }
        event.add("effects",effects);event.addProperty("effects_json",effects.toString());
        try{
            PalEntityBridge.write(root.resolve("mc-food-"+token.id()+".json"),event);
            if(paid){pending.put(token.id(),event);waiting.put(p.getUUID(),token.id());writeIndex();}
        }catch(IOException e){Passthrough.LOG.error("Paid food completion receipt uncertain {}: {}",token.id(),e.toString());
            waiting.put(p.getUUID(),token.id());p.sendSystemMessage(Component.literal("补给同步未确认，消费凭据已保留"));}
        var state=PalEntityBridge.playerState(p);
        if(state!=null){p.getFoodData().setFoodLevel(EntityVitals.food(state.fullStomach(),state.maxFullStomach()));p.getFoodData().setSaturation(0);}
    }
    private static Map<String,String> effects(ServerPlayer p){
        Map<String,String> r=new HashMap<>();for(MobEffectInstance e:p.getActiveEffects())r.put(e.getEffect().unwrapKey().map(k->k.identifier().toString()).orElse(""),e.getAmplifier()+":"+e.getDuration());return r;
    }
    static void tick(){
        if(root==null)return;
        for(var entry:new ArrayList<>(pending.entrySet())){
            Path file=root.resolve("pal-food-result-"+entry.getKey()+".json");if(!Files.exists(file))continue;
            try{
                JsonObject result=JsonParser.parseString(Files.readString(file)).getAsJsonObject();
                if(!entry.getKey().equals(result.get("id").getAsString()))continue;
                pending.remove(entry.getKey());
                String source=entry.getValue().get("source").getAsString();UUID uuid=UUID.fromString(source.substring(3));
                if(result.get("ok").getAsBoolean())waiting.remove(uuid,entry.getKey());
                // Failed/uncertain paid food keeps the player-specific gate; never re-eat or issue a free replacement.
                Passthrough.events.accept(result.toString());
            }catch(IOException|RuntimeException e){Passthrough.LOG.debug("Food receipt read: {}",e.toString());}
        }
        try{writeIndex();}catch(IOException e){Passthrough.LOG.warn("Food outbox: {}",e.toString());}
    }
    private static void writeIndex()throws IOException{
        JsonObject index=PalEntityBridge.authorityContext();index.addProperty("t","entity_foods");
        JsonArray ids=new JsonArray();for(String id:pending.keySet())ids.add(id);index.add("ids",ids);
        PalEntityBridge.write(root.resolve("mc-foods.json"),index);
    }
    public static JsonObject status(){JsonObject r=new JsonObject();r.addProperty("pending",pending.size());r.addProperty("blocked_paid_recovery",waiting.size());return r;}
}
