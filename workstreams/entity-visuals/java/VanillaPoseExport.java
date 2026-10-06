// Reusable MC model/renderstate -> rig and compact local-pose export.
// Runs on the calling thread; does not create a game, modify an entity or draw.
import java.util.*;
import java.lang.reflect.Field;
import com.mojang.blaze3d.vertex.PoseStack;
import org.joml.Vector3f;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.entity.state.EntityRenderState;

public final class VanillaPoseExport {
    private static final Field CHILDREN,CUBES;
    static {
        try {CHILDREN=ModelPart.class.getDeclaredField("children");CHILDREN.setAccessible(true);CUBES=ModelPart.class.getDeclaredField("cubes");CUBES.setAccessible(true);}
        catch(ReflectiveOperationException e){throw new ExceptionInInitializerError(e);}
    }
    private static List<Float> pose(ModelPart p){return List.of(p.x/16,p.y/16,p.z/16,p.xRot,p.yRot,p.zRot,p.xScale,p.yScale,p.zScale);}
    @SuppressWarnings("unchecked")
    private static Map<String,ModelPart> children(ModelPart p)throws IllegalAccessException{return(Map<String,ModelPart>)CHILDREN.get(p);}
    @SuppressWarnings("unchecked")
    private static void rig(ModelPart p,String path,String parent,List<Object> parts)throws IllegalAccessException {
        List<Object> faces=new ArrayList<>();
        for(var cube:(List<ModelPart.Cube>)CUBES.get(p))for(var face:cube.polygons){
            List<Object> vertices=new ArrayList<>();for(var v:face.vertices())vertices.add(List.of(v.worldX(),v.worldY(),v.worldZ(),v.u(),v.v()));
            var n=face.normal();faces.add(Map.of("vertices",vertices,"normal",List.of(n.x(),n.y(),n.z())));
        }
        var row=new LinkedHashMap<String,Object>();row.put("id",path);row.put("parent",parent);row.put("rest",pose(p));row.put("faces",faces);row.put("visible",p.visible);row.put("skip_draw",p.skipDraw);parts.add(row);
        var children=children(p);for(String name:new TreeSet<>(children.keySet()))rig(children.get(name),path.equals("/")?"/"+name:path+"/"+name,path,parts);
    }
    public static List<Object> rig(Model<?> model)throws IllegalAccessException {List<Object> parts=new ArrayList<>();rig(model.root(),"/",null,parts);return parts;}
    private static void poses(ModelPart p,String path,Map<String,Object> out)throws IllegalAccessException {
        out.put(path,pose(p));var children=children(p);for(String name:new TreeSet<>(children.keySet()))poses(children.get(name),path.equals("/")?"/"+name:path+"/"+name,out);
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    public static Map<String,Object> sample(Model model,EntityRenderState state)throws IllegalAccessException {
        model.setupAnim(state);var parts=new LinkedHashMap<String,Object>();poses(model.root(),"/",parts);
        List<Object> faces=new ArrayList<>();model.root().visit(new PoseStack(),(p,path,index,cube)->{
            for(var face:cube.polygons){
                var n=new Vector3f(face.normal());p.normal().transform(n);n.normalize();List<Object> vertices=new ArrayList<>();
                for(var v:face.vertices()){var q=new Vector3f(v.worldX(),v.worldY(),v.worldZ());p.pose().transformPosition(q);vertices.add(List.of(q.x,q.y,q.z,n.x,n.y,n.z,v.u(),v.v()));}
                faces.add(Map.of("part",path.isEmpty()?"/":path,"vertices",vertices));
            }
        });
        return Map.of("poses",parts,"faces",faces);
    }
}
