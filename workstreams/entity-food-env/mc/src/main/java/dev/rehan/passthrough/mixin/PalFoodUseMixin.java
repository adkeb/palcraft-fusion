package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import dev.rehan.passthrough.PalFoodBridge;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Native readiness and a single pending paid consumption protect the real stack. */
@Mixin(LivingEntity.class)
abstract class PalFoodUseMixin {
    @Inject(method="startUsingItem(Lnet/minecraft/world/InteractionHand;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$foodUse(InteractionHand hand,CallbackInfo ci){
        if((Object)this instanceof ServerPlayer player && PalEntityBridge.ownsHealth(player)
                && player.getItemInHand(hand).has(DataComponents.FOOD)&&!PalFoodBridge.canConsume(player,player.getItemInHand(hand))){
            player.sendSystemMessage(Component.literal("补给同步中，请稍候"));
            ci.cancel();
        }
    }
}
