package dev.rehan.passthrough.client.mixin;
import dev.rehan.passthrough.client.PlayFeedback;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(GuiGraphicsExtractor.class)
abstract class PlayOverlayMixin {
 @Inject(method="extractDeferredElements",at=@At("HEAD"))
 private void palcraft$feedback(int mouseX,int mouseY,float delta,CallbackInfo ci) {
  if(net.minecraft.client.Minecraft.getInstance().gui.screen()!=null) PlayFeedback.draw((GuiGraphicsExtractor)(Object)this);
 }
}
