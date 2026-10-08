package dev.rehan.passthrough.client.mixin;

import dev.rehan.passthrough.client.EntityCaptureExporter;
import net.minecraft.client.renderer.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
abstract class EntityCaptureResourceMixin {
    @Inject(method="onResourceManagerReload",at=@At("TAIL"))
    private void palcraft$invalidateEntityTextures(CallbackInfo info){EntityCaptureExporter.invalidateResources();}
}
