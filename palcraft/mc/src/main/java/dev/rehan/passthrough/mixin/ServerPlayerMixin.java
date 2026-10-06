package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.PalEntityBridge;
import java.util.Locale;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.portal.TeleportTransition;
import net.minecraft.world.phys.Vec3;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyVariable;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

/** Minecraft moving the player (ender pearls, /tp) moves the host's player too; otherwise the host would pull it back. */
@Mixin(ServerPlayer.class)
abstract class ServerPlayerMixin {
    /** Pal already owns death penalties. Transfer only the avatar's existing vanilla inventory/XP.
     * PlayerList's death flag remains false, so vanilla still uses/consumes the actual respawn block. */
    @ModifyVariable(method="restoreFrom(Lnet/minecraft/server/level/ServerPlayer;Z)V",at=@At("HEAD"),argsOnly=true,ordinal=0)
    private boolean palcraft$restoreAvatar(boolean original,ServerPlayer from,boolean keepEverything){
        return original||PalEntityBridge.normalRespawnAllowed(from);
    }
	@Inject(method = "teleport(Lnet/minecraft/world/level/portal/TeleportTransition;)Lnet/minecraft/server/level/ServerPlayer;", at = @At("HEAD"))
	private void passthrough$teleported(final TeleportTransition transition, final CallbackInfoReturnable<ServerPlayer> cir) {
		if (Passthrough.active) {
			Vec3 p = transition.position();
			dev.rehan.passthrough.BridgeNetwork.eventFor((ServerPlayer)(Object)this,String.format(Locale.ROOT, "{\"t\":\"pteleport\",\"pos\":[%.3f,%.3f,%.3f]}", p.x, p.y, p.z));
		}
	}
}
