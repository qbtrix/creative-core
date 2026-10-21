// StyleShader.swift: the MSL of a layer style's light layers (layer-style-engine LE-9a, LE-9a2), CoreRaster's `styleLayers`
// over whole-image float4 buffers. `style_pad` spreads the alpha on the distance field (choke > 0 only) and pads it
// with the outside value for the glows' box blur; `style_light` reads that mask bilinearly at (x - dx, y - dy) and
// tints it (an outer one knocked out by the alpha); `style_edge_seed` seeds the anti-aliased edge points of a copy
// padded by 1 px, `style_edt_pass` finds each pixel's nearest seed as CoreRaster's exact transform does (columns,
// then rows; not the jump flood, whose ties differ in thin stems), and `style_stroke` turns it into the stroke's
// smoothstep cover of the fill; `style_bevel_height` raises the signed distance through the shape's rise and profile, and
// `style_bevel_light` leans its central-difference normal toward the light into highlight and shadow. Distances are
// clamped to 1e30 before use, so no infinity reaches arithmetic. Grids may round up; every kernel bounds-checks.
#if canImport(Metal)
import CoreRender

enum StyleShader {
    /// The kernels' variants, for the warmup.
    static let variants = ["pad", "light", "edge_seed", "edt_pass", "stroke", "bevel_height", "bevel_light"]

    /// The pipeline key of `variant`.
    static func key(_ variant: String) -> PipelineKey { PipelineKey(op: .style, variant: variant) }

    /// Buffers 0, 1, 2 then 6, 7 as `styleDispatch` binds them; ints at 3, the float at 4, the float table at 5.
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
    kernel void style_edge_seed(device const float4 *in [[buffer(0)]], device long *f [[buffer(1)]],
                                device float4 *points [[buffer(2)]], constant int *p [[buffer(3)]],
                                device int *nearest [[buffer(6)]], uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pw = w + 2, x = int(gid.x), y = int(gid.y), i = y * pw + x;
        if (x >= pw || y >= h + 2) { return; }
        float v = style_edge_alpha(in, w, h, x, y), opposite = v >= 1 ? 0.0 : 1.0;
        bool seed = (v > 0 && v < 1) || style_edge_alpha(in, w, h, x - 1, y) == opposite
            || style_edge_alpha(in, w, h, x + 1, y) == opposite || style_edge_alpha(in, w, h, x, y - 1) == opposite
            || style_edge_alpha(in, w, h, x, y + 1) == opposite;
        if (!seed) { f[i] = -1; nearest[i] = -1; points[i] = float4(0); return; }
        float r2 = sqrt(2.0);
        float gx = style_edge_alpha(in, w, h, x + 1, y - 1) + r2 * style_edge_alpha(in, w, h, x + 1, y)
            + style_edge_alpha(in, w, h, x + 1, y + 1) - style_edge_alpha(in, w, h, x - 1, y - 1)
            - r2 * style_edge_alpha(in, w, h, x - 1, y) - style_edge_alpha(in, w, h, x - 1, y + 1);
        float gy = style_edge_alpha(in, w, h, x - 1, y + 1) + r2 * style_edge_alpha(in, w, h, x, y + 1)
            + style_edge_alpha(in, w, h, x + 1, y + 1) - style_edge_alpha(in, w, h, x - 1, y - 1)
            - r2 * style_edge_alpha(in, w, h, x, y - 1) - style_edge_alpha(in, w, h, x + 1, y - 1);
        float g = sqrt(gx * gx + gy * gy);
        float d = g > 0 ? style_edge_offset(v, abs(gx) / g, abs(gy) / g) / g : 0.0;
        f[i] = 0;
        nearest[i] = i;
        points[i] = float4(float(x) + d * gx, float(y) + d * gy, 1, 0);
    }
    // CoreRaster `DistanceField.envelopePass` (border off) for line gid.x: squared distances in `f` (-1 for none) and
    // their seeds, in exact int64, the breakpoints kept as fractions, so ties fall to the same seed as on the CPU.
    kernel void style_edt_pass(device const long *fin [[buffer(0)]], device const int *nin [[buffer(1)]],
                               device long *fout [[buffer(2)]], constant int *p [[buffer(3)]],
                               device int *nout [[buffer(6)]], device long *scratch [[buffer(7)]],
                               uint2 gid [[thread_position_in_grid]]) {
        int lines = p[0], n = p[1], along = p[2], l = int(gid.x);
        if (l >= lines || gid.y > 0) { return; }
        long base = long(l) * long(p[3]);
        device long *sites = scratch + long(l) * 5 * long(n);
        device long *heights = sites + n;
        device long *owner = heights + n;
        device long *bn = owner + n;
        device long *bd = bn + n;
        int k = -1;
        for (int q = 0; q < n; q++) {
            long fq = fin[base + long(q) * along], dq = q, sn = 0, sd = 0;
            if (fq < 0) { continue; }
            while (k >= 0) {
                long dv = sites[k];
                sn = (fq + dq * dq) - (heights[k] + dv * dv);
                sd = 2 * dq - 2 * dv;
                if (bd[k] == 0 || sn * bd[k] > bn[k] * sd) { break; }
                k -= 1;
            }
            k += 1;
            sites[k] = q; heights[k] = fq; owner[k] = nin[base + long(q) * along];
            bn[k] = k == 0 ? 0 : sn; bd[k] = k == 0 ? 0 : sd;
        }
        int j = 0;
        for (int i = 0; i < n; i++) {
            long at = base + long(i) * along;
            if (k < 0) { fout[at] = fin[at]; nout[at] = nin[at]; continue; }
            while (j < k && bn[j + 1] < long(i) * bd[j + 1]) { j += 1; }
            long d = long(i) - sites[j];
            fout[at] = d * d + heights[j];
            nout[at] = int(owner[j]);
        }
    }
    static float style_cover(float edge, float width) {
        float t = clamp(width + 0.5f - edge, 0.0f, 1.0f);
        return t * t * (3 - 2 * t);
    }
    kernel void style_stroke(device const int *nearest [[buffer(0)]], device const float4 *points [[buffer(1)]],
                             device float4 *paint [[buffer(2)]], constant int *p [[buffer(3)]],
                             constant float &width [[buffer(4)]], device const float4 *in [[buffer(6)]],
                             uint2 gid [[thread_position_in_grid]]) {
        int w = p[0], h = p[1], pw = w + 2, ph = h + 2, x = int(gid.x), y = int(gid.y);
        if (x >= w || y >= h) { return; }
        int seed = nearest[(y + 1) * pw + x + 1];
        int2 n = seed < 0 ? int2(-1) : int2(seed % pw, seed / pw);
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
