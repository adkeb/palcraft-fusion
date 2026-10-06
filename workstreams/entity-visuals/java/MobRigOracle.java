// Data-only rig/pose extraction from the user's installed Minecraft version.
import java.util.*;
import java.lang.reflect.Field;
import com.google.gson.*;
import com.mojang.blaze3d.vertex.PoseStack;
import org.joml.Vector3f;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.model.animal.pig.PigModel;
import net.minecraft.client.model.monster.zombie.ZombieModel;
import net.minecraft.client.model.monster.creeper.CreeperModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.builders.*;
import net.minecraft.client.renderer.entity.state.*;

public final class MobRigOracle {
    static final Gson JSON=new Gson();
    static Field children,cubes;
    static List<Float> pose(ModelPart p){return List.of(p.x/16,p.y/16,p.z/16,p.xRot,p.yRot,p.zRot,p.xScale,p.yScale,p.zScale);}
    @SuppressWarnings("unchecked")
    static void rig(ModelPart p,String path,String parent,List<Object> result)throws Exception {
        List<Object> faces=new ArrayList<>();
        for(var cube:(List<ModelPart.Cube>)cubes.get(p))for(var polygon:cube.polygons){
            List<Object> vertices=new ArrayList<>();
            for(var v:polygon.vertices())vertices.add(List.of(v.worldX(),v.worldY(),v.worldZ(),v.u(),v.v()));
            var n=polygon.normal();faces.add(Map.of("vertices",vertices,"normal",List.of(n.x(),n.y(),n.z())));
        }
        Map<String,Object> row=new LinkedHashMap<>();row.put("id",path);row.put("parent",parent);row.put("rest",pose(p));
        row.put("faces",faces);row.put("visible",p.visible);row.put("skip_draw",p.skipDraw);result.add(row);
        var map=(Map<String,ModelPart>)children.get(p);
        for(String name:new TreeSet<>(map.keySet()))rig(map.get(name),path.equals("/")?"/"+name:path+"/"+name,path,result);
    }
    @SuppressWarnings("unchecked")
    static void poses(ModelPart p,String path,Map<String,Object> result)throws Exception {
        result.put(path,pose(p));var map=(Map<String,ModelPart>)children.get(p);
        for(String name:new TreeSet<>(map.keySet()))poses(map.get(name),path.equals("/")?"/"+name:path+"/"+name,result);
    }
    static Model<?> model(String kind) {
        return switch(kind) {
            case "pig" -> new PigModel(PigModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
            case "zombie" -> new ZombieModel<>(LayerDefinition.create(HumanoidModel.createMesh(CubeDeformation.NONE,0),64,64).bakeRoot());
            default -> new CreeperModel(CreeperModel.createBodyLayer(CubeDeformation.NONE).bakeRoot());
        };
    }
    static LivingEntityRenderState state(String kind){return switch(kind){case"pig"->new PigRenderState();case"zombie"->new ZombieRenderState();default->new CreeperRenderState();};}
    @SuppressWarnings({"unchecked","rawtypes"})
    static void sample(String kind,Model model,String name,float walkPos,float speed,float headYaw,float headPitch,float attack,float age,float death,float swell,boolean hurt,boolean aggressive)throws Exception {
        var s=state(kind);s.walkAnimationPos=walkPos;s.walkAnimationSpeed=speed;s.yRot=headYaw;s.xRot=headPitch;s.ageInTicks=age;s.deathTime=death;s.hasRedOverlay=hurt;
        if(s instanceof ZombieRenderState z){z.swingAnimation=attack;z.isAggressive=aggressive;}
        if(s instanceof CreeperRenderState c)c.swelling=swell;
        model.setupAnim(s);
        Map<String,Object> params=Map.ofEntries(Map.entry("walk_pos",walkPos),Map.entry("walk_speed",speed),Map.entry("head_yaw",headYaw),Map.entry("head_pitch",headPitch),Map.entry("attack_time",attack),Map.entry("age",age),Map.entry("death_time",death),Map.entry("swelling",swell),Map.entry("hurt",hurt),Map.entry("aggressive",aggressive));
        Map<String,Object> partPoses=new LinkedHashMap<>();poses(model.root(),"/",partPoses);
        List<Object> vertices=new ArrayList<>();
        model.root().visit(new PoseStack(),(p,path,index,cube)->{
            for(var face:cube.polygons){
                List<Object> data=new ArrayList<>();var n=new Vector3f(face.normal());p.normal().transform(n);n.normalize();
                for(var v:face.vertices()){var q=new Vector3f(v.worldX(),v.worldY(),v.worldZ());p.pose().transformPosition(q);data.add(List.of(q.x,q.y,q.z,n.x,n.y,n.z,v.u(),v.v()));}
                vertices.add(Map.of("part",path.isEmpty()?"/":path,"vertices",data));
            }
        });
        System.out.println(JSON.toJson(Map.of("type","sample","kind",kind,"name",name,"state",params,"poses",partPoses,"faces",vertices)));
    }
    public static void main(String[] args)throws Exception {
        children=ModelPart.class.getDeclaredField("children");children.setAccessible(true);
        cubes=ModelPart.class.getDeclaredField("cubes");cubes.setAccessible(true);
        for(String kind:List.of("pig","zombie","creeper")){
            var m=model(kind);List<Object> parts=new ArrayList<>();rig(m.root(),"/",null,parts);
            String texture=switch(kind){case"pig"->"minecraft:entity/pig/pig_temperate";case"zombie"->"minecraft:entity/zombie/zombie";default->"minecraft:entity/creeper/creeper";};
            System.out.println(JSON.toJson(Map.of("type","rig","kind",kind,"texture",texture,"parts",parts,"source","Minecraft26.3 model factory")));
            sample(kind,m,"idle",0,0,0,0,0,0,0,0,false,false);
            sample(kind,m,"walk",1.2f,.65f,0,0,0,5,0,0,false,false);
            sample(kind,m,"walk_look",3.1f,.8f,35,-15,0,11,0,0,false,false);
            sample(kind,m,"attack_early",.7f,.3f,10,5,.2f,7,0,0,false,true);
            sample(kind,m,"attack_mid",2,.4f,-20,10,.5f,13,0,.5f,false,true);
            sample(kind,m,"hurt",1,.25f,0,0,0,9,0,0,true,false);
            sample(kind,m,"death",0,0,0,0,0,10,10,0,true,false);
            sample(kind,m,"fuse",.5f,.2f,0,0,0,15,0,.8f,false,false);
        }
    }
}
