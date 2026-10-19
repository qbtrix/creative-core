// FillColor.swift: the one colour distance the fill tools share (fill-tools).
// Flood fill (bucket, wand) and the colour-range mask both measure a pixel by
// the Euclidean OKLab distance of the straight (unpremultiplied) colours, with
// the alpha difference as a fourth axis, in Double through CoreColor.
import CoreColor

/// A premultiplied colour as straight OKLab plus alpha, ready to measure.
struct FillColor: Sendable {
    let lab: Color3
    let alpha: Double

    /// Unpremultiplies `premultiplied` and converts it to OKLab.
    /// - Throws: `RasterError.invalid` naming `what` when a component is, or
    ///   becomes after unpremultiplying, non-finite.
    init(_ premultiplied: RGBA, what: @autoclosure () -> String) throws {
        let s = premultiplied.unpremultiplied()
        do {
            lab = try Color3(Double(s.r), Double(s.g), Double(s.b)).converted(from: .linearSRGB, to: .oklab)
        } catch {
            throw RasterError.invalid("\(what()) is not finite, so it has no OKLab value")
        }
        alpha = Double(s.a)
    }

    /// The Euclidean OKLab distance to `other`, alpha difference as a fourth axis.
    func distance(to other: FillColor) -> Double {
        let (d0, d1, d2) = (lab.c0 - other.lab.c0, lab.c1 - other.lab.c1, lab.c2 - other.lab.c2)
        let da = alpha - other.alpha
        return (d0 * d0 + d1 * d1 + d2 * d2 + da * da).squareRoot()
    }
}
