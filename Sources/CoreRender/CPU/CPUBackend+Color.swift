// CPUBackend+Color.swift: the CPU backend's `.color` family, the W1 colour
// tone adjustments (vibrance to invert). `adjusted` (CPUBackend+Ops.swift)
// gates `s` by `.color` and hands its pixels here. A stub until the tone-pack
// feature fills this file: every case throws `RenderError.unsupported(.color)`.
// Invariants: called only with a `.color` case; the buffer is not changed.
import CoreRaster

extension CPUBackend {
    /// `buffer` with the `.color` case `adjustment` applied.
    func colorAdjusted(_ buffer: PixelBuffer, _ adjustment: ToneAdjustment) throws -> PixelBuffer {
        throw RenderError.unsupported(.color)
    }
}
