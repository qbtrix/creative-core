// BlendNonSeparableShader.swift: the four non-separable blend kernels (MB-9, MB-10), one per mode, each the in-place
// composite of CompositeShader with CoreRaster's B(Cb, Cs) for hue, saturation, color or luminosity
// (BlendMode.swift: Lum, Sat, SetLum, SetSat and ClipColor in its order of operations, the grey guards included)
// and CoreRaster's `sourceOver` mix: opacity scales the source first, alpha exactly 0 gives straight colour 0
// on either side, Cs' = Cs + αb (B - Cs), and the result is clamped to the finite half range. One library
// holds the four kernels; each mode's pipeline is its own key. ClipColor's edge cases (MB-10) follow the CPU in
// Float32, test for test and in its order: l, n and x come from the colour SetLum made, the low clip runs only when
// n < 0 and l > n and the high clip only when x > 1 and x > l (so a grey, max == min, never divides 0 by 0), and
// the high clip sees the low clip's output with the input's l and x. Lum 0 pulls a low clip to 0 and lum 1 pulls
// a high clip to 1 exactly, because the numerator multiplies by l and by 1 - l. SetSat leaves a grey black.
#if canImport(Metal)
import CoreRaster
import CoreRender

enum BlendNonSeparableShader {
    /// The modes with a kernel here, in BlendMode's order.
    static let modes: [BlendMode] = [.hue, .saturation, .color, .luminosity]

    /// The kernel `blendNonSeparable_<mode>` (for example `blendNonSeparable_luminosity`).
    static func key(_ mode: BlendMode) -> PipelineKey { PipelineKey(op: .blendNonSeparable, variant: mode.rawValue) }

    /// The bindings are CompositeShader's: buffer 0 holds destination x, y, width, height, source x, y; buffer 1
    /// the opacity; texture 0 the source tile, texture 1 the backdrop tile read and written in place.
    static let source = Self.functions + Self.modes.enumerated().map { Self.kernel($0.offset, $0.element) }.joined()

    /// The spec's helpers and B(Cb, Cs) per mode on straight colours, as BlendMode.swift computes them.
    static let functions = """
    #include <metal_stdlib>
    using namespace metal;
    static float ns_lum(float3 c) { return 0.3f * c.r + 0.59f * c.g + 0.11f * c.b; }
    static float ns_min(float3 c) { return min(min(c.r, c.g), c.b); }
    static float ns_max(float3 c) { return max(max(c.r, c.g), c.b); }
    static float ns_sat(float3 c) { return ns_max(c) - ns_min(c); }
    /// ClipColor: l, n and x come from the input; a grey (l == n or x == l) is left alone, never divided by 0;
    /// each guard is the CPU's, in its order, so an out-of-range colour clips low first, then high.
    static float3 ns_clip(float3 c) {
        float l = ns_lum(c), n = ns_min(c), x = ns_max(c);
        float3 o = c;
        if (n < 0.0f && l > n) { o = l + ((o - l) * l) / (l - n); }
        if (x > 1.0f && x > l) { o = l + ((o - l) * (1.0f - l)) / (x - l); }
        return o;
    }
    static float3 ns_setLum(float3 c, float l) { return ns_clip(c + (l - ns_lum(c))); }
    /// SetSat: the max channel becomes s, the min 0, the middle keeps its place; a grey becomes black.
    static float3 ns_setSat(float3 c, float s) {
        float n = ns_min(c), x = ns_max(c);
        if (!(x > n)) { return float3(0.0f); }  // max == min: the CPU's guard, no 0 / 0
        return (c - n) * s / (x - n);
    }
    static float3 blend_hue(float3 cb, float3 cs) { return ns_setLum(ns_setSat(cs, ns_sat(cb)), ns_lum(cb)); }
    static float3 blend_saturation(float3 cb, float3 cs) { return ns_setLum(ns_setSat(cb, ns_sat(cs)), ns_lum(cb)); }
    static float3 blend_color(float3 cb, float3 cs) { return ns_setLum(cs, ns_lum(cb)); }
    static float3 blend_luminosity(float3 cb, float3 cs) { return ns_setLum(cb, ns_lum(cs)); }
    /// One backdrop pixel of a TilePiece: CompositeShader's reads, then sourceOver after B(Cb, Cs) for `mode`
    /// (0 hue, 1 saturation, 2 color, 3 luminosity), clamped to the finite half range and written in place.
    static void ns_composite(uint2 gid, float opacity, constant int *p, texture2d<half, access::read_write> dst,
                             texture2d<half, access::read> src, int mode) {
        int2 g = int2(gid);
        if (g.x >= p[2] || g.y >= p[3]) { return; }
        uint2 at = uint2(g + int2(p[0], p[1]));
        float4 b = float4(dst.read(at)), s = opacity * float4(src.read(uint2(g + int2(p[4], p[5]))));
        float3 cb = float3(0.0f), cs = float3(0.0f);
        if (b.a != 0.0f) { cb = b.rgb / b.a; }
        if (s.a != 0.0f) { cs = s.rgb / s.a; }
        float3 blended = mode == 0 ? blend_hue(cb, cs) : mode == 1 ? blend_saturation(cb, cs)
            : mode == 2 ? blend_color(cb, cs) : blend_luminosity(cb, cs);
        float keep = 1.0f - s.a;
        float4 out = float4((cs + b.a * (blended - cs)) * s.a + b.rgb * keep, s.a + b.a * keep);
        dst.write(half4(clamp(out, -65504.0f, 65504.0f)), at);
    }

    """

    /// One mode's kernel: one thread per backdrop pixel of a TilePiece, bound like CompositeShader's.
    private static func kernel(_ index: Int, _ mode: BlendMode) -> String {
        """
        kernel void blendNonSeparable_\(mode.rawValue)(uint2 gid [[thread_position_in_grid]],
            constant float &opacity [[buffer(1)]], constant int *p [[buffer(0)]],
            texture2d<half, access::read_write> dst [[texture(1)]], texture2d<half, access::read> src [[texture(0)]]) {
            ns_composite(gid, opacity, p, dst, src, \(index));
        }

        """
    }
}
#endif
