package dev.rehan.passthrough.client.signtext;

import java.awt.image.BufferedImage;
import java.util.List;

/** CPU equivalent of Minecraft's nearest sampled text shader, before fog.
 * Input geometry, atlas pixels and vertex colours come from the live MC Font.
 * This class has no Minecraft, GL, font substitution, or sign editing code. */
public final class SignGlyphRaster {
    public record Vertex(double x, double y, double u, double v, int argb) {}
    public record Quad(int atlas, Vertex a, Vertex b, Vertex c, Vertex d) {}
    public record Bounds(int left, int top, int right, int bottom) {
        public Bounds {
            if (right <= left || bottom <= top || right - left > 512 || bottom - top > 256)
                throw new IllegalArgumentException("sign text bounds");
        }
    }
    /** Texture row zero is the same row addressed by MC's UV v=0. */
    public record Atlas(int width, int height, boolean grayscale, byte[] pixels) {
        public Atlas {
            if (width < 1 || height < 1 || width > 4096 || height > 4096
                || pixels.length != (long)width * height * (grayscale ? 1 : 4))
                throw new IllegalArgumentException("font atlas");
        }
        int sample(double u, double v) {
            int x = Math.floorMod((int)Math.floor(u * width), width);
            int y = Math.floorMod((int)Math.floor(v * height), height);
            int i = y * width + x;
            if (grayscale) {
                int r = pixels[i] & 255;
                // text.fsh IS_GRAYSCALE samples .rrrr, including RGB intensity.
                return r << 24 | r << 16 | r << 8 | r;
            }
            i *= 4;
            return (pixels[i + 3] & 255) << 24 | (pixels[i] & 255) << 16
                | (pixels[i + 1] & 255) << 8 | (pixels[i + 2] & 255);
        }
    }

    private SignGlyphRaster() {}

    public static BufferedImage render(Bounds bounds, int scale, List<Atlas> atlases,
                                       List<Quad> quads, float[] lightRgb) {
        if (scale < 1 || scale > 8 || quads.size() > 16384 || lightRgb.length != 3)
            throw new IllegalArgumentException("sign raster limits");
        for (float value : lightRgb) if (!Float.isFinite(value) || value < 0 || value > 1)
            throw new IllegalArgumentException("lightmap sample");
        int width = (bounds.right - bounds.left) * scale, height = (bounds.bottom - bounds.top) * scale;
        int[] output = new int[width * height];
        double[] weights = new double[3];
        for (Quad q : quads) {
            Atlas atlas = atlases.get(q.atlas);
            int x0 = Math.max(0, (int)Math.floor((minimumX(q) - bounds.left) * scale));
            int x1 = Math.min(width, (int)Math.ceil((maximumX(q) - bounds.left) * scale));
            int y0 = Math.max(0, (int)Math.floor((minimumY(q) - bounds.top) * scale));
            int y1 = Math.min(height, (int)Math.ceil((maximumY(q) - bounds.top) * scale));
            for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) {
                double px = bounds.left + (x + .5) / scale, py = bounds.top + (y + .5) / scale;
                Vertex a = q.a, b = q.b, c = q.c;
                // One quad pixel is blended exactly once, including its diagonal.
                if (!barycentric(px, py, a, b, c, weights)) {
                    b = q.c; c = q.d;
                    if (!barycentric(px, py, a, b, c, weights)) continue;
                }
                double u = a.u * weights[0] + b.u * weights[1] + c.u * weights[2];
                double v = a.v * weights[0] + b.v * weights[1] + c.v * weights[2];
                int texel = atlas.sample(u, v);
                double alpha = channel(texel, 24) * interpolate(a, b, c, weights, 24) / (255 * 255.0);
                if (alpha < .1) continue; // exact vanilla text.fsh discard threshold
                double red = channel(texel, 16) * interpolate(a, b, c, weights, 16) * lightRgb[0] / (255 * 255.0);
                double green = channel(texel, 8) * interpolate(a, b, c, weights, 8) * lightRgb[1] / (255 * 255.0);
                double blue = channel(texel, 0) * interpolate(a, b, c, weights, 0) * lightRgb[2] / (255 * 255.0);
                int index = y * width + x;
                output[index] = over(output[index], red, green, blue, alpha);
            }
        }
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
        image.setRGB(0, 0, width, height, output, 0, width);
        return image;
    }

    /** sample_lightmap.glsl at vanilla packed light coordinates. Lightmap UVs
     * address texel centres; the runtime lightmap uses a bilinear sampler. */
    public static float[] light(Atlas atlas, int packedLight) {
        if (atlas.grayscale) throw new IllegalArgumentException("RGBA lightmap required");
        double tx = Math.max(.5, Math.min(15.5, (packedLight & 65535) / 16.0 + .5)) / 16 * atlas.width - .5;
        double ty = Math.max(.5, Math.min(15.5, (packedLight >>> 16) / 16.0 + .5)) / 16 * atlas.height - .5;
        int x = (int)Math.floor(tx), y = (int)Math.floor(ty);
        float[] result = new float[3];
        for (int channel = 0; channel < 3; channel++) {
            double top = lightChannel(atlas, x, y, channel) * (1 - (tx - x)) + lightChannel(atlas, x + 1, y, channel) * (tx - x);
            double bottom = lightChannel(atlas, x, y + 1, channel) * (1 - (tx - x)) + lightChannel(atlas, x + 1, y + 1, channel) * (tx - x);
            result[channel] = (float)((top * (1 - (ty - y)) + bottom * (ty - y)) / 255.0);
        }
        return result;
    }

    private static int lightChannel(Atlas a, int x, int y, int channel) {
        x = Math.max(0, Math.min(a.width - 1, x)); y = Math.max(0, Math.min(a.height - 1, y));
        return a.pixels[(y * a.width + x) * 4 + channel] & 255;
    }
    private static double interpolate(Vertex a, Vertex b, Vertex c, double[] w, int shift) {
        return channel(a.argb, shift) * w[0] + channel(b.argb, shift) * w[1] + channel(c.argb, shift) * w[2];
    }
    private static int channel(int value, int shift) { return value >>> shift & 255; }
    private static int byteValue(double value) { return Math.max(0, Math.min(255, (int)Math.round(value * 255))); }
    private static int over(int dst, double r, double g, double b, double alpha) {
        double da = channel(dst, 24) / 255.0, outA = alpha + da * (1 - alpha);
        if (outA <= 0) return 0;
        double tail = da * (1 - alpha);
        return byteValue(outA) << 24
            | byteValue((r * alpha + channel(dst, 16) / 255.0 * tail) / outA) << 16
            | byteValue((g * alpha + channel(dst, 8) / 255.0 * tail) / outA) << 8
            | byteValue((b * alpha + channel(dst, 0) / 255.0 * tail) / outA);
    }
    private static boolean barycentric(double x, double y, Vertex a, Vertex b, Vertex c, double[] w) {
        double det = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
        if (!Double.isFinite(det) || Math.abs(det) < 1e-12) return false;
        w[0] = ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / det;
        w[1] = ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / det;
        w[2] = 1 - w[0] - w[1];
        return w[0] >= -1e-9 && w[1] >= -1e-9 && w[2] >= -1e-9;
    }
    private static double minimumX(Quad q) { return Math.min(Math.min(q.a.x, q.b.x), Math.min(q.c.x, q.d.x)); }
    private static double maximumX(Quad q) { return Math.max(Math.max(q.a.x, q.b.x), Math.max(q.c.x, q.d.x)); }
    private static double minimumY(Quad q) { return Math.min(Math.min(q.a.y, q.b.y), Math.min(q.c.y, q.d.y)); }
    private static double maximumY(Quad q) { return Math.max(Math.max(q.a.y, q.b.y), Math.max(q.c.y, q.d.y)); }
}
