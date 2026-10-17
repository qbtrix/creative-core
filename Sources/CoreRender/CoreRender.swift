// CoreRender: the one RenderBackend contract every app's Model draws through,
// its backends (a fake for tests, and the CPU backend over CoreRaster, the pixel
// reference, as it lands), the routing between backends as it lands, and the
// parity harness that measures a backend against the pixel reference.
// Linux-safe, Foundation only: the Metal backend lives in CoreRenderMetal, and
// its Linux-safe parts (capabilities, tiling math, cache keys) live here.
// This file is the target scaffold (render-backend RB-1); the contract is in
// RenderOp.swift, RenderSurface.swift, ToneAdjustment.swift and RenderBackend.swift.

/// Marks the CoreRender module; callers and tests can name it before the contract exists.
public enum CoreRenderTarget {
    public static let name = "CoreRender"
}
