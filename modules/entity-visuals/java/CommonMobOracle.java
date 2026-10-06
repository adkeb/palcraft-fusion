import java.util.*;
import com.google.gson.Gson;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.monster.skeleton.SkeletonModel;
import net.minecraft.client.model.monster.spider.SpiderModel;
import net.minecraft.client.model.monster.enderman.EndermanModel;
import net.minecraft.client.model.animal.cow.CowModel;
import net.minecraft.client.model.animal.sheep.*;
import net.minecraft.client.model.animal.chicken.AdultChickenModel;
import net.minecraft.client.renderer.entity.state.*;

public final class CommonMobOracle {
    private static final Gson JSON=new Gson();
    static Model<?> model(String kind){return switch(kind){
        case"skeleton"->new SkeletonModel<>(SkeletonModel.createBodyLayer().bakeRoot());
        case"spider"->new SpiderModel(SpiderModel.createSpiderBodyLayer().bakeRoot());
        case"cow"->new CowModel(CowModel.createBodyLayer().bakeRoot());
        case"sheep"->new SheepModel(SheepModel.createBodyLayer().bakeRoot());
        case"sheep_wool"->new SheepFurModel(SheepFurModel.createFurLayer().bakeRoot());
        case"chicken"->new AdultChickenModel(AdultChickenModel.createBodyLayer().bakeRoot());
        default->new EndermanModel<>(EndermanModel.createBodyLayer().bakeRoot());
    };}
    static LivingEntityRenderState state(String kind){return switch(kind){
        case"skeleton"->new SkeletonRenderState();case"cow"->new CowRenderState();
        case"sheep","sheep_wool"->new SheepRenderState();case"chicken"->new ChickenRenderState();
        case"enderman"->new EndermanRenderState();default->new LivingEntityRenderState();
    };}
    static String texture(String kind){return switch(kind){
        case"cow"->"minecraft:entity/cow/cow_temperate";case"sheep_wool"->"minecraft:entity/sheep/sheep_wool";
        case"chicken"->"minecraft:entity/chicken/chicken_temperate";default->"minecraft:entity/"+kind+"/"+kind;
    };}
    static void sample(Model<?> model,String kind,String name,float walk,float speed,float headYaw,float headPitch,float attack,float age)throws Exception {
        var s=state(kind);s.scale=1;s.ageScale=1;s.walkAnimationPos=walk;s.walkAnimationSpeed=speed;s.yRot=headYaw;s.xRot=headPitch;s.ageInTicks=age;
        Map<String,Object> input=new LinkedHashMap<>();input.put("walk_pos",walk);input.put("walk_speed",speed);input.put("head_yaw",headYaw);input.put("head_pitch",headPitch);input.put("attack_time",attack);input.put("age",age);
        if(s instanceof SkeletonRenderState a){a.swingAnimation=attack;a.isAggressive=attack>0;input.put("aggressive",a.isAggressive);input.put("holding_bow",false);}
        if(s instanceof SheepRenderState a){a.headEatPositionScale=name.equals("action")?.7f:0;a.headEatAngleScale=name.equals("action")?.6f:(float)Math.toRadians(headPitch);input.put("head_eat_position",a.headEatPositionScale);input.put("head_eat_angle",a.headEatAngleScale);}
        if(s instanceof ChickenRenderState a){a.flap=age*.35f;a.flapSpeed=name.equals("action")?.8f:.2f;input.put("flap",a.flap);input.put("flap_speed",a.flapSpeed);}
        if(s instanceof EndermanRenderState a){a.isCreepy=name.equals("action");input.put("creepy",a.isCreepy);input.put("carrying",false);}
        Map<String,Object> output=new LinkedHashMap<>(VanillaPoseExport.sample(model,s));output.put("type","sample");output.put("kind",kind);output.put("name",name);output.put("state",input);System.out.println(JSON.toJson(output));
    }
    public static void main(String[] args)throws Exception {
        for(String kind:List.of("skeleton","spider","cow","sheep","sheep_wool","chicken","enderman")){
            var model=model(kind);System.out.println(JSON.toJson(Map.of("type","rig","kind",kind,"texture",texture(kind),"parts",VanillaPoseExport.rig(model))));
            sample(model,kind,"idle",0,0,0,0,0,0);
            sample(model,kind,"walk_look",1.3f,.6f,20,-10,0,9);
            sample(model,kind,"action",2.4f,.4f,-15,5,.4f,13);
        }
    }
}
