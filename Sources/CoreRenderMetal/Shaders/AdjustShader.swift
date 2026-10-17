// AdjustShader.swift: the MSL of `adjust_tone` (metal-backend MB-13, MB-14), compiled on first use. One thread
// per tile pixel mirrors `AdjustTable.map`: alpha 0 gives zeros, else unpremultiply, map the straight color by
// `AdjustTable.Kind` (gains: times the per-channel factors; channel: each channel through the square-root-spaced
// table with linear interpolation, lines outside 0...1; luma: times the table's gain at the Rec. 709
// luminance), premultiply, clamp to the finite half range (as upload does) and write; alpha kept.
// Textures: 0 the source tile, 1 the output tile. Buffers: 0 the table (one 0 for gains), 1 `AdjustParams`.
#if canImport(Metal)
import CoreRender

/// The adjust kernel's pipeline key and source.
enum AdjustShader {
    static let key = PipelineKey(op: .adjust, variant: "tone")
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct AdjustParams {
        float gain_r;
        float gain_g;
        float gain_b;
        float below;
        float above;
        float luma_r;
        float luma_g;
        float luma_b;
        uint n;
        uint kind;
    };

    static float adjust_value(float v, constant float *t, constant AdjustParams &p) {
        if (p.n < 1) { return v; }
        if (!(v >= 0.0f)) { return t[0] + p.below * v; }
        if (v > 1.0f) { return t[p.n] + p.above * (v - 1.0f); }
        float f = sqrt(v) * float(p.n);
        uint i = min(uint(f), p.n - 1);
        return t[i] + (t[i + 1] - t[i]) * (f - float(i));
    }

    kernel void adjust_tone(texture2d<half, access::read> src [[texture(0)]],
                            texture2d<half, access::write> dst [[texture(1)]],
                            constant float *table [[buffer(0)]],
                            constant AdjustParams &p [[buffer(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= src.get_width() || gid.y >= src.get_height()) { return; }
        float4 px = float4(src.read(gid));
        if (px.a == 0.0f) { dst.write(half4(0.0h), gid); return; }
        float3 c = px.rgb / px.a;
        if (p.kind == 0) {
            c = c * float3(p.gain_r, p.gain_g, p.gain_b);
        } else if (p.kind == 2) {
            c = c * adjust_value(p.luma_r * c.r + p.luma_g * c.g + p.luma_b * c.b, table, p);
        } else {
            c = float3(adjust_value(c.r, table, p), adjust_value(c.g, table, p), adjust_value(c.b, table, p));
        }
        c = c * px.a;
        dst.write(half4(float4(clamp(c, float3(-65504.0f), float3(65504.0f)), px.a)), gid);
    }
    """
}
#endif
