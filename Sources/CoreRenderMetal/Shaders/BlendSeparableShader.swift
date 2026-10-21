// BlendSeparableShader.swift: the thirteen separable blend kernels besides `.normal` (MB-5, LE-7), one per mode, each
// the in-place composite of CompositeShader with CoreRaster's B(Cb, Cs) for that mode (BlendMode.swift) per
// channel and CoreRaster's `sourceOver` mix: opacity scales the source first, alpha exactly 0 gives straight
// colour 0 on either side (the CPU's `unpremultiplied` guard), Cs' = Cs + αb (B - Cs), and the result is
// clamped to the finite half range. One library holds every kernel; each mode's pipeline is its own key.
#if canImport(Metal)
import CoreRaster
import CoreRender

enum BlendSeparableShader {
    /// The modes with a kernel here: every separable mode but `.normal`, which runs `composite_normal`.
    static let modes: [BlendMode] = [
        .multiply, .screen, .overlay, .darken, .lighten, .colorDodge, .colorBurn,
        .hardLight, .softLight, .difference, .exclusion, .linearDodge, .linearBurn,
    ]

    /// The kernel `blendSeparable_<mode>` (for example `blendSeparable_colorDodge`).
    static func key(_ mode: BlendMode) -> PipelineKey { PipelineKey(op: .blendSeparable, variant: mode.rawValue) }

    /// The bindings are CompositeShader's: buffer 0 holds destination x, y, width, height, source x, y; buffer 1
    /// the opacity; texture 0 the source tile, texture 1 the backdrop tile read and written in place.
    static let source = Self.functions + Self.modes.map(Self.kernel).joined()

    /// B(Cb, Cs) per channel on straight colours, in BlendMode.swift's order of operations.
    private static let functions = """
    #include <metal_stdlib>
    using namespace metal;
    static float sep_screen(float cb, float cs) { return cb + cs - cb * cs; }
    static float sep_hard(float cb, float cs) { return cs <= 0.5f ? cb * 2.0f * cs : sep_screen(cb, 2.0f * cs - 1.0f); }
    static float blend_multiply(float cb, float cs) { return cb * cs; }
    static float blend_screen(float cb, float cs) { return sep_screen(cb, cs); }
    static float blend_overlay(float cb, float cs) { return sep_hard(cs, cb); }
    static float blend_darken(float cb, float cs) { return min(cb, cs); }
    static float blend_lighten(float cb, float cs) { return max(cb, cs); }
    static float blend_colorDodge(float cb, float cs) {
        if (cb == 0.0f) { return 0.0f; }
        if (cs >= 1.0f) { return 1.0f; }
        return min(1.0f, cb / (1.0f - cs));
    }
    static float blend_colorBurn(float cb, float cs) {
        if (cb >= 1.0f) { return 1.0f; }
        if (cs <= 0.0f) { return 0.0f; }
        return 1.0f - min(1.0f, (1.0f - cb) / cs);
    }
    static float blend_hardLight(float cb, float cs) { return sep_hard(cb, cs); }
    static float blend_softLight(float cb, float cs) {
        if (cs <= 0.5f) { return cb - (1.0f - 2.0f * cs) * cb * (1.0f - cb); }
        float d = cb <= 0.25f ? ((16.0f * cb - 12.0f) * cb + 4.0f) * cb : sqrt(cb);
        return cb + (2.0f * cs - 1.0f) * (d - cb);
    }
    static float blend_difference(float cb, float cs) { return fabs(cb - cs); }
    static float blend_exclusion(float cb, float cs) { return cb + cs - 2.0f * cb * cs; }
    static float blend_linearDodge(float cb, float cs) { return min(1.0f, cb + cs); }
    static float blend_linearBurn(float cb, float cs) { return max(0.0f, cb + cs - 1.0f); }
    /// sourceOver after the blend: premultiply Cs' by the scaled source alpha, then add the backdrop's share.
    static half4 separable_over(float4 s, float4 b, float3 cs, float3 blended) {
        float3 mixed = (cs + b.a * (blended - cs)) * s.a;
        float keep = 1.0f - s.a;
        return half4(clamp(float4(mixed + b.rgb * keep, s.a + b.a * keep), -65504.0f, 65504.0f));
    }

    """

    /// One mode's kernel: one thread per backdrop pixel of a TilePiece.
    private static func kernel(_ mode: BlendMode) -> String {
        let f = "blend_\(mode.rawValue)"
        return """
        kernel void blendSeparable_\(mode.rawValue)(texture2d<half, access::read> src [[texture(0)]],
            texture2d<half, access::read_write> dst [[texture(1)]], constant int *p [[buffer(0)]],
            constant float &opacity [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
            int2 g = int2(gid);
            if (g.x >= p[2] || g.y >= p[3]) { return; }
            uint2 at = uint2(int2(p[0], p[1]) + g);
            float4 s = float4(src.read(uint2(int2(p[4], p[5]) + g))) * opacity, b = float4(dst.read(at));
            float3 cs = s.a != 0.0f ? s.rgb / s.a : float3(0.0f), cb = b.a != 0.0f ? b.rgb / b.a : float3(0.0f);
            dst.write(separable_over(s, b, cs, float3(\(f)(cb.r, cs.r), \(f)(cb.g, cs.g), \(f)(cb.b, cs.b))), at);
        }

        """
    }
}
#endif
