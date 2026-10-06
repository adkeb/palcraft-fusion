package dev.rehan.passthrough.world;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import com.mojang.serialization.JsonOps;
import java.util.Comparator;
import java.util.function.Predicate;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.Block;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.nbt.NbtOps;
import net.minecraft.tags.FluidTags;
import net.minecraft.world.Container;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CropBlock;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.piston.PistonMovingBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateHolder;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.material.Fluids;
import net.minecraft.world.level.material.FlowingFluid;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;

/** Vanilla state and collision are separate from fluid and visual semantics. No guessed host materials. */
public final class WorldStateCodec {
    private static final int MAX_UPDATE_TAG_BYTES = 16384;

    private WorldStateCodec() {}

    public static JsonArray at(BlockPos pos) {
        JsonArray result = new JsonArray();
        result.add(pos.getX()); result.add(pos.getY()); result.add(pos.getZ());
        return result;
    }

    public static JsonArray vector(Vec3 pos) {
        JsonArray result = new JsonArray();
        result.add(pos.x); result.add(pos.y); result.add(pos.z);
        return result;
    }

    private static <T extends Comparable<T>> String value(StateHolder<?, ?> state, Property<T> property) {
        return property.getName(state.getValue(property));
    }

    public static JsonObject properties(StateHolder<?, ?> state) {
        JsonObject result = new JsonObject();
        state.getProperties().stream().sorted(Comparator.comparing(Property::getName))
            .forEach(property -> result.addProperty(property.getName(), value(state, property)));
        return result;
    }

    public static JsonObject state(BlockState state) {
        JsonObject result = new JsonObject();
        result.addProperty("id", BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString());
        result.addProperty("state", state.toString());
        result.add("properties", properties(state));
        return result;
    }

    public static boolean mirrored(BlockState state, boolean hostGround) {
        return !hostGround && !state.isAir() && !state.is(Blocks.BARRIER);
    }

    public static JsonObject fluid(BlockGetter world, BlockPos pos, BlockState block) {
        FluidState fluid = block.getFluidState();
        JsonObject result = new JsonObject();
        result.addProperty("id", BuiltInRegistries.FLUID.getKey(fluid.getType()).toString());
        result.addProperty("family", BuiltInRegistries.FLUID.getKey(fluid.getType() instanceof FlowingFluid flowing
            ? flowing.getSource() : fluid.getType()).toString());
        result.addProperty("kind", fluid.isEmpty() ? "none" : fluid.is(FluidTags.WATER) || fluid.getType().isSame(Fluids.WATER) ? "water"
            : fluid.is(FluidTags.LAVA) || fluid.getType().isSame(Fluids.LAVA) ? "lava" : "other");
        result.addProperty("empty", fluid.isEmpty());
        result.addProperty("waterlogged", block.hasProperty(BlockStateProperties.WATERLOGGED)
            && block.getValue(BlockStateProperties.WATERLOGGED));
        if (!fluid.isEmpty()) {
            result.addProperty("source", fluid.isSource());
            result.addProperty("amount", fluid.getAmount());
            result.addProperty("height", fluid.getHeight(world, pos));
            result.addProperty("own_height", fluid.getOwnHeight());
            result.addProperty("falling", fluid.hasProperty(BlockStateProperties.FALLING)
                && fluid.getValue(BlockStateProperties.FALLING));
            result.add("flow", vector(fluid.getFlow(world, pos)));
            result.add("properties", properties(fluid));
        }
        // A fluid volume is never a solid cube. Waterlogged blocks retain their own collision boxes.
        result.addProperty("collision", "ignore");
        result.addProperty("simulation", "minecraft");
        return result;
    }

    public static JsonObject block(BlockGetter world, BlockPos pos, BlockState block,
                                   HolderLookup.Provider registries, boolean hostGround) {
        return block(world, pos, block, registries, hostGround, ignored -> true);
    }

    public static JsonObject block(BlockGetter world, BlockPos pos, BlockState block,
                                   HolderLookup.Provider registries, boolean hostGround, Predicate<BlockPos> neighborAvailable) {
        JsonObject result = state(block);
        boolean mirrored = mirrored(block, hostGround);
        result.addProperty("op", mirrored ? "upsert" : "remove");
        result.add("at", at(pos));
        result.addProperty("mirror", mirrored);
        boolean visible = mirrored && !block.is(Blocks.STRUCTURE_VOID) && !block.is(Blocks.LIGHT);
        result.addProperty("visible", visible);
        JsonArray boxes = new JsonArray();
        if (mirrored) for (AABB box : block.getCollisionShape(world, pos).toAabbs()) {
            JsonArray bounds = new JsonArray();
            bounds.add(box.minX); bounds.add(box.minY); bounds.add(box.minZ);
            bounds.add(box.maxX); bounds.add(box.maxY); bounds.add(box.maxZ);
            boxes.add(bounds);
        }
        result.add("boxes", boxes);
        result.addProperty("solid", !boxes.isEmpty());
        result.addProperty("non_solid", boxes.isEmpty());
        JsonObject faces = new JsonObject(); JsonArray unknown = new JsonArray();
        for (Direction direction : Direction.values()) {
            BlockPos neighbor = pos.relative(direction); boolean known = neighborAvailable.test(neighbor);
            String name = direction.getSerializedName();
            faces.addProperty(name, !known || Block.shouldRenderFace(block, world.getBlockState(neighbor), direction));
            if (!known) unknown.add(name);
        }
        result.add("face_visibility", faces); result.add("face_unknown", unknown);
        result.addProperty("can_occlude", block.canOcclude());
        JsonObject fluid = fluid(world, pos, block);
        if (!block.getFluidState().isEmpty()) fluid.add("surface", WorldFluidSurface.sample(world, pos, block.getFluidState(), neighborAvailable));
        result.add("fluid", fluid);
        result.addProperty("light", block.getLightEmission());
        result.addProperty("render_kind", !visible ? "none" : block.is(Blocks.MOVING_PISTON) ? "moving_block"
            : block.is(Blocks.NETHER_PORTAL) || block.is(Blocks.END_PORTAL) || block.is(Blocks.END_GATEWAY) ? "portal"
            : block.is(Blocks.WATER) || block.is(Blocks.LAVA) ? "fluid" : boxes.isEmpty() ? "non_solid" : "block");
        for (Property<?> property : block.getProperties()) {
            if (property instanceof IntegerProperty age && age.getName().equals("age")) {
                JsonObject growth = new JsonObject();
                int current = block.getValue(age);
                int maximum = block.getBlock() instanceof CropBlock crop ? crop.getMaxAge()
                    : age.getPossibleValues().stream().max(Integer::compareTo).orElse(current);
                growth.addProperty("age", current); growth.addProperty("max_age", maximum);
                growth.addProperty("mature", current == maximum);
                result.add("growth", growth);
                break;
            }
        }
        BlockEntity entity = mirrored ? world.getBlockEntity(pos) : null;
        result.add("block_entity", entity == null || entity.isRemoved() ? JsonNull.INSTANCE : blockEntity(entity, registries));
        return result;
    }

    public static JsonObject blockEntity(BlockEntity entity, HolderLookup.Provider registries) {
        JsonObject result = new JsonObject();
        result.addProperty("id", BuiltInRegistries.BLOCK_ENTITY_TYPE.getKey(entity.getType()).toString());
        if (registries != null) {
            // Only the vanilla client update tag, never saveWithFullMetadata or container inventories.
            JsonElement tag = NbtOps.INSTANCE.convertTo(JsonOps.INSTANCE, entity.getUpdateTag(registries));
            if (tag.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length <= MAX_UPDATE_TAG_BYTES)
                result.add("update", tag);
            else result.addProperty("update_omitted", "exceeds_16384_bytes");
        }
        if (entity instanceof Container container) {
            int occupied = 0, count = 0;
            for (int slot = 0; slot < container.getContainerSize(); slot++) {
                var stack = container.getItem(slot);
                if (!stack.isEmpty()) { occupied++; count += stack.getCount(); }
            }
            JsonObject contents = new JsonObject();
            contents.addProperty("slots", container.getContainerSize());
            contents.addProperty("occupied", occupied); contents.addProperty("count", count);
            contents.addProperty("comparator", AbstractContainerMenu.getRedstoneSignalFromContainer(container));
            result.add("container", contents);
        }
        if (entity instanceof PistonMovingBlockEntity piston) {
            JsonObject motion = new JsonObject();
            motion.addProperty("progress", piston.getProgress(1.0F));
            motion.addProperty("previous_progress", piston.getProgress(0.0F));
            motion.addProperty("extending", piston.isExtending());
            motion.addProperty("source", piston.isSourcePiston());
            motion.addProperty("direction", piston.getDirection().getSerializedName());
            motion.add("moved", state(piston.getMovedState()));
            Vec3 offset = new Vec3(piston.getXOff(1.0F), piston.getYOff(1.0F), piston.getZOff(1.0F));
            motion.add("offset", vector(offset));
            result.add("motion", motion);
        }
        return result;
    }
}
