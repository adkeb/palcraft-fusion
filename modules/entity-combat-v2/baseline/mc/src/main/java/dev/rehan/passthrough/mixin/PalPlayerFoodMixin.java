package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.food.FoodData;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** One real Pal metabolism. The MC bar is a read-only map, without a second starvation or regeneration clock. */
@Mixin(FoodData.class)
abstract class PalPlayerFoodMixin {
    @Inject(method="tick(Lnet/minecraft/server/level/ServerPlayer;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$nativeFood(ServerPlayer player,CallbackInfo ci){
        if(PalEntityBridge.ownsHealth(player))ci.cancel();
    }
}
