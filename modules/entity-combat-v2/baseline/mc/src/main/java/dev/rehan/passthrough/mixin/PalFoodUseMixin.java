package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Until native MC food use is mapped, do not consume a player's MC food while their only metabolism is Pal. */
@Mixin(LivingEntity.class)
abstract class PalFoodUseMixin {
    @Inject(method="startUsingItem(Lnet/minecraft/world/InteractionHand;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$foodUse(InteractionHand hand,CallbackInfo ci){
        if((Object)this instanceof ServerPlayer player && PalEntityBridge.ownsHealth(player)
                && player.getItemInHand(hand).has(DataComponents.FOOD)){
            player.sendSystemMessage(Component.literal("请使用帕鲁食物补充饱食度"));
            ci.cancel();
        }
    }
}
