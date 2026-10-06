package dev.rehan.passthrough.client.mixin;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import dev.rehan.passthrough.client.EntityShaderInputCapture;
import net.minecraft.client.renderer.rendertype.RenderType;
import org.joml.Matrix4f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(RenderType.class)
abstract class EntityRenderTypeInputMixin {
    @Inject(method="writeDynamicTransforms",at=@At("RETURN"))
    private void palcraft$originalTypeTransforms(Matrix4f matrix,CallbackInfoReturnable<GpuBufferSlice> info){
        EntityShaderInputCapture.renderTypePrepared((RenderType)(Object)this,info.getReturnValue());
    }
}
