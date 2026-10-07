package dev.rehan.passthrough.client.mixin;
import dev.rehan.passthrough.client.PlayFeedback;
import net.minecraft.client.Minecraft;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.gui.Hud;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(Hud.class)
abstract class PlayHudMixin {
 @Inject(method="extractRenderState",at=@At("HEAD"),cancellable=true)
 private void palcraft$onlyCurrentForm(GuiGraphicsExtractor g,DeltaTracker delta,CallbackInfo ci){
  if(dev.rehan.passthrough.Passthrough.active&&!dev.rehan.passthrough.client.ClientInput.buildMode){
   g.centeredText(Minecraft.getInstance().font,"F5 变身 Minecraft",g.guiWidth()/2,18,0xffdbe9e5);ci.cancel();
  }
 }
 @Inject(method="extractRenderState",at=@At("TAIL"))
 private void palcraft$feedback(GuiGraphicsExtractor g,DeltaTracker delta,CallbackInfo ci){
  if(Minecraft.getInstance().gui.screen()==null) PlayFeedback.draw(g);
 }
}
