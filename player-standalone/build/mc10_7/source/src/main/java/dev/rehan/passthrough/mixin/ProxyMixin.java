package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.MobWar;
import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/**
 * Host people's proxies: hits on them go to the host instead of doing damage; they neither push nor get pushed
 * (they follow their actor every tick). Player melee and projectile damage share this server hook.
 */
@Mixin(LivingEntity.class)
abstract class ProxyMixin {
	@Inject(method = "hurtServer(Lnet/minecraft/server/level/ServerLevel;Lnet/minecraft/world/damagesource/DamageSource;F)Z", at = @At("HEAD"), cancellable = true)
	private void passthrough$proxyHurt(final ServerLevel level, final DamageSource source, final float amount, final CallbackInfoReturnable<Boolean> cir) {
		LivingEntity self = (LivingEntity) (Object) this;
		if (MobWar.isProxy(self)) {
			cir.setReturnValue(MobWar.onProxyHit(self, source, amount));
		}
	}

	@Inject(method = "isPushable()Z", at = @At("HEAD"), cancellable = true)
	private void passthrough$proxyNotPushable(final CallbackInfoReturnable<Boolean> cir) {
		if (MobWar.isProxy((LivingEntity) (Object) this)) {
			cir.setReturnValue(false);
		}
	}

	@Inject(method = "pushEntities()V", at = @At("HEAD"), cancellable = true)
	private void passthrough$proxyNoPush(final CallbackInfo ci) {
		if (MobWar.isProxy((LivingEntity) (Object) this)) {
			ci.cancel();
		}
	}

	@Inject(method = "die(Lnet/minecraft/world/damagesource/DamageSource;)V", at = @At("HEAD"))
	private void passthrough$nativeDeath(final DamageSource source, final CallbackInfo ci) {
		LivingEntity self = (LivingEntity)(Object)this;
		if (!self.level().isClientSide()) PalEntityBridge.onDeath(self, source);
	}
}
