package dev.rehan.passthrough.client.visual;

import com.mojang.renderpearl.api.pipeline.BlendEquation;
import com.mojang.renderpearl.api.pipeline.BlendFunction;
import com.mojang.renderpearl.api.pipeline.RenderPipeline;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;

/** Actual MC26.3 pipeline state. Names such as eyes never classify blending. */
public final class CaptureBlendMetadata {
    private CaptureBlendMetadata() {}
    private static Map<String,Object> equation(BlendEquation e) {
        return Map.of("source_factor",e.sourceFactor().name(),"dest_factor",e.destFactor().name(),"op",e.op().name());
    }
    private static String key(BlendEquation e) {
        return e.op().name()+"("+e.sourceFactor().name()+","+e.destFactor().name()+")";
    }
    public static Map<String,Object> read(RenderPipeline p) {
        Map<String,Object> m=new LinkedHashMap<>();
        m.put("v",1);m.put("source","actual_render_pipeline");m.put("pipeline",p.getLocation().toString());
        var flags=new TreeSet<>(p.getShaderDefines().flags());
        var values=new TreeMap<>(p.getShaderDefines().values());
        m.put("shader_flags",flags);m.put("shader_values",values);
        Map<String,String> shaders=new TreeMap<>();p.getShaders().forEach((kind,id)->shaders.put(kind.name(),id.toString()));
        m.put("shaders",shaders);m.put("cull",p.isCull());
        var depth=p.getDepthStencilState();
        m.put("depth",Map.of("compare",depth.depthTest().name(),"write",depth.writeDepth(),
                "bias_scale",depth.depthBiasScaleFactor(),"bias_constant",depth.depthBiasConstant()));
        var targets=new ArrayList<Map<String,Object>>();
        for(var target:p.getColorTargetStates()) {
            Map<String,Object> t=new LinkedHashMap<>();t.put("write_mask",target.writeMask());t.put("format",target.format()==null?"inherited_target_format":target.format().toString());
            var blend=target.blendFunction();t.put("enabled",blend.isPresent());
            if(blend.isPresent()) {t.put("color",equation(blend.get().color()));t.put("alpha",equation(blend.get().alpha()));}
            targets.add(t);
        }
        m.put("targets",targets);String mode="unknown";
        if(flags.contains("OIT_ALPHA_ONLY")||flags.contains("OIT_ACCUMULATE")||targets.size()!=1)mode="oit_or_multiple_targets";
        else {
            var b=p.getColorTargetStates().getFirst().blendFunction();
            if(b.isEmpty())mode="opaque";
            else {
                var f=b.get();m.put("equation","color="+key(f.color())+";alpha="+key(f.alpha()));
                if(f.equals(BlendFunction.ADDITIVE))mode="additive";
                else if(f.equals(BlendFunction.TRANSLUCENT))mode="translucent";
                else if(f.equals(BlendFunction.TRANSLUCENT_PREMULTIPLIED_ALPHA))mode="premultiplied_translucent";
                else mode="other_blend";
            }
        }
        m.put("mode",mode);
        m.put("coverage",Map.of("alpha_cutout",values.getOrDefault("ALPHA_CUTOUT","none"),
                "cutout_before_vertex_color",values.containsKey("ALPHA_CUTOUT"),"dissolve",flags.contains("DISSOLVE")));
        boolean entity=shaders.values().stream().anyMatch(s->s.equals("minecraft:core/entity"));
        m.put("light_mode",entity?(flags.contains("EMISSIVE")?"emissive_no_lightmap":"sample_lightmap"):"shader_specific");
        m.put("overlay_mode",entity?(flags.contains("NO_OVERLAY")?"none":"sample_overlay"):"shader_specific");
        m.put("vertex_mode",entity?(flags.contains("PER_FACE_LIGHTING")?"per_face_normal_mix":
                flags.contains("NO_CARDINAL_LIGHTING")?"vertex_rgba":"normal_direction_mix"):"shader_specific");
        return m;
    }
}
