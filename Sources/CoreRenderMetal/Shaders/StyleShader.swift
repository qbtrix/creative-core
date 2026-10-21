// StyleShader.swift: the MSL of a layer style's shadow and glow layers (layer-style-engine LE-9a), CoreRaster's
// `lightLayer` over whole-image float4 buffers. `style_pad` spreads the alpha on the distance field (choke > 0 only)
// and pads it with the outside value for the box blur; `style_light` reads that mask bilinearly at (x - dx, y - dy)
// and tints it, an outer one knocked out by the alpha. Distances are clamped to 1e30 before use, so no infinity
// reaches arithmetic. Grids may round up; every kernel bounds-checks.
#if canImport(Metal)
import CoreRender

enum StyleShader {
    /// The kernels' variants, for the warmup.
    static let variants = ["pad", "light"]

    /// The pipeline key of `variant`.
    static func key(_ variant: String) -> PipelineKey { PipelineKey(op: .style, variant: variant) }

    /// Buffers 0, 1, 2 as `styleDispatch` binds them; ints at 3, the float at 4, the float table at 5.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    constant float style_far = 1e30;
    kernel void style_pad(device const float4 *in [[buffer(0)]], device const float *field [[buffer(1)]],
                          device float4 *out [[buffer(2)]], constant int *p [[buffer(3)]],
                          constant float &choke [[buffer(4)]], uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pad = p[2], pw = w + 2 * pad;
        if (int(gid.x) >= pw || int(gid.y) >= h + 2 * pad) { return; }
        int x = int(gid.x) - pad, y = int(gid.y) - pad;
        bool inner = p[3] != 0;
        float v = inner ? 1.0 : 0.0;
        if (x >= 0 && y >= 0 && x < w && y < h) {
            float a = in[y * w + x].w;
            if (p[4] != 0) {
                float grown = clamp(choke - min(field[y * w + x], style_far) + 1.0f, 0.0f, 1.0f);
                a = inner ? min(a, 1.0f - grown) : max(a, grown);
            }
            a = clamp(a, 0.0f, 1.0f);
            v = inner ? 1.0f - a : a;
        }
        out[int(gid.y) * pw + int(gid.x)] = float4(v);
    }
    static float style_tap(device const float4 *mask, int pw, int ph, float outside, int x, int y) {
        return (x >= 0 && y >= 0 && x < pw && y < ph) ? mask[y * pw + x].w : outside;
    }
    kernel void style_light(device const float4 *in [[buffer(0)]], device const float4 *mask [[buffer(1)]],
                            device float4 *out [[buffer(2)]], constant int *p [[buffer(3)]],
                            constant float *f [[buffer(5)]], uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pad = p[2], x = int(gid.x), y = int(gid.y);
        if (x >= w || y >= h) { return; }
        int pw = w + 2 * pad, ph = h + 2 * pad;
        float outside = p[3] != 0 ? 1.0 : 0.0, cover = outside;
        float px = float(x) - f[0] + float(pad), py = float(y) - f[1] + float(pad);
        if (px > -1 && py > -1 && px < float(pw) && py < float(ph)) {
            float fx = floor(px), fy = floor(py), wx = px - fx, wy = py - fy;
            int x0 = int(fx), y0 = int(fy);
            float top = mix(style_tap(mask, pw, ph, outside, x0, y0), style_tap(mask, pw, ph, outside, x0 + 1, y0), wx);
            float low = mix(style_tap(mask, pw, ph, outside, x0, y0 + 1), style_tap(mask, pw, ph, outside, x0 + 1, y0 + 1), wx);
            cover = mix(top, low, wy);
        }
        if (p[3] == 0) { cover *= 1.0f - clamp(in[y * w + x].w, 0.0f, 1.0f); }
        out[y * w + x] = cover > 0 ? float4(f[2], f[3], f[4], f[5]) * cover : float4(0);
    }
    """
}
#endif
