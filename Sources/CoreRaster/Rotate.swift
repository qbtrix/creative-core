// Rotate.swift: turning a PixelBuffer clockwise by any angle, and the largest
// upright crop of the turned image that holds only image pixels (straighten).
// A multiple of 90 degrees goes through the exact quarter turn in
// Transform.swift. Any other angle samples the premultiplied pixels with the
// ResampleFilter kernels from Resample.swift, as one 2-D kernel: taps outside
// the image read transparent and the weights are divided by their whole sum,
// so the turned border is anti-aliased and a constant image stays constant
// wherever the kernel lies inside it. `straightenCrop` keeps every kernel of
// the widest filter (lanczos3, radius 3) inside the image, so its pixels are
// exact and opaque for either filter.
// Invariants: the turned size passes `validatedSize`, every output component
// is finite, and the source pixel at the image's center lands on the turned
// image's center.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// This image turned clockwise by `degrees` about its center, in a buffer
    /// just big enough to hold all of it; the uncovered corners are
    /// transparent. A multiple of 90 is the exact quarter turn. Throws
    /// `RasterError.invalid` for a non-finite angle, a turned size
    /// `validatedSize` rejects, or a lanczos3 overshoot that is not finite.
    public func rotated(degrees: Double, filter: ResampleFilter) throws -> PixelBuffer {
        let turn = try Self.turn(degrees)
        switch turn.quarters {
        case 0?: return self
        case 1?: return rotated(.degrees90)
        case 2?: return rotated(.degrees180)
        case 3?: return rotated(.degrees270)
        default: break
        }
        let (newWidth, newHeight) = try Self.turnedSize(width: width, height: height, turn)
        let (c, s) = (turn.cos, turn.sin)
        let r = filter.radius
        let input = components
        let channels = Self.channels
        var output = [Float](repeating: 0, count: newWidth * newHeight * channels)
        // Reused for every pixel: the kernel weights along x and y (at most 2r+1 taps each).
        let maxTaps = Int(2 * r) + 2
        var wx = [Double](repeating: 0, count: maxTaps), wy = wx
        var sum = [Double](repeating: 0, count: channels)
        let (sourceX, sourceY) = (Double(width - 1) / 2, Double(height - 1) / 2)
        // ponytail: one thread, O(pixels x taps^2); split rows across tasks if Apply on huge images is slow.
        for oy in 0..<newHeight {
            let dy = Double(oy) + 0.5 - Double(newHeight) / 2
            for ox in 0..<newWidth {
                let dx = Double(ox) + 0.5 - Double(newWidth) / 2
                // The source point under this pixel's center: the turn undone.
                let sx = dx * c + dy * s + sourceX
                let sy = -dx * s + dy * c + sourceY
                let x0 = Int((sx - r).rounded(.up)), x1 = Int((sx + r).rounded(.down))
                let y0 = Int((sy - r).rounded(.up)), y1 = Int((sy + r).rounded(.down))
                guard x1 >= 0, y1 >= 0, x0 < width, y0 < height else { continue }
                var totalX = 0.0, totalY = 0.0
                for i in x0...x1 { wx[i - x0] = filter.weight(Double(i) - sx); totalX += wx[i - x0] }
                for j in y0...y1 { wy[j - y0] = filter.weight(Double(j) - sy); totalY += wy[j - y0] }
                let total = totalX * totalY
                guard total != 0 else { continue }
                for k in 0..<channels { sum[k] = 0 }
                for j in max(y0, 0)...min(y1, height - 1) {
                    let rowWeight = wy[j - y0]
                    guard rowWeight != 0 else { continue }
                    for i in max(x0, 0)...min(x1, width - 1) {
                        let w = rowWeight * wx[i - x0]
                        let base = (j * width + i) * channels
                        for k in 0..<channels { sum[k] += w * Double(input[base + k]) }
                    }
                }
                let base = (oy * newWidth + ox) * channels
                for k in 0..<channels { output[base + k] = Float(sum[k] / total) }
            }
        }
        guard output.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("rotate by \(degrees) degrees: a component overflowed")
        }
        return PixelBuffer(checkedWidth: newWidth, height: newHeight, storage: output)
    }

    /// The largest rectangle with the `width x height` image's aspect ratio,
    /// centered in the image turned by `degrees` (see `rotated(degrees:filter:)`),
    /// whose pixels are all exact, opaque image pixels with either filter. In
    /// the turned image's pixels, rounded inward; the ratio holds within one
    /// pixel. At least 1 x 1, even for an image too thin to hold one such
    /// pixel. Throws `RasterError.invalid` for a size `validatedSize` rejects or
    /// a non-finite angle.
    public static func straightenCrop(
        width: Int, height: Int, degrees: Double
    ) throws -> (x: Int, y: Int, width: Int, height: Int) {
        _ = try validatedSize(width: width, height: height)
        let turn = try turn(degrees)
        let (turnedWidth, turnedHeight) = try turnedSize(width: width, height: height, turn)
        let (w, h, c, s) = (Double(width), Double(height), abs(turn.cos), abs(turn.sin))
        // A sample reads taps within the radius of it, so its pixel center
        // must sit radius - 1 inside the outer pixel centers on every side:
        // 2 x radius - 1 pixels in all. A quarter turn reads no kernel.
        let margin = turn.quarters == nil ? 2 * ResampleFilter.lanczos3.radius - 1 : 0
        let scale = max(0, min((w - margin) / (w * c + h * s), (h - margin) / (w * s + h * c)))
        let cropHeight = max(Int((scale * h).rounded(.down)), 1)
        let cropWidth = max(min(Int((scale * w).rounded(.down)), Int((Double(cropHeight) * w / h).rounded())), 1)
        return ((turnedWidth - cropWidth) / 2, (turnedHeight - cropHeight) / 2, cropWidth, cropHeight)
    }

    /// An angle as its cosine and sine, exact for a multiple of 90, which is
    /// also given as whole clockwise quarter turns 0...3. Throws for NaN and
    /// infinity.
    private static func turn(_ degrees: Double) throws -> (cos: Double, sin: Double, quarters: Int?) {
        guard degrees.isFinite else {
            throw RasterError.invalid("rotate by \(degrees) degrees: the angle must be finite")
        }
        let reduced = degrees.truncatingRemainder(dividingBy: 360)
        let quarters = reduced / 90
        if quarters == quarters.rounded() {
            switch (Int(quarters) + 4) % 4 {
            case 1: return (0, 1, 1)
            case 2: return (-1, 0, 2)
            case 3: return (0, -1, 3)
            default: return (1, 0, 0)
            }
        }
        let radians = reduced * Double.pi / 180
        return (cos(radians), sin(radians), nil)
    }

    /// The size that holds a `width x height` image turned by `turn`: its
    /// rotated bounds, rounded up.
    private static func turnedSize(
        width: Int, height: Int, _ turn: (cos: Double, sin: Double, quarters: Int?)
    ) throws -> (Int, Int) {
        let (w, h, c, s) = (Double(width), Double(height), abs(turn.cos), abs(turn.sin))
        let size = (Int((w * c + h * s).rounded(.up)), Int((w * s + h * c).rounded(.up)))
        _ = try validatedSize(width: size.0, height: size.1)
        return size
    }
}
