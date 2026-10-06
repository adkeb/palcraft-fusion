// One data-only check of the actual MC VertexConsumer default packed UV calls.
import java.lang.reflect.*;
import java.util.*;
import com.mojang.blaze3d.vertex.VertexConsumer;

public final class CaptureUvOracle {
    @SuppressWarnings("unchecked")
    public static void main(String[] args)throws Exception {
        Class<?> type=Class.forName("dev.rehan.passthrough.client.visual.VanillaEntityCapture$Recorder");
        Constructor<?> constructor=type.getDeclaredConstructor();constructor.setAccessible(true);
        VertexConsumer recorder=(VertexConsumer)constructor.newInstance();
        recorder.addVertex(1,2,3).setColor(0x80402010).setUv(.25f,.75f)
            .setOverlay((10<<16)|11).setLight((240<<16)|160).setNormal(0,1,0);
        Method finish=type.getDeclaredMethod("finish");finish.setAccessible(true);
        List<float[]> result=(List<float[]>)finish.invoke(recorder);float[] v=result.getFirst();
        if(v.length!=16||v[12]!=11||v[13]!=10||v[14]!=160||v[15]!=240)throw new AssertionError("Original UV1/UV2 were lost or changed: "+Arrays.toString(v));
        if(v[0]!=1||v[1]!=2||v[2]!=3||v[6]!=.25f||v[7]!=.75f||v[11]!=128/255f)throw new AssertionError("Existing vertex prefix changed");
        System.out.println("{\"status\":\"passed\",\"actual_MC_VertexConsumer_defaults\":true,\"UV1\":[11,10],\"UV2\":[160,240],\"vertex_fields\":16,\"runtime_graphics_verified\":false}");
    }
}
