// DisplayShader.swift: the MSL of `display_encode` (metal-backend MB-3), compiled on first use. One
// thread per tile pixel writes straight-alpha bytes at the tile's offset in the image buffer, mirroring
// `DisplayTable.encode` line for line. Buffers: 0 the bytes, 1 the 510 thresholds, 2 `DisplayParams`
// (tile x, tile y, image width, 1 for P3), 3 the 9 matrix entries (identity for sRGB).
#if canImport(Metal)
import CoreRender

/// The display kernel's pipeline key and source.
enum DisplayShader {
    static let key = PipelineKey(op: .display, variant: "encode")
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
