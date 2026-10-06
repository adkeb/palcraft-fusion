package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** A verified driven avatar is one Pal player. F5 never starts another health/death simulation. */
@Mixin(Player.class)
abstract class PalPlayerHealthMixin {
    @Inject(method="hurtServer(Lnet/minecraft/server/level/ServerLevel;Lnet/minecraft/world/damagesource/DamageSource;F)Z",at=@At("HEAD"),cancellable=true)
    private void palcraft$palHealth(ServerLevel level,DamageSource source,float amount,CallbackInfoReturnable<Boolean> cir){
        if((Object)this instanceof ServerPlayer p && PalEntityBridge.ownsHealth(p))
            cir.setReturnValue(PalEntityBridge.playerHurt(p,source,amount));
    }
}
