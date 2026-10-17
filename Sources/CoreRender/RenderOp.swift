// RenderOp.swift: the op families a RenderBackend may support, and the one
// error type of CoreRender, which CoreRenderMetal shares. A backend lists the
// families it implements in `supports`; the dispatcher routes each op to a
// backend that lists it, so a backend throws `unsupported` only when the
// dispatcher was bypassed. Contract types, no logic (render-backend RB-2).

/// One family of render operations. A backend declares the families it
/// implements; the dispatcher sends an op only to a backend that lists its
/// family. The raw value is the case name, for logs and goldens.
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
    /// `adjusted`: every `ToneAdjustment`.
    case adjust
    /// `cloned`: a masked copy offset within the surface.
    case retouch
}

/// What a backend throws. Each case says when; a backend never crashes.
public enum RenderError: Error, Equatable, Sendable {
    /// The op's family is not in the backend's `supports`. The dispatcher
    /// should have routed it to a backend that lists the family.
    case unsupported(RenderOp)
    /// The GPU or its command queue is gone, with the reason the platform
    /// gave. The backend reports `isHealthy == false` from then on.
    case deviceLost(String)
    /// The surface belongs to another backend (its `backend` is not this
    /// backend's `name`), or this backend already released it.
    case surfaceMismatch
    /// A CoreRaster error, its message passed through, from the CPU backend
    /// or from a backend that reads a buffer in or out.
    case raster(String)
}
