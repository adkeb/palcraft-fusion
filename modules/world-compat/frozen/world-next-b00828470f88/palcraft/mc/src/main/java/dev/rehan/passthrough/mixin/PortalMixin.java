package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.WorldBridge;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.block.Portal;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Observe real portal entry without canceling vanilla travel, cooldowns, or destination creation. */
@Mixin(Entity.class)
abstract class PortalMixin {
	@Inject(method = "setAsInsidePortal(Lnet/minecraft/world/level/block/Portal;Lnet/minecraft/core/BlockPos;)V", at = @At("HEAD"))
	private void passthrough$portalEntered(final Portal portal, final BlockPos pos, final CallbackInfo ci) {
		Entity entity = (Entity)(Object)this;
		if (entity.level() instanceof ServerLevel level) WorldBridge.onPortalEnter(level, entity, portal, pos);
	}
}
