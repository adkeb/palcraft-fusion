package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.WorldBridge;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.entity.BlockEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Capture successful vanilla mutations; the end-of-tick reader resolves cascading updates to final state. */
@Mixin(Level.class)
abstract class LevelMixin {
	@Inject(method = "setBlock(Lnet/minecraft/core/BlockPos;Lnet/minecraft/world/level/block/state/BlockState;II)Z", at = @At("RETURN"))
	private void passthrough$blockChanged(final BlockPos pos, final BlockState state, final int flags, final int limit, final CallbackInfoReturnable<Boolean> cir) {
		if (cir.getReturnValueZ() && (Object) this instanceof ServerLevel level) {
			WorldBridge.onBlockChanged(level, pos, state, flags);
		}
	}

	@Inject(method = "blockEntityChanged", at = @At("RETURN"))
	private void passthrough$blockEntityDirty(final BlockPos pos, final CallbackInfo ci) {
		if ((Object)this instanceof ServerLevel level) WorldBridge.onBlockEntityChanged(level, pos, "block_entity_dirty");
	}

	@Inject(method = "onBlockEntityAdded", at = @At("RETURN"))
	private void passthrough$blockEntityAdded(final BlockEntity entity, final CallbackInfo ci) {
		if ((Object)this instanceof ServerLevel level) WorldBridge.onBlockEntityChanged(level, entity.getBlockPos(), "block_entity_added");
	}
}
