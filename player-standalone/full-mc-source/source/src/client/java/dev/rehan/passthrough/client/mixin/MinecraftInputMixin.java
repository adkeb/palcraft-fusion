package dev.rehan.passthrough.client.mixin;

import dev.rehan.passthrough.Passthrough;
import net.minecraft.client.Minecraft;
import net.minecraft.client.MouseHandler;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

/** The host owns OS focus; otherwise retain Minecraft's complete survival input path. */
@Mixin(Minecraft.class)
abstract class MinecraftInputMixin {
    @Redirect(method = "handleKeybinds", at = @At(value = "INVOKE",
        target = "Lnet/minecraft/client/MouseHandler;isMouseGrabbed()Z"))
    private boolean palcraft$hostOwnsMouse(MouseHandler mouse) {
        return Passthrough.active || mouse.isMouseGrabbed();
    }
}
