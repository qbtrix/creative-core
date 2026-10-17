// UnsharpShader.swift: the unsharp MSL (MB-12). `blur_unsharp` finishes MB-11's blur down each column of the buffer
// BlurShader's `blur_pass` blurred across (same taps and sum) and sharpens every component with UnsharpRule's
// parameters: `sharpen` is UnsharpRule.apply's Float32 rule (strict threshold, fused multiply-add), which
// UnsharpRuleTests checks on Linux. One thread per pixel; grids may round up; ResampleShader's `resample_scatter`
// writes the result to tiles.
#if canImport(Metal)
import CoreRender

enum UnsharpShader {
    static let mask = PipelineKey(op: .blur, variant: "unsharp")

    /// Takes float4 buffers 0 (the source pixels), 1 (the source blurred across rows) and 2 (output, the same
    /// layout), the BlurTable weights at 3, buffer 4 as three ints (width, height, radius) and buffer 5 as two
    /// floats (amount, threshold).
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    static float sharpen(float x, float b, float amount, float threshold) {
        float d = x - b;
        return (d > threshold || d < -threshold) ? fma(amount, d, x) : x;
    }
    kernel void blur_unsharp(device const float4 *src [[buffer(0)]],
                             device const float4 *across [[buffer(1)]],
                             device float4 *out [[buffer(2)]],
                             device const float *weights [[buffer(3)]],
                             constant int *p [[buffer(4)]],
                             constant float *f [[buffer(5)]],
                             uint2 gid [[thread_position_in_grid]]) {
        int x = int(gid.x), y = int(gid.y), w = p[0], h = p[1], r = p[2];
        if (x >= w || y >= h) { return; }
        float4 b = float4(0.0f);
        for (int k = 0; k <= 2 * r; k++) {
            int j = y + k - r;
            j = j < 0 ? 0 : (j > h - 1 ? h - 1 : j);
            b += weights[k] * across[j * w + x];
        }
        float4 s = src[y * w + x];
        out[y * w + x] = float4(sharpen(s.x, b.x, f[0], f[1]), sharpen(s.y, b.y, f[0], f[1]),
                                sharpen(s.z, b.z, f[0], f[1]), sharpen(s.w, b.w, f[0], f[1]));
    }
    """
}
#endif
