// ParityHarness.swift: two compares. `compare(_:_:tolerance:)` checks two live results: their
// sRGB display bytes (CoreRaster's `rgba8`) and the linear premultiplied Floats of visible
// pixels (alpha over 0.01 in either result). `compare(golden:_:)` checks a result against a
// golden in bytes only, encoded as the golden was: a golden's bytes decoded to linear are off
// by up to half a display level (about 0.0045 near white), more than any linear tolerance.
// Both compare bytes the same way: where both alpha bytes are 0 the pixel is invisible and only
// alpha counts, since an alpha under half a level keeps its clamped color (0 or 255) on one
// backend and is flushed to 0, 0, 0, 0 on another.
import CoreRaster

/// What `compare` found: the worst deltas and the first pixel with each.
public struct ParityResult: Equatable, Sendable, CustomStringConvertible {
    /// Both worst deltas are within the tolerance.
    public let passed: Bool
    /// The largest per-channel difference of the 8-bit display bytes (sRGB, or
    /// the golden's color space for `compare(golden:_:)`).
    public let worstByteDelta: UInt8
    /// The column, then the row, of the first pixel (row-major) with `worstByteDelta`.
    public let worstByteX: Int, worstByteY: Int
    /// The largest per-component difference of the linear premultiplied
    /// Floats, over pixels whose alpha is above 0.01 in either buffer; 0 from
    /// `compare(golden:_:)`, which checks bytes only.
    public let worstLinearDelta: Float
    /// The column, then the row, of the first pixel (row-major) with `worstLinearDelta`.
    public let worstLinearX: Int, worstLinearY: Int
    /// True from `compare(golden:_:)`, which checks bytes only.
    public let bytesOnly: Bool

    /// One line: pass or FAIL, then each worst delta it checked and its pixel.
    public var description: String {
        "\(passed ? "pass" : "FAIL"): bytes \(worstByteDelta) at (\(worstByteX), \(worstByteY))"
            + (bytesOnly ? "" : ", linear \(worstLinearDelta) at (\(worstLinearX), \(worstLinearY))")
    }
}

/// The parity harness: compare, sample sets, rendering on a backend, goldens.
public enum ParityHarness {
    /// Compares `a` with `b` twice: their 8-bit sRGB display bytes, and the
    /// linear premultiplied Floats of every pixel whose alpha is above 0.01 in
    /// either buffer. Reports each worst delta at the first pixel, row-major,
    /// that has it; passes when both are within `tolerance`. Use it for two
    /// live results (backend against backend); against a golden use
    /// `compare(golden:_:)`. Throws `RenderError.raster` naming both sizes when they differ.
    public static func compare(_ a: PixelBuffer, _ b: PixelBuffer,
                               tolerance: ParityTolerance) throws -> ParityResult {
        try checkSizes(a.width, a.height, b.width, b.height)
        let bytesA = try RenderError.mapping { try a.rgba8(colorSpace: .sRGB) }
        let bytesB = try RenderError.mapping { try b.rgba8(colorSpace: .sRGB) }
        let (worstByte, bytePixel) = worstByteDelta(bytesA, bytesB)
        var (worstLinear, linearX, linearY): (Float, Int, Int) = (0, 0, 0)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let (p, q) = try RenderError.mapping { (try a.pixel(x: x, y: y), try b.pixel(x: x, y: y)) }
                guard max(p.a, q.a) > 0.01 else { continue }
                let delta = max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
                if delta > worstLinear { (worstLinear, linearX, linearY) = (delta, x, y) }
            }
        }
        return ParityResult(passed: worstByte <= tolerance.bytes && worstLinear <= tolerance.linear,
                            worstByteDelta: worstByte, worstByteX: bytePixel % a.width,
                            worstByteY: bytePixel / a.width, worstLinearDelta: worstLinear,
                            worstLinearX: linearX, worstLinearY: linearY, bytesOnly: false)
    }

    /// Compares `result` with `golden` in bytes only: `result` is encoded into
    /// the golden's color space as `ParityGolden.init` encoded the golden, and
    /// passes when no byte differs by more than the golden's `tolerance.bytes`.
    /// Use it for any backend against a checked-in golden; the linear bound
    /// cannot hold there, as the file header says. Throws `RenderError.raster`
    /// naming both sizes when they differ.
    public static func compare(golden: ParityGolden, _ result: PixelBuffer) throws -> ParityResult {
        let header = golden.header
        try checkSizes(header.width, header.height, result.width, result.height)
        let bytes = try RenderError.mapping { try result.rgba8(colorSpace: header.colorSpace) }
        let (worst, pixel) = worstByteDelta(golden.bytes, bytes)
        return ParityResult(passed: worst <= header.tolerance.bytes, worstByteDelta: worst,
                            worstByteX: pixel % header.width, worstByteY: pixel / header.width,
                            worstLinearDelta: 0, worstLinearX: 0, worstLinearY: 0, bytesOnly: true)
    }

    private static func checkSizes(_ aw: Int, _ ah: Int, _ bw: Int, _ bh: Int) throws {
        guard aw == bw, ah == bh else { throw RenderError.raster("compare sizes differ: \(aw)x\(ah) vs \(bw)x\(bh)") }
    }

    /// The largest per-byte difference and the index of the first pixel with it. A pixel whose
    /// alpha byte is 0 in both is invisible, so only its alpha byte counts (see the file header).
    private static func worstByteDelta(_ a: [UInt8], _ b: [UInt8]) -> (UInt8, Int) {
        var (worst, pixel): (UInt8, Int) = (0, 0)
        for i in stride(from: 0, to: min(a.count, b.count) - 3, by: 4) {
            let channels = a[i + 3] == 0 && b[i + 3] == 0 ? 3..<4 : 0..<4
            for c in channels where max(a[i + c], b[i + c]) - min(a[i + c], b[i + c]) > worst {
                (worst, pixel) = (max(a[i + c], b[i + c]) - min(a[i + c], b[i + c]), i / 4)
            }
        }
        return (worst, pixel)
    }
}
