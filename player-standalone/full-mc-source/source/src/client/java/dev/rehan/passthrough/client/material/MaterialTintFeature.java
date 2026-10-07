package dev.rehan.passthrough.client.material;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.BiomeColors;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Read-only, local bound-player tint response. The owning HostLink keeps auth/session routing. */
public final class MaterialTintFeature {
    private MaterialTintFeature() {}
    public static JsonObject query(JsonObject request, JsonObject trustedView) {
        Minecraft mc=Minecraft.getInstance();
        if(!mc.isSameThread())throw new IllegalStateException("Tint query requires client thread");
        if(mc.level==null||mc.player==null||trustedView==null)throw new IllegalStateException("Bound local world unavailable");
        JsonObject lifecycle=trustedView.getAsJsonArray("lifecycle").get(0).getAsJsonObject();
        String uuid=mc.player.getUUID().toString(),session=trustedView.get("session").getAsString(),dim=trustedView.get("dim").getAsString();
        long view=lifecycle.get("view").getAsLong();
        // Read-only hidden prepare can sample before view ACK. The real client
        // level must already be in the current trusted dimension.
        if(!dim.equals(mc.level.dimension().identifier().toString())||
           !uuid.equals(request.get("mc_uuid").getAsString())||
           !session.equals(request.get("world_session").getAsString())||
           !dim.equals(request.get("dim").getAsString())||view!=request.get("view").getAsLong())
            throw new SecurityException("Material tint scope is not the current bound view");
        JsonArray rows=request.getAsJsonArray("rows");
        if(rows==null||rows.size()==0||rows.size()>32)throw new IllegalArgumentException("1..32 tint rows required");
        JsonArray colors=new JsonArray();
        for(JsonElement element:rows) {
            JsonObject row=element.getAsJsonObject();
            BlockPos pos=new BlockPos(row.get("x").getAsInt(),row.get("y").getAsInt(),row.get("z").getAsInt());
            if(!mc.level.hasChunkAt(pos))throw new IllegalStateException("Tint biome chunk not loaded");
            BlockState state=mc.level.getBlockState(pos);
            // This samples the actual local biome/state color without placing a
            // probe block. Registry state overrides are read-only material queries.
            if(row.has("id"))state=BuiltInRegistries.BLOCK.getOptional(Identifier.parse(row.get("id").getAsString()))
                .orElseThrow(()->new IllegalArgumentException("Unknown tint block")).defaultBlockState();
            if(row.has("properties"))for(var property:row.getAsJsonObject("properties").entrySet())
                state=set(state,property.getKey(),property.getValue().getAsString());
            JsonArray indices=row.getAsJsonArray("indices");
            if(indices==null||indices.size()==0||indices.size()>16)throw new IllegalArgumentException("1..16 tint indices required");
            JsonObject result=new JsonObject(),tints=new JsonObject();
            boolean water=row.has("tint_role")&&row.get("tint_role").getAsString().equals("water");
            for(JsonElement index:indices) {
                int number=index.getAsInt();
                if(number<0||number>255)throw new IllegalArgumentException("Tint index outside0..255");
                int rgb=(water?BiomeColors.getAverageWaterColor(mc.level,pos):
                    mc.getBlockColors().getTintSource(state,number).colorInWorld(state,mc.level,pos))&0xffffff;
                tints.addProperty(Integer.toString(number),rgb);
            }
            result.addProperty("x",pos.getX());result.addProperty("y",pos.getY());result.addProperty("z",pos.getZ());
            result.addProperty("id",BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString());
            result.addProperty("tint_source",water?"minecraft:biome_water_color":"minecraft:block_tint_source.colorInWorld");
            if(row.has("key"))result.add("key",row.get("key"));
            result.add("tint_colors",tints);colors.add(result);
        }
        JsonObject reply=new JsonObject();
        reply.addProperty("t","material_tint");reply.addProperty("v",1);reply.addProperty("mc_uuid",uuid);
        reply.addProperty("world_session",session);reply.addProperty("dim",dim);reply.addProperty("view",view);
        reply.addProperty("source","minecraft:material_tint_v1");
        reply.addProperty("read_only",true);reply.add("rows",colors);
        if(request.has("request_id"))reply.add("request_id",request.get("request_id"));
        return reply;
    }
    private static <T extends Comparable<T>> BlockState setValue(BlockState state,Property<T> property,String value) {
        return state.setValue(property,property.getValue(value).orElseThrow(()->new IllegalArgumentException("Invalid block property")));
    }
    private static BlockState set(BlockState state,String name,String value) {
        Property<?> property=state.getBlock().getStateDefinition().getProperty(name);
        if(property==null)throw new IllegalArgumentException("Unknown block property");
        return setValue(state,property,value);
    }
}
