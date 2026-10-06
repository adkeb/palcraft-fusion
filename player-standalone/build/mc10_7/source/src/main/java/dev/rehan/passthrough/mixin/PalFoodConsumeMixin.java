package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import dev.rehan.passthrough.PalFoodBridge;
import net.minecraft.core.component.DataComponents;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.component.Consumable;
import net.minecraft.world.level.Level;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** MC 26.3 Consumable.onConsume shrinks the original stack by one at its RETURN. */
@Mixin(Consumable.class)
abstract class PalFoodConsumeMixin {
    @Inject(method="onConsume(Lnet/minecraft/world/level/Level;Lnet/minecraft/world/entity/LivingEntity;Lnet/minecraft/world/item/ItemStack;)Lnet/minecraft/world/item/ItemStack;",at=@At("HEAD"),cancellable=true)
    private void palcraft$prepare(Level level,LivingEntity entity,ItemStack stack,CallbackInfoReturnable<ItemStack> cir){
        if(entity instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p)&&stack.has(DataComponents.FOOD)
                && !PalFoodBridge.begin(p,stack))cir.setReturnValue(stack);
    }
    @Inject(method="onConsume(Lnet/minecraft/world/level/Level;Lnet/minecraft/world/entity/LivingEntity;Lnet/minecraft/world/item/ItemStack;)Lnet/minecraft/world/item/ItemStack;",at=@At("RETURN"))
    private void palcraft$completed(Level level,LivingEntity entity,ItemStack stack,CallbackInfoReturnable<ItemStack> cir){
        if(entity instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p))PalFoodBridge.complete(p,stack);
    }
}
