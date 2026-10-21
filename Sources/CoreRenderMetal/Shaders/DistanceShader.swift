// DistanceShader.swift: the jump-flood MSL (layer-style-engine LE-8) behind a layer style's distance field. One int4
// per pixel carries two nearest seeds: xy the nearest shape pixel (alpha >= level), zw the nearest non-shape pixel,
// -1 for none. `style_jfa_seed` seeds them, `style_jfa_step` is one jump-flood step of size p[2] (the 3 x 3 taps
// k apart, off-image taps skipped), and `style_jfa_distance` turns the seeds into CoreRaster `DistanceField`'s two
// fields: outside +infinity with no seed, inside also bounded by the transparent ring just past the edge
// (min(x + 1, w - x, y + 1, h - y)). Squared distances are summed in float, so no int overflows. Grids may round up.
#if canImport(Metal)
import CoreRender

enum DistanceShader {
    static let seed = PipelineKey(op: .style, variant: "jfa_seed")
    static let step = PipelineKey(op: .style, variant: "jfa_step")
    static let distance = PipelineKey(op: .style, variant: "jfa_distance")

    /// Buffer 0 is the pixels (float4) for `seed` and the seeds (int4) for the others; `seed` and `step` write int4
    /// seeds to buffer 1, `distance` writes float outside and inside fields to buffers 1 and 2. Ints at buffer 3:
    /// width, height, then the step size (`step`); the level is a float at buffer 4 (`seed`).
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    static float jfa_squared(int2 p, int2 s) {
        float dx = float(p.x - s.x), dy = float(p.y - s.y);
        return dx * dx + dy * dy;
    }
    kernel void style_jfa_seed(device const float4 *in [[buffer(0)]],
                               device int4 *out [[buffer(1)]],
                               constant int *p [[buffer(3)]],
                               constant float &level [[buffer(4)]],
                               uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        if (x >= p[0] || y >= p[1]) { return; }
        bool shape = in[y * p[0] + x].w >= level;
        out[y * p[0] + x] = shape ? int4(x, y, -1, -1) : int4(-1, -1, x, y);
    }
    kernel void style_jfa_step(device const int4 *in [[buffer(0)]],
                               device int4 *out [[buffer(1)]],
                               constant int *p [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y), k = p[2];
        if (x >= p[0] || y >= p[1]) { return; }
        int2 at = int2(x, y);
        int4 best = in[y * p[0] + x];
        float shape = best.x < 0 ? as_type<float>(0x7f800000u) : jfa_squared(at, best.xy);
        float other = best.z < 0 ? as_type<float>(0x7f800000u) : jfa_squared(at, best.zw);
        for (int dy = -k; dy <= k; dy += k) {
            for (int dx = -k; dx <= k; dx += k) {
                int qx = x + dx, qy = y + dy;
                if (qx < 0 || qy < 0 || qx >= p[0] || qy >= p[1]) { continue; }
                int4 c = in[qy * p[0] + qx];
                if (c.x >= 0) {
                    float d = jfa_squared(at, c.xy);
                    if (d < shape) { shape = d; best.xy = c.xy; }
                }
                if (c.z >= 0) {
                    float d = jfa_squared(at, c.zw);
                    if (d < other) { other = d; best.zw = c.zw; }
                }
            }
        }
        out[y * p[0] + x] = best;
    }
    kernel void style_jfa_distance(device const int4 *in [[buffer(0)]],
                                   device float *outside [[buffer(1)]],
                                   device float *inside [[buffer(2)]],
                                   constant int *p [[buffer(3)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y);
        if (x >= p[0] || y >= p[1]) { return; }
        int2 at = int2(x, y);
        int4 s = in[y * p[0] + x];
        float none = as_type<float>(0x7f800000u);
        outside[y * p[0] + x] = s.x < 0 ? none : sqrt(jfa_squared(at, s.xy));
        float ring = float(min(min(x + 1, p[0] - x), min(y + 1, p[1] - y)));
        inside[y * p[0] + x] = s.z < 0 ? ring : min(ring, sqrt(jfa_squared(at, s.zw)));
    }
    """
}
#endif
