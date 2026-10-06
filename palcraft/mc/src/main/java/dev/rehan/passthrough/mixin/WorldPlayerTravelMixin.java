package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.WorldCompatibility;
import java.util.Set;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Relative;
import net.minecraft.world.level.portal.TeleportTransition;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Capture the real source before vanilla moves it. No destination or inventory is supplied by a host request. */
@Mixin(ServerPlayer.class)
abstract class WorldPlayerTravelMixin {
    @Inject(method="teleport(Lnet/minecraft/world/level/portal/TeleportTransition;)Lnet/minecraft/server/level/ServerPlayer;",at=@At("HEAD"))
    private void passthrough$beforePortalTravel(TeleportTransition transition,CallbackInfoReturnable<ServerPlayer> cir) {
        WorldCompatibility.beforeTeleport((ServerPlayer)(Object)this);
    }
    @Inject(method="teleport(Lnet/minecraft/world/level/portal/TeleportTransition;)Lnet/minecraft/server/level/ServerPlayer;",at=@At("RETURN"))
    private void passthrough$afterPortalTravel(TeleportTransition transition,CallbackInfoReturnable<ServerPlayer> cir) {
        WorldCompatibility.afterTeleport((ServerPlayer)(Object)this,cir.getReturnValue()!=null);
    }
    @Inject(method="teleportTo(Lnet/minecraft/server/level/ServerLevel;DDDLjava/util/Set;FFZ)Z",at=@At("HEAD"))
    private void passthrough$beforeTravel(ServerLevel level,double x,double y,double z,Set<Relative> relative,float yaw,float pitch,boolean resetCamera,CallbackInfoReturnable<Boolean> cir) {
        WorldCompatibility.beforeTeleport((ServerPlayer)(Object)this);
    }
    @Inject(method="teleportTo(Lnet/minecraft/server/level/ServerLevel;DDDLjava/util/Set;FFZ)Z",at=@At("RETURN"))
    private void passthrough$afterTravel(ServerLevel level,double x,double y,double z,Set<Relative> relative,float yaw,float pitch,boolean resetCamera,CallbackInfoReturnable<Boolean> cir) {
        WorldCompatibility.afterTeleport((ServerPlayer)(Object)this,cir.getReturnValueZ());
    }
}
