package dev.rehan.passthrough.world;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.util.function.Predicate;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.material.Fluid;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.shapes.Shapes;

/** Common-side equivalent of MC 26.3 FluidRenderer's corner averaging, independently tested against that class. */
public final class WorldFluidSurface {
    private WorldFluidSurface() {}

    private static float height(BlockGetter world, Fluid fluid, BlockPos pos) {
        BlockState block = world.getBlockState(pos); FluidState state = block.getFluidState();
        if (fluid.isSame(state.getType())) {
            if (fluid.isSame(world.getFluidState(pos.above()).getType())) return 1.0F;
            return state.getOwnHeight();
        }
        return block.isSolid() ? -1.0F : 0.0F;
    }

    private static void weight(float[] sum, float height) {
        if (height >= 0.8F) { sum[0] += height * 10.0F; sum[1] += 10.0F; }
        else if (height >= 0.0F) { sum[0] += height; sum[1] += 1.0F; }
    }

    public static float average(BlockGetter world, Fluid fluid, float own, float a, float b, BlockPos diagonal) {
        if (a >= 1.0F || b >= 1.0F) return 1.0F;
        float[] sum = new float[2];
        if (a > 0.0F || b > 0.0F) {
            float diagonalHeight = height(world, fluid, diagonal);
            if (diagonalHeight >= 1.0F) return 1.0F;
            weight(sum, diagonalHeight);
        }
        weight(sum, own); weight(sum, b); weight(sum, a);
        return sum[1] == 0 ? 0 : sum[0] / sum[1];
    }

    public static boolean faceOccluded(Direction direction, float height, BlockState state) {
        var shape = state.getFaceOcclusionShape(direction.getOpposite());
        if (shape == Shapes.empty()) return false;
        if (shape == Shapes.block()) return direction != Direction.UP || height == 1.0F;
        return Shapes.blockOccludes(Shapes.box(0,0,0,1,height,1),shape,direction);
    }

    public static boolean shouldRenderFace(FluidState fluid, BlockState own, Direction direction, FluidState neighbor) {
        return !neighbor.getType().isSame(fluid.getType()) && !faceOccluded(direction.getOpposite(),1.0F,own);
    }

    public static JsonObject sample(BlockGetter world, BlockPos pos, FluidState fluid, Predicate<BlockPos> available) {
        JsonObject result = new JsonObject(); JsonObject corners = new JsonObject(); JsonArray unknown = new JsonArray();
        Fluid type = fluid.getType(); float own = height(world, type, pos);
        int[][] offsets = {{-1,-1},{1,-1},{-1,1},{1,1}};
        String[] names = {"north_west","north_east","south_west","south_east"};
        for (int i = 0; i < offsets.length; i++) {
            int x = offsets[i][0], z = offsets[i][1];
            BlockPos a = pos.offset(x,0,0), b = pos.offset(0,0,z), diagonal = pos.offset(x,0,z);
            boolean known = available.test(a) && available.test(a.above()) && available.test(b)
                && available.test(b.above()) && available.test(diagonal) && available.test(diagonal.above());
            float value = own >= 1.0F ? 1.0F : known ? average(world,type,own,height(world,type,a),height(world,type,b),diagonal)
                : fluid.getHeight(world,pos);
            corners.addProperty(names[i], value);
            if (!known) unknown.add(names[i]);
        }
        result.add("corners", corners); result.add("unknown", unknown);
        JsonObject faces = new JsonObject(); JsonArray unknownFaces = new JsonArray(); BlockState block = world.getBlockState(pos);
        for (Direction direction : Direction.values()) {
            BlockPos neighbor = pos.relative(direction); boolean known = available.test(neighbor);
            float edgeHeight = switch(direction) {
                case UP -> Math.min(Math.min(corners.get("north_west").getAsFloat(),corners.get("north_east").getAsFloat()),
                    Math.min(corners.get("south_west").getAsFloat(),corners.get("south_east").getAsFloat()));
                case NORTH -> Math.max(corners.get("north_west").getAsFloat(),corners.get("north_east").getAsFloat());
                case SOUTH -> Math.max(corners.get("south_west").getAsFloat(),corners.get("south_east").getAsFloat());
                case WEST -> Math.max(corners.get("north_west").getAsFloat(),corners.get("south_west").getAsFloat());
                case EAST -> Math.max(corners.get("north_east").getAsFloat(),corners.get("south_east").getAsFloat());
                case DOWN -> 0.8888889F;
            };
            boolean visible = !known || shouldRenderFace(fluid,block,direction,world.getFluidState(neighbor))
                && !faceOccluded(direction,edgeHeight,world.getBlockState(neighbor));
            faces.addProperty(direction.getSerializedName(),visible);
            if (!known) unknownFaces.add(direction.getSerializedName());
        }
        result.add("face_visibility",faces); result.add("face_unknown",unknownFaces);
        result.addProperty("units", "mc_blocks"); result.addProperty("visual_epsilon", 0.001F);
        result.addProperty("algorithm", "minecraft_26_3_weighted_fluid_height");
        // The visual slope is separate from vanilla's flat entity-contact volume height.
        result.addProperty("contact_height", fluid.getHeight(world,pos));
        return result;
    }
}
