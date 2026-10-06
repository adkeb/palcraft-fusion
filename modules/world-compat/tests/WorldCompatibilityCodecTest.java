import com.google.gson.JsonObject;
import dev.rehan.passthrough.world.WorldDeltaBuffer;
import dev.rehan.passthrough.world.WorldStateCodec;
import dev.rehan.passthrough.world.WorldFluidSurface;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import net.minecraft.SharedConstants;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.Bootstrap;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.core.component.DataComponentMap;
import net.minecraft.core.component.DataComponents;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.entity.ChestBlockEntity;
import net.minecraft.world.level.block.piston.PistonMovingBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;
import net.minecraft.world.level.material.FluidState;

/** Offline contract test using the installed, unobfuscated Minecraft 26.3 classes. No server or save opened. */
public final class WorldCompatibilityCodecTest {
    private static int checks;
    private static final BlockPos AT = new BlockPos(0, 64, 0);
    private static final class World implements BlockGetter {
        final Map<BlockPos,BlockState> states = new HashMap<>();
        final Map<BlockPos,BlockEntity> entities = new HashMap<>();
        public BlockState getBlockState(BlockPos pos) { return states.getOrDefault(pos, Blocks.AIR.defaultBlockState()); }
        public BlockEntity getBlockEntity(BlockPos pos) { return entities.get(pos); }
        public FluidState getFluidState(BlockPos pos) { return getBlockState(pos).getFluidState(); }
        public int getMinY() { return -64; }
        public int getHeight() { return 384; }
        JsonObject block(BlockState state) {
            states.put(AT,state); return WorldStateCodec.block(this,AT,state,null,false);
        }
    }
    private static void check(boolean condition, String message) {
        checks++; if (!condition) throw new AssertionError(message);
    }
    private static <T extends Comparable<T>> BlockState set(BlockState state,Property<T> property,String value) {
        return state.setValue(property,property.getValue(value).orElseThrow());
    }
    private static BlockState with(BlockState state,String property,String value) {
        for (Property<?> candidate:state.getProperties()) if (candidate.getName().equals(property)) return set(state,candidate,value);
        throw new AssertionError("Missing vanilla property "+property);
    }
    private static String prop(JsonObject block,String name) { return block.getAsJsonObject("properties").get(name).getAsString(); }
    private static String fluid(JsonObject block) { return block.getAsJsonObject("fluid").get("kind").getAsString(); }

    public static void main(String[] args) throws Exception {
        SharedConstants.tryDetectVersion(); Bootstrap.bootStrap();
        // 26.3 binds item components during data-pack loading. Bind only this isolated test stack's stack-size
        // component; no server, player, inventory, game save, or installed registry is modified.
        Items.OAK_PLANKS.builtInRegistryHolder().bindComponents(DataComponentMap.builder().set(DataComponents.MAX_STACK_SIZE,64).build());
        JsonObject fixtures = new JsonObject(); World world = new World();
        JsonObject wood = world.block(Blocks.OAK_PLANKS.defaultBlockState()); fixtures.add("wood",wood);
        check(fluid(wood).equals("none"),"ordinary wood must never become water");
        check(wood.get("solid").getAsBoolean() && wood.getAsJsonArray("boxes").size()==1,"wood collision is native vanilla cube");
        for (var entry : Map.of("stone",Blocks.STONE,"glass",Blocks.GLASS,"leaves",Blocks.OAK_LEAVES,
                "slab",Blocks.OAK_SLAB,"stairs",Blocks.OAK_STAIRS,"fence",Blocks.OAK_FENCE).entrySet()) {
            JsonObject sample=world.block(entry.getValue().defaultBlockState());fixtures.add(entry.getKey(),sample);
            check(sample.get("solid").getAsBoolean(),"registered collision oracle "+entry.getKey());
        }
        JsonObject source = world.block(Blocks.WATER.defaultBlockState()); fixtures.add("water_source",source);
        check(fluid(source).equals("water") && source.getAsJsonObject("fluid").get("source").getAsBoolean(),"water source preserved");
        check(!source.get("solid").getAsBoolean() && source.getAsJsonArray("boxes").isEmpty(),"water has no solid collision");
        check(source.get("visible").getAsBoolean() && source.get("render_kind").getAsString().equals("fluid"),"water is visible fluid");
        check(source.getAsJsonObject("fluid").get("amount").getAsInt()==8,"source amount is eight");
        check(Math.abs(source.getAsJsonObject("fluid").get("height").getAsDouble()-8.0/9.0)<1e-6,"vanilla water own height");
        check(source.getAsJsonObject("fluid").getAsJsonObject("surface").getAsJsonObject("corners").get("north_west").getAsDouble()<8.0/9.0,
            "rendered fluid corner differs from entity-contact height at an air boundary");
        world.states.put(AT.above(),Blocks.WATER.defaultBlockState());
        JsonObject full = world.block(Blocks.WATER.defaultBlockState()); fixtures.add("water_stacked",full);
        check(full.getAsJsonObject("fluid").get("height").getAsDouble()==1.0,"fluid stacked above raises height to one");
        world.states.remove(AT.above());
        JsonObject flowing = world.block(with(Blocks.WATER.defaultBlockState(),"level","3")); fixtures.add("water_flowing",flowing);
        check(!flowing.getAsJsonObject("fluid").get("source").getAsBoolean(),"flowing water remains flowing");
        check(flowing.getAsJsonObject("fluid").get("amount").getAsInt()==5,"flow level three is vanilla amount five");
        JsonObject falling = world.block(with(Blocks.WATER.defaultBlockState(),"level","8")); fixtures.add("water_falling",falling);
        check(falling.getAsJsonObject("fluid").get("falling").getAsBoolean(),"falling property preserved");
        JsonObject lava = world.block(Blocks.LAVA.defaultBlockState()); fixtures.add("lava",lava);
        check(fluid(lava).equals("lava") && !lava.get("solid").getAsBoolean(),"lava is a fluid, not a solid or water");
        JsonObject waterlogged = world.block(with(Blocks.OAK_SLAB.defaultBlockState(),"waterlogged","true")); fixtures.add("waterlogged_slab",waterlogged);
        check(fluid(waterlogged).equals("water") && waterlogged.get("solid").getAsBoolean(),"waterlogged slab keeps independent water and solid semantics");
        check(waterlogged.getAsJsonObject("fluid").get("waterlogged").getAsBoolean(),"waterlogged flag preserved");
        check(waterlogged.getAsJsonArray("boxes").get(0).getAsJsonArray().get(4).getAsDouble()==0.5,"slab collision stays half height");
        JsonObject immature = world.block(Blocks.WHEAT.defaultBlockState()); fixtures.add("wheat_0",immature);
        JsonObject mature = world.block(with(Blocks.WHEAT.defaultBlockState(),"age","7")); fixtures.add("wheat_7",mature);
        check(!immature.get("solid").getAsBoolean() && immature.get("visible").getAsBoolean(),"crop remains visible without collision");
        check(mature.getAsJsonObject("growth").get("mature").getAsBoolean() && prop(mature,"age").equals("7"),"crop growth state exact");
        JsonObject beets = world.block(with(Blocks.BEETROOTS.defaultBlockState(),"age","3")); fixtures.add("beetroot_3",beets);
        check(beets.getAsJsonObject("growth").get("max_age").getAsInt()==3,"crop-specific max age is not guessed as seven");
        JsonObject wire = world.block(with(Blocks.REDSTONE_WIRE.defaultBlockState(),"power","15")); fixtures.add("redstone_15",wire);
        check(prop(wire,"power").equals("15") && !wire.get("solid").getAsBoolean() && wire.get("visible").getAsBoolean(),"redstone power stays visible non-solid state");
        JsonObject doorClosed = world.block(Blocks.OAK_DOOR.defaultBlockState()); fixtures.add("door_closed",doorClosed);
        JsonObject doorOpen = world.block(with(Blocks.OAK_DOOR.defaultBlockState(),"open","true")); fixtures.add("door_open",doorOpen);
        check(!doorClosed.get("boxes").equals(doorOpen.get("boxes")),"open door collision changes orientation");
        JsonObject button = world.block(Blocks.OAK_BUTTON.defaultBlockState()); fixtures.add("button",button);
        check(button.getAsJsonArray("boxes").isEmpty() && button.get("visible").getAsBoolean(),"button is not dropped because it has no collision");
        JsonObject air = world.block(Blocks.AIR.defaultBlockState()); fixtures.add("air",air);
        check(air.get("op").getAsString().equals("remove"),"air removes mirrored state");
        JsonObject barrier = world.block(Blocks.BARRIER.defaultBlockState()); fixtures.add("barrier",barrier);
        check(barrier.get("op").getAsString().equals("remove") && !barrier.get("visible").getAsBoolean(),"host terrain proxy is never mirrored as material");
        BlockState moving = Blocks.MOVING_PISTON.defaultBlockState(); world.states.put(AT,moving);
        world.entities.put(AT,new PistonMovingBlockEntity(AT,moving,Blocks.OAK_PLANKS.defaultBlockState(),Direction.EAST,true,false));
        JsonObject piston = WorldStateCodec.block(world,AT,moving,null,false); fixtures.add("moving_piston",piston);
        JsonObject motion = piston.getAsJsonObject("block_entity").getAsJsonObject("motion");
        check(motion.getAsJsonObject("moved").get("id").getAsString().equals("minecraft:oak_planks"),"piston carries actual moved state");
        check(motion.get("extending").getAsBoolean() && motion.get("direction").getAsString().equals("east"),"piston direction and phase preserved");
        world.entities.clear(); ChestBlockEntity chest = new ChestBlockEntity(AT,Blocks.CHEST.defaultBlockState());
        chest.setItem(0,new ItemStack(Items.OAK_PLANKS,32)); world.entities.put(AT,chest);
        JsonObject container = world.block(Blocks.CHEST.defaultBlockState()); fixtures.add("chest",container);
        JsonObject summary = container.getAsJsonObject("block_entity").getAsJsonObject("container");
        check(summary.get("count").getAsInt()==32 && summary.get("occupied").getAsInt()==1,"container dirty event has correct summary");
        check(!container.getAsJsonObject("block_entity").has("items"),"world event does not broadcast private inventories");
        world.entities.clear(); world.states.put(AT.east(),Blocks.GLASS.defaultBlockState());
        JsonObject glass = world.block(Blocks.GLASS.defaultBlockState()); fixtures.add("glass_adjacent",glass);
        check(!glass.getAsJsonObject("face_visibility").get("east").getAsBoolean(),"vanilla glass skipRendering respected");
        world.states.put(AT.east(),Blocks.STONE.defaultBlockState());
        JsonObject occluded = world.block(Blocks.STONE.defaultBlockState());
        check(!occluded.getAsJsonObject("face_visibility").get("east").getAsBoolean(),"vanilla solid neighbor occlusion respected");
        JsonObject unknown = WorldStateCodec.block(world,AT,Blocks.STONE.defaultBlockState(),null,false,pos->pos.getX()<=0);
        check(unknown.getAsJsonObject("face_visibility").get("east").getAsBoolean() && unknown.getAsJsonArray("face_unknown").toString().contains("east"),"unloaded neighbor preserves face and flags uncertainty");
        Map<String,BlockState> palette=Map.of("wood",Blocks.OAK_PLANKS.defaultBlockState(),"stone",Blocks.STONE.defaultBlockState(),
            "glass",Blocks.GLASS.defaultBlockState(),"leaves",Blocks.OAK_LEAVES.defaultBlockState(),"slab",Blocks.OAK_SLAB.defaultBlockState(),
            "stairs",Blocks.OAK_STAIRS.defaultBlockState(),"fence",Blocks.OAK_FENCE.defaultBlockState());
        JsonObject visibilityPairs=new JsonObject();
        Map<String,BlockState> neighbors=new HashMap<>(palette);neighbors.put("air",Blocks.AIR.defaultBlockState());
        for(var own:palette.entrySet()) {
            JsonObject pair=new JsonObject();
            for(var neighbor:neighbors.entrySet()) {
                JsonObject faces=new JsonObject();
                for(Direction direction:Direction.values()) faces.addProperty(direction.getSerializedName(),Block.shouldRenderFace(own.getValue(),neighbor.getValue(),direction));
                pair.add(neighbor.getKey(),faces);
            }
            visibilityPairs.add(own.getKey(),pair);
        }
        // Verify our common-side fluid average against the actual private 26.3 renderer method, without rendering.
        Class<?> tintGetter=Class.forName("net.minecraft.client.renderer.block.BlockAndTintGetter");
        Object tintWorld=java.lang.reflect.Proxy.newProxyInstance(tintGetter.getClassLoader(),new Class<?>[]{tintGetter},(proxy,method,arguments)->{
            return switch(method.getName()) {
                case "getBlockState" -> world.getBlockState((BlockPos)arguments[0]);
                case "getFluidState" -> world.getFluidState((BlockPos)arguments[0]);
                case "getHeight" -> world.getHeight();
                case "getMinY" -> world.getMinY();
                default -> throw new UnsupportedOperationException(method.getName());
            };
        });
        Class<?> rendererType=Class.forName("net.minecraft.client.renderer.block.FluidRenderer");
        Object renderer=rendererType.getDeclaredConstructor(Class.forName("net.minecraft.client.renderer.block.FluidStateModelSet")).newInstance(new Object[]{null});
        var average=rendererType.getDeclaredMethod("calculateAverageHeight",tintGetter,net.minecraft.world.level.material.Fluid.class,float.class,float.class,float.class,BlockPos.class);
        average.setAccessible(true);
        for(float a:new float[]{0,5F/9F,8F/9F,1F,-1F}) for(float b:new float[]{0,3F/9F,8F/9F,1F,-1F}) {
            float expected=(Float)average.invoke(renderer,tintWorld,net.minecraft.world.level.material.Fluids.WATER,8F/9F,a,b,AT.north().east());
            float actual=WorldFluidSurface.average(world,net.minecraft.world.level.material.Fluids.WATER,8F/9F,a,b,AT.north().east());
            check(Float.compare(expected,actual)==0,"fluid renderer exact average "+a+" "+b);
        }
        var fluidOccluded=rendererType.getDeclaredMethod("isFaceOccludedByState",Direction.class,float.class,BlockState.class);fluidOccluded.setAccessible(true);
        var renderFace=rendererType.getDeclaredMethod("shouldRenderFace",FluidState.class,BlockState.class,Direction.class,FluidState.class);
        for(var entry:neighbors.entrySet()) for(Direction direction:Direction.values()) {
            for(float h:new float[]{0.5F,8F/9F,1.0F}) {
                boolean expected=(Boolean)fluidOccluded.invoke(null,direction,h,entry.getValue());
                check(expected==WorldFluidSurface.faceOccluded(direction,h,entry.getValue()),"fluid face occlusion oracle "+entry.getKey()+direction+h);
            }
            boolean expected=(Boolean)renderFace.invoke(null,Blocks.WATER.defaultBlockState().getFluidState(),entry.getValue(),direction,Blocks.AIR.defaultBlockState().getFluidState());
            check(expected==WorldFluidSurface.shouldRenderFace(Blocks.WATER.defaultBlockState().getFluidState(),entry.getValue(),direction,Blocks.AIR.defaultBlockState().getFluidState()),"fluid self occlusion oracle "+entry.getKey()+direction);
        }
        WorldDeltaBuffer queue = new WorldDeltaBuffer(2);
        var a = new WorldDeltaBuffer.Position("minecraft:overworld",-1,64,-1);
        var b = new WorldDeltaBuffer.Position("minecraft:the_nether",-1,64,-1);
        check(queue.mark(a,"block_state",1) && queue.mark(a,"block_entity_dirty",2),"same cell coalesces");
        check(queue.mark(b,"block_state",4) && queue.size()==2,"same coordinates in different dimensions remain distinct");
        check(!queue.mark(new WorldDeltaBuffer.Position("minecraft:overworld",2,64,0),"block_state",1),"bounded overflow is explicit");
        var first = queue.drain(1).getFirst();
        check(first.flags()==3 && first.causes().size()==2 && first.position().equals(a),"flags and causes retained on coalesced delta");
        queue.removeIf(pos->pos.dimension().equals("minecraft:the_nether"));
        check(queue.size()==0,"dimension/chunk unload can purge pending state");
        JsonObject output = new JsonObject(); output.addProperty("minecraft","26.3"); output.addProperty("checks",checks); output.add("samples",fixtures);
        output.add("face_visibility_pairs",visibilityPairs);output.addProperty("face_visibility_pair_count",336);
        if (args.length>0) Files.writeString(Path.of(args[0]),output.toString());
        System.out.println("WORLD_COMPAT_CODEC_OK checks="+checks);
    }
}
