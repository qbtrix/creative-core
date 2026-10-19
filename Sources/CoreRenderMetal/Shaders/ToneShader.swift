// ToneShader.swift: the MSL of the tone-program kernels, compiled on first use. `display_tone` is
// `display_target` (DisplayShader.swift) with a `ToneProgram` run on each pixel first, so a live adjustment
// re-encodes a resident picture into the canvas texture in one dispatch; `adjust_program` writes the program's
// result into a new surface's tile instead (an adjustment layer under other layers), clamped to the finite half
// range as `adjust_tone` writes. One thread per tile pixel mirrors `ToneProgram.map`: alpha 0 gives zeros,
// else unpremultiply, each step on the straight color in order (gains; each channel through its table; the
// table's gain at the Rec. 709 luminance; hue/saturation as standard HSL on the clamped sRGB-encoded values;
// or a 3x3 matrix, clamp at 0 and lightness mix), premultiply. Textures: 0 the source tile, 1 the target (or
// output tile). Buffers: 1 display thresholds, 2 `DisplayParams`, 3 the display matrix (`display_tone` only,
// as `display_target`), 4 the steps (`ToneStep`, seven 4-byte fields), 5 the tables (device memory: each thread
// indexes them at its own value), 6 the step count.
#if canImport(Metal)
import CoreRender

/// The tone-and-display kernel's pipeline key and source.
enum ToneShader {
    static let key = PipelineKey(op: .display, variant: "tone")
    /// `adjust_program`, a program into a new surface.
    static let adjustKey = PipelineKey(op: .adjust, variant: "program")
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    \(AdjustShader.functions)

    \(DisplayShader.functions)

    struct ToneStep {
        float a;
        float b;
        float c;
        uint kind;
        uint n;
        uint outer;
        uint offset;
    };

    static float tone_encode(float v) {
        float a = fabs(v);
        float e = a <= 0.0031308f ? a * 12.92f : 1.055f * pow(a, 1.0f / 2.4f) - 0.055f;
        return clamp(v < 0.0f ? -e : e, 0.0f, 1.0f);
    }

    static float tone_decode(float v) {
        float a = fabs(v);
        float l = a <= 0.04045f ? a / 12.92f : pow((a + 0.055f) / 1.055f, 2.4f);
        return v < 0.0f ? -l : l;
    }

    // `ToneProgram.shifted`: hue (degrees), saturation and lightness (percent) on standard HSL.
    static float3 tone_hue_saturation(float3 c, float hue, float saturation, float lightness) {
        float3 e = float3(tone_encode(c.r), tone_encode(c.g), tone_encode(c.b));
        float hi = max(e.r, max(e.g, e.b)), lo = min(e.r, min(e.g, e.b)), d = hi - lo;
        float l = (hi + lo) / 2.0f, h = 0.0f, s = 0.0f;
        if (d > 0.0f) {
            float sector = hi == e.r ? (e.g - e.b) / d : hi == e.g ? (e.b - e.r) / d + 2.0f : (e.r - e.g) / d + 4.0f;
            h = fmod(sector * 60.0f + 360.0f, 360.0f);
            s = d / (1.0f - fabs(2.0f * l - 1.0f));
        }
        h = fmod(h + hue + 360.0f, 360.0f);
        s = min(1.0f, max(0.0f, s * (1.0f + saturation / 100.0f)));
        l = lightness >= 0.0f ? l + (1.0f - l) * lightness / 100.0f : l * (1.0f + lightness / 100.0f);
        float chroma = (1.0f - fabs(2.0f * l - 1.0f)) * s, hp = h / 60.0f;
        float x = chroma * (1.0f - fabs(fmod(hp, 2.0f) - 1.0f));
        float3 rgb;
        switch (int(hp) % 6) {
            case 0: rgb = float3(chroma, x, 0.0f); break;
            case 1: rgb = float3(x, chroma, 0.0f); break;
            case 2: rgb = float3(0.0f, chroma, x); break;
            case 3: rgb = float3(0.0f, x, chroma); break;
            case 4: rgb = float3(x, 0.0f, chroma); break;
            default: rgb = float3(chroma, 0.0f, x); break;
        }
        float3 v = rgb + (l - chroma / 2.0f);
        return float3(tone_decode(v.r), tone_decode(v.g), tone_decode(v.b));
    }

    // `ToneProgram.mixed`: t[0...8] the rows, t[9] the lightness.
    static float tone_light(float v, float l) {
        float c = max(v, 0.0f);
        return l >= 0.0f ? c + (1.0f - c) * l : c * (1.0f + l);
    }

    static float3 tone_matrix(float3 c, device const float *t) {
        return float3(tone_light(t[0] * c.r + t[1] * c.g + t[2] * c.b, t[9]),
                      tone_light(t[3] * c.r + t[4] * c.g + t[5] * c.b, t[9]),
                      tone_light(t[6] * c.r + t[7] * c.g + t[8] * c.b, t[9]));
    }

    static float4 tone_apply(float4 px, constant ToneStep *steps, uint count, device const float *tables) {
        if (px.a == 0.0f) { return float4(0.0f); }
        float3 c = px.rgb / px.a;
        for (uint i = 0; i < count; i++) {
            ToneStep s = steps[i];
            device const float *t = tables + s.offset;
            if (s.kind == 0) {
                c = c * float3(s.a, s.b, s.c);
            } else if (s.kind == 1) {
                c = float3(adjust_value(c.r, t, s.n, s.outer), adjust_value(c.g, t, s.n, s.outer),
                           adjust_value(c.b, t, s.n, s.outer));
            } else if (s.kind == 2) {
                c = c * adjust_value(\(AdjustTable.lumaWeights.x)f * c.r + \(AdjustTable.lumaWeights.y)f * c.g
                                     + \(AdjustTable.lumaWeights.z)f * c.b, t, s.n, s.outer);
            } else if (s.kind == 4) {
                c = tone_matrix(c, t);
            } else {
                c = tone_hue_saturation(c, s.a, s.b, s.c);
            }
        }
        return float4(c * px.a, px.a);
    }

    kernel void display_tone(texture2d<half, access::read> tile [[texture(0)]],
                             texture2d<float, access::write> out [[texture(1)]],
                             constant float *table [[buffer(1)]],
                             constant DisplayParams &p [[buffer(2)]],
                             constant float *m [[buffer(3)]],
                             constant ToneStep *steps [[buffer(4)]],
                             device const float *tables [[buffer(5)]],
                             constant uint &count [[buffer(6)]],
                             uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= tile.get_width() || gid.y >= tile.get_height()) { return; }
        float4 px = tone_apply(float4(tile.read(gid)), steps, count, tables);
        uint4 v = uint4(display_bytes(px, table, p.p3, m));
        if (p.stride != 0 && v.a != 255) { v.rgb = (v.rgb * v.a + 127) / 255; }
        out.write(float4(v) / 255.0f, uint2(gid.x + p.x, gid.y + p.y));
    }

    kernel void adjust_program(texture2d<half, access::read> src [[texture(0)]],
                               texture2d<half, access::write> dst [[texture(1)]],
                               constant ToneStep *steps [[buffer(4)]],
                               device const float *tables [[buffer(5)]],
                               constant uint &count [[buffer(6)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= src.get_width() || gid.y >= src.get_height()) { return; }
        float4 px = tone_apply(float4(src.read(gid)), steps, count, tables);
        dst.write(half4(clamp(px, float4(-65504.0f), float4(65504.0f))), gid);
    }
    """
}
#endif
