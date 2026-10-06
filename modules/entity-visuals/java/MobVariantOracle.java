// Small data-only export of actual 26.3 climate/baby model factories and poses.
import java.util.*;
import com.google.gson.Gson;
import com.mojang.blaze3d.vertex.PoseStack;
import org.joml.Vector3f;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.model.animal.pig.*;
import net.minecraft.client.model.monster.zombie.*;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.builders.*;
import net.minecraft.client.renderer.entity.state.*;

public final class MobVariantOracle {
    static final Gson JSON=new Gson();
    static Model<?> make(String kind,String variant,boolean baby) {
        if(kind.equals("pig")) {
            if(baby)return new BabyPigModel(BabyPigModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
            if(variant.equals("cold"))return new ColdPigModel(ColdPigModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
            return new PigModel(PigModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
        }
        if(baby)return new BabyZombieModel<>(BabyZombieModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
        return new ZombieModel<>(LayerDefinition.create(HumanoidModel.createMesh(CubeDeformation.NONE,0),64,64).bakeRoot());
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    static void sample(Model model,String key,String kind,boolean baby,String name,float walk,float speed,float yaw,float pitch,float attack,float age)throws Exception {
        LivingEntityRenderState s=kind.equals("pig")?new PigRenderState():new ZombieRenderState();
        s.isBaby=baby;s.ageScale=baby?.5f:1;s.scale=1;s.walkAnimationPos=walk;s.walkAnimationSpeed=speed;s.yRot=yaw;s.xRot=pitch;s.ageInTicks=age;
        if(s instanceof ZombieRenderState z){z.swingAnimation=attack;z.isAggressive=attack>0;}
        model.setupAnim(s);Map<String,Object> poses=new LinkedHashMap<>();MobRigOracle.poses(model.root(),"/",poses);
        List<Object> faces=new ArrayList<>();model.root().visit(new PoseStack(),(p,path,index,cube)->{
            for(var face:cube.polygons){
                List<Object> vertices=new ArrayList<>();var n=new Vector3f(face.normal());p.normal().transform(n);n.normalize();
                for(var v:face.vertices()){var q=new Vector3f(v.worldX(),v.worldY(),v.worldZ());p.pose().transformPosition(q);vertices.add(List.of(q.x,q.y,q.z,n.x,n.y,n.z,v.u(),v.v()));}
                faces.add(Map.of("part",path.isEmpty()?"/":path,"vertices",vertices));
            }
        });
        var state=Map.ofEntries(Map.entry("baby",baby),Map.entry("variant",key.split("/")[1]),Map.entry("scale",1),Map.entry("age_scale",s.ageScale),
          Map.entry("walk_pos",walk),Map.entry("walk_speed",speed),Map.entry("head_yaw",yaw),Map.entry("head_pitch",pitch),Map.entry("attack_time",attack),Map.entry("age",age),Map.entry("aggressive",attack>0));
        System.out.println(JSON.toJson(Map.of("type","sample","rig_key",key,"kind",kind,"name",name,"state",state,"poses",poses,"faces",faces)));
    }
    static void export(String kind,String variant,boolean baby)throws Exception {
        var model=make(kind,variant,baby);String key=kind+"/"+variant+"/"+(baby?"baby":"adult");
        List<Object> parts=new ArrayList<>();MobRigOracle.rig(model.root(),"/",null,parts);
        String skin=kind.equals("pig")?"minecraft:entity/pig/pig_"+variant+(baby?"_baby":""):"minecraft:entity/zombie/zombie"+(baby?"_baby":"");
        System.out.println(JSON.toJson(Map.of("type","rig","rig_key",key,"kind",kind,"variant",variant,"baby",baby,"texture",skin,"parts",parts)));
        sample(model,key,kind,baby,"idle",0,0,0,0,0,0);
        sample(model,key,kind,baby,"walk_look",1.7f,.6f,25,-10,0,9);
        sample(model,key,kind,baby,"attack",2.1f,.4f,-15,5,.35f,13);
    }
    public static void main(String[] args)throws Exception {
        MobRigOracle.children=ModelPart.class.getDeclaredField("children");MobRigOracle.children.setAccessible(true);
        MobRigOracle.cubes=ModelPart.class.getDeclaredField("cubes");MobRigOracle.cubes.setAccessible(true);
        for(String climate:List.of("temperate","warm","cold"))for(boolean baby:new boolean[]{false,true})export("pig",climate,baby);
        for(boolean baby:new boolean[]{false,true})export("zombie","normal",baby);
    }
}
