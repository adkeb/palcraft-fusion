package dev.rehan.passthrough.client;

/** The same rotationYXZ(pi-yaw, -pitch, roll) basis used by CameraMixin. */
public final class GuideProjection {
    public record Camera(double x, double y, double z, double yaw, double pitch, double roll, double fov, double aspect) {
        public Camera(double x, double y, double z, double yaw, double pitch, double roll, double fov) {
            this(x, y, z, yaw, pitch, roll, fov, 0);
        }
        boolean valid() {
            return Double.isFinite(x) && Double.isFinite(y) && Double.isFinite(z)
                && Double.isFinite(yaw) && Double.isFinite(pitch) && Double.isFinite(roll)
                && Double.isFinite(fov) && fov > 1 && fov < 179
                && Double.isFinite(aspect) && (aspect == 0 || aspect >= .5 && aspect <= 4);
        }
    }
    private static final double NEAR = 0.08;
    private GuideProjection() {}

    private static double[] camera(Camera c, double x, double y, double z) {
        double yaw = Math.toRadians(c.yaw), pitch = Math.toRadians(c.pitch), roll = Math.toRadians(c.roll);
        double sy = Math.sin(yaw), cy = Math.cos(yaw), sp = Math.sin(pitch), cp = Math.cos(pitch);
        double dx = x - c.x, dy = y - c.y, dz = z - c.z;
        double r = -cy * dx - sy * dz;
        double u = -sy * sp * dx + cp * dy + cy * sp * dz;
        double f = -sy * cp * dx - sp * dy + cy * cp * dz;
        double cr = Math.cos(roll), sr = Math.sin(roll);
        return new double[]{cr * r + sr * u, -sr * r + cr * u, f};
    }
    private static double[] screen(Camera c, int width, int height, double[] point) {
        double scale = height / (2.0 * Math.tan(Math.toRadians(c.fov) / 2.0));
        double xScale = c.aspect > 0 ? scale * width / (height * c.aspect) : scale;
        return new double[]{width * .5 + point[0] / point[2] * xScale,
                            height * .5 - point[1] / point[2] * scale};
    }
    public static double[] project(Camera c, int width, int height, double x, double y, double z) {
        if (!c.valid() || width <= 0 || height <= 0) return null;
        double[] p = camera(c, x, y, z);
        return p[2] < NEAR ? null : screen(c, width, height, p);
    }
    /** Clip in camera space first, then clip the projected segment to the HUD viewport. */
    public static double[] segment(Camera c, int width, int height,
                                   double x0, double y0, double z0, double x1, double y1, double z1) {
        if (!c.valid() || width <= 0 || height <= 0) return null;
        double[] a = camera(c, x0, y0, z0), b = camera(c, x1, y1, z1);
        if (a[2] < NEAR && b[2] < NEAR) return null;
        if (a[2] < NEAR || b[2] < NEAR) {
            double t = (NEAR - a[2]) / (b[2] - a[2]);
            double[] cut = new double[]{a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]), NEAR};
            if (a[2] < NEAR) a = cut; else b = cut;
        }
        double[] p = screen(c, width, height, a), q = screen(c, width, height, b);
        if (!Double.isFinite(p[0]) || !Double.isFinite(p[1]) || !Double.isFinite(q[0]) || !Double.isFinite(q[1])) return null;
        double dx = q[0] - p[0], dy = q[1] - p[1], lo = 0, hi = 1;
        double[] denominators = {-dx, dx, -dy, dy};
        double[] distances = {p[0], width - 1 - p[0], p[1], height - 1 - p[1]};
        for (int i = 0; i < 4; i++) {
            double denominator = denominators[i], distance = distances[i];
            if (Math.abs(denominator) < 1e-12) { if (distance < 0) return null; continue; }
            double t = distance / denominator;
            if (denominator < 0) lo = Math.max(lo, t); else hi = Math.min(hi, t);
            if (lo > hi) return null;
        }
        return new double[]{p[0] + lo * dx, p[1] + lo * dy, p[0] + hi * dx, p[1] + hi * dy};
    }
}
