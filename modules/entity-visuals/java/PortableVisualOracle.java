// Data-only reference: actual projectile model factories and generated-item edges.
import java.util.*;
import java.lang.reflect.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import com.google.gson.Gson;
import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.math.Axis;
import org.joml.Vector3f;
import net.minecraft.resources.Identifier;
import net.minecraft.client.model.Model;
import net.minecraft.client.model.object.projectile.*;
import net.minecraft.client.renderer.entity.state.ArrowRenderState;
import net.minecraft.client.renderer.texture.SpriteContents;
import net.minecraft.client.resources.metadata.animation.FrameSize;
import it.unimi.dsi.fastutil.ints.IntList;

public final class PortableVisualOracle {
    static final Gson JSON=new Gson();
    // No NativeImage/GPU constructor is executed. Virtual SpriteContents getters
    // provide the CPU alpha mask that the actual ItemModelGenerator inspects.
    public static final class MaskSprite extends SpriteContents {
        int w,h;int[] pixels;
        private MaskSprite(){super(Identifier.withDefaultNamespace("oracle"),new FrameSize(1,1),(NativeImage)null);}
        @Override public int width(){return w;}
        @Override public int height(){return h;}
        @Override public IntList getUniqueFrames(){return IntList.of(0);}
        @Override public boolean isTransparent(int frame,int x,int y){return((pixels[y*w+x]>>>24)&255)==0;}
    }
    @SuppressWarnings("restriction")
    static MaskSprite sprite(BufferedImage image)throws Exception {
        Field field=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");field.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)field.get(null);var s=(MaskSprite)unsafe.allocateInstance(MaskSprite.class);
        s.w=image.getWidth();s.h=image.getHeight();s.pixels=image.getRGB(0,0,s.w,s.h,null,0,s.w);return s;
    }
    static void itemEdges(String item)throws Exception {
        var stream=PortableVisualOracle.class.getResourceAsStream("/assets/minecraft/textures/item/"+item+".png");
        var image=ImageIO.read(stream);stream.close();var contents=sprite(image);
        Class<?> generator=Class.forName("net.minecraft.client.resources.model.cuboid.ItemModelGenerator");
        Method get=generator.getDeclaredMethod("getSideFaces",SpriteContents.class);get.setAccessible(true);
        var edges=(Collection<?>)get.invoke(null,contents);List<Object> rows=new ArrayList<>();
        for(Object edge:edges){var c=edge.getClass();var facing=c.getDeclaredMethod("facing");var x=c.getDeclaredMethod("x");var y=c.getDeclaredMethod("y");facing.setAccessible(true);x.setAccessible(true);y.setAccessible(true);
            rows.add(Map.of("direction",facing.invoke(edge).toString(),"x",x.invoke(edge),"y",y.invoke(edge)));}
        rows.sort(Comparator.comparing(Object::toString));
        System.out.println(JSON.toJson(Map.of("type","item_edges","item","minecraft:"+item,"width",contents.w,"height",contents.h,"edges",rows)));
    }
    static void posed(Model<?> model,String kind,float yaw,float pitch,float shake)throws Exception {
        if(model instanceof ArrowModel arrow){var state=new ArrowRenderState();state.shake=shake;arrow.setupAnim(state);}
        PoseStack pose=new PoseStack();pose.rotateDegrees(Axis.YP,yaw-90);pose.rotateDegrees(Axis.ZP,pitch+(kind.equals("trident")?90:0));
        List<Object> faces=new ArrayList<>();model.root().visit(pose,(p,path,index,cube)->{for(var polygon:cube.polygons){
            var n=new Vector3f(polygon.normal());p.normal().transform(n);n.normalize();List<Object> vertices=new ArrayList<>();
            for(var v:polygon.vertices()){var q=new Vector3f(v.worldX(),v.worldY(),v.worldZ());p.pose().transformPosition(q);vertices.add(List.of(q.x,q.y,q.z,n.x,n.y,n.z,v.u(),v.v()));}
            faces.add(Map.of("part",path.isEmpty()?"/":path,"vertices",vertices));
        }});
        System.out.println(JSON.toJson(Map.of("type","projectile_pose","kind",kind,"yaw",yaw,"pitch",pitch,"shake",shake,"faces",faces)));
    }
    public static void main(String[]args)throws Exception {
        var arrow=new ArrowModel(ArrowModel.createBodyLayer().bakeRoot());var trident=new TridentModel(TridentModel.createLayer().bakeRoot());
        System.out.println(JSON.toJson(Map.of("type","rig","kind","arrow","texture","minecraft:entity/projectiles/arrow","parts",VanillaPoseExport.rig(arrow))));
        String tridentTexture=TridentModel.TEXTURE.toString().replace(":textures/",":").replace(".png","");
        System.out.println(JSON.toJson(Map.of("type","rig","kind","trident","texture",tridentTexture,"parts",VanillaPoseExport.rig(trident))));
        posed(arrow,"arrow",0,0,0);posed(arrow,"arrow",35,-20,3);posed(trident,"trident",0,0,0);posed(trident,"trident",-60,25,0);
        itemEdges("iron_pickaxe");itemEdges("coal");itemEdges("arrow");
    }
}
