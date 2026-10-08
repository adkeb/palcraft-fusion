package dev.rehan.passthrough.mixin;

import com.mojang.authlib.GameProfile;
import net.minecraft.server.network.ServerLoginPacketListenerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

/** MC fills this before VERIFYING; Fabric GAME_PROFILE context is populated only after login queries finish. */
@Mixin(ServerLoginPacketListenerImpl.class)
public interface SessionLoginAccessor {
    @Accessor("authenticatedProfile")
    GameProfile palcraft$authenticatedProfile();
}
