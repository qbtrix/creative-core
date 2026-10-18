// RenderBackend+Resident.swift: the two contract methods resident rendering
// adds (`blank` and the batched `composite(_:onto:)`), with defaults built
// from the older methods, so the CPU backend and every test double run them
// unchanged and give exactly the pixels of the calls they stand for. A GPU
// backend replaces them to avoid a CPU upload and one command buffer per step.
// Invariant: the batched default checks every step's family before the first
// blend, so an unsupported step leaves `b` untouched.
import CoreRaster

/// One layer of a batched composite: `surface` blended onto the backdrop with
/// its top-left pixel at (`x`, `y`), through `mode` at `opacity`.
public struct CompositeStep: Sendable, Equatable {
    public let surface: RenderSurface
    public let x: Int
    public let y: Int
    public let mode: BlendMode
    public let opacity: Float

    public init(_ surface: RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float) {
        (self.surface, self.x, self.y, self.mode, self.opacity) = (surface, x, y, mode, opacity)
    }

    /// The family that gates this step.
    public var family: RenderOp { RenderOp(compositing: mode) }
}

extension RenderBackend {
    /// A clear `PixelBuffer` of the size, uploaded.
    public func blank(width: Int, height: Int) throws -> RenderSurface {
        try surface(RenderError.mapping { try PixelBuffer(width: width, height: height) })
    }

    /// One `composite(_:onto:x:y:mode:opacity:)` per step, after checking
    /// every step's family is in `supports`.
    public func composite(_ steps: [CompositeStep], onto b: inout RenderSurface) throws {
        if let missing = steps.first(where: { !supports.contains($0.family) }) {
            throw RenderError.unsupported(missing.family)
        }
        for step in steps {
            try composite(step.surface, onto: &b, x: step.x, y: step.y, mode: step.mode, opacity: step.opacity)
        }
    }
}
