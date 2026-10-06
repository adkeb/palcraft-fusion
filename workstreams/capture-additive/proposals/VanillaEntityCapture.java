package dev.rehan.passthrough.client.visual;
// Generic 26.3 renderer -> collector -> original vertex stream. Client-thread API.
// No kind whitelist, new service, authority, physics, AI or damage protocol.
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;
import com.mojang.blaze3d.vertex.*;
import net.minecraft.client.Minecraft;
import net.minecraft.client.model.Model;
import net.minecraft.client.renderer.*;
import net.minecraft.client.renderer.entity.EntityRenderer;
import net.minecraft.client.renderer.entity.state.EntityRenderState;
import net.minecraft.client.renderer.rendertype.RenderType;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.client.renderer.texture.UvMapping;
import net.minecraft.resources.Identifier;
import net.minecraft.world.entity.Entity;

public final class VanillaEntityCapture implements InvocationHandler {
    private final List<Map<String,Object>> batches=new ArrayList<>();
    private final Map<String,Integer> unsupported=new LinkedHashMap<>();
    private final int maxVertices;
    private int vertices,order;
    private final SubmitNodeCollector collector;
    public VanillaEntityCapture(int maxVertices){
        this.maxVertices=maxVertices;
        collector=(SubmitNodeCollector)Proxy.newProxyInstance(SubmitNodeCollector.class.getClassLoader(),new Class<?>[]{SubmitNodeCollector.class},this);
    }
    @Override public Object invoke(Object proxy,Method method,Object[] a)throws Throwable {
        String name=method.getName();
        if(method.getDeclaringClass()==Object.class)return switch(name){case"toString"->"VanillaEntityCaptureCollector";case"hashCode"->System.identityHashCode(proxy);case"equals"->proxy==a[0];default->null;};
        if(name.equals("order")){order=(Integer)a[0];return collector;}
        if(name.equals("submitModel")&&a.length==9&&a[3]instanceof RenderType){model(a);return null;}
        if(name.equals("submitCustomGeometry")){
            var type=(RenderType)a[1];var recorder=new Recorder();
            ((SubmitNodeCollector.CustomGeometryRenderer)a[2]).render(((PoseStack)a[0]).last(),recorder);
            record(type,recorder.finish(),"custom_geometry",type.primitiveTopology().toString(),0,0);return null;
        }
        if(method.isDefault())return InvocationHandler.invokeDefault(proxy,method,a);
        // Text/shadow/leash/item/block submissions are not silently declared
        // visible. Their exact missing path remains in this frame's diagnostics.
        unsupported.merge(name,1,Integer::sum);return null;
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    private void model(Object[] a)throws ReflectiveOperationException {
        Model model=(Model)a[0];Object state=a[1];PoseStack pose=(PoseStack)a[2];RenderType type=(RenderType)a[3];
        int light=(Integer)a[4],overlay=(Integer)a[5],color=(Integer)a[6];
        UvMapping mapping=(UvMapping)a[7];var recorder=new Recorder();VertexConsumer sink=mapping==null?recorder:mapping.wrap(recorder);
        model.setupAnim(state);model.renderToBuffer(pose,sink,light,overlay,color);
        record(type,recorder.finish(),model.getClass().getName(),"QUADS",light,overlay);
    }
    private static Object field(Object value,String name)throws ReflectiveOperationException {
        Class<?> type=value.getClass();while(type!=null){try{Field f=type.getDeclaredField(name);f.setAccessible(true);return f.get(value);}catch(NoSuchFieldException e){type=type.getSuperclass();}}
        throw new NoSuchFieldException(name);
    }
    private static Map<String,String> textures(RenderType type)throws ReflectiveOperationException {
        Object state=field(type,"state");var result=new LinkedHashMap<String,String>();
        for(var e:((Map<?,?>)field(state,"textures")).entrySet()){
            Object location=field(e.getValue(),"location");result.put(e.getKey().toString(),location.toString());
        }
        return result;
    }
    private void record(RenderType type,List<float[]> data,String source,String topology,int light,int overlay)throws ReflectiveOperationException {
        if(data.isEmpty())return;
        if(vertices+data.size()>maxVertices)throw new IllegalStateException("Actual entity vertex budget exceeded: "+maxVertices);
        vertices+=data.size();var batch=new LinkedHashMap<String,Object>();
        batch.put("source",source);batch.put("layer_order",order);batch.put("render_type_name",field(type,"name"));
        batch.put("textures",textures(type));batch.put("has_blending",type.hasBlending());batch.put("primitive",topology);
        batch.put("capture_blend",CaptureBlendMetadata.read(type.pipeline()));
        batch.put("light",light);batch.put("overlay",overlay);batch.put("vertices",data);batches.add(batch);
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    public Map<String,Object> renderer(EntityRenderer renderer,EntityRenderState state,CameraRenderState camera) {
        PoseStack pose=new PoseStack();var offset=renderer.getRenderOffset(state);
        pose.translate(offset.x,offset.y,offset.z);
        renderer.submit(state,pose,collector,camera);
        return Map.of("schema",1,"source","actual_entity_renderer_submit","capture_class",getClass().getName(),"renderer",renderer.getClass().getName(),
            "space","minecraft_entity_origin_world_orientation","native_actor_yaw",0,
            "vertex_layout",List.of("x","y","z","nx","ny","nz","u","v","r","g","b","a"),
            "batches",batches,"vertices",vertices,"unsupported_submissions",unsupported);
    }
    @SuppressWarnings({"rawtypes","unchecked"})
    public static Map<String,Object> entity(Entity entity,float partialTicks,CameraRenderState camera,int maxVertices) {
        // Call within the existing MC client frame/tick hook on its own thread.
        var dispatcher=Minecraft.getInstance().getEntityRenderDispatcher();EntityRenderer renderer=dispatcher.getRenderer(entity);
        EntityRenderState state=renderer.createRenderState(entity,partialTicks);
        Map<String,Object> frame=new LinkedHashMap<>(new VanillaEntityCapture(maxVertices).renderer(renderer,state,camera));
        frame.put("mc_uuid",entity.getUUID().toString());frame.put("id","mc:"+entity.getUUID());
        frame.put("kind",net.minecraft.core.registries.BuiltInRegistries.ENTITY_TYPE.getKey(entity.getType()).toString());
        frame.put("dimension",entity.level().dimension().identifier().toString());
        frame.put("x",state.x);frame.put("y",state.y);frame.put("z",state.z);return frame;
    }
    public static boolean exportTexture(Identifier texture,Path root)throws IOException {
        // Static resources (entity PNGs) are exported from existing resource packs.
        // Runtime skins and generated atlases require the texture owner adapter.
        var resource=Minecraft.getInstance().getResourceManager().getResource(texture);
        if(resource.isEmpty())return false;
        Path target=root.resolve(texture.getNamespace()).resolve(texture.getPath()).normalize();
        if(!target.startsWith(root.normalize()))throw new IOException("Texture path outside asset root");
        Files.createDirectories(target.getParent());try(InputStream in=resource.get().open()){Files.copy(in,target,StandardCopyOption.REPLACE_EXISTING);}return true;
    }
    private static final class Recorder implements VertexConsumer {
        private final List<float[]> data=new ArrayList<>();private float[] current;
        private void flush(){if(current!=null){data.add(current);current=null;}}
        List<float[]> finish(){flush();return data;}
        @Override public VertexConsumer addVertex(float x,float y,float z){flush();current=new float[]{x,y,z,0,1,0,0,0,1,1,1,1};return this;}
        @Override public VertexConsumer setColor(int r,int g,int b,int a){current[8]=r/255f;current[9]=g/255f;current[10]=b/255f;current[11]=a/255f;return this;}
        @Override public VertexConsumer setColor(int color){return setColor((color>>>16)&255,(color>>>8)&255,color&255,(color>>>24)&255);}
        @Override public VertexConsumer setUv(float u,float v){current[6]=u;current[7]=v;return this;}
        @Override public VertexConsumer setUv1(int u,int v){return this;}
        @Override public VertexConsumer setUv2(int u,int v){return this;}
        @Override public VertexConsumer setUv3(float u,float v){return this;}
        @Override public VertexConsumer setNormal(float x,float y,float z){current[3]=x;current[4]=y;current[5]=z;return this;}
        @Override public VertexConsumer setLineWidth(float width){return this;}
    }
}
