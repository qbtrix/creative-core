// BlurFamily.swift: box blur and motion blur on premultiplied components, so
// colour never bleeds in from transparent pixels. Box blur is three separable
// running-sum passes per axis (the result approaches a Gaussian); a fractional
// radius weights the two outer taps by its fraction. Motion blur averages
// ceil(distance) + 1 bilinear samples one step (distance / ceil(distance), at
// most 1 px) apart along the angle, starting on a whole pixel, so an integer
// distance on an axis lands on whole pixels and spreads over distance + 1 of
// them. Both read past the edge as the nearest edge pixel. Invariants: radius
// and distance are finite and in 0...1,000 (0 is identity), degrees finite;
// every weight set sums to 1, so the output is a convex mix of the input.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// The largest box radius or motion distance, in pixels.
    static let maxBlurReach = 1_000.0

    /// This buffer box-blurred by `radius` pixels: three box passes along
    /// each axis. Radius 0 returns the buffer unchanged. Throws
    /// `RasterError.invalid` for a radius that is not finite or not in 0...1,000.
    public func boxBlurred(radius: Double) throws -> PixelBuffer {
        try Self.checkReach(radius, "box blur radius")
        guard radius > 0 else { return self }
        let c = Self.channels
        var data = components
        for _ in 0..<3 {
            data = Self.boxPass(data, lines: height, length: width, along: c, across: width * c, radius: radius)
            data = Self.boxPass(data, lines: width, length: height, along: width * c, across: c, radius: radius)
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: data)
    }

    /// This buffer blurred `distance` pixels along `degrees` (0 is +x, 90 is
    /// +y). Distance 0 returns the buffer unchanged. Throws
    /// `RasterError.invalid` for a non-finite angle, or a distance that is not
    /// finite or not in 0...1,000.
    public func motionBlurred(degrees: Double, distance: Double) throws -> PixelBuffer {
        guard degrees.isFinite else {
            throw RasterError.invalid("motion blur angle \(degrees): must be finite")
        }
        try Self.checkReach(distance, "motion blur distance")
        guard distance > 0 else { return self }
        let radians = degrees * .pi / 180
        // Snap the rounding residue of cos and sin at right angles to 0, so an
        // axis-aligned blur never leaks a 1e-16 weight into the next row.
        let ux = abs(cos(radians)) < 1e-12 ? 0 : cos(radians)
        let uy = abs(sin(radians)) < 1e-12 ? 0 : sin(radians)
        let steps = distance.rounded(.up)
        let count = Int(steps) + 1
        let step = distance / steps
        let start = (-distance / 2).rounded(.down)
        let src = components, c = Self.channels
        var out = [Float](repeating: 0, count: src.count)
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        /// Adds pixel (`px`, `py`), clamped to the nearest edge pixel, at weight `w`.
        func add(_ px: Int, _ py: Int, _ w: Double) {
            guard w > 0 else { return }
            let j = (min(max(py, 0), height - 1) * width + min(max(px, 0), width - 1)) * c
            r += w * Double(src[j]); g += w * Double(src[j + 1]); b += w * Double(src[j + 2]); a += w * Double(src[j + 3])
        }
        for y in 0..<height {
            for x in 0..<width {
                r = 0; g = 0; b = 0; a = 0
                for i in 0..<count {
                    // Bilinear: the sample point is within 1,001 px of the
                    // buffer, so its floor converts to Int without overflow.
                    let t = start + Double(i) * step
                    let sx = Double(x) + t * ux, sy = Double(y) + t * uy
                    let fx = sx.rounded(.down), fy = sy.rounded(.down)
                    let wx = sx - fx, wy = sy - fy, x0 = Int(fx), y0 = Int(fy)
                    add(x0, y0, (1 - wx) * (1 - wy)); add(x0 + 1, y0, wx * (1 - wy))
                    add(x0, y0 + 1, (1 - wx) * wy); add(x0 + 1, y0 + 1, wx * wy)
                }
                let k = 1 / Double(count), o = (y * width + x) * c
                out[o] = Float(r * k); out[o + 1] = Float(g * k); out[o + 2] = Float(b * k); out[o + 3] = Float(a * k)
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// Throws unless `value` is finite and in 0...`maxBlurReach`.
    private static func checkReach(_ value: Double, _ name: String) throws {
        guard value.isFinite, value >= 0, value <= maxBlurReach else {
            throw RasterError.invalid("\(name) \(value): must be finite and in 0...\(Int(maxBlurReach))")
        }
    }

    /// One box pass over `lines` lines of `length` pixels: each output pixel
    /// is the mean over the 2 `radius` + 1 px window centred on it, the two
    /// outer taps weighted by the fraction of `radius`, from running (prefix)
    /// sums in Double. `along` and `across` are the storage steps between
    /// neighbouring pixels of a line and between lines.
    private static func boxPass(
        _ input: [Float], lines: Int, length: Int, along: Int, across: Int, radius: Double
    ) -> [Float] {
        let c = channels, n = Int(radius), fraction = radius - Double(n)
        let scale = 1 / (2 * radius + 1)
        var output = input
        var prefix = [Double](repeating: 0, count: (length + 1) * c)
        for line in 0..<lines {
            let base = line * across
            for i in 0..<length {
                for k in 0..<c { prefix[(i + 1) * c + k] = prefix[i * c + k] + Double(input[base + i * along + k]) }
            }
            /// The value of channel `k` at `j`, clamped to the line's ends.
            func value(_ j: Int, _ k: Int) -> Double { Double(input[base + min(max(j, 0), length - 1) * along + k]) }
            /// The sum of channel `k` over pixels 0..<`j`, extended past
            /// both ends by repeating the end pixel.
            func running(_ j: Int, _ k: Int) -> Double {
                if j <= 0 { return Double(j) * value(0, k) }
                if j >= length { return prefix[length * c + k] + Double(j - length) * value(length - 1, k) }
                return prefix[j * c + k]
            }
            for i in 0..<length {
                for k in 0..<c {
                    let inner = running(i + n + 1, k) - running(i - n, k)
                    let outer = fraction * (value(i - n - 1, k) + value(i + n + 1, k))
                    output[base + i * along + k] = Float((inner + outer) * scale)
                }
            }
        }
        return output
    }
}
