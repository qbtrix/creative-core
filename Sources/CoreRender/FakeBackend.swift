// FakeBackend.swift: a RenderBackend for tests. It runs the ops in its
// `supports` set, throws `.unsupported` for the rest, can be made unhealthy,
// and records every call so a test can check what the dispatcher sent it. It
// holds no pixels: reads and displays return blanks of the surface's size.

import CoreColor
import CoreRaster
import Foundation

/// The calls a FakeBackend received, in order. A class only so a value-typed
/// fake can record calls from non-mutating protocol methods.
public final class FakeCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RenderOp] = []

    public init() {}

    /// Every op the fake was asked to run, refused ones included.
    public var calls: [RenderOp] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ op: RenderOp) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(op)
    }
}

/// A test backend that runs only the ops it was given.
public struct FakeBackend: RenderBackend {
    public let name: String
    public let supports: Set<RenderOp>
    public var healthy: Bool
    public let log: FakeCallLog

    public init(name: String = "fake", supports: Set<RenderOp>, healthy: Bool = true) {
        self.name = name
        self.supports = supports
        self.healthy = healthy
        self.log = FakeCallLog()
    }

    public var isHealthy: Bool { healthy }

    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        made(width: buffer.width, height: buffer.height)
    }

    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        try run(.display)
        return try PixelBuffer(width: surface.width, height: surface.height)
    }

    public func release(_ surface: RenderSurface) {}

    public func display(_ surface: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try run(.display)
        return [UInt8](repeating: 0, count: surface.width * surface.height * 4)
    }

    public func composite(_ source: RenderSurface, onto backdrop: inout RenderSurface,
                          x: Int, y: Int, mode: BlendMode, opacity: Float) throws {
        try run(.composite)
    }

    public func cropped(_ surface: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try run(.transform)
        return made(width: width, height: height)
    }

    public func rotated(_ surface: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        try run(.transform)
        return made(width: surface.height, height: surface.width)
    }

    public func resampled(_ surface: RenderSurface, width: Int, height: Int,
                          filter: ResampleFilter) throws -> RenderSurface {
        try run(.resample)
        return made(width: width, height: height)
    }

    public func gaussianBlur(_ surface: RenderSurface, sigma: Double) throws -> RenderSurface {
        try run(.blur)
        return made(width: surface.width, height: surface.height)
    }

    public func unsharpMask(_ surface: RenderSurface, amount: Double, sigma: Double,
                            threshold: Double) throws -> RenderSurface {
        try run(.blur)
        return made(width: surface.width, height: surface.height)
    }

    public func adjusted(_ surface: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try run(.adjust)
        return made(width: surface.width, height: surface.height)
    }

    public func cloned(_ surface: RenderSurface, offset: (dx: Int, dy: Int),
                       through mask: Mask) throws -> RenderSurface {
        try run(.retouch)
        return made(width: surface.width, height: surface.height)
    }

    /// Records the call, then throws `.unsupported` when the fake does not run `op`.
    private func run(_ op: RenderOp) throws {
        log.record(op)
        guard supports.contains(op) else { throw RenderError.unsupported(op) }
    }

    private func made(width: Int, height: Int) -> RenderSurface {
        RenderSurface(id: UUID(), width: width, height: height, backend: name)
    }
}
