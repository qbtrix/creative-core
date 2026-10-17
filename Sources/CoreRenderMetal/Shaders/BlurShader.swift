// BlurShader.swift: the blur MSL (MB-11). `blur_pass` runs one 1-D pass of a BlurTable over a whole-image float4
// buffer, one thread per pixel and line, its taps clamped to the line's ends (a border never reads black). The
// result is written to tiles by ResampleShader's `resample_scatter`. Grids may round up.
#if canImport(Metal)
import CoreRender

enum BlurShader {
    static let pass = PipelineKey(op: .blur, variant: "pass")

    /// Takes float4 buffers 0 (input) and 1 (output, the same layout), the table's weights at 2, and buffer 3 as
    /// five ints: lines, line length, radius, then the pixel step along and across a line.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void blur_pass(device const float4 *in [[buffer(0)]],
                          device float4 *out [[buffer(1)]],
                          device const float *weights [[buffer(2)]],
                          constant int *p [[buffer(3)]],
                          uint2 gid [[thread_position_in_grid]]) {
        int i = int(gid.x), line = int(gid.y), r = p[2];
        if (i >= p[1] || line >= p[0]) { return; }
        float4 sum = float4(0.0f);
        for (int k = 0; k <= 2 * r; k++) {
            int j = i + k - r;
            j = j < 0 ? 0 : (j > p[1] - 1 ? p[1] - 1 : j);
            sum += weights[k] * in[line * p[4] + j * p[3]];
        }
        out[line * p[4] + i * p[3]] = sum;
    }
    """
}
#endif
