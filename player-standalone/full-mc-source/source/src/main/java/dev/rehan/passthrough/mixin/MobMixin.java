package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.MobWar;
import net.minecraft.world.entity.Mob;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Minecraft's world is always day here (so its lighting stays bright): undead don't burn in it. */
@Mixin(Mob.class)
abstract class MobMixin {
	@Inject(method = "burnUndead()V", at = @At("HEAD"), cancellable = true)
	private void passthrough$noSunburn(final CallbackInfo ci) {
		if (Passthrough.active) {
			ci.cancel();
		}
	}

	@Inject(method = "serverAiStep()V", at = @At("HEAD"))
	private void passthrough$palBrainTarget(final CallbackInfo ci) {
		MobWar.syncBrainTarget((Mob)(Object)this);
	}
}
