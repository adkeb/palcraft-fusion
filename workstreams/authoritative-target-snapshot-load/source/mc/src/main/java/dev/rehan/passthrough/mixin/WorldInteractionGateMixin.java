package dev.rehan.passthrough.mixin;

import dev.rehan.passthrough.BridgeNetwork;
import dev.rehan.passthrough.WorldCompatibility;
import net.minecraft.network.protocol.game.ServerboundContainerButtonClickPacket;
import net.minecraft.network.protocol.game.ServerboundContainerClickPacket;
import net.minecraft.network.protocol.game.ServerboundInteractPacket;
import net.minecraft.network.protocol.game.ServerboundPlayerActionPacket;
import net.minecraft.network.protocol.game.ServerboundUseItemOnPacket;
import net.minecraft.network.protocol.game.ServerboundUseItemPacket;
import net.minecraft.network.protocol.game.ServerboundMovePlayerPacket;
import net.minecraft.network.protocol.game.ServerboundMoveVehiclePacket;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** Freeze original MC interaction packets as well as host_pose until the real Pal projection is confirmed. */
@Mixin(ServerGamePacketListenerImpl.class)
abstract class WorldInteractionGateMixin {
    @Shadow public ServerPlayer player;
    @Unique private boolean passthrough$viewBlocked() {
        // Packet handlers run once on Netty before scheduling themselves, then again on the server thread.
        return player.level().getServer().isSameThread() && BridgeNetwork.drives(player) && WorldCompatibility.waitingForView(player);
    }
    @Inject(method="handlePlayerAction",at=@At("HEAD"),cancellable=true)
    private void passthrough$blockAction(ServerboundPlayerActionPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleUseItemOn",at=@At("HEAD"),cancellable=true)
    private void passthrough$useBlock(ServerboundUseItemOnPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleUseItem",at=@At("HEAD"),cancellable=true)
    private void passthrough$useItem(ServerboundUseItemPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleInteract",at=@At("HEAD"),cancellable=true)
    private void passthrough$interact(ServerboundInteractPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleContainerClick",at=@At("HEAD"),cancellable=true)
    private void passthrough$container(ServerboundContainerClickPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleContainerButtonClick",at=@At("HEAD"),cancellable=true)
    private void passthrough$containerButton(ServerboundContainerButtonClickPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleMovePlayer",at=@At("HEAD"),cancellable=true)
    private void passthrough$movement(ServerboundMovePlayerPacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
    @Inject(method="handleMoveVehicle",at=@At("HEAD"),cancellable=true)
    private void passthrough$vehicleMovement(ServerboundMoveVehiclePacket packet,CallbackInfo ci) { if(passthrough$viewBlocked())ci.cancel(); }
}
