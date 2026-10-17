// ResampleShader.swift: the resample MSL (MB-8). `resample_pass` runs one 1-D ResampleTable pass, one thread per
// output pixel and line; `resample_scatter` writes a tile clamped to the finite half range. Grids may round up.
#if canImport(Metal)
import CoreRender

enum ResampleShader {
    static let pass = PipelineKey(op: .resample, variant: "pass")
    static let scatter = PipelineKey(op: .resample, variant: "scatter")

    /// The pass takes float4 buffers 0 (input) and 1 (output), the table's offsets, indices and weights at 2,
    /// 3 and 4, and buffer 5 as six ints: lines, new length, the input's pixel step along and across a line,
    /// then the output's. Scatter takes buffer 1 as five ints: the tile's x, y, width, height, image width.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void resample_pass(device const float4 *in [[buffer(0)]],
                              device float4 *out [[buffer(1)]],
                              device const int *offsets [[buffer(2)]],
                              device const int *indices [[buffer(3)]],
                              device const float *weights [[buffer(4)]],
                              constant int *p [[buffer(5)]],
                              uint2 gid [[thread_position_in_grid]]) {
        int i = int(gid.x), line = int(gid.y);
        if (i >= p[1] || line >= p[0]) { return; }
        float4 sum = float4(0.0f);
        for (int k = offsets[i]; k < offsets[i + 1]; k++) {
            sum += weights[k] * in[line * p[3] + indices[k] * p[2]];
        }
        out[line * p[5] + i * p[4]] = sum;
    }
    kernel void resample_scatter(device const float4 *in [[buffer(0)]],
                                 texture2d<half, access::write> dst [[texture(0)]],
                                 constant int *p [[buffer(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
        int2 g = int2(gid);
        if (g.x >= p[2] || g.y >= p[3]) { return; }
        float4 v = in[(p[1] + g.y) * p[4] + p[0] + g.x];
        dst.write(half4(clamp(v, float4(-65504.0f), float4(65504.0f))), gid);
    }
    """
}
#endif
