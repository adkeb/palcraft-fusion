package dev.rehan.passthrough.client.mixin;

import dev.rehan.passthrough.client.signtext.SignTextExporter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.Lightmap;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Runs after this frame's vanilla lightmap. Inert until an accepted view is bound. */
@Mixin(GameRenderer.class)
abstract class SignTextGameRendererMixin {
    @Shadow @Final private Lightmap lightmap;

    @Inject(method = "renderLevel", at = @At("TAIL"))
    private void palcraft$exportSignText(CallbackInfo ci) {
        SignTextExporter.frame(Minecraft.getInstance(), lightmap.getTextureView());
    }

    @Inject(method = "onResourceManagerReload", at = @At("TAIL"))
    private void palcraft$refreshSignFont(CallbackInfo ci) {
        SignTextExporter.invalidateFonts();
    }
}
