// RenderOp.swift: the op families a RenderBackend may support, and the one
// error type of CoreRender, which CoreRenderMetal shares. A backend lists the
// families it implements in `supports`; RenderDispatcher, the routing between
// backends, sends each op only to a backend that lists it, so a backend throws
// `unsupported` for an unlisted family only when it is called directly. A
// backend may also throw `unsupported` for a listed family when the input is
// over its device limit; RenderDispatcher passes that error on without
// retrying, and the caller runs the op on the CPU backend (its `fallback`).
// Contract types, plus the two
// mappings every backend shares: a blend mode to the family that gates it, and
// a CoreRaster error to `RenderError.raster` (`init(_:)` and `mapping`,
// render-backend RB-2).
import CoreRaster

/// One family of render operations. A backend declares the families it
/// implements; RenderDispatcher sends an op only to a backend that lists
/// its family. The raw value is the case name, for logs and goldens.
public enum RenderOp: String, CaseIterable, Codable, Sendable {
    /// `display`: a surface to sRGB or Display P3 bytes for the screen.
    case display
    /// `composite` with `BlendMode.normal`: source over, with opacity.
    case composite
    /// `composite` with a separable mode (multiply, screen, overlay, ...).
    case blendSeparable
    /// `composite` with a non-separable mode (hue, saturation, color, luminosity).
    case blendNonSeparable
    /// `cropped` and `rotated`: exact pixel rearrangements.
    case transform
    /// `resampled`: a filtered resize.
    case resample
    /// `gaussianBlur` and `unsharpMask`: convolution.
    case blur
    /// `adjusted` with a tone adjustment whose `family` is `.adjust`: the
    /// six from before W1 (exposure, levels, curves, white balance, contrast,
    /// highlights and shadows).
    case adjust
    /// `cloned`: a masked copy offset within the surface.
    case retouch
    /// `composite(_:onto:x:y:mode:opacity:mask:maskX:maskY:)`: a composite
    /// whose coverage is scaled by a mask. CPU first (`notOnMetalYet`).
    case maskedComposite
    /// `transformed`, `flipped` and `composite(_:onto:through:mode:opacity:filter:)`:
    /// an affine matrix or a mirror, filtered. CPU first (`notOnMetalYet`).
    case affine
    /// `applying(_:)`: every `LayerEffect`. CPU first (`notOnMetalYet`).
    case effect
    /// `adjusted` with a tone adjustment whose `family` is `.color`: the W1
    /// colour adjustments (vibrance to invert). CPU first (`notOnMetalYet`).
    case color
    /// `styled(_:_:)`: a `LayerStyleStack` drawn on a layer. CPU first (`notOnMetalYet`).
    case style
}

extension RenderOp {
    /// The CPU-first families no Metal kernel implements yet. The Metal
    /// backend enables none of them, so RenderDispatcher sends each to the
    /// CPU; a family leaves this set when its kernel and parity test land.
    public static let notOnMetalYet: Set<RenderOp> = [.maskedComposite, .affine, .effect, .color, .style]
}

extension RenderOp {
    /// The family that gates `composite` through `mode`: `.composite` for
    /// `.normal`, `.blendNonSeparable` for hue, saturation, color and
    /// luminosity, and `.blendSeparable` for every other mode.
    public init(compositing mode: BlendMode) {
        switch mode {
        case .normal: self = .composite
        case .hue, .saturation, .color, .luminosity: self = .blendNonSeparable
        default: self = .blendSeparable
        }
    }
}

/// What a backend throws. Each case says when; a backend never crashes.
public enum RenderError: Error, Equatable, Sendable {
    /// The op's family is not in the backend's `supports` (RenderDispatcher
    /// sends an op only to a backend that lists it), or this input is over
    /// this backend's device limit (the Metal backend's `maxBufferLength` for
    /// display, resample, blur (gaussianBlur and unsharpMask) and retouch
    /// (cloned)): run it on the CPU backend, which
    /// has no such limit. The backend stays healthy, and RenderDispatcher
    /// passes this error on without retrying the op on its `fallback`.
    /// A W1 family `f` in `RenderOp.notOnMetalYet` is the exception to that
    /// remedy: until its feature lands, every backend, the CPU included,
    /// throws `unsupported(f)` from a method that is not built yet, even when
    /// `f` is in `supports`. There is no fallback: the caller skips the op.
    case unsupported(RenderOp)
    /// The GPU stopped answering, with the reason the platform gave: no
    /// command queue, a tile texture it would not allocate (out of memory), a
    /// failed command buffer, or a probe that returned wrong numbers. The
    /// backend reports `isHealthy == false` from then on. The Metal backend
    /// offers `MetalBackend.recover(probeSource:)` on the concrete type (not on
    /// `RenderBackend` or `RenderDispatcher`): if it throws too, the device is
    /// gone and the app opens a new backend on a new device. Out of memory is
    /// the exception: `recover` passes but the upload fails again until the
    /// app releases surfaces or lowers `MetalBackend.budgetBytes`.
    case deviceLost(String)
    /// The surface belongs to another backend (its `backend` is not this
    /// backend's `name`), this backend already released it, or the handle's
    /// width and height do not match its stored pixels.
    case surfaceMismatch
    /// Invalid input or data, with a message saying which: a CoreRaster error
    /// passed through (from a backend's op, a buffer read in or out, or a
    /// parity compare of two sizes), a rejected argument (a pipeline variant,
    /// a tile index, a golden name, a malformed parity sample), an unreadable
    /// or malformed golden file, or a broken internal invariant of a backend.
    case raster(String)
}

extension RenderError {
    /// A CoreRaster error as `.raster`, its message passed through.
    public init(_ error: RasterError) {
        switch error {
        case .invalid(let message): self = .raster(message)
        }
    }

    /// Runs `body`, rethrowing any CoreRaster error as `RenderError(_:)`, so
    /// every backend and helper maps raster errors the same way.
    public static func mapping<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as RasterError { throw RenderError(error) }
    }
}
