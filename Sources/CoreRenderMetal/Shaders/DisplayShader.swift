// DisplayShader.swift: the MSL of the display encode kernel (metal-backend MB-3), compiled on first
// use through `MetalPipelines.pipeline(for:source:)` as `display_encode`. One thread per tile pixel:
// it reads the rgba16Float tile, writes straight-alpha bytes into one image-sized buffer at the tile's
// offset, and mirrors `DisplayTable.encode` (CoreRender/Metal/DisplayTable.swift) line for line:
// alpha 0 gives all zeros, colors are divided by alpha (skipped at alpha 1), Display P3 applies the
// matrix, then each component counts the curve thresholds and alpha the alpha thresholds, by the same
// eight-step search, which reads `table[base ... base + 254]` only. Buffers: 0 the output bytes,
// 1 the 510 `DisplayTable.thresholds`, 2 `DisplayParams`, 3 the 9 matrix entries (identity for sRGB).
#if canImport(Metal)
import CoreRender

/// The display kernel's source and pipeline key.
enum DisplayShader {
    /// `display_encode`.
    static let key = PipelineKey(op: .display, variant: "encode")

    /// The kernel. `DisplayParams` is four `uint`s: the tile's x and y in the image, the image width
    /// in pixels (the output row stride) and 1 for Display P3, else 0.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct DisplayParams {
        uint x;
        uint y;
        uint stride;
        uint p3;
    };

    static uchar display_level(float v, constant float *t) {
        uint index = 0;
        for (uint step = 128; step > 0; step >>= 1) {
            if (v >= t[index + step - 1]) { index += step; }
        }
        return uchar(index);
    }

    kernel void display_encode(texture2d<half, access::read> tile [[texture(0)]],
                               device uchar4 *out [[buffer(0)]],
                               constant float *table [[buffer(1)]],
                               constant DisplayParams &p [[buffer(2)]],
                               constant float *m [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= tile.get_width() || gid.y >= tile.get_height()) { return; }
        float4 px = float4(tile.read(gid));
        uint at = (gid.y + p.y) * p.stride + gid.x + p.x;
        if (px.a == 0.0f) { out[at] = uchar4(0); return; }
        float3 c = px.a == 1.0f ? px.rgb : px.rgb / px.a;
        if (p.p3 != 0) {
            c = float3(m[0] * c.r + m[1] * c.g + m[2] * c.b,
                       m[3] * c.r + m[4] * c.g + m[5] * c.b,
                       m[6] * c.r + m[7] * c.g + m[8] * c.b);
        }
        out[at] = uchar4(display_level(c.r, table), display_level(c.g, table),
                         display_level(c.b, table), display_level(px.a, table + 255));
    }
    """
}
#endif
