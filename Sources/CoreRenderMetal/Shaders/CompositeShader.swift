// CompositeShader.swift: the `.normal` composite kernel's MSL (MB-4), one thread per backdrop pixel of a
// TilePiece, in place, with CoreRaster's `sourceOver` in float: opacity scales the source first, source alpha
// exactly 0 gives straight colour 0 (the CPU's guard), and the result is clamped to the finite half range.
#if canImport(Metal)
import CoreRender

enum CompositeShader {
    /// The kernel `composite_normal`.
    static let key = PipelineKey(op: .composite, variant: "normal")

    /// Buffer 0 holds six ints: destination x, y (local to the backdrop tile), piece width, height, then
    /// source x, y (local to the source tile) of the top-left pixel. Buffer 1 holds the opacity, in 0...1.
    /// Texture 1 is the backdrop tile, read and written in place (read-write texture tier 2).
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void composite_normal(texture2d<half, access::read> src [[texture(0)]],
                                 texture2d<half, access::read_write> dst [[texture(1)]],
                                 constant int *p [[buffer(0)]],
                                 constant float &opacity [[buffer(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
        int2 g = int2(gid);
        if (g.x >= p[2] || g.y >= p[3]) { return; }
        uint2 d = uint2(int2(p[0], p[1]) + g);
        float4 s = float4(src.read(uint2(int2(p[4], p[5]) + g))) * opacity;
        float4 b = float4(dst.read(d));
        float3 cs = s.a != 0.0f ? s.rgb / s.a : float3(0.0f);
        float keep = 1.0f - s.a;
        float4 o = float4(cs * s.a + b.rgb * keep, s.a + b.a * keep);
        dst.write(half4(clamp(o, -65504.0f, 65504.0f)), d);
    }
    """
}
#endif
