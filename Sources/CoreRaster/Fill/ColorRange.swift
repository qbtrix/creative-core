// ColorRange.swift: colour sampling and the colour-range mask behind select
// by colour range (fill-tools). `sampledColor` is the mean of a small box,
// clipped at the buffer's edge; `colorRangeMask` covers each pixel by
// `1 − smoothstep(0, f, d)` of its OKLab distance `d` from the colour.
// Invariants: arguments are checked before any pixel is read; the distance is
// the Euclidean OKLab distance of the straight colours with the alpha
// difference as a fourth axis, in Double through CoreColor; coverage stays in
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
    /// - Throws: `RasterError.invalid` for a non-finite colour or a
    ///   fuzziness outside 0...1.
    public func colorRangeMask(around color: RGBA, fuzziness: Float) throws -> Mask {
        guard color.isFinite else {
            throw RasterError.invalid("colour range colour \(color): components must be finite")
        }
        guard (0...1).contains(fuzziness) else {
            throw RasterError.invalid("colour range fuzziness \(fuzziness): must be in 0...1")
        }
        let target = try Self.straightOKLab(color)
        let f = Double(fuzziness)
        var coverage = [Float](repeating: 0, count: width * height)
        // Flat regions repeat one colour, so the last pixel's answer is reused.
        var last: (pixel: RGBA, value: Float)?
        for y in 0..<height {
            for x in 0..<width {
                let c = try pixel(x: x, y: y)
                if let last, last.pixel == c {
                    coverage[y * width + x] = last.value
                    continue
                }
                let q = try Self.straightOKLab(c)
                let (d0, d1, d2) = (q.lab.c0 - target.lab.c0, q.lab.c1 - target.lab.c1, q.lab.c2 - target.lab.c2)
                let da = q.a - target.a
                let d = (d0 * d0 + d1 * d1 + d2 * d2 + da * da).squareRoot()
                let value: Float
                if f == 0 {
                    value = d == 0 ? 1 : 0
                } else {
                    let t = min(max(d / f, 0), 1)
                    value = Float(1 - t * t * (3 - 2 * t))
                }
                coverage[y * width + x] = value
                last = (c, value)
            }
        }
        return Mask(checkedWidth: width, height: height, storage: coverage)
    }

    /// A premultiplied colour as straight OKLab plus alpha. Throws
    /// `RasterError.invalid` when unpremultiplying leaves a non-finite value.
    private static func straightOKLab(_ c: RGBA) throws -> (lab: Color3, a: Double) {
        let s = c.unpremultiplied()
        do {
            let lab = try Color3(Double(s.r), Double(s.g), Double(s.b)).converted(from: .linearSRGB, to: .oklab)
            return (lab, Double(s.a))
        } catch {
            throw RasterError.invalid("colour \(c) has no finite OKLab value")
        }
    }
}
