// ToneRendering.swift: a backend that runs a whole `ToneProgram` (Metal/ToneProgram.swift) over a surface in one
// pass, so an app can apply a chain of tone adjustments (an adjustment layer's, say) without a surface per
// adjustment or a readback. `CPUBackend` conforms by reading the surface, mapping each pixel through
// `ToneProgram.map` and storing the result: the reference the Metal backend's `adjust_program` kernel matches
// within `ParityTolerance.standard`. The source is unchanged; an empty program gives a copy. Linux-safe.
import CoreRaster

/// A backend that applies a tone program to a surface.
public protocol ToneRendering: RenderBackend {
    /// `s` with `tone` applied to each pixel, as a new surface the caller releases.
    func adjusted(_ s: RenderSurface, tone: ToneProgram) throws -> RenderSurface
}

extension CPUBackend: ToneRendering {
    public func adjusted(_ s: RenderSurface, tone: ToneProgram) throws -> RenderSurface {
        let source = try read(s)
        var out = try RenderError.mapping { try PixelBuffer(width: source.width, height: source.height) }
        for y in 0..<source.height {
            for x in 0..<source.width {
                try RenderError.mapping { try out.setPixel(x: x, y: y, tone.map(try source.pixel(x: x, y: y))) }
            }
        }
        return try surface(out)
    }
}
