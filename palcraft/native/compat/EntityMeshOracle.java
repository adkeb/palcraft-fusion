// Data-only extraction from the player's current Java Minecraft model factories.
import java.util.*;
import org.joml.*;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Transformation;
import net.minecraft.core.Direction;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.object.chest.ChestModel;
import net.minecraft.client.model.monster.shulker.ShulkerModel;
import net.minecraft.client.renderer.blockentity.*;
import net.minecraft.client.renderer.blockentity.state.SignRenderState;

public final class EntityMeshOracle {
    static void matrix(Matrix4fc m) {
        float[] values = m.get(new float[16]);
        System.out.print("[");
        for (int i=0;i<16;i++){if(i>0)System.out.print(",");System.out.printf("%.9f",values[i]);}
        System.out.print("]");
    }
    static void export(String family,String variant,float input,ModelPart root,Transformation transform) {
        PoseStack poses = new PoseStack();
        if(transform!=null)poses.mulPose(transform);
        Set<String> parts = new HashSet<>();
        root.visit(poses, (pose,path,index,cube)->{
            if(parts.add(path)) {
                System.out.printf("{\"type\":\"part\",\"family\":\"%s\",\"variant\":\"%s\",\"input\":%.6f,\"part\":\"%s\",\"matrix\":",family,variant,input,path);
                matrix(pose.pose());System.out.println("}");
            }
            for (var face:cube.polygons) {
                var normal = new Vector3f(face.normal());pose.normal().transform(normal);normal.normalize();
                System.out.printf("{\"type\":\"face\",\"family\":\"%s\",\"variant\":\"%s\",\"input\":%.6f,\"part\":\"%s\",\"normal\":[%.9f,%.9f,%.9f],\"vertices\":[",family,variant,input,path,normal.x,normal.y,normal.z);
                int i=0;
                for (var v:face.vertices()) {
                    var p=new Vector3f(v.worldX(),v.worldY(),v.worldZ());pose.pose().transformPosition(p);
                    if(i++>0)System.out.print(",");
                    System.out.printf("[%.9f,%.9f,%.9f,%.9f,%.9f]",p.x,p.y,p.z,v.u(),v.v());
                }
                System.out.println("]}");
            }
        });
    }
    static void text(String family,String variant,SignRenderState.SignTransformations t) {
        System.out.printf("{\"type\":\"text\",\"family\":\"%s\",\"variant\":\"%s\",\"front\":",family,variant);
        matrix(t.frontText().getMatrix());System.out.print(",\"back\":");matrix(t.backText().getMatrix());System.out.println("}");
    }
    @SuppressWarnings("unchecked")
    public static void main(String[] args)throws Exception {
        Locale.setDefault(Locale.ROOT);
        float[] inputs={0,.125f,.25f,.5f,.75f,1};
        var constructor=Class.forName("net.minecraft.client.renderer.blockentity.ShulkerBoxRenderer$ShulkerBoxModel").getDeclaredConstructor(ModelPart.class);
        constructor.setAccessible(true);
        for(Direction d:Direction.values()) {
            var root=ShulkerModel.createBoxLayer().bakeRoot();
            var model=(Model<Float>)constructor.newInstance(root);
            for(float input:inputs) {
                model.setupAnim(input);
                export("shulker",d.getSerializedName(),input,root,ShulkerBoxRenderer.modelTransform(d));
            }
        }
        for(String kind:List.of("single","left","right")) {
            var layer=kind.equals("single")?ChestModel.createSingleBodyLayer():kind.equals("left")?ChestModel.createDoubleBodyLeftLayer():ChestModel.createDoubleBodyRightLayer();
            var root=layer.bakeRoot();var model=new ChestModel(root);
            for(float input:inputs) {
                float eased=1-(1-input)*(1-input)*(1-input);
                model.setupAnim(eased);export("chest",kind,input,root,null);
            }
        }
        for(Direction d:List.of(Direction.NORTH,Direction.SOUTH,Direction.EAST,Direction.WEST)) {
            var t=DecoratedPotRenderer.modelTransformation(d);
            export("pot_base",d.getSerializedName(),0,DecoratedPotRenderer.createBaseLayer().bakeRoot(),t);
            export("pot_sides",d.getSerializedName(),0,DecoratedPotRenderer.createSidesLayer().bakeRoot(),t);
        }
        for(int rotation=0;rotation<16;rotation++) {
            text("sign_text","free_"+rotation,StandingSignRenderer.TRANSFORMATIONS.freeTransformations(rotation));
            text("hanging_sign_text","free_"+rotation,HangingSignRenderer.TRANSFORMATIONS.freeTransformations(rotation));
        }
        for(Direction d:List.of(Direction.NORTH,Direction.SOUTH,Direction.EAST,Direction.WEST)) {
            text("sign_text","wall_"+d.getSerializedName(),StandingSignRenderer.TRANSFORMATIONS.wallTransformation(d));
            text("hanging_sign_text","wall_"+d.getSerializedName(),HangingSignRenderer.TRANSFORMATIONS.wallTransformation(d));
        }
    }
}
