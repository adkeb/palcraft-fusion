package dev.rehan.passthrough.client;

import com.mojang.blaze3d.platform.Lighting;
import com.mojang.blaze3d.platform.NativeImage;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import dev.rehan.passthrough.client.mixin.EntityOverlayTextureAccessor;
import dev.rehan.passthrough.client.signtext.SignGlyphRaster;
import dev.rehan.passthrough.client.signtext.SignTextExporter;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import javax.imageio.ImageIO;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.DynamicGpuData;
import net.minecraft.client.renderer.rendertype.RenderType;
import org.joml.Vector3fc;

/** Original shader inputs paired with one real entity-capture render frame.
 * Uses the existing sign GPU copy utility and render callback, not another
 * service, transport, reader, thread or world authority. */
public final class EntityShaderInputCapture {
    private static final Map<Lighting.Entry,float[][]> lights=new EnumMap<>(Lighting.Entry.class);
    private static Lighting.Entry activeLighting;
    private static long lightingRevision;
    private static final Map<GpuBufferSlice,Map<String,Object>> transforms=new HashMap<>();
    private static final Map<RenderType,Map<String,Object>> renderTypeTransforms=new IdentityHashMap<>();
    private static long transformFrame;
    public record Image(String resource,String sha256,byte[] png,int width,int height,String source,long revision) {}
    public record Snapshot(Image overlay,Image lightmap,Map<String,Object> inputs,long epoch,long capturedMs) {}
    private EntityShaderInputCapture() {}

    public static void resetTransforms(){transforms.clear();renderTypeTransforms.clear();transformFrame++;}
    /** Observe the actual CPU values used for this returned UBO slice. No GPU
     * buffer mapping or invented WHITE/default colour is performed. */
    public static void transformWritten(GpuBufferSlice slice,DynamicGpuData.Transform transform) {
        if(transforms.size()>=4096)return;
        var color=transform.colorModulator();var offset=transform.modelOffset();
        transforms.put(slice,Map.of("available",true,"source","DynamicGpuData.Transform -> returned UBO slice","frame",transformFrame,
            "ColorModulator",new float[]{color.x(),color.y(),color.z(),color.w()},
            "ModelOffset",new float[]{offset.x(),offset.y(),offset.z()},"TextureMat",transform.textureMatrix().get(new float[16])));
    }
    public static void renderTypePrepared(RenderType type,GpuBufferSlice slice) {
        Map<String,Object> original=transforms.get(slice);
        if(original!=null&&renderTypeTransforms.size()<4096) {
            Map<String,Object> scoped=new LinkedHashMap<>(original);scoped.put("cardinal_lighting",lighting());renderTypeTransforms.put(type,scoped);
        }
    }
    public static Map<String,Object> renderTypeInputs(RenderType type) {
        return renderTypeTransforms.getOrDefault(type,Map.of("available",false,
            "error","original_RenderType_DynamicTransforms_not_observed_this_frame"));
    }

    /** Exact values about to be written by vanilla into its Lighting UBO. */
    public static void lightingUpdated(Lighting.Entry entry,Vector3fc first,Vector3fc second) {
        lights.put(entry,new float[][]{{first.x(),first.y(),first.z()},{second.x(),second.y(),second.z()}});
        lightingRevision++;
    }
    public static void lightingSelected(Lighting.Entry entry){activeLighting=entry;}
    private static Map<String,Object> lighting() {
        float[][] original=activeLighting==null?null:lights.get(activeLighting);
        if(original==null)return Map.of("available",false,"error","original_selected_Lighting_UBO_inputs_not_observed");
        return Map.of("available",true,"source","Lighting.updateBuffer + setupFor","entry",activeLighting.name(),"revision",lightingRevision,
            "space","minecraft_original_normal_basis","Light0_Direction",original[0].clone(),"Light1_Direction",original[1].clone());
    }
    private static Image png(BufferedImage pixels,String kind,String source,long revision)throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        if(!ImageIO.write(pixels,"png",bytes))throw new IOException("shader_png_encoder_unavailable");
        byte[] data=bytes.toByteArray();if(data.length>8*1024*1024)throw new IOException("shader_png_byte_budget_exceeded");
        try {
            String sha=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
            // Immutable resource IDs avoid resolving a previous frame's lightmap
            // when two retained entities used different runtime texels.
            return new Image("palcraft:runtime/entity/"+kind+"/"+sha+".png",sha,data,pixels.getWidth(),pixels.getHeight(),source,revision);
        }catch(java.security.NoSuchAlgorithmException failure){throw new IllegalStateException(failure);}
    }
    private static Image overlay(Minecraft mc,long revision)throws IOException {
        NativeImage original=((EntityOverlayTextureAccessor)(Object)mc.gameRenderer.overlayTexture()).palcraft$originalOverlayTexture().getPixels();
        if(original==null)throw new IOException("original_overlay_CPU_pixels_unavailable");
        int width=original.getWidth(),height=original.getHeight();
        if((long)width*height>2097152)throw new IOException("overlay_pixel_budget_exceeded");
        BufferedImage pixels=new BufferedImage(width,height,BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<height;y++)for(int x=0;x<width;x++)pixels.setRGB(x,y,original.getPixel(x,y));
        return png(pixels,"overlay","OverlayTexture.DynamicTexture.getPixels",revision);
    }
    private static Image lightmap(SignGlyphRaster.Atlas atlas,long revision)throws IOException {
        if(atlas.grayscale())throw new IOException("original_lightmap_not_RGBA");
        BufferedImage pixels=new BufferedImage(atlas.width(),atlas.height(),BufferedImage.TYPE_INT_ARGB);
        byte[] rgba=atlas.pixels();
        for(int y=0;y<atlas.height();y++)for(int x=0;x<atlas.width();x++) {
            int i=(y*atlas.width()+x)*4;
            pixels.setRGB(x,y,(rgba[i+3]&255)<<24|(rgba[i]&255)<<16|(rgba[i+1]&255)<<8|(rgba[i+2]&255));
        }
        return png(pixels,"lightmap","RenderType.prepare/GameRenderer.lightmap.original_GPU_copy",revision);
    }
    /** Start once for the frame, share this future for its two entity rows. The
     * retained geometry and uniforms are not replaced with a later-frame pose
     * when the original lightmap copy completes. */
    public static CompletableFuture<Snapshot> capture(Minecraft mc,long epoch,long capturedMs)throws IOException {
        long revision=SignTextExporter.shaderLightmapRevision();
        Image overlay=overlay(mc,epoch);Map<String,Object> inputs=new LinkedHashMap<>();
        inputs.put("cardinal_lighting",lighting());
        var view=mc.gameRenderer.lightmap();if(view==null)throw new IOException("original_active_lightmap_unavailable");
        return SignTextExporter.readShaderTexture(view.texture()).thenApply(atlas->{
            try{return new Snapshot(overlay,lightmap(atlas,revision),inputs,epoch,capturedMs);}
            catch(IOException failure){throw new java.util.concurrent.CompletionException(failure);}
        });
    }
    public static Map<String,Object> descriptor(Image image,long epoch,long capturedMs) {
        return Map.of("resource",image.resource,"sha256",image.sha256,"width",image.width,"height",image.height,
            "source",image.source,"revision",image.revision,"source_epoch",epoch,"captured_ms",capturedMs,"row_zero","MC UV v=0");
    }
}
