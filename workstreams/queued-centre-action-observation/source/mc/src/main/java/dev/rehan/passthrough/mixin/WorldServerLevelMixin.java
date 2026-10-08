package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.WorldBridge;
import dev.rehan.passthrough.WorldCompatibility;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.BlockEventData;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Block entity client updates and successful lid/piston/note-block events use ServerLevel overrides. */
@Mixin(ServerLevel.class)
abstract class WorldServerLevelMixin {
    @Inject(method = "sendBlockUpdated", at = @At("RETURN"))
    private void passthrough$worldUpdate(BlockPos pos, BlockState before, BlockState after, int flags, CallbackInfo ci) {
        WorldBridge.onBlockEntityChanged((ServerLevel)(Object)this, pos, "client_update");
    }

    @Inject(method = "doBlockEvent", at = @At("RETURN"))
    private void passthrough$worldBlockEvent(BlockEventData event, CallbackInfoReturnable<Boolean> cir) {
        if (cir.getReturnValueZ()) WorldCompatibility.blockEvent((ServerLevel)(Object)this, event.pos(), event.block(), event.paramA(), event.paramB());
    }
}
