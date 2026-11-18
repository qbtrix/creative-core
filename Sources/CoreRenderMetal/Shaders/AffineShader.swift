// AffineShader.swift: the composite through an AffineMatrix (#829), one kernel per blend mode, one thread per
// backdrop pixel of one backdrop tile, in place. Each thread samples the source like CoreRaster's `sampled` for
// `.bilinear` at stretch 1 (taps floor(u) and floor(u) + 1, the CPU's ceil(u - 1)...floor(u + 1) less a tap of weight 0, weighted by the tent, the sum over in-source taps
// divided by the weight of every tap, so the outside reads clear), then blends with the in-place composite's math:
// BlendSeparableShader's and BlendNonSeparableShader's B(Cb, Cs), mixed by `separable_over` (`.normal` is that mix
// with B = Cs). The source taps come from up to a 4 x 4 block of source tiles bound as a texture array; the host
// passes the block-local source point of the region's first pixel, so Float positions stay small.
#if canImport(Metal)
import CoreRaster
import CoreRender

enum AffineShader {
    /// The kernel `affine_<mode>`.
    static func key(_ mode: BlendMode) -> PipelineKey { PipelineKey(op: .affine, variant: mode.rawValue) }

    /// Textures 0...15 the source block (slot row * 4 + column), texture 16 the backdrop tile. Buffer 0 holds
    /// `AffineParams`: region (tile-local x, y, width, height), limits (source width and height less the block's
    /// origin), inverse (a, b, c, d), start (block-local u, v of the region's first pixel) and the opacity.
    static let source = BlendSeparableShader.functions + BlendNonSeparableShader.functions + header
        + BlendMode.allCases.map(kernel).joined()

    private static let header = """
    struct AffineParams { int4 region; int4 limits; float4 inv; float4 start; float opacity; };
    static float aff_tent(float t) { t = fabs(t); return t < 1.0f ? 1.0f - t : 0.0f; }

    """

    /// B(Cb, Cs) for `mode` in MSL, on straight colours `cb` and `cs`.
    private static func blended(_ mode: BlendMode) -> String {
        switch RenderOp(compositing: mode) {
        case .composite: return "cs"
        case .blendNonSeparable: return "blend_\(mode.rawValue)(cb, cs)"
        default: return "float3(blend_\(mode.rawValue)(cb.r, cs.r), blend_\(mode.rawValue)(cb.g, cs.g), blend_\(mode.rawValue)(cb.b, cs.b))"
        }
    }

    private static func kernel(_ mode: BlendMode) -> String {
        """
        kernel void affine_\(mode.rawValue)(array<texture2d<half, access::read>, 16> src [[texture(0)]],
            texture2d<half, access::read_write> dst [[texture(16)]], constant AffineParams &q [[buffer(0)]],
            uint2 gid [[thread_position_in_grid]]) {
            int2 g = int2(gid);
            if (g.x >= q.region.z || g.y >= q.region.w) { return; }
            float u = q.start.x + q.inv.x * float(g.x) + q.inv.z * float(g.y);
            float v = q.start.y + q.inv.y * float(g.x) + q.inv.w * float(g.y);
            float4 sum = float4(0.0f);
            float total = 0.0f;
            int i0 = int(floor(u)), i1 = i0 + 1;  // the CPU's taps ceil(u - 1)...floor(u + 1) less one of weight 0
            int j0 = int(floor(v)), j1 = j0 + 1;
            float tx = 0.0f, ty = 0.0f;
            for (int i = i0; i <= i1; i++) { tx += aff_tent(float(i) - u); }
            for (int j = j0; j <= j1; j++) { ty += aff_tent(float(j) - v); }
            total = tx * ty;
            bool inside = u > -2.0f - float(q.limits.z) && u < float(q.limits.x) + 1.0f
                && v > -2.0f - float(q.limits.w) && v < float(q.limits.y) + 1.0f;
            for (int j = max(max(j0, -q.limits.w), 0); inside && j <= min(min(j1, q.limits.y - 1), 1023); j++) {
                float wy = aff_tent(float(j) - v);
                if (wy == 0.0f) { continue; }
                for (int i = max(max(i0, -q.limits.z), 0); i <= min(min(i1, q.limits.x - 1), 1023); i++) {
                    float w = wy * aff_tent(float(i) - u);
                    sum += w * float4(src[(j >> 8) * 4 + (i >> 8)].read(uint2(i & 255, j & 255)));
                }
            }
            float4 s = (inside && total != 0.0f ? sum / total : float4(0.0f)) * q.opacity;
            uint2 at = uint2(q.region.xy + g);
            float4 b = float4(dst.read(at));
            float3 cs = s.a != 0.0f ? s.rgb / s.a : float3(0.0f), cb = b.a != 0.0f ? b.rgb / b.a : float3(0.0f);
            dst.write(separable_over(s, b, cs, \(blended(mode))), at);
        }

        """
    }
}
#endif
