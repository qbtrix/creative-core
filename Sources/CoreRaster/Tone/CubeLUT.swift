// CubeLUT.swift: the `.cube` 3D LUT text reader, the tone-pack contract slice
// (docs/blueprints/core/features/tone-pack.md), from the published `.cube`
// format: `#` comment lines, then keyword lines (`TITLE`, `LUT_3D_SIZE n`,
// `DOMAIN_MIN r g b`, `DOMAIN_MAX r g b`), then n³ lines of three numbers,
// red index fastest. It reads untrusted text: every damage throws
// `RasterError.invalid`, and the table never grows past n³ entries.
public enum CubeLUT {
    /// The LUT a `.cube` text describes. Accepts LUT_3D_SIZE 2...65 (once,
    /// before the table) and DOMAIN_MIN 0 0 0 / DOMAIN_MAX 1 1 1 only; throws
    /// `RasterError.invalid` for any other keyword, a keyword after the table
    /// starts, a line that is not three finite numbers, or a table that does
    /// not hold exactly n³ entries.
    public static func parse(_ text: String) throws -> ColorLUT {
        var size: Int?
        var table: [SIMD3<Float>] = []
        for (number, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard let head = tokens.first, !head.hasPrefix("#") else { continue }
            func fail(_ why: String) -> RasterError { RasterError.invalid(".cube line \(number + 1): \(why)") }
            if Float(head) != nil {
                guard let n = size else { throw fail("table before LUT_3D_SIZE") }
                guard table.count < n * n * n else { throw fail("more than \(n * n * n) entries") }
                guard let entry = triple(tokens) else { throw fail("needs three finite numbers") }
                table.append(entry)
                continue
            }
            guard table.isEmpty else { throw fail("keyword \(head) after the table") }
            switch head {
            case "TITLE":
                continue
            case "LUT_3D_SIZE":
                guard size == nil else { throw fail("LUT_3D_SIZE given twice") }
                guard tokens.count == 2, let n = Int(tokens[1]) else {
                    throw fail("LUT_3D_SIZE needs one integer, got '\(tokens.dropFirst().joined(separator: " "))'")
                }
                guard (2...65).contains(n) else { throw fail("LUT_3D_SIZE \(n) is outside 2...65") }
                size = n
                table.reserveCapacity(n * n * n)
            case "DOMAIN_MIN", "DOMAIN_MAX":
                let bound: Float = head == "DOMAIN_MIN" ? 0 : 1
                guard triple(tokens) == SIMD3(repeating: bound) else {
                    throw fail("\(head) must be \(bound) \(bound) \(bound)")
                }
            default:
                throw fail("unsupported keyword \(head)")
            }
        }
        guard let n = size else { throw RasterError.invalid(".cube has no LUT_3D_SIZE") }
        return try ColorLUT(size: n, table: table)
    }

    /// The three finite numbers after a line's first token (or of the whole
    /// line when it starts with a number); nil when the line has another shape.
    private static func triple(_ tokens: [Substring]) -> SIMD3<Float>? {
        let values = (tokens.first.flatMap { Float($0) } == nil ? tokens.dropFirst() : tokens[...]).map { Float($0) }
        guard values.count == 3, let r = values[0], let g = values[1], let b = values[2],
              r.isFinite, g.isFinite, b.isFinite else { return nil }
        return SIMD3(r, g, b)
    }
}
