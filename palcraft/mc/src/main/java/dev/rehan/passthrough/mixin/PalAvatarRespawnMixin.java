package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.network.protocol.game.ServerboundClientCommandPacket;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** A secondary MC respawn must not replace/heal the avatar while the real Pal player owns death/respawn. */
@Mixin(ServerGamePacketListenerImpl.class)
abstract class PalAvatarRespawnMixin {
    @Shadow public ServerPlayer player;
    @Inject(method="handleClientCommand(Lnet/minecraft/network/protocol/game/ServerboundClientCommandPacket;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$nativeRespawn(ServerboundClientCommandPacket packet,CallbackInfo ci){
        if(player.level().getServer().isSameThread()
                && packet.getAction()==ServerboundClientCommandPacket.Action.PERFORM_RESPAWN
                && PalEntityBridge.ownsHealth(player))ci.cancel();
    }
}
