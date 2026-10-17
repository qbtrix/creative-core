// ParityHarness.swift: `compare` checks the sRGB display bytes (CoreRaster's `rgba8`) and
// the linear premultiplied Floats of visible pixels (alpha over 0.01 in either result).
import CoreRaster

/// What `compare` found: the worst deltas and the first pixel with each.
public struct ParityResult: Equatable, Sendable, CustomStringConvertible {
    /// Both worst deltas are within the tolerance.
    public let passed: Bool
    public let worstByteDelta: UInt8, worstByteX: Int, worstByteY: Int
    public let worstLinearDelta: Float, worstLinearX: Int, worstLinearY: Int

    public var description: String {
        "\(passed ? "pass" : "FAIL"): bytes \(worstByteDelta) at (\(worstByteX), \(worstByteY)), "
            + "linear \(worstLinearDelta) at (\(worstLinearX), \(worstLinearY))"
    }
}

/// The parity harness: compare, sample sets, rendering on a backend, goldens.
public enum ParityHarness {
    /// Compares `a` with `b`. Throws `RenderError.surfaceMismatch` when their sizes differ.
    public static func compare(_ a: PixelBuffer, _ b: PixelBuffer,
                               tolerance: ParityTolerance) throws -> ParityResult {
        guard a.width == b.width, a.height == b.height else { throw RenderError.surfaceMismatch }
        let bytesA = try raster { try a.rgba8(colorSpace: .sRGB) }
        let bytesB = try raster { try b.rgba8(colorSpace: .sRGB) }
        var (worstByte, bytePixel): (UInt8, Int) = (0, 0)
        for (i, (p, q)) in zip(bytesA, bytesB).enumerated() where max(p, q) - min(p, q) > worstByte {
            (worstByte, bytePixel) = (max(p, q) - min(p, q), i / 4)
        }
        var (worstLinear, linearX, linearY): (Float, Int, Int) = (0, 0, 0)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let (p, q) = try raster { (try a.pixel(x: x, y: y), try b.pixel(x: x, y: y)) }
                guard max(p.a, q.a) > 0.01 else { continue }
                let delta = max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
                if delta > worstLinear { (worstLinear, linearX, linearY) = (delta, x, y) }
            }
        }
        return ParityResult(passed: worstByte <= tolerance.bytes && worstLinear <= tolerance.linear,
                            worstByteDelta: worstByte, worstByteX: bytePixel % a.width,
                            worstByteY: bytePixel / a.width, worstLinearDelta: worstLinear,
                            worstLinearX: linearX, worstLinearY: linearY)
    }

    /// Runs `body`, passing a CoreRaster error through as `RenderError.raster`.
    static func raster<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch RasterError.invalid(let message) { throw RenderError.raster(message) }
    }
}
