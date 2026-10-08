package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.MobWar;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.projectile.Projectile;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Cross-engine projectiles use the MC server's one collision/hurt path for players and mobs alike. */
@Mixin(Projectile.class)
abstract class ProjectileMixin {
	@Shadow
	public abstract Entity getOwner();

	@Inject(method = "canHitEntity(Lnet/minecraft/world/entity/Entity;)Z", at = @At("HEAD"), cancellable = true)
	private void passthrough$throughProxies(final Entity target, final CallbackInfoReturnable<Boolean> cir) {
		// Imported Pal sources already fight in the Pal server. Do not echo a proxy-owned shot into another proxy.
		if (MobWar.isProxy(target) && this.getOwner()!=null && MobWar.isProxy(this.getOwner())) cir.setReturnValue(false);
	}
}
