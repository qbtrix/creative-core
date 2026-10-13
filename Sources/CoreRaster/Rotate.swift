// Rotate.swift: turning a PixelBuffer clockwise by any angle, and the largest
// upright crop inside the turned image (a photo's straighten). Multiples of 90
// degrees go through `rotated(_:)` and stay exact. Other angles sample each
// output pixel with the `Taps` of `Resample.swift` (the `ResampleFilter`
// kernels, clamp-to-edge) on premultiplied components, then scale it by its
// coverage: a one-pixel linear ramp across the image's edge, so the border is
// anti-aliased and the uncovered corners are transparent. A pixel whose center
// lands at least half a pixel inside the edge has coverage 1, and
// `straightenCrop` keeps every pixel center that far in. Invariants: the
// angle is finite, every size goes through `validatedSize`, and every output
// component is finite.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// This image turned clockwise by `degrees` about its center, sampled with
    /// `filter`. The result is just big enough to hold the turned image, and
    /// the corners it uncovers are transparent. Throws `RasterError.invalid`
    /// for a non-finite angle, a result size `validatedSize` rejects, or a
    /// lanczos3 overshoot that leaves a component that is not finite.
    public func rotated(degrees: Double, filter: ResampleFilter) throws -> PixelBuffer {
        let turn = try Self.Turn(degrees: degrees)
        switch turn.quarter {
        case 0: return self
        case 1: return rotated(.degrees90)
        case 2: return rotated(.degrees180)
        case 3: return rotated(.degrees270)
        default: break
        }
        let (newWidth, newHeight) = turn.boundingSize(width: width, height: height)
        _ = try Self.validatedSize(width: newWidth, height: newHeight)
        let input = components
        let c = Self.channels
        var output = [Float](repeating: 0, count: newWidth * newHeight * c)
        var sum = [Double](repeating: 0, count: c)
        for ny in 0..<newHeight {
            for nx in 0..<newWidth {
                // Inverse map: the output pixel center turned back by the angle,
                // in input coordinates where pixel j is at j.
                let dx = Double(nx) + 0.5 - Double(newWidth) / 2
                let dy = Double(ny) + 0.5 - Double(newHeight) / 2
                let sx = dx * turn.cosine + dy * turn.sine + Double(width) / 2 - 0.5
                let sy = dy * turn.cosine - dx * turn.sine + Double(height) / 2 - 0.5
                let coverage = Self.coverage(sx, length: width) * Self.coverage(sy, length: height)
                guard coverage > 0 else { continue }
                let xTaps = Taps(center: sx, stretch: 1, length: width, filter: filter)
                let yTaps = Taps(center: sy, stretch: 1, length: height, filter: filter)
                for k in 0..<c { sum[k] = 0 }
                for (j, wy) in zip(yTaps.indices, yTaps.weights) {
                    for (i, wx) in zip(xTaps.indices, xTaps.weights) {
                        let w = wx * wy
                        let s = (j * width + i) * c
                        for k in 0..<c { sum[k] += w * Double(input[s + k]) }
                    }
                }
                let d = (ny * newWidth + nx) * c
                for k in 0..<c { output[d + k] = Float(sum[k] * coverage) }
            }
        }
        guard output.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("rotate by \(degrees) degrees: a component overflowed")
        }
        return PixelBuffer(checkedWidth: newWidth, height: newHeight, storage: output)
    }

    /// The largest rectangle with about the `width:height` ratio, centered in
    /// a `width x height` image turned by `degrees` (see
    /// `rotated(degrees:filter:)`), that holds only fully opaque image pixels.
    /// Coordinates are in the turned result's pixels, rounded inward; the
    /// shorter side is floored and the longer one follows the ratio, so the
    /// ratio holds within one pixel. A multiple of 90 degrees returns the whole
    /// turned image. Throws `RasterError.invalid` for a non-finite angle, a
    /// size `validatedSize` rejects, or an image too small to hold any crop.
    public static func straightenCrop(
        width: Int, height: Int, degrees: Double
    ) throws -> (x: Int, y: Int, width: Int, height: Int) {
        _ = try validatedSize(width: width, height: height)
        let turn = try Turn(degrees: degrees)
        let (outWidth, outHeight) = turn.boundingSize(width: width, height: height)
        if turn.quarter != nil { return (0, 0, outWidth, outHeight) }
        // A centered rectangle k*width x k*height, nudged off center by up to
        // half a pixel per axis when rounded, keeps its corners' projections
        // on the image's axes within the opaque area, (width - 1) x (height - 1).
        let (w, h) = (Double(width), Double(height))
        let (c, s) = turn.spread
        let k = min((w - 1 - c - s) / (w * c + h * s), (h - 1 - c - s) / (w * s + h * c))
        var cropWidth: Int, cropHeight: Int
        if width >= height {
            cropHeight = Int(max(k * h, 0).rounded(.down))
            cropWidth = cropHeight * width / height
        } else {
            cropWidth = Int(max(k * w, 0).rounded(.down))
            cropHeight = cropWidth * height / width
        }
        guard cropWidth >= 1, cropHeight >= 1 else {
            throw RasterError.invalid(
                "straighten \(width)x\(height) by \(degrees) degrees: no opaque crop fits")
        }
        return ((outWidth - cropWidth) / 2, (outHeight - cropHeight) / 2, cropWidth, cropHeight)
    }

    /// How much of a pixel centered at input coordinate `p` lies on a line of
    /// `length` pixels, which spans -0.5...length - 0.5: 1 from half a pixel
    /// inside the edge, 0 from half a pixel outside, linear between.
    private static func coverage(_ p: Double, length: Int) -> Double {
        min(max(min(p + 1, Double(length) - p), 0), 1)
    }

    /// A finite clockwise angle reduced to 0..<360 degrees.
    private struct Turn {
        /// 0...3 when the angle is that many quarter turns, else nil.
        let quarter: Int?
        /// The cosine and sine of the angle.
        let cosine: Double
        let sine: Double

        init(degrees: Double) throws {
            guard degrees.isFinite else {
                throw RasterError.invalid("rotate by \(degrees) degrees: the angle must be finite")
            }
            var reduced = degrees.truncatingRemainder(dividingBy: 360)
            if reduced < 0 { reduced += 360 }
            if reduced >= 360 { reduced = 0 }
            quarter = reduced.truncatingRemainder(dividingBy: 90) == 0 ? Int(reduced / 90) : nil
            let radians = reduced * Double.pi / 180
            (cosine, sine) = (cos(radians), sin(radians))
        }

        /// The absolute cosine and sine, which fix the turned image's bounds.
        var spread: (cos: Double, sin: Double) { (abs(cosine), abs(sine)) }

        /// The size of the smallest pixel grid that holds a `width x height`
        /// image turned by this angle: ceil(w |cos| + h |sin|) by
        /// ceil(w |sin| + h |cos|); swapped or kept exactly for quarter turns.
        func boundingSize(width: Int, height: Int) -> (width: Int, height: Int) {
            if let quarter { return quarter % 2 == 0 ? (width, height) : (height, width) }
            let (c, s) = spread
            let (w, h) = (Double(width), Double(height))
            return (Int((w * c + h * s).rounded(.up)), Int((w * s + h * c).rounded(.up)))
        }
    }
}
