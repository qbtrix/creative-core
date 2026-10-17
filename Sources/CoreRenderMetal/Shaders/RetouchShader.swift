// RetouchShader.swift: the clone MSL (metal-backend MB-15), compiled on first use. `retouch_clone` writes one
// output tile from a whole-image float4 buffer of the source and a whole-image coverage buffer (the mask's values,
// one float per pixel), one thread per tile pixel, as CoreRaster's `cloned`: pixel (x, y) whose source
// (x + dx, y + dy) lies on the image becomes c * source + (1 - c) * self on premultiplied components, any other
// pixel is copied unchanged; clamped to the finite half range as upload does. The host bounds |dx| < width and
// |dy| < height first, so the sums cannot overflow. Grids may round up.
#if canImport(Metal)
import CoreRender

enum RetouchShader {
    static let key = PipelineKey(op: .retouch, variant: "clone")

    /// Buffers: 0 the source pixels (float4, row-major), 1 the coverage (float, row-major), 2 eight ints: the
    /// tile's x, y, width, height, then the image width, height, dx and dy. Texture 0: the output tile.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void retouch_clone(device const float4 *in [[buffer(0)]],
                              device const float *coverage [[buffer(1)]],
                              constant int *p [[buffer(2)]],
                              texture2d<half, access::write> dst [[texture(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
        int2 g = int2(gid);
        if (g.x >= p[2] || g.y >= p[3]) { return; }
        int x = p[0] + g.x, y = p[1] + g.y, sx = x + p[6], sy = y + p[7];
        int at = y * p[4] + x;
        float4 v = in[at];
        if (sx >= 0 && sx < p[4] && sy >= 0 && sy < p[5]) {
            float c = coverage[at];
            if (c != 0.0f) { v = in[sy * p[4] + sx] * c + v * (1.0f - c); }
        }
        dst.write(half4(clamp(v, float4(-65504.0f), float4(65504.0f))), gid);
    }
    """
}
#endif
