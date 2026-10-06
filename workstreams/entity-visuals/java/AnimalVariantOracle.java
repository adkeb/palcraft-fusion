// Complete small baby/climate batch; uses the reusable real-model pose exporter.
import java.util.*;
import com.google.gson.Gson;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.animal.cow.*;
import net.minecraft.client.model.animal.sheep.*;
import net.minecraft.client.model.animal.chicken.*;
import net.minecraft.client.renderer.entity.state.*;

public final class AnimalVariantOracle {
    private static final Gson JSON=new Gson();
    static Model<?> model(String kind,String variant,boolean baby){
        if(kind.equals("cow")){
            if(baby)return new BabyCowModel(BabyCowModel.createBodyLayer().bakeRoot());
            if(variant.equals("cold"))return new ColdCowModel(ColdCowModel.createBodyLayer().bakeRoot());
            if(variant.equals("warm"))return new WarmCowModel(WarmCowModel.createBodyLayer().bakeRoot());
            return new CowModel(CowModel.createBodyLayer().bakeRoot());
        }
        if(kind.equals("chicken")){
            if(baby)return new BabyChickenModel(BabyChickenModel.createBodyLayer().bakeRoot());
            if(variant.equals("cold"))return new ColdChickenModel(ColdChickenModel.createBodyLayer().bakeRoot());
            return new AdultChickenModel(AdultChickenModel.createBodyLayer().bakeRoot());
        }
        if(kind.equals("sheep_wool"))return new SheepFurModel((baby?BabySheepModel.createBodyLayer():SheepFurModel.createFurLayer()).bakeRoot());
        return baby?new BabySheepModel(BabySheepModel.createBodyLayer().bakeRoot()):new SheepModel(SheepModel.createBodyLayer().bakeRoot());
    }
    static void sample(Model<?> model,String key,String kind,String climate,boolean baby,String name,float walk,float speed,float yaw,float pitch,float age)throws Exception {
        LivingEntityRenderState s=kind.equals("cow")?new CowRenderState():kind.equals("chicken")?new ChickenRenderState():new SheepRenderState();
        s.isBaby=baby;s.ageScale=baby?.5f:1;s.scale=1;s.walkAnimationPos=walk;s.walkAnimationSpeed=speed;s.yRot=yaw;s.xRot=pitch;s.ageInTicks=age;
        Map<String,Object> input=new LinkedHashMap<>();input.put("baby",baby);input.put("variant",climate);input.put("age_scale",s.ageScale);input.put("scale",1);input.put("walk_pos",walk);input.put("walk_speed",speed);input.put("head_yaw",yaw);input.put("head_pitch",pitch);input.put("age",age);
        if(s instanceof SheepRenderState a){a.headEatPositionScale=name.equals("action")?.6f:0;a.headEatAngleScale=name.equals("action")?.7f:(float)Math.toRadians(pitch);input.put("head_eat_position",a.headEatPositionScale);input.put("head_eat_angle",a.headEatAngleScale);}
        if(s instanceof ChickenRenderState a){a.flap=age*.3f;a.flapSpeed=name.equals("action")?.75f:.15f;input.put("flap",a.flap);input.put("flap_speed",a.flapSpeed);}
        Map<String,Object> row=new LinkedHashMap<>(VanillaPoseExport.sample(model,s));row.put("type","sample");row.put("rig_key",key);row.put("kind",kind);row.put("name",name);row.put("state",input);System.out.println(JSON.toJson(row));
    }
    static void export(String kind,String climate,boolean baby)throws Exception {
        var model=model(kind,climate,baby);String key=kind+"/"+climate+"/"+(baby?"baby":"adult");
        String base=kind.equals("sheep_wool")?"entity/sheep/sheep_wool":kind.equals("sheep")?"entity/sheep/sheep":"entity/"+kind+"/"+kind+"_"+climate;
        String texture="minecraft:"+base+(baby?"_baby":"");
        System.out.println(JSON.toJson(Map.of("type","rig","rig_key",key,"kind",kind,"variant",climate,"baby",baby,"texture",texture,"parts",VanillaPoseExport.rig(model))));
        sample(model,key,kind,climate,baby,"idle",0,0,0,0,0);
        sample(model,key,kind,climate,baby,"walk_look",1.6f,.55f,15,-12,8);
        sample(model,key,kind,climate,baby,"action",2.2f,.35f,-20,6,12);
    }
    public static void main(String[] args)throws Exception {
        for(String kind:List.of("cow","chicken"))for(String climate:List.of("temperate","warm","cold"))for(boolean baby:new boolean[]{false,true})export(kind,climate,baby);
        for(String kind:List.of("sheep","sheep_wool"))for(boolean baby:new boolean[]{false,true})export(kind,"normal",baby);
    }
}
