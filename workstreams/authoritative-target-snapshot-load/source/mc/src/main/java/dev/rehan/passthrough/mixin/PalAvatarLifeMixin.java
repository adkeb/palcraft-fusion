package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Pal owns healing, corpse/respawn and death penalty. MC keeps its inventory and reports the mapped health. */
@Mixin(LivingEntity.class)
abstract class PalAvatarLifeMixin {
    @Inject(method="heal(F)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$palHealing(float amount,CallbackInfo ci){
        if((Object)this instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p))ci.cancel();
    }
    @Inject(method="die(Lnet/minecraft/world/damagesource/DamageSource;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$palDeath(DamageSource source,CallbackInfo ci){
        if((Object)this instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p))ci.cancel();
    }
    @Inject(method="tickDeath()V",at=@At("HEAD"),cancellable=true)
    private void palcraft$palCorpse(CallbackInfo ci){
        if((Object)this instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p))ci.cancel();
    }
}
