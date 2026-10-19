// DisplayShader.swift: the MSL of the display kernels, compiled on first use. `display_encode`
// (metal-backend MB-3): one thread per tile pixel writes straight-alpha bytes at the tile's offset in the
// image buffer, mirroring `DisplayTable.encode` line for line. Buffers: 0 the bytes, 1 the 510
// thresholds, 2 `DisplayParams` (tile x, tile y, image width, 1 for P3), 3 the 9 matrix entries (identity
// for sRGB). `display_target` (resident rendering) computes the same bytes through `display_bytes` and
// writes them into an 8-bit unorm texture at the tile's offset there instead, premultiplied when asked
// with the CPU's rounding, (c x a + 127) / 255; `DisplayParams.stride` is then 1 for premultiplied.
// `functions` (`DisplayParams`, `display_level`, `display_bytes`) is shared with ToneShader.swift's `display_tone`.
#if canImport(Metal)
import CoreRender

/// The display kernel's pipeline key and source.
enum DisplayShader {
    static let key = PipelineKey(op: .display, variant: "encode")
    /// `display_target`, the write into a texture.
    static let targetKey = PipelineKey(op: .display, variant: "target")
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    \(functions)

    kernel void display_encode(texture2d<half, access::read> tile [[texture(0)]],
                               device uchar4 *out [[buffer(0)]],
                               constant float *table [[buffer(1)]],
                               constant DisplayParams &p [[buffer(2)]],
                               constant float *m [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= tile.get_width() || gid.y >= tile.get_height()) { return; }
        out[(gid.y + p.y) * p.stride + gid.x + p.x] = display_bytes(float4(tile.read(gid)), table, p.p3, m);
    }

    kernel void display_target(texture2d<half, access::read> tile [[texture(0)]],
                               texture2d<float, access::write> out [[texture(1)]],
                               constant float *table [[buffer(1)]],
                               constant DisplayParams &p [[buffer(2)]],
                               constant float *m [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= tile.get_width() || gid.y >= tile.get_height()) { return; }
        uint4 v = uint4(display_bytes(float4(tile.read(gid)), table, p.p3, m));
        if (p.stride != 0 && v.a != 255) { v.rgb = (v.rgb * v.a + 127) / 255; }
        out.write(float4(v) / 255.0f, uint2(gid.x + p.x, gid.y + p.y));
    }
    """

    /// `DisplayParams`, `display_level` and `display_bytes`, which `display_tone` (ToneShader.swift) shares.
    static let functions = """
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

    static uchar4 display_bytes(float4 px, constant float *table, uint p3, constant float *m) {
        if (px.a == 0.0f) { return uchar4(0); }
        float3 c = px.a == 1.0f ? px.rgb : px.rgb / px.a;
        if (p3 != 0) {
            c = float3(m[0] * c.r + m[1] * c.g + m[2] * c.b,
                       m[3] * c.r + m[4] * c.g + m[5] * c.b,
                       m[6] * c.r + m[7] * c.g + m[8] * c.b);
        }
        return uchar4(display_level(c.r, table), display_level(c.g, table),
                      display_level(c.b, table), display_level(px.a, table + 255));
    }
    """
}
#endif
