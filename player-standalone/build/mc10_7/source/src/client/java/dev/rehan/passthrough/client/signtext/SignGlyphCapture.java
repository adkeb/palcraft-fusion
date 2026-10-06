package dev.rehan.passthrough.client.signtext;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Transformation;
import com.mojang.renderpearl.api.textures.GpuTexture;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Set;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.font.PlainTextRenderable;
import net.minecraft.client.gui.font.TextRenderable;
import net.minecraft.client.renderer.blockentity.AbstractSignRenderer;
import net.minecraft.client.renderer.blockentity.state.SignRenderState;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.world.item.DyeColor;
import net.minecraft.world.level.block.entity.SignText;
import org.joml.Matrix4f;

/** Replay the exact MC26.3 AbstractSignRenderer and TextFeatureRenderer text
 * submission, capturing the renderer's actual glyph/effect quads. */
final class SignGlyphCapture {
    record Surface(JsonObject metadata, SignGlyphRaster.Bounds bounds,
                   List<SignGlyphRaster.Quad> quads, int light) {}
    final IdentityHashMap<GpuTexture, Integer> atlasIds = new IdentityHashMap<>();
    final ArrayList<GpuTexture> textures = new ArrayList<>();
    final Set<GpuTexture> dynamicTextures = java.util.Collections.newSetFromMap(new IdentityHashMap<>());

    int texture(GpuTexture texture) {
        Integer known = atlasIds.get(texture);
        if (known != null) return known;
        if (textures.size() >= 32) throw new IllegalStateException("sign font atlas limit");
        int id = textures.size(); textures.add(texture); atlasIds.put(texture, id); return id;
    }

    Surface face(Font font, SignRenderState state, SignText text, Transformation transform) {
        JsonObject meta = new JsonObject();
        JsonArray matrix = new JsonArray();
        for (float value : transform.getMatrix().get(new float[16])) matrix.add(value);
        meta.add("transform", matrix);
        // Fixed size across edits, with margins for vanilla bold/italic/outline.
        int halfWidth = (state.maxTextLineWidth + 1) / 2, halfHeight = 4 * state.textLineHeight / 2;
        var bounds = new SignGlyphRaster.Bounds(-halfWidth - 8, -halfHeight - 8, halfWidth + 8, halfHeight + 8);
        JsonArray pixels = new JsonArray();
        pixels.add(bounds.left()); pixels.add(bounds.top()); pixels.add(bounds.right()); pixels.add(bounds.bottom());
        meta.add("pixel_bounds", pixels);
        int dark = AbstractSignRenderer.getDarkColor(text);
        boolean glowing = text.hasGlowingText();
        int color = glowing ? text.getColor().getTextColor() : dark;
        boolean outline = glowing && (color == DyeColor.BLACK.getTextColor() || state.drawOutline);
        int light = glowing ? 15728880 : state.lightCoords;
        meta.addProperty("glowing", glowing); meta.addProperty("outline", outline);
        meta.addProperty("dye", text.getColor().getSerializedName());
        meta.addProperty("minecraft_color", color); meta.addProperty("light_coords", light);
        meta.addProperty("filtered", state.isTextFilteringEnabled);
        meta.addProperty("light_baked", true); meta.addProperty("alpha", "straight");
        var quads = new ArrayList<SignGlyphRaster.Quad>();
        FormattedCharSequence[] lines = text.getRenderMessages(state.isTextFilteringEnabled, component -> {
            List<FormattedCharSequence> split = font.split(component, state.maxTextLineWidth);
            return split.isEmpty() ? FormattedCharSequence.EMPTY : split.getFirst();
        });
        boolean[] obfuscated = {false};
        boolean[] dynamic = {false};
        for (int line = 0; line < lines.length; line++) {
            FormattedCharSequence sequence = lines[line];
            sequence.accept((index, style, codepoint) -> { obfuscated[0] |= style.isObfuscated(); return true; });
            // Deliberately integer division: odd-width MC lines centre at integer X.
            float x = -font.width(sequence) / 2, y = line * state.textLineHeight - halfHeight;
            Font.GlyphVisitor visitor = new Font.GlyphVisitor() {
                @Override public void acceptRenderable(TextRenderable glyph) {
                    int atlas = texture(glyph.textureView().texture());
                    if (glyph instanceof PlainTextRenderable) {
                        dynamicTextures.add(glyph.textureView().texture()); dynamic[0] = true;
                    }
                    Sink sink = new Sink();
                    glyph.render(new Matrix4f(), sink, light, false);
                    sink.append(atlas, quads);
                }
            };
            if (outline) font.prepare8xTextOutline(sequence, x, y, dark).visit(visitor);
            font.prepareText(sequence, x, y, color, false, false, 0).visit(visitor);
        }
        meta.addProperty("obfuscated", obfuscated[0]);
        meta.addProperty("dynamic_atlas", dynamic[0]);
        // Resource-pack glyphs can extend farther than their advance/line height.
        // Expand the same four-vertex plane rather than silently cropping them.
        int left = bounds.left(), top = bounds.top(), right = bounds.right(), bottom = bounds.bottom();
        for (var q : quads) for (var v : List.of(q.a(), q.b(), q.c(), q.d())) {
            left = Math.min(left, (int)Math.floor(v.x()) - 1); top = Math.min(top, (int)Math.floor(v.y()) - 1);
            right = Math.max(right, (int)Math.ceil(v.x()) + 1); bottom = Math.max(bottom, (int)Math.ceil(v.y()) + 1);
        }
        bounds = new SignGlyphRaster.Bounds(left, top, right, bottom);
        pixels = new JsonArray(); pixels.add(left); pixels.add(top); pixels.add(right); pixels.add(bottom); meta.add("pixel_bounds", pixels);
        return new Surface(meta, bounds, List.copyOf(quads), light);
    }

    private static final class Point {
        float x, y, u, v; int color = 0xffffffff;
        SignGlyphRaster.Vertex freeze() { return new SignGlyphRaster.Vertex(x, y, u, v, color); }
    }
    private static final class Sink implements VertexConsumer {
        private final ArrayList<Point> points = new ArrayList<>();
        private Point point;
        @Override public VertexConsumer addVertex(float x, float y, float z) {
            if (!Float.isFinite(x) || !Float.isFinite(y) || !Float.isFinite(z) || points.size() >= 65536)
                throw new IllegalStateException("sign glyph vertex limit");
            point = new Point(); point.x = x; point.y = y; points.add(point); return this;
        }
        @Override public VertexConsumer setColor(int r, int g, int b, int a) { return setColor(a << 24 | r << 16 | g << 8 | b); }
        @Override public VertexConsumer setColor(int color) { point.color = color; return this; }
        @Override public VertexConsumer setUv(float u, float v) { point.u = u; point.v = v; return this; }
        @Override public VertexConsumer setUv1(int u, int v) { return this; }
        @Override public VertexConsumer setUv2(int u, int v) { return this; }
        @Override public VertexConsumer setUv3(float u, float v) { return this; }
        @Override public VertexConsumer setNormal(float x, float y, float z) { return this; }
        @Override public VertexConsumer setLineWidth(float width) { return this; }
        void append(int atlas, List<SignGlyphRaster.Quad> output) {
            if (points.size() % 4 != 0) throw new IllegalStateException("non-quad MC glyph");
            for (int i = 0; i < points.size(); i += 4)
                output.add(new SignGlyphRaster.Quad(atlas, points.get(i).freeze(), points.get(i + 1).freeze(),
                    points.get(i + 2).freeze(), points.get(i + 3).freeze()));
        }
    }
}
