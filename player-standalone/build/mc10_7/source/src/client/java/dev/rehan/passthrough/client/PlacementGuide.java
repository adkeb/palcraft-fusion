package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import dev.rehan.passthrough.client.mixin.BlockItemPlacementAccessor;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.core.BlockPos;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.*;
import net.minecraft.world.phys.shapes.CollisionContext;
import java.util.List;

/** A read-only preview. Right click and the server remain the authority and consume items. */
final class PlacementGuide {
    private static final int SELECT = 0xccf0f7f4, VALID = 0xcc59edbc, INVALID = 0xccff6b6b;
    private static final long POSE_AGE = 150_000_000L;
    private record Preview(BlockPos pos, BlockState shape, boolean valid, String reason, InteractionHand hand) {}
    private static Preview latest;
    private static long latestNanos;

    static JsonObject feedback() {
        JsonObject result = new JsonObject();
        Preview p = System.nanoTime() - latestNanos < POSE_AGE ? latest : null;
        result.addProperty("visible", p != null);
        if (p != null) {
            result.addProperty("valid", p.valid);
            result.addProperty("reason", p.reason);
            result.addProperty("hand", p.hand.name());
            result.addProperty("x", p.pos.getX()); result.addProperty("y", p.pos.getY()); result.addProperty("z", p.pos.getZ());
        }
        return result;
    }
    static void draw(GuiGraphicsExtractor g) {
        latest = null;
        Minecraft mc = Minecraft.getInstance();
        HostState.Pose pose = HostState.frame();
        if (!ClientInput.buildMode || pose == null || System.nanoTime() - pose.receivedNanos() > POSE_AGE ||
            mc.player == null || mc.level == null || mc.gameMode == null || mc.gui.screen() != null ||
            !(mc.hitResult instanceof BlockHitResult hit) || hit.getType() != HitResult.Type.BLOCK) return;
        GuideProjection.Camera camera = new GuideProjection.Camera(pose.x(), pose.y(), pose.z(),
            pose.yaw(), pose.pitch(), pose.roll(), pose.fov(), PlayFeedback.viewportAspect());
        BlockState selected = mc.level.getBlockState(hit.getBlockPos());
        if (!selected.isAir() && !selected.is(Blocks.BARRIER))
            boxes(g, camera, hit.getBlockPos(), selected.getShape(mc.level, hit.getBlockPos(), CollisionContext.of(mc.player)).toAabbs(), SELECT);

        InteractionHand hand = mc.player.getMainHandItem().getItem() instanceof BlockItem ?
            InteractionHand.MAIN_HAND : InteractionHand.OFF_HAND;
        var stack = mc.player.getItemInHand(hand);
        if (stack.isEmpty() || !(stack.getItem() instanceof BlockItem item)) return;
        BlockPlaceContext original = new BlockPlaceContext(mc.player, hand, stack, hit);
        BlockPlaceContext context = item.updatePlacementContext(original);
        BlockPos pos = context == null ? original.getClickedPos() : context.getClickedPos();
        String reason = "";
        boolean allowed = original.canPlace() && context != null && context.canPlace();
        if (!allowed) reason = "目标无法替换";
        else if (!item.getBlock().isEnabled(mc.level.enabledFeatures())) { allowed = false; reason = "方块尚未启用"; }
        else if (mc.level.isOutsideBuildHeight(pos) || !mc.level.getWorldBorder().isWithinBounds(pos)) { allowed = false; reason = "超出建造范围"; }
        else if (!mc.level.mayInteract(mc.player, pos)) { allowed = false; reason = "该区域无法建造"; }
        else if (mc.player.blockActionRestricted(mc.level, hit.getBlockPos(), mc.gameMode.getPlayerMode())) { allowed = false; reason = "当前模式无法建造"; }
        BlockState state = context == null ? null : ((BlockItemPlacementAccessor)item).palcraft$placementState(context);
        if (allowed && state == null) { allowed = false; reason = "支撑或碰撞阻挡"; }
        // Invalid previews still use the candidate shape, without placing or consuming anything.
        BlockState shape = state != null ? state : context == null ? null : item.getBlock().getStateForPlacement(context);
        latest = new Preview(pos.immutable(), shape, allowed, reason, hand);
        latestNanos = System.nanoTime();
        int color = allowed ? VALID : INVALID;
        List<AABB> outlines = shape == null ? List.of() : shape.getShape(mc.level, pos, CollisionContext.of(mc.player)).toAabbs();
        if (outlines.isEmpty()) outlines = List.of(new AABB(0, 0, 0, 1, 1, 1));
        boxes(g, camera, pos, outlines, color);
        String label = allowed ? (mc.player.getAbilities().instabuild ? "右键放置" : "右键放置 · 消耗 1 个") : "无法放置 · " + reason;
        g.centeredText(mc.font, label, g.guiWidth() / 2, g.guiHeight() / 2 + 18, color | 0xff000000);
    }
    private static void boxes(GuiGraphicsExtractor g, GuideProjection.Camera camera, BlockPos pos, List<AABB> boxes, int color) {
        for (AABB b : boxes) {
            double[][] vertices = new double[8][3];
            for (int i = 0; i < 8; i++) vertices[i] = new double[]{
                pos.getX() + ((i & 1) == 0 ? b.minX : b.maxX),
                pos.getY() + ((i & 2) == 0 ? b.minY : b.maxY),
                pos.getZ() + ((i & 4) == 0 ? b.minZ : b.maxZ)};
            for (int i = 0; i < 8; i++) for (int axis : new int[]{1, 2, 4}) if ((i & axis) == 0) {
                double[] a = vertices[i], z = vertices[i | axis];
                double[] line = GuideProjection.segment(camera, g.guiWidth(), g.guiHeight(), a[0], a[1], a[2], z[0], z[1], z[2]);
                if (line != null) line(g, line, color);
            }
        }
    }
    private static void line(GuiGraphicsExtractor g, double[] line, int color) {
        double dx = line[2] - line[0], dy = line[3] - line[1], length = Math.hypot(dx, dy);
        if (length < .05) return;
        var pose = g.pose();
        pose.pushMatrix(); pose.translate((float)line[0], (float)line[1]); pose.rotate((float)Math.atan2(dy, dx));
        g.fill(0, 0, (int)Math.ceil(length), 1, color);
        pose.popMatrix();
    }
    private PlacementGuide() {}
}
