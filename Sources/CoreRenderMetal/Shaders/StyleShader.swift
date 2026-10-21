// StyleShader.swift: the MSL of a layer style's light layers (layer-style-engine LE-9a, LE-9a2), CoreRaster's `styleLayers`
// over whole-image float4 buffers. `style_pad` spreads the alpha on the distance field (choke > 0 only) and pads it
// with the outside value for the glows' box blur; `style_light` reads that mask bilinearly at (x - dx, y - dy) and
// tints it (an outer one knocked out by the alpha); `style_edge_seed` seeds the anti-aliased edge points of a copy
// padded by 1 px for the jump flood, and `style_stroke` turns the nearest seeds into the stroke's smoothstep cover of
// the fill; `style_bevel_height` raises the signed distance through the shape's rise and profile, and
// `style_bevel_light` leans its central-difference normal toward the light into highlight and shadow (LE-9a2);
// `style_composite` puts one layer on the canvas in place with the blend shaders' B(Cb, Cs), as CoreRaster's
// `sourceOver`, or clipped to the layer's alpha as `compositeClipped` (LE-9b). Distances are clamped to 1e30 before
// use, so no infinity reaches arithmetic. Grids may round up; every kernel bounds-checks.
#if canImport(Metal)
import CoreRaster
import CoreRender

enum StyleShader {
    /// The kernels' variants, for the warmup.
    static let variants = ["pad", "light", "edge_seed", "stroke", "bevel_height", "bevel_light", "composite"]

    /// The pipeline key of `variant`.
    static func key(_ variant: String) -> PipelineKey { PipelineKey(op: .style, variant: variant) }

    /// The index `style_composite` takes for `mode`: its place in `BlendMode.allCases`.
    static func modeIndex(_ mode: BlendMode) -> Int { BlendMode.allCases.firstIndex(of: mode) ?? 0 }

    /// The blend shaders' B(Cb, Cs) (their source opens with the include), the light kernels and the composite.
    static let source = BlendSeparableShader.functions + BlendNonSeparableShader.functions + kernels + composite

    /// B(Cb, Cs) for a `modeIndex`: Cs for `.normal`, per channel for a separable mode, on the colour otherwise.
    static let blend = "static float3 style_blend(int mode, float3 cb, float3 cs) {\n    switch (mode) {\n"
        + BlendSeparableShader.modes.map { m in
            let f = "blend_\(m.rawValue)"
            return "    case \(modeIndex(m)): return float3(\(f)(cb.r, cs.r), \(f)(cb.g, cs.g), \(f)(cb.b, cs.b));\n"
        }.joined()
        + BlendNonSeparableShader.modes.map { "    case \(modeIndex($0)): return blend_\($0.rawValue)(cb, cs);\n" }.joined()
        + "    default: return cs;\n    }\n}\n"

    /// `style_over` is `sourceOver`; `style_composite` puts buffer 1 at `opacity` onto the canvas (buffer 0) in
    /// place, with ints w, h, `modeIndex` and 1 to clip to buffer 2's alpha as `compositeClipped` does.
    static let composite = blend + """
    static float4 style_over(float4 src, float4 b, int mode, float opacity) {
        float4 s = src * opacity;
        float3 cs = s.a != 0.0f ? s.rgb / s.a : float3(0.0f), cb = b.a != 0.0f ? b.rgb / b.a : float3(0.0f);
        float3 blended = mode == 0 ? cs : style_blend(mode, cb, cs);
        float keep = 1.0f - s.a;
        return float4((cs + b.a * (blended - cs)) * s.a + b.rgb * keep, s.a + b.a * keep);
    }
    kernel void style_composite(device float4 *canvas [[buffer(0)]], device const float4 *src [[buffer(1)]],
                                device const float4 *clip [[buffer(2)]], constant int *p [[buffer(3)]],
                                constant float &opacity [[buffer(4)]], uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], x = int(gid.x), y = int(gid.y), i = y * w + x;
        if (x >= w || y >= p[1]) { return; }
        float4 d = canvas[i], s = src[i];
        if (p[3] == 0) { canvas[i] = style_over(s, d, p[2], opacity); return; }
        float inside = clamp(clip[i].w, 0.0f, 1.0f);
        if (inside <= 0) { return; }
        float alpha = d.a;
        float3 straight = alpha > 0 ? d.rgb / alpha : float3(0.0f);
        float4 opaque = float4(select(float3(0.0f), straight, isfinite(straight)), 1.0f);
        float4 blended = style_over(s, opaque, p[2], opacity);
        float covered = min(alpha, inside), hole = max(inside - alpha, 0.0f) * opacity;
        canvas[i] = float4(covered * blended.rgb + (alpha - covered) * opaque.rgb + hole * s.rgb, alpha + hole * s.a);
    }

    """

    /// Buffers 0, 1, 2 then 6, 7 as `styleDispatch` binds them; ints at 3, the float at 4, the float table at 5.
    static let kernels = """
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
    static float style_edge_alpha(device const float4 *in, int w, int h, int x, int y) {
        int ix = x - 1, iy = y - 1;
        return (ix >= 0 && iy >= 0 && ix < w && iy < h) ? clamp(in[iy * w + ix].w, 0.0f, 1.0f) : 0.0f;
    }
    static float style_edge_offset(float alpha, float gx, float gy) {
        float u = max(gx, gy), v = min(gx, gy), a1 = 0.5 * v / u;
        if (alpha < a1) { return 0.5 * (u + v) - sqrt(2 * u * v * alpha); }
        if (alpha < 1 - a1) { return (0.5 - alpha) * u; }
        return -0.5 * (u + v) + sqrt(2 * u * v * (1 - alpha));
    }
    kernel void style_edge_seed(device const float4 *in [[buffer(0)]], device int4 *seeds [[buffer(1)]],
                                device float4 *points [[buffer(2)]], constant int *p [[buffer(3)]],
                                uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pw = w + 2, x = int(gid.x), y = int(gid.y), i = y * pw + x;
        if (x >= pw || y >= h + 2) { return; }
        float v = style_edge_alpha(in, w, h, x, y), opposite = v >= 1 ? 0.0 : 1.0;
        bool seed = (v > 0 && v < 1) || style_edge_alpha(in, w, h, x - 1, y) == opposite
            || style_edge_alpha(in, w, h, x + 1, y) == opposite || style_edge_alpha(in, w, h, x, y - 1) == opposite
            || style_edge_alpha(in, w, h, x, y + 1) == opposite;
        if (!seed) { seeds[i] = int4(-1); points[i] = float4(0); return; }
        float r2 = sqrt(2.0);
        float gx = style_edge_alpha(in, w, h, x + 1, y - 1) + r2 * style_edge_alpha(in, w, h, x + 1, y)
            + style_edge_alpha(in, w, h, x + 1, y + 1) - style_edge_alpha(in, w, h, x - 1, y - 1)
            - r2 * style_edge_alpha(in, w, h, x - 1, y) - style_edge_alpha(in, w, h, x - 1, y + 1);
        float gy = style_edge_alpha(in, w, h, x - 1, y + 1) + r2 * style_edge_alpha(in, w, h, x, y + 1)
            + style_edge_alpha(in, w, h, x + 1, y + 1) - style_edge_alpha(in, w, h, x - 1, y - 1)
            - r2 * style_edge_alpha(in, w, h, x, y - 1) - style_edge_alpha(in, w, h, x + 1, y - 1);
        float g = sqrt(gx * gx + gy * gy);
        float d = g > 0 ? style_edge_offset(v, abs(gx) / g, abs(gy) / g) / g : 0.0;
        seeds[i] = int4(x, y, -1, -1);
        points[i] = float4(float(x) + d * gx, float(y) + d * gy, 1, 0);
    }
    static float style_cover(float edge, float width) {
        float t = clamp(width + 0.5f - edge, 0.0f, 1.0f);
        return t * t * (3 - 2 * t);
    }
    kernel void style_stroke(device const int4 *seeds [[buffer(0)]], device const float4 *points [[buffer(1)]],
                             device float4 *paint [[buffer(2)]], constant int *p [[buffer(3)]],
                             constant float &width [[buffer(4)]], device const float4 *in [[buffer(6)]],
                             uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pw = w + 2, ph = h + 2, x = int(gid.x), y = int(gid.y);
        if (x >= w || y >= h) { return; }
        int4 n = seeds[(y + 1) * pw + x + 1];
        float best = style_far;
        if (n.x >= 0) {
            for (int qy = max(n.y - 1, 0); qy <= min(n.y + 1, ph - 1); qy++) {
                for (int qx = max(n.x - 1, 0); qx <= min(n.x + 1, pw - 1); qx++) {
                    float4 q = points[qy * pw + qx];
                    if (q.z > 0) { best = min(best, length(float2(x + 1, y + 1) - q.xy)); }
                }
            }
        }
        float alpha = in[y * w + x].w, cover;
        bool shape = alpha >= 0.5;
        if (p[2] == 0) { cover = (shape ? 1.0 : style_cover(best, width)) * (1 - clamp(alpha, 0.0f, 1.0f)); }
        else if (p[2] == 1) { cover = shape ? style_cover(best, width) : 1.0; }
        else { cover = style_cover(best, width / 2); }
        paint[y * w + x] *= cover;
    }
    kernel void style_bevel_height(device const float *outside [[buffer(0)]], device const float *inside [[buffer(1)]],
                                   device float4 *heights [[buffer(2)]], constant int *p [[buffer(3)]],
                                   constant float &size [[buffer(4)]], device float *signed_d [[buffer(6)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], x = int(gid.x), y = int(gid.y), i = y * w + x;
        if (x >= w || y >= p[1]) { return; }
        float in_d = min(inside[i], style_far), d = in_d > 0 ? in_d - 0.5f : 0.5f - min(outside[i], style_far);
        signed_d[i] = d;
        float t = d / size, r = p[2] == 0 ? t : p[2] == 1 ? 1 + t : p[2] == 2 ? 0.5 + t : 2 * abs(t);
        r = clamp(r, 0.0f, 1.0f);
        float lift = p[3] == 0 ? 1 - (1 - r) * (1 - r) : r;
        heights[i] = float4(p[4] != 0 ? lift : -lift, 0, 0, 0);
    }
    static float style_height(device const float4 *heights, int w, int h, int x, int y) {
        return heights[clamp(y, 0, h - 1) * w + clamp(x, 0, w - 1)].x;
    }
    kernel void style_bevel_light(device const float4 *in [[buffer(0)]], device const float4 *heights [[buffer(1)]],
                                  device float4 *highlight [[buffer(2)]], constant int *p [[buffer(3)]],
                                  constant float *f [[buffer(5)]], device float4 *shadow [[buffer(6)]],
                                  device const float *signed_d [[buffer(7)]], uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], x = int(gid.x), y = int(gid.y), i = y * w + x;
        if (x >= w || y >= h) { return; }
        highlight[i] = float4(0);
        shadow[i] = float4(0);
        float alpha = clamp(in[i].w, 0.0f, 1.0f);
        if (signed_d[i] < -f[0]) { return; }
        float clip = p[2] == 0 ? alpha : p[2] == 1 ? 1 - alpha : 1.0;
        if (clip <= 0) { return; }
        float nx = -(style_height(heights, w, h, x + 1, y) - style_height(heights, w, h, x - 1, y)) / 2 * f[1];
        float ny = -(style_height(heights, w, h, x, y + 1) - style_height(heights, w, h, x, y - 1)) / 2 * f[1];
        float lean = (nx * f[2] + ny * f[3]) / sqrt(nx * nx + ny * ny + 1);
        float cover = min(abs(lean), 1.0f) * clip;
        if (cover <= 0) { return; }
        if (lean > 0) { highlight[i] = float4(f[4], f[5], f[6], f[7]) * cover; }
        else { shadow[i] = float4(f[8], f[9], f[10], f[11]) * cover; }
    }
    """
}
#endif
