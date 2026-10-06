package dev.rehan.passthrough.client.mixin;

import com.mojang.blaze3d.resource.GraphicsResourceAllocator;
import com.mojang.renderpearl.api.buffers.GpuBufferSlice;
import dev.rehan.passthrough.client.EntityCaptureExporter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import org.joml.Vector4f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Uses the existing renderer/camera, never another guest or drawing context. */
@Mixin(LevelRenderer.class)
abstract class EntityCaptureRenderMixin {
    @Inject(method="render",at=@At("TAIL"))
    private void palcraft$captureEntities(GraphicsResourceAllocator allocator,boolean renderOutline,CameraRenderState camera,
        GpuBufferSlice slice,Vector4f color,boolean renderSky,boolean renderClouds,CallbackInfo info){
        EntityCaptureExporter.frame(Minecraft.getInstance(),camera);
    }
}
