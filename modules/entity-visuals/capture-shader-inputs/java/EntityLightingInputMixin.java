package dev.rehan.passthrough.client.mixin;
import com.mojang.blaze3d.platform.Lighting;
import dev.rehan.passthrough.client.EntityShaderInputCapture;
import org.joml.Vector3fc;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Lighting.class)
abstract class EntityLightingInputMixin {
    @Inject(method="updateBuffer",at=@At("HEAD"))
    private void palcraft$originalLightDirections(Lighting.Entry entry,Vector3fc first,Vector3fc second,CallbackInfo info) {
        EntityShaderInputCapture.lightingUpdated(entry,first,second);
    }
    @Inject(method="setupFor",at=@At("TAIL"))
    private void palcraft$originalLightSelection(Lighting.Entry entry,CallbackInfo info){EntityShaderInputCapture.lightingSelected(entry);}
}
