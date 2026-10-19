// AdjustShader.swift: the MSL of `adjust_tone` (metal-backend MB-13, MB-14), compiled on first use. One thread
// per tile pixel mirrors `AdjustTable.map`: alpha 0 gives zeros, else unpremultiply, map the straight color by
// `AdjustTable.Kind` (gains: times the per-channel factors; channel: each channel through the square-root-spaced
// table with linear interpolation, and outside 0...1 through the octave table of that side, indexed by the
// float's exponent bits and interpolated on its mantissa; luma: times the table's gain at the Rec. 709
// luminance, constant outside 0...1), premultiply, clamp to the finite half range (as upload does) and write;
// alpha kept. Textures: 0 the source tile, 1 the output tile. Buffers: 0 the table (one 0 for gains): `n + 1`
// values, then `outer` entries below 0 and `outer` above 1 (none for gains and luma), 1 `AdjustParams`.
// `functions` (the table reads) is shared with ToneShader.swift's tone-program kernels.
#if canImport(Metal)
import CoreRender

/// The adjust kernel's pipeline key and source.
enum AdjustShader {
    static let key = PipelineKey(op: .adjust, variant: "tone")
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    \(functions)

    struct AdjustParams {
        float gain_r;
        float gain_g;
        float gain_b;
        float luma_r;
        float luma_g;
        float luma_b;
        uint n;
        uint kind;
        uint outer;
    };

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
            c = c * adjust_value(p.luma_r * c.r + p.luma_g * c.g + p.luma_b * c.b, table, p.n, p.outer);
        } else {
            c = float3(adjust_value(c.r, table, p.n, p.outer), adjust_value(c.g, table, p.n, p.outer),
                       adjust_value(c.b, table, p.n, p.outer));
        }
        c = c * px.a;
        dst.write(half4(float4(clamp(c, float3(-65504.0f), float3(65504.0f)), px.a)), gid);
    }
    """

    /// The table reads `adjust_tone` and `display_tone` (ToneShader.swift) share: `adjust_octave`, `adjust_value`.
    static let functions = """
    #define OCTAVE_MIN \(AdjustTable.octaveMin)
    #define OCTAVE_MAX \(AdjustTable.octaveMax)
    #define PER_OCTAVE \(AdjustTable.perOctave)
    #define OCTAVE_FIRST_INV \(1 / AdjustTable.octaveX(0))f
    #define OCTAVE_LAST_X0 \(AdjustTable.octaveX(AdjustTable.octaveCount - 2))f
    #define OCTAVE_LAST_X1 \(AdjustTable.octaveX(AdjustTable.octaveCount - 1))f

    // `AdjustTable.octave`: o at |x| = a > 0, the line from f(0) under 2^OCTAVE_MIN, the last interval's past.
    // Templates on the table pointer: `adjust_tone` reads a constant table, the tone-program kernels a device
    // one (each thread indexes it at its own value, which the constant address space serves slowly).
    template <typename Table>
    static float adjust_octave(Table o, uint count, float a, float zero) {
        uint bits = as_type<uint>(a);
        int octave = int((bits >> 23) & 0xFFu) - 127 - (OCTAVE_MIN);
        if (octave < 0) { return zero + (o[0] - zero) * (a * OCTAVE_FIRST_INV); }
        uint last = count - 1;
        if (octave >= (OCTAVE_MAX) - (OCTAVE_MIN)) {
            return o[last - 1] + (o[last] - o[last - 1]) * ((a - OCTAVE_LAST_X0) / (OCTAVE_LAST_X1 - OCTAVE_LAST_X0));
        }
        float f = float(bits & 0x7FFFFFu) * (1.0f / 8388608.0f) * float(PER_OCTAVE);
        uint j = min(uint(f), uint(PER_OCTAVE) - 1);
        uint i = uint(octave) * uint(PER_OCTAVE) + j;
        if (i + 1 > last) { return o[last]; }
        return o[i] + (o[i + 1] - o[i]) * (f - float(j));
    }

    template <typename Table>
    static float adjust_value(float v, Table t, uint n, uint outer) {
        if (n < 1) { return v; }
        if (!(v >= 0.0f)) { return outer < 2 ? t[0] : adjust_octave(t + n + 1, outer, -v, t[0]); }
        if (v > 1.0f) { return outer < 2 ? t[n] : adjust_octave(t + n + 1 + outer, outer, v, t[0]); }
        float f = sqrt(v) * float(n);
        uint i = min(uint(f), n - 1);
        return t[i] + (t[i + 1] - t[i]) * (f - float(i));
    }
    """
}
#endif
