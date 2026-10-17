// FakeBackend.swift: a RenderBackend test double for contract tests and
// RenderDispatcher, the routing between backends. It supports the op families it is
// given, records every call in order, and holds real PixelBuffers in a
// SurfaceStore so `read(surface(b))` is `b`. It is not a pixel reference: crop,
// rotate and resample give
// CoreRaster's result so sizes are right, display gives `rgba8`, the filter
// ops (blur, unsharp, adjust, clone) return a new surface with the pixels
// unchanged, and composite checks both surfaces and leaves `b` alone.
// Invariants: every method records its call first; an op outside `supports`
// then throws `unsupported` with the family that gates it; a surface this fake
// did not make, or released, throws `surfaceMismatch`. Copies share the log
// and the store, so a copy handed to other code, such as RenderDispatcher,
// reports to the test's copy.

import CoreColor
import CoreRaster

/// A RenderBackend that supports a chosen set of op families and records calls.
public struct FakeBackend: RenderBackend {
    /// One recorded call, in the order the fake received it.
    public enum Call: Equatable, Sendable {
        /// `surface(_:)` with a buffer of this size.
        case surface(width: Int, height: Int)
        /// `read(_:)` of this surface.
        case read(RenderSurface)
        /// `release(_:)` of this surface.
        case release(RenderSurface)
        /// An op method, named by the family that gates it (a composite
        /// through `.hue` records `.op(.blendNonSeparable)`).
        case op(RenderOp)
    }

    public let name: String
    /// The families the fake performs; any other op throws `unsupported`.
    public var supports: Set<RenderOp>
    /// What `isHealthy` reports. An unhealthy fake still performs every op it
    /// supports when called directly; only RenderDispatcher reads its health.
    public var healthy: Bool
    public var isHealthy: Bool { healthy }

    private let log = Locked<[Call]>([])
    private let store: SurfaceStore

    /// A fake named `name` (written into its surfaces) that supports `supports`.
    public init(name: String = "fake", supports: Set<RenderOp>, healthy: Bool = true) {
        self.name = name
        self.supports = supports
        self.healthy = healthy
        self.store = SurfaceStore(backend: name)
    }

    /// Every call so far, oldest first, from this fake and all its copies.
    public var calls: [Call] { log.withLock { $0 } }

    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        record(.surface(width: buffer.width, height: buffer.height))
        return store.insert(buffer)
    }

    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        record(.read(surface))
        return try store.buffer(for: surface)
    }

    public func release(_ surface: RenderSurface) {
        record(.release(surface))
        store.remove(surface)
    }

    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try RenderError.mapping { try input(s, .display).rgba8(colorSpace: colorSpace) }
    }

    /// Checks both surfaces and the family, then leaves `b` unchanged.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        _ = try input(s, RenderOp(compositing: mode))
        _ = try store.buffer(for: b)
    }

    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        store.insert(try RenderError.mapping { try input(s, .transform).cropped(x: x, y: y, width: width, height: height) })
    }

    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        store.insert(try input(s, .transform).rotated(turn))
    }

    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        store.insert(try RenderError.mapping { try input(s, .resample).resized(width: width, height: height, filter: filter) })
    }

    // The filter ops: a new surface with `s`'s pixels unchanged.
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        store.insert(try input(s, .blur))
    }
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        store.insert(try input(s, .blur))
    }
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        store.insert(try input(s, .adjust))
    }
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        store.insert(try input(s, .retouch))
    }

    private func record(_ call: Call) {
        log.withLock { $0.append(call) }
    }

    /// Records `.op(op)`, throws `unsupported(op)` outside `supports`, then
    /// returns `s`'s pixels or throws `surfaceMismatch`.
    private func input(_ s: RenderSurface, _ op: RenderOp) throws -> PixelBuffer {
        record(.op(op))
        guard supports.contains(op) else { throw RenderError.unsupported(op) }
        return try store.buffer(for: s)
    }
}
