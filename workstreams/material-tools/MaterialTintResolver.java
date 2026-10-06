package dev.rehan.passthrough.client.material;

import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;

/** MC26.3's actual block tint sources. Copy/invoke through the owning client feature router. */
public final class MaterialTintResolver {
    private MaterialTintResolver() {}
    public static JsonObject sample(BlockPos pos, int... indices) {
        Minecraft mc = Minecraft.getInstance();
        if (!mc.isSameThread()) throw new IllegalStateException("Tint sampling requires the Minecraft client thread");
        if (mc.level == null || mc.player == null) throw new IllegalStateException("Local bound player/world unavailable");
        if (indices.length > 16) throw new IllegalArgumentException("Too many tint indices");
        var state = mc.level.getBlockState(pos);
        JsonObject result = new JsonObject(), colors = new JsonObject();
        for (int index : indices) {
            if (index < 0 || index > 255) throw new IllegalArgumentException("Invalid tint index");
            // This replaces the pre-26.3 getColor API. It preserves distinct
            // grass, leaves, redstone/state and any registered modded sources.
            int color = mc.getBlockColors().getTintSource(state, index).colorInWorld(state, mc.level, pos);
            colors.addProperty(Integer.toString(index), color & 0xffffff);
        }
        result.addProperty("x",pos.getX());result.addProperty("y",pos.getY());result.addProperty("z",pos.getZ());
        result.addProperty("mc_uuid",mc.player.getUUID().toString());
        result.addProperty("tint_source","minecraft:block_colors");
        result.add("tint_colors",colors);
        return result;
    }
}
