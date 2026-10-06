// Exercises actual EntityRenderer.submit without constructing any MC game/GPU.
import java.lang.reflect.Field;
import java.util.*;
import com.google.gson.Gson;
import dev.rehan.passthrough.client.visual.VanillaEntityCapture;
import net.minecraft.client.model.monster.creeper.CreeperModel;
import net.minecraft.client.model.monster.dragon.EnderDragonModel;
import net.minecraft.client.model.geom.builders.CubeDeformation;
import net.minecraft.client.renderer.entity.*;
import net.minecraft.client.renderer.entity.state.*;
import net.minecraft.client.renderer.state.level.CameraRenderState;

public final class RendererCaptureOracle {
    private static Object allocate(Class<?> type)throws Exception {
        var f=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);
        return((sun.misc.Unsafe)f.get(null)).allocateInstance(type);
    }
    private static void set(Object object,String name,Object value)throws Exception {
        Class<?> type=object.getClass();while(type!=null){try{Field field=type.getDeclaredField(name);field.setAccessible(true);field.set(object,value);return;}catch(NoSuchFieldException e){type=type.getSuperclass();}}
        throw new NoSuchFieldException(name);
    }
    public static void main(String[] args)throws Exception {
        var gson=new Gson();var camera=new CameraRenderState();
        var creeper=(CreeperRenderer)allocate(CreeperRenderer.class);
        set(creeper,"model",new CreeperModel(CreeperModel.createBodyLayer(CubeDeformation.NONE).bakeRoot()));set(creeper,"layers",new ArrayList<>());
        var cs=new CreeperRenderState();cs.scale=1;cs.ageScale=1;cs.walkAnimationPos=1.2f;cs.walkAnimationSpeed=.6f;cs.bodyRot=35;cs.xRot=-10;cs.yRot=15;
        System.out.println(gson.toJson(new VanillaEntityCapture(60000).renderer(creeper,cs,camera)));
        var dragon=(EnderDragonRenderer)allocate(EnderDragonRenderer.class);
        set(dragon,"model",new EnderDragonModel(EnderDragonModel.createBodyLayer().bakeRoot()));
        var ds=new EnderDragonRenderState();ds.flapTime=.35f;ds.partialTicks=.5f;ds.distanceToEgg=20;
        System.out.println(gson.toJson(new VanillaEntityCapture(60000).renderer(dragon,ds,camera)));
    }
}
