// DisplayTable.swift: CoreColor's `DisplayTransfer` byte rules as Float thresholds for the Metal display
// kernel (metal-backend MB-3; GPUs have no Double). Curve entry k - 1 is the least Float whose byte is
// at least k, by bisection through `DisplayTransfer` itself, so a Float gets exactly the CPU's byte; the
// alpha half does the same for `DisplayTransfer.byte`. P3 adds the linear sRGB to P3 matrix as Float.
// `encode` is the kernel in Swift (DisplayShader.swift mirrors it). `level` reads base...base + 254 only.
import CoreColor
import CoreRaster

/// The display encode as Float tables: what the Metal kernel uploads and what `encode` mirrors.
public struct DisplayTable: Equatable, Sendable {
    /// Thresholds per half: one per byte step from 1 to 255.
    public static let levels = 255
    /// Where the alpha half starts in `thresholds`.
    public static let alphaBase = levels

    /// `.sRGB` or `.displayP3`.
    public let space: ColorSpace
    /// The curve thresholds, then the alpha thresholds: `2 * levels` Floats.
    public let thresholds: [Float]
    /// Linear sRGB to linear Display P3, row-major, 9 entries; nil for sRGB.
    public let matrix: [Float]?

    /// The table for `space`. Throws `RenderError.raster` for a space other than `.sRGB` or `.displayP3`.
    public init(_ space: ColorSpace) throws {
        guard PixelBuffer.displayColorSpaces.contains(space) else {
            throw RenderError.raster("color space \(space.rawValue): display tables must be sRGB or displayP3")
        }
        self.space = space
        thresholds = Self.shared
        matrix = space == .displayP3 ? try Self.p3Matrix() : nil
    }

    /// One premultiplied pixel as straight-alpha bytes, as the kernel does it: alpha 0 gives zeros, else
    /// unpremultiply (skipped at alpha 1), apply `matrix`, and take each component's and alpha's `level`.
    public func encode(_ p: RGBA) -> [UInt8] {
        guard p.a != 0 else { return [0, 0, 0, 0] }
        var (r, g, b) = p.a == 1 ? (p.r, p.g, p.b) : (p.r / p.a, p.g / p.a, p.b / p.a)
        if let m = matrix, m.count == 9 {
            (r, g, b) = (m[0] * r + m[1] * g + m[2] * b, m[3] * r + m[4] * g + m[5] * b,
                         m[6] * r + m[7] * g + m[8] * b)
        }
        return [Self.level(r, thresholds, base: 0), Self.level(g, thresholds, base: 0),
                Self.level(b, thresholds, base: 0), Self.level(p.a, thresholds, base: Self.alphaBase)]
    }

    /// How many of the `levels` thresholds from `base` are at or under `v` (NaN: 0), by an eight-step
    /// search reading `table[base ... base + 254]` only; 0 when `table` is shorter than that.
    public static func level(_ v: Float, _ table: [Float], base: Int) -> UInt8 {
        guard base >= 0, table.count >= base + levels else { return 0 }
        var index = 0
        var step = 128
        while step > 0 {
            if v >= table[base + index + step - 1] { index += step }
            step >>= 1
        }
        return UInt8(truncatingIfNeeded: index)
    }

    /// Both halves, built once: the curve's from `DisplayTransfer(.sRGB)`, the alpha's from `byte`.
    private static let shared: [Float] = {
        guard let transfer = try? DisplayTransfer(.sRGB) else { return [] }
        let curve = { (v: Float) in transfer.encode(Color3(Double(v), 0, 0)).0 }
        let alpha = { (v: Float) in DisplayTransfer.byte(Double(v)) }
        return (1...levels).map { least(curve, $0) } + (1...levels).map { least(alpha, $0) }
    }()

    /// The smallest Float in 0...1 with `rule(v) >= k`, by bisection on bit patterns (non-negative
    /// Floats order as their bits do, and both rules are non-decreasing and give 255 at 1).
    private static func least(_ rule: (Float) -> UInt8, _ k: Int) -> Float {
        var lo: UInt32 = 0
        var hi = (1 as Float).bitPattern
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if Int(rule(Float(bitPattern: mid))) >= k { hi = mid } else { lo = mid + 1 }
        }
        return Float(bitPattern: lo)
    }

    /// Linear sRGB to linear P3: column c is the linear P3 of the unit linear sRGB color c, through the
    /// same conversion the CPU's encode uses. Throws `RenderError.raster` if a conversion fails.
    private static func p3Matrix() throws -> [Float] {
        let columns = try [Color3(1, 0, 0), Color3(0, 1, 0), Color3(0, 0, 1)].map { unit in
            let p3: Color3
            do { p3 = try unit.converted(from: .linearSRGB, to: .displayP3) } catch {
                throw RenderError.raster("display P3 matrix: \(error)")
            }
            return [p3.c0, p3.c1, p3.c2].map { Float(TransferCurve.decode($0)) }
        }
        return (0..<9).map { columns[$0 % 3][$0 / 3] }
    }
}
