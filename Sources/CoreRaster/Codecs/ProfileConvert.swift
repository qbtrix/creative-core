// ProfileConvert.swift: converting a buffer from one colour profile to
// another (Convert to Profile, as opposed to assigning, which keeps the
// numbers). A PixelBuffer is linear light, premultiplied, so each pixel is
// unpremultiplied, converted and premultiplied again. Between two linear
// profiles (every curve gamma 1) only the transform's matrix part applies.
// Otherwise a non-linear side's numbers are read as CoreColor's sRGB-encoded
// form: each value is encoded with TransferCurve, decoded with the source
// profile's own curves, mapped, encoded with the target's curves and decoded
// with TransferCurve again. Invariants a reader must keep: alpha never
// changes, alpha 0 pixels are copied unchanged (they carry no recoverable
// colour), nothing is clamped (Float32 keeps out-of-gamut values), and a
// non-finite result or a profile CoreColor cannot invert throws RasterError.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor

extension PixelBuffer {
    /// This buffer's colours, numbers in `source`'s primaries and curves,
    /// re-expressed in `target`'s. Linear premultiplied in and out; alpha is
    /// unchanged and out-of-gamut values stay unclamped. Throws
    /// `RasterError.invalid` when the profiles cannot form a transform or a
    /// converted component is not finite.
    public func converted(from source: ColorProfile, to target: ColorProfile) throws(RasterError) -> PixelBuffer {
        let transform: ProfileTransform
        do throws(ColorError) {
            transform = try ProfileTransform(from: source, to: target)
        } catch {
            switch error {
            case .invalid(let why): throw RasterError.invalid("convert \(source.name) to \(target.name): \(why)")
            }
        }
        let linearIn = Self.isLinear(source), linearOut = Self.isLinear(target)
        func convert(_ c: Color3) -> Color3 {
            if linearIn && linearOut { return transform.applyLinear(c) }
            let encoded = linearIn ? c : Color3(TransferCurve.encode(c.c0), TransferCurve.encode(c.c1), TransferCurve.encode(c.c2))
            let m = transform.apply(encoded)
            return linearOut ? m : Color3(TransferCurve.decode(m.c0), TransferCurve.decode(m.c1), TransferCurve.decode(m.c2))
        }
        var storage = components
        for i in stride(from: 0, to: storage.count, by: Self.channels) {
            let a = storage[i + 3]
            guard a != 0 else { continue }
            let alpha = Double(a)
            let straight = Color3(Double(storage[i]) / alpha, Double(storage[i + 1]) / alpha, Double(storage[i + 2]) / alpha)
            let mapped = convert(straight)
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

    /// True when every curve of `profile` is gamma 1, so its numbers are linear light already.
    private static func isLinear(_ profile: ColorProfile) -> Bool {
        profile.curves.allSatisfy { $0 == .gamma(1) }
    }
}
