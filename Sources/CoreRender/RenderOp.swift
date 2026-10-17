// RenderOp.swift: the operations a RenderBackend can run, and the errors it
// throws. Every op is one family of the contract; a backend lists the families
// it runs in `supports`, and the dispatcher sends the rest to the CPU.

/// One family of render work. A backend that does not list an op in
/// `supports` must throw `RenderError.unsupported` for it, never draw nothing.
public enum RenderOp: String, CaseIterable, Codable, Sendable {
    case display
    case composite
    case blendSeparable
    case blendNonSeparable
    case transform
    case resample
    case blur
    case adjust
    case retouch
}

/// The errors a RenderBackend throws. Backends map their own failures onto
/// these cases; a caller never sees a Metal or CPU-specific error type.
public enum RenderError: Error, Equatable, Sendable {
    /// The backend does not run this op.
    case unsupported(RenderOp)
    /// The device or context was lost; `reason` names what the backend saw.
    case deviceLost(String)
    /// A surface from another backend or a different size was handed to an op
    /// that needs them to match.
    case surfaceMismatch
    /// CoreRaster rejected the input; `message` is its message unchanged.
    case raster(String)
}
