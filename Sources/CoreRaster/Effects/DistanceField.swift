// DistanceField.swift: the exact Euclidean distance, in pixels between pixel
// centres, from each pixel to the shape (the pixels whose alpha is >= level)
// and to its complement. An exact squared distance transform: one 1D
// lower-envelope pass down every column, then one along every row, in Double,
// so squared distances are whole numbers and the square root is exact to
// Float. Each pass also carries the index of the nearest site, which strokes
// use. Beyond the buffer's edge reads as transparent: it is outside the
// shape, so `inside` counts the ring of pixels just past the edge, and
// `outside` never does. Invariants: level is finite; a shape with no pixels
// has `outside` +infinity everywhere; lookups off the buffer never trap.

/// Distances from a buffer's alpha edge, in pixels.
public struct DistanceField: Sendable {
    /// The source buffer's size; outside(x:y:) and inside(x:y:) are defined on 0..<width × 0..<height.
    public let width: Int, height: Int
    /// Row-major distance to the nearest shape pixel (0 on the shape).
    let outsideField: [Float]
    /// Row-major distance to the nearest non-shape pixel (0 off the shape).
    let insideField: [Float]

    /// The field of `buffer`'s alpha: a pixel is in the shape when its alpha
    /// is >= `level`. Throws `RasterError.invalid` for a level that is not finite.
    public init(alpha buffer: PixelBuffer, level: Float = 0.5) throws {
        guard level.isFinite else {
            throw RasterError.invalid("distance field level \(level): must be finite")
        }
        width = buffer.width
        height = buffer.height
        let src = buffer.components, c = PixelBuffer.channels
        var shape = [Bool](repeating: false, count: width * height)
        for i in shape.indices { shape[i] = src[i * c + 3] >= level }
        outsideField = Self.transform(seeds: shape, width: width, height: height, border: false).distance
        insideField = Self.transform(seeds: shape.map { !$0 }, width: width, height: height, border: true).distance
    }

    /// Distance from (x, y) to the nearest pixel inside the shape: 0 on the
    /// shape, +infinity off the buffer or when the shape is empty.
    public func outside(x: Int, y: Int) -> Float {
        guard x >= 0, x < width, y >= 0, y < height else { return .infinity }
        return outsideField[y * width + x]
    }

    /// Distance from (x, y) to the nearest pixel outside the shape, counting
    /// the transparent ring past the buffer's edge: 0 off the shape or off the buffer.
    public func inside(x: Int, y: Int) -> Float {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return insideField[y * width + x]
    }

    /// The Euclidean distance from every pixel to the nearest `seeds` pixel
    /// (or, with `border`, to the ring just past the edge as well), and that
    /// seed's index (-1 for the ring or for no seed at all).
    static func transform(seeds: [Bool], width: Int, height: Int, border: Bool) -> (distance: [Float], nearest: [Int]) {
        var f = seeds.map { $0 ? 0 : Double.infinity }
        var nearest = seeds.indices.map { seeds[$0] ? $0 : -1 }
        var scratch = Envelope(capacity: max(width, height) + 2)
        envelopePass(&f, &nearest, lines: width, length: height, along: width, across: 1, border: border, &scratch)
        envelopePass(&f, &nearest, lines: height, length: width, along: 1, across: width, border: border, &scratch)
        return (f.map { Float($0.squareRoot()) }, nearest)
    }

    /// Working storage for one line's lower envelope of parabolas.
    struct Envelope {
        var line: [Double], lineNearest: [Int], sites: [Int], siteNearest: [Int], heights: [Double], bounds: [Double]
        init(capacity: Int) {
            line = [Double](repeating: 0, count: capacity)
            lineNearest = [Int](repeating: -1, count: capacity)
            sites = [Int](repeating: 0, count: capacity)
            siteNearest = [Int](repeating: -1, count: capacity)
            heights = [Double](repeating: 0, count: capacity)
            bounds = [Double](repeating: 0, count: capacity + 1)
        }
    }

    /// Replaces every line of `f` (`lines` lines of `length` values, `along`
    /// apart, lines `across` apart) by its 1D squared distance transform,
    /// min over q of (i - q)^2 + f[q]; with `border`, zero sites at -1 and
    /// `length` stand for the transparent ring past the edge. Infinite sites
    /// are skipped, so a line with none stays infinite. `nearest` follows
    /// each value to the seed it came from.
    static func envelopePass(
        _ f: inout [Double], _ nearest: inout [Int], lines: Int, length: Int, along: Int, across: Int, border: Bool, _ e: inout Envelope
    ) {
        let first = border ? -1 : 0, last = border ? length : length - 1
        for l in 0..<lines {
            let base = l * across
            for i in 0..<length { e.line[i] = f[base + i * along]; e.lineNearest[i] = nearest[base + i * along] }
            var k = -1
            for q in first...last {
                let fq = q < 0 || q >= length ? 0 : e.line[q]
                guard fq.isFinite else { continue }
                let dq = Double(q)
                var s = -Double.infinity
                while k >= 0 {
                    let dv = Double(e.sites[k])
                    s = ((fq + dq * dq) - (e.heights[k] + dv * dv)) / (2 * dq - 2 * dv)
                    if s > e.bounds[k] { break }
                    k -= 1
                }
                k += 1
                e.sites[k] = q
                e.heights[k] = fq
                e.siteNearest[k] = q < 0 || q >= length ? -1 : e.lineNearest[q]
                e.bounds[k] = k == 0 ? -.infinity : s
            }
            guard k >= 0 else { continue }
            e.bounds[k + 1] = .infinity
            var j = 0
            for i in 0..<length {
                let di = Double(i)
                while e.bounds[j + 1] < di { j += 1 }
                let d = di - Double(e.sites[j])
                f[base + i * along] = d * d + e.heights[j]
                nearest[base + i * along] = e.siteNearest[j]
            }
        }
    }
}
