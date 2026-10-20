// ColorRange.swift: colour sampling and the colour-range mask behind select
// by colour range (fill-tools). `sampledColor` is the mean of a small box,
// clipped at the buffer's edge; `colorRangeMask` covers each pixel by
// `1 − smoothstep(0, f, d)` of its OKLab distance `d` from the colour.
// Invariants: arguments are checked before any pixel is read; the distance is
// `FillColor`'s, shared with flood fill; coverage stays in
// 0...1; fuzziness 0 is a hard mask of exact matches.
import CoreColor

extension PixelBuffer {
    /// The mean colour of the (2r + 1) x (2r + 1) box centred on `p`. Near
    /// the edge the box is clipped: the mean is over its in-bounds pixels.
    ///
    /// - Parameters:
    ///   - p: the centre pixel; must lie inside the buffer, or the call throws.
    ///   - radius: `r`, in 0...2 (0 samples the one pixel, 1 a 3 x 3 box,
    ///     2 a 5 x 5 box); any other value throws.
    /// - Returns: the mean colour, premultiplied like the buffer.
    /// - Throws: `RasterError.invalid` for a point outside the buffer or a
    ///   radius outside 0...2.
    public func sampledColor(at p: (x: Int, y: Int), radius: Int) throws -> RGBA {
        guard (0...2).contains(radius) else {
            throw RasterError.invalid("sample radius \(radius): must be in 0...2")
        }
        guard (0..<width).contains(p.x), (0..<height).contains(p.y) else {
            throw RasterError.invalid("sample point (\(p.x), \(p.y)) is outside \(width)x\(height)")
        }
        let span = { (c: Int, size: Int) in max(c - radius, 0)...min(c + radius, size - 1) }
        let xs = span(p.x, width), ys = span(p.y, height)
        var sum = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
        for y in ys {
            for x in xs {
                let c = try pixel(x: x, y: y)
                sum = (sum.r + Double(c.r), sum.g + Double(c.g), sum.b + Double(c.b), sum.a + Double(c.a))
            }
        }
        let n = Double(xs.count * ys.count)
        return RGBA(r: Float(sum.r / n), g: Float(sum.g / n), b: Float(sum.b / n), a: Float(sum.a / n))
    }

    /// A mask covering each pixel by its OKLab distance from `color`, with a
    /// soft falloff: coverage `1 − smoothstep(0, fuzziness, d)`.
    ///
    /// - Parameters:
    ///   - color: the colour to select around, premultiplied like the
    ///     buffer; must be finite.
    ///   - fuzziness: in 0...1; the distance at which coverage falls to 0.
    ///     0 gives a hard mask of exact matches.
    /// - Returns: a mask the size of the buffer, coverage in 0...1.
    /// - Throws: `RasterError.invalid` for a non-finite colour, a fuzziness
    ///   outside 0...1, or a buffer pixel that is not finite once
    ///   unpremultiplied (so has no OKLab value); the message names the pixel.
    public func colorRangeMask(around color: RGBA, fuzziness: Float) throws -> Mask {
        guard color.isFinite else {
            throw RasterError.invalid("colour range colour \(color): components must be finite")
        }
        guard (0...1).contains(fuzziness) else {
            throw RasterError.invalid("colour range fuzziness \(fuzziness): must be in 0...1")
        }
        let target = try FillColor(color, what: "colour range colour")
        let (w, n) = (width, width * height)
        // One linear pass over the raw components. Flat regions repeat one
        // colour, so the last pixel's answer is reused (NaN matches nothing).
        let coverage = try components.withUnsafeBufferPointer { px in
            try [Float](unsafeUninitializedCapacity: n) { cover, count in
                var last = RGBA(r: .nan, g: .nan, b: .nan, a: .nan), lastValue: Float = 0
                for i in 0..<n {
                    let c = RGBA(r: px[4 * i], g: px[4 * i + 1], b: px[4 * i + 2], a: px[4 * i + 3])
                    if c != last {
                        let d = try FillColor(c, what: "colour range: pixel (\(i % w), \(i / w))").distance(to: target)
                        if fuzziness == 0 {
                            lastValue = d == 0 ? 1 : 0
                        } else {
                            lastValue = 1 - Self.smoothstep(0, fuzziness, Float(d))
                        }
                        last = c
                    }
                    cover.initializeElement(at: i, to: lastValue)
                    count = i + 1
                }
            }
        }
        return Mask(checkedWidth: width, height: height, storage: coverage)
    }
}
