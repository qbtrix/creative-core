// ProfileConvert.swift: converting a buffer from one colour profile to
// another (Convert to Profile, as opposed to assigning, which keeps the
// numbers). A PixelBuffer is linear light, premultiplied, so each pixel is
// unpremultiplied, mapped through the transform's linear (matrix) part and
// premultiplied again. Invariants a reader must keep: alpha never changes,
// alpha 0 pixels are copied unchanged (they carry no recoverable colour),
// nothing is clamped (Float32 keeps out-of-gamut values), and a non-finite
// result or a profile CoreColor cannot invert throws RasterError.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor

extension PixelBuffer {
    /// This buffer's colours, numbers in `source`'s linear primaries,
    /// re-expressed in `target`'s. Linear premultiplied in and out; alpha is
    /// unchanged and out-of-gamut values stay unclamped. Throws
    /// `RasterError.invalid` when the profiles cannot form a transform or a
    /// converted component is not finite.
    public func converted(from source: ColorProfile, to target: ColorProfile) throws -> PixelBuffer {
        let transform: ProfileTransform
        do {
            transform = try ProfileTransform(from: source, to: target)
        } catch {
            throw RasterError.invalid("convert \(source.name) to \(target.name): \(error)")
        }
        var storage = components
        for i in stride(from: 0, to: storage.count, by: Self.channels) {
            let a = storage[i + 3]
            guard a != 0 else { continue }
            let alpha = Double(a)
            let straight = Color3(Double(storage[i]) / alpha, Double(storage[i + 1]) / alpha, Double(storage[i + 2]) / alpha)
            let mapped = transform.applyLinear(straight)
            let rgb = (Float(mapped.c0 * alpha), Float(mapped.c1 * alpha), Float(mapped.c2 * alpha))
            guard rgb.0.isFinite, rgb.1.isFinite, rgb.2.isFinite else {
                let n = i / Self.channels
                throw RasterError.invalid("converted pixel at (\(n % width), \(n / width)) is not finite")
            }
            storage[i] = rgb.0
            storage[i + 1] = rgb.1
            storage[i + 2] = rgb.2
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }
}
