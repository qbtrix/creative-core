// ProfileConvert.swift: converting a buffer from one colour profile to
// another (Convert to Profile, as opposed to assigning, which keeps the
// numbers). A PixelBuffer is linear light, premultiplied, so each pixel is
// unpremultiplied, converted and premultiplied again. A side whose curves
// decode as the buffer does (every curve gamma 1, or the built-in sRGB curve,
// which is CoreColor's TransferCurve rounded to the ICC grid) gets no curve
// pass, so between two such profiles (the built-ins) only the transform's
// matrix part applies. Any other side gets a curve pass: a source's numbers
// are encoded with TransferCurve and decoded with its own curves before the
// matrix; a target's are encoded with its own curves and decoded with
// TransferCurve after it. Invariants a reader must keep: alpha never
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
    /// This buffer's colours, tagged with `source`, converted to `target`.
    ///
    /// Input contract: the pixels are premultiplied linear light as the codecs
    /// produce them, meaning the file's numbers decoded with CoreColor's sRGB
    /// `TransferCurve` (the way the PSD reader decodes them), whatever
    /// profile the file carries. A side whose curves are all gamma 1, or are the
    /// built-in sRGB curve, needs no curve pass, so between such profiles only
    /// the matrix applies. For any other `source` the `TransferCurve` decode is
    /// undone and `source`'s own curves decode instead, before the matrix; for
    /// any other `target`, `target`'s curves encode and `TransferCurve` decodes
    /// again, after it. So a truly linear buffer tagged with, say, a gamma-2.2
    /// profile is not converted matrix-only: tag it with that profile's
    /// gamma-1 twin instead.
    ///
    /// Output is premultiplied linear light in the same convention. Alpha is
    /// unchanged, alpha 0 pixels are copied as they are, and out-of-gamut values
    /// stay unclamped. For example
    /// `try layered.composite?.converted(from: layered.profile ?? .sRGB, to: .linearSRGB)`.
    /// Throws `RasterError.invalid` when the profiles cannot form a transform or
    /// a converted component is not finite.
    public func converted(from source: ColorProfile, to target: ColorProfile) throws(RasterError) -> PixelBuffer {
        let asked = (source, target)
        let transform = try Self.transform(from: source, to: target, for: asked)
        // Curve-only passes (same primaries, so the matrix is the identity), nil on a side that decodes as the buffer.
        let decodeIn = Self.decodesAsBuffer(source) ? nil : try Self.transform(from: source, to: Self.linear(source), for: asked)
        let encodeOut = Self.decodesAsBuffer(target) ? nil : try Self.transform(from: Self.linear(target), to: target, for: asked)
        @inline(never) func convert(_ c: Color3) -> Color3 {
            var v = c
            if let decodeIn {
                v = decodeIn.apply(Color3(TransferCurve.encode(v.c0), TransferCurve.encode(v.c1), TransferCurve.encode(v.c2)))
            }
            v = transform.applyLinear(v)
            if let encodeOut {
                v = encodeOut.apply(v)
                v = Color3(TransferCurve.decode(v.c0), TransferCurve.decode(v.c1), TransferCurve.decode(v.c2))
            }
            return v
        }
        // The fast path: each curve pass through its CurveTables, the matrix with hoisted coefficients (the
        // same products, in the same order, as applyLinear), and convert(_:) for any pixel a table does not cover.
        let inTables = decodeIn.flatMap { t in source.isGray ? nil : CurveTables { x in
            let e = TransferCurve.encode(x)
            return t.apply(Color3(e, e, e))
        } }
        let outTables = encodeOut.flatMap { t in target.isGray ? nil : CurveTables { x in
            let v = t.apply(Color3(x, x, x))
            return Color3(TransferCurve.decode(v.c0), TransferCurve.decode(v.c1), TransferCurve.decode(v.c2))
        } }
        let exactOnly = (decodeIn != nil && inTables == nil) || (encodeOut != nil && outTables == nil)
        let (x, y, z) = (transform.applyLinear(Color3(1, 0, 0)), transform.applyLinear(Color3(0, 1, 0)),
                         transform.applyLinear(Color3(0, 0, 1)))
        let (m0, m1, m2, m3, m4, m5, m6, m7, m8) = (x.c0, y.c0, z.c0, x.c1, y.c1, z.c1, x.c2, y.c2, z.c2)
        let (n, channels, hasIn, hasOut) = (CurveTables.stride, Self.channels, inTables != nil, outTables != nil)
        // One pass from the source components into fresh storage: no copy first, and every element written.
        var notFinite: Int?
        let storage = components.withUnsafeBufferPointer { s in
            (inTables?.table ?? []).withUnsafeBufferPointer { ti in
                (outTables?.table ?? []).withUnsafeBufferPointer { to in
                    [Float](unsafeUninitializedCapacity: s.count) { p, initialized in
                        for i in stride(from: 0, to: s.count, by: channels) {
                            let a = s[i + 3]
                            p[i + 3] = a
                            guard a != 0 else {
                                (p[i], p[i + 1], p[i + 2]) = (s[i], s[i + 1], s[i + 2])
                                continue
                            }
                            let alpha = Double(a), inverse = 1 / alpha
                            let straight = (Double(s[i]) * inverse, Double(s[i + 1]) * inverse, Double(s[i + 2]) * inverse)
                            var (r, g, b) = straight
                            var covered = !exactOnly
                            if covered, hasIn {
                                covered = CurveTables.covers(r) && CurveTables.covers(g) && CurveTables.covers(b)
                                if covered {
                                    (r, g, b) = (CurveTables.lookup(ti, 0, r), CurveTables.lookup(ti, n, g),
                                                 CurveTables.lookup(ti, 2 * n, b))
                                }
                            }
                            var mapped = (m0 * r + m1 * g + m2 * b, m3 * r + m4 * g + m5 * b, m6 * r + m7 * g + m8 * b)
                            if covered, hasOut {
                                covered = CurveTables.covers(mapped.0) && CurveTables.covers(mapped.1)
                                    && CurveTables.covers(mapped.2)
                                if covered {
                                    mapped = (CurveTables.lookup(to, 0, mapped.0), CurveTables.lookup(to, n, mapped.1),
                                              CurveTables.lookup(to, 2 * n, mapped.2))
                                }
                            }
                            if !covered {
                                let v = convert(Color3(straight.0, straight.1, straight.2))
                                mapped = (v.c0, v.c1, v.c2)
                            }
                            let rgb = (Float(mapped.0 * alpha), Float(mapped.1 * alpha), Float(mapped.2 * alpha))
                            if !(rgb.0.isFinite && rgb.1.isFinite && rgb.2.isFinite), notFinite == nil { notFinite = i / channels }
                            (p[i], p[i + 1], p[i + 2]) = rgb
                        }
                        initialized = s.count
                    }
                }
            }
        }
        if let n = notFinite {
            throw RasterError.invalid("converted pixel at (\(n % width), \(n / width)) is not finite")
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: storage)
    }

    /// True when `profile`'s curves decode a value the way a PixelBuffer already
    /// holds it, so converting needs no curve pass on that side: every curve is
    /// gamma 1 (linear light), or the curves are the built-in sRGB curve, which
    /// stands for CoreColor's TransferCurve rounded to the ICC grid (within 2^-16).
    private static func decodesAsBuffer(_ profile: ColorProfile) -> Bool {
        profile.curves.allSatisfy { $0 == .gamma(1) } || profile.curves == ColorProfile.sRGB.curves
    }

    /// `profile` with every curve gamma 1: the same primaries, read as linear light.
    private static func linear(_ profile: ColorProfile) -> ColorProfile {
        var twin = profile
        twin.curves = Array(repeating: .gamma(1), count: profile.curves.count)
        return twin
    }

    /// The CoreColor transform from `a` to `b`, its error rethrown as a plain
    /// RasterError naming the conversion asked for.
    private static func transform(from a: ColorProfile, to b: ColorProfile,
                                  for asked: (ColorProfile, ColorProfile)) throws(RasterError) -> ProfileTransform {
        do throws(ColorError) {
            return try ProfileTransform(from: a, to: b)
        } catch {
            switch error {
            case .invalid(let why): throw RasterError.invalid("convert \(asked.0.name) to \(asked.1.name): \(why)")
            }
        }
    }
}
