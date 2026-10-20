// FillColor.swift: the one colour distance the fill tools share (fill-tools).
// Flood fill (bucket, wand) and the colour-range mask both measure a pixel by
// the Euclidean OKLab distance of the straight (unpremultiplied) colours, with
// the alpha difference as a fourth axis, in Double through CoreColor. The
// raster gradient shares its CoreColor conversion with errors as RasterError.
import CoreColor

/// A premultiplied colour as straight OKLab plus alpha, ready to measure.
struct FillColor: Sendable {
    let lab: Color3
    let alpha: Double

    /// Unpremultiplies `premultiplied` and converts it to OKLab.
    /// - Throws: `RasterError.invalid` naming `what` and the colour when a
    ///   finite colour overflows Float on unpremultiplying (a component far
    ///   larger than a tiny alpha), or when CoreColor cannot convert it.
    init(_ premultiplied: RGBA, what: @autoclosure () -> String) throws {
        let s = premultiplied.unpremultiplied()
        if premultiplied.isFinite, !s.isFinite {
            throw RasterError.invalid("\(what()) \(premultiplied) overflows when unpremultiplied: its colour"
                                      + " components are too large for its alpha (premultiplied)")
        }
        lab = try Self.converted(Color3(Double(s.r), Double(s.g), Double(s.b)), from: .linearSRGB, to: .oklab,
                                 what: "\(what()) \(premultiplied)")
        alpha = Double(s.a)
    }

    /// CoreColor's conversion of `c` from `source` to `target`, its
    /// `ColorError` mapped to `RasterError.invalid`: "`what` has no
    /// `target` value". FillColor and the raster gradient both use it.
    static func converted(_ c: Color3, from source: ColorSpace, to target: ColorSpace,
                          what: @autoclosure () -> String) throws -> Color3 {
        do { return try c.converted(from: source, to: target) } catch {
            throw RasterError.invalid("\(what()) has no \(target.rawValue) value (\(error))")
        }
    }

    /// The Euclidean OKLab distance to `other`, alpha difference as a fourth axis.
    func distance(to other: FillColor) -> Double {
        let (d0, d1, d2) = (lab.c0 - other.lab.c0, lab.c1 - other.lab.c1, lab.c2 - other.lab.c2)
        let da = alpha - other.alpha
        return (d0 * d0 + d1 * d1 + d2 * d2 + da * da).squareRoot()
    }
}
