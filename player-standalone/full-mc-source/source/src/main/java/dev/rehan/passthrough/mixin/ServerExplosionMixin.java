package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.WorldBridge;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.ServerExplosion;
import net.minecraft.world.level.Explosion;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Publish final vanilla destruction and a visual effect; Pal must not deal this explosion's damage again. */
@Mixin(ServerExplosion.class)
abstract class ServerExplosionMixin {
	@Shadow
	public abstract Vec3 center();

	@Shadow
	public abstract float radius();

	@Shadow
	public abstract Entity getDirectSourceEntity();
	@Shadow public abstract ServerLevel level();
	@Shadow public abstract Explosion.BlockInteraction getBlockInteraction();

	@Inject(method = "explode", at = @At("RETURN"))
	private void passthrough$report(final CallbackInfoReturnable<Integer> cir) {
		Entity source = this.getDirectSourceEntity();
		WorldBridge.onExplosion(this.level(), this.center(), this.radius(), source == null ? "" : BuiltInRegistries.ENTITY_TYPE.getKey(source.getType()).getPath(),
			cir.getReturnValueI(), this.getBlockInteraction().name().toLowerCase(java.util.Locale.ROOT));
	}
}
