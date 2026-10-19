// ToneProgram.swift: a chain of tone adjustments as the data one Metal pass runs per pixel (the `display_tone`
// kernel, Shaders/ToneShader.swift), so a live slider re-encodes a resident picture with its adjustments in one
// dispatch: no intermediate surfaces, no readback. Each step is one `ToneAdjustment`, applied in order to the
// straight color as `CPUBackend.adjusted` applies them one after another. Exposure, levels, curves, white
// balance, contrast and highlights/shadows are their `AdjustTable` (gains, or a table and its two octave
// tables, concatenated into `tables` at the step's `offset`); hue/saturation is math, standard HSL on the
// clamped sRGB-encoded values as CoreRaster's `hueSaturation` does it, in Float. A `matrix` operation is a
// 3x3 matrix on the straight linear color, negatives clamped to 0, then a lightness mix toward white (positive)
// or black (negative): an app's own colour matrix (Photo's Hue/Saturation), its nine entries and lightness in
// `tables` at the step's offset. Any other adjustment throws `RenderError.unsupported(.color)`. Parameters are
// checked by the CPU backend, so a bad one throws its error. `map` is the kernel in Swift. Linux-safe.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreRaster

/// Tone adjustments in order, as the Float data one GPU pass reads.
public struct ToneProgram: Equatable, Sendable {
    /// One operation of a program: a tone adjustment, or a colour matrix with a lightness mix.
    public enum Operation: Equatable, Sendable {
        case adjustment(ToneAdjustment)
        /// Straight linear color times `rows` (row-major 3x3), each result below 0 clamped to 0, then mixed
        /// toward white by `lightness` when positive (c + (1 - c) x l) or toward black when negative (c x (1 + l)).
        /// Nine finite entries and a finite `lightness` in -1...1.
        case matrix(rows: [Float], lightness: Float)
    }

    /// One step. `kind` 0 to 2 are `AdjustTable.Kind`; 3 is hue/saturation, 4 a matrix.
    public struct Step: Equatable, Sendable {
        /// `AdjustTable.Kind.rawValue`, or `hueSaturation`.
        public let kind: UInt32
        /// The gains (kind 0), or hue in degrees, saturation and lightness in -100...100 (kind 3).
        public let values: SIMD3<Float>
        /// The table's intervals over 0...1 (0 without a table).
        public let n: UInt32
        /// Entries of each octave table (0 without).
        public let outer: UInt32
        /// Where the step's table starts in `tables`.
        public let offset: UInt32
    }

    /// `Step.kind` of hue/saturation.
    public static let hueSaturation: UInt32 = 3
    /// `Step.kind` of a matrix operation.
    public static let matrix: UInt32 = 4

    public let steps: [Step]
    /// Every step's table, then its octave tables below and above, back to back.
    public let tables: [Float]
    /// Each step's AdjustTable (nil for hue/saturation and a matrix), for `map`.
    private let adjustTables: [AdjustTable?]

    /// The program for `adjustments`, in order. Throws as `init(operations:)` does.
    public init(_ adjustments: [ToneAdjustment]) throws {
        try self.init(operations: adjustments.map(Operation.adjustment))
    }

    /// The program for `operations`, in order. Throws the CPU backend's error for a bad parameter,
    /// `RenderError.raster` for a matrix that isn't nine finite entries with a finite lightness in -1...1, and
    /// `RenderError.unsupported(.color)` for an adjustment the program has no step for.
    public init(operations: [Operation]) throws {
        var steps: [Step] = [], tables: [Float] = [], adjustTables: [AdjustTable?] = []
        for operation in operations {
            let adjustment: ToneAdjustment
            switch operation {
            case .adjustment(let made): adjustment = made
            case .matrix(let rows, let lightness):
                guard rows.count == 9, rows.allSatisfy(\.isFinite), lightness.isFinite, (-1...1).contains(lightness) else {
                    throw RenderError.raster("tone matrix: needs 9 finite entries and a lightness in -1...1")
                }
                steps.append(Step(kind: Self.matrix, values: .zero, n: 0, outer: 0, offset: UInt32(tables.count)))
                tables += rows + [lightness]
                adjustTables.append(nil)
                continue
            }
            if case .hueSaturation(let hue, let saturation, let lightness) = adjustment {
                // The CPU checks the ranges and throws its own error.
                let cpu = CPUBackend()
                _ = try cpu.adjusted(cpu.surface(RenderError.mapping { try PixelBuffer(width: 1, height: 1) }), adjustment)
                steps.append(Step(kind: Self.hueSaturation, values: SIMD3(hue, saturation, lightness), n: 0, outer: 0, offset: 0))
                adjustTables.append(nil)
                continue
            }
            let table = try AdjustTable(adjustment)
            steps.append(Step(kind: table.kind.rawValue, values: table.gains, n: UInt32(max(table.values.count - 1, 0)),
                              outer: UInt32(min(table.below.count, table.above.count)), offset: UInt32(tables.count)))
            tables += table.values + table.below + table.above
            adjustTables.append(table)
        }
        (self.steps, self.tables, self.adjustTables) = (steps, tables, adjustTables)
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// One premultiplied pixel through every step, as the kernel maps it: alpha 0 gives zeros, else
    /// unpremultiply, each step on the straight color, premultiply; alpha unchanged.
    public func map(_ p: RGBA) -> RGBA {
        guard p.a != 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        var c = SIMD3(p.r, p.g, p.b) / p.a
        for (step, table) in zip(steps, adjustTables) {
            if step.kind == Self.matrix {
                let at = Int(step.offset)
                let m = Array(tables[at..<(at + 10)])
                c = Self.mixed(c, rows: m, lightness: m[9])
                continue
            }
            guard let table else {
                c = Self.shifted(c, by: step.values)
                continue
            }
            switch table.kind {
            case .gains: c *= table.gains
            case .luma:
                let w = AdjustTable.lumaWeights
                c *= table.apply(w.x * c.x + w.y * c.y + w.z * c.z)
            case .channel: c = SIMD3(table.apply(c.x), table.apply(c.y), table.apply(c.z))
            }
        }
        c *= p.a
        return RGBA(r: c.x, g: c.y, b: c.z, a: p.a)
    }

    /// The straight linear color `c` through a `matrix` operation: rows, clamp below 0, lightness mix.
    static func mixed(_ c: SIMD3<Float>, rows m: [Float], lightness l: Float) -> SIMD3<Float> {
        func light(_ v: Float) -> Float {
            let c = max(v, 0)
            return l >= 0 ? c + (1 - c) * l : c * (1 + l)
        }
        return SIMD3(light(m[0] * c.x + m[1] * c.y + m[2] * c.z), light(m[3] * c.x + m[4] * c.y + m[5] * c.z),
                     light(m[6] * c.x + m[7] * c.y + m[8] * c.z))
    }

    /// The straight color `c` shifted by hue (degrees), saturation and lightness (percent) as standard HSL on
    /// its sRGB-encoded values clamped to 0...1, then decoded: CoreRaster's `hueSaturation`, in Float.
    static func shifted(_ c: SIMD3<Float>, by shift: SIMD3<Float>) -> SIMD3<Float> {
        func encode(_ v: Float) -> Float {
            let a = abs(v)
            let e = a <= 0.0031308 ? a * 12.92 : 1.055 * powf(a, 1 / 2.4) - 0.055
            return min(max(v < 0 ? -e : e, 0), 1)
        }
        func decode(_ v: Float) -> Float {
            let a = abs(v)
            let l = a <= 0.04045 ? a / 12.92 : powf((a + 0.055) / 1.055, 2.4)
            return v < 0 ? -l : l
        }
        let e = SIMD3(encode(c.x), encode(c.y), encode(c.z))
        let hi = e.max(), lo = e.min(), d = hi - lo
        var l = (hi + lo) / 2, h: Float = 0, s: Float = 0
        if d > 0 {
            let sector = hi == e.x ? (e.y - e.z) / d : hi == e.y ? (e.z - e.x) / d + 2 : (e.x - e.y) / d + 4
            h = fmodf(sector * 60 + 360, 360)
            s = d / (1 - abs(2 * l - 1))
        }
        h = fmodf(h + shift.x + 360, 360)
        s = min(1, max(0, s * (1 + shift.y / 100)))
        l = shift.z >= 0 ? l + (1 - l) * shift.z / 100 : l * (1 + shift.z / 100)
        let chroma = (1 - abs(2 * l - 1)) * s, hp = h / 60
        let x = chroma * (1 - abs(fmodf(hp, 2) - 1))
        let rgb: SIMD3<Float> = switch Int(hp) % 6 {
        case 0: [chroma, x, 0]
        case 1: [x, chroma, 0]
        case 2: [0, chroma, x]
        case 3: [0, x, chroma]
        case 4: [x, 0, chroma]
        default: [chroma, 0, x]
        }
        let v = rgb + SIMD3(repeating: l - chroma / 2)
        return SIMD3(decode(v.x), decode(v.y), decode(v.z))
    }
}
