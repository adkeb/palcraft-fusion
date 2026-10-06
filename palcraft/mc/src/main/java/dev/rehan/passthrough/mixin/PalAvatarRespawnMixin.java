package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.PalEntityBridge;
import net.minecraft.network.protocol.game.ServerboundClientCommandPacket;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** The real Pal lifecycle releases the original MC respawn command after normal native revival. */
@Mixin(ServerGamePacketListenerImpl.class)
abstract class PalAvatarRespawnMixin {
    @Shadow public ServerPlayer player;
    @Unique private ServerPlayer palcraft$respawnSource;
    @Inject(method="handleClientCommand(Lnet/minecraft/network/protocol/game/ServerboundClientCommandPacket;)V",at=@At("HEAD"),cancellable=true)
    private void palcraft$nativeRespawn(ServerboundClientCommandPacket packet,CallbackInfo ci){
        if(!player.level().getServer().isSameThread()
                ||packet.getAction()!=ServerboundClientCommandPacket.Action.PERFORM_RESPAWN)return;
        palcraft$respawnSource=null;
        if(!PalEntityBridge.ownsHealth(player))return;
        if(!PalEntityBridge.normalRespawnAllowed(player)){ci.cancel();return;}
        palcraft$respawnSource=player;
    }
    @Inject(method="handleClientCommand(Lnet/minecraft/network/protocol/game/ServerboundClientCommandPacket;)V",at=@At("RETURN"))
    private void palcraft$adoptNativeLife(ServerboundClientCommandPacket packet,CallbackInfo ci){
        if(packet.getAction()==ServerboundClientCommandPacket.Action.PERFORM_RESPAWN
                &&palcraft$respawnSource!=null&&palcraft$respawnSource!=player)
            PalEntityBridge.syncRespawnedPlayer(player);
        palcraft$respawnSource=null;
    }
}
