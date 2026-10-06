package dev.rehan.passthrough.client.mixin;

import net.minecraft.client.gui.Font;
import net.minecraft.client.renderer.blockentity.AbstractSignRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

/** Read the renderer's actual Font, including the active resource pack providers. */
@Mixin(AbstractSignRenderer.class)
public interface SignFontAccessor {
    @Accessor("font") Font palcraft$signFont();
}
