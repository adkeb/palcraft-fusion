package dev.rehan.passthrough.client.mixin;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import dev.rehan.passthrough.client.EntityShaderInputCapture;
import net.minecraft.client.renderer.DynamicGpuData;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(DynamicGpuData.class)
abstract class EntityDynamicInputMixin {
    @Inject(method="reset",at=@At("HEAD"))
    private void palcraft$resetOriginalTransforms(CallbackInfo info){EntityShaderInputCapture.resetTransforms();}
    @Inject(method="writeTransform(Lnet/minecraft/client/renderer/DynamicGpuData$Transform;)Lcom/mojang/renderpearl/api/buffers/GpuBufferSlice;",at=@At("RETURN"))
    private void palcraft$originalTransform(DynamicGpuData.Transform transform,CallbackInfoReturnable<GpuBufferSlice> info){
        EntityShaderInputCapture.transformWritten(info.getReturnValue(),transform);
    }
    @Inject(method="writeTransforms([Lnet/minecraft/client/renderer/DynamicGpuData$Transform;)[Lcom/mojang/renderpearl/api/buffers/GpuBufferSlice;",at=@At("RETURN"))
    private void palcraft$originalTransforms(DynamicGpuData.Transform[] transforms,CallbackInfoReturnable<GpuBufferSlice[]> info){
        GpuBufferSlice[] slices=info.getReturnValue();
        for(int i=0;i<slices.length;i++)EntityShaderInputCapture.transformWritten(slices[i],transforms[i]);
    }
}
