// TransformShader.swift: the quarter-turn kernel's MSL (MB-7). One thread per destination pixel of a TilePiece
// copies the mapped source half4 unchanged (exact); threads past the piece return, so grids may round up.
#if canImport(Metal)
import CoreRender

enum TransformShader {
    /// The kernel `transform_rotate`.
    static let key = PipelineKey(op: .transform, variant: "rotate")

    /// Buffer 0 holds ten ints: destination x, y (local to its tile), piece width, height, source x, y
    /// (local to its tile) of the top-left pixel, then the source step per column (x, y) and per row (x, y).
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void transform_rotate(texture2d<half, access::read> src [[texture(0)]],
                                 texture2d<half, access::write> dst [[texture(1)]],
                                 constant int *p [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
        int2 g = int2(gid);
        if (g.x >= p[2] || g.y >= p[3]) { return; }
        int2 s = int2(p[4], p[5]) + g.x * int2(p[6], p[7]) + g.y * int2(p[8], p[9]);
        dst.write(src.read(uint2(s)), uint2(int2(p[0], p[1]) + g));
    }
    """
}
#endif
