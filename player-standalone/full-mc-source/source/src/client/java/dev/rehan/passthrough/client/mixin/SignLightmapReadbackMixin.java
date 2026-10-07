package dev.rehan.passthrough.client.mixin;

import com.mojang.renderpearl.api.textures.GpuTexture;
import dev.rehan.passthrough.client.signtext.SignTextExporter;
import net.minecraft.client.renderer.Lightmap;
import net.minecraft.client.renderer.state.LightmapRenderState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** The native text exporter samples the actual lightmap, including gamma,
 * weather, night vision and darkness. Only its copy permission changes. */
@Mixin(Lightmap.class)
abstract class SignLightmapReadbackMixin {
    @ModifyArg(method = "<init>", index = 1,
        at = @At(value = "INVOKE", target = "Lcom/mojang/renderpearl/api/device/GpuDevice;createTexture(Ljava/lang/String;ILcom/mojang/renderpearl/api/GpuFormat;IIII)Lcom/mojang/renderpearl/api/textures/GpuTexture;"))
    private int palcraft$allowSignLightReadback(int usage) {
        return usage | GpuTexture.USAGE_COPY_SRC;
    }

    @Inject(method = "render", at = @At("TAIL"))
    private void palcraft$trackLightmap(LightmapRenderState state, CallbackInfo ci) {
        if (state.needsUpdate) SignTextExporter.lightmapChanged();
    }
}
